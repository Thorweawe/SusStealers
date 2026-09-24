--!strict
-- Tüm oyun dengesi burada. Yeni karakter / mutasyon eklemek için sadece bu dosya.

local Config = {}

-- ─── Dünya ──────────────────────────────────────────────────────────────────
Config.PlotCount = 8
Config.PodiumsPerPlot = 8

--[[
	Üs ölçüsü 60x44'ten 72x52'ye büyüdü. Sebep: üssün üstünde artık
	kaidelerin yanı sıra merdiven, yükseltme kulübesi ve bonus kaideler de
	var; eski ölçüde her şey birbirinin dibindeydi. Kaideler arası boşluk da
	6.5'ten 7.5'e çıktı — komşu karakterlerin şapkaları birbirine giriyordu.
]]
Config.PlotSize = Vector3.new(72, 2, 52)
Config.PodiumSpacing = 7.5
--[[
	Ön/arka kaide sırasının üs merkezine uzaklığı.

	Burada duruyor çünkü İKİ yer birden kullanıyor: PlotService gerçek
	kaideleri, build_decor da altlarındaki pedleri buna göre koyuyor.
	Ayrı ayrı yazılıydı (9 ve 8) ve bir stud kayıyorlardı — pedler
	kaidelerin altından taşıyordu.
]]
Config.PodiumRowZ = 9

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
Config.PlotSpacing = 120       -- yanal boşluk 48 stud (üs 72 geniş)
Config.PlotRowSpacing = 116    -- dikey boşluk 64 stud (üs 52 derin)

--[[
	Üs odaları: harita The Skeld, her üs bir Skeld odası. Sıra üs numarasına
	göre (1-4 arka satır, 5-8 ön satır). Skeld'de motorlar solda üst üste
	durduğu için 1 ve 5 motor odaları; aralarındaki koridor ucunda Reaktör.

	İki yer kullanıyor: harita kurucusu (tools/map) oda zeminini, tabelayı
	ve eşyaları buna göre kuruyor; PlotService üssün zeminini aynı renge
	boyuyor. Renk burada tek yerde, yoksa üs ile oda ayrı tonda kalıyordu.
]]
export type BayRoom = {
	id: string,        -- eşya seti (aynı id aynı eşyalar)
	name: string,      -- tabelada yazan ad
	tile: Color3,      -- zemin karosu
	tile2: Color3,     -- dama deseninin ikinci tonu
	grout: Color3,     -- karo arası oluk
	accent: Color3,    -- odanın vurgu rengi (şerit, ekran)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Config.BayRooms = {
	{ id = "Engine", name = "UPPER ENGINE", tile = rgb(170, 154, 138), tile2 = rgb(156, 141, 126), grout = rgb(108, 96, 86), accent = rgb(240, 136, 52) },
	{ id = "Security", name = "SECURITY", tile = rgb(116, 176, 140), tile2 = rgb(104, 162, 128), grout = rgb(66, 110, 84), accent = rgb(90, 230, 150) },
	{ id = "Comms", name = "COMMUNICATIONS", tile = rgb(132, 154, 190), tile2 = rgb(120, 142, 178), grout = rgb(78, 96, 126), accent = rgb(120, 206, 255) },
	{ id = "O2", name = "O2", tile = rgb(116, 184, 174), tile2 = rgb(104, 170, 160), grout = rgb(66, 118, 110), accent = rgb(120, 244, 204) },
	{ id = "Engine", name = "LOWER ENGINE", tile = rgb(170, 154, 138), tile2 = rgb(156, 141, 126), grout = rgb(108, 96, 86), accent = rgb(240, 136, 52) },
	{ id = "Electrical", name = "ELECTRICAL", tile = rgb(184, 170, 116), tile2 = rgb(168, 154, 102), grout = rgb(116, 104, 64), accent = rgb(255, 214, 60) },
	{ id = "Admin", name = "ADMIN", tile = rgb(180, 118, 126), tile2 = rgb(164, 104, 112), grout = rgb(110, 64, 72), accent = rgb(110, 240, 150) },
	{ id = "Shields", name = "SHIELDS", tile = rgb(220, 200, 156), tile2 = rgb(204, 184, 142), grout = rgb(146, 126, 94), accent = rgb(255, 216, 80) },
} :: { BayRoom }

function Config.GetBayRoom(index: number): BayRoom
	return Config.BayRooms[(index - 1) % #Config.BayRooms + 1]
end

--[[
	Weapons odasındaki "Clear Asteroids" görevi (Among Us'taki görevin
	aynısı): topçu konsoluna gel, ekrandan geçen asteroitleri vur.

	Ödül gelirle ölçekleniyor ki her aşamada anlamlı kalsın ama çalmanın
	yerini tutmasın: 3 dakikalık gelir, en az $1000. Ödül 20 dakikada bir
	alınabiliyor (arada oyun oynanabiliyor, ödülsüz); en kısa süre de oyunu
	gerçekten oynamayı gerektiriyor (20 asteroit 8 saniyeden hızlı
	vurulamıyor — daha hızlı gelen istek sahte sayılıyor).
]]
Config.AsteroidTask = {
	goal = 20,            -- vurulacak asteroit
	minSeconds = 8,       -- bundan hızlı bitirilemez (sahte istek)
	maxSeconds = 240,     -- konsoldan başlanan oyun bu kadar geçerli
	cooldown = 1200,      -- iki ödül arası (20 dk)
	rewardSeconds = 180,  -- ödül = saniyelik gelir × bu
	minReward = 1000,
	range = 45,           -- bitirirken konsola en fazla bu kadar uzak
}

--[[
	Ek odalardaki (Storage, Laboratory) Among Us görevleri. Asteroit göreviyle
	aynı kurallar: konsoldan başlanıyor (sunucu saati tutuyor), en kısa süre
	var (oynamadan bitirilemez), bekleme süresi var, konsolun yakınında
	olmak gerekiyor. Ödül küçük: görevler oyunun özü değil, arada bir sapma.

	minSeconds — bundan hızlı bitirilemez (sahte istek)
	maxSeconds — konsoldan başlanan görev bu kadar geçerli
	cooldown   — aynı görevin iki ödülü arası
	rewardSeconds — ödül = saniyelik gelir × bu (en az minReward)
]]
export type TaskDef = {
	id: string,
	name: string,
	room: string,
	minSeconds: number,
	maxSeconds: number,
	cooldown: number,
	rewardSeconds: number,
	minReward: number,
	range: number,
}

Config.Tasks = {
	{ id = "Fuel",   name = "Fuel Engines", room = "Storage",    minSeconds = 3, maxSeconds = 180, cooldown = 600, rewardSeconds = 60, minReward = 500, range = 16 },
	{ id = "Wiring", name = "Fix Wiring",   room = "Storage",    minSeconds = 2, maxSeconds = 180, cooldown = 600, rewardSeconds = 60, minReward = 500, range = 16 },
	{ id = "Card",   name = "Swipe Card",   room = "Laboratory", minSeconds = 1, maxSeconds = 180, cooldown = 600, rewardSeconds = 60, minReward = 500, range = 16 },
} :: { TaskDef }

function Config.GetTask(id: string): TaskDef?
	for _, def in Config.Tasks do
		if def.id == id then
			return def
		end
	end
	return nil
end

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
--[[
	Shift ile koşma. Karakter TAŞIRKEN çalışmıyor: çalmanın riski taşırken
	yavaş kalmak, koşmaya izin vermek o riski tamamen siler.

	Hız taşıma tavanının epey üstünde ama abartılı değil; haritayı
	geçmek hızlansın, kaçış kolaylaşmasın diye.
]]
Config.SprintWalkSpeed = 24
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
	  description = "Steal 20% faster" },
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
		text = "The upgrade booth sits in your base. Upgrades cost cash, not Robux.",
		check = "upgrades", goal = 1, reward = 40000,
	},
	{
		id = "Spin", title = "Take your free spin", hint = "Wheel",
		text = "The wheel gives one free spin every day. Go claim today's.",
		check = "spins", goal = 1, reward = 40000,
	},
} :: { TutorialStep }

