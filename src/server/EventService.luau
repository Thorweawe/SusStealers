--!strict
--[[
	Sunucu olayları: saatli, herkesin aynı anda yaşadığı kısa anlar.
	Steal a Brainrot tarzı oyunları canlı tutan şey bunlar: oyuncu "saat
	:15'te toplantı var" diye oyuna giriyor.

	  Emergency Meeting  — 2 dk herkese 2x gelir
	  Lights Sabotage    — ışıklar kararıyor, çalma süreleri kısalıyor
	  Reactor Meltdown   — istasyonun rastgele yerlerine enerji çekirdeği
	                       düşüyor, ilk dokunan alıyor (nakit / nadiren karakter)
	  Impostor Among Us  — rastgele bir oyuncu 1 dk herkesin gördüğü impostor;
	                       yakalanırsa yakalayan ONA ödüyor

	Takvim Config.Events'te, UTC saatine hizalı: bütün sunucularda aynı
	anda başlıyor. Aynı anda tek olay: takvim zaten çakışmıyor, yine de
	biri sürerken diğeri gelirse atlanıyor.

	═══ İSTEMCİYE NASIL GİDİYOR ════════════════════════════════════════════

	workspace nitelikleri — ayrı remote yok, yeni bir saldırı yüzeyi yok:
	  EventId / EventName / EventEndsAt       — süren olay
	  NextEventId / NextEventName / NextEventAt — sıradaki
	  EventIncomeMul                          — EconomyService okuyor
	Zamanlar unix saniye; istemci workspace:GetServerTimeNow() ile sayıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)
local StealService = require(script.Parent.StealService)
local AnnounceService = require(script.Parent.AnnounceService)

local EventService = {}

local NOTIFY_KIND = "event"
-- Dışa açık: test her servisin türünün Config.NotifyCues'ta sesi olduğuna bakıyor
EventService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent
local paused = false
local rng = Random.new()

type Active = {
	def: Config.EventDef,
	endsAt: number,
	cleanup: () -> (),
}
local active: Active? = nil

local impostor: Player? = nil
local cores: Folder? = nil

-- ─── Yardımcılar ────────────────────────────────────────────────────────────

local function notifyAll(text: string, isError: boolean?)
	if notifyRemote then
		notifyRemote:FireAllClients(text, isError == true, NOTIFY_KIND)
	end
end

local function notify(player: Player, text: string, isError: boolean?)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError == true, NOTIFY_KIND)
	end
end

local function announce(text: string)
	AnnounceService.Summon(AnnounceService.Paint(text, Color3.fromRGB(255, 90, 80)))
end

local function publish()
	local a = active
	workspace:SetAttribute("EventId", if a then a.def.id else "")
	workspace:SetAttribute("EventName", if a then a.def.name else "")
	workspace:SetAttribute("EventEndsAt", if a then a.endsAt else 0)
end

--[[ Olayın takvimdeki bir sonraki başlangıcını ve sıradakini yayınlar. ]]
local function publishNext(now: number)
	local bestDef: Config.EventDef? = nil
	local bestAt = math.huge
	for _, def in Config.Events do
		-- Rastgele olay (Impostor) sürpriz: sıradaki olarak yayınlanmıyor
		if def.random then
			continue
		end
		local at = Config.GetNextEventStart(def, now + 1)
		if at < bestAt then
			bestDef, bestAt = def, at
		end
	end
	if bestDef then
		workspace:SetAttribute("NextEventId", bestDef.id)
		workspace:SetAttribute("NextEventName", bestDef.name)
		workspace:SetAttribute("NextEventAt", bestAt)
	end
end

-- ─── Emergency Meeting ──────────────────────────────────────────────────────

local function beginMeeting(): () -> ()
	workspace:SetAttribute("EventIncomeMul", Config.MeetingIncomeMul)
	notifyAll(string.format("EMERGENCY MEETING! %dx income for everyone!", Config.MeetingIncomeMul))
	return function()
		workspace:SetAttribute("EventIncomeMul", 1)
	end
end

