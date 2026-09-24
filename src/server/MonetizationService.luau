--!strict
-- Gamepass ve developer product satın almaları.
--
-- İki ayrı sorumluluk var:
--   1. Gamepass sahipliği: kalıcı, Roblox'ta duruyor. Her sorguda Roblox'a
--      gitmek yavaş ve kotalı, o yüzden oturum boyunca önbelleğe alınıyor.
--   2. Developer product: tek seferlik ödeme, ödülü biz vermek zorundayız.
--      ProcessReceipt bu işin kritik yeri, aşağıda ayrıca açıklandı.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local MonetizationService = {}

local notifyRemote: RemoteEvent

-- oyuncu -> pass anahtarı -> sahiplik
local passCache: { [Player]: { [string]: boolean } } = {}

-- Ödülü veren fonksiyonlar dışarıdan bağlanıyor. Böylece bu modül
-- ConveyorService / RebirthService'i require etmiyor ve döngüsel
-- bağımlılık oluşmuyor.
type Granter = (player: Player, product: Config.ProductDef) -> boolean
local granters: { [string]: Granter } = {}

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "purchase"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
MonetizationService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
	end
end

-- ─── Gamepass ───────────────────────────────────────────────────────────────

--[[
	Oyuncunun pass'i var mı. Sonuç oturum boyunca önbellekte tutuluyor:
	UserOwnsGamePassAsync ağ çağrısı ve kotalı, gelir döngüsünde saniyede
	bir çağrılamaz.

	Oyun sırasında satın alınırsa PromptGamePassPurchaseFinished önbelleği
	tazeliyor, yani oyuncunun yeniden girmesi gerekmiyor.
]]
function MonetizationService.HasPass(player: Player, key: string): boolean
	local def = Config.GamePasses[key]
	if not def or def.id == 0 then
		return false
	end

	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end

	if cache[key] ~= nil then
		return cache[key]
	end

	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
	end)

	-- Hata olursa false önbelleklemiyoruz; geçici bir ağ sorunu yüzünden
	-- oyuncunun satın aldığı şeyi oturum boyunca kaybetmesi kabul edilemez.
	if not ok then
		warn(string.format("[Monetization] %s icin %s sorgulanamadi", player.Name, key))
		return false
	end

	cache[key] = owns
	return owns
end

-- ─── Etki noktaları ─────────────────────────────────────────────────────────

--[[
	Süreli takviyeler — iksir mantığı.

	Görev ödülü olarak veriliyor ve HEPSİ süreli. Kalıcı pass'i bedava
	dağıtmak satışı öldürürdü; süreli olanı öldürmüyor, tersine ne
	kaçırdığını gösteriyor.

	Pass'i olan oyuncuya ÜSTÜNE binmiyor (max alınıyor), yoksa parasını
	veren oyuncu bedava ödülle daha da öne geçerdi.

	Süre os.time ile tutuluyor, os.clock ile değil: istemci kalan süreyi
	kendi saatinden hesaplayabilsin diye.
]]
type Boost = { until_: number, multiplier: number, name: string }

local boosts: { [Player]: { [string]: Boost } } = {}

local function boostOf(player: Player, kind: string): Boost?
	local own = boosts[player]
	local boost = own and own[kind]
	if boost and boost.until_ > os.time() then
		return boost
	end
	return nil
end

--[[
	Takviye verir. Aynı tür zaten aktifse süre ÜSTÜNE ekleniyor; oyuncu
	aktifken ikinci kez kazanırsa ödül boşa gitmesin.
]]
function MonetizationService.GrantBoost(player: Player, kind: string, seconds: number, multiplier: number?, name: string?)
	local own = boosts[player]
	if not own then
		own = {}
		boosts[player] = own
	end

	local now = os.time()
	local existing = own[kind]
	local base = if existing and existing.until_ > now then existing.until_ else now

	own[kind] = {
		until_ = base + seconds,
		multiplier = math.max(if existing and existing.until_ > now then existing.multiplier else 1, multiplier or 1),
		name = name or kind,
	}

	-- İstemci kalan süreyi göstersin diye nitelik olarak da yayınlıyoruz
	player:SetAttribute("BoostName", own[kind].name)
	player:SetAttribute("BoostUntil", own[kind].until_)
end

--[[
	Oyuncunun bütün takviyelerini siler.

	Testler için: her test kendi ortamını kurmalı ve bir önceki testin
	açtığı on dakikalık takviye ölçümü bozmamalı. Koşu sonunda da
	çağrılıyor ki test, canlı oturuma takviye sızdırmasın.
]]
function MonetizationService.ClearBoosts(player: Player)
	boosts[player] = nil
	player:SetAttribute("BoostName", nil)
	player:SetAttribute("BoostUntil", nil)
end

--[[ Takviyeden kalan saniye. Yoksa 0. ]]
function MonetizationService.GetBoostRemaining(player: Player, kind: string): number
	local boost = boostOf(player, kind)
	return if boost then boost.until_ - os.time() else 0
end

function MonetizationService.GetIncomeMultiplier(player: Player): number
	local fromPass = if MonetizationService.HasPass(player, "DoubleIncome")
		then Config.PassDoubleIncomeMultiplier
		else 1

	local boost = boostOf(player, "income")
	local fromBoost = if boost then boost.multiplier else 1

	-- Çarpmıyor, büyüğünü alıyor: ikisi üst üste binmemeli
	return math.max(fromPass, fromBoost)
end

function MonetizationService.GetExtraPodiumsPerFloor(player: Player): number
	return if MonetizationService.HasPass(player, "ExtraPodiums")
		then Config.PassExtraPodiumsPerFloor
		else 0
end

