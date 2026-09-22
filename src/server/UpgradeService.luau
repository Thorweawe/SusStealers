--!strict
-- Üs yükseltmeleri: oyun içi parayla alınan kalıcı iyileştirmeler.
--
-- Nakdin karakter almak dışında bir harcama yeri yoktu; kaideler dolunca
-- para birikip anlamsızlaşıyordu. Robux ürünlerinin aksine bunlar herkese
-- açık, tek şart yeterince oynamış olmak.
--
-- Her üste bir yükseltme kulübesi var (PlotService kuruyor). Oyuncu
-- kulübenin önündeki alana basınca istemcideki UpgradePanel açılıyor;
-- bu servis sadece seviyeleri yayınlıyor ve satın alma isteğini doğruluyor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)

local UpgradeService = {}

local notifyRemote: RemoteEvent

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "upgrade"

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
	end
end

-- ─── Seviye ─────────────────────────────────────────────────────────────────

--[[ Oyuncunun bir yükseltmedeki seviyesi. Profili yoksa 0. ]]
function UpgradeService.GetLevel(player: Player, id: string): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	return profile.upgrades[id] or 0
end

--[[ Üssün sahibinin seviyesi. Sahipsiz üste 0. ]]
function UpgradeService.GetPlotLevel(plot: Model, id: string): number
	local owner = PlotService.GetOwner(plot)
	if not owner then
		return 0
	end
	return UpgradeService.GetLevel(owner, id)
end

-- ─── Satın alma ─────────────────────────────────────────────────────────────

--[[ Yükseltmeyi bir seviye yükseltmeyi dener. ]]
function UpgradeService.TryUpgrade(player: Player, id: string): boolean
	local def = Config.GetUpgrade(id)
	if not def then
		return false
	end

	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local level = profile.upgrades[id] or 0
	local floors = Config.GetUnlockedFloors(profile.floorsBought)
	local cost = Config.GetUpgradeCost(id, level, floors)

	if not cost then
		--[[
			Tavan kat sayısına bağlı. Oyuncu tavana dayandıysa mesaj bunu
			söylemeli, yoksa "maxed" görüp yükseltmenin bittiğini sanıyor —
			oysa bir üst kat alınca devamı geliyor.
		]]
		if floors < Config.MaxFloors then
			notify(player, string.format(
				"%s is maxed for floor %d - buy the next floor to raise the cap",
				def.name, floors
			), true)
		else
			notify(player, string.format("%s is fully maxed", def.name), true)
		end
		return false
	end

	if not EconomyService.TrySpend(player, cost) then
		notify(player, string.format(
			"%s costs $%s - you have $%s",
			def.name, Config.FormatCash(cost),
			Config.FormatCash(EconomyService.GetCash(player))
		), true)
		return false
	end

	profile.upgrades[id] = level + 1
	UpgradeService.PublishLevels(player)
	notify(player, string.format("%s upgraded to level %d", def.name, level + 1), false)
	return true
end

--[[
	Seviyeleri oyuncunun niteliklerine yazar.

	Arayüzün seviyeyi bilmesi gerekiyor ama bunun için ayrı bir remote
	açmaya gerek yok: nitelikler kendiliğinden replike oluyor ve sadece
	sunucu yazabiliyor. İstemci `player:GetAttribute("Upg_LockPower")`
	diyerek okuyor, maliyeti de Config'ten kendisi hesaplıyor.
]]
function UpgradeService.PublishLevels(player: Player)
	local profile = DataService.Get(player)
	local floors = if profile then Config.GetUnlockedFloors(profile.floorsBought) else 1

	for _, def in Config.Upgrades do
		player:SetAttribute("Upg_" .. def.id, UpgradeService.GetLevel(player, def.id))
	end

	-- Arayüz tavanı da bilmeli: kaç kutucuk çizeceğini ve "maxed" mi
	-- diyeceğini buna göre belirliyor
	player:SetAttribute("UpgradeFloors", floors)
end

--[[ Oyuncunun o anki yükseltme tavanı. ]]
function UpgradeService.GetMaxLevel(player: Player, id: string): number
	local def = Config.GetUpgrade(id)
	if not def then
		return 0
	end
	local profile = DataService.Get(player)
	local floors = if profile then Config.GetUnlockedFloors(profile.floorsBought) else 1
	return Config.GetUpgradeMaxLevel(def, floors)
end


-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function UpgradeService.Start()
	notifyRemote = Net.Get("Notify")

	--[[
		FİZİKSEL PANOLAR KALDIRILDI.

		Her üsse dört tabela dikiliyordu; kulübenin tezgâhına taşınınca da
		altı tabela 15 studluk tezgâha sığmıyor, birbirine ve direklere
		giriyordu ("bazı üslerde iç içe giriyor"). Üstelik tezgâhın etrafı
		gereksiz nesneyle doluyordu.

		Yerine kulübenin önündeki alana basınca açılan bir arayüz geçti
		(istemcideki UpgradePanel). Kulübede artık tek bir çift yüzlü
		"UPGRADES" tabelası var, gerisi arayüzde.
	]]

	--[[
		Satın alma isteği. Doğrulama TryUpgrade'in içinde: üs sahibi mi,
		seviye tavanda mı, parası yetiyor mu. Buradaki tek ek iş hız sınırı —
		istemci istediği sıklıkta tetikleyebilir.
	]]
	local lastBuy: { [Player]: number } = {}

	Net.Get("UpgradeBuy").OnServerEvent:Connect(function(player, id)
		if typeof(id) ~= "string" then
			return
		end

		local now = os.clock()
		if now - (lastBuy[player] or 0) < 0.15 then
			return
		end
		lastBuy[player] = now

		-- Üssü olmayan oyuncu yükseltme alamaz
		if not PlotService.GetPlotOf(player) then
			notify(player, "You need a base first", true)
			return
		end

		UpgradeService.TryUpgrade(player, id)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)

	--[[
		Seviyeler nitelik olarak yayınlanıyor. Profil girişten sonra
		yükleniyor, o yüzden ilk yayın için kısa bir döngü var; her servise
		kanca takmaktan basit ve saniyede bir yazmak bedava.
	]]
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				UpgradeService.PublishLevels(player)
			end
			task.wait(2)
		end
	end)
end

return UpgradeService