-- ─── Lights Sabotage ────────────────────────────────────────────────────────

local function beginLights(): () -> ()
	StealService.SetEventHoldMultiplier(Config.LightsOutHoldMul)
	notifyAll("LIGHTS SABOTAGED! Stealing is faster in the dark!")
	return function()
		StealService.SetEventHoldMultiplier(1)
	end
end

-- ─── Reactor Meltdown ───────────────────────────────────────────────────────

--[[
	İstasyon zemininin sınırları (koridor karoları). Harita koddan kurulu,
	koordinat yazmıyoruz.
]]
local function stationBounds(): (Vector3?, Vector3?)
	local decor = workspace:FindFirstChild("Decor")
	local floor = decor and decor:FindFirstChild("Floor")
	if not floor then
		return nil, nil
	end
	local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in floor:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "HallTile" then
			mn = mn:Min(d.Position - d.Size / 2)
			mx = mx:Max(d.Position + d.Size / 2)
		end
	end
	if mn.X == math.huge then
		return nil, nil
	end
	return mn, mx
end

--[[
	Rastgele ama adil nokta: hiçbir üssün içine düşmüyor (sahibine bedava
	olurdu) ve bir engelin içinde değil.
]]
function EventService.RandomCorePosition(): Vector3?
	local mn, mx = stationBounds()
	if not (mn and mx) then
		return nil
	end
	local plots = PlotService.GetAllPlots()
	local params = OverlapParams.new()
	params.RespectCanCollide = true
	for _ = 1, 60 do
		local p = Vector3.new(rng:NextNumber(mn.X + 6, mx.X - 6), 0, rng:NextNumber(mn.Z + 6, mx.Z - 6))
		local inPlot = false
		for _, plot in plots do
			local cf, size = plot:GetBoundingBox()
			local lp = cf:PointToObjectSpace(Vector3.new(p.X, cf.Position.Y, p.Z))
			if math.abs(lp.X) <= size.X / 2 + 4 and math.abs(lp.Z) <= size.Z / 2 + 4 then
				inPlot = true
				break
			end
		end
		if not inPlot then
			local spot = Vector3.new(p.X, 2.5, p.Z)
			local blocked = workspace:GetPartBoundsInBox(CFrame.new(spot), Vector3.new(3, 3, 3), params)
			if #blocked == 0 then
				return spot
			end
		end
	end
	return nil
end

--[[
	Ödülü verir. Nakit gelirle ölçekli; düşük ihtimalle bir karakter
	(~10 dakikalık gelirle alınabilecek en iyisi, boş kaide varsa).
	Döner: "cash" | "unit", miktar ya da karakter kimliği.
]]
function EventService.GrantCore(player: Player, roll: number?): (string, any)
	local income = EconomyService.GetIncome(player)
	local r = roll or rng:NextNumber()
	if r < Config.MeltdownUnitChance then
		local budget = math.max(income * 60 * Config.MeltdownUnitMinutes, Config.Units[1].price)
		local pick: string? = nil
		local bestPrice = -1
		for _, def in Config.Units do
			if def.price <= budget and def.price > bestPrice then
				pick, bestPrice = def.id, def.price
			end
		end
		local plot = PlotService.GetPlotOf(player)
		local podium = plot and PlotService.FindEmptyPodium(plot)
		if pick and podium and PlotService.PlaceUnit(podium, pick) then
			return "unit", pick
		end
	end
	local amount = math.max(Config.MeltdownMinCash, math.floor(income * Config.MeltdownRewardSeconds))
	EconomyService.AddCash(player, amount)
	return "cash", amount
end