-- Bitirince verilen ek ödül. Adım ödüllerinden büyük ki son adım yarıda
-- bırakılmasın.
--[[
	Ödüller yükseltme fiyatlarıyla birlikte yükseltildi. Öğreticinin 5.
	adımı "bir yükseltme al" diyor; en ucuz yükseltme 100 bine çıkınca
	eski toplam (65 bin) o adımı imkânsız kılıyordu.
]]
Config.TutorialFinishBonus = 50000

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

-- ─── Bildirim sesleri ───────────────────────────────────────────────────────
--[[
	Bildirim tınıları.

	İLK DENEMEM YETERSİZDİ: hepsi aynı 0.39 saniyelik örnekten yalnızca
	perde değiştirilerek türetiliyordu. 1.18 ile 0.92 arasındaki fark o
	kadar kısa bir seste ayırt edilemiyor — kullanıcı haklı olarak "satın
	alma, satma ve yükseltme hâlâ aynı" dedi.

	ŞİMDİ FARKLI ÖRNEKLERDEN türetiliyor. Elimizde beş ses var ve üçü uzun,
	yani içlerinden farklı anlar kesilebiliyor:

	  Success (0.39 sn)  kısa parlak blip
	  Deny    (0.73 sn)  kısa boğuk red
	  Machine (1.93 sn)  mekanik uğultu  -> kesilince "tık/güm"
	  Alarm   (33 sn)    gergin siren    -> kesilince "bip"
	  Ambient (32 sn)    geniş süzülme   -> kesilince "yükseliş"

	Tımbre farkı perdeden çok daha güçlü bir işaret: mekanik bir "güm" ile
	parlak bir "ping" aynı perdede bile karıştırılmıyor. Perde ve vuruş
	sayısı üstüne binen ikincil işaretler.

	source  hangi örnek (yoksa Success)
	startAt örneğin neresinden başlasın (uzun örnekleri kesmek için)
	length  kaç saniye çalsın (yoksa sonuna kadar)
]]

export type NotifyCue = {
	source: string?,
	startAt: number?,
	length: number?,
	pitch: number,
	volume: number,
	repeats: number?,
	gap: number?,
}

Config.NotifyCues = {
	--[[
		Para işlemleri. ÜÇÜ DE FARKLI KAYNAKTAN: perde farkı kısa seslerde
		ayırt edilmiyordu, timbre farkı ediliyor. Kullanıcının "satın alma,
		satma ve yükseltme hâlâ aynı" şikâyeti tam olarak buydu.
	]]
	buy      = { source = "UiA", startAt = 1.20, length = 0.28, pitch = 1.15, volume = 0.45 },
	sell     = { source = "UiB", startAt = 2.40, length = 0.30, pitch = 0.85, volume = 0.45 },
	upgrade  = { source = "UiC", startAt = 3.60, length = 0.26, pitch = 1.00, volume = 0.50, repeats = 2, gap = 0.13 },

	-- Çalma döngüsü: uyarı ailesinden, kısa ve gergin
	steal    = { source = "Alarm", startAt = 2.00, length = 0.22, pitch = 1.25, volume = 0.45 },
	deposit  = { source = "UiD", startAt = 1.50, length = 0.28, pitch = 0.80, volume = 0.50, repeats = 2, gap = 0.12 },
	lock     = { source = "Throb", startAt = 4.00, length = 0.55, pitch = 0.75, volume = 0.50 },
	catch    = { source = "Alarm", startAt = 1.00, length = 0.18, pitch = 1.10, volume = 0.55, repeats = 3, gap = 0.10 },

	-- Büyük ve kalıcı alımlar: ağır, çok vuruşlu
	floor    = { source = "Throb", startAt = 2.00, length = 0.65, pitch = 0.60, volume = 0.60, repeats = 2, gap = 0.22 },
	rebirth  = { source = "Throb", startAt = 8.00, length = 1.60, pitch = 0.55, volume = 0.65 },
	purchase = { source = "UiC", startAt = 5.00, length = 0.26, pitch = 1.05, volume = 0.55, repeats = 3, gap = 0.11 },

	-- Kutlamalar: yükselen dizi, farklı tonlardan
	badge    = { source = "UiD", startAt = 4.00, length = 0.24, pitch = 1.20, volume = 0.55, repeats = 3, gap = 0.09 },
	title    = { source = "UiA", startAt = 6.00, length = 0.26, pitch = 1.05, volume = 0.50, repeats = 3, gap = 0.12 },
	quest    = { source = "UiB", startAt = 5.50, length = 0.26, pitch = 0.95, volume = 0.45, repeats = 2, gap = 0.12 },
	spin     = { source = "UiC", startAt = 8.00, length = 0.24, pitch = 1.30, volume = 0.45, repeats = 2, gap = 0.07 },
	potion   = { source = "UiD", startAt = 7.00, length = 0.22, pitch = 1.45, volume = 0.40 },
	-- Yumurta açılışı: yükselen üç vuruş, "çatladı" hissi için hızlı
	pet      = { source = "UiA", startAt = 3.00, length = 0.20, pitch = 1.35, volume = 0.50, repeats = 3, gap = 0.08 },
	-- Günlük/oynama/indeks ödülü: hediye kutusu açılışı, parlak ve kısa
	reward   = { source = "UiD", startAt = 2.50, length = 0.22, pitch = 1.25, volume = 0.50, repeats = 2, gap = 0.10 },
	-- Ekipman satın alma: metalik tek vuruş
	gear     = { source = "UiB", startAt = 3.50, length = 0.26, pitch = 0.95, volume = 0.50 },
	-- Sunucu olayı başladı/yaklaşıyor: alarm ailesinden, ağır iki vuruş
	event    = { source = "Alarm", startAt = 5.00, length = 0.30, pitch = 0.85, volume = 0.45, repeats = 2, gap = 0.22 },
	-- Arkadaş sunucuya girdi: sıcak, iki vuruşlu karşılama
	friend   = { source = "UiA", startAt = 7.50, length = 0.24, pitch = 1.10, volume = 0.45, repeats = 2, gap = 0.14 },

	-- Bilgilendirme: en sessizler, araya girmemeli
	tutorial = { source = "UiA", startAt = 9.00, length = 0.24, pitch = 1.00, volume = 0.32 },
	welcome  = { source = "UiB", startAt = 8.00, length = 0.30, pitch = 1.00, volume = 0.38, repeats = 2, gap = 0.15 },
	plot     = { source = "UiC", startAt = 11.0, length = 0.24, pitch = 0.90, volume = 0.32 },
	income   = { source = "UiB", startAt = 12.0, length = 0.20, pitch = 0.95, volume = 0.25 },
} :: { [string]: NotifyCue }

