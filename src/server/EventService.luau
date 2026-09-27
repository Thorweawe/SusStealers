--!strict
--[[
	Sunucu olayları: saatli, herkesin aynı anda yaşadığı kısa anlar.
	Steal a Brainrot tarzı oyunları canlı tutan şey bunlar: oyuncu "saat
	:15'te toplantı var" diye oyuna giriyor.

	  Emergency Meeting  — 2 dk herkese 2x gelir
	  Lights Sabotage    — ışıklar kararıyor, uzaydaki canavarlar yarı kör
	  Reactor Meltdown   — uzaya enerji çekirdekleri savruluyor, ilk dokunan
	                       alıyor (nakit / nadiren karakter)
	  Mutation Storm     — uzaydaki bütün mürettebat mutasyonlu
	  Golden Comet       — sürpriz: uzaydan altın kuyruklu yıldız geçiyor, ilk
	                       dokunan mutasyonlu mürettebat + para (SpaceBonusService)

	(Impostor Among Us 2026-09-28'de kalktı: oyuncudan çalmaya dayanıyordu.)

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
local AnnounceService = require(script.Parent.AnnounceService)
local SpaceService = require(script.Parent.SpaceService)
local SpaceBonusService = require(script.Parent.SpaceBonusService)

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
	-- Canavarlar karanlıkta geç fark edip yavaş kovalıyor
	SpaceService.SetEventMods({ wakeMul = Config.LightsOutWakeMul, chaseMul = Config.LightsOutChaseMul })
	notifyAll("LIGHTS SABOTAGED! Space monsters are half blind - perfect time for a heist!")
	return function()
		SpaceService.SetEventMods({})
	end
end

-- ─── Golden Comet ─────────────────────────────────────────────────────────────

local function beginComet(): () -> ()
	local stop = SpaceBonusService.StartComet()
	notifyAll("A GOLDEN COMET is crossing space! First to touch it wins a mutated crewmate!")
	return stop
end

-- ─── Mutation Storm ─────────────────────────────────────────────────────────

local function beginStorm(): () -> ()
	SpaceService.SetEventMods({ mutated = true })
	notifyAll("MUTATION STORM! Every crewmate in space is mutated - fly out and steal!")
	return function()
		SpaceService.SetEventMods({})
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
	-- Uzay soygunu döneminde çekirdekler uzaya savruluyor (oyuncular uçup topluyor)
	local inSpace = SpaceService.RandomSpacePoint(rng)
	if inSpace then
		return inSpace
	end
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
		-- Karakter: bir üst canavarın havuzundan, doğrudan kaideye (boş kaide varsa)
		local _, unitId = SpaceService.GrantUnit(player, false, 1)
		if unitId then
			return "unit", unitId
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
	-- Uzayda uçarken kolay görülüp çarpılsın diye büyük
	core.Size = Vector3.new(4.5, 4.5, 4.5)
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(90, 255, 170)
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CastShadow = false
	core.Position = position
	local light = Instance.new("PointLight")
	light.Color = core.Color
	light.Range = 26
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
	notifyAll(string.format("REACTOR MELTDOWN! %d glowing cores were vented into space - fly out and grab them!", placed))
	return function()
		folder:Destroy()
		cores = nil
	end
end

-- ─── Yaşam döngüsü ──────────────────────────────────────────────────────────

local BEGIN: { [string]: () -> (() -> ())? } = {
	Meeting = beginMeeting,
	LightsOut = beginLights,
	Meltdown = beginMeltdown,
	Storm = beginStorm,
	Comet = beginComet,
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
