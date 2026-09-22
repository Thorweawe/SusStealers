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
	spawnedAt: number,
	-- Bantta kalma süresi. Normalde Config.ConveyorLifetime; çağrılan
	-- karakterde daha uzun (Config.SummonLifetime)
	lifetime: number,
}

local activeItems: { ConveyorItem } = {}

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

--[[
	Konveyöre bir karakter düşürür.

	`forcedRarity` verilirse o kademeden çekiyor (saatli çağrı). Kademe
	seviye kilidine takılıyorsa çağıran zaten kontrol etmiş olmalı; burası
	sadece çekiyor.
]]
local function spawnItem(plot: Model, forcedRarity: string?): Config.UnitDef?
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

	local def = if forcedRarity
		then Config.RollUnitOfRarity(rng, forcedRarity) or Config.RollUnit(rng, conveyorLevel)
		else Config.RollUnit(rng, conveyorLevel)
	local mutation = Config.RollMutation(rng)

	-- Garanti satin alindiysa mutasyon cikana kadar cek
	if luckyPlots[plot] then
		luckyPlots[plot] = nil
		while not mutation do
			mutation = Config.RollMutation(rng)
		end
	end

	local mutationId = if mutation then mutation.id else nil
	local price = Config.GetPrice(def.id, mutationId)

	local model = UnitModel.Build(def.id, mutationId)
	model.Name = "ConveyorItem"

	local travel = conveyor.Size.X - 4
	local startCFrame = conveyor.CFrame * CFrame.new(-travel / 2, conveyor.Size.Y / 2, 0)
	model:PivotTo(startCFrame)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local label = UnitModel.BuildLabel(def.id, mutationId)
	label.Parent = model.PrimaryPart

	-- Satın alma promptu
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy"
	prompt.ObjectText = string.format("$%s", Config.FormatCash(price))
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart

	model.Parent = items

	local item: ConveyorItem = {
		model = model,
		plot = plot,
		unitId = def.id,
		mutationId = mutationId,
		price = price,
		startCFrame = startCFrame,
		travel = travel,
		spawnedAt = os.clock(),
		lifetime = if forcedRarity then Config.SummonLifetime else Config.ConveyorLifetime,
	}
	table.insert(activeItems, item)

	PromptGuard.Connect(prompt, function(player)
		ConveyorService.TryBuy(player, item, prompt)
	end)

	--[[
		Doğal nadir çıkış herkese duyuruluyor. Çağrıyla gelenler burada
		DUYURULMUYOR: çağrı kendi toplu duyurusunu yapıyor, sekiz üsse
		aynı anda düşen karakterin sekiz ayrı satırı olmasın.
	]]
	if owner and not forcedRarity and ANNOUNCE_RARITIES[def.rarity] then
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
	if item.model.Parent == nil then
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

local function stepItems()
	local now = os.clock()

	for index = #activeItems, 1, -1 do
		local item = activeItems[index]

		if item.model.Parent == nil then
			table.remove(activeItems, index)
			continue
		end

		local elapsed = now - item.spawnedAt
		local progress = elapsed / item.lifetime

		if progress >= 1 then
			item.model:Destroy()
			table.remove(activeItems, index)
			continue
		end

		item.model:PivotTo(item.startCFrame * CFrame.new(item.travel * progress, 0, 0))
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

--[[
	Saatli çağrıyı çalıştırır: o kademeyi AÇMIŞ her üsse bir karakter
	düşürür ve tek bir duyuru yapar. Kaç üsse düştüğünü döndürür.

	Kilit kontrolü şart. Mythic ConveyorSpeed 8'de, Secret 10'da açılıyor;
	kilitsiz çağrı 1. kattaki oyuncuya bu kademeleri saat başı verirdi
	(Config.SummonEvents'teki ölçüm).
]]
function ConveyorService.RunSummon(event: Config.SummonEvent): number
	local count = 0
	for _, plot in PlotService.GetAllPlots() do
		local owner = PlotService.GetOwner(plot)
		if owner then
			local level = UpgradeService.GetLevel(owner, "ConveyorSpeed")
			if Config.IsRarityUnlocked(event.rarity, level) then
				if spawnItem(plot, event.rarity) then
					count += 1
				end
			end
		end
	end

	local rarity = Config.Rarities[event.rarity]
	local tone = if rarity then rarity.color else Color3.new(1, 1, 1)
	if count > 0 then
		AnnounceService.Summon(string.format("%s SUMMON! A %s crewmate just landed on %d conveyor%s. Guard it or steal it!",
			AnnounceService.Paint(string.upper(event.rarity), tone),
			event.rarity, count, if count == 1 then "" else "s"))
	else
		--[[
			Kimse o kademeyi açmamışsa bile olay oldu. Sessiz geçseydi
			oyuncu saatin neden boşa aktığını anlamazdı; burası aynı zamanda
			"bunu nasıl alırım" sorusunun cevabı.
		]]
		local gate = Config.RarityUnlock[event.rarity]
		AnnounceService.Summon(string.format("%s summon passed. Reach Conveyor Speed %d to receive it!",
			AnnounceService.Paint(string.upper(event.rarity), tone),
			if gate then gate.unlockLevel else 0))
	end
	return count
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

	--[[
		Saatli çağrılar. os.time'a hizalı: bütün sunucularda aynı saniyede
		çalıyor ve istemci geri sayımı aynı formülden hesaplıyor.

		Aradaki HER saniyeye bakılıyor, sadece "şimdi"ye değil: sunucu bir
		an takılırsa tam o saniye atlanabilir ve çağrı hiç gelmezdi. En
		fazla 10 saniye geriye bakıyoruz — uzun bir donmadan sonra eski
		çağrıları topluca patlatmasın.
	]]
	task.spawn(function()
		local checked = os.time()
		while true do
			task.wait(1)
			local now = os.time()
			local from = math.max(checked + 1, now - 10)

			for moment = from, now do
				local event = Config.GetSummonAt(moment)
				if event then
					ConveyorService.RunSummon(event)
				end

				local upcoming = Config.GetSummonAt(moment + Config.SummonWarning)
				if upcoming then
					local rarity = Config.Rarities[upcoming.rarity]
					AnnounceService.Summon(string.format("%s summon in %d seconds. Get back to your base!",
						AnnounceService.Paint(string.upper(upcoming.rarity),
							if rarity then rarity.color else Color3.new(1, 1, 1)),
						Config.SummonWarning))
				end
			end
			checked = now
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local plot = PlotService.GetPlotOf(player)
		if not plot then
			return
		end
		for index = #activeItems, 1, -1 do
			if activeItems[index].plot == plot then
				activeItems[index].model:Destroy()
				table.remove(activeItems, index)
			end
		end
	end)
end

return ConveyorService