--[[ Bu türün tanımlı bir sesi var mı. Testler buna bakıyor. ]]
function Config.HasNotifyCue(kind: string): boolean
	return Config.NotifyCues[kind] ~= nil
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

-- ─── Sunucu olayları ────────────────────────────────────────────────────────
--[[
	Saatli olaylar (EventService). Zamanlar UTC saatine hizalı: bütün
	sunucularda aynı anda başlıyor, oyuncu "Emergency Meeting her saat
	başı :15'te" diye öğrenebiliyor ve o saatte oyuna giriyor.

	every   — kaç saniyede bir
	offset  — periyodun içindeki başlangıç (0 = saat başı)
	duration— kaç saniye sürüyor

	Dakikalar birbirine denk gelmeyecek şekilde dağıtıldı: :00 impostor
	(çift saatler), :15 toplantı, :30 reaktör (3 saatte bir), :45 ışıklar.
]]
export type EventDef = {
	id: string,
	name: string,
	every: number,
	offset: number,
	duration: number,
}

Config.Events = {
	{ id = "Meeting",   name = "Emergency Meeting", every = 3600,     offset = 15 * 60, duration = 120 },
	{ id = "LightsOut", name = "Lights Sabotage",   every = 3600,     offset = 45 * 60, duration = 90 },
	{ id = "Meltdown",  name = "Reactor Meltdown",  every = 3 * 3600, offset = 30 * 60, duration = 60 },
	{ id = "Impostor",  name = "Impostor Among Us", every = 2 * 3600, offset = 0,       duration = 60 },
} :: { EventDef }

-- Başlamadan kaç saniye önce haber verilsin
Config.EventWarning = 30

-- Emergency Meeting: herkese gelir çarpanı
Config.MeetingIncomeMul = 2
-- Lights Sabotage: çalma basılı tutma süresi bu oranla çarpılıyor
Config.LightsOutHoldMul = 0.6

--[[
	Reactor Meltdown: istasyonun rastgele noktalarına enerji çekirdekleri
	düşüyor, ilk dokunan alıyor. Rastgele çünkü üsler farklı yerlerde; sabit
	nokta bazı üslere hep yakın olurdu.
	Ödül gelirle ölçekli (yeni oyuncu için de anlamlı, zengin için de):
	nakit ya da düşük ihtimalle bir karakter.
]]
Config.MeltdownCores = 6
Config.MeltdownRewardSeconds = 90   -- nakit ödül = saniyelik gelir × bu
Config.MeltdownMinCash = 5000
Config.MeltdownUnitChance = 0.15
Config.MeltdownUnitMinutes = 10     -- karakter ödülü: ~10 dk'lık gelirle alınabilecek en iyisi

--[[
	Impostor Among Us: rastgele bir oyuncu 1 dakikalığına herkesin gördüğü
	impostor oluyor. Çalarken yakalanırsa yakalayan ona parasının bir
	kısmını ÖDÜYOR; yakalanmazsa çaldığıyla kalıyor. Diğerleri için ikilem:
	yakalamak para kaybettiriyor, yakalamamak karakter.
]]
Config.ImpostorPayMin = 0.03
Config.ImpostorPayMax = 0.05
Config.ImpostorPayCap = 200000

--[[ Olayın verilen andan sonraki ilk başlangıcı (unix saniye). ]]
function Config.GetNextEventStart(def: EventDef, now: number): number
	local into = (now - def.offset) % def.every
	if into == 0 then
		return now
	end
	return now - into + def.every
end

function Config.GetEvent(id: string): EventDef?
	for _, def in Config.Events do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- ─── Vent ───────────────────────────────────────────────────────────────────
-- Taşırken kullanılamıyor (VentService). Bekleme, iki kapak arasında gidip
-- gelip kovalayanı sonsuza kadar atlatmayı engelliyor.
Config.VentCooldown = 8
Config.VentHoldTime = 0.35

-- ─── Arkadaş bonusu ─────────────────────────────────────────────────────────
--[[
	Aynı sunucudaki her Roblox arkadaşı için küçük bir gelir bonusu.
	Amaç oyuncunun arkadaşını çağırması; dengeyi bozmaması için küçük ve
	tavanlı: üç arkadaşta +%15, sonrası artmıyor. Karşılaştırma: tek bir
	rebirth +%50, gelir pass'i x2.

	Karşılıklı: iki arkadaş aynı sunucudaysa İKİSİ de bonus alıyor, yani
	davet eden de gelen de kazanıyor.
]]
Config.FriendBonusPerFriend = 0.05
Config.FriendBonusMax = 0.15

--[[ Sunucudaki arkadaş sayısına göre gelir bonusu (0.10 = +%10). ]]
function Config.GetFriendBonus(friendCount: number): number
	return math.min(Config.FriendBonusMax, math.max(0, friendCount) * Config.FriendBonusPerFriend)
end

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
	-- Yumurtayı tek seferde üç kez açar (üç kat fiyat, tek bekleme)
	TripleHatch  = { id = 0, name = "Triple Hatch" },
} :: { [string]: GamePassDef }

--[[
	Oyunun Roblox grubu. OTOMATİK YUMURTA AÇMA gruba katılanlara açık:
	oyuncu grubu büyütüyor, grup da güncelleme bildirimleriyle oyuncuyu
	geri getiriyor.

	0 = grup henüz kurulmadı: otomatik açma kapalı. Studio'da test için
	grup şartı aranmıyor (PetService). Grup kurulunca ID buraya yazılacak.
]]
Config.GroupId = 0

--[[
	Yumurta açılışının süresi (saniye). Bir yumurta açılırken ikincisi
	açılamıyor — sunucu bu süreyi bekletiyor, istemcideki animasyon da bu
	süreye göre ayarlı (HatchFX). Eskiden art arda basınca animasyonlar
	kuyruğa giriyor ve sonuçlar kaçıyordu.
]]
Config.HatchDuration = 3.5
Config.TripleHatchCount = 3

-- Gamepass etkileri. Tek yerde dursun ki denge değiştirmek kolay olsun.
Config.PassDoubleIncomeMultiplier = 2
Config.PassExtraPodiumsPerFloor = 2

