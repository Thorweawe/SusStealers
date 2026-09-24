--!strict
--[[
	Gezen impostor: arada bir bir vent'ten çıkan NPC hırsız.

	  1. Yaklaşma — rastgele bir üssün (sahibi var, kaidesi dolu) bir
	     kaidesine yürüyor. Sahibine haber gidiyor.
	  2. Hackleme — kaidenin yanında Config.RogueHackSeconds bekliyor.
	     KİLİT İŞE YARAMIYOR: kilit oyunculara karşı; impostoru yalnızca
	     sahibinin kendisi durdurabiliyor. Kaide boşalırsa vazgeçiyor.
	  3. Kaçış — karakterin kopyasını sırtlanıp uzaktaki bir vent'e koşuyor;
	     kaidedeki asıl karakter soluklaşıyor.
	  4. Sonuç — yakalanırsa sahibine ödül, karakter normale dönüyor.
	     Kaçarsa karakter kaidede kalıyor ama Config.RogueOfflineSeconds
	     boyunca gelir üretmiyor (kaidede "OfflineUntil" niteliği;
	     EconomyService okuyor).

	YALNIZCA üssün sahibi durdurabiliyor: prompt herkese görünüyor ama
	başkası basınca reddediliyor (StealService'teki hırsız yakalama ile
	aynı kural).

	HAREKET SUNUCUDA: herkes aynı yerde görmeli ve yakalama mesafesi
	sunucuda doğrulanıyor (PromptGuard). Model tek parça gibi hareket
	ediyor: kök parça çapalı, diğerleri ona kaynaklı — ağa her karede
	tek CFrame gidiyor.

	Olay sırasında (EventService) çıkmıyor; olaylar zaten yeterince
	kalabalık.
]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local UnitModel = require(Shared.UnitModel)

local EconomyService = require(script.Parent.EconomyService)
local EventService = require(script.Parent.EventService)
local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local TitleService = require(script.Parent.TitleService)
local VentService = require(script.Parent.VentService)

local RogueService = {}

local NOTIFY_KIND = "rogue"
RogueService.NotifyKind = NOTIFY_KIND

type Rogue = {
	model: Model,
	root: BasePart,
	lift: number,
	pos: Vector3,
	status: TextLabel,
	plot: Model,
	podium: Part,
	owner: Player,
	phase: string,      -- "approach" | "hack" | "flee" | "done"
	carried: Model?,
	alive: boolean,
}

local notifyRemote: RemoteEvent
local paused = false
local current: Rogue? = nil
-- Kaçırılan kaideler -> geri sayım etiketi
local offline: { [Part]: BillboardGui } = {}

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, NOTIFY_KIND)
	end
end

local function unitName(podium: Part): string
	local def = Config.GetUnit(podium:GetAttribute("UnitId") :: string)
	return if def then def.name else "crewmate"
end

-- ─── Kaidedeki karakterin görünüşü ──────────────────────────────────────────

--[[ Karakteri soluklaştırır ya da eski hâline döndürür. ]]
local function setGhost(podium: Part, ghost: boolean)
	local unit = podium:FindFirstChild("Unit")
	if not unit then
		return
	end
	for _, d in unit:GetDescendants() do
		if d:IsA("BasePart") then
			if ghost then
				if d:GetAttribute("RogueGhost") == nil and d.Transparency < 1 then
					d:SetAttribute("RogueGhost", d.Transparency)
					d.Transparency = 0.5 + d.Transparency * 0.5
				end
			else
				local original = d:GetAttribute("RogueGhost")
				if typeof(original) == "number" then
					d.Transparency = original
					d:SetAttribute("RogueGhost", nil)
				end
			end
		end
	end
end

local function clearOffline(podium: Part)
	podium:SetAttribute("OfflineUntil", nil)
	podium:SetAttribute("OfflineUnit", nil)
	setGhost(podium, false)
	local label = offline[podium]
	if label then
		label:Destroy()
		offline[podium] = nil
	end
end

