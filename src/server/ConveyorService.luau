--!strict
-- Her üssün konveyöründe karakter üretir, kaydırır, satın alma promptunu yönetir.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local UnitModel = require(Shared.UnitModel)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local MonetizationService = require(script.Parent.MonetizationService)
local UpgradeService = require(script.Parent.UpgradeService)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)
local AnnounceService = require(script.Parent.AnnounceService)

local ConveyorService = {}

local rng = Random.new()
local notifyRemote: RemoteEvent

type ConveyorItem = {
	model: Model,
	plot: Model,
	unitId: string,
	mutationId: string?,
	price: number,
	startCFrame: CFrame,
	travel: number,
	-- Bant saatinin bu değere geldiği an karakter kapağın ağzında (konum 0)
	spawnDistance: number,
	prompt: ProximityPrompt,
	label: BillboardGui,
	visible: boolean,
}

local activeItems: { ConveyorItem } = {}

--[[
	═══ BANT SAATİ ══════════════════════════════════════════════════════════

	Her üssün bandının tek bir "kat edilen yol" sayacı var:

	    D(t) = distance + speed × (t − stamp)

	Karakterin banttaki konumu D(t) − spawnDistance. Banttaki gri çıtalar da
	istemcide AYNI sayaçtan çiziliyor (ConveyorFX): çıta k'nın konumu
	(k × aralık + D) mod bant boyu. Karakterler D'nin çıta aralığının tam
	katına geldiği anda ağza varıyor, yani her karakter bir çıtanın üstünde
	kapaktan çıkıyor ve o çıtayla birlikte ilerliyor.

	Hız değişince (Conveyor Speed yükseltmesi, sahip değişimi) sayaç o anda
	sabitleniyor ve yeni hızla devam ediyor: karakterler de çıtalar da aynı
	anda hızlanıyor, hiçbiri sıçramıyor.

	İstemciye Conveyor parçasının nitelikleriyle gidiyor: BeltSpeed,
	BeltDistance, BeltStamp (workspace:GetServerTimeNow saniyesi).
]]
type Belt = { distance: number, stamp: number, speed: number }
local belts: { [Model]: Belt } = {}

-- Art arda alınamayan karakter sayısı (Config.ConveyorPityAfter)
local missStreak: { [Model]: number } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function beltDistance(belt: Belt, now: number): number
	return belt.distance + belt.speed * (now - belt.stamp)
end

--[[ Üssün bandını sahibin yükseltme seviyesine göre günceller ve döner. ]]
local function syncBelt(plot: Model, conveyor: BasePart, now: number): Belt
	local owner = PlotService.GetOwner(plot)
	local level = if owner then UpgradeService.GetLevel(owner, "ConveyorSpeed") else 0
	local speed = Config.GetConveyorBeltSpeed(level)

	local belt = belts[plot]
	if belt and belt.speed == speed then
		return belt
	end

	if belt then
		belt.distance = beltDistance(belt, now)
		belt.stamp = now
		belt.speed = speed
	else
		belt = { distance = 0, stamp = now, speed = speed }
		belts[plot] = belt
	end

	conveyor:SetAttribute("BeltSpeed", belt.speed)
	conveyor:SetAttribute("BeltDistance", belt.distance)
	conveyor:SetAttribute("BeltStamp", belt.stamp)
	return belt
end

--[[ Karakterlerin bantta gittiği yol (Conveyor boyundan türetiliyor). ]]
local function beltTravel(conveyor: BasePart): number
	return conveyor.Size.X - 4
end

-- "Garantili mutasyon" satin alan oyuncunun ussu. Bir sonraki uretimde
-- harcaniyor: mutasyon cikmazsa zorla veriliyor, yani para verip bos
-- cikma ihtimali yok.
local luckyPlots: { [Model]: boolean } = {}

-- ─── Üretim ─────────────────────────────────────────────────────────────────

--[[
	Sunucu geneli duyurulacak kademeler. Mythic ve üstü: konveyörde nadir
	çıkıyor, çalınmaya değer ve oyuncuların haberdar olması oyunu
	canlandırıyor. Daha aşağısı kanalı gürültüyle doldururdu.
]]
local ANNOUNCE_RARITIES = { Mythic = true, Secret = true }

