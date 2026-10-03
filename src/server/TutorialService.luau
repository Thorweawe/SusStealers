--!strict
-- Öğretici: yeni oyuncuyu oyunun döngüsünden sırayla geçirir.
--
-- Neden gerekli: oyunun hiçbir yerinde uzaydan nasıl çalınacağı, kaidenin ne
-- işe yaradığı ya da başkasından nasıl çalınacağı yazmıyor. Bu türde
-- oyuncu ilk iki dakikada döngüyü çözemezse çıkıyor.
--
-- Nasıl çalışıyor: adımlar Config.Tutorial'da veri olarak duruyor, burada
-- sadece koşullar hesaplanıyor. Koşullar zaten var olan durumdan okunuyor
-- (profil sayaçları, üs nitelikleri) — hiçbir servis bu modülü çağırmıyor,
-- yani bağımlılık tek yönlü ve öğretici kaldırılsa oyun aynen çalışır.
--
-- İlerleme profilde bir sayı: tamamlanan adım sayısı. Adımlar sıralı
-- olduğu için bu yeterli ve tamamlanan adım oturum değişse de geri gelmiyor.
--
-- İstemci tarafı: "Tutorial" remote'u mevcut adımı ve hedef nesneyi
-- gönderiyor, arayüzü istemci çiziyor. Arayüz hiç bağlanmasa bile adımlar
-- Notify üzerinden metin olarak geliyor, yani öğretici tek başına ayakta.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local TutorialService = {}

local SKIPPED = -1
local POLL_INTERVAL = 1
local SKIP_DEBOUNCE = 2

local tutorialRemote: RemoteEvent
local notifyRemote: RemoteEvent

-- Aynı yükü tekrar tekrar göndermemek için son gönderilen imza
local lastSignature: { [Player]: string } = {}
local lastIndex: { [Player]: number } = {}
local lastSkipAt: { [Player]: number } = {}
local paused = false

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "tutorial"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
TutorialService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
	end
end

-- ─── Koşullar ───────────────────────────────────────────────────────────────

--[[
	Adımın baktığı sayacın anlık değeri. Bilinmeyen isim 0 dönüyor ki
	Config'e yanlış yazılmış bir adım oyunu kilitlemek yerine sadece
	ilerlemesin ve fark edilsin.
]]
local function checkValue(player: Player, check: string): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end

	if check == "units" then
		return #profile.units

	elseif check == "trainings" then
		return profile.trainings

	elseif check == "bestPlanet" then
		return profile.bestPlanet

	elseif check == "upgrades" then
		local bought = 0
		for _, level in profile.upgrades do
			if level > 0 then
				bought += 1
			end
		end
		return bought

	elseif check == "spins" then
		return if profile.lastSpinAt > 0 then 1 else 0

	elseif check == "tasks" then
		-- Oturumda biten görevler (TaskService bekleme bitişini nitelik olarak yazıyor)
		local done = 0
		for _, def in Config.Tasks do
			if player:GetAttribute("TaskReady_" .. def.id) ~= nil then
				done += 1
			end
		end
		return done

	elseif check == "pets" then
		-- Bir kez bile çıkmış petler (otomatik silinen de sayılıyor)
		local found = 0
		for _ in profile.petsFound do
			found += 1
		end
		return found

	elseif check == "salvaged" then
		return profile.salvaged or 0

	elseif check == "spaceSpeed" then
		-- Kapsülde antrenman (CapsuleService); tam sayıya yuvarlanmış
		return math.floor(profile.spaceSpeed)

	elseif check == "jetpacks" then
		-- Satın alınan jetpack'ler (başlangıç paketi sayılmıyor)
		local owned = 0
		for _, has in profile.jetpacks do
			if has then
				owned += 1
			end
		end
		return owned

	elseif check == "defenseWaves" then
		-- Gezegen savunmasında dayanılan en uzun dalga (DefenseService)
		return if profile.defense then (profile.defense.bestWave or 0) else 0

	elseif check == "gear" then
		local owned = 0
		for _, has in profile.gear do
			if has then
				owned += 1
			end
		end
		return owned
	end

	return 0