--[[ Kaideyi Config.RogueOfflineSeconds boyunca gelirsiz bırakır. ]]
local function setOffline(podium: Part)
	clearOffline(podium)
	podium:SetAttribute("OfflineUntil", workspace:GetServerTimeNow() + Config.RogueOfflineSeconds)
	-- Hangi karakter kaçırıldı: kaidedeki karakter DEĞİŞİRSE gelirsizlik biter
	podium:SetAttribute("OfflineUnit", podium:GetAttribute("UnitId"))
	setGhost(podium, true)

	local gui = Instance.new("BillboardGui")
	gui.Name = "OfflineLabel"
	-- Piksel boyutlu etiket hiç çizilmedi; karakter etiketleri gibi ölçekli.
	-- Karakterin kendi etiketinin (6.8) üstünde
	gui.Size = UDim2.fromScale(4.6, 1.1)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	-- AlwaysOnTop açık etiketler bu oyunda hiç çizilmedi (karakter etiketleri de kapalı)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Parent = podium
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 90, 90)
	text.TextStrokeTransparency = 0.3
	text.Text = "STOLEN " .. Config.FormatDuration(Config.RogueOfflineSeconds)
	text.Parent = gui
	offline[podium] = gui
end

-- ─── Model ──────────────────────────────────────────────────────────────────

local function buildModel(): (Model, BasePart, number, TextLabel)
	local model = UnitModel.Build("RedCrew")
	model.Name = "RogueImpostor"
	local root = model.PrimaryPart :: BasePart
	--[[
		Kökten ayak tabanına mesafe. Kök parça ayak hizasında DEĞİL; pivottan
		hesaplayınca NPC yarı yarıya zemine gömülüyordu. Sınır kutusunun
		altından ölçülüyor.
	]]
	local box, size = model:GetBoundingBox()
	local lift = root.Position.Y - (box.Position.Y - size.Y / 2)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = d == root
		end
	end
	-- Kaidedeki karakterlerle karışmasın: kırmızı dış hat, duvarın arkasından da
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.75
	highlight.FillColor = Color3.fromRGB(255, 40, 40)
	highlight.OutlineColor = Color3.fromRGB(255, 60, 60)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Name = "RogueLabel"
	-- Piksel boyutlu etiket çizilmedi; ölçekli. Sırtındaki karakterin üstünde
	gui.Size = UDim2.fromScale(6, 1.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7.5, 0)
	-- AlwaysOnTop açık etiketler çizilmedi; duvar arkasından görünürlüğü Highlight veriyor
	gui.AlwaysOnTop = false
	gui.MaxDistance = 160
	gui.Parent = root
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.55)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 70, 70)
	title.TextStrokeTransparency = 0.2
	title.Text = "ROGUE IMPOSTOR"
	title.Parent = gui
	local status = Instance.new("TextLabel")
	status.Position = UDim2.fromScale(0, 0.55)
	status.Size = UDim2.fromScale(1, 0.45)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextScaled = true
	status.TextColor3 = Color3.new(1, 1, 1)
	status.TextStrokeTransparency = 0.3
	status.Text = ""
	status.Parent = gui

	return model, root, lift, status
end

--[[
	Ayakların altındaki zemin. Yol noktaları zeminin biraz üstünde
	gelebiliyor (NPC havada süzülüyordu); aşağı ışın atıp oturtuyoruz.
	Karakterler ve çarpışmasız süsler sayılmıyor.
]]
local function groundY(r: Rogue, pos: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { r.model }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0), params)
	return if hit then hit.Position.Y else pos.Y
end

--[[
	`container`daki parçaları köke kaynaklar ve çapayı bırakır: böylece
	yalnızca kök hareket ediyor, gerisi onunla gidiyor.

	DÜNYADAYKEN çağrılmalı. Model workspace'e girmeden kurulan kaynaklar
	montaj oluşturmadı: kök yürürken gövde doğduğu vent'te kalıyordu.
]]
local function weldTo(root: BasePart, container: Instance)
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
			d.Anchored = false
		end
	end
end

local function place(r: Rogue, pos: Vector3, facing: Vector3)
	pos = Vector3.new(pos.X, groundY(r, pos), pos.Z)
	r.pos = pos
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local look = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	r.root.CFrame = CFrame.lookAt(pos, pos + look) + Vector3.new(0, r.lift, 0)
end

-- ─── Hedef seçimi ───────────────────────────────────────────────────────────

--[[ Kaidenin önünde, üssün ortasına doğru ayakta durulacak nokta. ]]
local function standPoint(plot: Model, podium: Part): Vector3
	local base = plot:FindFirstChild("Base") :: BasePart?
	local center = if base then base.Position else podium.Position
	local d = Vector3.new(center.X - podium.Position.X, 0, center.Z - podium.Position.Z)
	d = if d.Magnitude > 0.1 then d.Unit else Vector3.zAxis
	return podium.Position + d * 3.5 + Vector3.new(0, 1, 0)
