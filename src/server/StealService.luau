--!strict
-- Çalma mekaniği: kaideden söküp taşıma, kendi üssüne bırakma ve kilit savunması.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local UnitModel = require(Shared.UnitModel)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local MonetizationService = require(script.Parent.MonetizationService)
local UpgradeService = require(script.Parent.UpgradeService)
local EconomyService = require(script.Parent.EconomyService)
local BadgeService = require(script.Parent.BadgeService)
local TitleService = require(script.Parent.TitleService)

local StealService = {}

local notifyRemote: RemoteEvent
local alertRemote: RemoteEvent

type Carry = {
	model: Model,
	unitId: string,
	mutationId: string?,
	victim: Player?,
	-- Işınlanarak taşımayı atlamayı engellemek için: nereden, ne zaman
	origin: Vector3,
	startedAt: number,
}

local carrying: { [Player]: Carry } = {}
local lastStealAt: { [Player]: number } = {}

--[[
	Çalma serisi. Art arda başarılı çalma bonus veriyor; araya uzun bir
	boşluk girerse sıfırlanıyor. Bırakma anında sayılıyor, çalma anında
	değil — yakalanan hırsız bonusu hak etmemeli.
]]
local streak: { [Player]: number } = {}
local streakAt: { [Player]: number } = {}

--[[
	Aynı kurbandan kaç kez çalındı. Yoksa iki arkadaş birbirinden sonsuz
	çalıp sıralamayı sahteliyor. Sayaç kurban başına tutuluyor ve sınıra
	ulaşınca o kurban bir süre kapalı kalıyor.
]]
local victimHits: { [Player]: { [Player]: number } } = {}
local victimBlockedUntil: { [Player]: { [Player]: number } } = {}

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "steal"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
StealService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
end

--[[
	Oyuncunun taşıma hızı: yükseltme seviyesi + pet bonusu.

	Pet bonusu nitelikten okunuyor, PetService require edilmiyor —
	EconomyService'teki gerekçenin aynısı, döngüsel bağımlılık olmasın.
	Tavan Config'te: taşırken normal hızı geçmek çalmanın riskini silerdi.
]]
local function carrySpeedFor(player: Player): number
	local petBonus = player:GetAttribute("PetSpeedBonus") :: number?
	return Config.GetCarryWalkSpeed(
		UpgradeService.GetLevel(player, "CarrySpeed"),
		math.max(0, petBonus or 0)
	)
end

--[[
	Kilit süresi ve bekleme. Yükseltme ve gamepass birbirine eklenmiyor,
	hangisi daha iyiyse o geçerli — ikisini de alan iki kat avantaj
	kazanmasın.
]]
--[[
	Oyuncunun o anki yürüme hızı.

	Hız üç duruma bağlı ve üçü de burada: taşırken yavaş, shift basılıyken
	hızlı, normalde normal. Üç ayrı yerde atanıyordu ve koşma eklenince
	hangisinin kazanacağı belirsiz kalırdı — taşırken koşmak çalmanın
	riskini tamamen silerdi.

	Koşma bu modülde çünkü taşımayla YARIŞIYOR; ayrı bir servise koymak
	iki servisin aynı özelliği farklı zamanlarda ezmesi demekti.
]]
local sprinting: { [Player]: boolean } = {}

local function applyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	--[[
		Ekipman hızı (Speed Coil) nitelikten okunuyor: GearService yazıyor.
		Yalnızca TAŞIMIYORKEN sayılıyor — çalınan karakterle kaçarken
		hızlanmak çalmanın riskini silerdi. Koşuyla üst üste binmiyor,
		büyüğü geçerli.
	]]
	local gearSpeed = player:GetAttribute("GearSpeed")
	local boost = if typeof(gearSpeed) == "number" then gearSpeed else 0

	if carrying[player] then
		humanoid.WalkSpeed = carrySpeedFor(player)
	elseif sprinting[player] then
		humanoid.WalkSpeed = math.max(Config.SprintWalkSpeed, boost)
	else
		humanoid.WalkSpeed = math.max(Config.NormalWalkSpeed, boost)
	end