function MonetizationService.GetStealHoldMultiplier(player: Player): number
	-- Üst üste binmiyor: pass varsa pass, yoksa iksir
	if MonetizationService.HasPass(player, "FastSteal") then
		return Config.PassFastStealMultiplier
	end
	if boostOf(player, "steal") then
		return Config.PotionFastStealMultiplier
	end
	return 1
end

--[[
	Çalma çarpanını istemciye nitelik olarak yayınlar. İstemci kendi
	ekranındaki çalma promptunu buna göre kısaltıyor (PromptFilter);
	yoksa sunucu kısa basışı kabul etse de prompt tam süreyi bekliyordu.
]]
function MonetizationService.PublishStealHold(player: Player)
	local mul = MonetizationService.GetStealHoldMultiplier(player)
	if player:GetAttribute("StealHoldMul") ~= mul then
		player:SetAttribute("StealHoldMul", mul)
	end
end

--[[ Kilit süresi ve bekleme süresi. ]]
function MonetizationService.GetLockValues(player: Player): (number, number)
	if MonetizationService.HasPass(player, "StrongLock")
		or boostOf(player, "lock")
	then
		return Config.PassStrongLockDuration, Config.PassStrongLockCooldown
	end
	return Config.LockDuration, Config.LockCooldown
end

-- ─── Developer product ──────────────────────────────────────────────────────

--[[
	Bir ürün tipi için ödül verme fonksiyonu kaydeder.
	ConveyorService ve RebirthService kendi ödüllerini böyle bağlıyor.
]]
function MonetizationService.RegisterGranter(kind: string, granter: Granter)
	granters[kind] = granter
end

local function findProduct(productId: number): Config.ProductDef?
	for _, def in Config.Products do
		if def.id ~= 0 and def.id == productId then
			return def
		end
	end
	return nil
end

--[[ Makbuz daha önce işlendi mi. Profilde tutuluyor. ]]
local function receiptSeen(profile: any, purchaseId: string): boolean
	return table.find(profile.receipts, purchaseId) ~= nil
end

local function rememberReceipt(profile: any, purchaseId: string)
	table.insert(profile.receipts, purchaseId)

	-- Sınırsız büyümesin; en eskiyi at
	while #profile.receipts > Config.ReceiptHistoryLimit do
		table.remove(profile.receipts, 1)
	end
end

--[[
	Satın alma tamamlandığında Roblox burayı çağırır.

	İki tehlike var ve ikisi de para kaybettiriyor:
	  - PurchaseGranted dönüp ödülü kaydetmezsek oyuncu öder, hiçbir şey almaz.
	  - Aynı makbuzu iki kez işlersek bir ödemeden iki ödül çıkar.

	Bu yüzden: ödül profile yazılıyor, makbuz kimliği de aynı profile
	kaydediliyor ve profil hemen diske yazılıyor. Yazma başarısızsa
	NotProcessedYet dönüyoruz; Roblox aynı makbuzu tekrar gönderiyor.
	Tekrar geldiğinde makbuz profilde görülüyor ve ödül ikinci kez
	verilmiyor, yalnızca kaydetme yeniden deneniyor.
]]
local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Oyuncu gitti; işlemedik. Roblox geri geldiğinde tekrar gönderir.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.Get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)

	-- Bu oturumda zaten verdik; sadece kalıcı hale gelmesini garantile
	if receiptSeen(profile, purchaseId) then
		return if DataService.Save(player)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local def = findProduct(receiptInfo.ProductId)
	if not def then
		-- Tanımadığımız ürün. Granted dönmek parayı yakar, o yüzden
		-- işlemiyoruz: Config'e eklenince tekrar denenecek.
		warn(string.format("[Monetization] Bilinmeyen urun: %d", receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local granter = granters[def.kind]
	if not granter then
		warn(string.format("[Monetization] '%s' tipi icin odul fonksiyonu yok", def.kind))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(granter, player, def)
	if not ok or not granted then
		warn(string.format("[Monetization] %s icin %s verilemedi", player.Name, def.name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	rememberReceipt(profile, purchaseId)

	if not DataService.Save(player) then
		-- Ödül bellekte duruyor ama diske yazılamadı. Granted demiyoruz;
		-- Roblox tekrar deneyecek ve yukarıdaki makbuz kontrolü ikinci
		-- ödülü engelleyecek.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	notify(player, string.format("%s purchased", def.name), false)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ─── Satın alma istemi ──────────────────────────────────────────────────────

function MonetizationService.PromptPass(player: Player, key: string)
	local def = Config.GamePasses[key]
	if not def or def.id == 0 then
		notify(player, "That item is not available yet", true)
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, def.id)
end

function MonetizationService.PromptProduct(player: Player, key: string)
	local def = Config.Products[key]
	if not def or def.id == 0 then
		notify(player, "That item is not available yet", true)
		return
	end
	MarketplaceService:PromptProductPurchase(player, def.id)
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
	boosts[player] = nil
end)

function MonetizationService.Start()
	notifyRemote = Net.Get("Notify")

	MarketplaceService.ProcessReceipt = processReceipt

	-- Oyun içinde pass alındığında önbelleği tazele, yeniden girmesin
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end

		for key, def in Config.GamePasses do
			if def.id == passId then
				local cache = passCache[player]
				if not cache then
					cache = {}
					passCache[player] = cache
				end
				cache[key] = true
				notify(player, string.format("%s unlocked!", def.name), false)
				break
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)

	-- İksir süresi dolunca da nitelik düşmeli; saniyede bir bakmak yeter
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				task.spawn(MonetizationService.PublishStealHold, player)
			end
			task.wait(1)
		end
	end)
end

return MonetizationService