local function spawnCore(folder: Folder, position: Vector3)
	local core = Instance.new("Part")
	core.Name = "ReactorCore"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(2.6, 2.6, 2.6)
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(90, 255, 170)
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CastShadow = false
	core.Position = position
	local light = Instance.new("PointLight")
	light.Color = core.Color
	light.Range = 14
	light.Brightness = 2
	light.Parent = core
	core.Parent = folder

	local taken = false
	core.Touched:Connect(function(hit)
		if taken then
			return
		end
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not player or not humanoid or humanoid.Health <= 0 then
			return
		end
		taken = true
		core:Destroy()
		local kind, value = EventService.GrantCore(player)
		if kind == "unit" then
			local def = Config.GetUnit(value)
			local name = if def then def.name else tostring(value)
			notify(player, string.format("Reactor core: you got a %s!", name))
			announce(string.format("%s grabbed a reactor core and got a %s!", player.DisplayName, name))
		else
			notify(player, string.format("Reactor core: +$%s", Config.FormatCash(value)))
		end
	end)
end

local function beginMeltdown(): () -> ()
	local folder = Instance.new("Folder")
	folder.Name = "EventCores"
	folder.Parent = workspace
	cores = folder
	local placed = 0
	for _ = 1, Config.MeltdownCores do
		local pos = EventService.RandomCorePosition()
		if pos then
			spawnCore(folder, pos)
			placed += 1
		end
	end
	notifyAll(string.format("REACTOR MELTDOWN! %d energy cores dropped around the station!", placed))
	return function()
		folder:Destroy()
		cores = nil
	end
end

-- ─── Impostor Among Us ──────────────────────────────────────────────────────

--[[
	Yakalayanın impostora ödediği tutar: parasının %3-5'i, en fazla tavan.
	`roll` 0..1 arası (testler sabit verebilsin).
]]
function EventService.ImpostorPayment(catcherCash: number, roll: number): number
	local share = Config.ImpostorPayMin + (Config.ImpostorPayMax - Config.ImpostorPayMin) * math.clamp(roll, 0, 1)
	return math.max(0, math.min(Config.ImpostorPayCap, math.floor(catcherCash * share)))
end

local function tagImpostor(player: Player, on: boolean)
	player:SetAttribute("Impostor", on)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local old = head and head:FindFirstChild("ImpostorTag")
	if old then
		old:Destroy()
	end
	if on and head then
		local tag = Instance.new("BillboardGui")
		tag.Name = "ImpostorTag"
		tag.Size = UDim2.fromOffset(160, 40)
		tag.StudsOffset = Vector3.new(0, 3.2, 0)
		tag.AlwaysOnTop = true
		tag.MaxDistance = 250
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 60, 60)
		label.TextStrokeTransparency = 0.2
		label.Text = "IMPOSTOR"
		label.Parent = tag
		tag.Parent = head
	end
end

--[[ StealService yakalama bildirimi: hırsız o anki impostorsa ödeme. ]]
function EventService.OnCaught(thief: Player, catcher: Player, roll: number?): number
	if thief ~= impostor or thief:GetAttribute("Impostor") ~= true then
		return 0
	end
	local pay = EventService.ImpostorPayment(EconomyService.GetCash(catcher), roll or rng:NextNumber())
	if pay <= 0 or not EconomyService.TrySpend(catcher, pay) then
		return 0
	end
	EconomyService.AddCash(thief, pay)
	notify(catcher, string.format("That was the IMPOSTOR! You paid them $%s", Config.FormatCash(pay)), true)
	notify(thief, string.format("They caught you, impostor! +$%s", Config.FormatCash(pay)))
	return pay
end