end

--[[ Koşma bayrağını ayarlar. Taşıyan oyuncuda hıza etkisi yok. ]]
function StealService.SetSprinting(player: Player, active: boolean)
	sprinting[player] = active or nil
	applyWalkSpeed(player)
end

--[[ Hızı yeniden hesaplar (ekipman takılıp çıkarılınca GearService çağırıyor). ]]
function StealService.RefreshSpeed(player: Player)
	applyWalkSpeed(player)
end

--[[ Oyuncu şu an çalınmış bir karakter taşıyor mu. ]]
function StealService.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

local function lockValuesFor(player: Player): (number, number)
	local duration, cooldown = Config.GetLockValues(UpgradeService.GetLevel(player, "LockPower"))

	if MonetizationService.HasPass(player, "StrongLock") then
		duration = math.max(duration, Config.PassStrongLockDuration)
		cooldown = math.min(cooldown, Config.PassStrongLockCooldown)
	end

	return duration, cooldown
end

-- ─── Taşıma ─────────────────────────────────────────────────────────────────

local function attachToBack(player: Player, unitId: string, mutationId: string?): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart")) then
		return nil
	end

	local model = UnitModel.Build(unitId, mutationId)
	model.Name = "CarriedUnit"
	model:PivotTo(root.CFrame * CFrame.new(0, 3.5, 0.4))

	local primary = model.PrimaryPart :: BasePart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true

			if descendant ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end

	local rootWeld = Instance.new("WeldConstraint")
	rootWeld.Part0 = root
	rootWeld.Part1 = primary
	rootWeld.Parent = primary

	model.Parent = character

	applyWalkSpeed(player)

	return model
end

local function stopCarrying(player: Player)
	local carry = carrying[player]
	if not carry then
		return
	end

	if carry.model.Parent then
		carry.model:Destroy()
	end
	carrying[player] = nil

	-- Taşıma bitti: koşuyorsa koşu hızına, değilse normale dönsün
	applyWalkSpeed(player)
end

--[[ Taşınan karakteri sahibine geri verir (ölüm / çıkış durumunda). ]]
local function returnToVictim(player: Player)
	local carry = carrying[player]
	if not carry then
		return
	end

	local victim = carry.victim
	if victim and victim.Parent then
		local plot = PlotService.GetPlotOf(victim)
		local podium = plot and PlotService.FindEmptyPodium(plot)

		if podium then
			PlotService.PlaceUnit(podium, carry.unitId, carry.mutationId)
			notify(victim, "Thief down! Your unit is back", false)
		else
			-- Boş kaide yoksa karakteri sessizce yok etmek yerine parasını iade et.
			-- Kurban çalınmayı takiben o slotu doldurmuş olabiliyor; eski hali
			-- oyuncunun en pahalı karakterini iz bırakmadan siliyordu.
			local refund = Config.GetPrice(carry.unitId, carry.mutationId)
			EconomyService.AddCash(victim, refund)
			notify(victim, string.format(
				"Thief down! No free podium - refunded $%s",
				Config.FormatCash(refund)
			), false)
		end
	end

	stopCarrying(player)
end

--[[
	Tokat (Slap Glove): hırsız taşıdığını düşürüyor, karakter kurbanın
	üssüne geri dönüyor. Yakalama promptuyla aynı sonuç ama başka biri de
	yapabiliyor — kurbanın arkadaşı da savunabilsin. Taşımıyorsa false.
]]
function StealService.KnockDrop(thief: Player): boolean
	if not carrying[thief] then
		return false
	end
	returnToVictim(thief)
	return true
end

-- ─── Yakalama ───────────────────────────────────────────────────────────────

