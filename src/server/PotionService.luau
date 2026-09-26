--!strict
-- İksir envanteri: süreli takviyeleri saklar ve oyuncu istediğinde içirir.
--
-- Neden envanter: takviyeyi kazandığı anda uygulamak, oyuncu o sırada
-- başka bir şeyle uğraşıyorsa ödülü çöpe atıyor. Envanterde duran iksiri
-- oyuncu işine geldiğinde içiyor — mesela çalmaya çıkmadan önce Fast Hands,
-- uzun bir oturum başında Double Income.
--
-- Etkinin kendisi MonetizationService'te: pass'lerle aynı yerden okunuyor,
-- böylece "pass mi iksir mi" ayrımını her servis ayrı ayrı yapmıyor.
-- Pass'i olan oyuncuya iksir üstüne binmiyor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)

local PotionService = {}

local USE_DEBOUNCE = 0.5
local PUBLISH_INTERVAL = 1

local potionsRemote: RemoteEvent
local notifyRemote: RemoteEvent

local lastUseAt: { [Player]: number } = {}
local lastSignature: { [Player]: string } = {}

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "potion"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
PotionService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
	end
end

-- ─── Envanter ───────────────────────────────────────────────────────────────

--[[
	Envantere iksir ekler. Tavana dayanmışsa eklemiyor ve false dönüyor;
	çağıran ödülü boşa harcamış saymasın diye.
]]
function PotionService.Grant(player: Player, potionId: string, count: number?): boolean
	local profile = DataService.Get(player)
	if not (profile and Config.GetPotion(potionId)) then
		return false
	end

	local current = profile.potions[potionId] or 0
	if current >= Config.PotionStackLimit then
		return false
	end

	profile.potions[potionId] = math.min(Config.PotionStackLimit, current + (count or 1))
	DataService.RequestSave(player)
	PotionService.Publish(player, true)
	return true
end

--[[ Envanterdeki adet. ]]
function PotionService.GetCount(player: Player, potionId: string): number
	local profile = DataService.Get(player)
	return if profile then (profile.potions[potionId] or 0) else 0
end

--[[
	İksiri içer: envanterden düşer ve takviyeyi başlatır.

	Aynı türden bir takviye zaten aktifse süre üstüne ekleniyor
	(MonetizationService hallediyor), yani iksir boşa gitmiyor.
]]
function PotionService.Use(player: Player, potionId: string): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local def = Config.GetPotion(potionId)
	if not def then
		notify(player, "Unknown potion", true)
		return false
	end

	local current = profile.potions[potionId] or 0
	if current <= 0 then
		notify(player, "You do not have that potion", true)
		return false
	end

	-- Önce düş, sonra uygula: uygulama hata verirse iksir geri gelmiyor ama
	-- çift içilmiş de olmuyor. Takviye vermek hata veremeyecek kadar basit.
	profile.potions[potionId] = current - 1
	if profile.potions[potionId] <= 0 then
		profile.potions[potionId] = nil
	end

	MonetizationService.GrantBoost(player, def.kind, def.seconds, def.multiplier, def.name)

	notify(player, string.format("%s active for %s",
		def.name, Config.FormatDuration(def.seconds)), false)

	DataService.RequestSave(player)
	PotionService.Publish(player, true)
	return true
end

-- ─── Yayın ──────────────────────────────────────────────────────────────────

--[[
	Envanteri ve aktif takviyeyi istemciye gönderir.

	Aktif takviyenin kalan süresi de burada: istemci os.time ile aynı
	saati okuduğu için bitiş anını gönderip geri sayımı ona bırakıyoruz,
	saniyede bir paket yollamak yerine.
]]
function PotionService.Publish(player: Player, force: boolean?)
	local profile = DataService.Get(player)
	if not (profile and potionsRemote) then
		return
	end

	local items = {}
	local signature = {}

	for _, def in Config.Potions do
		local count = profile.potions[def.id] or 0
		local remaining = MonetizationService.GetBoostRemaining(player, def.kind)

		table.insert(items, {
			id = def.id,
			name = def.name,
			description = def.description,
			kind = def.kind,
			seconds = def.seconds,
			count = count,
			activeUntil = if remaining > 0 then os.time() + remaining else 0,
		})

		table.insert(signature, string.format("%s%d%s",
			def.id, count, if remaining > 0 then "a" else ""))
	end

	local joined = table.concat(signature, "|")
	if not force and lastSignature[player] == joined then
		return
	end
	lastSignature[player] = joined

	potionsRemote:FireClient(player, items)
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function PotionService.Start()
	potionsRemote = Net.Get("Potions")
	notifyRemote = Net.Get("Notify")

	--[[
		İçme isteği. İstemciden gelen tek şey bir iksir kimliği; envanterde
		yoksa Use reddediyor. Sel basmasın diye bekletme var.
	]]
	--[[
		Mağazadan Robux'la alınan iksir (Config.Products, kind = "potion").
		Envantere giriyor; envanter o iksirde doluysa (PotionStackLimit)
		hemen içiliyor — parası ödenmiş ürün asla boşa gitmemeli, ödül
		verilemezse Roblox makbuzu tekrar tekrar gönderirdi.
	]]
	MonetizationService.RegisterGranter("potion", function(player, product)
		local id = product.potion
		local def = id and Config.GetPotion(id)
		if not def then
			return false
		end
		if PotionService.Grant(player, def.id, 1) then
			notify(player, string.format("%s added to your potions", def.name), false)
			return true
		end
		MonetizationService.GrantBoost(player, def.kind, def.seconds, def.multiplier, def.name)
		notify(player, string.format("Potions full - %s drunk right away (%s)",
			def.name, Config.FormatDuration(def.seconds)), false)
		PotionService.Publish(player, true)
		return true
	end)

	local useRemote = Net.Get("PotionUse")
	useRemote.OnServerEvent:Connect(function(player, potionId)
		if typeof(potionId) ~= "string" or #potionId > 64 then
			return
		end

		local now = os.clock()
		if now - (lastUseAt[player] or 0) < USE_DEBOUNCE then
			return
		end
		lastUseAt[player] = now

		PotionService.Use(player, potionId)
	end)

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player) and player.Parent then
				PotionService.Publish(player, true)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		lastUseAt[player] = nil
		lastSignature[player] = nil
	end)

	--[[
		Takviye bittiğinde envanter panelinin "aktif" işaretini kaldırması
		gerekiyor. İmza kontrolü sayesinde bu döngü çoğu turda hiçbir şey
		göndermiyor.
	]]
	task.spawn(function()
		while true do
			task.wait(PUBLISH_INTERVAL)
			for _, player in Players:GetPlayers() do
				PotionService.Publish(player)
			end
		end
	end)
end

return PotionService
