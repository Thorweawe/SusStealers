--!strict
-- Görevler: 30 dakikalık, 3 saatlik ve günlük hedefler.
--
-- Neden gerekli: gelir üretmek pasif bir döngü. "Şimdi ne yapayım"
-- sorusunun cevabı yoksa oyun açık bırakılan bir sekmeye dönüşüyor.
--
-- Nasıl çalışıyor: her vadenin bir penceresi var. Pencere dolunca görevler
-- yeniden çekiliyor. İlerleme profildeki artan sayaçların farkından
-- hesaplanıyor — görev verilirken sayacın o anki değeri taban alınıyor.
-- Bu yüzden hiçbir servis bu modülü çağırmıyor; bağımlılık tek yönlü.
--
-- Ödüller gelirle ölçekli, çünkü sabit tutar geç oyunda anlamsız kalıyor.
-- Günlük vadenin tamamını bitiren ayrıca bir iksir alıyor: Robux
-- pass'lerinin süreli karşılığı, envantere giriyor, kalıcı değil.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PotionService = require(script.Parent.PotionService)
local MonetizationService = require(script.Parent.MonetizationService)

local QuestService = {}

local POLL_INTERVAL = 2

local questsRemote: RemoteEvent
local notifyRemote: RemoteEvent
local paused = false

local rng = Random.new()

-- Aynı yükü tekrar tekrar göndermemek için son gönderilen imza
local lastSignature: { [Player]: string } = {}

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "quest"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
QuestService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
	end
end

-- ─── Sayaçlar ───────────────────────────────────────────────────────────────

--[[
	Görevin baktığı sayacın anlık değeri.

	Hepsi yalnızca artıyor. İlerleme bu değerin, görev verilirken alınan
	tabandan farkı. Azalan bir sayaç eklenirse ilerleme geri gider ve
	tamamlanmış görev tamamlanmamışa döner — o yüzden yeni sayaç eklerken
	artan olduğundan emin ol.
]]
local function statValue(player: Player, stat: string): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end

	if stat == "stolen" then
		return profile.stolen
	elseif stat == "bought" then
		return profile.bought
	elseif stat == "sold" then
		return profile.sold
	elseif stat == "earned" then
		return profile.earned
	elseif stat == "caught" then
		return profile.caught
	elseif stat == "spins" then
		return profile.spins
	elseif stat == "rebirths" then
		return profile.rebirths
	elseif stat == "upgrades" then
		local bought = 0
		for _, level in profile.upgrades do
			if level > 0 then
				bought += 1
			end
		end
		return bought
	end

	return 0
end

-- ─── Görev çekme ────────────────────────────────────────────────────────────

--[[
	Bir vade için yeni görevler çeker ve pencereyi başlatır.

	Hedefler çekim anındaki gelire göre hesaplanıp donduruluyor. Canlı
	hesaplansaydı oyuncu zenginleştikçe hedef büyür, görev hiç bitmezdi.
]]
local function rollTier(player: Player, tier: Config.QuestTier)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local income = EconomyService.GetIncome(player)
	local entries: { DataService.QuestEntry } = {}

	for _, def in Config.RollQuests(rng, tier) do
		table.insert(entries, {
			id = def.id,
			goal = math.max(1, Config.GetQuestGoal(def, tier, income)),
			baseline = statValue(player, def.stat),
			done = false,
			claimed = false,
		})
	end

	profile.quests[tier.id] = {
		expiresAt = os.time() + tier.seconds,
		entries = entries,
	}
end