--[[ Hırsızı bu kurbandan belirli bir süre engeller. ]]
local function blockFrom(thief: Player, victim: Player, seconds: number)
	local blocked = victimBlockedUntil[thief]
	if not blocked then
		blocked = {}
		victimBlockedUntil[thief] = blocked
	end
	blocked[victim] = os.clock() + seconds
end

--[[
	Kurban, karakterini taşıyan hırsızı durdurur.

	Çalmanın karşı hamlesi bu: eskiden kurban çalındığını görüyordu ama
	yapabileceği tek şey kilitti, o da olay olduktan sonra işe yaramıyordu.
	Artık peşine düşüp geri alabiliyor.

	Prompt taşınan karakterin üstünde duruyor, yani yalnızca hırsız gerçekten
	bir şey taşırken görünüyor. Tetikleyen kişi kurban değilse reddediliyor.
]]
local function setupCatchPrompt(thief: Player, model: Model)
	local primary = model.PrimaryPart
	if not primary then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CatchPrompt"
	prompt.ActionText = "Stop Thief"
	prompt.ObjectText = thief.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = Config.CatchHoldTime
	prompt.MaxActivationDistance = Config.CatchRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = primary

	PromptGuard.Connect(prompt, function(catcher)
		local carry = carrying[thief]
		if not carry then
			return
		end

		-- Yalnızca soyulan kişi durdurabilir; başkası karışamaz
		if carry.victim ~= catcher then
			notify(catcher, "Only the owner can stop this thief", true)
			return
		end

		local unitId, mutationId = carry.unitId, carry.mutationId
		local def = Config.GetUnit(unitId)
		local unitName = if def then def.name else unitId

		-- returnToVictim karakteri geri koyuyor, kaide doluysa parasını veriyor
		returnToVictim(thief)
		blockFrom(thief, catcher, Config.CatchBlockDuration)

		-- Yakalanan hırsızın serisi de kırılıyor: seri risk ödülüydü,
		-- yakalanmak riskin gerçekleşmesi demek
		streak[thief] = nil
		thief:SetAttribute("StealStreak", 0)

		-- Yakalama oyunun en tatmin edici anı; kendi sesi olmalı
		notify(catcher, string.format("You stopped %s and got %s back!", thief.DisplayName, unitName), false, "catch")
		notify(thief, string.format(
			"Caught! You cannot steal from %s for %d min",
			catcher.DisplayName,
			math.floor(Config.CatchBlockDuration / 60)
		), true)

		BadgeService.Award(catcher, "ThiefCatcher")
		TitleService.AddCaught(catcher)
	end)
end

-- ─── Bırakma ────────────────────────────────────────────────────────────────

local function isInsidePlot(position: Vector3, plot: Model): boolean
	local base = plot:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return false
	end

	local delta = position - base.Position
	return math.abs(delta.X) <= Config.PlotSize.X / 2
		and math.abs(delta.Z) <= Config.PlotSize.Z / 2
		and math.abs(delta.Y) <= 30
end