end

local function computePath(from: Vector3, to: Vector3): { Vector3 }?
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.6,
		AgentHeight = 5,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})
	local ok = pcall(function()
		path:ComputeAsync(from + Vector3.new(0, 2, 0), to)
	end)
	if not (ok and path.Status == Enum.PathStatus.Success) then
		return nil
	end
	local points = {}
	for _, wp in path:GetWaypoints() do
		table.insert(points, wp.Position)
	end
	return points
end

local function shuffled<T>(list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Hedef olabilecek (üs, kaide) çiftleri: sahibi olan üslerin dolu ve
	zaten kaçırılmamış kaideleri. Kilit fark etmiyor.
]]
function RogueService.GetCandidates(): { { plot: Model, podium: Part } }
	local out = {}
	local now = workspace:GetServerTimeNow()
	for _, plot in PlotService.GetAllPlots() do
		if not PlotService.GetOwner(plot) then
			continue
		end
		for _, podium in PlotService.GetPodiums(plot) do
			local offlineUntil = podium:GetAttribute("OfflineUntil") :: number?
			if PlotService.IsOccupied(podium) and not (offlineUntil and offlineUntil > now) then
				table.insert(out, { plot = plot, podium = podium })
			end
		end
	end
	return out
end

-- ─── Yaşam döngüsü ──────────────────────────────────────────────────────────

local function despawn(r: Rogue)
	r.alive = false
	r.phase = "done"
	if r.model.Parent then
		r.model:Destroy()
	end
	if current == r then
		current = nil
	end
end

--[[ Yolu izler. Durdurulursa (yakalandı, vazgeçti) ya da süre dolarsa false. ]]
local function walk(r: Rogue, points: { Vector3 }, speed: number, timeout: number, phase: string): boolean
	local started = os.clock()
	for _, target in points do
		while true do
			if not r.alive or r.phase ~= phase then
				return false
			end
			if os.clock() - started > timeout then
				return false
			end
			local dt = RunService.Heartbeat:Wait()
			local flat = Vector3.new(target.X - r.pos.X, 0, target.Z - r.pos.Z)
			local dist = flat.Magnitude
			if dist < 0.5 then
				place(r, Vector3.new(target.X, target.Y, target.Z), flat)
				break
			end
			local step = math.min(dist, speed * dt)
			local dir = flat.Unit
			local y = r.pos.Y + (target.Y - r.pos.Y) * math.clamp(step / dist, 0, 1)
			place(r, Vector3.new(r.pos.X + dir.X * step, y, r.pos.Z + dir.Z * step), dir)
		end
	end
	return true
end