--[[ Süresi dolmuş ya da hiç olmayan vadeleri yeniler. ]]
local function refreshExpired(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local now = os.time()
	local changed = false

	for _, tier in Config.QuestTiers do
		local slot = profile.quests[tier.id]
		if not slot or #slot.entries == 0 or slot.expiresAt <= now then
			rollTier(player, tier)
			changed = true
		end
	end

	return changed
end

-- ─── Günlük bonus ───────────────────────────────────────────────────────────

--[[
	Günlük vadenin tamamını bitirene verilen ek ödül: bir iksir.

	Envantere giriyor, anında uygulanmıyor — oyuncu ne zaman işine
	geliyorsa o zaman içiyor. Envanteri doluysa (Config.PotionStackLimit)
	Grant false dönüyor ve bonus verilmemiş sayılıyor; bildirimde de öyle
	yazıyor ki oyuncu ödülü kaybettiğini sanmasın.
]]
local function grantDailyBonus(player: Player): string?
	local def = Config.RollPotion(rng)

	if not PotionService.Grant(player, def.id) then
		notify(player, string.format(
			"All daily quests complete! Your %s stack is full - use one to make room",
			def.name), true)
		return nil
	end

	return string.format("%s potion (%s)", def.name, Config.FormatDuration(def.seconds))
end

-- ─── İlerleme ───────────────────────────────────────────────────────────────

--[[
	Vadedeki bütün görevlerin ödülü TESLİM ALINDI mı.

	done değil claimed'e bakıyor: günlük bonus, oyuncu ödüllerini
	topladığında gelmeli. Sadece koşulların sağlanmasına baksaydı oyuncu
	panele hiç dokunmadan bonusu alırdı ve "kendi alsın" isteği anlamsız
	kalırdı.
]]
local function tierComplete(slot: DataService.QuestSlot): boolean
	for _, entry in slot.entries do
		if not entry.claimed then
			return false
		end
	end
	return #slot.entries > 0
end

--[[
	Tamamlanan görevleri işaretler ve ödülleri verir.

	Ödül gelirle ölçekli ve ödeme anındaki gelire bakıyor: görev çekilirken
	hesaplansaydı, üç saat boyunca büyüyen bir oyuncu üç saat önceki
	gelirine göre ödüllenirdi.
]]
function QuestService.Check(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local changed = refreshExpired(player)

	for _, tier in Config.QuestTiers do
		local slot = profile.quests[tier.id]
		if not slot then
			continue
		end

		for _, entry in slot.entries do
			if entry.done then
				continue
			end

			local def = Config.GetQuest(entry.id)
			if not def then
				-- Config'ten kalkmış görev: teslim alınmış say, oyuncu vadeyi
				-- asla bitiremez hale gelmesin
				entry.done = true
				entry.claimed = true
				changed = true
				continue
			end

			local progress = statValue(player, def.stat) - entry.baseline
			if progress < entry.goal then
				continue
			end

			entry.done = true
			changed = true

			--[[
				ÖDÜL BURADA VERİLMİYOR. Görev tamamlandı olarak işaretleniyor
				ve oyuncu panelden kendi topluyor (QuestService.Claim).

				Neden: otomatik ödülde oyuncu görevleri hiç okumuyordu, ekranın
				kenarında bir bildirim geçiyor ve bitiyordu. Toplamak için
				panele bakmak gerekince görevler görünür hale geliyor.
			]]
			notify(player, string.format(
				"%s quest ready to claim: %s",
				tier.name,
				string.format(def.text, Config.FormatQuestGoal(def, entry.goal))
			), false)
		end

	end

	-- Süresi biten takviyenin niteliği kalmasın; panel "bitti" yazmasın.
	-- Vade döngüsünün dışında: oyuncu başına bir kez yeter.
	if player:GetAttribute("BoostName") ~= nil
		and MonetizationService.GetBoostRemaining(player, "income") <= 0
		and MonetizationService.GetBoostRemaining(player, "steal") <= 0
		and MonetizationService.GetBoostRemaining(player, "lock") <= 0
	then
		player:SetAttribute("BoostName", nil)
		player:SetAttribute("BoostUntil", nil)
	end

	if changed then
		DataService.RequestSave(player)
	end

	QuestService.Publish(player, changed)
end

--[[
	Tamamlanmış bir görevin ödülünü teslim eder.

	Koşulu istemci belirlemiyor: sunucu zaten Check içinde done işaretledi,
	burası yalnızca "henüz alınmamış mı" diye bakıp ödüyor. İstemciden
	gelen tek şey hangi vade ve hangi görev.

	Ödül TESLİM ANINDAKİ gelire göre: görev çekilirken hesaplansaydı üç
	saatte büyüyen oyuncu üç saat önceki gelirine göre ödüllenirdi.
]]
function QuestService.Claim(player: Player, tierId: string, questId: string): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local tier = Config.GetQuestTier(tierId)
	local slot = profile.quests[tierId]
	if not (tier and slot) then
		return false
	end

	for _, entry in slot.entries do
		if entry.id ~= questId then
			continue
		end

		if not entry.done then
			notify(player, "That quest is not finished yet", true)
			return false
		end

		if entry.claimed then
			-- Sessiz: çift tıklama ya da gecikmiş paket, hata değil
			return false
		end

		entry.claimed = true

		local reward = Config.GetQuestReward(tier, EconomyService.GetIncome(player))
		EconomyService.AddCash(player, reward)

		local def = Config.GetQuest(questId)
		notify(player, string.format(
			"%s  ·  +$%s",
			if def then string.format(def.text, Config.FormatQuestGoal(def, entry.goal)) else questId,
			Config.FormatCash(reward)
		), false)

		--[[
			Günlük vadenin tamamı teslim alındıysa bonus da burada veriliyor.
			Check içinde olsaydı oyuncu son ödülü almadan bonusu alırdı.
		]]
		if tierId == "daily" and tierComplete(slot) then
			local granted = grantDailyBonus(player)
			if granted then
				notify(player, string.format(
					"All daily quests claimed! Bonus: %s", granted
				), false)
			end
		end

		DataService.RequestSave(player)
		QuestService.Publish(player, true)
		return true
	end

	return false
end

-- ─── Yayın ──────────────────────────────────────────────────────────────────

--[[
	Görev panelinin çizdiği veri. İmza değişmediyse göndermiyor; iki
	saniyede bir dönen döngü ağ trafiği yaratmasın.
]]
function QuestService.Publish(player: Player, force: boolean?)
	local profile = DataService.Get(player)
	if not (profile and questsRemote) then
		return
	end

	local now = os.time()
	local payload = {}
	local signature = {}

	for _, tier in Config.QuestTiers do
		local slot = profile.quests[tier.id]
		if not slot then
			continue
		end

		local entries = {}
		for _, entry in slot.entries do
			local def = Config.GetQuest(entry.id)
			if not def then
				continue
			end

			local value = math.clamp(
				statValue(player, def.stat) - entry.baseline,
				0, entry.goal
			)

			table.insert(entries, {
				id = entry.id,
				text = string.format(def.text, Config.FormatQuestGoal(def, entry.goal)),
				value = value,
				goal = entry.goal,
				done = entry.done,
				claimed = entry.claimed,
				cash = def.incomeSeconds ~= nil,
			})

			table.insert(signature, string.format("%s%d%s%s",
				entry.id, value,
				if entry.done then "d" else "",
				if entry.claimed then "c" else ""))
		end

		table.insert(payload, {
			id = tier.id,
			name = tier.name,
			secondsLeft = math.max(0, slot.expiresAt - now),
			reward = Config.GetQuestReward(tier, EconomyService.GetIncome(player)),
			entries = entries,
		})
	end

	local joined = table.concat(signature, "|")
	if not force and lastSignature[player] == joined then
		return
	end
	lastSignature[player] = joined

	questsRemote:FireClient(player, payload)
end

-- ─── Test kancası ───────────────────────────────────────────────────────────

--[[
	Arka plan taramasını durdurur. TitleService.SetPaused ile aynı sebep:
	testler profili doğrudan değiştirirken tarama araya girmemeli.
]]
function QuestService.SetPaused(value: boolean)
	paused = value
end

--[[ Testler için: bir vadeyi zorla yeniden çeker. ]]
function QuestService.RollTier(player: Player, tierId: string): boolean
	local tier = Config.GetQuestTier(tierId)
	if not tier then
		return false
	end
	rollTier(player, tier)
	return true
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function QuestService.Start()
	questsRemote = Net.Get("Quests")
	notifyRemote = Net.Get("Notify")

	--[[
		Teslim alma isteği. İstemciden gelen iki metin; ikisi de sunucuda
		aranıyor ve görev tamamlanmamışsa reddediliyor. Sel basmasın diye
		bekletme var.
	]]
	local claimRemote = Net.Get("QuestClaim")
	local lastClaimAt: { [Player]: number } = {}

	claimRemote.OnServerEvent:Connect(function(player, tierId, questId)
		if typeof(tierId) ~= "string" or typeof(questId) ~= "string" then
			return
		end
		if #tierId > 32 or #questId > 32 then
			return
		end

		local now = os.clock()
		if now - (lastClaimAt[player] or 0) < 0.2 then
			return
		end
		lastClaimAt[player] = now

		QuestService.Claim(player, tierId, questId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastClaimAt[player] = nil
	end)

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			if not DataService.WaitForProfile(player) or player.Parent == nil then
				return
			end

			-- Üs verilene kadar bekle: gelir hesabı ona bağlı ve hedefler
			-- çekim anındaki gelire göre donuyor
			for _ = 1, 20 do
				if PlotService.GetPlotOf(player) then
					break
				end
				task.wait(0.5)
			end

			QuestService.Check(player)
			QuestService.Publish(player, true)
		end)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		lastSignature[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			if paused then
				continue
			end
			for _, player in Players:GetPlayers() do
				QuestService.Check(player)
			end
		end
	end)
end

return QuestService