local function tryDeposit(player: Player)
	local carry = carrying[player]
	if not carry then
		return
	end

	local plot = PlotService.GetPlotOf(player)
	if not plot then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end

	if not isInsidePlot(root.Position, plot) then
		return
	end

	-- Bu mesafe bu sürede yürünebilir miydi? Karakterin konumu istemcinin
	-- elinde olduğu için ışınlanan biri üsse anında varabiliyor. Reddetmek
	-- yerine bekletiyoruz: süre dolduğunda bırakma kendiliğinden olur.
	-- Böylece exploit hiçbir şey kazandırmaz ama meşru oyuncu da takılmaz.
	-- Hız yükseltmesi olan oyuncu gerçekten daha hızlı gidiyor; taban hızla
	-- hesaplarsak onu haksız yere bekletiriz.
	local travelled = (root.Position - carry.origin).Magnitude
	local minimumTime = travelled / carrySpeedFor(player) * Config.CarryTravelTolerance
	if os.clock() - carry.startedAt < minimumTime then
		return
	end

	local podium = PlotService.FindEmptyPodium(plot)
	if not podium then
		return -- yer açılana kadar taşımaya devam eder
	end

	PlotService.PlaceUnit(podium, carry.unitId, carry.mutationId)
	EconomyService.AddStealCount(player)

	local def = Config.GetUnit(carry.unitId)

	--[[
		Seri bonusu. Art arda çalmak risk almak demek: her çalma yeni bir
		yürüyüş ve yeni bir yakalanma ihtimali. Bonus peşin para olarak
		veriliyor, kalıcı çarpan değil — çarpan olsaydı seri kırılana kadar
		biriken avantaj oyunu bozardı.
	]]
	local now = os.clock()
	local previous = streak[player]
	if previous and now - (streakAt[player] or 0) <= Config.StealStreakTimeout then
		streak[player] = previous + 1
	else
		streak[player] = 1
	end
	streakAt[player] = now

	local level = (streak[player] or 1) - 1
	local bonusRate = Config.GetStreakBonus(level)
	local payout = 0
	if bonusRate > 0 and def then
		payout = math.floor(Config.GetPrice(carry.unitId, carry.mutationId) * bonusRate)
		if payout > 0 then
			EconomyService.AddCash(player, payout)
		end
	end

	if payout > 0 then
		notify(player, string.format(
			"%s added  ·  streak x%d  +$%s",
			if def then def.name else carry.unitId,
			streak[player],
			Config.FormatCash(payout)
		), false)
	else
		notify(player, string.format("%s added to your base", if def then def.name else carry.unitId), false, "deposit")
	end

	player:SetAttribute("StealStreak", streak[player])

	BadgeService.Award(player, "FirstSteal")
	TitleService.ReportStreak(player, streak[player])
	TitleService.Check(player)
	if streak[player] >= Config.StealStreakMax then
		BadgeService.Award(player, "StreakMaster")
	end

	stopCarrying(player)
end

-- ─── Çalma ──────────────────────────────────────────────────────────────────

