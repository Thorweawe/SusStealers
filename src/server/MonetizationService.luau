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

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError)
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

function MonetizationService.GetIncomeMultiplier(player: Player): number
	return if MonetizationService.HasPass(player, "DoubleIncome")
		then Config.PassDoubleIncomeMultiplier
		else 1
end

function MonetizationService.GetExtraPodiumsPerFloor(player: Player): number
	return if MonetizationService.HasPass(player, "ExtraPodiums")
		then Config.PassExtraPodiumsPerFloor
		else 0
end

function MonetizationService.GetStealHoldMultiplier(player: Player): number
	return if MonetizationService.HasPass(player, "FastSteal")
		then Config.PassFastStealMultiplier
		else 1
end

--[[ Kilit süresi ve bekleme süresi. ]]
function MonetizationService.GetLockValues(player: Player): (number, number)
	if MonetizationService.HasPass(player, "StrongLock") then
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
end

return MonetizationService