-- Kat başına fiziksel kaide sayısı: normal + bonus. Bonus kaideler her
-- zaman inşa ediliyor ama pass olmadan kullanılamıyor. Slot numaraları
-- bu sabite göre ilerliyor; sonradan değiştirmek kayıtlı slot -> kaide
-- eşlemesini bozar, o yüzden değişirse DataService sürümü de artmalı.
Config.PodiumsPerFloorTotal = Config.PodiumsPerPlot + Config.PassExtraPodiumsPerFloor
--[[
	Hızlı çalma: basılı tutma süresi bu oranla çarpılıyor.
	Pass kalıcı ve Robux'la alınıyor, o yüzden belirgin şekilde güçlü
	(%40); iksir süreli bir tadımlık (%20) — pass'in ne işe yaradığını
	gösteriyor ama yerini tutmuyor. İkisi üst üste binmiyor, iyisi geçiyor.

	ESKİ HATA: sunucu kısa süreyi kabul ediyordu ama istemcideki prompt
	yine TAM süre dolunca tetikleniyordu; pass ve iksir pratikte hiçbir şey
	yapmıyordu. Şimdi oyuncunun çarpanı "StealHoldMul" niteliğiyle istemciye
	gidiyor ve PromptFilter kendi ekranındaki promptu kısaltıyor.
]]
Config.PassFastStealMultiplier = 0.6
Config.PotionFastStealMultiplier = 0.8
-- Hiçbir çarpan birleşimi (pass + Lights Sabotage) çalmayı bundan kısa yapamaz
Config.MinStealHold = 1

--[[
	Oyuncuya özel çalma süresi: taban (karaktere ve olaya göre) × kişisel
	çarpan, alt sınırla. Sunucu (PromptGuard) ve istemci (PromptFilter)
	AYNI fonksiyonu kullanıyor; farklı hesaplasalar basış reddedilirdi.
]]
function Config.GetPersonalStealHold(base: number, multiplier: number): number
	return math.max(math.min(base, Config.MinStealHold), base * multiplier)
end
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
	baseMaxLevel: number,  -- 1. katta ulaşılabilen tavan
	baseCost: number,
	costGrowth: number,
}