local function onStealPrompt(podium: Part, thief: Player)
	local victimPlot = PlotService.GetPlotFromDescendant(podium)
	if not victimPlot then
		return
	end

	local thiefPlot = PlotService.GetPlotOf(thief)
	if not thiefPlot then
		notify(thief, "You need a base first", true)
		return
	end

	if thiefPlot == victimPlot then
		notify(thief, "That is your own unit", true)
		return
	end

	if carrying[thief] then
		notify(thief, "You are already carrying one", true)
		return
	end

	if not PlotService.IsOccupied(podium) then
		return
	end

	if victimPlot:GetAttribute("Locked") then
		notify(thief, "This base is locked", true)
		return
	end

	-- Dokunulmazlık süresi kurbanın Unit Guard seviyesine göre
	local victimOwner = PlotService.GetOwner(victimPlot)
	local guardLevel = if victimOwner then UpgradeService.GetLevel(victimOwner, "UnitGuard") else 0
	local safeSeconds = Config.GetSafeSeconds(guardLevel)

	local placedAt = podium:GetAttribute("PlacedAt") :: number
	if os.clock() - placedAt < safeSeconds then
		notify(thief, "Unit is still protected", true)
		return
	end

	local cooldownLeft = Config.StealCooldown - (os.clock() - (lastStealAt[thief] or -math.huge))
	if cooldownLeft > 0 then
		notify(thief, string.format("Wait %d s", math.ceil(cooldownLeft)), true)
		return
	end

	if not PlotService.FindEmptyPodium(thiefPlot) then
		notify(thief, "No free podium - make room first", true)
		return
	end

	--[[
		Aynı kurbandan sınır. Sayaç ve engel burada, çalma anında kontrol
		ediliyor — bırakma anında olsaydı hırsız taşımaya başlayıp sonra
		reddedilirdi, bu da kafa karıştırıcı olurdu.
	]]
	if victimOwner and victimOwner ~= thief then
		local blocked = victimBlockedUntil[thief]
		local until_ = blocked and blocked[victimOwner]
		if until_ and os.clock() < until_ then
			notify(thief, string.format(
				"Too many steals from %s - try someone else (%ds)",
				victimOwner.DisplayName,
				math.ceil(until_ - os.clock())
			), true)
			return
		end
	end

	local unitId, mutationId = PlotService.ClearUnit(podium)
	if not unitId then
		return
	end

	local model = attachToBack(thief, unitId, mutationId)
	if not model then
		-- Karakter yoksa geri koy, kayıp olmasın
		PlotService.PlaceUnit(podium, unitId, mutationId)
		return
	end

	local victim = victimOwner
	carrying[thief] = {
		model = model,
		unitId = unitId,
		mutationId = mutationId,
		victim = victim,
		origin = podium.Position,
		startedAt = os.clock(),
	}
	lastStealAt[thief] = os.clock()

	-- Kurban sayacını artır, sınıra ulaşınca o kurbanı bir süre kapat
	if victimOwner and victimOwner ~= thief then
		local hits = victimHits[thief]
		if not hits then
			hits = {}
			victimHits[thief] = hits
		end
		hits[victimOwner] = (hits[victimOwner] or 0) + 1

		if hits[victimOwner] >= Config.StealsPerVictim then
			hits[victimOwner] = 0
			local blocked = victimBlockedUntil[thief]
			if not blocked then
				blocked = {}
				victimBlockedUntil[thief] = blocked
			end
			blocked[victimOwner] = os.clock() + Config.VictimCooldown
		end
	end

	local def = Config.GetUnit(unitId)
	local unitName = if def then def.name else unitId

	setupCatchPrompt(thief, model)

	notify(thief, string.format("Stole %s! Run to your base", unitName), false, "steal")
	if victim then
		alertRemote:FireClient(victim, thief.DisplayName, unitName)
		notify(victim, string.format("%s is carrying your %s - chase and press E to stop them",
			thief.DisplayName, unitName), true)
		BadgeService.Award(victim, "Victim")
		TitleService.AddRobbed(victim)
	end
end

-- ─── Promptlar ──────────────────────────────────────────────────────────────

local function setupPodiumPrompt(podium: Part)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Steal"
	prompt.ObjectText = "Be the impostor"
	prompt.HoldDuration = Config.StealHoldTime
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = podium

	--[[
		Kaidedeki karakter değiştikçe promptu güncelle. HoldDuration
		karaktere göre değiştiği için yalnızca yaratılışta ayarlamak
		yetmiyor: kaideye yeni bir karakter konduğunda öncekinin süresi
		kalırdı.
	]]
	local function refresh()
		local unitId = podium:GetAttribute("UnitId") :: string
		if unitId == "" then
			prompt.Enabled = false
			return
		end

		local mutationId = podium:GetAttribute("MutationId") :: string
		local hold = Config.GetStealHoldTime(unitId, if mutationId == "" then nil else mutationId)

		-- Hızlı Çalma pass'i kişiye özel, prompt ise herkese ortak.
		-- Burada taban süre yazılıyor; kişisel indirim tetiklenme anında
		-- PromptGuard'ın beklediği süreye yansıyor.
		prompt.HoldDuration = hold
		prompt.ObjectText = string.format("%.1fs", hold)
		prompt.Enabled = true
	end

	podium:GetAttributeChangedSignal("UnitId"):Connect(refresh)
	refresh()

	PromptGuard.Connect(prompt, function(player)
		onStealPrompt(podium, player)
	end, function(player)
		-- Hızlı Çalma pass'i olan daha kısa tutuyor
		return prompt.HoldDuration * MonetizationService.GetStealHoldMultiplier(player)
	end)