end

-- ─── Hedef nesne ────────────────────────────────────────────────────────────

--[[
	İstemcinin ok ya da ışın çizeceği nesne. Bulunamazsa nil — arayüz o
	zaman sadece metni gösteriyor, hata vermiyor.
]]
local function targetFor(player: Player, hint: string): Instance?
	local plot = PlotService.GetPlotOf(player)

	if hint == "SpaceGate" then
		-- Launch Bay'deki kalkış pedi (SpaceService kuruyor)
		local zone = workspace:FindFirstChild("SpaceZone")
		local bay = zone and zone:FindFirstChild("LaunchBay")
		return bay and bay:FindFirstChild("LaunchPad")

	elseif hint == "Capsule" then
		local capsule = plot and plot:FindFirstChild("Capsule")
		return capsule and (capsule:FindFirstChild("Pad") or capsule)

	elseif hint == "JetpackStand" then
		-- Launch Bay güvertesindeki jetpack dükkânı (JetpackService kuruyor)
		local zone = workspace:FindFirstChild("SpaceZone")
		local bay = zone and zone:FindFirstChild("LaunchBay")
		local stand = bay and bay:FindFirstChild("JetpackStand")
		return stand and (stand:FindFirstChild("Counter") or stand)

	elseif hint == "Upgrades" then
		-- Yükseltmeler ayrı tabelalardan tek bir kulübeye taşındı
		return plot and plot:FindFirstChild("UpgradeBooth")

	elseif hint == "Wheel" then
		local decor = workspace:FindFirstChild("Decor")
		return decor and decor:FindFirstChild("Wheel")

	elseif string.sub(hint, 1, 6) == "Planet" then
		-- Uzaydaki gezegen (SpaceService "PlanetN"); hedef tepedeki canavar
		local zone = workspace:FindFirstChild("SpaceZone")
		local planets = zone and zone:FindFirstChild("Planets")
		local planet = planets and planets:FindFirstChild(hint)
		return planet and (planet:FindFirstChild("Planet") or planet)

	elseif hint == "Task" then
		-- Config.Tasks sırasındaki ilk konsol (haritada TaskId niteliği)
		local decor = workspace:FindFirstChild("Decor")
		if decor then
			for _, def in Config.Tasks do
				for _, part in decor:GetDescendants() do
					if part:IsA("BasePart") and part:GetAttribute("TaskId") == def.id then
						return part
					end
				end
			end
		end
		return nil

	elseif hint == "Hatchery" then
		local decor = workspace:FindFirstChild("Decor")
		local hatchery = decor and decor:FindFirstChild("Hatchery", true)
		return hatchery and (hatchery:FindFirstChild("Egg1") or hatchery)

	elseif hint == "GearShop" then
		-- Klasörün kendisi vurgulanamıyor; dükkân tezgâhındaki ilk promptun parçası
		local decor = workspace:FindFirstChild("Decor")
		local shop = decor and decor:FindFirstChild("GearShop", true)
		local prompt = shop and shop:FindFirstChild("GearPrompt", true)
		return if prompt then prompt.Parent else shop
	end

	return nil
end

--[[ Testler için: hint -> dünyadaki hedef. ]]
function TutorialService._TargetFor(player: Player, hint: string): Instance?
	return targetFor(player, hint)
end

-- ─── Durum yayını ───────────────────────────────────────────────────────────

local function stepCount(): number
	return #Config.Tutorial
end