local function beginImpostor(): (() -> ())?
	local candidates = {}
	for _, p in Players:GetPlayers() do
		if PlotService.GetPlotOf(p) and p.Character then
			table.insert(candidates, p)
		end
	end
	-- Tek başına impostor olmanın anlamı yok
	if #candidates < 2 then
		return nil
	end
	local chosen = candidates[rng:NextInteger(1, #candidates)]
	impostor = chosen
	tagImpostor(chosen, true)
	notifyAll(string.format("%s is the IMPOSTOR for 1 minute! Catching them costs YOU money - lock your base!", chosen.DisplayName))
	notify(chosen, "You are the IMPOSTOR! Steal - if they catch you, THEY pay you!")

	local respawn = chosen.CharacterAdded:Connect(function()
		task.wait(0.5)
		if impostor == chosen then
			tagImpostor(chosen, true)
		end
	end)
	return function()
		respawn:Disconnect()
		if chosen.Parent then
			tagImpostor(chosen, false)
		end
		impostor = nil
	end
end

-- ─── Yaşam döngüsü ──────────────────────────────────────────────────────────

local BEGIN: { [string]: () -> (() -> ())? } = {
	Meeting = beginMeeting,
	LightsOut = beginLights,
	Meltdown = beginMeltdown,
	Impostor = beginImpostor,
}

--[[
	Olayı hemen başlatır (takvimden ya da testten). Başlayamadıysa
	(koşul sağlanmadı, başka olay sürüyor) false.
]]
function EventService.Begin(id: string, now: number?): boolean
	if active then
		return false
	end
	local def = Config.GetEvent(id)
	local begin = BEGIN[id]
	if not (def and begin) then
		return false
	end
	local cleanup = begin()
	if not cleanup then
		return false
	end
	active = { def = def, endsAt = (now or os.time()) + def.duration, cleanup = cleanup }
	publish()
	announce(string.format("%s has started!", string.upper(def.name)))
	return true
end

function EventService.End()
	local a = active
	if not a then
		return
	end
	active = nil
	a.cleanup()
	publish()
	notifyAll(string.format("%s is over.", a.def.name))
end

function EventService.GetActiveId(): string?
	return if active then active.def.id else nil
end

--[[ Testler: takvim koşu boyunca olay başlatmasın. ]]
function EventService.SetPaused(value: boolean)
	paused = value
end

function EventService.Start()
	notifyRemote = Net.Get("Notify")
	workspace:SetAttribute("EventIncomeMul", 1)
	publish()

	StealService.OnCaught(function(thief, catcher)
		EventService.OnCaught(thief, catcher)
	end)

	Players.PlayerRemoving:Connect(function(player)
		if player == impostor then
			EventService.End()
		end
	end)

	-- Takvim: saniyede bir bak. Uyarı ve başlangıç için her olayın bir sonraki slotu.
	local warned: { [string]: number } = {}
	local started: { [string]: number } = {}
	-- Rastgele olayların bu saatteki planı: kimlik -> { hour, starts, done }
	local plans: { [string]: { hour: number, starts: { number }, done: { [number]: boolean } } } = {}
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			publishNext(now)

			local a = active
			if a and now >= a.endsAt then
				EventService.End()
			end

			if paused then
				continue
			end

			for _, def in Config.Events do
				if def.random then
					--[[
						Saat değişince yeni zar: bu saatin başlangıçları. Uyarı
						yok, çizelgede yok — sürpriz. Başlayamazsa (tek oyuncu,
						başka olay sürüyor) o başlangıç yanıyor.
					]]
					local hour = now - now % 3600
					local plan = plans[def.id]
					if not plan or plan.hour ~= hour then
						plan = { hour = hour, starts = Config.PlanRandomEvent(def, hour, rng), done = {} }
						plans[def.id] = plan
					end
					for _, at in plan.starts do
						if not plan.done[at] and now >= at and now - at < 5 then
							plan.done[at] = true
							EventService.Begin(def.id, now)
						end
					end
					continue
				end
				local nextAt = Config.GetNextEventStart(def, now)
				-- Uyarı: başlangıçtan EventWarning saniye önce, slot başına bir kez
				if nextAt - now <= Config.EventWarning and nextAt > now and warned[def.id] ~= nextAt then
					warned[def.id] = nextAt
					notifyAll(string.format("%s in %d seconds!", def.name, nextAt - now))
				end
				--[[
					Başlangıç: en son slotun ilk 5 saniyesi içindeysek. Tam
					saniyeye denk gelmeyi beklemiyoruz; task.wait(1) arada bir
					saniye atlayabiliyor ve olay hiç başlamazdı.
				]]
				local lastAt = if nextAt == now then now else nextAt - def.every
				if now - lastAt < 5 and started[def.id] ~= lastAt then
					started[def.id] = lastAt
					EventService.Begin(def.id, now)
				end
			end
		end
	end)
end

return EventService
