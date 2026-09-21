--!strict
-- Öğretici: yeni oyuncuyu oyunun döngüsünden sırayla geçirir.
--
-- Neden gerekli: oyunun hiçbir yerinde konveyörün ne olduğu, kaidenin ne
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
-- Kilit adımının tabanı: üssü devralan oyuncu, önceki sahibinin kilidiyle
-- adımı geçmesin diye adım başladığında o anki değeri kaydediyoruz
local lockBaseline: { [Player]: { plot: Model, at: number } } = {}
local lastSkipAt: { [Player]: number } = {}
local paused = false

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError)
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

	elseif check == "steals" then
		return profile.stolen

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

	elseif check == "locksUsed" then
		--[[
			Kilidin kendisi profilde tutulmuyor (StealService plot niteliğine
			os.clock yazıyor, oturumla birlikte sıfırlanıyor). Bu yüzden
			"kilit kullanıldı" bilgisini mutlak değerle değil, adım
			başladığındaki değere göre ölçüyoruz.
		]]
		local plot = PlotService.GetPlotOf(player)
		if not plot then
			return 0
		end

		local usedAt = (plot:GetAttribute("LockUsedAt") :: number?) or 0
		local baseline = lockBaseline[player]

		if not baseline or baseline.plot ~= plot then
			lockBaseline[player] = { plot = plot, at = usedAt }
			return 0
		end

		return if usedAt > baseline.at then 1 else 0
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

	if hint == "Conveyor" then
		return plot and plot:FindFirstChild("Conveyor")

	elseif hint == "Sign" then
		return plot and plot:FindFirstChild("Sign")

	elseif hint == "Upgrades" then
		if not plot then
			return nil
		end
		-- İlk yükseltme tablosu yeterli; hepsi yan yana duruyor
		for _, child in plot:GetChildren() do
			if string.sub(child.Name, 1, 8) == "Upgrade_" then
				return child
			end
		end
		return nil

	elseif hint == "Wheel" then
		local decor = workspace:FindFirstChild("Decor")
		return decor and decor:FindFirstChild("Wheel")

	elseif hint == "RivalPlot" then
		-- Sahibi olan başka bir üs; yoksa boş bir üs de iş görür çünkü
		-- oyuncunun oraya gitmesi yeterli
		local fallback: Model? = nil
		for _, other in PlotService.GetAllPlots() do
			if other ~= plot then
				if PlotService.GetOwner(other) then
					return other
				end
				fallback = fallback or other
			end
		end
		return fallback
	end

	return nil
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

	-- Arayüz henüz bağlı değilse öğretici yine de anlaşılsın diye adım
	-- değiştiğinde metni bildirim olarak da gönderiyoruz. Adım başına bir
	-- kez, yani toplamda altı mesaj.
	if isNewStep then
		notify(player, string.format("[%d/%d] %s - %s",
			index, stepCount(), step.title, step.text), false)
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
		if not step or checkValue(player, step.check) < step.goal then
			break
		end

		profile.tutorialStep += 1
		advanced = true

		if step.reward > 0 then
			EconomyService.AddCash(player, step.reward)
			notify(player, string.format("Step complete: %s  ·  +$%s",
				step.title, Config.FormatCash(step.reward)), false)
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
			"Tutorial complete! +$%s  ·  You know the job now, Crewmate.",
			Config.FormatCash(bonus)), false)
	end

	if advanced then
		lockBaseline[player] = nil
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
	lockBaseline[player] = nil
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

	local played = profile.stolen > 0
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

			-- Üs verilene kadar bekle: ilk adımın hedefi konveyör ve
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
		lockBaseline[player] = nil
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