--[[ Oyuncunun öğreticisi bitmiş ya da atlanmış mı. ]]
function TutorialService.IsFinished(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile then
		return true
	end
	return profile.tutorialStep == SKIPPED or profile.tutorialStep >= stepCount()
end

--[[ Sıradaki adım. Öğretici bittiyse nil. ]]
function TutorialService.GetStep(player: Player): Config.TutorialStep?
	local profile = DataService.Get(player)
	if not profile or TutorialService.IsFinished(player) then
		return nil
	end
	return Config.GetTutorialStep(profile.tutorialStep + 1)
end

--[[
	Mevcut durumu istemciye gönderir. İmza değişmediyse göndermiyor;
	saniyede bir çalışan döngünün ağ trafiği yaratmaması için.
]]
local function publish(player: Player, force: boolean?)
	local step = TutorialService.GetStep(player)

	if not step then
		local signature = "done"
		if not force and lastSignature[player] == signature then
			return
		end
		lastSignature[player] = signature
		lastIndex[player] = nil
		player:SetAttribute("TutorialStep", stepCount())

		if tutorialRemote then
			tutorialRemote:FireClient(player, { active = false })
		end
		return
	end

	local profile = DataService.Get(player)
	local index = if profile then profile.tutorialStep + 1 else 1
	local value = math.min(checkValue(player, step.check), step.goal)

	local signature = string.format("%d/%d", index, value)
	if not force and lastSignature[player] == signature then
		return
	end

	local isNewStep = lastIndex[player] ~= index
	lastSignature[player] = signature
	lastIndex[player] = index
	player:SetAttribute("TutorialStep", index - 1)

	if tutorialRemote then
		tutorialRemote:FireClient(player, {
			active = true,
			index = index,
			total = stepCount(),
			id = step.id,
			title = step.title,
			text = step.text,
			hint = step.hint,
			reward = step.reward,
			value = value,
			goal = step.goal,
		}, targetFor(player, step.hint))
	end

	--[[
		Eskiden yeni adımın uzun metni ayrıca bildirim olarak da gidiyordu.
		Öğretici kartı (TutorialUI) aynı metni zaten gösteriyor; alttaki
		ikinci kopya ekranı dolduruyordu. Yalnızca kısa bir başlık.
	]]
	if isNewStep and index > 1 then
		notify(player, string.format("Next: %s", step.title), false)
	end
end

-- ─── İlerleme ───────────────────────────────────────────────────────────────

--[[
	Sıradaki adımın koşulu sağlandıysa ilerletir ve ödülü verir.

	Döngüde birden fazla adım tamamlanmış olabilir (örneğin iki karakteri
	arka arkaya alan oyuncu), o yüzden while.
]]
function TutorialService.Check(player: Player)
	local profile = DataService.Get(player)
	if not profile or TutorialService.IsFinished(player) then
		publish(player)
		return
	end

	local advanced = false

	while true do
		local step = Config.GetTutorialStep(profile.tutorialStep + 1)
		if not step then
			break
		end
		local done = checkValue(player, step.check) >= step.goal
		if not done then
			break
		end

		profile.tutorialStep += 1
		advanced = true

		-- Hediye uzay hızı (Config.TutorialStep.speed)
		local speedGift = step.speed or 0
		if speedGift > 0 then
			local CapsuleService = require(script.Parent.CapsuleService) :: any
			CapsuleService.SetSpeed(player, CapsuleService.GetSpeed(player) + speedGift)
		end
		local speedText = if speedGift > 0 then string.format("  ·  +%d Space Speed", speedGift) else ""
		if step.reward > 0 then
			EconomyService.AddCash(player, step.reward)
			notify(player, string.format("Step complete: %s  ·  +$%s%s",
				step.title, Config.FormatCash(step.reward), speedText), false)
		else
			notify(player, string.format("Step complete: %s", step.title), false)
		end
	end

	if advanced and profile.tutorialStep >= stepCount() then
		local bonus = Config.TutorialFinishBonus
		if bonus > 0 then
			EconomyService.AddCash(player, bonus)
		end
		notify(player, string.format(
			"Tutorial complete! +$%s  ·  Tip: two of the same crewmate MERGE into a stronger one (F on a podium)!",
			Config.FormatCash(bonus)), false)
	end

	if advanced then
		DataService.RequestSave(player)
	end

	publish(player, advanced)
end

--[[
	Öğreticiyi kapatır. Kalan ödüller yanıyor — atlamak bir kısayol değil,
	bilenler için bir sessizlik düğmesi.
]]
function TutorialService.Skip(player: Player)
	local profile = DataService.Get(player)
	if not profile or TutorialService.IsFinished(player) then
		return
	end

	profile.tutorialStep = SKIPPED
	DataService.RequestSave(player)

	notify(player, "Tutorial skipped", false)
	publish(player, true)
end

--[[
	Kaydı olan eski oyuncuyu öğreticiye sokmaz.

	tutorialStep alanı sonradan eklendi; onsuz kaydedilmiş her profil 0
	ile geliyor. Bunları öğreticiye sokmak hem saçma hem de zaten yaptıkları
	işler için ödül dağıtırdı. Oynadığına dair herhangi bir iz varsa
	öğretici bitmiş sayılıyor, ödül verilmeden.
]]
function TutorialService.SkipIfVeteran(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile or profile.tutorialStep ~= 0 then
		return false
	end

	local played = profile.salvaged > 0
		or profile.rebirths > 0
		or #profile.units > 0
		or profile.lastSpinAt > 0
		or next(profile.upgrades) ~= nil
		or profile.cash > Config.StartingCash

	if not played then
		return false
	end

	profile.tutorialStep = stepCount()
	return true
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

--[[
	Arka plan taramasını durdurur. TitleService.SetPaused ile aynı sebep:
	testler profili doğrudan değiştirirken tarama araya girmemeli.
]]
--[[ Durumu zorla yeniden yayınlar (profil dışarıdan değiştiğinde: testlerin geri yüklemesi). ]]
function TutorialService.Refresh(player: Player)
	publish(player, true)
end

function TutorialService.SetPaused(value: boolean)
	paused = value
end

function TutorialService.Start()
	tutorialRemote = Net.Get("Tutorial")
	notifyRemote = Net.Get("Notify")

	-- Yalnızca TutorialSkip dinleniyor. "Tutorial" tek yönlü kalıyor ki
	-- istemci onu tetikleyemesin.
	local skipRemote = Net.Get("TutorialSkip")
	skipRemote.OnServerEvent:Connect(function(player)
		-- Bu remote hiçbir şey vermiyor; tek etkisi oyuncunun kendi
		-- öğreticisini kapatması. Yine de sel basmasın diye bekletme var.
		local now = os.clock()
		if now - (lastSkipAt[player] or 0) < SKIP_DEBOUNCE then
			return
		end
		lastSkipAt[player] = now
		TutorialService.Skip(player)
	end)

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			if not DataService.WaitForProfile(player) then
				return
			end
			if player.Parent == nil then
				return
			end

			TutorialService.SkipIfVeteran(player)

			-- Üs verilene kadar bekle: ilk adımlar karakteri üsse getirmek,
			-- üs yoksa oyuncu zaten hiçbir şey yapamıyor
			for _ = 1, 20 do
				if PlotService.GetPlotOf(player) then
					break
				end
				task.wait(0.5)
			end

			publish(player, true)
		end)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		lastSignature[player] = nil
		lastIndex[player] = nil
		lastSkipAt[player] = nil
	end)

	--[[
		Koşullar olay yayını yapmıyor; tarama en ucuz çözüm. Yalnızca
		öğreticisi bitmemiş oyuncular geziliyor, yani birkaç saniye sonra
		döngü pratikte boşa dönüyor.
	]]
	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			if paused then
				continue
			end
			for _, player in Players:GetPlayers() do
				if not TutorialService.IsFinished(player) then
					TutorialService.Check(player)
				end
			end
		end
	end)
end

return TutorialService
