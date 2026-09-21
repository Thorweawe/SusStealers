--!strict
-- Tüm oyun dengesi burada. Yeni karakter / mutasyon eklemek için sadece bu dosya.

local Config = {}

-- ─── Dünya ──────────────────────────────────────────────────────────────────
Config.PlotCount = 8
Config.PodiumsPerPlot = 8
Config.PlotSize = Vector3.new(60, 2, 44)
Config.PodiumSpacing = 6.5

--[[
	Üsler ızgara halinde diziliyor: soldan sağa PlotColumns tane, sonra alt
	satıra geçiliyor. Tek sıra istersen PlotColumns'u PlotCount'a eşitle.

	Tek sıra (8x1) harita 644x108 stud'luk bir şerit yapıyordu; 25:1 oranında
	her şey yassı görünüyor, duvar ve pencere gibi detaylar kayboluyordu.
	4x2 ızgarada harita derinleşiyor ve istasyon gibi duruyor.

	Boşluklar üs ölçüsünden büyük olmalı, yoksa üsler bitişik görünür:
	PlotSpacing - PlotSize.X = yanal boşluk, PlotRowSpacing - PlotSize.Z = dikey.
]]
Config.PlotColumns = 4
Config.PlotSpacing = 92        -- yanal boşluk 32 stud
Config.PlotRowSpacing = 84     -- dikey boşluk 40 stud

-- ─── Ekonomi ────────────────────────────────────────────────────────────────
Config.StartingCash = 250
Config.IncomeInterval = 1

-- ─── Konveyör ───────────────────────────────────────────────────────────────
Config.ConveyorInterval = 10   -- kaç saniyede bir yeni karakter gelir
Config.ConveyorLifetime = 22   -- alınmazsa kaç saniye sonra kaybolur
Config.ConveyorSpeed = 6

-- ─── Çalma ──────────────────────────────────────────────────────────────────
Config.StealHoldTime = 4.0     -- prompt kaç saniye basılı tutulur
Config.StealCooldown = 18      -- bir çalmadan sonra oyuncunun bekleme süresi
-- Taşırken yavaşlık çalmanın bedeli: hırsız savunmasız ve yakalanabilir
-- olmalı. 11 fazla hızlıydı, kurban fark ettiğinde yetişemiyordu.
Config.CarryWalkSpeed = 8      -- karakter taşırken hız
Config.NormalWalkSpeed = 16
Config.SafeSeconds = 8         -- yeni yerleştirilen karakter kaç sn çalınamaz

-- Çalınan karakter, çalındığı yerden üsse taşınırken en az bu oranda
-- yürüme süresi geçmiş olmalı. Karakterin konumu istemcinin elinde
-- olduğu için ışınlanan biri yürüyüşü tamamen atlayabiliyordu; çalmanın
-- bütün riski o yürüyüşte. 1.0 = tam yürüme süresi (çok sıkı, eğim ve
-- kestirme yüzünden meşru oyuncu takılır), 0 = kontrol kapalı.
Config.CarryTravelTolerance = 0.7

-- ─── Çalma serisi ───────────────────────────────────────────────────────────
--[[
	Art arda başarılı çalma bonus veriyor. Risk almayı ödüllendiriyor: her
	çalma yeni bir yürüyüş, yeni bir yakalanma ihtimali. Seri bozulunca
	sıfırlanıyor, yani biriktirdiğin bonus da gidiyor — devam etmek cazip
	ama pahalı.

	Bonus bırakma anında peşin para olarak veriliyor, gelire eklenmiyor:
	kalıcı çarpan olsaydı seri kırılana kadar biriken avantaj oyunu bozardı.
]]
Config.StealStreakStep = 0.05      -- seri başına bonus (%5)
Config.StealStreakMax = 5          -- bundan sonrası bonus artırmıyor
Config.StealStreakTimeout = 180    -- bu kadar çalmazsan seri sıfırlanır

--[[
	Aynı kurbandan çalma sınırı. Yoksa iki arkadaş birbirinden sonsuz çalıp
	sıralamayı sahteliyor; rekabetin anlamı kalmıyor. Sınıra ulaşınca o
	kurban bir süre kapalı kalıyor, hırsız başka hedef aramak zorunda.
]]
Config.StealsPerVictim = 5
Config.VictimCooldown = 600        -- 10 dakika

--[[ Seri seviyesine göre bonus çarpanı. 0. seride bonus yok. ]]
function Config.GetStreakBonus(streak: number): number
	return math.min(streak, Config.StealStreakMax) * Config.StealStreakStep
end

-- ─── Hırsızı yakalama ───────────────────────────────────────────────────────
--[[
	Kurban, karakterini taşıyan hırsızın yanına gidip onu durdurabiliyor.
	Çalmanın karşı hamlesi bu: eskiden kurban çalındığını görüyor ama
	yapabileceği bir şey yoktu, sadece kilidi kalıyordu.

	Engel süresini 3 dakika seçtim. Çalma beklemesi 18 saniye, yani
	yakalanan hırsız senden on tur boyunca çalamıyor — caydırıcı ama
	oyundan kopartmıyor. Başkalarından çalmaya devam edebiliyor, ceza
	yalnızca yakalayan kurbana özel.
]]
Config.CatchHoldTime = 1.5         -- yakalama promptu kaç sn basılı tutulur
Config.CatchRange = 14             -- kaç studdan yakalanabilir
Config.CatchBlockDuration = 180    -- yakalanan hırsız kurbandan kaç sn çalamaz

-- ─── Şans çarkı ─────────────────────────────────────────────────────────────
--[[
	Günde bir bedava çevirme, fazlası Robux ile. Ödüller sabit tutar değil,
	oyuncunun kendi gelirinin katı: sabit olsaydı geç oyunda anlamsızlaşır,
	erken oyunda dengeyi bozardı. Taban değerler yeni oyuncu için.

	Her dilimde bir şey çıkıyor, boş dilim yok.
]]
Config.SpinCooldownHours = 24
Config.SpinDuration = 4            -- çark kaç saniye hızlı döner

export type SpinReward = {
	id: string,
	name: string,
	weight: number,
	kind: string,            -- cash | spawn | mutation | unit
	incomeSeconds: number?,  -- cash: kaç saniyelik gelir
	minimum: number?,        -- cash: taban tutar
}