--[[
	Yükseltmeler: pahalı, seviye başına az, ama çok seviyeli.

	Üç kural birlikte çalışıyor:

	1. TAVAN KAT SAYISIYLA İKİYE KATLANIYOR. 1. katta 6 seviye, 2. katta
	   12, 3. katta 24. Kat açmak yalnızca kaide değil, harcayacak yer de
	   açıyor.

	2. SEVİYE BAŞINA ETKİ YARIYA İNDİ. Seviye sayısı ikiye katlandığı
	   için tavandaki güç eskisiyle aynı kalıyor — oyun bozulmuyor, sadece
	   yol daha uzun ve daha kademeli.

	3. TABAN FİYAT DÖRT KAT. Erken seviyeler artık bedavaya gelmiyor.
	   Büyüme 2.0'a indi: 2.6 ile 24 seviye matematiksel olarak
	   ulaşılamazdı, yani ikiye katlanan tavan hiçbir işe yaramazdı.

	Etkilerin hepsi bir tavana yaklaşıyor (çarpımsal ya da clamp'li),
	doğrusal değil. Böylece ileride tavan yine artarsa oyun kırılmıyor.

	Rebirth yükseltmeleri SIFIRLIYOR (RebirthService). Kalıcı olsalardı
	rebirth'ten sonra harcanacak yer yine kalmazdı.
]]
Config.Upgrades = {
	{ id = "ConveyorSpeed", name = "Conveyor Speed", baseMaxLevel = 6, baseCost = 100000, costGrowth = 2.0 },
	{ id = "UnitGuard",     name = "Unit Guard",     baseMaxLevel = 6, baseCost = 240000, costGrowth = 2.0 },
	{ id = "CarrySpeed",    name = "Carry Speed",    baseMaxLevel = 5, baseCost = 400000, costGrowth = 2.0 },
	{ id = "LockPower",     name = "Lock Power",     baseMaxLevel = 6, baseCost = 600000, costGrowth = 2.0 },
} :: { UpgradeDef }

--[[
	Açık kat sayısına göre tavan. Her kat tavanı ikiye katlıyor.
	floors 1 -> baseMaxLevel, 2 -> x2, 3 -> x4.
]]
function Config.GetUpgradeMaxLevel(def: UpgradeDef, floors: number): number
	local unlocked = math.clamp(floors, 1, Config.MaxFloors)
	return def.baseMaxLevel * 2 ^ (unlocked - 1)
end

--[[ Oyunda ulaşılabilecek en yüksek tavan. Kayıt kırpması buna bakıyor. ]]
function Config.GetUpgradeCeiling(def: UpgradeDef): number
	return Config.GetUpgradeMaxLevel(def, Config.MaxFloors)
end

local upgradesById: { [string]: UpgradeDef } = {}
for _, def in Config.Upgrades do
	upgradesById[def.id] = def
end

function Config.GetUpgrade(id: string): UpgradeDef?
	return upgradesById[id]
end

--[[
	Bir sonraki seviyenin maliyeti. Seviye o katın tavanındaysa nil döner.

	floors verilmezse en yüksek tavan varsayılıyor; sadece fiyat soran
	(tavanı ayrıca kontrol eden) çağrılar için.
]]
function Config.GetUpgradeCost(id: string, currentLevel: number, floors: number?): number?
	local def = upgradesById[id]
	if not def then
		return nil
	end

	local max = if floors then Config.GetUpgradeMaxLevel(def, floors) else Config.GetUpgradeCeiling(def)
	if currentLevel >= max then
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
	-- 0.88 -> 0.94: seviye başına yarı etki, iki kat seviyede aynı taban
	return math.max(2, Config.ConveyorInterval * 0.94 ^ level)
end

--[[ Yeni konan karakterin dokunulmazlık süresi. ]]
function Config.GetSafeSeconds(level: number): number
	return Config.SafeSeconds + level * 1
end

--[[
	Karakter taşırken yürüme hızı. Normal hızı geçmemeli, yoksa taşımak
	avantaj haline gelir ve çalmanın riski kaybolur. Son seviyede tam
	tavana ulaşacak şekilde ayarlı.
]]
function Config.GetCarryWalkSpeed(level: number, petBonus: number?): number
	local base = Config.CarryWalkSpeed + level * 0.2 + (petBonus or 0)
	return math.min(Config.NormalWalkSpeed - 1, base)
end

--[[ Kilit süresi ve bekleme süresi, yükseltme seviyesine göre. ]]
function Config.GetLockValues(level: number): (number, number)
	return Config.LockDuration + level * 1.25, math.max(30, Config.LockCooldown - level * 1.75)
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

--[[
	═══ DENGE ═══════════════════════════════════════════════════════════════

	Ölçü birimi AMORTİ SÜRESİ: price / income. Karakterin kendi parasını kaç
	saniyede geri ödediği. Oyunun bütün hızı bu tek sayıda.

	ESKİ DURUM: her karakter kendini 21-33 saniyede ödüyordu, üstelik
	nadirlik arttıkça süre KISALIYORDU (Amogus Prime 21.4s, Red Crewmate
	33s). Sonuç: sekiz kaidesi dolu bir oyuncu saniyede yatırdığı paranın
	~%35'ini geri alıyor, yani sermayesi yarım dakikada katlanıyordu. Birkaç
	dakikada milyarlara çıkılmasının sebebi buydu — test sırasında 4.65B
	görüldü.

	YENİ DURUM: amorti süresi nadirlikle UZUYOR.

	    Common  55s → Uncommon 75s → Rare 100s → Epic 135s
	                → Legendary 175s → Mythic 230s → Secret 320s

	Neden artan? Çünkü yüksek nadirlik zaten kendi başına ödül. Kısa amorti
	verirsek pahalı karakter hem daha güçlü hem daha verimli olur ve ucuz
	kaidelerin hiçbir anlamı kalmaz. Uzayan amorti, pahalı karakteri bir
	YATIRIM yapıyor: toplam kazanç çok daha yüksek ama geri dönüş sabır
	istiyor. Bu arada çalma da anlam kazanıyor — rakibin Mythic'i hâlâ
	kendini ödemeden onu çalmak gerçek bir darbe.

	Fiyat merdiveni ~2.1x adımlarla ilerliyor. Her kademede dört karakter
	var (Mythic üç, Secret iki) — eskiden bazı kademelerde tek karakter
	vardı ve konveyörde hep aynı şey çıkıyordu.

	Sayılar elle yazıldı, formülle üretilmedi: yuvarlak fiyatlar oyuncuya
	daha okunaklı geliyor ve tek tek elden geçirilebiliyor.
]]
Config.Units = {
	-- Common — amorti ~55s
	{ id = "RedCrew",     name = "Red Crewmate",       rarity = "Common",    price =        100, income =           2, weight = 1000, color = Color3.fromRGB(197,  17,  17) },
	{ id = "BlueCrew",    name = "Blue Crewmate",      rarity = "Common",    price =        220, income =           4, weight =  920, color = Color3.fromRGB( 19,  46, 210) },
	{ id = "YellowCrew",  name = "Yellow Crewmate",    rarity = "Common",    price =        480, income =           9, weight =  840, color = Color3.fromRGB(241, 224,  90) },
	{ id = "LimeCrew",    name = "Lime Crewmate",      rarity = "Common",    price =       1000, income =          18, weight =  760, color = Color3.fromRGB( 80, 240,  57) },

	-- Uncommon — amorti ~75s
	{ id = "Engineer",    name = "Engineer",           rarity = "Uncommon",  price =       2200, income =          29, weight =  520, color = Color3.fromRGB( 56, 254, 220) },
	{ id = "Scientist",   name = "Scientist",          rarity = "Uncommon",  price =       4800, income =          64, weight =  450, color = Color3.fromRGB( 80, 240, 100) },
	{ id = "Janitor",     name = "Janitor",            rarity = "Uncommon",  price =      10500, income =         140, weight =  390, color = Color3.fromRGB(113,  73,  30) },
	{ id = "Guardian",    name = "Guardian Angel",     rarity = "Uncommon",  price =      23000, income =         307, weight =  330, color = Color3.fromRGB(235, 235, 255) },

	-- Rare — amorti ~100s
	{ id = "Shapeshift",  name = "Shapeshifter",       rarity = "Rare",      price =      50000, income =         500, weight =  195, color = Color3.fromRGB(107,  47, 187) },
	{ id = "VentCrawler", name = "Vent Crawler",       rarity = "Rare",      price =     110000, income =        1100, weight =  165, color = Color3.fromRGB( 62,  71,  78) },
	{ id = "MedbayScan",  name = "Medbay Scanner",     rarity = "Rare",      price =     240000, income =        2400, weight =  140, color = Color3.fromRGB( 90, 200, 255) },
	{ id = "Sheriff",     name = "Sheriff",            rarity = "Rare",      price =     520000, income =        5200, weight =  115, color = Color3.fromRGB(218, 165,  32) },

	-- Epic — amorti ~135s
	{ id = "Impostor",    name = "Impostor",           rarity = "Epic",      price =    1150000, income =        8500, weight =   72, color = Color3.fromRGB(140,  10,  10) },
	{ id = "Reactor",     name = "Reactor Meltdown",   rarity = "Epic",      price =    2500000, income =       18500, weight =   58, color = Color3.fromRGB(255, 120,  20) },
	{ id = "O2Sabotage",  name = "O2 Sabotage",        rarity = "Epic",      price =    5400000, income =       40000, weight =   46, color = Color3.fromRGB(120, 220, 255) },
	{ id = "Emergency",   name = "Emergency Meeting",  rarity = "Epic",      price =   11500000, income =       85000, weight =   36, color = Color3.fromRGB(255,  60,  60) },

	-- Legendary — amorti ~175s
	{ id = "Ejected",     name = "Ejected Into Space", rarity = "Legendary", price =   25000000, income =      143000, weight =   20, color = Color3.fromRGB( 25,  25,  60) },
	{ id = "Polus",       name = "Polus Outpost",      rarity = "Legendary", price =   54000000, income =      309000, weight =   16, color = Color3.fromRGB(190, 210, 225) },
	{ id = "TheSkeld",    name = "The Skeld",          rarity = "Legendary", price =  115000000, income =      657000, weight =   12, color = Color3.fromRGB(120, 130, 145) },
	{ id = "Airship",     name = "The Airship",        rarity = "Legendary", price =  250000000, income =     1430000, weight =    9, color = Color3.fromRGB(150, 118,  70) },

	-- Mythic — amorti ~230s
	{ id = "DoubleImp",   name = "Double Impostor",    rarity = "Mythic",    price =  540000000, income =     2350000, weight =    5, color = Color3.fromRGB(190,   0,  55) },
	{ id = "TripleImp",   name = "Triple Impostor",    rarity = "Mythic",    price = 1200000000, income =     5220000, weight =    3, color = Color3.fromRGB(120,   0,  35) },
	{ id = "Jester",      name = "The Jester",         rarity = "Mythic",    price = 2600000000, income =    11300000, weight =    2, color = Color3.fromRGB(238,  84, 187) },

	-- Secret — amorti ~320s
	{ id = "AmogusPrime", name = "Amogus Prime",       rarity = "Secret",    price = 5800000000, income =    18100000, weight =    1, color = Color3.fromRGB( 12,  12,  18) },
	{ id = "TheCrewmate", name = "The Crewmate",       rarity = "Secret",    price =13000000000, income =    40600000, weight =    1, color = Color3.fromRGB(215, 224, 240) },
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

-- ─── Petler ─────────────────────────────────────────────────────────────────
--[[
	═══ NE İŞE YARIYORLAR ══════════════════════════════════════════════════

	Pet, oyuncunun peşinden gelen küçük bir yoldaş ve iki şeye dokunuyor:
	GELİR yüzdesi ve TAŞIMA HIZI. İkisi de oyunun iki ana fiiline karşılık
	geliyor — kaide doldurmak ve çalmak.

	Neden bu iki stat? Çünkü oyuncunun zaten umursadığı sayılar bunlar ve
	ikisi de HUD'da görünüyor. Üçüncü bir stat eklemek (şans, kilit süresi)
	peti "bir sürü küçük yüzde" haline getirirdi; bakışta ne yaptığı
	anlaşılmazdı.

	═══ NEDEN YUMURTA ══════════════════════════════════════════════════════

	Peti doğrudan satmak, parası olanın istediğini alması demek — nadirlik
	kademesi anlamsızlaşır. Yumurta ise PARAYLA ALINIYOR ama içinden ne
	çıkacağı şansa bağlı: para sadece daha iyi bir havuza giriş bileti.

	Her yumurtanın kendi kademe ağırlıkları var ve havuzlar üst üste
	biniyor (Skeld yumurtası hâlâ Uncommon verebiliyor). Bu kasten:
	pahalı yumurtanın kötü sonucu da olsun ki açmak heyecanlı kalsın.

	═══ DENGE ══════════════════════════════════════════════════════════════

	Üç pet takılabiliyor ve bonuslar TOPLANIYOR. Üç Secret pet +%375 gelir
	demek — çok gibi duruyor ama Secret yalnızca en pahalı yumurtadan ve
	%6 ağırlıkla çıkıyor; oraya gelen oyuncu zaten oyunun sonunda.

	Gelir çarpanı rebirth ve gamepass ile ÇARPILIYOR (EconomyService),
	toplanmıyor. Yani pet her kademede aynı oranda işe yarıyor.
]]
export type PetDef = {
	id: string,
	name: string,
	rarity: Rarity,
	incomeBonus: number,   -- gelire eklenen oran (0.25 = +%25)
	speedBonus: number,    -- taşıma hızına eklenen stud/s
	color: Color3,
}

--[[
	Kademe başına bonus. Pet tanımları bunu kullanıyor ki aynı kademedeki
	iki pet aynı gücü versin — fark yalnızca görünüşte olsun.

	Denge değiştirmek isteyen tek yere bakıyor: aşağıdaki dört sayı.
]]
local PET_TIER = {
	Common    = { income = 0.02, speed = 0.05 },
	Uncommon  = { income = 0.05, speed = 0.10 },
	Rare      = { income = 0.10, speed = 0.20 },
	Epic      = { income = 0.20, speed = 0.35 },
	Legendary = { income = 0.40, speed = 0.55 },
	Mythic    = { income = 0.75, speed = 0.85 },
	Secret    = { income = 1.25, speed = 1.20 },
}

local function pet(id: string, name: string, rarity: Rarity, color: Color3): PetDef
	local tier = PET_TIER[rarity]
	return {
		id = id,
		name = name,
		rarity = rarity,
		incomeBonus = tier.income,
		speedBonus = tier.speed,
		color = color,
	}
end

--[[
	Petler. Hepsi Skeld'in kendi eşyalarından: bir görev konsolu, bir
	yedek kask, havalandırmadan çıkan bir şey. Among Us'tan HAZIR VARLIK
	kopyalanmıyor — alınan şey mekânın dili.
]]
Config.Pets = {
	-- Common
	pet("MiniCrew",   "Mini Crew",        "Common",    Color3.fromRGB(197,  17,  17)),
	pet("Bolt",       "Loose Bolt",       "Common",    Color3.fromRGB(176, 184, 196)),
	pet("VentRat",    "Vent Rat",         "Common",    Color3.fromRGB(113,  73,  30)),

	-- Uncommon
	pet("BrainSlug",  "Brain Slug",       "Uncommon",  Color3.fromRGB(238, 132, 195)),
	pet("SparePod",   "Spare Helmet",     "Uncommon",  Color3.fromRGB(150, 222, 236)),
	pet("Hamster",    "Cargo Hamster",    "Uncommon",  Color3.fromRGB(226, 186, 120)),

	-- Rare
	pet("MedDrone",   "Medbay Drone",     "Rare",      Color3.fromRGB( 90, 200, 255)),
	pet("TaskBot",    "Task Bot",         "Rare",      Color3.fromRGB( 56, 254, 220)),
	pet("VentCrab",   "Vent Crab",        "Rare",      Color3.fromRGB( 62,  71,  78)),

	-- Epic
	pet("SusShadow",  "Sus Shadow",       "Epic",      Color3.fromRGB(107,  47, 187)),
	pet("CoreShard",  "Reactor Shard",    "Epic",      Color3.fromRGB(255, 120,  20)),
	pet("SecurityCam","Security Cam",     "Epic",      Color3.fromRGB(120, 220, 255)),

	-- Legendary
	pet("MiniImp",    "Mini Impostor",    "Legendary", Color3.fromRGB(190,   0,  55)),
	pet("EscapePod",  "Escape Pod",       "Legendary", Color3.fromRGB(215, 224, 240)),
	pet("SnowPal",    "Polus Snow Pal",   "Legendary", Color3.fromRGB(190, 210, 225)),

	-- Mythic
	pet("GhostCrew",  "Ejected Ghost",    "Mythic",    Color3.fromRGB(170, 190, 255)),
	pet("MeetingBell","Emergency Bell",   "Mythic",    Color3.fromRGB(255,  70, 110)),

	-- Secret
	pet("TheEgg",     "The Egg",          "Secret",    Color3.fromRGB(238, 230, 214)),
	pet("VoidShard",  "Void Shard",       "Secret",    Color3.fromRGB( 18,  18,  26)),
} :: { PetDef }

-- Aynı anda takılabilecek pet sayısı. Üç: sıralı bir seçim yapacak kadar
-- az, "hangisi daha iyi" sorusunu anlamlı kılacak kadar çok.
Config.PetEquipSlots = 3

--[[
	Envanter tavanı. Sınırsız olsaydı kayıt dosyası büyür ve arayüz
	kullanılmaz hale gelirdi. Aynı petten birden fazla tutuluyor (adet),
	yani tavan ÇEŞİT sayısı değil, kayıt satırı sayısı.
]]
Config.PetStackLimit = 99

--[[
	═══ PET MUTASYONLARI ═══════════════════════════════════════════════════

	Karakter mutasyonlarından AYRI bir tablo. Onlarınki gelir çarpanı
	x2..x30; pete x30 verseydik tek bir Cosmic Secret +%3750 gelir demekti
	ve oyun biterdi. Burada çarpan petin BONUSUNA uygulanıyor ve en fazla
	x3.

	Şans yumurta açarken bir kez atılıyor; birleştirmede mutasyon
	KORUNUYOR (üç Golden -> bir Golden). Böylece mutasyonlu kopya
	toplamanın da bir anlamı oluyor.
]]
export type PetMutationDef = {
	id: string,
	name: string,
	chance: number,
	multiplier: number,
	tint: Color3,
}

Config.PetMutations = {
	-- Sıra önemli: en nadir önce denenir, tutan uygulanır
	{ id = "Cosmic",  name = "Cosmic",  chance = 0.005, multiplier = 3.0, tint = Color3.fromRGB(150,  90, 255) },
	{ id = "Crystal", name = "Crystal", chance = 0.020, multiplier = 2.0, tint = Color3.fromRGB(120, 230, 255) },
	{ id = "Golden",  name = "Golden",  chance = 0.050, multiplier = 1.5, tint = Color3.fromRGB(255, 200,  60) },
} :: { PetMutationDef }

function Config.GetPetMutation(id: string?): PetMutationDef?
	if not id or id == "" then
		return nil
	end
	for _, def in Config.PetMutations do
		if def.id == id then
			return def
		end
	end
	return nil
end

function Config.RollPetMutation(rng: Random): PetMutationDef?
	for _, def in Config.PetMutations do
		if rng:NextNumber() < def.chance then
			return def
		end
	end
	return nil
end

--[[
	═══ BOYUT KADEMELERİ (BİRLEŞTİRME) ═════════════════════════════════════

	Birleştirme petin NADİRLİĞİNİ değil BOYUTUNU büyütüyor: aynı petten
	üç tane -> o petin BIG hâli; üç BIG -> HUGE; üç HUGE -> TITAN. Tür ve
	mutasyon aynı kalıyor, sahadaki model de gözle görülür şekilde büyüyor.

	Eskiden üç kopya bir üst kademeden RASTGELE bir pete dönüşüyordu; en
	sevdiğin peti birleştirince elinde başka bir pet kalıyordu ve Secret
	hiç birleştirilemiyordu.

	Çarpan petin bonusuna uygulanıyor (mutasyonla ÇARPILARAK):

	    Big x2.5 (3 kopya) · Huge x5 (9) · Titan x10 (27)

	Üç kopyanın ham toplamı x3; Big x2.5 ondan biraz AZ ama tek slota
	sığıyor — slot üç tane, yani birleştirme slot verimliliği. Titan için
	aynı petten 27 tane gerekiyor: oyunun sonundaki hedef bu.
]]
export type PetSizeDef = {
	id: string,
	name: string,
	multiplier: number,
	scale: number,       -- sahadaki model ölçeği (PetModel)
}

Config.PetSizes = {
	{ id = "Big",   name = "Big",   multiplier = 2.5, scale = 1.5 },
	{ id = "Huge",  name = "Huge",  multiplier = 5,   scale = 2.2 },
	{ id = "Titan", name = "Titan", multiplier = 10,  scale = 3.2 },
} :: { PetSizeDef }

function Config.GetPetSize(id: string?): PetSizeDef?
	if not id or id == "" then
		return nil
	end
	for _, def in Config.PetSizes do
		if def.id == id then
			return def
		end
	end
	return nil
end

--[[ Bir sonraki boyut. Normal -> Big -> Huge -> Titan -> nil. ]]
function Config.GetNextPetSize(current: PetSizeDef?): PetSizeDef?
	if not current then
		return Config.PetSizes[1]
	end
	local index = table.find(Config.PetSizes, current)
	return if index then Config.PetSizes[index + 1] else nil
end

--[[
	═══ ENVANTER ANAHTARI ══════════════════════════════════════════════════

	Envanter "anahtar -> adet" tablosu. Aynı petin Golden'ı, Huge'ı ve
	düzü AYRI satır olmalı, ama tabloyu iç içe yapmak kayıt biçimini ve
	bütün okuyucuları değiştirirdi.

	Anahtar: pet kimliği, ardından sırayla isteğe bağlı mutasyon ve boyut.

	    "MiniCrew"   "MiniCrew:Golden"   "MiniCrew:Huge"   "MiniCrew:Golden:Huge"

	Mutasyon ve boyut kimlikleri birbirinden farklı olduğu için hangisinin
	hangisi olduğu adından anlaşılıyor. Düz pet eski biçimle birebir aynı,
	yani mevcut kayıtlar olduğu gibi okunuyor.
]]
function Config.PetKey(petId: string, mutationId: string?, sizeId: string?): string
	local key = petId
	if mutationId and mutationId ~= "" then
		key ..= ":" .. mutationId
	end
	if sizeId and sizeId ~= "" then
		key ..= ":" .. sizeId
	end
	return key
end

--[[
	Anahtarı çözer: (pet, mutasyon?, boyut?). Pet, mutasyon ya da boyut
	tanınmıyorsa pet nil döner — çağıran o satırı atlamalı (Config'ten
	kalkmış bir şey kayıtta kalmış olabilir). Tanınmayanı sessizce atmak
	oyuncunun elinden bir şey almak olurdu.
]]
function Config.ParsePetKey(key: string): (PetDef?, PetMutationDef?, PetSizeDef?)
	local parts = string.split(key, ":")
	-- Config.GetPet aşağıda tanımlı; çağrı anında çözülüyor
	local def = Config.GetPet(parts[1])
	if not def or #parts > 3 then
		return nil, nil, nil
	end

	local mutation: PetMutationDef? = nil
	local size: PetSizeDef? = nil
	for i = 2, #parts do
		local part = parts[i]
		local m = Config.GetPetMutation(part)
		local s = Config.GetPetSize(part)
		if m and not mutation and not size then
			mutation = m
		elseif s and not size then
			size = s
		else
			return nil, nil, nil
		end
	end
	return def, mutation, size
end

--[[ "Golden Huge Mini Crew" gibi okunur ad. ]]
function Config.PetDisplayName(key: string): string
	local def, mutation, size = Config.ParsePetKey(key)
	if not def then
		return key
	end
	local name = def.name
	if size then
		name = size.name .. " " .. name
	end
	if mutation then
		name = mutation.name .. " " .. name
	end
	return name
end

-- Aynı anahtardan kaç kopya bir üst boyuta birleşiyor
Config.PetFuseCount = 3
--[[ Verilen kademeden eşit şansla bir pet. Yumurta çekilişinin ikinci aşaması. ]]
function Config.RollPetOfRarity(rng: Random, rarity: string): PetDef?
	local pool = {}
	for _, def in Config.Pets do
		if def.rarity == rarity then
			table.insert(pool, def)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

export type EggDef = {
	id: string,
	name: string,
	price: number,
	weights: { [string]: number },  -- nadirlik -> ağırlık
}

--[[
	Yumurtalar. Fiyatları o kademedeki karakterlerin fiyatına yakın:
	yumurta, kaideye bir karakter daha koymakla yarışmalı.
]]
Config.Eggs = {
	{ id = "SupplyEgg", name = "Supply Egg", price =         50000,
		weights = { Common = 60, Uncommon = 28, Rare = 10, Epic = 2 } },
	{ id = "SkeldEgg",  name = "Skeld Egg",  price =       2500000,
		weights = { Uncommon = 45, Rare = 33, Epic = 17, Legendary = 5 } },
	{ id = "PolusEgg",  name = "Polus Egg",  price =     150000000,
		weights = { Rare = 40, Epic = 34, Legendary = 20, Mythic = 6 } },
	{ id = "VoidEgg",   name = "Void Egg",   price =    9000000000,
		weights = { Epic = 36, Legendary = 36, Mythic = 22, Secret = 6 } },
} :: { EggDef }

local petsById: { [string]: PetDef } = {}
for _, def in Config.Pets do
	petsById[def.id] = def
end

function Config.GetPet(id: string): PetDef?
	return petsById[id]
end

function Config.GetEgg(id: string): EggDef?
	for _, def in Config.Eggs do
		if def.id == id then
			return def
		end
	end
	return nil
end

--[[
	Yumurtadan bir pet çeker.

	İki aşamalı: önce KADEME seçiliyor (yumurtanın ağırlıklarıyla), sonra
	o kademedeki petlerden biri eşit şansla. Tek aşamalı olsaydı kademede
	üç pet olması o kademeyi üç kat sık yapardı — yani yeni bir pet eklemek
	dengeyi sessizce bozardı.
]]
function Config.RollPet(rng: Random, eggId: string): PetDef?
	local egg = Config.GetEgg(eggId)
	if not egg then
		return nil
	end

	local total = 0
	for _, weight in egg.weights do
		total += weight
	end
	if total <= 0 then
		return nil
	end

	local roll = rng:NextNumber(0, total)
	local chosen: string? = nil
	for rarity, weight in egg.weights do
		roll -= weight
		if roll <= 0 then
			chosen = rarity
			break
		end
	end
	if not chosen then
		return nil
	end

	return Config.RollPetOfRarity(rng, chosen)
end

--[[
	Tek bir envanter anahtarının bonusu: petin kademe bonusu x mutasyon x boyut.
]]
function Config.GetPetKeyBonus(key: string): (number, number)
	local def, mutation, size = Config.ParsePetKey(key)
	if not def then
		return 0, 0
	end
	local mul = (if mutation then mutation.multiplier else 1) * (if size then size.multiplier else 1)
	return def.incomeBonus * mul, def.speedBonus * mul
end

--[[
	Takılı petlerin toplam bonusu. Liste envanter ANAHTARLARI tutuyor
	("MiniCrew" ya da "MiniCrew:Golden").

	Bilinmeyen anahtarlar sessizce atlanıyor: bir pet Config'den
	kaldırılırsa eski kayıtlar oyunu kırmasın.
]]
function Config.GetPetBonus(equipped: { string }): (number, number)
	local income, speed = 0, 0
	for index, key in equipped do
		if index > Config.PetEquipSlots then
			break
		end
		local i, s = Config.GetPetKeyBonus(key)
		income += i
		speed += s
	end
	return income, speed
end

-- ─── Ekipman (lobideki Gear Shop) ───────────────────────────────────────────
--[[
	Oyun içi parayla bir kez alınan, kalıcı aletler. Her doğuşta sırt
	çantasına geliyor. Steal a Brainrot'u sürükleyici yapan şey bu katman:
	kilit dışında AKTİF bir savunma (tokat) ve hareket araçları.

	Güç sınırları bilinçli:
	  - Speed Coil yalnızca TAŞIMIYORKEN işe yarıyor: çalınan karakterle
	    kaçarken hızlanmak çalmanın riskini silerdi.
	  - Gravity Coil zıplamayı iki katına çıkarıyor ama emniyet duvarları
	    40-70 stud; haritadan çıkılamıyor. Kilit fiziksel bir duvar değil,
	    zıplayarak atlatılamıyor.
	  - Slap Glove'un bekleme süresi var; hırsızı durdurur, öldürmez.
]]
export type GearDef = {
	id: string,
	name: string,
	price: number,
	blurb: string,
	walkSpeed: number?,    -- Speed Coil: elde tutarken yürüme hızı
	jumpHeight: number?,   -- Gravity Coil: elde tutarken zıplama yüksekliği
	cooldown: number?,     -- Slap Glove: iki tokat arası saniye
	range: number?,        -- Slap Glove: menzil (stud)
}

Config.Gear = {
	{ id = "SlapGlove",   name = "Slap Glove",   price =    250000, cooldown = 5, range = 8,
		blurb = "Slap a thief and they drop what they stole." },
	{ id = "GravityCoil", name = "Gravity Coil", price =    800000, jumpHeight = 15,
		blurb = "Jump twice as high while holding it." },
	{ id = "SpeedCoil",   name = "Speed Coil",   price =   1500000, walkSpeed = 27,
		blurb = "Run faster while holding it (not while carrying)." },
} :: { GearDef }

function Config.GetGear(id: string): GearDef?
	for _, def in Config.Gear do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- ─── Ödüller: günlük seri, oynama süresi, indeks ────────────────────────────
--[[
	═══ NEDEN ═══════════════════════════════════════════════════════════════

	İkisi de oyuncuyu GERİ getiren şeyler, oyunu değiştirenler değil:
	  - Günlük seri: her gün girip toplayan oyuncunun ödülü büyüyor, bir
	    gün kaçırınca seri başa dönüyor. "Yarın da gireyim" sebebi.
	  - Oynama süresi hediyeleri: oturumun 5., 10., 20. ... dakikasında
	    birer kutu. "Biraz daha kalayım" sebebi. Gün değişince sıfırlanıyor
	    (oturum değil) — çıkıp girerek aynı kutuyu tekrar almak olmasın.

	Nakit ödüller oyuncunun GELİRİNE göre (kaç saniyelik gelir) ve bir
	tabanı var: 1B kazanan oyuncuya $5K vermek anlamsız, yeni oyuncuya
	saatlik gelir vermek de dengeyi bozar.

	Ödül türleri:
	  cash   — `seconds` saniyelik gelir, en az `minimum`
	  potion — rastgele bir iksir (envantere), `count` kadar
	  egg    — bedava bir yumurta açılışı (`egg`), animasyonuyla
]]
export type RewardDef = {
	kind: string,
	seconds: number?,
	minimum: number?,
	count: number?,
	egg: string?,
	minutes: number?,   -- yalnızca oynama süresi hediyelerinde
}

Config.DailyRewards = {
	{ kind = "cash",   seconds = 60,  minimum = 5000 },
	{ kind = "potion", count = 1 },
	{ kind = "cash",   seconds = 300, minimum = 25000 },
	{ kind = "egg",    egg = "SupplyEgg" },
	{ kind = "cash",   seconds = 900, minimum = 100000 },
	{ kind = "potion", count = 2 },
	-- Yedinci gün büyük: seriyi tamamlamanın hedefi bu
	{ kind = "egg",    egg = "SkeldEgg" },
} :: { RewardDef }

Config.PlaytimeRewards = {
	{ minutes = 5,  kind = "cash",   seconds = 60,  minimum = 2000 },
	{ minutes = 10, kind = "potion", count = 1 },
	{ minutes = 20, kind = "cash",   seconds = 240, minimum = 10000 },
	{ minutes = 30, kind = "egg",    egg = "SupplyEgg" },
	{ minutes = 45, kind = "cash",   seconds = 600, minimum = 50000 },
	{ minutes = 60, kind = "egg",    egg = "SkeldEgg" },
} :: { RewardDef }

--[[
	İndeks ödülü: bir nadirliğin BÜTÜN karakterleri keşfedilince toplanan
	kalıcı gelir bonusu. Toplam +%42; tamamlanmış bir indeks bir gamepass
	kadar değerli değil ama her satır ayrı bir hedef.
	Rebirth'te sıfırlanmıyor — keşif de sıfırlanmıyor.
]]
Config.IndexRewards = {
	Common = 0.02, Uncommon = 0.03, Rare = 0.04, Epic = 0.05,
	Legendary = 0.07, Mythic = 0.09, Secret = 0.12,
} :: { [string]: number }

--[[ Nakit ödülünün tutarı: gelirin `seconds` katı, en az `minimum`. ]]
function Config.GetRewardCash(reward: RewardDef, incomePerSecond: number): number
	return math.max(reward.minimum or 0, math.floor(incomePerSecond * (reward.seconds or 0)))
end

--[[ UTC gün numarası. Günlük seri ve oynama süresi bununla sıfırlanıyor. ]]
function Config.DayIndex(now: number): number
	return math.floor(now / 86400)
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