--[[ Konveyöre bir karakter düşürür. ]]
local function spawnItem(plot: Model): Config.UnitDef?
	local conveyor = plot:FindFirstChild("Conveyor")
	local items = plot:FindFirstChild("Items")
	if not (conveyor and conveyor:IsA("Part") and items) then
		return nil
	end

	--[[
		Nadirlik havuzu konveyör seviyesine bağlı. Yeni oyuncunun ilk
		dakikasında Amogus Prime görmesi hem ilerleme hissini yok ediyordu
		hem de ConveyorSpeed upgrade'ini sadece "daha sık" yapıyordu;
		artık "daha iyi" de oluyor.
	]]
	local owner = PlotService.GetOwner(plot)
	local conveyorLevel = if owner then UpgradeService.GetLevel(owner, "ConveyorSpeed") else 0

	--[[
		Bütçe koruması (Config.ConveyorPityAfter). Garantili mutasyon
		satın alınmışsa devreye girmiyor: oyuncu Robux verdi, havuzu
		daraltmak ödediği şeyi küçültürdü.
	]]
	local lucky = luckyPlots[plot] == true
	local budget: number? = nil
	if owner and not lucky then
		local cash = EconomyService.GetCash(owner)
		local broke = EconomyService.GetIncome(owner) <= 0
		local pity = (missStreak[plot] or 0) >= Config.ConveyorPityAfter
		if (broke or pity) and cash >= Config.GetCheapestUnitPrice() then
			budget = cash
		end
	end

	local def = if budget then Config.RollAffordableUnit(rng, conveyorLevel, budget) else Config.RollUnit(rng, conveyorLevel)
	local mutation = Config.RollMutation(rng)

	-- Garanti satin alindiysa mutasyon cikana kadar cek
	if lucky then
		luckyPlots[plot] = nil
		while not mutation do
			mutation = Config.RollMutation(rng)
		end
	end

	-- Bütçeli çekilişte mutasyonlu fiyat bütçeyi aşıyorsa düz gelsin
	if budget and mutation and Config.GetPrice(def.id, mutation.id) > budget then
		mutation = nil
	end

	local mutationId = if mutation then mutation.id else nil
	local price = Config.GetPrice(def.id, mutationId)

	-- Art arda alınamayan sayacı: sahip bu karakteri alabiliyorsa sıfırla
	if owner then
		if price <= EconomyService.GetCash(owner) then
			missStreak[plot] = 0
		else
			missStreak[plot] = (missStreak[plot] or 0) + 1
		end
	end

	local model = UnitModel.Build(def.id, mutationId)
	model.Name = "ConveyorItem"

	local travel = beltTravel(conveyor)
	local startCFrame = conveyor.CFrame * CFrame.new(-travel / 2, conveyor.Size.Y / 2, 0)

	--[[
		Karakter bir sonraki çıtaya hizalanıyor: bant saati çıta aralığının
		bir sonraki katına geldiğinde ağızda olacak. O ana kadar (en fazla
		bir çıta aralığı) kapağın içinde bekliyor, sonra çıtasıyla çıkıyor.
	]]
	local now = serverNow()
	local belt = syncBelt(plot, conveyor, now)
	local gap = travel / Config.ConveyorSlats
	local spawnDistance = (math.floor(beltDistance(belt, now) / gap) + 1) * gap
	local position = beltDistance(belt, now) - spawnDistance
	model:PivotTo(startCFrame * CFrame.new(position, 0, 0))

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local label = UnitModel.BuildLabel(def.id, mutationId)
	-- Kapağın içindeyken etiket görünmesin; ağızdan çıkınca açılıyor
	label.Enabled = false
	label.Parent = model.PrimaryPart

	-- Satın alma promptu
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy"
	prompt.ObjectText = string.format("$%s", Config.FormatCash(price))
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	-- İstemcideki PromptFilter Enabled'ı yerelde yeniden yazıyor; kapağın
	-- içindeyken açmasın diye durum ayrıca nitelikle gidiyor
	prompt:SetAttribute("OnBelt", false)
	prompt.Parent = model.PrimaryPart

	-- İstemci (ConveyorFX) karakteri kendi karesinde bant saatine göre çiziyor
	model:SetAttribute("BeltStart", startCFrame)
	model:SetAttribute("SpawnDistance", spawnDistance)
	model:SetAttribute("Travel", travel)

	model.Parent = items

	local item: ConveyorItem = {
		model = model,
		plot = plot,
		unitId = def.id,
		mutationId = mutationId,
		price = price,
		startCFrame = startCFrame,
		travel = travel,
		spawnDistance = spawnDistance,
		prompt = prompt,
		label = label,
		visible = false,
	}
	table.insert(activeItems, item)

	PromptGuard.Connect(prompt, function(player)
		ConveyorService.TryBuy(player, item, prompt)
	end)

	-- Kendi bandında gördüğün karakter indekste "keşfedildi" oluyor
	if owner then
		DataService.Discover(owner, def.id)
	end

	-- Nadir çıkış Summons kanalında herkese duyuruluyor
	if owner and ANNOUNCE_RARITIES[def.rarity] then
		local rarity = Config.Rarities[def.rarity]
		local name = if mutation then mutation.name .. " " .. def.name else def.name
		AnnounceService.Summon(string.format("%s appeared on %s's conveyor!",
			AnnounceService.Paint(name, rarity.color), owner.DisplayName))
	end

	return def
end

-- ─── Satın alma ─────────────────────────────────────────────────────────────

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "buy"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
ConveyorService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
end