--[[
	Kaçış kapakları: kaideden en az Config.RogueEscapeMinDistance uzakta
	olanlar, yakından uzağa. Hiçbiri o kadar uzak değilse en uzağı.
]]
local function escapePads(from: Vector3): { BasePart }
	local pads = table.clone(VentService.GetPads())
	table.sort(pads, function(a, b)
		return (a.Position - from).Magnitude < (b.Position - from).Magnitude
	end)
	local out = {}
	for _, pad in pads do
		if (pad.Position - from).Magnitude >= Config.RogueEscapeMinDistance then
			table.insert(out, pad)
		end
	end
	if #out == 0 and #pads > 0 then
		table.insert(out, pads[#pads])
	end
	return out
end

--[[
	Hackleme tamamlandı: karakterin kopyasını sırtlan, asıl karakter
	soluklaşsın. Testler de bunu doğrudan çağırıyor.
]]
function RogueService._Grab()
	local r = current
	if not r or r.phase == "flee" or r.phase == "done" then
		return
	end
	r.phase = "flee"
	local unit = r.podium:FindFirstChild("Unit")
	if unit and unit:IsA("Model") then
		local copy = unit:Clone()
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
			elseif d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then
				d:Destroy()
			end
		end
		copy:ScaleTo(0.6)
		-- Kopyanın ayakları impostorun kafasının tepesine
		local _, rogueSize = r.model:GetBoundingBox()
		local feet = r.root.Position.Y - r.lift
		copy:PivotTo(r.root.CFrame * CFrame.new(0, 0, 0.3))
		local box, size = copy:GetBoundingBox()
		local bottom = box.Position.Y - size.Y / 2
		copy:PivotTo(copy:GetPivot() + Vector3.new(0, feet + rogueSize.Y - 0.3 - bottom, 0))
		copy.Parent = r.model
		weldTo(r.root, copy)
		r.carried = copy
	end
	setGhost(r.podium, true)
	r.status.Text = "Escaping with " .. unitName(r.podium) .. "!"
	notify(r.owner, string.format("The impostor grabbed your %s! Catch it before it vents (hold E)", unitName(r.podium)), true)
end

--[[ Kaçtı: kaide gelirsiz kalıyor. Testler de doğrudan çağırıyor. ]]
function RogueService._Escape()
	local r = current
	if not r then
		return
	end
	local grabbed = r.phase == "flee"
	despawn(r)
	if grabbed and r.podium.Parent and PlotService.IsOccupied(r.podium) then
		setOffline(r.podium)
		notify(r.owner, string.format("The impostor escaped! Your %s makes no money for %s",
			unitName(r.podium), Config.FormatDuration(Config.RogueOfflineSeconds)), true)
	end
end

--[[
	Durdurma denemesi. Sebebini döner: "ok" | "none" | "owner".
	Ödül tutarı ikinci dönüş (yalnızca "ok"da).
]]
function RogueService.TryCatch(player: Player): (string, number)
	local r = current
	if not r or not r.alive then
		return "none", 0
	end
	if player ~= r.owner then
		notify(player, string.format("Only %s can stop this impostor", r.owner.DisplayName), true)
		return "owner", 0
	end
	despawn(r)
	setGhost(r.podium, false)
	local reward = Config.GetRogueReward(EconomyService.GetIncome(player))
	EconomyService.AddCash(player, reward)
	TitleService.AddCaught(player)
	notify(player, string.format("You stopped the impostor! +$%s", Config.FormatCash(reward)), false)
	return "ok", reward
end

--[[
	İmpostoru çıkarır. `plot`/`podium` verilmezse rastgele seçiliyor.
	`static` = hareket yok (testler adımları kendileri çağırıyor).
	Çıkarsa true.
]]
function RogueService.Spawn(plot: Model?, podium: Part?, static: boolean?): boolean
	if current then
		return false
	end
	local pads = VentService.GetPads()
	if #pads == 0 then
		return false
	end

	-- Hedef ve yol: yolu bulunamayan kaide (kapalı üst kat vb.) atlanıyor
	local spawnPad: BasePart = pads[math.random(1, #pads)]
	local chosen: { plot: Model, podium: Part }? = nil
	local path: { Vector3 }? = nil
	local candidates = if plot and podium then { { plot = plot, podium = podium } } else shuffled(RogueService.GetCandidates())
	for i, c in candidates do
		if i > 6 then
			break
		end
		if static then
			chosen = c
			break
		end
		local p = computePath(spawnPad.Position, standPoint(c.plot, c.podium))
		if p then
			chosen, path = c, p
			break
		end
	end
	if not chosen then
		return false
	end
	local owner = PlotService.GetOwner(chosen.plot)
	if not owner then
		return false
	end

	local model, root, lift, status = buildModel()
	local r: Rogue = {
		model = model,
		root = root,
		lift = lift,
		pos = spawnPad.Position,
		status = status,
		plot = chosen.plot,
		podium = chosen.podium,
		owner = owner,
		phase = "approach",
		carried = nil,
		alive = true,
	}
	status.Text = "Heading to " .. owner.DisplayName .. "'s base"

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RoguePrompt"
	prompt.ActionText = "Stop Impostor"
	prompt.ObjectText = "Only " .. owner.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = Config.RogueCatchHold
	prompt.MaxActivationDistance = Config.RogueCatchRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	PromptGuard.Connect(prompt, function(player)
		if current == r then
			RogueService.TryCatch(player)
		end
	end)

	-- Sıra önemli: önce kaynak (parçalar hâlâ kurulduğu yerde), sonra konum.
	-- Tersi, kökü taşıyıp gövdeyi geride bırakan bir kaynak kaydediyordu.
	model.Parent = workspace
	weldTo(root, model)
	place(r, spawnPad.Position + Vector3.new(0, spawnPad.Size.Y / 2, 0), Vector3.zAxis)
	current = r

	notify(owner, "A rogue impostor crawled out of a vent and is heading for your base! Stop it (hold E)", true)
	for _, other in Players:GetPlayers() do
		if other ~= owner then
			notify(other, string.format("A rogue impostor is after %s's base!", owner.DisplayName), false)
		end
	end

	if static or not path then
		return true
	end

	task.spawn(function()
		-- 1) Yaklaşma
		if not walk(r, path, Config.RogueApproachSpeed, Config.RogueApproachTimeout, "approach") then
			if r.alive and r.phase == "approach" then
				notify(r.owner, "The impostor got lost and vented away", false)
				despawn(r)
			end
			return
		end
		place(r, r.pos, r.podium.Position - r.pos)

		-- 2) Hackleme: kaide boşalırsa (satıldı, çalındı) vazgeç
		r.phase = "hack"
		local hackEnd = os.clock() + Config.RogueHackSeconds
		while r.alive and r.phase == "hack" and os.clock() < hackEnd do
			if not PlotService.IsOccupied(r.podium) then
				notify(r.owner, "The impostor gave up and vented away", false)
				despawn(r)
				return
			end
			r.status.Text = string.format("Hacking %s... %ds", unitName(r.podium), math.ceil(hackEnd - os.clock()))
			task.wait(0.25)
		end
		if not (r.alive and r.phase == "hack") then
			return
		end
		RogueService._Grab()

		-- 3) Kaçış
		local fleePath: { Vector3 }? = nil
		for i, pad in escapePads(r.pos) do
			if i > 4 then
				break
			end
			fleePath = computePath(r.pos, pad.Position + Vector3.new(0, 1, 0))
			if fleePath then
				break
			end
		end
		if fleePath then
			walk(r, fleePath, Config.RogueFleeSpeed, Config.RogueFleeTimeout, "flee")
		else
			-- Yol yoksa kaçış süresi kadar yerinde bekleyip kaçmış sayılıyor
			local t = os.clock()
			while r.alive and r.phase == "flee" and os.clock() - t < Config.RogueFleeTimeout do
				task.wait(0.25)
			end
		end
		if r.alive and r.phase == "flee" and current == r then
			RogueService._Escape()
		end
	end)
	return true
end

function RogueService.GetCurrent(): Rogue?
	return current
end

--[[ Testler için: sahnedeki impostoru ve kaide durumunu temizler. ]]
function RogueService._Reset(podium: Part?)
	if current then
		local r = current
		despawn(r)
		setGhost(r.podium, false)
	end
	if podium then
		clearOffline(podium)
	end
end

function RogueService.SetPaused(value: boolean)
	paused = value
end

function RogueService.Start()
	notifyRemote = Net.Get("Notify")

	--[[
		Kaidedeki karakter değişirse (satıldı, çalındı) gelirsizlik de biter.
		Kaçırılan karakterle KARŞILAŞTIRILIYOR: nitelik sinyalleri gecikmeli
		geliyor, "değişti" diye her sinyalde silmek, karakter konduktan hemen
		sonra kaçırılınca yeni işareti siliyordu.
	]]
	for _, plot in PlotService.GetAllPlots() do
		for _, podium in PlotService.GetPodiums(plot) do
			podium:GetAttributeChangedSignal("UnitId"):Connect(function()
				if podium:GetAttribute("OfflineUntil") ~= nil
					and podium:GetAttribute("UnitId") ~= podium:GetAttribute("OfflineUnit")
				then
					clearOffline(podium)
				end
			end)
		end
	end

	-- Sahibi çıkarsa impostor da gidiyor
	Players.PlayerRemoving:Connect(function(player)
		local r = current
		if r and r.owner == player then
			despawn(r)
		end
	end)

	-- Geri sayım etiketleri ve süresi dolan kaideler
	task.spawn(function()
		while true do
			task.wait(1)
			local now = workspace:GetServerTimeNow()
			for podium, gui in offline do
				local untilAt = podium:GetAttribute("OfflineUntil") :: number?
				if not untilAt or untilAt <= now or not podium.Parent then
					clearOffline(podium)
				else
					local text = gui:FindFirstChildOfClass("TextLabel")
					if text then
						text.Text = "STOLEN " .. Config.FormatDuration(untilAt - now)
					end
				end
			end
		end
	end)

	-- Zamanlayıcı
	task.spawn(function()
		task.wait(math.random(Config.RogueFirstDelay[1], Config.RogueFirstDelay[2]))
		while true do
			local spawned = false
			if not paused and not current and EventService.GetActiveId() == nil then
				spawned = RogueService.Spawn()
			end
			-- Çıkamadıysa (hedef yok, olay var) bir dakika sonra tekrar dene
			task.wait(if spawned then math.random(Config.RogueIntervalMin, Config.RogueIntervalMax) else 60)
		end
	end)
end

return RogueService