end

local function setupLockPrompt(plot: Model)
	--[[
		Prompt üssün İÇİNDEKİ kilit konsoluna bağlanıyor.

		Eskiden üssün önündeki tabeladaydı: oyuncunun üssünü kilitlemek için
		dışarı çıkıp kapının önüne gitmesi gerekiyordu, ki hırsız içerideyken
		yapılacak en son şey bu. Konsol kaidelerin yanında.

		Konsol bulunamazsa tabelaya düşülüyor — eski bir place ya da
		PlotService değişirse kilit tamamen kaybolmasın.
	]]
	local console = plot:FindFirstChild("LockConsole")
	local anchor = console and console:FindFirstChild("LockButton") or plot:FindFirstChild("Sign")
	if not (anchor and anchor:IsA("BasePart")) then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LockPrompt"
	prompt.ActionText = "Lock"
	prompt.ObjectText = string.format("%d s protection", Config.LockDuration)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	PromptGuard.Connect(prompt, function(player)
		if PlotService.GetOwner(plot) ~= player then
			notify(player, "Not your base", true)
			return
		end

		-- Güçlü Kilit pass'i süreyi uzatıp beklemeyi kısaltıyor
		local duration, cooldown = lockValuesFor(player)

		local usedAt = plot:GetAttribute("LockUsedAt") :: number
		local cooldownLeft = cooldown - (os.clock() - usedAt)
		if usedAt > 0 and cooldownLeft > 0 then
			notify(player, string.format("Lock ready in %d s", math.ceil(cooldownLeft)), true)
			return
		end

		plot:SetAttribute("Locked", true)
		plot:SetAttribute("LockUsedAt", os.clock())
		notify(player, string.format("Base locked for %d s", duration), false, "lock")

		task.delay(duration, function()
			if plot.Parent then
				plot:SetAttribute("Locked", false)
				if PlotService.GetOwner(plot) == player and player.Parent then
					notify(player, "Lock expired", true)
				end
			end
		end)
	end)
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function StealService.Start()
	notifyRemote = Net.Get("Notify")
	alertRemote = Net.Get("StealAlert")

	for _, plot in PlotService.GetAllPlots() do
		setupLockPrompt(plot)
		for _, podium in PlotService.GetPodiums(plot) do
			setupPodiumPrompt(podium)
		end
	end

	--[[
		Koşma isteği. İstemciden gelen tek şey bir bayrak; hızı sunucu
		belirliyor ve taşıyan oyuncuda yok sayıyor.
	]]
	Net.Get("Sprint").OnServerEvent:Connect(function(player, active)
		if typeof(active) ~= "boolean" then
			return
		end
		StealService.SetSprinting(player, active)
	end)

	RunService.Heartbeat:Connect(function()
		for player in carrying do
			tryDeposit(player)
		end
	end)

	local function watchCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			-- Yeniden doğan karakterde koşma bayrağı düşsün: tuşu bırakmış
			-- olabilir ve haberimiz olmaz
			sprinting[player] = nil
			humanoid.WalkSpeed = Config.NormalWalkSpeed
			humanoid.Died:Connect(function()
				returnToVictim(player)
			end)
		end)
	end

	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	Players.PlayerAdded:Connect(watchCharacter)

	Players.PlayerRemoving:Connect(function(player)
		returnToVictim(player)
		carrying[player] = nil
		sprinting[player] = nil
		lastStealAt[player] = nil
		streak[player] = nil
		streakAt[player] = nil
		victimHits[player] = nil
		victimBlockedUntil[player] = nil

		-- Çıkan oyuncu başkalarının sayaçlarında da kurban olarak duruyor
		for _, hits in victimHits do
			hits[player] = nil
		end
		for _, blocked in victimBlockedUntil do
			blocked[player] = nil
		end
	end)
end

return StealService