Config.SpinRewards = {
	{ id = "SmallCash",  name = "Cash",              weight = 40, kind = "cash",     incomeSeconds =  60, minimum =   1000 },
	{ id = "MedCash",    name = "Big Cash",          weight = 25, kind = "cash",     incomeSeconds = 300, minimum =  10000 },
	{ id = "Spawn",      name = "Instant Spawn",     weight = 15, kind = "spawn" },
	{ id = "Mutation",   name = "Guaranteed Mutation", weight = 12, kind = "mutation" },
	{ id = "HugeCash",   name = "Huge Cash",         weight =  6, kind = "cash",     incomeSeconds = 900, minimum = 100000 },
	{ id = "FreeUnit",   name = "Free Unit",         weight =  2, kind = "unit" },
} :: { SpinReward }

--[[ Çarkta ağırlıklı ödül seçer. ]]
function Config.RollSpinReward(rng: Random): SpinReward
	local total = 0
	for _, reward in Config.SpinRewards do
		total += reward.weight
	end

	local roll = rng:NextNumber(0, total)
	for _, reward in Config.SpinRewards do
		roll -= reward.weight
		if roll <= 0 then
			return reward
		end
	end
	return Config.SpinRewards[1]
end

--[[ Nakit ödülünün tutarı. Gelir düşükse taban değer geçerli. ]]
function Config.GetSpinCash(reward: SpinReward, incomePerSecond: number): number
	local scaled = incomePerSecond * (reward.incomeSeconds or 0)
	return math.floor(math.max(reward.minimum or 0, scaled))
end

-- ─── Unvanlar ───────────────────────────────────────────────────────────────
--[[
	Sohbette adının yanında görünen unvan. Rozetlerden farkı: rozet Roblox
	tarafında kalıcı bir nişan, unvan oyun içi bir gösterge ve açılınca
	para ödülü veriyor.

	Koşullar profildeki sayaçlara bakıyor, yani her unvan için ayrı kod
	yazmak gerekmiyor — yeni unvan eklemek bu tabloya bir satır.

	Ödüller gelirle ölçekli: sabit tutar olsaydı geç oyunda açılan unvanlar
	anlamsız kalırdı. Taban değer yeni oyuncu için.

	order: aynı anda birden fazla unvan açıksa en yükseği takılıyor.
]]

export type TitleDef = {
	id: string,
	name: string,
	stat: string,          -- profildeki sayaç
	threshold: number,
	order: number,
	incomeSeconds: number, -- ödül: kaç saniyelik gelir
	minimum: number,       -- ödül tabanı
}

Config.Titles = {
	{ id = "Crewmate",    name = "Crewmate",     stat = "steals",   threshold =  0, order =  1, incomeSeconds =   0, minimum =      0 },
	{ id = "Sus",         name = "Sus",          stat = "steals",   threshold =  1, order =  2, incomeSeconds =  60, minimum =   2500 },
	{ id = "VentCrawler", name = "Vent Crawler", stat = "steals",   threshold = 10, order =  4, incomeSeconds = 180, minimum =  25000 },
	{ id = "Impostor",    name = "Impostor",     stat = "steals",   threshold = 50, order =  8, incomeSeconds = 600, minimum = 250000 },
	{ id = "Shapeshifter",name = "Shapeshifter", stat = "maxStreak",threshold =  5, order =  7, incomeSeconds = 420, minimum = 150000 },
	{ id = "Security",    name = "Security",     stat = "caught",   threshold =  5, order =  5, incomeSeconds = 240, minimum =  50000 },
	{ id = "Ejected",     name = "Ejected",      stat = "robbed",   threshold = 25, order =  3, incomeSeconds = 120, minimum =  10000 },
	{ id = "Engineer",    name = "Engineer",     stat = "maxedUpgrades", threshold = 1, order = 6, incomeSeconds = 300, minimum = 100000 },
	{ id = "Captain",     name = "Captain",      stat = "rebirths", threshold =  1, order =  9, incomeSeconds = 900, minimum = 500000 },
	{ id = "AmogusPrime", name = "Amogus Prime", stat = "secrets",  threshold =  1, order = 10, incomeSeconds =1800, minimum =1000000 },
} :: { TitleDef }

local titlesById: { [string]: TitleDef } = {}
for _, def in Config.Titles do
	titlesById[def.id] = def
end

function Config.GetTitle(id: string): TitleDef?
	return titlesById[id]
end

--[[ Unvan ödülünün tutarı. Gelir düşükse taban değer geçerli. ]]
function Config.GetTitleReward(def: TitleDef, incomePerSecond: number): number
	return math.floor(math.max(def.minimum, incomePerSecond * def.incomeSeconds))
end

-- ─── Görevler ───────────────────────────────────────────────────────────────
--[[
	Üç vadeli görevler: 30 dakika, 3 saat, günlük.

	Neden var: gelir üretmek pasif bir döngü. Oyuncuya "şimdi ne yapayım"
	sorusunun cevabını veren bir şey yoksa oyun açık bırakılan bir sekmeye
	dönüşüyor. Görevler o boşluğu dolduruyor ve oyuncuyu çalmaya,
	yükseltmeye, çark çevirmeye itiyor.

	Vade penceresi dolunca görevler yeniden çekiliyor. Tamamlananlar
	pencere dolana kadar tamamlanmış duruyor — "hepsini bitirdim" hissi
	olmadan hemen yenisi gelirse hiç bitmeyen bir liste oluyor.

	İlerleme mutlak sayaçların farkından hesaplanıyor: görev verilirken
	sayacın o anki değeri taban alınıyor. Bu yüzden her sayaç yalnızca
	artmalı; azalan bir sayaç ilerlemeyi geri götürür.
]]

export type QuestTier = {
	id: string,
	name: string,
	seconds: number,       -- pencere uzunluğu
	slots: number,         -- aynı anda kaç görev
	goalMul: number,       -- hedefler kısa vadeye göre bu kat
	rewardSeconds: number, -- ödül: kaç saniyelik gelir
	rewardMinimum: number, -- ödül tabanı
}

