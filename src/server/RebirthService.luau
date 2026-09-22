--!strict
-- Rebirth: her şeyi sıfırlar, karşılığında kalıcı gelir çarpanı ve yeni kat verir.
--
-- Tavana ulaşan oyuncunun yapacak bir şeyi kalmıyordu: 8 kaide dolduktan
-- sonra biriken para hiçbir işe yaramıyordu. Rebirth o parayı harcanabilir
-- bir hedefe çeviriyor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local BadgeService = require(script.Parent.BadgeService)

local RebirthService = {}

local notifyRemote: RemoteEvent

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "rebirth"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
RebirthService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
end

-- ─── Rebirth ────────────────────────────────────────────────────────────────

--[[
	Oyuncunun rebirth yapmasını dener. Başarılıysa true döner.
	Prompt dışından da çağrılabilsin diye dışa açık.
]]
function RebirthService.TryRebirth(player: Player, skipCost: boolean?): boolean
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		notify(player, "You need a base first", true)
		return false
	end

	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	if profile.rebirths >= Config.MaxFloors - 1 then
		notify(player, "You are already at max rebirth", true)
		return false
	end

	local cost = Config.GetRebirthCost(profile.rebirths)
	if skipCost then
		-- "Anında Rebirth" ürünü: maliyet aranmıyor ama sıfırlama aynen
		-- uygulanıyor, yoksa satın alan oyuncu hem parasını hem katı alırdı
		cost = 0
	elseif not EconomyService.TrySpend(player, cost) then
		notify(player, string.format(
			"Rebirth costs $%s - you have $%s",
			Config.FormatCash(cost),
			Config.FormatCash(EconomyService.GetCash(player))
		), true)
		return false
	end

	-- Sıfırlama: kaideler boşalır, nakit başlangıca döner.
	-- Kalan parayı da alıyoruz; rebirth "her şeyi bırak" demek.
	for _, podium in PlotService.GetPodiums(plot) do
		if PlotService.IsOccupied(podium) then
			PlotService.ClearUnit(podium)
		end
	end

	EconomyService.AddCash(player, Config.StartingCash - EconomyService.GetCash(player))

	--[[
		Yükseltmeler de sıfırlanıyor.

		Kalıcı olsalardı rebirth'ten sonra harcanacak yer yine kalmazdı:
		tavanı zaten doldurmuş oyuncu için rebirth sadece bir çarpan
		olurdu. Sıfırlanınca kat başına ikiye katlanan tavan da anlam
		kazanıyor — yeni katla birlikte baştan ve daha uzun bir yol.

		Satın alınan KAT sıfırlanmıyor; o parayla alındı ve kalıcı.
	]]
	profile.upgrades = {}

	profile.rebirths += 1
	-- Kat artık rebirth ödülü değil, parayla alınıyor. Yine de burada
	-- çağırıyoruz: satın alınmış katlar sıfırlamadan sağ çıkmalı.
	PlotService.SetUnlockedFloors(plot, Config.GetUnlockedFloors(profile.floorsBought))
	PlotService.RefreshSign(plot)

	local multiplier = Config.GetIncomeMultiplier(profile.rebirths)

	--[[
		Mesaj eskiden "floor N unlocked" diyordu ve artık yalan olurdu:
		rebirth katı vermiyor, satın alma hakkını veriyor. Yeni bir kat
		açıldıysa onu söylüyoruz, açılmadıysa sadece çarpanı.
	]]
	local next = Config.GetNextFloor(profile.floorsBought)
	if next and profile.rebirths >= next.rebirths then
		notify(player, string.format(
			"REBIRTH %d! Income x%.1f  ·  Floor %d now available for $%s",
			profile.rebirths, multiplier, next.floor, Config.FormatCash(next.cost)
		), false)
	else
		notify(player, string.format(
			"REBIRTH %d! Income x%.1f",
			profile.rebirths, multiplier
		), false)
	end

	BadgeService.Award(player, "FirstRebirth")

	-- Rebirth pahalı ve geri alınamaz; bir sonraki autosave'i beklemeyelim
	DataService.Save(player)
	return true
end

-- ─── İstek ──────────────────────────────────────────────────────────────────
--[[
	PROMPT KALDIRILDI.

	Rebirth üssün önündeki tabelaya bağlı bir "R'ye basılı tut"tu. İki
	sorunu vardı: oyunun en büyük kararı sıradan bir promptun arkasında
	duruyordu, ve rakibin üssüne giden oyuncu yanlışlıkla kendi tabelasına
	basıp rebirth atabiliyordu.

	Artık arayüzden: oyuncu ne kaybedeceğini (kaideler, yükseltmeler) ve ne
	kazanacağını görüp onaylıyor. Doğrulama değişmedi, TryRebirth aynı.
]]

function RebirthService.Start()
	notifyRemote = Net.Get("Notify")

	MonetizationService.RegisterGranter("rebirth", function(player)
		return RebirthService.TryRebirth(player, true)
	end)

	--[[ Arayüzün göstermesi için: kaçıncı rebirth ve sıradakinin fiyatı.
	     Nitelik kendiliğinden replike oluyor, remote gerekmiyor. ]]
	local function publish(player: Player)
		local profile = DataService.Get(player)
		local rebirths = if profile then profile.rebirths else 0
		player:SetAttribute("Rebirths", rebirths)
		player:SetAttribute("RebirthCost", Config.GetRebirthCost(rebirths))
	end

	local lastTry: { [Player]: number } = {}

	Net.Get("RebirthBuy").OnServerEvent:Connect(function(player)
		local now = os.clock()
		if now - (lastTry[player] or 0) < 1 then
			return
		end
		lastTry[player] = now

		RebirthService.TryRebirth(player)
		publish(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
	end)

	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				publish(player)
			end
			task.wait(2)
		end
	end)
end

return RebirthService