function ConveyorService.TryBuy(player: Player, item: ConveyorItem, prompt: ProximityPrompt)
	if item.model.Parent == nil or not item.visible then
		return
	end

	local plot = PlotService.GetPlotOf(player)
	if not plot then
		notify(player, "You need a base first", true)
		return
	end

	if plot ~= item.plot then
		notify(player, "Not your conveyor", true)
		return
	end

	local podium = PlotService.FindEmptyPodium(plot)
	if not podium then
		notify(player, "No free podium", true)
		return
	end

	if not EconomyService.TrySpend(player, item.price) then
		notify(player, "Not enough cash", true)
		return
	end

	prompt.Enabled = false
	PlotService.PlaceUnit(podium, item.unitId, item.mutationId)
	DataService.Bump(player, "bought")

	local def = Config.GetUnit(item.unitId)
	notify(player, string.format("%s purchased", if def then def.name else item.unitId), false)

	item.model:Destroy()
end

-- ─── Döngü ──────────────────────────────────────────────────────────────────

--[[
	PERFORMANS: bandın üstündeki modeller sunucuda saniyede PIVOT_RATE kez
	taşınıyor, her karede değil. Ekrandaki akıcı hareket istemcinin işi
	(ConveyorFX, aynı bant saatinden her karede); sunucudaki konum yalnızca
	promptun mesafe doğrulaması için gerekiyor ve birkaç stud geride kalması
	fark etmiyor. Eskiden sekiz üssün bütün modelleri her Heartbeat'te
	taşınıyor, her parçanın konumu saniyede 60 kez ağdan gidiyordu.
]]
local PIVOT_INTERVAL = 0.2
local lastPivotAt = 0

local function stepItems()
	local now = serverNow()
	local pivotNow = now - lastPivotAt >= PIVOT_INTERVAL
	if pivotNow then
		lastPivotAt = now
	end

	-- Bantlar karakteri olmasa da güncel kalmalı: istemcideki çıtalar
	-- yükseltme alınır alınmaz hızlansın
	for _, plot in PlotService.GetAllPlots() do
		local conveyor = plot:FindFirstChild("Conveyor")
		if conveyor and conveyor:IsA("BasePart") then
			syncBelt(plot, conveyor, now)
		end
	end

	for index = #activeItems, 1, -1 do
		local item = activeItems[index]

		if item.model.Parent == nil then
			table.remove(activeItems, index)
			continue
		end

		local belt = belts[item.plot]
		if not belt then
			item.model:Destroy()
			table.remove(activeItems, index)
			continue
		end

		local position = beltDistance(belt, now) - item.spawnDistance
		if position >= item.travel then
			item.model:Destroy()
			table.remove(activeItems, index)
			continue
		end

		-- Ağızdan çıkana kadar alınamıyor ve etiketi kapalı
		local visible = position >= 0
		local changed = visible ~= item.visible
		if changed then
			item.visible = visible
			item.prompt.Enabled = visible
			item.prompt:SetAttribute("OnBelt", visible)
			item.label.Enabled = visible
		end

		if pivotNow or changed then
			item.model:PivotTo(item.startCFrame * CFrame.new(position, 0, 0))
		end
	end
end

--[[ Oyuncunun konveyorune hemen bir karakter dusurur. ]]
function ConveyorService.SpawnFor(player: Player): boolean
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		return false
	end
	spawnItem(plot)
	return true
end

--[[ Sonraki uretimde mutasyonu garanti eder. ]]
function ConveyorService.GrantLuckyRoll(player: Player): boolean
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		return false
	end
	luckyPlots[plot] = true
	spawnItem(plot)
	return true
end

function ConveyorService.Start()
	notifyRemote = Net.Get("Notify")

	MonetizationService.RegisterGranter("conveyor", function(player)
		return ConveyorService.SpawnFor(player)
	end)

	MonetizationService.RegisterGranter("lucky", function(player)
		return ConveyorService.GrantLuckyRoll(player)
	end)

	RunService.Heartbeat:Connect(stepItems)

	-- Üretim aralığı artık üs başına: Conveyor Speed yükseltmesi olan
	-- oyuncunun konveyörü daha sık besleniyor. Tek bir global döngü
	-- yerine her üssün kendi zamanlayıcısı var.
	local nextSpawn: { [Model]: number } = {}

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()

			for _, plot in PlotService.GetAllPlots() do
				local owner = PlotService.GetOwner(plot)
				if not owner then
					-- Sahipsiz üste karakter üretmeye gerek yok
					nextSpawn[plot] = nil
					continue
				end

				if now >= (nextSpawn[plot] or 0) then
					spawnItem(plot)
					local level = UpgradeService.GetLevel(owner, "ConveyorSpeed")
					nextSpawn[plot] = now + Config.GetConveyorInterval(level)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local plot = PlotService.GetPlotOf(player)
		if not plot then
			return
		end
		missStreak[plot] = nil
		for index = #activeItems, 1, -1 do
			if activeItems[index].plot == plot then
				activeItems[index].model:Destroy()
				table.remove(activeItems, index)
			end
		end
	end)
end

return ConveyorService