--[[
	goalMul zamanla orantılı değil bilerek: 30 dakikadan 3 saate geçerken
	süre 6 katına çıkıyor ama kimse 3 saat kesintisiz oynamıyor. 4 kat,
	iki oturumda bitirilebilir bir hedef bırakıyor.
]]
Config.QuestTiers = {
	{ id = "short",  name = "30 Minutes", seconds =  1800, slots = 2, goalMul =  1, rewardSeconds =  120, rewardMinimum =   5000 },
	{ id = "medium", name = "3 Hours",    seconds = 10800, slots = 2, goalMul =  4, rewardSeconds =  900, rewardMinimum =  50000 },
	{ id = "daily",  name = "Daily",      seconds = 86400, slots = 2, goalMul = 12, rewardSeconds = 3600, rewardMinimum = 250000 },
} :: { QuestTier }

export type QuestDef = {
	id: string,
	text: string,           -- string.format kalıbı; %s hedefin yazılı hali
	stat: string,           -- QuestService'in tanıdığı sayaç
	base: number,           -- kısa vade hedefi
	maxGoal: number,        -- uzun vadede bile bunu aşmıyor
	fromTier: number,       -- bu sıradan önceki vadelerde çıkmıyor
	incomeSeconds: number?, -- hedef nakitse: kaç saniyelik gelir
	minimum: number?,       -- nakit hedefi tabanı
}

--[[
	maxGoal neden var: "hırsız yakala" görevi günlük vadede 12 katına
	çıksaydı, oyuncunun kontrolü dışında bir şey isterdi — birinin gelip
	ondan çalmasını beklemek. Başkasına bağlı görevlerin tavanı düşük.

	fromTier neden var: yeni oyuncu 30 dakikada yükseltme alamıyor, rebirth
	hiç atamıyor. O görevler kısa vadede çıkarsa görev paneli baştan
	imkânsız görünüyor.
]]
Config.Quests = {
	{ id = "Steal",   stat = "stolen",   base = 3, maxGoal = 30, fromTier = 1, text = "Steal %s crewmates" },
	{ id = "Buy",     stat = "bought",   base = 5, maxGoal = 50, fromTier = 1, text = "Buy %s crewmates off the conveyor" },
	{ id = "Sell",    stat = "sold",     base = 3, maxGoal = 25, fromTier = 1, text = "Sell %s crewmates" },
	{ id = "Earn",    stat = "earned",   base = 0, maxGoal = 0,  fromTier = 1, text = "Earn $%s", incomeSeconds = 300, minimum = 20000 },
	{ id = "Catch",   stat = "caught",   base = 1, maxGoal =  3, fromTier = 2, text = "Catch %s thieves red-handed" },
	{ id = "Upgrade", stat = "upgrades", base = 1, maxGoal =  4, fromTier = 2, text = "Buy %s base upgrades" },
	{ id = "Spin",    stat = "spins",    base = 1, maxGoal =  1, fromTier = 3, text = "Spin the wheel %s time" },
	{ id = "Rebirth", stat = "rebirths", base = 1, maxGoal =  1, fromTier = 3, text = "Rebirth %s time" },
} :: { QuestDef }

--[[
	İksirler — süreli takviyeler.

	Görev ödülü olarak envantere giriyor, ANINDA uygulanmıyor. Sebep:
	çalışırken kazanılan bir takviye boşa gidiyor. Envanterde durursa
	oyuncu ne zaman işine geliyorsa o zaman içiyor.

	Hepsi SÜRELİ. Kalıcı hiçbir şey verilmiyor: kalıcı pass'i bedava
	dağıtmak satışı öldürür, süreli olanı tersine çalışır — on dakika iki
	kat kazanan oyuncu pass'in ne işe yaradığını öğrenmiş oluyor.

	kind, MonetizationService'in tanıdığı takviye türü. Aynı türden iki
	iksir üst üste binmiyor, süreleri ekleniyor.
]]

export type PotionDef = {
	id: string,
	name: string,
	description: string,
	kind: string,
	seconds: number,
	weight: number,
	multiplier: number?,
}

--[[
	3x gelir pass'in (2x) üstünde ama yalnızca beş dakika ve en nadiri;
	kalıcı 2x ile yarışmıyor, sadece ödülü heyecanlı kılıyor.
]]
Config.Potions = {
	{ id = "Income2x",   name = "Double Income", kind = "income", seconds = 600, multiplier = 2, weight = 35,
	  description = "2x cash from every podium" },
	{ id = "FastSteal",  name = "Fast Hands",    kind = "steal",  seconds = 900, weight = 25,
	  description = "Steal prompts finish faster" },
	{ id = "StrongLock", name = "Reinforced Lock", kind = "lock", seconds = 900, weight = 25,
	  description = "Longer lock, shorter cooldown" },
	{ id = "Income3x",   name = "Triple Income", kind = "income", seconds = 300, multiplier = 3, weight = 15,
	  description = "3x cash from every podium" },
} :: { PotionDef }

-- Aynı iksirden envanterde en fazla bu kadar durabiliyor. Sınırsız olsaydı
-- oyuncu aylarca biriktirip tek seferde dökerdi.
Config.PotionStackLimit = 5

local potionsById: { [string]: PotionDef } = {}
for _, def in Config.Potions do
	potionsById[def.id] = def
end

function Config.GetPotion(id: string): PotionDef?
	return potionsById[id]
end

function Config.RollPotion(rng: Random): PotionDef
	local total = 0
	for _, def in Config.Potions do
		total += def.weight
	end

	local roll = rng:NextNumber() * total
	for _, def in Config.Potions do
		roll -= def.weight
		if roll <= 0 then
			return def
		end
	end

	return Config.Potions[1]
end

