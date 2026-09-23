--!strict
-- Üst katların oyun içi parayla satın alınması.
--
-- Neden var: kat eskiden doğrudan rebirth ödülüydü. Rebirth zaten kalıcı
-- gelir çarpanı veriyordu, kat da bedava gelince rebirth tek başına her
-- şeydi ve biriken paranın rebirth dışında harcanacak büyük bir yeri
-- yoktu.
--
-- Şimdi ikisi ayrı: rebirth katın KİLİDİNİ açıyor, kat parayla alınıyor.
-- "5 milyarı 2. kata mı yatırayım yoksa 8 milyarlık rebirth'e mi
-- saklayayım" gerçek bir karar.
--
-- Kat, üssün yükseltme kulübesindeki NEW FLOOR satırından alınıyor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local FloorService = {}

local REFRESH_INTERVAL = 2

local notifyRemote: RemoteEvent

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "floor"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
FloorService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
	end
end

--[[
	Eskiden burada her üsse bir satın alma PEDİ kuruluyordu: merdivenin
	dibinde neon bir levha, ışık sütunu ve "FLOOR 3 · Needs 2 rebirth ·
	$150B" yazan bir tabela. Tabela her üste, rakiplerinkine de çıkıyor
	ve haritayı kalabalıklaştırıyordu; oyuncular da kat almak için zaten
	yükseltme kulübesini (NEW FLOOR satırı) kullanıyordu.

	Ped kaldırıldı. Kat yalnızca kulübeden alınıyor; iki yol da aynı
	TryBuy'a çıkıyordu, doğrulamada değişen bir şey yok.
]]
-- ─── Satın alma ─────────────────────────────────────────────────────────────

--[[
	Sıradaki katı satın alır.

	Sıralı: 3. kat 2. kat alınmadan satın alınamıyor, yoksa arada boş kat
	kalırdı. Rebirth koşulu burada aranıyor ve sonradan geri alınmıyor —
	oyuncu parasını ödedi.
]]
function FloorService.TryBuy(player: Player): boolean
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		notify(player, "You need a base first", true)
		return false
	end

	if PlotService.GetOwner(plot) ~= player then
		notify(player, "Not your base", true)
		return false
	end

	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local def = Config.GetNextFloor(profile.floorsBought)
	if not def then
		notify(player, "You already own every floor", true)
		return false
	end

	if profile.rebirths < def.rebirths then
		notify(player, string.format(
			"Floor %d needs %d rebirth%s - you have %d",
			def.floor, def.rebirths,
			if def.rebirths == 1 then "" else "s",
			profile.rebirths
		), true)
		return false
	end

	if not EconomyService.TrySpend(player, def.cost) then
		notify(player, string.format(
			"Floor %d costs $%s - you have $%s",
			def.floor,
			Config.FormatCash(def.cost),
			Config.FormatCash(EconomyService.GetCash(player))
		), true)
		return false
	end

	profile.floorsBought += 1
	PlotService.SetUnlockedFloors(plot, Config.GetUnlockedFloors(profile.floorsBought))
	FloorService.Publish(player)

	notify(player, string.format("Floor %d unlocked!", def.floor), false)

	-- Pahalı ve geri alınamaz; bir sonraki autosave'i beklemeyelim
	DataService.Save(player)
	return true
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

--[[
	Kat ve rebirth sayısını oyuncunun niteliklerine yazar.

	Arayüzün "sıradaki kat hangisi, kaç rebirth istiyor, kaç para" diye
	göstermesi için bu iki sayı yeterli; gerisini Config'ten kendisi
	hesaplıyor. Nitelik kullanıldı çünkü kendiliğinden replike oluyor ve
	sadece sunucu yazabiliyor.
]]
function FloorService.Publish(player: Player)
	local profile = DataService.Get(player)
	player:SetAttribute("FloorsBought", if profile then profile.floorsBought else 0)
	player:SetAttribute("Rebirths", if profile then profile.rebirths else 0)
end

function FloorService.Start()
	notifyRemote = Net.Get("Notify")

	-- Kat yükseltme kulübesindeki NEW FLOOR satırından alınıyor
	local lastBuy: { [Player]: number } = {}

	Net.Get("FloorBuy").OnServerEvent:Connect(function(player)
		local now = os.clock()
		if now - (lastBuy[player] or 0) < 0.4 then
			return
		end
		lastBuy[player] = now
		FloorService.TryBuy(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)

	--[[
		Rebirth başka serviste değişiyor ve olay yayını yok; arayüzün
		kat satırını doğru göstermesi için nitelikler iki saniyede bir
		tazeleniyor.
	]]
	task.spawn(function()
		while true do
			task.wait(REFRESH_INTERVAL)
			for _, player in Players:GetPlayers() do
				FloorService.Publish(player)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			if DataService.WaitForProfile(player) then
				FloorService.Publish(player)
			end
		end)
	end)
end

return FloorService