--[[ Süreyi okunur yazar. Panel ve bildirimler bunu kullanıyor. ]]
function Config.FormatDuration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	if total >= 3600 then
		return string.format("%dh %dm", total // 3600, (total % 3600) // 60)
	end
	return string.format("%d:%02d", total // 60, total % 60)
end

local questsById: { [string]: QuestDef } = {}
for _, def in Config.Quests do
	questsById[def.id] = def
end

function Config.GetQuest(id: string): QuestDef?
	return questsById[id]
end

function Config.GetQuestTier(id: string): QuestTier?
	for _, tier in Config.QuestTiers do
		if tier.id == id then
			return tier
		end
	end
	return nil
end

--[[ Vadenin sırası (1'den başlar). Bilinmiyorsa 0. ]]
function Config.GetQuestTierIndex(id: string): number
	for index, tier in Config.QuestTiers do
		if tier.id == id then
			return index
		end
	end
	return 0
end

--[[
	Görevin o vadedeki hedefi. Nakit hedefleri gelirle ölçekleniyor, çünkü
	sabit bir tutar geç oyunda bir saniyede doluyor, erken oyunda hiç
	dolmuyor.
]]
function Config.GetQuestGoal(def: QuestDef, tier: QuestTier, incomePerSecond: number): number
	if def.incomeSeconds then
		local scaled = incomePerSecond * def.incomeSeconds * tier.goalMul
		return math.floor(math.max((def.minimum or 0) * tier.goalMul, scaled))
	end

	return math.floor(math.min(def.maxGoal, math.max(1, def.base * tier.goalMul)))
end

--[[ Görev metnindeki hedefin okunur hali. Nakit hedefleri kısaltılıyor. ]]
function Config.FormatQuestGoal(def: QuestDef, goal: number): string
	if def.incomeSeconds then
		return Config.FormatCash(goal)
	end
	return tostring(goal)
end

--[[ Vade ödülü. Unvan ödülleriyle aynı mantık: gelirle ölçekli, tabanlı. ]]
function Config.GetQuestReward(tier: QuestTier, incomePerSecond: number): number
	return math.floor(math.max(tier.rewardMinimum, incomePerSecond * tier.rewardSeconds))
end

--[[
	Bir vade için görev seçer. Aynı görev iki kez çıkmıyor; uygun görev
	sayısı slot sayısından azsa daha az görev dönüyor (boş satır, aynı
	görevin iki kez görünmesinden iyi).
]]
function Config.RollQuests(rng: Random, tier: QuestTier): { QuestDef }
	local tierIndex = Config.GetQuestTierIndex(tier.id)

	local pool = {}
	for _, def in Config.Quests do
		if def.fromTier <= tierIndex then
			table.insert(pool, def)
		end
	end

	local picked = {}
	for _ = 1, math.min(tier.slots, #pool) do
		local index = rng:NextInteger(1, #pool)
		table.insert(picked, pool[index])
		table.remove(pool, index)
	end

	return picked
end

-- ─── Öğretici ───────────────────────────────────────────────────────────────
--[[
	Yeni oyuncunun ilk oturumunda izlediği sıralı adımlar.

	Neden var: oyunun döngüsü (konveyörden al -> kaideye koy -> gelir üret ->
	başkasından çal -> üssünü kilitle) hiçbir yerde anlatılmıyor. Bu türde
	oyuncu ilk iki dakikada döngüyü çözemezse çıkıyor.

	Adımlar sıralı: biri bitmeden sonraki gösterilmiyor. Koşul kontrolü
	TutorialService'te; burada yalnızca veri duruyor çünkü Config istemciden
	de okunuyor ve sunucu durumuna erişemiyor.

	check:  TutorialService'in tanıdığı sayaç adı
	goal:   o sayacın ulaşması gereken değer (ilerleme çubuğu bundan çıkıyor)
	hint:   istemcinin hedef göstereceği nesnenin adı
	reward: adım bitince verilen nakit

	Ödüller sabit: öğretici tanımı gereği oyunun en başında geçiyor, gelirle
	ölçeklemek burada hep tabana düşerdi. Toplamı en ucuz yükseltmenin ilk
	seviyesinden biraz fazla — öğreticiyi bitiren oyuncu oyunun ikinci
	katmanına dokunabiliyor ama dengeyi bozmuyor.
]]

export type TutorialStep = {
	id: string,
	title: string,
	text: string,
	hint: string,
	check: string,
	goal: number,
	reward: number,
}

Config.Tutorial = {
	{
		id = "Buy", title = "Hire a crewmate", hint = "Conveyor",
		text = "Crewmates ride the conveyor at your base. Hold the prompt on one to buy it.",
		check = "units", goal = 1, reward = 500,
	},
	{
		id = "Fill", title = "Fill another podium", hint = "Conveyor",
		text = "Every crewmate on a podium prints cash each second. Buy a second one.",
		check = "units", goal = 2, reward = 1500,
	},
	{
		id = "Steal", title = "Steal from a rival", hint = "RivalPlot",
		text = "Walk into another base, hold the prompt on a podium, then carry it home.",
		check = "steals", goal = 1, reward = 4000,
	},
	{
		id = "Lock", title = "Lock your base", hint = "Sign",
		text = "Hold the prompt on your base sign. Nobody can steal while the lock holds.",
		check = "locksUsed", goal = 1, reward = 4000,
	},
	{
		id = "Upgrade", title = "Buy an upgrade", hint = "Upgrades",
		text = "Upgrade boards stand at the back of your base. They cost cash, not Robux.",
		check = "upgrades", goal = 1, reward = 15000,
	},
	{
		id = "Spin", title = "Take your free spin", hint = "Wheel",
		text = "The wheel gives one free spin every day. Go claim today's.",
		check = "spins", goal = 1, reward = 15000,
	},
} :: { TutorialStep }

-- Bitirince verilen ek ödül. Adım ödüllerinden büyük ki son adım yarıda
-- bırakılmasın.
Config.TutorialFinishBonus = 25000

--[[ Sıra numarasıyla adım. Aralık dışıysa nil. ]]
function Config.GetTutorialStep(index: number): TutorialStep?
	return Config.Tutorial[index]
end

--[[ Öğreticinin toplam nakit değeri. Denge testleri buna bakıyor. ]]
function Config.GetTutorialTotalReward(): number
	local total = Config.TutorialFinishBonus
	for _, step in Config.Tutorial do
		total += step.reward
	end
	return total
end

-- ─── Rozetler ───────────────────────────────────────────────────────────────
-- ID'ler Creator Dashboard > Badges altında oluşturulunca buraya yazılacak.
-- id = 0 olan rozet verilmiyor; oyun onu yokmuş gibi çalışıyor.

export type BadgeDef = {
	id: number,
	name: string,
}

Config.Badges = {
	FirstSteal   = { id = 0, name = "First Heist" },
	FirstRebirth = { id = 0, name = "Reborn" },
	Millionaire  = { id = 0, name = "Millionaire" },
	Billionaire  = { id = 0, name = "Billionaire" },
	ThiefCatcher = { id = 0, name = "Caught Red-Handed" },
	Victim       = { id = 0, name = "Robbed" },
	FullHouse    = { id = 0, name = "Full House" },
	SecretFind   = { id = 0, name = "Secret Collector" },
	StreakMaster = { id = 0, name = "Streak Master" },
	FirstSpin    = { id = 0, name = "Lucky Spinner" },
} :: { [string]: BadgeDef }

-- Rozet eşikleri
Config.BadgeMillionaire = 1000000
Config.BadgeBillionaire = 1000000000

-- ─── Kilit (savunma) ────────────────────────────────────────────────────────
Config.LockDuration = 25
Config.LockCooldown = 80

-- ─── Rebirth ve katlar ──────────────────────────────────────────────────────
-- Tavana ulaşan oyuncunun yapacak bir şeyi kalmıyordu. Rebirth her şeyi
-- sıfırlıyor ama karşılığında kalıcı gelir çarpanı ve yeni bir kat veriyor.
Config.MaxFloors = 3           -- 1. kat açık gelir, üstü satın alınıyor
Config.FloorHeight = 18        -- katlar arası yükseklik (stud)
-- 8 kaide Amogus Prime ile 1. kat tavanı ~3.36M/sn. Rebirth'ün o tavanda
-- birkaç dakikalık oyun kadar tutması gerekiyor; 25M yedi saniyelik
-- kazançtı, hiçbir şey ifade etmiyordu.
Config.RebirthBaseCost = 1000000000
Config.RebirthCostGrowth = 8   -- her seviyede maliyet bu kat artar
Config.RebirthIncomeBonus = 0.5 -- seviye başına kalıcı gelir artışı (+%50)

--[[
	Üst katlar: rebirth AÇIYOR, para SATIN ALIYOR.

	Eskiden kat doğrudan rebirth ödülüydü. Sorun şuydu: rebirth zaten
	kalıcı gelir çarpanı veriyor, kat da bedava gelince rebirth tek
	başına her şeydi ve biriken paranın rebirth dışında harcanacak büyük
	bir yeri yoktu.

	Şimdi ikisi ayrı: rebirth katın KİLİDİNİ açıyor, kat parayla
	alınıyor. Böylece rebirth'ten sonra oyuncunun önünde somut ve pahalı
	bir hedef duruyor, ve para biriktirmek rebirth ile yarışıyor —
	5 milyarı 2. kata mı yatırayım yoksa 8 milyarlık rebirth'e mi
	saklayayım sorusu gerçek bir karar.

	Fiyatlar rebirth maliyetlerine göre: 2. kat (5 mlr) ilk rebirth'ün
	(1 mlr) beş katı, 3. kat (150 mlr) ilk iki rebirth'ün toplamının
	(9 mlr) çok üstünde — bilerek, oyunun son büyük alımı olsun diye.

	Satın alınan kat KALICI: rebirth onu geri almıyor. Parasını ödedi.
]]

export type FloorUnlock = {
	floor: number,
	rebirths: number,  -- bu kadar rebirth olmadan satın alınamıyor
	cost: number,      -- oyun içi nakit
}

Config.FloorUnlocks = {
	{ floor = 2, rebirths = 1, cost =   5000000000 },
	{ floor = 3, rebirths = 2, cost = 150000000000 },
} :: { FloorUnlock }

function Config.GetFloorUnlock(floor: number): FloorUnlock?
	for _, def in Config.FloorUnlocks do
		if def.floor == floor then
			return def
		end
	end
	return nil
end

--[[
	Satın alınabilecek bir sonraki kat. Hepsi alınmışsa nil.

	Sıralı: 3. kat 2. kat alınmadan satın alınamıyor. Aksi halde oyuncu
	ortadaki katı atlayıp üsttekini alır ve arada boşluk kalırdı.
]]
function Config.GetNextFloor(floorsBought: number): FloorUnlock?
	return Config.GetFloorUnlock(floorsBought + 2)
end

-- ─── Çevrimdışı gelir ───────────────────────────────────────────────────────
-- Oyuncu çıkınca kazanç tamamen duruyordu, geri gelmek için sebep azdı.
-- Ama çevrimdışı oyuncudan çalınamıyor da: çıkmak zaten güvenli, bir de
-- cömert kazanç verirsek çıkmak oynamaktan kârlı hale gelir.
--
-- Bu ayarlarla 3 saat çevrimdışı ≈ 9 dakika aktif oyun. Hoş geldin
-- hediyesi kadar, strateji olacak kadar değil.
Config.OfflineIncomeRate = 0.05
Config.OfflineIncomeCapHours = 3

-- ─── Para kazanma ───────────────────────────────────────────────────────────
-- ID'ler Creator Dashboard > Monetization altında ürün oluşturulunca buraya
-- yazılacak. id = 0 olan ürün devre dışıdır: satın alma kontrolü yapılmaz,
-- oyun da onu yokmuş gibi çalışır. Böylece ID'ler gelmeden test edilebiliyor.

export type GamePassDef = {
	id: number,
	name: string,
}

Config.GamePasses = {
	DoubleIncome = { id = 0, name = "2x Income" },
	ExtraPodiums = { id = 0, name = "+2 Podiums Per Floor" },
	FastSteal    = { id = 0, name = "Fast Steal" },
	StrongLock   = { id = 0, name = "Strong Lock" },
} :: { [string]: GamePassDef }

-- Gamepass etkileri. Tek yerde dursun ki denge değiştirmek kolay olsun.
Config.PassDoubleIncomeMultiplier = 2
Config.PassExtraPodiumsPerFloor = 2

-- Kat başına fiziksel kaide sayısı: normal + bonus. Bonus kaideler her
-- zaman inşa ediliyor ama pass olmadan kullanılamıyor. Slot numaraları
-- bu sabite göre ilerliyor; sonradan değiştirmek kayıtlı slot -> kaide
-- eşlemesini bozar, o yüzden değişirse DataService sürümü de artmalı.
Config.PodiumsPerFloorTotal = Config.PodiumsPerPlot + Config.PassExtraPodiumsPerFloor
Config.PassFastStealMultiplier = 0.7   -- basılı tutma süresi bu oranla çarpılır
Config.PassStrongLockDuration = 40
Config.PassStrongLockCooldown = 50

export type ProductDef = {
	id: number,
	name: string,
	kind: string,       -- cash | conveyor | lucky | rebirth | spin
	amount: number?,
}

Config.Products = {
	Cash100K       = { id = 0, name = "$100K",           kind = "cash", amount =   100000 },
	Cash1M         = { id = 0, name = "$1M",             kind = "cash", amount =  1000000 },
	Cash10M        = { id = 0, name = "$10M",            kind = "cash", amount = 10000000 },
	SkipConveyor   = { id = 0, name = "Instant Spawn",   kind = "conveyor" },
	LuckyRoll      = { id = 0, name = "Guaranteed Mutation", kind = "lucky" },
	InstantRebirth = { id = 0, name = "Instant Rebirth", kind = "rebirth" },
	ExtraSpin      = { id = 0, name = "Extra Spin",      kind = "spin" },
} :: { [string]: ProductDef }

-- Profilde saklanan makbuz kimliği sayısı. Aynı satın almanın iki kez
-- işlenmesini engellemek için tutuluyor; sınırsız büyümesin diye kırpılıyor.
Config.ReceiptHistoryLimit = 50

-- ─── Üs yükseltmeleri (oyun içi parayla) ────────────────────────────────────
-- Nakdin karakter almak dışında harcanacak yeri olsun diye. Robux ürünlerinin
-- aksine bunlar herkese açık: yeterince oynayan herkes alabiliyor.

export type UpgradeDef = {
	id: string,
	name: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number,
}

-- Eğri bilerek uzun: ilk seviyeler birkaç dakikada alınıyor ama hepsini
-- maksimuma çekmek rebirth maliyetlerinin toplamından fazla tutuyor.
-- Böylece rebirth'ten sonra da alınacak yükseltme kalıyor; kalıcı gelir
-- çarpanı da üst seviyeleri erişilebilir hale getiriyor.
Config.Upgrades = {
	{ id = "ConveyorSpeed", name = "Conveyor Speed", maxLevel = 12, baseCost =  25000, costGrowth = 2.6 },
	{ id = "UnitGuard",     name = "Unit Guard",     maxLevel = 12, baseCost =  60000, costGrowth = 2.6 },
	{ id = "CarrySpeed",    name = "Carry Speed",    maxLevel = 10, baseCost = 100000, costGrowth = 2.6 },
	{ id = "LockPower",     name = "Lock Power",     maxLevel = 12, baseCost = 150000, costGrowth = 2.6 },
} :: { UpgradeDef }

local upgradesById: { [string]: UpgradeDef } = {}
for _, def in Config.Upgrades do
	upgradesById[def.id] = def
end

function Config.GetUpgrade(id: string): UpgradeDef?
	return upgradesById[id]
end

--[[ Bir sonraki seviyenin maliyeti. Seviye tavandaysa nil döner. ]]
function Config.GetUpgradeCost(id: string, currentLevel: number): number?
	local def = upgradesById[id]
	if not def or currentLevel >= def.maxLevel then
		return nil
	end
	return math.floor(def.baseCost * def.costGrowth ^ currentLevel)
end

-- Yükseltme etkileri. Hepsi tek yerde dursun ki denge değiştirmek kolay olsun.

--[[
	Konveyörde iki karakter arası süre. Çarpımsal azalıyor: doğrusal
	olsaydı birkaç seviyede tabana çarpar, kalan seviyeler hiçbir şey
	yapmazdı.
]]
function Config.GetConveyorInterval(level: number): number
	return math.max(2, Config.ConveyorInterval * 0.88 ^ level)
end

--[[ Yeni konan karakterin dokunulmazlık süresi. ]]
function Config.GetSafeSeconds(level: number): number
	return Config.SafeSeconds + level * 2
end

--[[
	Karakter taşırken yürüme hızı. Normal hızı geçmemeli, yoksa taşımak
	avantaj haline gelir ve çalmanın riski kaybolur. Son seviyede tam
	tavana ulaşacak şekilde ayarlı.
]]
function Config.GetCarryWalkSpeed(level: number): number
	return math.min(Config.NormalWalkSpeed - 1, Config.CarryWalkSpeed + level * 0.4)
end

--[[ Kilit süresi ve bekleme süresi, yükseltme seviyesine göre. ]]
function Config.GetLockValues(level: number): (number, number)
	return Config.LockDuration + level * 2.5, math.max(30, Config.LockCooldown - level * 3.5)
end

-- ─── Nadirlikler ────────────────────────────────────────────────────────────
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"

Config.Rarities = {
	Common    = { order = 1, color = Color3.fromRGB(170, 176, 186) },
	Uncommon  = { order = 2, color = Color3.fromRGB( 80, 200, 120) },
	Rare      = { order = 3, color = Color3.fromRGB( 70, 145, 255) },
	Epic      = { order = 4, color = Color3.fromRGB(170,  95, 255) },
	Legendary = { order = 5, color = Color3.fromRGB(255, 175,  45) },
	Mythic    = { order = 6, color = Color3.fromRGB(255,  70, 110) },
	Secret    = { order = 7, color = Color3.fromRGB( 30,  30,  40) },
}

-- ─── Karakterler ────────────────────────────────────────────────────────────
-- weight: konveyörde çıkma ağırlığı (büyük = sık)
-- income: saniyede kazandırdığı para
export type UnitDef = {
	id: string,
	name: string,
	rarity: Rarity,
	price: number,
	income: number,
	weight: number,
	color: Color3,
}

Config.Units = {
	-- Common
	{ id = "RedCrew",     name = "Red Crewmate",       rarity = "Common",    price =    100, income =     3, weight = 1000, color = Color3.fromRGB(197,  17,  17) },
	{ id = "BlueCrew",    name = "Blue Crewmate",      rarity = "Common",    price =    180, income =     6, weight =  900, color = Color3.fromRGB( 19,  46, 210) },
	{ id = "YellowCrew",  name = "Yellow Crewmate",    rarity = "Common",    price =    320, income =    11, weight =  800, color = Color3.fromRGB(241, 224,  90) },

	-- Uncommon
	{ id = "Engineer",    name = "Engineer",           rarity = "Uncommon",  price =    750, income =    28, weight =  500, color = Color3.fromRGB( 56, 254, 220) },
	{ id = "Scientist",   name = "Scientist",          rarity = "Uncommon",  price =   1600, income =    62, weight =  420, color = Color3.fromRGB( 80, 240, 100) },
	{ id = "Guardian",    name = "Guardian Angel",     rarity = "Uncommon",  price =   3400, income =   135, weight =  340, color = Color3.fromRGB(235, 235, 255) },

	-- Rare
	{ id = "Shapeshift",  name = "Shapeshifter",       rarity = "Rare",      price =   7500, income =   310, weight =  200, color = Color3.fromRGB(107,  47, 187) },
	{ id = "VentCrawler", name = "Vent Crawler",       rarity = "Rare",      price =  16000, income =   680, weight =  160, color = Color3.fromRGB( 62,  71,  78) },
	{ id = "MedbayScan",  name = "Medbay Scanner",     rarity = "Rare",      price =  34000, income =  1450, weight =  120, color = Color3.fromRGB( 90, 200, 255) },

	-- Epic
	{ id = "Impostor",    name = "Impostor",           rarity = "Epic",      price =  72000, income =  3100, weight =   70, color = Color3.fromRGB(140,  10,  10) },
	{ id = "Reactor",     name = "Reactor Meltdown",   rarity = "Epic",      price = 155000, income =  6800, weight =   50, color = Color3.fromRGB(255, 120,  20) },
	{ id = "Emergency",   name = "Emergency Meeting",  rarity = "Epic",      price = 330000, income = 14500, weight =   36, color = Color3.fromRGB(255,  60,  60) },

	-- Legendary
	{ id = "Ejected",     name = "Ejected Into Space", rarity = "Legendary", price = 700000, income = 31000, weight =   18, color = Color3.fromRGB( 25,  25,  60) },
	{ id = "TheSkeld",    name = "The Skeld",          rarity = "Legendary", price =1500000, income = 67000, weight =   12, color = Color3.fromRGB(120, 130, 145) },

	-- Mythic
	{ id = "DoubleImp",   name = "Double Impostor",    rarity = "Mythic",    price =3200000, income =145000, weight =    5, color = Color3.fromRGB(190,   0,  55) },

	-- Secret
	{ id = "AmogusPrime", name = "Amogus Prime",       rarity = "Secret",    price =9000000, income =420000, weight =    1, color = Color3.fromRGB( 12,  12,  18) },
} :: { UnitDef }

-- ─── Mutasyonlar ────────────────────────────────────────────────────────────
-- Konveyörde çıkan her karaktere sırayla bakılır, ilk tutan uygulanır.
export type MutationDef = {
	id: string,
	name: string,
	chance: number,
	incomeMul: number,
	tint: Color3?,
}

-- Toplam mutasyon şansı ~%13. Tek tek çarpılıyor, o yüzden
-- bir tanesini yükseltmek toplamı beklediğinden çok artırır.
Config.Mutations = {
	{ id = "Impostor", name = "IMPOSTOR", chance = 0.004, incomeMul = 30, tint = Color3.fromRGB(190,  15,  40) },
	{ id = "Golden",   name = "Golden",   chance = 0.012, incomeMul = 15, tint = Color3.fromRGB(255, 200,  60) },
	{ id = "Ejected",  name = "Ejected",  chance = 0.025, incomeMul =  8, tint = Color3.fromRGB( 40,  40,  90) },
	{ id = "Vented",   name = "Vented",   chance = 0.050, incomeMul =  4, tint = Color3.fromRGB( 90, 110, 120) },
	{ id = "Sus",      name = "Sus",      chance = 0.050, incomeMul =  2, tint = Color3.fromRGB(255, 120, 180) },
} :: { MutationDef }

-- Mutasyonlu karakterin fiyat çarpanı = incomeMul * bu sayı.
-- Gelir çarpanı ise incomeMul'ün tamamı. Yani 0.6'da mutasyonlu karakter
-- kendini normalden %40 daha hızlı amorti eder — şans vuruşu her zaman
-- kârlı. 1.0 yaparsan mutasyon sadece "daha büyük ama aynı verimde"
-- bir karakter olur.
Config.MutationPriceFactor = 0.6

-- Karakter satılınca alış fiyatının bu kadarı geri gelir. 1.0'a yaklaştıkça
-- oyuncu bedava deneme hakkı kazanır: alır, beğenmezse tam iade alır.
-- Düşürdükçe kaide dolduğunda karar vermek zorlaşır.
Config.SellRefundFactor = 0.5

-- ─── Yardımcılar ────────────────────────────────────────────────────────────

local unitsById: { [string]: UnitDef } = {}
for _, unit in Config.Units do
	unitsById[unit.id] = unit
end

function Config.GetUnit(id: string): UnitDef?
	return unitsById[id]
end

function Config.GetMutation(id: string?): MutationDef?
	if id == nil then
		return nil
	end
	for _, mutation in Config.Mutations do
		if mutation.id == id then
			return mutation
		end
	end
	return nil
end

--[[
	Karakterin satış fiyatı. Konveyör bunu kullanır; çalınan bir karakter
	sahibine iade edilemediğinde para iadesi de buradan hesaplanır.
	Tek kaynak olsun diye iki yerde ayrı ayrı hesaplanmıyor.
]]
function Config.GetPrice(unitId: string, mutationId: string?): number
	local def = unitsById[unitId]
	if not def then
		return 0
	end

	local mutation = Config.GetMutation(mutationId)
	local multiplier = if mutation then mutation.incomeMul * Config.MutationPriceFactor else 1
	return math.floor(def.price * multiplier)
end

--[[
	Konveyörden alınabilecek en ucuz karakterin fiyatı. Oyuncunun
	kilitlenip kilitlenmediğini anlamak için kullanılıyor: geliri sıfır
	ve nakdi bunun altındaysa hiçbir şey yapamaz.
]]
local cheapestPrice: number? = nil
function Config.GetCheapestUnitPrice(): number
	if not cheapestPrice then
		local lowest = math.huge
		for _, unit in Config.Units do
			if unit.price < lowest then
				lowest = unit.price
			end
		end
		cheapestPrice = lowest
	end
	return cheapestPrice :: number
end

--[[ Karakteri satınca eline geçen para. ]]
function Config.GetSellPrice(unitId: string, mutationId: string?): number
	return math.floor(Config.GetPrice(unitId, mutationId) * Config.SellRefundFactor)
end

--[[
	Karakteri çalmak için promptun kaç saniye basılı tutulacağı.
	Değerle birlikte artar: ucuz karakter çabuk gider, pahalı karakter
	hırsızı uzun süre açıkta bırakır. Ölçek logaritmik, çünkü fiyatlar
	100 ile 9.000.000 arasında; doğrusal olsaydı ilk beş karakter hariç
	hepsi tavan değere yapışırdı.

	100 -> 2 sn, 9.000.000 -> 8 sn.
]]
function Config.GetStealHoldTime(unitId: string, mutationId: string?): number
	local price = Config.GetPrice(unitId, mutationId)
	if price <= 0 then
		return Config.StealHoldTime
	end

	local t = math.log(price / 100) / math.log(90000)
	return math.clamp(2 + t * 6, 2, 8)
end

--[[ Bir sonraki rebirth'ün maliyeti. Seviye 0 -> ilk rebirth'ün fiyatı. ]]
function Config.GetRebirthCost(rebirths: number): number
	return math.floor(Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths)
end

--[[ Rebirth sayısının getirdiği kalıcı gelir çarpanı. 0 -> 1.0 ]]
function Config.GetIncomeMultiplier(rebirths: number): number
	return 1 + rebirths * Config.RebirthIncomeBonus
end

--[[ Kaç kat açık. İlk kat bedava, her rebirth bir kat daha açar. ]]
--[[
	Açık kat sayısı.

	1. kat herkeste açık. Üstü satın alındığı kadar — rebirth koşulu
	satın alma anında aranıyor, sonradan geri alınmıyor.
]]
function Config.GetUnlockedFloors(floorsBought: number): number
	return math.clamp(1 + floorsBought, 1, Config.MaxFloors)
end

--[[ Açık katlarla birlikte toplam kaç kaide kullanılabilir. ]]
function Config.GetUnlockedPodiumCount(floorsBought: number): number
	return Config.GetUnlockedFloors(floorsBought) * Config.PodiumsPerPlot
end

--[[
	Oyuncu yokken biriken kazanç. Tam oran verilmiyor ve tavanı var;
	yoksa uzun süre girmemek oynamaktan kârlı hale gelir.
]]
function Config.GetOfflineEarnings(incomePerSecond: number, secondsAway: number): number
	if incomePerSecond <= 0 or secondsAway <= 0 then
		return 0
	end

	local capped = math.min(secondsAway, Config.OfflineIncomeCapHours * 3600)
	return math.floor(incomePerSecond * capped * Config.OfflineIncomeRate)
end

--[[
	Konveyör seviyesinin nadirliğe etkisi.

	Önceden bütün seviyelerde aynı ağırlıklar kullanılıyordu: ilk dakikasında
	oyuna giren biri Amogus Prime görebiliyordu. Bu iki şeyi birden bozuyor —
	ilerleme hissi kalmıyor ve ConveyorSpeed upgrade'i sadece "daha sık"
	anlamına geliyor, "daha iyi" anlamına gelmiyor.

	Artık her nadirlik kademesinin bir açılma seviyesi var. Kilitli kademe
	hiç çıkmıyor; açık kademelerin ağırlığı seviye yükseldikçe artıyor.
	Böylece upgrade "daha hızlı kasa" değil "daha iyi kasa" oluyor.

	unlockLevel: bu kademenin çıkmaya başladığı ConveyorSpeed seviyesi
	bonus:       seviye başına ağırlık çarpanı artışı
]]
Config.RarityUnlock = {
	Common    = { unlockLevel = 0,  bonus = 0.00 },
	Uncommon  = { unlockLevel = 0,  bonus = 0.06 },
	Rare      = { unlockLevel = 2,  bonus = 0.14 },
	Epic      = { unlockLevel = 4,  bonus = 0.22 },
	Legendary = { unlockLevel = 6,  bonus = 0.30 },
	Mythic    = { unlockLevel = 8,  bonus = 0.40 },
	Secret    = { unlockLevel = 10, bonus = 0.50 },
}

--[[
	Bir karakterin verilen seviyedeki ağırlığı. Kilitliyse 0.
	Common'a bonus verilmiyor: seviye yükseldikçe payı kendiliğinden
	azalsın, yoksa üst kademeler hiç öne çıkamıyor.
]]
function Config.GetUnitWeight(unit: UnitDef, conveyorLevel: number): number
	local gate = Config.RarityUnlock[unit.rarity]
	if not gate then
		return unit.weight
	end
	if conveyorLevel < gate.unlockLevel then
		return 0
	end

	local steps = conveyorLevel - gate.unlockLevel
	return unit.weight * (1 + gate.bonus * steps)
end

--[[
	Konveyör için ağırlıklı rastgele karakter seçer. Seviye verilmezse 0
	kabul edilir: çağıran taraf seviyeyi geçirmeyi unutursa oyun kırılmaz,
	sadece başlangıç havuzundan çeker.
]]
function Config.RollUnit(rng: Random, conveyorLevel: number?): UnitDef
	local level = conveyorLevel or 0

	local total = 0
	for _, unit in Config.Units do
		total += Config.GetUnitWeight(unit, level)
	end

	if total <= 0 then
		return Config.Units[1]
	end

	local roll = rng:NextNumber(0, total)
	for _, unit in Config.Units do
		roll -= Config.GetUnitWeight(unit, level)
		if roll <= 0 then
			return unit
		end
	end

	return Config.Units[1]
end

--[[ Mutasyon çeker, çıkmazsa nil döner. ]]
function Config.RollMutation(rng: Random): MutationDef?
	for _, mutation in Config.Mutations do
		if rng:NextNumber() < mutation.chance then
			return mutation
		end
	end
	return nil
end

--[[ 1234567 -> "1.23M" ]]
function Config.FormatCash(amount: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi" }
	local index = 1
	local value = amount

	while value >= 1000 and index < #suffixes do
		value /= 1000
		index += 1
	end

	if index == 1 then
		return string.format("%d", value)
	end
	return string.format("%.2f%s", value, suffixes[index])
end

return Config
