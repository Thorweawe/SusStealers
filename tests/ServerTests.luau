--!strict
--[[
	Sunucu regresyon testleri.

	Neden var: iki kişi aynı sunucu dosyalarına yazıyoruz ve sistemler
	birbirine bağlı. Bir kez basılı tutma doğrulaması yüzünden çalma ve
	satma tamamen kırıldı, ancak elle oynanarak fark edildi. Bu paket o
	sınıftaki hataları değişiklikten hemen sonra yakalamak için.

	Çalıştırma (MCP run_script_in_play_mode, mode = "start_play"):

		local Tests = require(game.ServerScriptService.Server.Tests)
		Tests.Run(game:GetService("Players"):GetPlayers()[1])

	Oyuncu gerektiriyor çünkü testlerin çoğu üs, profil ve karakter
	istiyor. init.server bu modülü require ETMİYOR; yayına çıkan kodda
	hiçbir etkisi yok.

	Testler oyuncunun profilini geçici olarak değiştiriyor; Run sonunda
	başlangıç hali geri yükleniyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Net = require(ReplicatedStorage.Shared.Net)
local CosmeticModel = require(ReplicatedStorage.Shared.CosmeticModel)

local Server = script.Parent
local PlotService = require(Server.PlotService)
local EconomyService = require(Server.EconomyService)
local SellService = require(Server.SellService)
local StealService = require(Server.StealService)
local UpgradeService = require(Server.UpgradeService)
local RebirthService = require(Server.RebirthService)
local MonetizationService = require(Server.MonetizationService)
local ConveyorService = require(Server.ConveyorService)
local PromptGuard = require(Server.PromptGuard)
local DataService = require(Server.DataService)
local BadgeService = require(Server.BadgeService)
local SpinService = require(Server.SpinService)
local TitleService = require(Server.TitleService)
local TutorialService = require(Server.TutorialService)
local QuestService = require(Server.QuestService)
local PotionService = require(Server.PotionService)
local FloorService = require(Server.FloorService)
local PetService = require(Server.PetService)
local RewardService = require(Server.RewardService)
local GearService = require(Server.GearService)
local MinigameService = require(Server.MinigameService)
local TaskService = require(Server.TaskService)
local CosmeticService = require(Server.CosmeticService)
local FriendService = require(Server.FriendService)
local VentService = require(Server.VentService)
local EventService = require(Server.EventService)
local SabotageService = require(Server.SabotageService)
local RogueService = require(Server.RogueService)
local AdminMapService = require(Server.AdminMapService)
local SettingsService = require(Server.SettingsService)

local ServerTests = {}

-- ─── Test altyapısı ─────────────────────────────────────────────────────────

type Case = { name: string, fn: (any) -> () }

local cases: { Case } = {}
local function case(name: string, fn: (any) -> ())
	table.insert(cases, { name = name, fn = fn })
end

local current = { passed = 0, failed = 0, notes = {} :: { string } }

local function ok(label: string, condition: boolean, detail: string?)
	if condition then
		current.passed += 1
	else
		current.failed += 1
		table.insert(current.notes, string.format("      %s %s", label, detail or ""))
	end
end

local function eq(label: string, actual: any, expected: any)
	ok(label, actual == expected, string.format("(%s, beklenen %s)", tostring(actual), tostring(expected)))
end

local function near(label: string, actual: number, expected: number, tolerance: number)
	ok(label, math.abs(actual - expected) <= tolerance,
		string.format("(%.3f, beklenen %.3f ±%.3f)", actual, expected, tolerance))
end

-- ─── Ortam yardımcıları ─────────────────────────────────────────────────────

--[[ Oyuncunun üssünü tamamen boşaltır. ]]
local function clearPlot(plot: Model)
	for _, podium in PlotService.GetPodiums(plot) do
		if PlotService.IsOccupied(podium) then
			PlotService.ClearUnit(podium)
		end
	end

	local items = plot:FindFirstChild("Items")
	if items then
		items:ClearAllChildren()
	end
end

local function setCash(player: Player, amount: number)
	EconomyService.AddCash(player, amount - EconomyService.GetCash(player))
end

-- ─── A. Config bütünlüğü ────────────────────────────────────────────────────

case("Config: karakter tanımları tutarlı", function()
	local seen = {}
	local allValid = true
	local uniqueIds = true

	for _, unit in Config.Units do
		if seen[unit.id] then
			uniqueIds = false
		end
		seen[unit.id] = true

		if unit.price <= 0 or unit.income <= 0 or unit.weight <= 0 then
			allValid = false
		end
		if not Config.Rarities[unit.rarity] then
			allValid = false
		end
	end

	ok("id'ler benzersiz", uniqueIds)
	ok("fiyat/gelir/ağırlık pozitif ve nadirlik tanımlı", allValid)
	ok("en az 10 karakter var", #Config.Units >= 10, tostring(#Config.Units))
end)

case("Config: pahalı karakter daha çok kazandırıyor", function()
	-- Sıralama bozulursa ucuz karakter üstün olur ve ilerleme anlamsızlaşır
	local sorted = table.clone(Config.Units)
	table.sort(sorted, function(a, b) return a.price < b.price end)

	local monotonic = true
	for index = 2, #sorted do
		if sorted[index].income <= sorted[index - 1].income then
			monotonic = false
		end
	end
	ok("fiyat arttıkça gelir de artıyor", monotonic)
end)

case("Config: mutasyon oranı makul", function()
	local none = 1
	for _, mutation in Config.Mutations do
		ok(mutation.id .. " şansı 0-1 arası", mutation.chance > 0 and mutation.chance < 1)
		ok(mutation.id .. " çarpanı 1'den büyük", mutation.incomeMul > 1)
		none *= (1 - mutation.chance)
	end

	local total = 1 - none
	ok("toplam mutasyon şansı %5-%25 arası", total >= 0.05 and total <= 0.25,
		string.format("%.1f%%", total * 100))
end)

case("Config: para formatı", function()
	eq("950", Config.FormatCash(950), "950")
	eq("1.23M", Config.FormatCash(1234567), "1.23M")
	eq("sıfır", Config.FormatCash(0), "0")
end)

case("Config: mutasyonlu fiyat mutasyonsuzdan yüksek", function()
	for _, mutation in Config.Mutations do
		local plain = Config.GetPrice("RedCrew", nil)
		local mutated = Config.GetPrice("RedCrew", mutation.id)
		ok(mutation.id .. " daha pahalı", mutated > plain,
			string.format("%d vs %d", mutated, plain))
	end
end)

-- ─── B. Üs ve kaide yapısı ──────────────────────────────────────────────────

case("Üs: oyuncuya atanıyor ve doğuş pedinde başlıyor", function(ctx)
	ok("üs verildi", ctx.plot ~= nil)

	local pad = ctx.plot:FindFirstChild("SpawnPad")
	ok("doğuş pedi var", pad ~= nil)

	if pad and ctx.player.Character then
		local root = ctx.player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			ok("karakter pedin yakınında", (root.Position - pad.Position).Magnitude < 25,
				string.format("%.0f stud", (root.Position - pad.Position).Magnitude))
		end
	end
end)

case("Üs: kaide sayıları ve bonus işaretleri", function(ctx)
	local all = PlotService.GetPodiums(ctx.plot)
	eq("toplam kaide", #all, Config.MaxFloors * Config.PodiumsPerFloorTotal)

	local bonus, slots = 0, {}
	local uniqueSlots = true
	for _, podium in all do
		if podium:GetAttribute("Bonus") then
			bonus += 1
		end
		local slot = podium:GetAttribute("SlotIndex")
		if slots[slot] then
			uniqueSlots = false
		end
		slots[slot] = true
	end

	eq("bonus kaide sayısı", bonus, Config.MaxFloors * Config.PassExtraPodiumsPerFloor)
	ok("slot numaraları benzersiz", uniqueSlots)
end)

case("Üs: kapalı kat ve bonus kaide kullanılamıyor", function(ctx)
	PlotService.SetUnlockedFloors(ctx.plot, 1)

	local upstairs, bonus
	for _, podium in PlotService.GetPodiums(ctx.plot) do
		if (podium:GetAttribute("Floor") :: number) == 2 and not upstairs then
			upstairs = podium
		end
		if podium:GetAttribute("Bonus") and (podium:GetAttribute("Floor") :: number) == 1 and not bonus then
			bonus = podium
		end
	end

	if upstairs then
		eq("2. kata yerleştirme reddedildi", PlotService.PlaceUnit(upstairs, "RedCrew", nil), false)
	end
	if bonus then
		eq("bonus kaideye yerleştirme reddedildi", PlotService.PlaceUnit(bonus, "RedCrew", nil), false)
	end

	eq("kullanılabilir kaide", #PlotService.GetUnlockedPodiums(ctx.plot), Config.PodiumsPerPlot)
end)

case("Üs: üsler birbiriyle çakışmıyor", function()
	local plots = PlotService.GetAllPlots()
	local overlap = false

	for i = 1, #plots do
		for j = i + 1, #plots do
			local a = plots[i]:FindFirstChild("Base")
			local b = plots[j]:FindFirstChild("Base")
			if a and b then
				local d = a.Position - b.Position
				if math.abs(d.X) < Config.PlotSize.X and math.abs(d.Z) < Config.PlotSize.Z then
					overlap = true
				end
			end
		end
	end

	ok("hiçbir üs çakışmıyor", not overlap)
end)

case("Üs: her katın merdiveni kendi zeminine ulaşıyor", function(ctx)
	--[[
		Yerleşim rampadan merdivene geçti. Basamakların en üstü o katın
		güvertesine yakın olmalı; aksi halde kat açılıyor ama çıkılamıyor.
	]]
	local floors = ctx.plot:FindFirstChild("Floors")
	ok("Floors klasörü var", floors ~= nil)
	if not floors then return end

	for floor = 2, Config.MaxFloors do
		local model = floors:FindFirstChild(string.format("Floor%d", floor))
		if not model then
			ok("kat " .. floor .. " var", false)
			continue
		end

		local lowest, highest
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part.Name == "Step" then
				if not lowest or part.Position.Y < lowest then lowest = part.Position.Y end
				if not highest or part.Position.Y > highest then highest = part.Position.Y end
			end
		end

		ok("kat " .. floor .. " basamakları var", lowest ~= nil)
		if not (lowest and highest) then continue end

		local deck = model:FindFirstChild("Deck")
		if deck and deck:IsA("BasePart") then
			ok("kat " .. floor .. " merdiveni güverteye ulaşıyor",
				math.abs(highest - deck.Position.Y) <= Config.FloorHeight,
				string.format("%.1f vs %.1f", highest, deck.Position.Y))
		end
	end
end)

-- ─── C. Ekonomi ─────────────────────────────────────────────────────────────

case("Üs: dekor pedleri kaidelerin altında hizalı", function(ctx)
	--[[
		Ped konumu iki ayrı dosyada elle yazılıydı (PlotService 9,
		build_decor 8) ve bir stud kayıyordu: pedler kaidelerin altından
		taşıyordu. Sayı artık Config.PodiumRowZ'de ve bu test iki tarafın
		yeniden ayrışmasını yakalıyor.
	]]
	local decor = workspace:FindFirstChild("Decor")
	local plotsDecor = decor and decor:FindFirstChild("Plots")
	local pf = plotsDecor and plotsDecor:FindFirstChild(ctx.plot.Name)

	ok("dekor klasörü var", pf ~= nil)
	if not pf then return end

	local pads = {}
	for _, part in pf:GetChildren() do
		if part:IsA("BasePart") and part.Name == "PodiumPad" then
			table.insert(pads, part)
		end
	end

	ok("ped var", #pads > 0, tostring(#pads))

	local podiums = PlotService.GetPodiums(ctx.plot)
	local worst = 0

	for _, pad in pads do
		local best = math.huge
		for _, pod in podiums do
			local d = (Vector3.new(pad.Position.X, 0, pad.Position.Z)
				- Vector3.new(pod.Position.X, 0, pod.Position.Z)).Magnitude
			if d < best then best = d end
		end
		if best > worst then worst = best end
	end

	ok("her ped bir kaidenin altında", worst < 0.5,
		string.format("%.2f stud kayma", worst))
end)

case("Ekonomi: nakit ekleme ve harcama", function(ctx)
	setCash(ctx.player, 1000)
	eq("başlangıç", EconomyService.GetCash(ctx.player), 1000)

	EconomyService.AddCash(ctx.player, 500)
	eq("ekleme sonrası", EconomyService.GetCash(ctx.player), 1500)

	eq("yetersiz harcama reddedildi", EconomyService.TrySpend(ctx.player, 99999), false)
	eq("red sonrası bakiye değişmedi", EconomyService.GetCash(ctx.player), 1500)

	eq("yeterli harcama kabul edildi", EconomyService.TrySpend(ctx.player, 500), true)
	eq("harcama sonrası", EconomyService.GetCash(ctx.player), 1000)
end)

case("Ekonomi: nakit profile yazılıyor", function(ctx)
	setCash(ctx.player, 4242)
	eq("profil nakdi eşleşiyor", ctx.profile.cash, 4242)
end)

case("Ekonomi: gelir kaidelerden hesaplanıyor", function(ctx)
	clearPlot(ctx.plot)
	eq("boş üste gelir sıfır", EconomyService.GetIncome(ctx.player), 0)

	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)
	PlotService.PlaceUnit(podiums[1], "Engineer", nil)

	local expected = Config.GetUnit("Engineer").income
		* Config.GetIncomeMultiplier(ctx.profile.rebirths)
	eq("tek karakterin geliri", EconomyService.GetIncome(ctx.player), math.floor(expected))

	PlotService.PlaceUnit(podiums[2], "Engineer", nil)
	eq("iki karakterin geliri", EconomyService.GetIncome(ctx.player), math.floor(expected * 2))
end)

case("Ekonomi: mutasyon geliri çarpıyor", function(ctx)
	clearPlot(ctx.plot)
	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)

	PlotService.PlaceUnit(podiums[1], "Engineer", "Golden")
	local mutation = Config.GetMutation("Golden")
	local expected = Config.GetUnit("Engineer").income * mutation.incomeMul
		* Config.GetIncomeMultiplier(ctx.profile.rebirths)

	eq("Golden çarpanı uygulandı", EconomyService.GetIncome(ctx.player), math.floor(expected))
end)

-- ─── D. Satın alma ve satma ─────────────────────────────────────────────────

case("Satma: son karakter satılamıyor", function(ctx)
	clearPlot(ctx.plot)
	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)

	PlotService.PlaceUnit(podiums[1], "Engineer", nil)
	eq("tek karakter satılamadı", SellService.Sell(ctx.player, podiums[1]), false)
	ok("kaide hâlâ dolu", PlotService.IsOccupied(podiums[1]))

	PlotService.PlaceUnit(podiums[2], "RedCrew", nil)
	eq("ikinci varken satılabildi", SellService.Sell(ctx.player, podiums[2]), true)
	eq("tekrar sona düşünce engellendi", SellService.Sell(ctx.player, podiums[1]), false)
end)

case("Satma: doğru tutar ödeniyor", function(ctx)
	clearPlot(ctx.plot)
	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)

	PlotService.PlaceUnit(podiums[1], "RedCrew", nil)
	PlotService.PlaceUnit(podiums[2], "Reactor", "Golden")

	setCash(ctx.player, 0)
	local expected = Config.GetSellPrice("Reactor", "Golden")
	SellService.Sell(ctx.player, podiums[2])

	eq("ödenen tutar", EconomyService.GetCash(ctx.player), expected)
	ok("kaide boşaldı", not PlotService.IsOccupied(podiums[2]))
	ok("model silindi", podiums[2]:FindFirstChild("Unit") == nil)
end)

case("Satma: başkasının kaidesi satılamıyor", function(ctx)
	local other
	for _, plot in PlotService.GetAllPlots() do
		if plot ~= ctx.plot then
			other = plot
			break
		end
	end

	if not other then
		ok("başka üs bulundu", false)
		return
	end

	PlotService.SetUnlockedFloors(other, 1)
	local podium = PlotService.GetUnlockedPodiums(other)[1]
	PlotService.PlaceUnit(podium, "RedCrew", nil)

	local before = EconomyService.GetCash(ctx.player)
	eq("satış reddedildi", SellService.Sell(ctx.player, podium), false)
	eq("nakit değişmedi", EconomyService.GetCash(ctx.player), before)
	ok("kaide dolu kaldı", PlotService.IsOccupied(podium))

	PlotService.ClearUnit(podium)
end)

case("Satın alma: satış fiyatı alış fiyatından düşük", function()
	-- Eşit veya yüksek olsaydı al-sat döngüsüyle sonsuz para basılırdı
	for _, unit in Config.Units do
		local buy = Config.GetPrice(unit.id, nil)
		local sell = Config.GetSellPrice(unit.id, nil)
		ok(unit.id .. " satış < alış", sell < buy, string.format("%d vs %d", sell, buy))
	end
end)

-- ─── E. Çalma kuralları ─────────────────────────────────────────────────────

case("Çalma: ışınlanma kontrolü mesafeyi zaman olarak istiyor", function(ctx)
	local speed = Config.GetCarryWalkSpeed(UpgradeService.GetLevel(ctx.player, "CarrySpeed"))
	local distance = 200
	local minimum = distance / speed * Config.CarryTravelTolerance

	ok("200 stud için asgari süre pozitif", minimum > 0, string.format("%.1f sn", minimum))
	ok("dürüst yürüme süresi eşiği geçiyor", distance / speed >= minimum)
	ok("anında varış eşiği geçemiyor", 0.1 < minimum)
end)

case("Çalma: taşıma hızı normal hızı aşmıyor", function()
	-- Aşsaydı karakter taşımak avantaj olur, çalmanın riski kaybolurdu
	for level = 0, 50 do
		ok("seviye " .. level, Config.GetCarryWalkSpeed(level) < Config.NormalWalkSpeed,
			string.format("%.1f", Config.GetCarryWalkSpeed(level)))
	end
end)

case("Çalma: seri bonusu tavanlı", function()
	local previous = -1
	for streak = 0, Config.StealStreakMax + 5 do
		local bonus = Config.GetStreakBonus(streak)
		ok("seri " .. streak .. " bonusu azalmıyor", bonus >= previous)
		previous = bonus
	end

	eq("tavan aşılmıyor",
		Config.GetStreakBonus(Config.StealStreakMax + 10),
		Config.GetStreakBonus(Config.StealStreakMax))
	eq("sıfırıncı seride bonus yok", Config.GetStreakBonus(0), 0)
end)

case("Çalma: promptlar kaidelerde kurulu", function(ctx)
	local podium = PlotService.GetUnlockedPodiums(ctx.plot)[1]
	ok("StealPrompt var", podium:FindFirstChild("StealPrompt") ~= nil)
	ok("SellPrompt var", podium:FindFirstChild("SellPrompt") ~= nil)

	local steal = podium:FindFirstChild("StealPrompt")
	local sell = podium:FindFirstChild("SellPrompt")
	if steal and sell then
		ok("tuşlar farklı", steal.KeyboardKeyCode ~= sell.KeyboardKeyCode,
			tostring(steal.KeyboardKeyCode) .. " / " .. tostring(sell.KeyboardKeyCode))
	end
end)

case("Çalma: süre karakterin değerine göre ölçekleniyor", function()
	local cheap = Config.GetStealHoldTime("RedCrew", nil)
	local expensive = Config.GetStealHoldTime("AmogusPrime", nil)

	ok("ucuz karakter daha hızlı çalınıyor", cheap < expensive,
		string.format("%.1f vs %.1f", cheap, expensive))
	ok("süreler 2-8 sn arasında", cheap >= 2 and expensive <= 8)
end)

-- ─── F. Yükseltmeler ────────────────────────────────────────────────────────

case("Yükseltme: seviye ve maliyet", function(ctx)
	local id = "ConveyorSpeed"
	ctx.profile.upgrades[id] = nil

	eq("başlangıç seviyesi", UpgradeService.GetLevel(ctx.player, id), 0)

	local cost = Config.GetUpgradeCost(id, 0)
	setCash(ctx.player, cost - 1)
	eq("parası yetmeyince reddedildi", UpgradeService.TryUpgrade(ctx.player, id), false)

	setCash(ctx.player, cost)
	eq("parası yetince alındı", UpgradeService.TryUpgrade(ctx.player, id), true)
	eq("seviye arttı", UpgradeService.GetLevel(ctx.player, id), 1)
	eq("tam tutar düştü", EconomyService.GetCash(ctx.player), 0)
end)

case("Yükseltme: tavana ulaşınca duruyor", function(ctx)
	local id = "LockPower"
	local def = Config.GetUpgrade(id)

	-- Tavan artık kat sayısına bağlı
	local ceiling = Config.GetUpgradeCeiling(def)
	ctx.profile.floorsBought = Config.MaxFloors - 1
	ctx.profile.upgrades[id] = ceiling
	eq("tavanda maliyet nil", Config.GetUpgradeCost(id, ceiling), nil)

	setCash(ctx.player, 1e15)
	eq("tavanda satın alma reddedildi", UpgradeService.TryUpgrade(ctx.player, id), false)
	eq("seviye değişmedi", UpgradeService.GetLevel(ctx.player, id), ceiling)
end)

case("Yükseltme: her seviye gerçekten bir şey değiştiriyor", function()
	-- Etki tabana çarparsa üst seviyeler paranın boşa gitmesi olur
	for _, def in Config.Upgrades do
		local values = {}
		local distinct = 0

		for level = 0, Config.GetUpgradeCeiling(def) do
			local value
			if def.id == "ConveyorSpeed" then
				value = string.format("%.3f", Config.GetConveyorInterval(level))
			elseif def.id == "UnitGuard" then
				value = tostring(Config.GetSafeSeconds(level))
			elseif def.id == "CarrySpeed" then
				value = string.format("%.3f", Config.GetCarryWalkSpeed(level))
			else
				local d, c = Config.GetLockValues(level)
				value = string.format("%.1f/%.1f", d, c)
			end

			if not values[value] then
				values[value] = true
				distinct += 1
			end
		end

		eq(def.name .. " farklı değer sayısı", distinct, Config.GetUpgradeCeiling(def) + 1)
	end
end)

case("Yükseltme: maliyet eğrisi rebirth'ten sonra da iş bırakıyor", function()
	local total = 0
	for _, def in Config.Upgrades do
		for level = 0, Config.GetUpgradeCeiling(def) - 1 do
			total += Config.GetUpgradeCost(def.id, level) or 0
		end
	end

	local rebirths = 0
	for level = 0, Config.MaxFloors - 2 do
		rebirths += Config.GetRebirthCost(level)
	end

	ok("yükseltmeler rebirth'lerden pahalı", total > rebirths,
		string.format("$%s vs $%s", Config.FormatCash(total), Config.FormatCash(rebirths)))
end)

-- ─── G. Rebirth ─────────────────────────────────────────────────────────────

case("Rebirth: parası yetmeyince reddediliyor", function(ctx)
	ctx.profile.rebirths = 0
	setCash(ctx.player, Config.GetRebirthCost(0) - 1)
	eq("reddedildi", RebirthService.TryRebirth(ctx.player), false)
	eq("seviye değişmedi", ctx.profile.rebirths, 0)
end)

case("Rebirth: sıfırlıyor ve çarpan veriyor", function(ctx)
	--[[
		Kat artık rebirth ödülü DEĞİL, parayla alınıyor. Bu test eskiden
		rebirth'ten sonra katın açılmasını bekliyordu; o kural kalktı.
		Katın satın almayla açıldığı ayrı testlerde sınanıyor.
	]]
	ctx.profile.rebirths = 0
	ctx.profile.floorsBought = 0
	PlotService.SetUnlockedFloors(ctx.plot, 1)
	clearPlot(ctx.plot)

	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)
	PlotService.PlaceUnit(podiums[1], "TheSkeld", nil)

	setCash(ctx.player, Config.GetRebirthCost(0))
	eq("rebirth başarılı", RebirthService.TryRebirth(ctx.player), true)

	eq("seviye 1 oldu", ctx.profile.rebirths, 1)
	eq("nakit başlangıca döndü", EconomyService.GetCash(ctx.player), Config.StartingCash)
	eq("kat bedava açılmadı", ctx.plot:GetAttribute("UnlockedFloors"), 1)

	local occupied = 0
	for _, podium in PlotService.GetPodiums(ctx.plot) do
		if PlotService.IsOccupied(podium) then
			occupied += 1
		end
	end
	eq("kaideler boşaldı", occupied, 0)

	near("gelir çarpanı", Config.GetIncomeMultiplier(1), 1 + Config.RebirthIncomeBonus, 0.001)
end)

case("Rebirth: tavanda duruyor", function(ctx)
	ctx.profile.rebirths = Config.MaxFloors - 1
	setCash(ctx.player, 1e15)
	eq("tavanda reddedildi", RebirthService.TryRebirth(ctx.player), false)
	eq("seviye değişmedi", ctx.profile.rebirths, Config.MaxFloors - 1)
end)

-- ─── H. Para kazanma ────────────────────────────────────────────────────────

case("Monetization: id=0 olan ürünler devre dışı", function(ctx)
	for key, def in Config.GamePasses do
		if def.id == 0 then
			eq(key .. " sahipliği false", MonetizationService.HasPass(ctx.player, key), false)
		end
	end

	--[[
		Pass'ler artık gerçek kimlikli: test eden hesap (ör. oyunun sahibi)
		pass'e sahipse etkisi de olmalı. Beklenen değer sahipliğe göre.
	]]
	local has = MonetizationService.HasPass
	eq("gelir çarpanı", MonetizationService.GetIncomeMultiplier(ctx.player),
		if has(ctx.player, "DoubleIncome") then Config.PassDoubleIncomeMultiplier else 1)
	eq("ekstra kaide", MonetizationService.GetExtraPodiumsPerFloor(ctx.player),
		if has(ctx.player, "ExtraPodiums") then Config.PassExtraPodiumsPerFloor else 0)
	eq("çalma süresi çarpanı", MonetizationService.GetStealHoldMultiplier(ctx.player),
		if has(ctx.player, "FastSteal") then Config.PassFastStealMultiplier else 1)
end)

case("Monetization: ürün ve pass kimlikleri girilmiş ve benzersiz", function()
	local seen: { [number]: string } = {}
	for key, def in Config.GamePasses do
		ok(key .. " kimliği var", def.id > 0)
		ok(key .. " kimliği tekrar etmiyor", seen[def.id] == nil, seen[def.id])
		seen[def.id] = key
	end
	for key, def in Config.Products do
		-- İksir ürünleri henüz Creator Dashboard'da açılmadı (0 = mağazada SOON)
		if def.kind ~= "potion" then
			ok(key .. " kimliği var", def.id > 0)
		end
		if def.id > 0 then
			ok(key .. " kimliği tekrar etmiyor", seen[def.id] == nil, seen[def.id])
			seen[def.id] = key
		end
	end
end)

case("Monetization: ürün tanımları tutarlı", function()
	local kinds = { cash = true, conveyor = true, lucky = true, rebirth = true, spin = true, potion = true }

	for key, def in Config.Products do
		ok(key .. " tipi tanınıyor", kinds[def.kind] == true, def.kind)
		if def.kind == "cash" then
			ok(key .. " tutarı pozitif", (def.amount or 0) > 0)
		end
		if def.kind == "potion" then
			ok(key .. " iksiri var", def.potion ~= nil and Config.GetPotion(def.potion) ~= nil)
		end
	end
end)

--[[ Banttaki bir modelin fiyatı (UnitId + MutationId etiketlerinden). ]]
local function itemPrice(model: Instance): number
	local unit = model:FindFirstChild("UnitId") :: StringValue?
	local mutation = model:FindFirstChild("MutationId") :: StringValue?
	if not unit then
		return math.huge
	end
	local mutationId = if mutation and mutation.Value ~= "" then mutation.Value else nil
	return Config.GetPrice(unit.Value, mutationId)
end

case("Konveyör: parasız oyuncuya yalnızca alabileceği karakter geliyor", function(ctx)
	--[[
		$100 ile kalan oyuncu (geliri 0) bantta hep alamayacağı karakterler
		görüyordu; kilitlenme koruması parayı veriyor ama harcanacak yer
		çıkmıyordu. Artık geliri 0 iken her çekiliş bütçeye uygun.
	]]
	clearPlot(ctx.plot)
	setCash(ctx.player, Config.GetCheapestUnitPrice())

	for _ = 1, 15 do
		ConveyorService.SpawnFor(ctx.player)
	end

	local items = ctx.plot:FindFirstChild("Items")
	local count, affordable = 0, 0
	for _, model in items:GetChildren() do
		count += 1
		if itemPrice(model) <= Config.GetCheapestUnitPrice() then
			affordable += 1
		end
	end

	eq("15 karakter üretildi", count, 15)
	eq("hepsi $100 ile alınabiliyor", affordable, count)
	clearPlot(ctx.plot)
end)

case("Konveyör: bütçe çekilişi sınırlı ve kilitli kademeye girmiyor", function()
	local rng = Random.new(7)
	local fine = true
	for _ = 1, 200 do
		local unit = Config.RollAffordableUnit(rng, 0, 1000)
		if unit.price > 1000 or Config.GetUnitWeight(unit, 0) <= 0 then
			fine = false
		end
	end
	ok("200 çekilişte bütçe ve kademe kilidi tutuyor", fine)
	eq("bütçe yetmezse en ucuzu", Config.RollAffordableUnit(rng, 0, 0).price, Config.GetCheapestUnitPrice())
end)

case("Konveyör: bant hızı yükseltmeyle artıyor ama tavanlı", function()
	local base = Config.GetConveyorBeltSpeed(0)
	ok("taban pozitif", base > 0)
	ok("seviye 6 daha hızlı", Config.GetConveyorBeltSpeed(6) > base)

	local def = Config.GetUpgrade("ConveyorSpeed")
	if not def then
		return
	end
	local top = Config.GetConveyorBeltSpeed(Config.GetUpgradeCeiling(def))
	near("tavan çarpanı", top / base, Config.ConveyorBeltSpeedMax, 1e-6)

	-- En hızlı hâlde bile karakter bantta alınacak kadar kalmalı
	local travel = Config.PlotSize.X - 12
	ok("en hızlı bantta >= 10 sn", travel / top >= 10, string.format("%.1f sn", travel / top))
end)

case("Konveyör: karakter çıtaya hizalı ve bant saati istemciye gidiyor", function(ctx)
	clearPlot(ctx.plot)
	setCash(ctx.player, Config.GetCheapestUnitPrice())
	ConveyorService.SpawnFor(ctx.player)

	local conveyor = ctx.plot:FindFirstChild("Conveyor") :: BasePart
	ok("BeltSpeed niteliği var", typeof(conveyor:GetAttribute("BeltSpeed")) == "number")
	ok("BeltDistance niteliği var", typeof(conveyor:GetAttribute("BeltDistance")) == "number")
	ok("BeltStamp niteliği var", typeof(conveyor:GetAttribute("BeltStamp")) == "number")

	local model = ctx.plot:FindFirstChild("Items"):FindFirstChildOfClass("Model")
	ok("karakter doğdu", model ~= nil)
	if not model then
		return
	end

	local travel = model:GetAttribute("Travel") :: number
	local spawnDistance = model:GetAttribute("SpawnDistance") :: number
	local gap = travel / Config.ConveyorSlats
	local rem = spawnDistance % gap
	ok("doğuş çıta aralığının katında", rem < 1e-6 or gap - rem < 1e-6, string.format("%.4f", rem))

	-- Kapağın içindeyken alınamaz: prompt kapalı, OnBelt false
	local prompt = model.PrimaryPart and model.PrimaryPart:FindFirstChild("BuyPrompt") :: ProximityPrompt?
	ok("prompt var", prompt ~= nil)
	if prompt then
		eq("kapaktayken OnBelt false", prompt:GetAttribute("OnBelt"), false)
		-- En fazla bir çıta aralığı sonra ağızdan çıkmış olmalı
		local speed = conveyor:GetAttribute("BeltSpeed") :: number
		task.wait(gap / speed + 0.2)
		if model.Parent then
			eq("ağızdan çıkınca OnBelt true", prompt:GetAttribute("OnBelt"), true)
			eq("ağızdan çıkınca prompt açık", prompt.Enabled, true)
		end
	end
	clearPlot(ctx.plot)
end)

case("Monetization: ödül fonksiyonları çalışıyor", function(ctx)
	clearPlot(ctx.plot)

	eq("anlık üretim", ConveyorService.SpawnFor(ctx.player), true)
	eq("garantili mutasyon", ConveyorService.GrantLuckyRoll(ctx.player), true)

	local items = ctx.plot:FindFirstChild("Items")
	local mutated = 0
	for _, model in items:GetChildren() do
		local tag = model:FindFirstChild("MutationId")
		if tag and (tag :: StringValue).Value ~= "" then
			mutated += 1
		end
	end

	ok("en az bir mutasyonlu üretildi", mutated >= 1, tostring(mutated))
	items:ClearAllChildren()
end)

-- ─── I. Güvenlik ────────────────────────────────────────────────────────────

case("Güvenlik: uzaktan tetikleme reddediliyor", function(ctx)
	local podium = PlotService.GetUnlockedPodiums(ctx.plot)[1]
	local prompt = podium:FindFirstChild("SellPrompt")
	local root = ctx.player.Character and ctx.player.Character:FindFirstChild("HumanoidRootPart")

	if not (prompt and root) then
		ok("prompt ve karakter bulundu", false)
		return
	end

	local origin = root.CFrame

	root.CFrame = CFrame.new(podium.Position + Vector3.new(0, 4, 3))
	task.wait(0.3)
	local near_ = PromptGuard.Validate(prompt, ctx.player, 0)
	ok("yakından kabul", near_)

	root.CFrame = CFrame.new(podium.Position + Vector3.new(500, 4, 0))
	task.wait(0.3)
	ok("500 stud uzaktan reddedildi", not PromptGuard.Validate(prompt, ctx.player, 0))

	root.CFrame = origin
	task.wait(0.2)
end)

-- ─── J. Kayıt ───────────────────────────────────────────────────────────────

case("Kayıt: profil alanları eksiksiz", function(ctx)
	local p = ctx.profile
	ok("cash sayı", typeof(p.cash) == "number")
	ok("rebirths sayı", typeof(p.rebirths) == "number")
	ok("units tablo", typeof(p.units) == "table")
	ok("upgrades tablo", typeof(p.upgrades) == "table")
	ok("receipts tablo", typeof(p.receipts) == "table")
end)

case("Ayarlar: sınırlanıyor, profile ve niteliğe yazılıyor", function(ctx)
	local player = ctx.player
	local settings = ctx.profile.settings
	local before = table.clone(settings)

	SettingsService._Reset(player)
	local result = SettingsService.Apply(player, { music = 5, sfx = -1, shake = false, cash = 1e9 }, 1000)
	ok("kabul edildi", result ~= nil)
	eq("müzik 1'e sıkıştı", settings.music, 1)
	eq("efekt 0'a sıkıştı", settings.sfx, 0)
	eq("sarsıntı kapandı", settings.shake, false)
	eq("nitelik yazıldı", player:GetAttribute("SettingSfx"), 0)
	ok("bilinmeyen alan profile girmedi", (settings :: any).cash == nil)

	-- Çok sık istek düşüyor; yanlış tür yok sayılıyor
	ok("sık istek reddedildi", SettingsService.Apply(player, { music = 0.5 }, 1000.1) == nil)
	SettingsService.Apply(player, { music = "x", shake = 1 }, 1001)
	eq("yanlış tür müziği değiştirmedi", settings.music, 1)
	eq("yanlış tür sarsıntıyı değiştirmedi", settings.shake, false)

	-- Geri al: oyuncunun gerçek ayarı bozulmasın
	SettingsService._Reset(player)
	SettingsService.Apply(player, before, 2000)
	SettingsService._Reset(player)
end)

case("Kayıt: kaide değişiklikleri profile yansıyor", function(ctx)
	clearPlot(ctx.plot)
	eq("boşken units boş", #ctx.profile.units, 0)

	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)
	PlotService.PlaceUnit(podiums[1], "Reactor", "Vented")
	PlotService.PlaceUnit(podiums[2], "RedCrew", nil)

	eq("iki karakter yazıldı", #ctx.profile.units, 2)

	local found = false
	for _, entry in ctx.profile.units do
		if entry.unitId == "Reactor" and entry.mutationId == "Vented" then
			found = true
		end
	end
	ok("mutasyon bilgisi korundu", found)

	PlotService.ClearUnit(podiums[1])
	eq("sökülünce düştü", #ctx.profile.units, 1)
end)

case("Kayıt: çevrimdışı gelir tavanlı", function()
	local rate = 1000
	local oneHour = Config.GetOfflineEarnings(rate, 3600)
	local capped = Config.GetOfflineEarnings(rate, Config.OfflineIncomeCapHours * 3600)
	local beyond = Config.GetOfflineEarnings(rate, 99 * 3600)

	ok("bir saat pozitif", oneHour > 0)
	eq("tavan aşılmıyor", beyond, capped)
	ok("oran tam değil", capped < rate * Config.OfflineIncomeCapHours * 3600)
end)

-- ─── K. Rozetler ────────────────────────────────────────────────────────────

case("Rozet: tanımlar tutarlı", function()
	local count = 0
	for key, def in Config.Badges do
		count += 1
		ok(key .. " adı dolu", typeof(def.name) == "string" and #def.name > 0)
		ok(key .. " id sayı", typeof(def.id) == "number")
	end
	ok("en az 8 rozet tanımlı", count >= 8, tostring(count))
end)

case("Rozet: id=0 olanlar sessizce atlanıyor", function(ctx)
	-- Çağrı patlamamalı; id yoksa hiçbir şey yapmadan dönmeli
	local success = pcall(function()
		BadgeService.Award(ctx.player, "FirstSteal")
		BadgeService.Award(ctx.player, "BoyleBirRozetYok")
		BadgeService.CheckCash(ctx.player, Config.BadgeBillionaire)
	end)
	ok("hata vermeden çalıştı", success)
end)

case("Rozet: nakit eşikleri sıralı", function()
	ok("milyoner eşiği pozitif", Config.BadgeMillionaire > 0)
	ok("milyarder eşiği daha yüksek", Config.BadgeBillionaire > Config.BadgeMillionaire)
end)

-- ─── L. Şans çarkı ──────────────────────────────────────────────────────────

case("Çark: ödül tablosu geçerli", function()
	local kinds = { cash = true, spawn = true, mutation = true, unit = true }
	local total = 0

	for _, reward in Config.SpinRewards do
		total += reward.weight
		ok(reward.id .. " ağırlığı pozitif", reward.weight > 0)
		ok(reward.id .. " tipi tanınıyor", kinds[reward.kind] == true, reward.kind)

		if reward.kind == "cash" then
			ok(reward.id .. " taban tutarı pozitif", (reward.minimum or 0) > 0)
			ok(reward.id .. " gelir süresi pozitif", (reward.incomeSeconds or 0) > 0)
		end
	end

	ok("toplam ağırlık pozitif", total > 0)
	ok("boş dilim yok", #Config.SpinRewards >= 4, tostring(#Config.SpinRewards))
end)

case("Çark: rulet tüm ödülleri üretebiliyor", function()
	local rng = Random.new(12345)
	local seen = {}
	local distinct = 0

	for _ = 1, 20000 do
		local reward = Config.RollSpinReward(rng)
		if not seen[reward.id] then
			seen[reward.id] = true
			distinct += 1
		end
	end

	eq("her ödül en az bir kez çıktı", distinct, #Config.SpinRewards)
end)

case("Çark: nakit ödülü gelirle ölçekleniyor", function()
	local reward
	for _, entry in Config.SpinRewards do
		if entry.kind == "cash" then
			reward = entry
			break
		end
	end

	if not reward then
		ok("nakit ödülü var", false)
		return
	end

	eq("sıfır gelirde taban değer", Config.GetSpinCash(reward, 0), reward.minimum)

	local high = Config.GetSpinCash(reward, 1000000)
	ok("yüksek gelirde ölçekleniyor", high > reward.minimum, Config.FormatCash(high))
	eq("beklenen tutar", high, math.floor(1000000 * reward.incomeSeconds))
end)

case("Çark: bedava hak bekleme süresi", function(ctx)
	ctx.profile.lastSpinAt = 0
	near("hiç çevirmemişken hak hazır", SpinService.GetCooldown(ctx.player), 0, 0.001)

	ctx.profile.lastSpinAt = os.time()
	local remaining = SpinService.GetCooldown(ctx.player)
	near("çevirdikten sonra tam süre", remaining, Config.SpinCooldownHours * 3600, 5)

	ctx.profile.lastSpinAt = os.time() - Config.SpinCooldownHours * 3600
	near("süre dolunca hak geri geliyor", SpinService.GetCooldown(ctx.player), 0, 5)

	ctx.profile.lastSpinAt = 0
end)

case("Çark: dünyada kurulu ve promptu var", function()
	local decor = workspace:FindFirstChild("Decor")
	local wheel = decor and decor:FindFirstChild("Wheel")
	ok("workspace.Decor.Wheel var", wheel ~= nil)

	if wheel then
		local plinth = wheel:FindFirstChild("WheelPlinth")
		local anchor = plinth and plinth:FindFirstChild("SpinPromptPoint")
		ok("prompt noktası kaidede", anchor ~= nil and anchor:IsA("Attachment"))
		if anchor and plinth then
			ok("SpinPrompt kurulu", anchor:FindFirstChild("SpinPrompt") ~= nil)
			-- Göz hizasında olmalı (yaklaşınca ekranda kalsın), çark göbeğinde değil
			local y = (anchor :: Attachment).WorldPosition.Y - (plinth.Position.Y - plinth.Size.Y / 2)
			ok("prompt alçakta", y > 1 and y < 7, tostring(y))
			-- Çarkın önünde, arkasında değil
			local hub = wheel:FindFirstChild("WheelHub") :: BasePart?
			if hub then
				local pz = plinth.CFrame:PointToObjectSpace((anchor :: Attachment).WorldPosition).Z
				local hz = plinth.CFrame:PointToObjectSpace(hub.Position).Z
				ok("prompt çarkın önünde", pz * hz > 0, tostring(pz) .. " / " .. tostring(hz))
			end
		end
	end
end)

case("Çark: bedava çevirme hakkı harcıyor", function(ctx)
	ctx.profile.lastSpinAt = 0
	setCash(ctx.player, 0)

	local spun = SpinService.Spin(ctx.player, true)
	ok("çevirme başarılı", spun)

	if spun then
		ok("hak harcandı", SpinService.GetCooldown(ctx.player) > 0)
		eq("ikinci çevirme reddedildi", SpinService.Spin(ctx.player, true), false)

		-- Çark kazanılan ödülün diliminde duruyor (açı sunucu saatinden)
		local WheelSpin = require(ReplicatedStorage.Shared.WheelSpin)
		local wheel = workspace.Decor:FindFirstChild("Wheel")
		local slice = wheel and wheel:GetAttribute("SpinSlice")
		local finish = wheel and wheel:GetAttribute("SpinEnd")
		ok("çevirme nitelikleri yazıldı", typeof(slice) == "number" and typeof(finish) == "number")
		if wheel and typeof(slice) == "number" and typeof(finish) == "number" then
			local count = #Config.SpinWheelSlices
			local stop = WheelSpin.Angle(wheel, finish, 26)
			-- Duruş açısında dilimin merkezi tepeden (90°) en fazla yarım dilim sapıyor
			local sliceAt = ((slice - 1) * 360 / count - stop - 90 + 180) % 360 - 180
			ok("dilimde durdu", math.abs(sliceAt) < 180 / count, tostring(sliceAt))
			near("bekleme boyunca yerinde", WheelSpin.Angle(wheel, finish + WheelSpin.HOLD * 0.9, 26), stop, 1e-6)
		end
	end

	ctx.profile.lastSpinAt = 0
end)

case("Çark: her ödülün dilimi var, dilimlerde yazı", function()
	eq("12 dilim", #Config.SpinWheelSlices, 12)
	for _, reward in Config.SpinRewards do
		ok(reward.id .. " çarkta", table.find(Config.SpinWheelSlices, reward.id) ~= nil)
	end
	for _, id in Config.SpinWheelSlices do
		local known = false
		for _, reward in Config.SpinRewards do
			if reward.id == id then
				known = true
			end
		end
		ok(id .. " geçerli ödül", known)
	end
	local wheel = workspace.Decor:FindFirstChild("Wheel")
	local labels = wheel and wheel:FindFirstChild("SliceLabels")
	eq("dilim yazıları", labels and #labels:GetChildren() or 0, 12)
	if labels then
		for _, label in labels:GetChildren() do
			ok("yazı çarkla dönüyor", label:GetAttribute("SpinCenter") ~= nil and label:GetAttribute("SpinAxisVec") ~= nil)
		end
	end
end)

-- ─── M. Hırsızı yakalama ────────────────────────────────────────────────────

case("Yakalama: ayarlar makul", function()
	ok("basılı tutma süresi pozitif", Config.CatchHoldTime > 0)
	ok("menzil kaide menzilinden geniş", Config.CatchRange >= 10, tostring(Config.CatchRange))

	-- Engel süresi çalma beklemesinden uzun olmalı, yoksa caydırıcılığı yok
	ok("engel süresi çalma beklemesinden uzun",
		Config.CatchBlockDuration > Config.StealCooldown,
		string.format("%d vs %d", Config.CatchBlockDuration, Config.StealCooldown))

	-- Ama oyundan kopartacak kadar uzun da olmamalı
	ok("engel süresi 10 dakikayı aşmıyor", Config.CatchBlockDuration <= 600,
		tostring(Config.CatchBlockDuration))
end)

case("Yakalama: kurban sınırı ayarları", function()
	ok("kurban başına çalma sınırı pozitif", Config.StealsPerVictim > 0)
	ok("kurban beklemesi yakalama engelinden uzun",
		Config.VictimCooldown >= Config.CatchBlockDuration,
		string.format("%d vs %d", Config.VictimCooldown, Config.CatchBlockDuration))
end)

-- ─── N. Unvanlar ────────────────────────────────────────────────────────────

case("Unvan: tanımlar tutarlı", function()
	local stats = {
		steals = true, robbed = true, caught = true, maxStreak = true,
		secrets = true, rebirths = true, maxedUpgrades = true,
	}

	local ids, orders = {}, {}
	local uniqueIds, uniqueOrders = true, true

	for _, def in Config.Titles do
		if ids[def.id] then uniqueIds = false end
		ids[def.id] = true

		if orders[def.order] then uniqueOrders = false end
		orders[def.order] = true

		ok(def.id .. " sayacı tanınıyor", stats[def.stat] == true, def.stat)
		ok(def.id .. " eşiği negatif değil", def.threshold >= 0)
		ok(def.id .. " sırası pozitif", def.order > 0)
	end

	ok("id'ler benzersiz", uniqueIds)
	ok("sıralar benzersiz", uniqueOrders)
	ok("en az 8 unvan", #Config.Titles >= 8, tostring(#Config.Titles))
end)

case("Unvan: ödüller sırayla büyüyor", function()
	-- Üst unvan alt unvandan az ödül verirse ilerleme ters hissettirir
	local sorted = table.clone(Config.Titles)
	table.sort(sorted, function(a, b) return a.order < b.order end)

	local previous = -1
	local monotonic = true
	for _, def in sorted do
		local reward = Config.GetTitleReward(def, 0)
		if reward < previous then
			monotonic = false
		end
		previous = reward
	end
	ok("taban ödüller azalmıyor", monotonic)
end)

case("Unvan: başlangıç unvanı herkeste açık", function()
	local zeroThreshold = 0
	for _, def in Config.Titles do
		if def.threshold == 0 then
			zeroThreshold += 1
		end
	end
	ok("eşiği sıfır olan en az bir unvan var", zeroThreshold >= 1, tostring(zeroThreshold))
end)

case("Unvan: profil alanları var", function(ctx)
	local p = ctx.profile
	ok("titles tablo", typeof(p.titles) == "table")
	ok("activeTitle metin", typeof(p.activeTitle) == "string")

	for _, field in { "robbed", "caught", "maxStreak" } do
		ok(field .. " sayı", typeof((p :: any)[field]) == "number")
	end
end)

case("Unvan: koşul sağlanınca açılıyor ve ödül veriyor", function(ctx)
	ctx.profile.titles = {}
	ctx.profile.caught = 0
	setCash(ctx.player, 0)

	TitleService.Check(ctx.player)
	ok("eşiksiz unvan hemen açıldı", ctx.profile.titles.Crewmate == true)

	-- Security unvanı 5 yakalama istiyor
	local def = Config.GetTitle("Security")
	ok("Security tanımlı", def ~= nil)
	if not def then return end

	ok("eşik altında açılmadı", ctx.profile.titles.Security ~= true)

	local before = EconomyService.GetCash(ctx.player)
	for _ = 1, def.threshold do
		TitleService.AddCaught(ctx.player)
	end

	ok("eşiğe ulaşınca açıldı", ctx.profile.titles.Security == true)
	ok("ödül verildi", EconomyService.GetCash(ctx.player) > before,
		Config.FormatCash(EconomyService.GetCash(ctx.player) - before))

	-- İkinci kez ödül vermemeli
	local after = EconomyService.GetCash(ctx.player)
	TitleService.Check(ctx.player)
	eq("tekrar ödül yok", EconomyService.GetCash(ctx.player), after)
end)

case("Unvan: en yüksek olan takılıyor", function(ctx)
	ctx.profile.titles = { Crewmate = true, Security = true }
	ctx.profile.caught = 999
	TitleService.Check(ctx.player)

	local shown = TitleService.GetTitle(ctx.player)
	ok("bir unvan takılı", shown ~= "", shown)

	-- Takılı unvan açık olanların en yüksek sıralısı olmalı
	local best
	for _, def in Config.Titles do
		if ctx.profile.titles[def.id] and (not best or def.order > best.order) then
			best = def
		end
	end
	if best then
		eq("en yüksek sıralı takılı", shown, best.name)
	end
end)

case("Unvan: seri rekoru sadece yükselince yazılıyor", function(ctx)
	ctx.profile.maxStreak = 0

	TitleService.ReportStreak(ctx.player, 3)
	eq("ilk rapor yazıldı", ctx.profile.maxStreak, 3)

	TitleService.ReportStreak(ctx.player, 1)
	eq("düşük rapor yok sayıldı", ctx.profile.maxStreak, 3)

	TitleService.ReportStreak(ctx.player, 7)
	eq("yüksek rapor yazıldı", ctx.profile.maxStreak, 7)
end)

-- ─── O. Öğretici ────────────────────────────────────────────────────────────

case("Öğretici: adım tanımları tutarlı", function()
	local checks = {
		units = true, steals = true, upgrades = true,
		spins = true, locksUsed = true,
	}

	local ids = {}
	local uniqueIds = true

	for _, step in Config.Tutorial do
		if ids[step.id] then uniqueIds = false end
		ids[step.id] = true

		ok(step.id .. " sayacı tanınıyor", checks[step.check] == true, step.check)
		ok(step.id .. " hedefi pozitif", step.goal > 0, tostring(step.goal))
		ok(step.id .. " ödülü negatif değil", step.reward >= 0)
		ok(step.id .. " başlığı dolu", step.title ~= "")
		ok(step.id .. " metni dolu", step.text ~= "")
		ok(step.id .. " hedef nesnesi belirtilmiş", step.hint ~= "")
	end

	ok("id'ler benzersiz", uniqueIds)
	ok("en az 4 adım", #Config.Tutorial >= 4, tostring(#Config.Tutorial))
	ok("aralık dışı adım nil", Config.GetTutorialStep(#Config.Tutorial + 1) == nil)
end)

case("Öğretici: adımlar oynanabilir sırada", function()
	--[[
		Aynı sayaca bakan iki adım varsa ikincisinin hedefi büyük olmalı;
		yoksa ikinci adım birincisiyle aynı anda tamamlanır ve oyuncu ne
		yaptığını anlamadan iki ödül alır.
	]]
	local highest: { [string]: number } = {}
	local increasing = true

	for _, step in Config.Tutorial do
		local previous = highest[step.check]
		if previous and step.goal <= previous then
			increasing = false
		end
		highest[step.check] = step.goal
	end

	ok("aynı sayaca bakan adımlar artıyor", increasing)

	-- İlk adım oyuncunun başlangıç parasıyla yapılabilmeli
	local first = Config.Tutorial[1]
	ok("ilk adım karakter almak", first.check == "units", first.check)
	ok("başlangıç parası en ucuz karaktere yetiyor",
		Config.StartingCash >= Config.GetCheapestUnitPrice(),
		string.format("%d < %d", Config.StartingCash, Config.GetCheapestUnitPrice()))
end)

case("Öğretici: ödül toplamı dengeyi bozmuyor", function()
	local total = Config.GetTutorialTotalReward()

	ok("toplam pozitif", total > 0, Config.FormatCash(total))

	-- Öğreticiyi bitiren oyuncu yükseltmelere dokunabilmeli ama hepsini
	-- birden alamamalı; yoksa oyunun ikinci katmanı bedava geliyor
	local cheapestUpgrade = math.huge
	local allFirstLevels = 0
	for _, def in Config.Upgrades do
		cheapestUpgrade = math.min(cheapestUpgrade, def.baseCost)
		allFirstLevels += def.baseCost
	end

	ok("en ucuz yükseltmeye yetiyor", total >= cheapestUpgrade,
		string.format("%s < %s", Config.FormatCash(total), Config.FormatCash(cheapestUpgrade)))
	ok("tüm yükseltmelerin ilk seviyesini birden almıyor", total < allFirstLevels,
		string.format("%s >= %s", Config.FormatCash(total), Config.FormatCash(allFirstLevels)))

	-- Rebirth maliyeti yanında önemsiz kalmalı
	ok("rebirth maliyetinin yanında küçük", total < Config.GetRebirthCost(0) / 100,
		Config.FormatCash(total))
end)

case("Öğretici: profil alanı var ve sınırlı", function(ctx)
	ok("tutorialStep sayı", typeof(ctx.profile.tutorialStep) == "number",
		typeof(ctx.profile.tutorialStep))
	ok("aralıkta", ctx.profile.tutorialStep >= -1
		and ctx.profile.tutorialStep <= #Config.Tutorial,
		tostring(ctx.profile.tutorialStep))
end)

case("Öğretici: koşul sağlanınca ilerliyor ve ödül veriyor", function(ctx)
	clearPlot(ctx.plot)
	ctx.profile.tutorialStep = 0
	setCash(ctx.player, 0)

	TutorialService.Check(ctx.player)
	eq("karakter yokken ilk adımda kalıyor", ctx.profile.tutorialStep, 0)

	local step = Config.Tutorial[1]
	local before = EconomyService.GetCash(ctx.player)

	-- İlk adım: kaideye bir karakter koymak
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	ok("boş kaide var", podium ~= nil)
	if not podium then return end
	PlotService.PlaceUnit(podium, Config.Units[1].id, nil)

	TutorialService.Check(ctx.player)
	eq("adım tamamlandı", ctx.profile.tutorialStep, 1)
	eq("ödül verildi", EconomyService.GetCash(ctx.player) - before, step.reward)

	-- İkinci kez ödül vermemeli
	local after = EconomyService.GetCash(ctx.player)
	TutorialService.Check(ctx.player)
	eq("tekrar ödül yok", EconomyService.GetCash(ctx.player), after)
	eq("adım geri gitmedi", ctx.profile.tutorialStep, 1)

	clearPlot(ctx.plot)
end)

case("Öğretici: bir turda birden fazla adım geçebiliyor", function(ctx)
	--[[
		Oyuncu arka arkaya iki karakter alırsa iki adım birden tamamlanmalı.
		Tek adım ilerleyen bir döngü, oyuncuyu bir saniye boyunca bitmiş bir
		görevle bekletiyordu.
	]]
	clearPlot(ctx.plot)
	ctx.profile.tutorialStep = 0
	-- Çalma sayacı sıfırlanmazsa 3. adım (birinden çal) da aynı turda
	-- tamamlanıyor ve beklenen ödül tutmuyor
	ctx.profile.stolen = 0
	setCash(ctx.player, 0)

	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)
	ok("en az iki kaide açık", #podiums >= 2, tostring(#podiums))
	if #podiums < 2 then return end

	PlotService.PlaceUnit(podiums[1], Config.Units[1].id, nil)
	PlotService.PlaceUnit(podiums[2], Config.Units[1].id, nil)

	TutorialService.Check(ctx.player)
	ok("iki adım birden geçti", ctx.profile.tutorialStep >= 2,
		tostring(ctx.profile.tutorialStep))

	local expected = Config.Tutorial[1].reward + Config.Tutorial[2].reward
	eq("iki ödül de verildi", EconomyService.GetCash(ctx.player), expected)

	clearPlot(ctx.plot)
end)

case("Öğretici: bitince bonus veriyor ve susuyor", function(ctx)
	ctx.profile.tutorialStep = #Config.Tutorial - 1
	setCash(ctx.player, 0)

	-- Son adımın koşulunu sağla
	local last = Config.Tutorial[#Config.Tutorial]
	eq("son adım çark", last.check, "spins")
	ctx.profile.lastSpinAt = os.time()

	TutorialService.Check(ctx.player)
	eq("öğretici bitti", ctx.profile.tutorialStep, #Config.Tutorial)
	eq("bitiş bonusu dahil", EconomyService.GetCash(ctx.player),
		last.reward + Config.TutorialFinishBonus)

	ok("bitmiş sayılıyor", TutorialService.IsFinished(ctx.player))
	ok("sıradaki adım yok", TutorialService.GetStep(ctx.player) == nil)

	local after = EconomyService.GetCash(ctx.player)
	TutorialService.Check(ctx.player)
	eq("bonus tekrar verilmiyor", EconomyService.GetCash(ctx.player), after)
end)

case("Öğretici: atlamak ödül vermiyor", function(ctx)
	ctx.profile.tutorialStep = 0
	setCash(ctx.player, 0)

	TutorialService.Skip(ctx.player)

	ok("bitmiş sayılıyor", TutorialService.IsFinished(ctx.player))
	eq("hiç ödül verilmedi", EconomyService.GetCash(ctx.player), 0)
	ok("sıradaki adım yok", TutorialService.GetStep(ctx.player) == nil)

	-- Atlanmış öğretici geri açılmamalı
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	if podium then
		PlotService.PlaceUnit(podium, Config.Units[1].id, nil)
	end
	TutorialService.Check(ctx.player)
	eq("koşul sağlansa da geri açılmıyor", EconomyService.GetCash(ctx.player), 0)

	clearPlot(ctx.plot)
end)

case("Öğretici: eski kayıt öğreticiye sokulmuyor", function(ctx)
	--[[
		tutorialStep alanı sonradan eklendi; onsuz kaydedilmiş profiller 0
		ile geliyor. Oynadığına dair iz varsa öğretici bitmiş sayılmalı,
		yoksa yıllardır oynayan oyuncuya "ilk karakterini al" deniyor.
	]]
	clearPlot(ctx.plot)
	ctx.profile.tutorialStep = 0
	ctx.profile.stolen = 12
	setCash(ctx.player, 0)

	local before = EconomyService.GetCash(ctx.player)
	local finished = TutorialService.SkipIfVeteran(ctx.player)

	ok("eski oyuncu tespit edildi", finished)
	ok("öğretici bitmiş sayılıyor", TutorialService.IsFinished(ctx.player))
	eq("ödül dağıtılmadı", EconomyService.GetCash(ctx.player), before)

	-- Gerçekten yeni oyuncu elenmemeli
	ctx.profile.tutorialStep = 0
	ctx.profile.stolen = 0
	ctx.profile.rebirths = 0
	ctx.profile.lastSpinAt = 0
	ctx.profile.upgrades = {}
	setCash(ctx.player, Config.StartingCash)

	ok("yeni oyuncu öğreticide kalıyor", not TutorialService.SkipIfVeteran(ctx.player))
	eq("adım sıfırda", ctx.profile.tutorialStep, 0)
end)

case("Öğretici: hedef nesneler dünyada var", function(ctx)
	--[[
		Adımın hint'i karşılığını bulamazsa oyuncuya hedef gösterilmiyor ve
		"nereye gideceğim" sorusu cevapsız kalıyor. Bu test hint isimleriyle
		dünyadaki nesne adlarını senkronda tutuyor.
	]]
	local resolvable = {
		Conveyor = function()
			return ctx.plot:FindFirstChild("Conveyor")
		end,
		Sign = function()
			return ctx.plot:FindFirstChild("Sign")
		end,
		Upgrades = function()
			return ctx.plot:FindFirstChild("UpgradeBooth")
		end,
		Wheel = function()
			local decor = workspace:FindFirstChild("Decor")
			return decor and decor:FindFirstChild("Wheel")
		end,
		RivalPlot = function()
			for _, other in PlotService.GetAllPlots() do
				if other ~= ctx.plot then
					return other
				end
			end
			return nil
		end,
	}

	for _, step in Config.Tutorial do
		local finder = resolvable[step.hint]
		ok(step.id .. " hint'i tanınıyor", finder ~= nil, step.hint)
		if finder then
			ok(step.hint .. " dünyada bulundu", finder() ~= nil)
		end
	end
end)

case("Öğretici: durum niteliği istemciye yansıyor", function(ctx)
	clearPlot(ctx.plot)
	ctx.profile.tutorialStep = 0
	TutorialService.Check(ctx.player)

	local value = ctx.player:GetAttribute("TutorialStep")
	ok("TutorialStep niteliği var", typeof(value) == "number", typeof(value))
	eq("profil ile aynı", value, ctx.profile.tutorialStep)
end)

-- ─── P. Unvan kuşanma ───────────────────────────────────────────────────────

case("Unvan: açık olanı kuşanabiliyoruz", function(ctx)
	ctx.profile.titles = { Crewmate = true, Security = true }
	ctx.profile.titleManual = false
	ctx.profile.activeTitle = ""

	ok("açık unvan takıldı", TitleService.Equip(ctx.player, "Security"))
	eq("profile yazıldı", ctx.profile.activeTitle, "Security")
	eq("nitelik yazıldı", ctx.player:GetAttribute("Title"), "Security")
	ok("elle seçim işaretlendi", ctx.profile.titleManual)
end)

case("Unvan: açılmamış olan reddediliyor", function(ctx)
	ctx.profile.titles = { Crewmate = true }
	ctx.profile.titleManual = false
	ctx.profile.activeTitle = "Crewmate"

	ok("kilitli unvan reddedildi", not TitleService.Equip(ctx.player, "Captain"))
	eq("takılı unvan değişmedi", ctx.profile.activeTitle, "Crewmate")

	ok("uydurma kimlik reddedildi", not TitleService.Equip(ctx.player, "YokBoyleBirSey"))
	eq("yine değişmedi", ctx.profile.activeTitle, "Crewmate")
end)

case("Unvan: elle seçim yeni açılanla ezilmiyor", function(ctx)
	--[[
		Oyuncu düşük bir unvanı beğenip taktıysa, sonradan daha yükseği
		açılınca üstüne yazmamalı. Otomatik seçimin tek işi menüyü hiç
		açmayan oyuncuyu ilerletmek.
	]]
	ctx.profile.titles = { Crewmate = true, Sus = true }
	ctx.profile.caught = 0
	TitleService.Equip(ctx.player, "Sus")
	eq("seçim yapıldı", ctx.profile.activeTitle, "Sus")

	-- Daha yüksek sıralı bir unvan aç
	for _ = 1, 5 do
		TitleService.AddCaught(ctx.player)
	end

	ok("yeni unvan gerçekten açıldı", ctx.profile.titles.Security == true)
	eq("seçim korundu", ctx.profile.activeTitle, "Sus")
	eq("nitelik de korundu", ctx.player:GetAttribute("Title"), "Sus")
end)

case("Unvan: otomatiğe dönülebiliyor", function(ctx)
	ctx.profile.titles = { Crewmate = true, Security = true }
	ctx.profile.caught = 999
	TitleService.Equip(ctx.player, "Crewmate")
	eq("düşük unvan takılı", ctx.profile.activeTitle, "Crewmate")

	ok("boş kimlik kabul edildi", TitleService.Equip(ctx.player, ""))
	ok("elle seçim kalktı", not ctx.profile.titleManual)
	eq("en yükseğe döndü", ctx.profile.activeTitle, "Security")
end)

-- ─── R. Görevler ────────────────────────────────────────────────────────────

case("Görev: tanımlar tutarlı", function()
	local stats = {
		stolen = true, bought = true, sold = true, earned = true,
		caught = true, spins = true, rebirths = true, upgrades = true,
	}

	local ids = {}
	local uniqueIds = true

	for _, def in Config.Quests do
		if ids[def.id] then uniqueIds = false end
		ids[def.id] = true

		ok(def.id .. " sayacı tanınıyor", stats[def.stat] == true, def.stat)
		ok(def.id .. " metni %s içeriyor", string.find(def.text, "%%s") ~= nil, def.text)
		ok(def.id .. " vadesi geçerli",
			def.fromTier >= 1 and def.fromTier <= #Config.QuestTiers,
			tostring(def.fromTier))

		if def.incomeSeconds then
			ok(def.id .. " nakit tabanı var", (def.minimum or 0) > 0)
		else
			ok(def.id .. " tabanı pozitif", def.base > 0)
			ok(def.id .. " tavanı tabandan küçük değil", def.maxGoal >= def.base)
		end
	end

	ok("id'ler benzersiz", uniqueIds)
	ok("en az 6 görev", #Config.Quests >= 6, tostring(#Config.Quests))
end)

case("Görev: vadeler sırayla büyüyor", function()
	local previousSeconds, previousMul, previousReward = 0, 0, 0
	local increasing = true

	for _, tier in Config.QuestTiers do
		if tier.seconds <= previousSeconds
			or tier.goalMul < previousMul
			or tier.rewardMinimum <= previousReward
		then
			increasing = false
		end
		previousSeconds = tier.seconds
		previousMul = tier.goalMul
		previousReward = tier.rewardMinimum

		ok(tier.id .. " slot sayısı pozitif", tier.slots > 0)
	end

	ok("süre, hedef ve ödül birlikte büyüyor", increasing)
	eq("üç vade var", #Config.QuestTiers, 3)
	eq("ilki 30 dakika", Config.QuestTiers[1].seconds, 1800)
	eq("ikincisi 3 saat", Config.QuestTiers[2].seconds, 10800)
	eq("üçüncüsü günlük", Config.QuestTiers[3].seconds, 86400)
end)

case("Görev: çekim aynı görevi iki kez vermiyor", function()
	local rng = Random.new(12345)

	for _, tier in Config.QuestTiers do
		local tierIndex = Config.GetQuestTierIndex(tier.id)

		for _ = 1, 40 do
			local picked = Config.RollQuests(rng, tier)
			local seen = {}
			local unique, allowed = true, true

			for _, def in picked do
				if seen[def.id] then unique = false end
				seen[def.id] = true
				if def.fromTier > tierIndex then allowed = false end
			end

			if not unique then
				ok(tier.id .. " tekrar yok", false)
				break
			end
			if not allowed then
				ok(tier.id .. " erken vade görevi yok", false)
				break
			end
		end

		ok(tier.id .. " çekimi geçerli", true)
	end
end)

case("Görev: hedefler vadeye göre ölçekleniyor", function()
	local steal = Config.GetQuest("Steal")
	ok("Steal tanımlı", steal ~= nil)
	if not steal then return end

	local short = Config.GetQuestTier("short")
	local daily = Config.GetQuestTier("daily")
	if not (short and daily) then return end

	local shortGoal = Config.GetQuestGoal(steal, short, 0)
	local dailyGoal = Config.GetQuestGoal(steal, daily, 0)

	ok("günlük hedef daha büyük", dailyGoal > shortGoal,
		string.format("%d vs %d", dailyGoal, shortGoal))
	ok("tavan aşılmıyor", dailyGoal <= steal.maxGoal, tostring(dailyGoal))

	-- Başkasına bağlı görevin tavanı düşük olmalı
	local catch = Config.GetQuest("Catch")
	if catch then
		ok("yakalama tavanı düşük", catch.maxGoal <= 5, tostring(catch.maxGoal))
	end
end)

case("Görev: nakit hedefi gelirle ölçekleniyor", function()
	local earn = Config.GetQuest("Earn")
	local short = Config.GetQuestTier("short")
	ok("Earn tanımlı", earn ~= nil)
	if not (earn and short) then return end

	local poor = Config.GetQuestGoal(earn, short, 0)
	local rich = Config.GetQuestGoal(earn, short, 100000)

	ok("gelirsiz oyuncuda taban geçerli", poor > 0, tostring(poor))
	ok("zengin oyuncuda hedef büyüyor", rich > poor,
		string.format("%d vs %d", rich, poor))
end)

case("Görev: ödül gelirle ölçekleniyor ve tabanı var", function()
	for _, tier in Config.QuestTiers do
		local poor = Config.GetQuestReward(tier, 0)
		local rich = Config.GetQuestReward(tier, 100000)

		eq(tier.id .. " tabanı", poor, tier.rewardMinimum)
		ok(tier.id .. " gelirle büyüyor", rich > poor)
	end
end)

case("Görev: profil alanları var", function(ctx)
	local p = ctx.profile
	ok("quests tablo", typeof(p.quests) == "table")
	ok("potions tablo", typeof(p.potions) == "table")

	for _, field in { "bought", "sold", "spins", "earned" } do
		ok(field .. " sayı", typeof((p :: any)[field]) == "number", typeof((p :: any)[field]))
	end
end)

case("Görev: çekiliyor ve ilerliyor", function(ctx)
	ctx.profile.quests = {}
	ctx.profile.stolen = 0
	QuestService.Check(ctx.player)

	local slot = ctx.profile.quests.short
	ok("kısa vade çekildi", slot ~= nil)
	if not slot then return end

	ok("görev var", #slot.entries > 0, tostring(#slot.entries))
	ok("pencere ileride", slot.expiresAt > os.time())

	-- Steal görevini zorla yerleştir ki ilerlemeyi ölçebilelim
	slot.entries = { { id = "Steal", goal = 2, baseline = ctx.profile.stolen, done = false } }

	QuestService.Check(ctx.player)
	ok("eşik altında tamamlanmadı", not slot.entries[1].done)

	local before = EconomyService.GetCash(ctx.player)
	ctx.profile.stolen += 2
	QuestService.Check(ctx.player)

	ok("eşiğe ulaşınca tamamlandı", slot.entries[1].done)
	--[[
		Ödül artık Check'te GELMİYOR: oyuncu panelden kendi topluyor.
		Otomatik ödülde görevler hiç okunmuyordu.
	]]
	eq("tamamlanınca ödül verilmedi", EconomyService.GetCash(ctx.player), before)
	ok("teslim alınmadı olarak duruyor", not slot.entries[1].claimed)
end)

case("Görev: ilerleme tabana göre, mutlak değere göre değil", function(ctx)
	--[[
		Zaten 500 kez çalmış oyuncuya "3 kez çal" görevi verildiğinde görev
		anında tamamlanmamalı. Taban kaydı tam olarak bunun için var.
	]]
	ctx.profile.quests = {}
	ctx.profile.stolen = 500

	QuestService.RollTier(ctx.player, "short")
	local slot = ctx.profile.quests.short
	ok("vade çekildi", slot ~= nil)
	if not slot then return end

	slot.entries = { { id = "Steal", goal = 3, baseline = ctx.profile.stolen, done = false } }
	QuestService.Check(ctx.player)
	ok("geçmiş sayılmadı", not slot.entries[1].done, tostring(ctx.profile.stolen))

	ctx.profile.stolen += 3
	QuestService.Check(ctx.player)
	ok("yeni ilerleme sayıldı", slot.entries[1].done)
end)

case("Görev: süresi dolan vade yeniden çekiliyor", function(ctx)
	ctx.profile.quests = {}
	QuestService.Check(ctx.player)

	local slot = ctx.profile.quests.short
	ok("vade var", slot ~= nil)
	if not slot then return end

	slot.expiresAt = os.time() - 1
	for _, entry in slot.entries do
		entry.done = true
	end

	QuestService.Check(ctx.player)
	local fresh = ctx.profile.quests.short
	ok("pencere yenilendi", fresh.expiresAt > os.time())

	local anyOpen = false
	for _, entry in fresh.entries do
		if not entry.done then
			anyOpen = true
		end
	end
	ok("yeni görevler açık geldi", anyOpen)
end)

-- ─── S. İksirler ────────────────────────────────────────────────────────────

case("Görev: ödül elle toplanıyor", function(ctx)
	ctx.profile.quests = {}
	ctx.profile.stolen = 0
	QuestService.Check(ctx.player)

	local slot = ctx.profile.quests.short
	ok("vade var", slot ~= nil)
	if not slot then return end

	slot.entries = { { id = "Steal", goal = 1, baseline = ctx.profile.stolen, done = false, claimed = false } }
	setCash(ctx.player, 0)

	-- Bitmemiş görev toplanamaz
	ok("bitmemiş görev toplanamıyor", not QuestService.Claim(ctx.player, "short", "Steal"))
	eq("para gelmedi", EconomyService.GetCash(ctx.player), 0)

	-- Koşulu sağla
	ctx.profile.stolen += 1
	QuestService.Check(ctx.player)
	ok("görev tamamlandı", slot.entries[1].done)
	eq("ama ödül hâlâ verilmedi", EconomyService.GetCash(ctx.player), 0)

	-- Topla
	ok("toplama başarılı", QuestService.Claim(ctx.player, "short", "Steal"))
	ok("ödül geldi", EconomyService.GetCash(ctx.player) > 0,
		Config.FormatCash(EconomyService.GetCash(ctx.player)))
	ok("teslim alındı işaretlendi", slot.entries[1].claimed)

	-- İkinci kez toplanamaz
	local after = EconomyService.GetCash(ctx.player)
	ok("ikinci toplama reddedildi", not QuestService.Claim(ctx.player, "short", "Steal"))
	eq("para değişmedi", EconomyService.GetCash(ctx.player), after)
end)

case("Görev: uydurma toplama isteği reddediliyor", function(ctx)
	--[[
		İstemciden gelen iki metin doğrudan aranıyor. Olmayan vade ya da
		olmayan görev sessizce reddedilmeli; istemciye güvenilmiyor.
	]]
	setCash(ctx.player, 0)

	ok("olmayan vade reddedildi", not QuestService.Claim(ctx.player, "yok", "Steal"))
	ok("olmayan görev reddedildi", not QuestService.Claim(ctx.player, "short", "YokBoyleBirGorev"))
	eq("para gelmedi", EconomyService.GetCash(ctx.player), 0)
end)

case("Görev: eski kayıtta biten görev tekrar toplanamıyor", function(ctx)
	--[[
		claimed alanı sonradan eklendi. Eski kayıtta done=true olan
		görevin ödülü ZATEN verilmişti (o zaman otomatikti). Göç onları
		teslim alınmış saymalı, yoksa oyuncu aynı ödülü bir kez daha
		toplardı.
	]]
	ctx.profile.quests = {}
	QuestService.Check(ctx.player)

	local slot = ctx.profile.quests.short
	if not slot then return end

	-- Göçün ürettiği hâl: done ve claimed birlikte
	slot.entries = { { id = "Steal", goal = 1, baseline = 0, done = true, claimed = true } }
	setCash(ctx.player, 0)

	ok("toplanamıyor", not QuestService.Claim(ctx.player, "short", "Steal"))
	eq("para gelmedi", EconomyService.GetCash(ctx.player), 0)
end)

case("İksir: tanımlar tutarlı", function()
	local kinds = { income = true, steal = true, lock = true }
	local ids = {}
	local uniqueIds = true

	for _, def in Config.Potions do
		if ids[def.id] then uniqueIds = false end
		ids[def.id] = true

		ok(def.id .. " türü tanınıyor", kinds[def.kind] == true, def.kind)
		ok(def.id .. " süreli", def.seconds > 0, tostring(def.seconds))
		ok(def.id .. " ağırlığı pozitif", def.weight > 0)
		ok(def.id .. " açıklaması dolu", def.description ~= "")

		if def.kind == "income" then
			ok(def.id .. " çarpanı var", (def.multiplier or 0) > 1)
		end
	end

	ok("id'ler benzersiz", uniqueIds)
	ok("stok sınırı makul", Config.PotionStackLimit >= 1 and Config.PotionStackLimit <= 20,
		tostring(Config.PotionStackLimit))
end)

case("İksir: hiçbiri kalıcı değil", function()
	--[[
		Bu ödüller Robux pass'lerinin karşılığı. Süresiz bir tanesi bile
		pass satışını öldürür; test o yüzden var.
	]]
	local allTimed = true
	for _, def in Config.Potions do
		if def.seconds <= 0 or def.seconds > 3600 then
			allTimed = false
		end
	end
	ok("hepsi süreli ve en fazla bir saat", allTimed)
end)

case("İksir: rulet tüm iksirleri üretebiliyor", function()
	local rng = Random.new(777)
	local seen = {}

	for _ = 1, 2000 do
		seen[Config.RollPotion(rng).id] = true
	end

	for _, def in Config.Potions do
		ok(def.id .. " çıkabiliyor", seen[def.id] == true)
	end
end)

case("İksir: envantere giriyor ve stok sınırı var", function(ctx)
	ctx.profile.potions = {}

	ok("verildi", PotionService.Grant(ctx.player, "Income2x"))
	eq("adet bir", PotionService.GetCount(ctx.player, "Income2x"), 1)

	for _ = 1, Config.PotionStackLimit + 5 do
		PotionService.Grant(ctx.player, "Income2x")
	end
	eq("stok sınırında durdu",
		PotionService.GetCount(ctx.player, "Income2x"), Config.PotionStackLimit)

	ok("dolu stoka ekleme reddedildi", not PotionService.Grant(ctx.player, "Income2x"))
	ok("uydurma iksir reddedildi", not PotionService.Grant(ctx.player, "YokBoyleBirSey"))
end)

case("İksir: içmek envanterden düşüyor ve takviye başlatıyor", function(ctx)
	ctx.profile.potions = { Income2x = 2 }

	local before = MonetizationService.GetIncomeMultiplier(ctx.player)

	ok("içildi", PotionService.Use(ctx.player, "Income2x"))
	eq("envanterden düştü", PotionService.GetCount(ctx.player, "Income2x"), 1)

	ok("takviye aktif", MonetizationService.GetBoostRemaining(ctx.player, "income") > 0,
		tostring(MonetizationService.GetBoostRemaining(ctx.player, "income")))
	ok("gelir çarpanı arttı", MonetizationService.GetIncomeMultiplier(ctx.player) > before,
		string.format("%.1f -> %.1f", before, MonetizationService.GetIncomeMultiplier(ctx.player)))
end)

case("İksir: olmayan iksir içilemiyor", function(ctx)
	ctx.profile.potions = {}

	ok("envanterde yokken reddedildi", not PotionService.Use(ctx.player, "Income2x"))
	ok("uydurma kimlik reddedildi", not PotionService.Use(ctx.player, "YokBoyleBirSey"))
	eq("envanter bozulmadı", PotionService.GetCount(ctx.player, "Income2x"), 0)
end)

case("İksir: gelir takviyesi geliri gerçekten çarpıyor", function(ctx)
	-- Önceki test bir takviye açık bırakmış olabilir; "temel gelir"
	-- ölçümünün boostsuz olması şart
	MonetizationService.ClearBoosts(ctx.player)
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	ok("boş kaide var", podium ~= nil)
	if not podium then return end

	PlotService.PlaceUnit(podium, Config.Units[1].id, nil)
	local base = EconomyService.GetIncome(ctx.player)
	ok("temel gelir pozitif", base > 0, tostring(base))

	ctx.profile.potions = { Income2x = 1 }
	PotionService.Use(ctx.player, "Income2x")

	local boosted = EconomyService.GetIncome(ctx.player)
	ok("gelir arttı", boosted > base, string.format("%d -> %d", base, boosted))

	clearPlot(ctx.plot)
end)

case("İksir: süre dolunca etki bitiyor", function(ctx)
	--[[
		Kalan süreyi doğrudan sınayamıyoruz (os.time saniyelik). Bunun
		yerine hiç takviye verilmemiş bir türü kontrol ediyoruz: sıfır
		dönmeli, yani "aktif" varsayılanı yok.
	]]
	MonetizationService.ClearBoosts(ctx.player)
	eq("verilmemiş takviye sıfır",
		MonetizationService.GetBoostRemaining(ctx.player, "lock"), 0)

	ctx.profile.potions = { StrongLock = 1 }
	PotionService.Use(ctx.player, "StrongLock")

	local remaining = MonetizationService.GetBoostRemaining(ctx.player, "lock")
	local def = Config.GetPotion("StrongLock")
	ok("süre tanımdaki kadar", def ~= nil and remaining <= def.seconds and remaining > 0,
		tostring(remaining))
end)

case("İksir: pass'in üstüne binmiyor", function(ctx)
	--[[
		Parasını verip kalıcı 2x alan oyuncu, bedava iksirle 4x kazanmamalı.
		MonetizationService ikisinin büyüğünü alıyor.
	]]
	MonetizationService.ClearBoosts(ctx.player)
	ctx.profile.potions = { Income2x = 1 }
	PotionService.Use(ctx.player, "Income2x")

	local withBoost = MonetizationService.GetIncomeMultiplier(ctx.player)
	ok("çarpan pass değerini aşmıyor", withBoost <= Config.PassDoubleIncomeMultiplier,
		string.format("%.1f > %.1f", withBoost, Config.PassDoubleIncomeMultiplier))
end)

case("Görev: günlük vadeyi bitirmek iksir veriyor", function(ctx)
	ctx.profile.potions = {}
	ctx.profile.quests = {}
	QuestService.Check(ctx.player)

	local slot = ctx.profile.quests.daily
	ok("günlük vade var", slot ~= nil)
	if not slot then return end

	-- Tamamlanmış say ama "yeni tamamlandı" anını yakalayabilmek için
	-- son görevi açık bırak
	for index, entry in slot.entries do
		entry.done = index < #slot.entries
	end

	local last = slot.entries[#slot.entries]
	local def = Config.GetQuest(last.id)
	ok("son görev tanımlı", def ~= nil)
	if not def then return end

	-- Son görevin koşulunu sağla
	last.goal = 1
	last.baseline = -1

	QuestService.Check(ctx.player)
	ok("son görev tamamlandı", last.done)

	--[[
		Bonus TESLİM ALINCA geliyor, tamamlanınca değil. Oyuncu son
		ödülünü almadan bonusu alsaydı "kendi alsın" kuralı yarım kalırdı.
	]]
	local beforeClaim = 0
	for _, count in ctx.profile.potions do
		beforeClaim += count
	end
	eq("tamamlanınca iksir gelmedi", beforeClaim, 0)

	-- Diğerlerini teslim alınmış say, sonuncuyu elle topla
	for index, entry in slot.entries do
		entry.claimed = index < #slot.entries
	end
	ok("son görev toplandı", QuestService.Claim(ctx.player, "daily", last.id))

	local total = 0
	for _, count in ctx.profile.potions do
		total += count
	end
	ok("iksir verildi", total > 0, tostring(total))

	-- İkinci kez toplanamaz
	ok("tekrar toplanamıyor", not QuestService.Claim(ctx.player, "daily", last.id))
	local after = 0
	for _, count in ctx.profile.potions do
		after += count
	end
	eq("tekrar iksir yok", after, total)
end)

case("Güvenlik: istemciden sunucuya dinlenen remote listesi bilinçli", function()
	--[[
		Eski hali toplam remote sayısına bakıyordu; server -> client yönü
		büyüdükçe o sayı anlamsız şişiyordu. Asıl önemli olan İSTEMCİNİN
		tetikleyebildiği remote'lar — saldırı yüzeyi orası.
	]]
	local listened = Net.GetClientToServer()

	--[[
		Sayı büyüdükçe değil, gerekçesizleştikçe tehlikeli.

		Şu an on dört remote var: TutorialSkip, TitleEquip, PotionUse,
		QuestClaim, UpgradeBuy, Sprint, FloorBuy, RebirthBuy, PetHatch,
		PetEquip, PetFuse, RewardClaim, GearBuy, AsteroidsDone, TaskDone,
		CosmeticAction, SabotageAction. Hiçbiri
		oyuncuya bedava bir şey VERMİYOR — ya oyuncunun kendi parasını
		harcıyor, ya zaten kazanılmış bir şeyi kullanıyor, ya da hakkı
		sunucudaki sayaçlardan hesaplanan bir ödülü topluyor. AsteroidsDone
		küçük bir ödül veriyor ama oyunun başlangıcı, süresi ve bekleme
		süresi sunucuda (MinigameService.TryComplete, testi aşağıda).
		Gerekçeleri Net.luau'da tek tek yazılı.

		Sınır on sekizde (TaskDone ek oda görevleri, CosmeticAction kozmetikler,
		SabotageAction sabotaj eşyaları, SettingsSave oyuncu ayarları için
		eklendi; gerekçeleri Net.luau'da): yenisi eklemek bilinçli bir karar
		olsun, kazara büyümesin.
	]]
	ok("liste bilinçli", #listened <= 18, tostring(#listened))

	for _, name in listened do
		ok(name .. " gerçekten var", ReplicatedStorage.Net:FindFirstChild(name) ~= nil)
		ok(name .. " yön haritasında", Net.IsClientToServer(name))
	end

	-- Yön haritasında olmayan hiçbir remote dinlenmemeli
	ok("Notify dinlenmiyor", not Net.IsClientToServer("Notify"))
	ok("Quests dinlenmiyor", not Net.IsClientToServer("Quests"))
	ok("Titles dinlenmiyor", not Net.IsClientToServer("Titles"))
	ok("Potions dinlenmiyor", not Net.IsClientToServer("Potions"))
end)

-- ─── T. Üst kat satın alma ──────────────────────────────────────────────────

case("Ses: her servisin bildirim türünün sesi var", function()
	--[[
		Sunucu bildirimle birlikte bir TÜR gönderiyor, istemci ona göre ses
		seçiyor. Sunucuya yeni bir tür eklenip Config.NotifyCues'a
		yazılmazsa o işlem sessizce taban sese düşer ve kimse fark etmez —
		kullanıcının şikâyeti tam olarak buydu: her şey aynı sesti.

		Betik kaynağını okuyamıyoruz (çalışan oyun betiği için Roblox bunu
		eklentiye kısıtlıyor), o yüzden her servis kendi türünü NotifyKind
		olarak dışa açıyor ve burada onu topluyoruz.
	]]
	local missing = {}
	local checked = 0

	for _, module in script.Parent:GetChildren() do
		if not module:IsA("ModuleScript") or module.Name == "Tests" then
			continue
		end

		local loaded = require(module) :: any
		local kind = if typeof(loaded) == "table" then loaded.NotifyKind else nil

		if typeof(kind) == "string" then
			checked += 1
			if not Config.HasNotifyCue(kind) then
				table.insert(missing, module.Name .. ":" .. kind)
			end
		end
	end

	ok("tür açan servis var", checked >= 10, tostring(checked))
	ok("sesi olmayan tür yok", #missing == 0, table.concat(missing, ", "))
end)

case("Ses: tınılar birbirinden ayırt edilebilir", function()
	--[[
		Ayrı tür ama aynı perde+seviye, kulakta aynı sese çıkıyor. En sık
		karıştırılacak üçlü satın alma / satma / yükseltme; onlar kesin
		farklı olmalı.
	]]
	local seen: { [string]: string } = {}
	local clashes = {}

	for kind, cue in Config.NotifyCues do
		ok(kind .. " perdesi makul", cue.pitch >= 0.4 and cue.pitch <= 2,
			string.format("%.2f", cue.pitch))
		ok(kind .. " seviyesi makul", cue.volume > 0 and cue.volume <= 1,
			string.format("%.2f", cue.volume))

		--[[
			İmzaya KAYNAK da dahil: tımbre farkı perdeden güçlü bir işaret
			ve iki tür aynı perdede olsa bile farklı örnekten geliyorsa
			karışmıyor. Kaynak yoksa taban örnek (Success).
		]]
		local signature = string.format("%s@%.2f/%.2f/%.2f/%d",
			cue.source or "Success", cue.startAt or 0,
			cue.pitch, cue.volume, cue.repeats or 1)

		if seen[signature] then
			table.insert(clashes, seen[signature] .. "=" .. kind)
		end
		seen[signature] = kind
	end

	ok("aynı tınıya sahip iki tür yok", #clashes == 0, table.concat(clashes, ", "))

	--[[
		En sık arka arkaya yapılan üçlü. Kullanıcının şikâyeti tam olarak
		bunların ayırt edilememesiydi, o yüzden burada ayrıca sınanıyorlar:
		ya farklı örnekten gelmeli ya da perdeleri belirgin ayrı olmalı.
	]]
	local core = {}
	for _, kind in { "buy", "sell", "upgrade" } do
		local cue = Config.NotifyCues[kind]
		ok(kind .. " tanımlı", cue ~= nil)
		if cue then
			table.insert(core, { kind = kind, cue = cue })
		end
	end

	for i = 1, #core do
		for j = i + 1, #core do
			local a, b = core[i], core[j]
			local differentSource = (a.cue.source or "Success") ~= (b.cue.source or "Success")
			-- Perde oranı: 1.5 kat ~ yedi yarım ses, kulakta net ayrı
			local ratio = math.max(a.cue.pitch, b.cue.pitch) / math.min(a.cue.pitch, b.cue.pitch)

			ok(string.format("%s ile %s ayırt edilebilir", a.kind, b.kind),
				differentSource or ratio >= 1.5,
				string.format("aynı örnek, perde oranı %.2f", ratio))
		end
	end
end)

case("Ses: her tınının kaynağı gerçekten var", function()
	--[[
		Kaynak adı Config'te metin, karşılığı SoundFX'teki ID tablosunda.
		İkisi ayrı dosyada olduğu için bir yazım hatası sessizce taban
		sese düşürüyor ve kimse fark etmiyor — bu tam olarak oldu:
		Config "AlarmBurst" diyordu, tabloda adı "Alarm"dı.

		Sunucudan SoundFX'in kendi tablosunu okuyamıyoruz (istemci modülü),
		o yüzden geçerli adların listesi burada duruyor. Yeni kaynak
		eklenince buraya da yazılmalı; test bunu zorluyor.
	]]
	local SOURCES = {
		Ambient = true, Machine = true, Alarm = true,
		UiA = true, UiB = true, UiC = true, UiD = true,
		Throb = true, Deny = true, Success = true,
	}

	local bad = {}
	for kind, cue in Config.NotifyCues do
		if cue.source and not SOURCES[cue.source] then
			table.insert(bad, kind .. "->" .. cue.source)
		end

		-- Kesit başlangıcı negatif olamaz; süre de pozitif olmalı
		if cue.startAt then
			ok(kind .. " kesit başlangıcı geçerli", cue.startAt >= 0,
				tostring(cue.startAt))
		end
		if cue.length then
			ok(kind .. " kesit süresi pozitif", cue.length > 0, tostring(cue.length))
		end
	end

	ok("tanınmayan kaynak yok", #bad == 0, table.concat(bad, ", "))
end)

case("Kat: tanımlar tutarlı", function()
	local floors = {}
	local increasing = true
	local previousCost, previousRebirths = 0, -1

	for _, def in Config.FloorUnlocks do
		ok("kat " .. def.floor .. " birden büyük", def.floor >= 2, tostring(def.floor))
		ok("kat " .. def.floor .. " tavanda", def.floor <= Config.MaxFloors)
		ok("kat " .. def.floor .. " fiyatı pozitif", def.cost > 0)

		if def.cost <= previousCost or def.rebirths < previousRebirths then
			increasing = false
		end
		previousCost = def.cost
		previousRebirths = def.rebirths

		floors[def.floor] = true
	end

	ok("fiyat ve rebirth koşulu birlikte artıyor", increasing)

	-- 1. kat bedava olmalı, satılık listede yer almamalı
	ok("1. kat satılık değil", floors[1] ~= true)

	-- Her üst kat için bir tanım olmalı, yoksa arada erişilemez kat kalır
	for floor = 2, Config.MaxFloors do
		ok("kat " .. floor .. " tanımlı", Config.GetFloorUnlock(floor) ~= nil)
	end

	ok("olmayan kat nil", Config.GetFloorUnlock(Config.MaxFloors + 1) == nil)
end)

case("Kat: pahalı olmalı", function()
	--[[
		Kullanıcının istediği buydu ve ucuzlarsa oyunun geç kısmı anlamını
		kaybediyor. Ölçü: her katın fiyatı, onu açan rebirth'e kadar
		harcanan toplamdan büyük olmalı — yani rebirth'ü biriktirmiş
		oyuncu katı anında alamamalı.
	]]
	for _, def in Config.FloorUnlocks do
		local spentOnRebirths = 0
		for level = 0, def.rebirths - 1 do
			spentOnRebirths += Config.GetRebirthCost(level)
		end

		ok(string.format("kat %d fiyatı rebirth masrafından büyük", def.floor),
			def.cost > spentOnRebirths,
			string.format("%s vs %s",
				Config.FormatCash(def.cost), Config.FormatCash(spentOnRebirths)))
	end
end)

case("Kat: sıra atlanamıyor", function()
	local first = Config.GetNextFloor(0)
	ok("hiç kat yokken 2. kat sıradaki", first ~= nil and first.floor == 2,
		tostring(first and first.floor))

	local second = Config.GetNextFloor(1)
	ok("2. kat alınınca 3. kat sıradaki", second ~= nil and second.floor == 3,
		tostring(second and second.floor))

	ok("hepsi alınınca sıradaki yok", Config.GetNextFloor(Config.MaxFloors - 1) == nil)
end)

case("Kat: açık kat sayısı satın almaya bağlı", function()
	eq("hiç alınmamışken tek kat", Config.GetUnlockedFloors(0), 1)
	eq("bir alınmışken iki kat", Config.GetUnlockedFloors(1), 2)
	eq("tavan aşılmıyor", Config.GetUnlockedFloors(99), Config.MaxFloors)
end)

case("Kat: profil alanı var ve sınırlı", function(ctx)
	ok("floorsBought sayı", typeof(ctx.profile.floorsBought) == "number",
		typeof(ctx.profile.floorsBought))
	ok("aralıkta", ctx.profile.floorsBought >= 0
		and ctx.profile.floorsBought <= Config.MaxFloors - 1,
		tostring(ctx.profile.floorsBought))
end)

case("Kat: rebirth yetmezse satılmıyor", function(ctx)
	local def = Config.GetFloorUnlock(2)
	ok("2. kat tanımlı", def ~= nil)
	if not def then return end

	ctx.profile.floorsBought = 0
	ctx.profile.rebirths = 0
	PlotService.SetUnlockedFloors(ctx.plot, 1)
	setCash(ctx.player, def.cost * 10)

	ok("rebirth koşulu var", def.rebirths > 0, tostring(def.rebirths))
	ok("satın alma reddedildi", not FloorService.TryBuy(ctx.player))
	eq("kat alınmadı", ctx.profile.floorsBought, 0)
	eq("para harcanmadı", EconomyService.GetCash(ctx.player), def.cost * 10)
end)

case("Kat: parası yetmezse satılmıyor", function(ctx)
	local def = Config.GetFloorUnlock(2)
	if not def then return end

	ctx.profile.floorsBought = 0
	ctx.profile.rebirths = def.rebirths
	PlotService.SetUnlockedFloors(ctx.plot, 1)
	setCash(ctx.player, def.cost - 1)

	ok("satın alma reddedildi", not FloorService.TryBuy(ctx.player))
	eq("kat alınmadı", ctx.profile.floorsBought, 0)
	eq("para duruyor", EconomyService.GetCash(ctx.player), def.cost - 1)
end)

case("Kat: koşullar sağlanınca açılıyor", function(ctx)
	local def = Config.GetFloorUnlock(2)
	if not def then return end

	ctx.profile.floorsBought = 0
	ctx.profile.rebirths = def.rebirths
	PlotService.SetUnlockedFloors(ctx.plot, 1)

	--[[
		Fiyatın üstüne biraz koyuyoruz. Tam fiyat verilseydi bakiye sıfıra
		inerdi ve EconomyService'in kilitlenme koruması devreye girip en
		ucuz karakterin parasını geri yatırırdı (TryBuy içindeki Save
		yield ediyor, döngüye sıra geliyor). Koruma doğru çalışıyor; test
		onun üstüne oturmamalı.
	]]
	local spare = Config.GetCheapestUnitPrice() * 10
	setCash(ctx.player, def.cost + spare)

	eq("başlangıçta tek kat", ctx.plot:GetAttribute("UnlockedFloors"), 1)
	local beforePodiums = #PlotService.GetUnlockedPodiums(ctx.plot)

	ok("satın alma başarılı", FloorService.TryBuy(ctx.player))
	eq("kat sayacı arttı", ctx.profile.floorsBought, 1)
	eq("fiyat kadar para gitti", EconomyService.GetCash(ctx.player), spare)
	eq("kat açıldı", ctx.plot:GetAttribute("UnlockedFloors"), 2)

	ok("kaide sayısı arttı", #PlotService.GetUnlockedPodiums(ctx.plot) > beforePodiums,
		string.format("%d -> %d", beforePodiums, #PlotService.GetUnlockedPodiums(ctx.plot)))
end)

case("Kat: hepsi alınınca duruyor", function(ctx)
	ctx.profile.floorsBought = Config.MaxFloors - 1
	ctx.profile.rebirths = 99
	setCash(ctx.player, 1e15)

	ok("fazlası satılmıyor", not FloorService.TryBuy(ctx.player))
	eq("sayaç tavanda kaldı", ctx.profile.floorsBought, Config.MaxFloors - 1)
end)

case("Kat: satın alınan kat rebirth'ten sağ çıkıyor", function(ctx)
	--[[
		Kata parasını ödedi. Rebirth kaideleri ve nakdi sıfırlıyor ama
		katı geri almamalı, yoksa oyuncu aynı katı iki kez satın alırdı.
	]]
	ctx.profile.floorsBought = 1
	ctx.profile.rebirths = 0
	PlotService.SetUnlockedFloors(ctx.plot, Config.GetUnlockedFloors(1))
	clearPlot(ctx.plot)

	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)
	PlotService.PlaceUnit(podiums[1], "TheSkeld", nil)
	setCash(ctx.player, Config.GetRebirthCost(0))

	ok("rebirth başarılı", RebirthService.TryRebirth(ctx.player))
	eq("kat sayacı korundu", ctx.profile.floorsBought, 1)
	eq("kat hâlâ açık", ctx.plot:GetAttribute("UnlockedFloors"), 2)
end)

case("Kat: üslerde satın alma pedi ve tabelası yok", function()
	--[[
		Ped kaldırıldı: her üste "FLOOR 3 · Needs 2 rebirth" yazan bir tabela
		ve ışık sütunu koyuyordu, rakiplerin üslerinde de görünüyordu. Kat
		artık yalnızca yükseltme kulübesinden (FloorBuy) alınıyor. Biri pedi
		geri eklerse bu test yakalar.
	]]
	for _, plot in PlotService.GetAllPlots() do
		ok(plot.Name .. " pedsiz", plot:FindFirstChild("FloorPad") == nil)
		local label = plot:FindFirstChild("FloorLabel", true)
		ok(plot.Name .. " kat tabelası yok", label == nil)
	end
end)
case("Kat: eski kayıt katlarını kaybetmiyor", function()
	--[[
		Katlar eskiden doğrudan rebirth ödülüydü. floorsBought alanı
		olmayan bir kayıt 0 ile gelir ve rebirth atmış oyuncu katlarını
		kaybederdi — üstelik üstünde karakteri varken. Göç eski kuralın
		verdiği kadarını hediye ediyor.
	]]
	local migrated = Config.GetUnlockedFloors(math.clamp(2, 0, Config.MaxFloors - 1))
	eq("2 rebirth'lü eski oyuncu üç kata sahip", migrated, 3)

	local fresh = Config.GetUnlockedFloors(math.clamp(0, 0, Config.MaxFloors - 1))
	eq("yeni oyuncu tek kat", fresh, 1)
end)


case("Yükseltme: tavan kat sayısıyla ikiye katlanıyor", function()
	for _, def in Config.Upgrades do
		local f1 = Config.GetUpgradeMaxLevel(def, 1)
		local f2 = Config.GetUpgradeMaxLevel(def, 2)
		local f3 = Config.GetUpgradeMaxLevel(def, 3)

		eq(def.name .. " 1. kat tabanı", f1, def.baseMaxLevel)
		eq(def.name .. " 2. kat iki katı", f2, f1 * 2)
		eq(def.name .. " 3. kat dört katı", f3, f1 * 4)
		eq(def.name .. " tavan en üst kat", Config.GetUpgradeCeiling(def), f3)
	end
end)

case("Yükseltme: kat tavanı satın almayı durduruyor", function(ctx)
	local id = "ConveyorSpeed"
	local def = Config.GetUpgrade(id)

	-- 1. katta sadece taban kadar alınabilmeli
	ctx.profile.floorsBought = 0
	ctx.profile.upgrades[id] = def.baseMaxLevel
	setCash(ctx.player, 1e15)

	eq("1. kat tavanında reddedildi", UpgradeService.TryUpgrade(ctx.player, id), false)
	eq("seviye değişmedi", UpgradeService.GetLevel(ctx.player, id), def.baseMaxLevel)

	-- Kat alınca devamı gelmeli
	ctx.profile.floorsBought = 1
	eq("üst kat tavanı açtı", UpgradeService.TryUpgrade(ctx.player, id), true)
	eq("seviye arttı", UpgradeService.GetLevel(ctx.player, id), def.baseMaxLevel + 1)
end)

case("Yükseltme: rebirth sıfırlıyor", function(ctx)
	--[[
		Kalıcı olsalardı rebirth'ten sonra harcanacak yer kalmazdı.
		Satın alınan KAT ise sıfırlanmamalı; parayla alındı.
	]]
	clearPlot(ctx.plot)
	ctx.profile.rebirths = 0
	ctx.profile.floorsBought = 1
	ctx.profile.upgrades = { ConveyorSpeed = 3, LockPower = 2 }
	PlotService.SetUnlockedFloors(ctx.plot, Config.GetUnlockedFloors(1))

	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)
	PlotService.PlaceUnit(podiums[1], "TheSkeld", nil)
	setCash(ctx.player, Config.GetRebirthCost(0))

	ok("rebirth başarılı", RebirthService.TryRebirth(ctx.player))

	eq("ConveyorSpeed sıfırlandı", UpgradeService.GetLevel(ctx.player, "ConveyorSpeed"), 0)
	eq("LockPower sıfırlandı", UpgradeService.GetLevel(ctx.player, "LockPower"), 0)
	eq("satın alınan kat korundu", ctx.profile.floorsBought, 1)
end)

case("Yükseltme: seviye başına etki yarıya indi ama tavan aynı kaldı", function()
	--[[
		Seviye sayısı ikiye katlandı, seviye başına etki yarıya indi.
		Net sonuç: tavandaki güç eskisiyle aynı, yol iki kat uzun.
		Bu test gücün kazara artmasını engelliyor.
	]]
	local def = Config.GetUpgrade("ConveyorSpeed")
	local ceiling = Config.GetUpgradeCeiling(def)

	local top = Config.GetConveyorInterval(ceiling)
	ok("konveyör tabanı makul", top >= 2 and top <= Config.ConveyorInterval,
		string.format("%.2f", top))

	local carry = Config.GetCarryWalkSpeed(Config.GetUpgradeCeiling(Config.GetUpgrade("CarrySpeed")))
	ok("taşıma hızı normali geçmiyor", carry < Config.NormalWalkSpeed,
		string.format("%.2f", carry))

	local duration, cooldown = Config.GetLockValues(Config.GetUpgradeCeiling(Config.GetUpgrade("LockPower")))
	ok("kilit süresi bekleme süresini aşmıyor", duration < cooldown + 60,
		string.format("%.1f / %.1f", duration, cooldown))
end)

case("Koşma: ayarlar makul", function()
	ok("koşu normalden hızlı", Config.SprintWalkSpeed > Config.NormalWalkSpeed,
		tostring(Config.SprintWalkSpeed))
	ok("koşu abartılı değil", Config.SprintWalkSpeed <= Config.NormalWalkSpeed * 2,
		tostring(Config.SprintWalkSpeed))

	-- Taşıma hızı koşunun çok altında kalmalı: çalmanın riski bu
	local fastestCarry = Config.GetCarryWalkSpeed(
		Config.GetUpgradeCeiling(Config.GetUpgrade("CarrySpeed")))
	ok("en hızlı taşıma bile koşudan yavaş", fastestCarry < Config.SprintWalkSpeed,
		string.format("%.1f vs %d", fastestCarry, Config.SprintWalkSpeed))
end)

case("Koşma: taşırken hız artmıyor", function(ctx)
	--[[
		Koşmaya taşırken izin vermek çalmanın tek riskini siler. Sunucu
		bayrağı kabul ediyor ama hıza yansıtmıyor.
	]]
	local character = ctx.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	ok("karakter var", humanoid ~= nil)
	if not humanoid then return end

	StealService.SetSprinting(ctx.player, true)
	local sprintSpeed = humanoid.WalkSpeed
	eq("koşarken koşu hızı", sprintSpeed, Config.SprintWalkSpeed)

	StealService.SetSprinting(ctx.player, false)
	eq("bırakınca normal hız", humanoid.WalkSpeed, Config.NormalWalkSpeed)
end)

-- ─── U. Petler, ödüller, ekipman ────────────────────────────────────────────

case("Pet: anahtar pet/mutasyon/boyut çözülüyor, bozuk anahtar reddediliyor", function()
	local def, mutation, size = Config.ParsePetKey("MiniCrew:Golden:Huge")
	ok("pet", def ~= nil and def.id == "MiniCrew")
	ok("mutasyon", mutation ~= nil and mutation.id == "Golden")
	ok("boyut", size ~= nil and size.id == "Huge")
	ok("yalnızca boyut", (Config.ParsePetKey("MiniCrew:Titan")) ~= nil)
	ok("bilinmeyen parça", (Config.ParsePetKey("MiniCrew:Nope")) == nil)
	ok("iki boyut", (Config.ParsePetKey("MiniCrew:Big:Huge")) == nil)
	eq("anahtar kurma", Config.PetKey("MiniCrew", "Golden", "Huge"), "MiniCrew:Golden:Huge")
	local plain = Config.GetPetKeyBonus("MiniCrew")
	local titan = Config.GetPetKeyBonus("MiniCrew:Titan")
	near("Titan çarpanı", titan / plain, 10, 0.001)
end)

case("Pet: birleştirme boyutu büyütüyor, türü ve mutasyonu koruyor", function(ctx)
	--[[
		Makine yanında olma şartı var; test karakteri makineye taşımak
		yerine mesafe kontrolünü geçici olarak açıyor.
	]]
	local original = PetService.NearFuseMachine
	PetService.NearFuseMachine = function() return true end

	ctx.profile.pets = { ["VoidShard:Cosmic"] = 3 }
	ctx.profile.equippedPets = { "VoidShard:Cosmic" }
	local key = PetService.TryFuse(ctx.player, "VoidShard:Cosmic")
	eq("Secret da birleşiyor, Big oluyor", key, "VoidShard:Cosmic:Big")
	eq("kopyalar yandı", ctx.profile.pets["VoidShard:Cosmic"], nil)
	ok("takılı liste temizlendi", table.find(ctx.profile.equippedPets, "VoidShard:Cosmic") == nil)

	ctx.profile.pets = { ["MiniCrew:Titan"] = 3 }
	eq("Titan'ın üstü yok", PetService.TryFuse(ctx.player, "MiniCrew:Titan"), nil)
	ctx.profile.pets = { MiniCrew = 2 }
	eq("iki kopya yetmiyor", PetService.TryFuse(ctx.player, "MiniCrew"), nil)

	PetService.NearFuseMachine = original
	-- Test oyuncusu kendi üssünde duruyor, lobideki makineden uzakta
	ctx.profile.pets = { MiniCrew = 3 }
	eq("uzaktan birleşmiyor", PetService.TryFuse(ctx.player, "MiniCrew"), nil)
end)

case("Pet: her yumurtanın kendi takımı var, güç yumurtayla artıyor", function()
	-- yumurta -> kademe -> petler (her kademede 1-3 pet)
	local byEgg: { [string]: { [string]: { Config.PetDef } } } = {}
	local ids: { [string]: boolean } = {}
	for _, def in Config.Pets do
		ok(def.id .. " yumurtası var", Config.GetEgg(def.egg) ~= nil, def.egg)
		ok(def.id .. " kimliği tek", ids[def.id] == nil)
		ids[def.id] = true
		byEgg[def.egg] = byEgg[def.egg] or {}
		byEgg[def.egg][def.rarity] = byEgg[def.egg][def.rarity] or {}
		table.insert(byEgg[def.egg][def.rarity], def)
	end
	eq("pet sayısı (yumurta başına kademe başına bir)", #Config.Pets, 25)

	local function minIncome(list: { Config.PetDef }): number
		local m = math.huge
		for _, d in list do
			m = math.min(m, d.incomeBonus)
		end
		return m
	end
	local function maxIncome(list: { Config.PetDef }): number
		local m = -math.huge
		for _, d in list do
			m = math.max(m, d.incomeBonus)
		end
		return m
	end

	for _, egg in Config.Eggs do
		local mine = byEgg[egg.id] or {}
		for rarity in egg.weights do
			ok(egg.id .. " " .. rarity .. " peti var", mine[rarity] ~= nil and #mine[rarity] > 0)
		end
		-- Kademe arttıkça güç artıyor: üst kademenin en zayıfı alt kademenin en güçlüsünden iyi
		local order: { string } = {}
		for rarity in mine do
			table.insert(order, rarity)
		end
		table.sort(order, function(a, b)
			return Config.Rarities[a].order < Config.Rarities[b].order
		end)
		for i = 2, #order do
			ok(egg.id .. " sıralı güç " .. order[i], minIncome(mine[order[i]]) > maxIncome(mine[order[i - 1]]))
		end
		-- Aynı kademedeki petler farklı stat veriyor
		for rarity, list in mine do
			for a = 1, #list do
				for b = a + 1, #list do
					ok(egg.id .. " " .. rarity .. " farklı stat " .. list[a].id .. "/" .. list[b].id,
						list[a].incomeBonus ~= list[b].incomeBonus or list[a].speedBonus ~= list[b].speedBonus)
				end
			end
		end
		-- Petlerin şansları toplamı %100 (kademe şansı kademedeki pet sayısına bölünüyor)
		local sum = 0
		for _, def in Config.GetEggPets(egg.id) do
			sum += Config.GetPetChance(egg.id, def.id)
		end
		near(egg.id .. " şans toplamı", sum, 100, 0.01)
		-- Çekiliş yalnızca o yumurtanın petlerini veriyor
		local rng = Random.new(7)
		local foreign = 0
		for _ = 1, 300 do
			local def = Config.RollPet(rng, egg.id)
			if not def or def.egg ~= egg.id then
				foreign += 1
			end
		end
		eq(egg.id .. " başka yumurtanın peti çıkmıyor", foreign, 0)
	end
	-- Kademeler: ucuz yumurta Legendary'e kadar, Skeld Mythic'e, son ikisi Secret
	local supply, skeld, polus, void = byEgg.SupplyEgg, byEgg.SkeldEgg, byEgg.PolusEgg, byEgg.VoidEgg
	ok("Supply'da Common..Epic + Legendary", supply.Common ~= nil and supply.Epic ~= nil and supply.Legendary ~= nil and supply.Mythic == nil)
	ok("Skeld'de Legendary + Mythic", skeld.Legendary ~= nil and skeld.Mythic ~= nil and skeld.Secret == nil)
	ok("Supply Legendary nadir (<%1)", (Config.Eggs[1].weights.Legendary or 0) < 1)
	ok("Skeld Mythic nadir (<%1)", (Config.Eggs[2].weights.Mythic or 0) < 1)
	ok("Polus ve Void'de Secret", polus.Secret ~= nil and void.Secret ~= nil)
	-- Pahalı yumurtanın en zayıf Common'ı ucuzunkinin en güçlüsünden iyi
	ok("Void Common > Supply Common", minIncome(void.Common) > maxIncome(supply.Common))
	ok("Polus Common > Skeld Common", minIncome(polus.Common) > maxIncome(skeld.Common))
	ok("Supply Epic hâlâ Void Common'dan iyi", minIncome(supply.Epic) > maxIncome(void.Common))
end)

case("Pet: otomatik silme envantere koymuyor ama indekse işliyor", function(ctx)
	ctx.profile.pets = {}
	ctx.profile.equippedPets = {}
	ctx.profile.petsFound = {}
	SettingsService._Reset(ctx.player)
	SettingsService.Apply(ctx.player, { autoDelete = { Common = true, Uncommon = true, Rare = true, Epic = true, Bogus = true } }, 5000)
	eq("nitelik kademe sırasıyla", ctx.player:GetAttribute("SettingAutoDelete"), "Common,Uncommon,Rare,Epic")
	ok("tanınmayan kademe girmedi", ctx.profile.settings.autoDelete.Bogus == nil)

	setCash(ctx.player, 10000000)
	local keys = PetService.TryHatch(ctx.player, "SupplyEgg", 1, false)
	ok("açıldı", keys ~= nil and #keys == 1)
	if keys then
		local def, mutation = Config.ParsePetKey(keys[1])
		--[[
			Çekiliş rastgele: Supply Egg'e Legendary eklenince test ara sıra
			düşüyordu (Legendary silme listesinde değil, envantere girmesi
			DOĞRU). Beklenti petin kademesine göre.
		]]
		local deleted = def ~= nil and mutation == nil and ctx.profile.settings.autoDelete[def.rarity] == true
		if deleted then
			eq("silinen envantere girmedi", ctx.profile.pets[keys[1]], nil)
		else
			-- Mutasyonlu ya da silme listesinde olmayan kademe: envantere giriyor
			eq("silinmeyen envanterde", ctx.profile.pets[keys[1]], 1)
		end
		ok("indekse işlendi", def ~= nil and ctx.profile.petsFound[def.id] == true)
	end

	SettingsService._Reset(ctx.player)
	SettingsService.Apply(ctx.player, { autoDelete = {} }, 6000)
	eq("kapatınca liste boş", ctx.player:GetAttribute("SettingAutoDelete"), "")
	SettingsService._Reset(ctx.player)
	PetService._ResetBusy(ctx.player)
end)

case("Pet: aynı petten kopya sayısı kadar takılıyor, en iyiler seçiliyor", function(ctx)
	ctx.profile.pets = { MiniCrew = 3, Bolt = 1 }
	ctx.profile.equippedPets = {}
	ok("1. kopya", PetService.TryEquip(ctx.player, "MiniCrew", true))
	ok("2. kopya", PetService.TryEquip(ctx.player, "MiniCrew", true))
	ok("3. kopya", PetService.TryEquip(ctx.player, "MiniCrew", true))
	eq("üç kopya takılı", #ctx.profile.equippedPets, 3)
	ok("slot dolu, dördüncü yok", not PetService.TryEquip(ctx.player, "Bolt", true))
	local income = Config.GetPetBonus(ctx.profile.equippedPets)
	near("bonus üç katı", income, Config.GetPetKeyBonus("MiniCrew") * 3, 0.0001)

	ok("bir kopya çıkıyor", PetService.TryEquip(ctx.player, "MiniCrew", false))
	eq("iki kaldı", #ctx.profile.equippedPets, 2)
	ctx.profile.pets = { MiniCrew = 2, Bolt = 1 }
	ok("elde olandan fazla takılmıyor", not PetService.TryEquip(ctx.player, "MiniCrew", true))

	-- En iyiler: Skeld Common (Mini Crew) Supply Common'dan (Bolt) güçlü
	ctx.profile.pets = { MiniCrew = 1, Bolt = 5 }
	PetService.EquipBest(ctx.player)
	eq("en iyi önce", ctx.profile.equippedPets[1], "MiniCrew")
	eq("sonra kopyalar", ctx.profile.equippedPets[2], "Bolt")
	eq("üç slot", #ctx.profile.equippedPets, 3)
	PetService.UnequipAll(ctx.player)
	eq("hepsi çıktı", #ctx.profile.equippedPets, 0)

	-- Birleştirme kopyaları azaltınca fazla takılı düşüyor
	local original = PetService.NearFuseMachine
	PetService.NearFuseMachine = function() return true end
	ctx.profile.pets = { MiniCrew = 4 }
	ctx.profile.equippedPets = { "MiniCrew", "MiniCrew", "MiniCrew" }
	PetService.TryFuse(ctx.player, "MiniCrew")
	PetService.NearFuseMachine = original
	eq("bir düz kopya kaldı", ctx.profile.pets.MiniCrew, 1)
	local plain = 0
	for _, k in ctx.profile.equippedPets do
		if k == "MiniCrew" then
			plain += 1
		end
	end
	eq("takılı düz kopya da bire indi", plain, 1)
	ctx.profile.equippedPets = {}
	PetService.Apply(ctx.player)
end)

case("Pet: sahadaki model istemcinin yürütmesi için işaretli", function(ctx)
	ctx.profile.pets = { Bolt = 1, VentRat = 1 }
	ctx.profile.equippedPets = { "Bolt", "VentRat" }
	PetService.Apply(ctx.player)
	local found = 0
	local folder = workspace:FindFirstChild("Pets")
	for _, model in (if folder then folder:GetChildren() else {}) do
		if model:IsA("Model") and model:GetAttribute("OwnerId") == ctx.player.UserId then
			found += 1
			ok(model.Name .. " sırası", typeof(model:GetAttribute("Slot")) == "number")
			eq(model.Name .. " toplam", model:GetAttribute("SlotCount"), 2)
			eq(model.Name .. " kalıcı akış", model.ModelStreamingMode, Enum.ModelStreamingMode.Persistent)
		end
	end
	eq("iki pet sahada", found, 2)
	ctx.profile.equippedPets = {}
	PetService.Apply(ctx.player)
end)

case("Harita: Security ve Admin odaları, kameralar", function()
	local rooms = workspace.Decor:FindFirstChild("UnderRooms")
	ok("yeraltı odaları", rooms ~= nil and rooms:FindFirstChild("Security") ~= nil and rooms:FindFirstChild("Admin") ~= nil)
	local security = workspace.Decor:FindFirstChild("SecurityRoom")
	ok("kamera konsolu promptu", security ~= nil and security:FindFirstChild("SecurityPrompt", true) ~= nil)
	ok("admin promptu", workspace.Decor.AdminTable:FindFirstChild("AdminPrompt", true) ~= nil)
	local cams, names = 0, {}
	for _, d in workspace.Decor:GetDescendants() do
		if d:IsA("BasePart") and typeof(d:GetAttribute("CamName")) == "string" then
			cams += 1
			ok("kamera adı tek: " .. d:GetAttribute("CamName"), names[d:GetAttribute("CamName")] == nil)
			names[d:GetAttribute("CamName")] = true
		end
	end
	ok("en az 7 kamera", cams >= 7, tostring(cams))
	-- Üslerin üstünde oda tabelası yok
	ok("oda tabelaları kalktı", workspace.Decor:FindFirstChild("RoomSign", true) == nil)
end)

case("Pet: açılış bitmeden ikinci yumurta açılmıyor", function(ctx)
	ctx.profile.pets = {}
	ctx.profile.equippedPets = {}
	setCash(ctx.player, 10000000)
	local first = PetService.TryHatch(ctx.player, "SupplyEgg", 1, false)
	ok("ilki açıldı", first ~= nil and #first == 1)
	local second = PetService.TryHatch(ctx.player, "SupplyEgg", 1, false)
	eq("ikincisi bekletildi", second, nil)
end)

case("Ödül: günlük seri günde bir kez, dün alındıysa devam ediyor", function(ctx)
	local today = Config.DayIndex(os.time())
	ctx.profile.dailyStreak = 3
	ctx.profile.lastDailyDay = today - 1
	setCash(ctx.player, 0)
	ok("toplandı", RewardService.ClaimDaily(ctx.player))
	eq("seri arttı", ctx.profile.dailyStreak, 4)
	ok("aynı gün ikinci kez yok", not RewardService.ClaimDaily(ctx.player))

	ctx.profile.lastDailyDay = today - 3
	ok("kaçırılan günden sonra toplandı", RewardService.ClaimDaily(ctx.player))
	eq("seri başa döndü", ctx.profile.dailyStreak, 1)
end)

case("Ödül: oynama hediyesi süresi dolmadan alınmıyor, bir kez alınıyor", function(ctx)
	ctx.profile.playtimeDay = Config.DayIndex(os.time())
	ctx.profile.playtimeClaimed = {}
	ctx.profile.playtimeSeconds = 60
	ok("5 dk dolmadan yok", not RewardService.ClaimPlaytime(ctx.player, 1))
	ctx.profile.playtimeSeconds = 5 * 60
	ok("5 dk dolunca var", RewardService.ClaimPlaytime(ctx.player, 1))
	ok("ikinci kez yok", not RewardService.ClaimPlaytime(ctx.player, 1))
end)

case("Ödül: indeks satırı tamamlanmadan bonus yok, tamamlanınca kalıcı", function(ctx)
	ctx.profile.indexClaimed = {}
	ctx.profile.discovered = {}
	ok("eksikken yok", not RewardService.ClaimIndex(ctx.player, "Common"))
	for _, unit in Config.Units do
		if unit.rarity == "Common" then
			ctx.profile.discovered[unit.id] = true
		end
	end
	ok("tamamlanınca var", RewardService.ClaimIndex(ctx.player, "Common"))
	near("bonus niteliği", ctx.player:GetAttribute("IndexBonus") or 0, Config.IndexRewards.Common, 0.0001)
	ok("ikinci kez yok", not RewardService.ClaimIndex(ctx.player, "Common"))
	ctx.profile.indexClaimed = {}
	ctx.player:SetAttribute("IndexBonus", 0)
end)

case("Ekipman: parası yetmeden alınmıyor, alınca kalıcı ve çantaya geliyor", function(ctx)
	ctx.profile.gear = {}
	setCash(ctx.player, 0)
	ok("parasız yok", not GearService.TryBuy(ctx.player, "SlapGlove"))
	setCash(ctx.player, 1000000)
	ok("alındı", GearService.TryBuy(ctx.player, "SlapGlove"))
	ok("profilde", ctx.profile.gear.SlapGlove == true)
	ok("ikinci kez yok", not GearService.TryBuy(ctx.player, "SlapGlove"))
	local backpack = ctx.player:FindFirstChildOfClass("Backpack")
	local found = false
	for _, container in { backpack, ctx.player.Character } do
		if container then
			for _, item in container:GetChildren() do
				if item:IsA("Tool") and item:GetAttribute("GearId") == "SlapGlove" then
					found = true
				end
			end
		end
	end
	ok("çantada", found)
	-- Temizlik: test aletini bırakma
	for _, container in { backpack, ctx.player.Character } do
		if container then
			for _, item in container:GetChildren() do
				if item:IsA("Tool") and item:GetAttribute("GearId") == "SlapGlove" then
					item:Destroy()
				end
			end
		end
	end
end)

case("Kod: bir kez kullanılıyor, büyük/küçük harf önemsiz, uydurma reddediliyor", function(ctx)
	local savedCodes = ctx.profile.codes
	ctx.profile.codes = {}
	RewardService._ResetCodeCooldown(ctx.player)
	local okBad = RewardService.RedeemCode(ctx.player, "NOT-A-REAL-CODE", 1000)
	ok("uydurma kod reddedildi", not okBad)
	local cash0 = ctx.profile.cash
	local ok1 = RewardService.RedeemCode(ctx.player, "  crewmate ", 1010)
	ok("küçük harf + boşlukla kabul", ok1)
	ok("para verildi", ctx.profile.cash > cash0)
	ok("profile işlendi", ctx.profile.codes.CREWMATE == true)
	local ok2 = RewardService.RedeemCode(ctx.player, "CREWMATE", 1020)
	ok("ikinci kez yok", not ok2)
	RewardService._ResetCodeCooldown(ctx.player)
	RewardService.RedeemCode(ctx.player, "SUS", 1030)
	local okFast = RewardService.RedeemCode(ctx.player, "RELEASE", 1030.5)
	ok("art arda deneme bekletiliyor", not okFast)
	for _, def in Config.Codes do
		ok(def.code .. " büyük harf", def.code == string.upper(def.code))
		ok(def.code .. " ödülü var", #def.rewards > 0)
	end
	ctx.profile.codes = savedCodes
	RewardService._ResetCodeCooldown(ctx.player)
end)

case("Ekipman: zıplama aleti yok, hız bobini koşudan hızlı", function(ctx)
	local kinds = { slap = true, speed = true, stun = true, cloak = true, blast = true }
	for _, def in Config.Gear do
		ok(def.id .. " türü tanınıyor", kinds[def.kind] == true, def.kind)
		ok(def.id .. " zıplama vermiyor", (def :: any).jumpHeight == nil)
		if def.kind ~= "speed" then
			ok(def.id .. " bekleme süresi var", (def.cooldown or 0) > 0)
		end
	end
	ok("Gravity Coil satılmıyor", Config.GetGear("GravityCoil") == nil)
	local coil = Config.GetGear("SpeedCoil") :: Config.GearDef
	ok("bobin yürüyüşü koşudan hızlı", (coil.walkSpeed or 0) > Config.SprintWalkSpeed)
	ok("bobinle koşu daha da hızlı", (coil.sprintSpeed or 0) > (coil.walkSpeed or 0))

	-- Hız: bobin eldeyken yürüme / Shift
	local humanoid = ctx.player.Character and ctx.player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		ctx.player:SetAttribute("GearSpeed", coil.walkSpeed)
		ctx.player:SetAttribute("GearSprint", coil.sprintSpeed)
		StealService.SetSprinting(ctx.player, false)
		eq("bobinle yürüme", humanoid.WalkSpeed, coil.walkSpeed)
		StealService.SetSprinting(ctx.player, true)
		eq("bobinle koşu", humanoid.WalkSpeed, coil.sprintSpeed)
		ctx.player:SetAttribute("GearSpeed", nil)
		ctx.player:SetAttribute("GearSprint", nil)
		StealService.RefreshSpeed(ctx.player)
		eq("bobinsiz koşu", humanoid.WalkSpeed, Config.SprintWalkSpeed)
		StealService.SetSprinting(ctx.player, false)
		eq("normal", humanoid.WalkSpeed, Config.NormalWalkSpeed)
	end

	-- Kaldırılan alet: parası bir kez iade
	local profile = DataService._Sanitize({ cash = 1000, gear = { GravityCoil = true, SlapGlove = true } })
	eq("iade edildi", profile.cash, 1000 + Config.RetiredGear.GravityCoil)
	ok("kayıttan düştü", profile.gear.GravityCoil == nil)
	ok("diğer alet kaldı", profile.gear.SlapGlove == true)
end)

case("Ekipman: denge - uzaktan ve alan aletleri sınırlı, sersemleme kilidi yok", function(ctx)
	local stun = Config.GetGear("StunGun") :: Config.GearDef
	local blast = Config.GetGear("EmergencyButton") :: Config.GearDef
	local slap = Config.GetGear("SlapGlove") :: Config.GearDef
	ok("stun menzili 30'u geçmiyor", (stun.range or 0) <= 30)
	ok("stun beklemesi en az 20", (stun.cooldown or 0) >= 20)
	ok("stun donması bekleme süresinden çok kısa", (stun.stun or 0) * 4 <= (stun.cooldown or 0))
	ok("buton beklemesi en az 45", (blast.cooldown or 0) >= 45)
	ok("tokat beklemesi en az 4", (slap.cooldown or 0) >= 4)
	ok("koruma donmadan uzun", Config.GearHitImmunity > (stun.stun or 0))

	-- Vurulan oyuncu kısa süre korunuyor
	GearService._MarkHit(ctx.player, os.clock())
	ok("vurulunca korunuyor", GearService.IsImmune(ctx.player))
	ok("koruma bitiyor", not GearService.IsImmune(ctx.player, os.clock() + Config.GearHitImmunity + 0.1))
	GearService._MarkHit(ctx.player, -math.huge)
end)

case("Ekipman: bekleme süresi sunucuda, görünmezlik açılıp kapanıyor", function(ctx)
	GearService._ResetCooldowns(ctx.player)
	ok("tokat atıldı", GearService.Use(ctx.player, "SlapGlove"))
	ok("hemen ikinci tokat yok", not GearService.Use(ctx.player, "SlapGlove"))
	ok("bobin kullanılmıyor", not GearService.Use(ctx.player, "SpeedCoil"))
	ok("tanınmayan alet yok", not GearService.Use(ctx.player, "GravityCoil"))

	local character = ctx.player.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local before = head.Transparency
		ok("serum içildi", GearService.Use(ctx.player, "GhostSerum"))
		eq("görünmez niteliği", ctx.player:GetAttribute("Cloaked"), true)
		eq("kafa görünmez", head.Transparency, 1)
		GearService.EndCloak(ctx.player)
		eq("kafa geri geldi", head.Transparency, before)
		eq("nitelik kalktı", ctx.player:GetAttribute("Cloaked"), nil)
	end
	GearService._ResetCooldowns(ctx.player)
end)

case("Görev: asteroit ödülü sunucuda doğrulanıyor", function(ctx)
	--[[
		Sonucu istemci söylüyor; bu test sunucunun sahte isteği nerelerde
		durdurduğunu sabitliyor: başlamamış, çok hızlı, çok eski, bekleme
		süresi dolmamış, konsoldan uzak.
	]]
	local rules = Config.AsteroidTask
	local original = MinigameService.NearConsole
	MinigameService.NearConsole = function()
		return true
	end
	MinigameService._Reset(ctx.player)
	setCash(ctx.player, 0)
	local T = 10000

	eq("başlamadan ödül yok", MinigameService.TryComplete(ctx.player, T), nil)
	MinigameService.Begin(ctx.player, T)
	eq("çok hızlı reddedildi", MinigameService.TryComplete(ctx.player, T + rules.minSeconds - 1), nil)
	eq("çok eski reddedildi", MinigameService.TryComplete(ctx.player, T + rules.maxSeconds + 1), nil)

	local reward = MinigameService.TryComplete(ctx.player, T + rules.minSeconds + 1)
	ok("geçerli bitiş ödül veriyor", reward ~= nil and reward >= rules.minReward, tostring(reward))
	eq("nakit eklendi", EconomyService.GetCash(ctx.player), reward or -1)
	eq("aynı oyun ikinci kez ödemiyor", MinigameService.TryComplete(ctx.player, T + rules.minSeconds + 2), nil)

	-- Bekleme süresi içinde yeni oyun ödemiyor, dolunca ödüyor
	local t2 = T + rules.minSeconds + 5
	MinigameService.Begin(ctx.player, t2)
	eq("bekleme süresinde yok", MinigameService.TryComplete(ctx.player, t2 + rules.minSeconds + 1), nil)
	local t3 = T + rules.minSeconds + 1 + rules.cooldown + 1
	MinigameService.Begin(ctx.player, t3 - rules.minSeconds - 1)
	ok("bekleme dolunca var", MinigameService.TryComplete(ctx.player, t3) ~= nil)

	-- Konsoldan uzak: test oyuncusu kendi üssünde, lobideki konsoldan uzakta
	MinigameService.NearConsole = original
	MinigameService._Reset(ctx.player)
	MinigameService.Begin(ctx.player, T)
	eq("uzaktan ödül yok", MinigameService.TryComplete(ctx.player, T + rules.minSeconds + 1), nil)
	MinigameService._Reset(ctx.player)
end)

-- ─── Arkadaş bonusu ─────────────────────────────────────────────────────────

case("Arkadaş: bonus küçük ve tavanlı", function()
	eq("arkadaş yoksa sıfır", Config.GetFriendBonus(0), 0)
	near("bir arkadaş", Config.GetFriendBonus(1), Config.FriendBonusPerFriend, 0.0001)
	near("tavanda duruyor", Config.GetFriendBonus(50), Config.FriendBonusMax, 0.0001)
	eq("negatif sayı sıfır", Config.GetFriendBonus(-3), 0)
	--[[
		"Oyunu kırmasın": tavan tek bir rebirth'ün kalıcı bonusunun yarısını
		geçmemeli, yoksa arkadaşla oynamak ilerlemenin kendisinden değerli
		olur.
	]]
	ok("rebirth'ten çok küçük", Config.FriendBonusMax <= Config.RebirthIncomeBonus / 2,
		string.format("%.2f / %.2f", Config.FriendBonusMax, Config.RebirthIncomeBonus))
	ok("sesi var", Config.HasNotifyCue(FriendService.NotifyKind))
end)

case("Arkadaş: bonus geliri çarpıyor, nitelik tavana kırpılıyor", function(ctx)
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	assert(podium, "boş kaide yok")
	-- Yüksek gelirli karakter: gelir tam sayıya yuvarlanıyor, küçük sayıda
	-- yuvarlama farkı bonusun kendisinden büyük olurdu
	PlotService.PlaceUnit(podium, Config.Units[10].id)

	ctx.player:SetAttribute("FriendBonus", 0)
	local base = EconomyService.GetIncome(ctx.player)
	ok("taban gelir var", base > 0, tostring(base))

	ctx.player:SetAttribute("FriendBonus", Config.GetFriendBonus(2))
	local boosted = EconomyService.GetIncome(ctx.player)
	near("iki arkadaş", boosted, base * (1 + Config.GetFriendBonus(2)), 2)

	-- Nitelik elle şişirilse bile tavanı geçmiyor
	ctx.player:SetAttribute("FriendBonus", 10)
	near("tavana kırpıldı", EconomyService.GetIncome(ctx.player), base * (1 + Config.FriendBonusMax), 2)

	-- Tek oyunculu testte gerçek arkadaş yok: yeniden yayın sıfıra döndürüyor
	FriendService._Publish(ctx.player)
	eq("arkadaş sayısı", ctx.player:GetAttribute("FriendsHere"), 0)
	eq("yayın sıfırladı", ctx.player:GetAttribute("FriendBonus"), 0)

	ctx.player:SetAttribute("FriendBonus", 0)
	clearPlot(ctx.plot)
end)

-- ─── Vent ──────────────────────────────────────────────────────────────────

case("Vent: kapaklar eşli ve promptlu", function()
	local pads = VentService.GetPads()
	ok("en az iki çift", #pads >= 4, tostring(#pads))
	local pairs: { [string]: number } = {}
	local prompted = true
	for _, pad in pads do
		local id = pad:GetAttribute("VentPair")
		pairs[tostring(id)] = (pairs[tostring(id)] or 0) + 1
		if not pad:FindFirstChild("VentPrompt") then
			prompted = false
		end
	end
	local allTwo = true
	for _, n in pairs do
		if n ~= 2 then
			allTwo = false
		end
	end
	ok("her çiftte iki kapak", allTwo)
	ok("her kapakta prompt", prompted)
end)

case("Vent: taşırken yok, bekleme var, eşine ışınlıyor", function(ctx)
	local pads = VentService.GetPads()
	assert(#pads >= 2, "vent yok")
	local a, b = pads[1], pads[2]
	local root = ctx.player.Character.HumanoidRootPart :: BasePart
	local home = root.CFrame
	VentService._Reset(ctx.player)

	-- Taşıyormuş gibi: StealService sırttaki modele bu adı veriyor
	local fake = Instance.new("Model")
	fake.Name = "CarriedUnit"
	fake.Parent = ctx.player.Character
	eq("taşırken reddedildi", VentService.TryVent(ctx.player, a, b, 1000), "carrying")
	fake:Destroy()

	eq("boş elle geçti", VentService.TryVent(ctx.player, a, b, 1000), "ok")
	ok("eşine vardı", (root.Position - b.Position).Magnitude < 6,
		string.format("%.1f", (root.Position - b.Position).Magnitude))
	eq("hemen tekrar yok", VentService.TryVent(ctx.player, b, a, 1000 + Config.VentCooldown - 1), "cooldown")
	eq("bekleme dolunca var", VentService.TryVent(ctx.player, b, a, 1000 + Config.VentCooldown + 1), "ok")

	VentService._Reset(ctx.player)
	root.CFrame = home
end)

-- ─── Sunucu olayları ───────────────────────────────────────────────────────

case("Olay: takvim tutarlı ve olaylar çakışmıyor", function()
	local ids = {}
	for _, def in Config.Events do
		if def.random then
			ids[def.id] = true
			continue
		end
		ok(def.id .. " süre periyottan kısa", def.duration + Config.EventWarning < def.every)
		ok(def.id .. " offset periyot içinde", def.offset >= 0 and def.offset < def.every)
		ids[def.id] = true
	end
	for _, id in { "Meeting", "LightsOut", "Meltdown", "Impostor" } do
		ok(id .. " tanımlı", ids[id] == true)
	end

	-- 24 saat boyunca her olayın penceresi (uyarı dahil) başka bir olayınkiyle kesişmesin
	local day0 = 1_700_000_000 - (1_700_000_000 % 86400)
	local windows = {}
	for _, def in Config.Events do
		if def.random then
			continue
		end
		local t = Config.GetNextEventStart(def, day0)
		while t < day0 + 86400 do
			table.insert(windows, { id = def.id, a = t - Config.EventWarning, b = t + def.duration })
			t += def.every
		end
	end
	local clash = nil
	for i = 1, #windows do
		for j = i + 1, #windows do
			local x, y = windows[i], windows[j]
			if x.a < y.b and y.a < x.b then
				clash = x.id .. "/" .. y.id
			end
		end
	end
	ok("çakışma yok", clash == nil, tostring(clash))

	-- Bir sonraki başlangıç: tam slotta kendisi, bir saniye sonra bir sonraki
	local meeting = Config.GetEvent("Meeting") :: Config.EventDef
	local slot = day0 + meeting.offset
	eq("tam slot", Config.GetNextEventStart(meeting, slot), slot)
	eq("slottan sonra", Config.GetNextEventStart(meeting, slot + 1), slot + meeting.every)
end)

case("Olay: rastgele impostor saatte iki kez, sabit olaylara denk gelmiyor", function()
	local def = Config.GetEvent("Impostor") :: Config.EventDef
	ok("rastgele", def.random == true)
	local rng = Random.new(7)
	local day0 = 1_700_000_000 - (1_700_000_000 % 86400)
	local allGood, countsOk, spacingOk = true, true, true
	for h = 0, 23 do
		local hour = day0 + h * 3600
		local starts = Config.PlanRandomEvent(def, hour, rng)
		if #starts ~= (def.perHour or 1) then
			countsOk = false
		end
		local windows = Config.GetFixedEventWindows(hour - 3600, hour + 7200)
		for i, t in starts do
			if t < hour or t + def.duration > hour + 3600 then
				allGood = false
			end
			for _, w in windows do
				if t < w[2] and w[1] < t + def.duration then
					allGood = false
				end
			end
			if i > 1 and t - starts[i - 1] < Config.RandomEventSpacing then
				spacingOk = false
			end
		end
	end
	ok("her saat perHour kadar", countsOk)
	ok("sabit olaylarla çakışmıyor", allGood)
	ok("birbirinden uzak", spacingOk)
	-- Farklı zarlar farklı zamanlar (her sunucu kendi planını yapıyor)
	local a = Config.PlanRandomEvent(def, day0, Random.new(1))
	local b = Config.PlanRandomEvent(def, day0, Random.new(2))
	ok("tahmin edilemez", a[1] ~= b[1] or a[2] ~= b[2])
end)

case("Olay: Emergency Meeting geliri katlıyor, bitince dönüyor", function(ctx)
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	assert(podium, "boş kaide yok")
	PlotService.PlaceUnit(podium, Config.Units[10].id)
	local base = EconomyService.GetIncome(ctx.player)

	ok("başladı", EventService.Begin("Meeting"))
	eq("süren olay", EventService.GetActiveId(), "Meeting")
	near("gelir katlandı", EconomyService.GetIncome(ctx.player), base * Config.MeetingIncomeMul, 2)
	eq("ikinci olay başlamıyor", EventService.Begin("LightsOut"), false)
	EventService.End()
	eq("bitince normal", EconomyService.GetIncome(ctx.player), base)
	eq("yayın temizlendi", workspace:GetAttribute("EventId"), "")
	clearPlot(ctx.plot)
end)

case("Olay: Lights Sabotage çalma süresini kısaltıyor", function(ctx)
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	assert(podium, "boş kaide yok")
	PlotService.PlaceUnit(podium, Config.Units[10].id)
	local prompt = podium:FindFirstChild("StealPrompt") :: ProximityPrompt
	assert(prompt, "çalma promptu yok")
	-- Prompt karaktere göre süresini nitelik sinyaliyle güncelliyor (ertelenmiş)
	task.wait()
	local normal = prompt.HoldDuration

	ok("başladı", EventService.Begin("LightsOut"))
	near("kısaldı", prompt.HoldDuration, normal * Config.LightsOutHoldMul, 0.01)
	EventService.End()
	near("geri döndü", prompt.HoldDuration, normal, 0.01)
	clearPlot(ctx.plot)
end)

case("Olay: Reactor Meltdown çekirdekleri üslerin dışında, ödül veriyor", function(ctx)
	ok("başladı", EventService.Begin("Meltdown"))
	local folder = workspace:FindFirstChild("EventCores")
	local count = if folder then #folder:GetChildren() else 0
	ok("çekirdek düştü", count > 0, tostring(count))

	local insidePlot = 0
	if folder then
		for _, core in folder:GetChildren() do
			for _, plot in PlotService.GetAllPlots() do
				local cf, size = plot:GetBoundingBox()
				local lp = cf:PointToObjectSpace(Vector3.new(core.Position.X, cf.Position.Y, core.Position.Z))
				if math.abs(lp.X) <= size.X / 2 and math.abs(lp.Z) <= size.Z / 2 then
					insidePlot += 1
				end
			end
		end
	end
	eq("üs içinde çekirdek yok", insidePlot, 0)
	EventService.End()
	eq("bitince temizlendi", workspace:FindFirstChild("EventCores"), nil)

	-- Ödül: nakit (zar yüksek) ve karakter (zar düşük, boş kaide var)
	clearPlot(ctx.plot)
	setCash(ctx.player, 0)
	local kind, amount = EventService.GrantCore(ctx.player, 0.99)
	eq("nakit ödül", kind, "cash")
	ok("en az taban", (amount :: number) >= Config.MeltdownMinCash, tostring(amount))
	local kind2, unitId = EventService.GrantCore(ctx.player, 0)
	eq("karakter ödülü", kind2, "unit")
	ok("tanımlı karakter", Config.GetUnit(unitId) ~= nil, tostring(unitId))
	clearPlot(ctx.plot)
end)

case("Olay: Impostor ödemesi %3-5 ve tavanlı", function(ctx)
	eq("alt sınır", EventService.ImpostorPayment(1_000_000, 0), 30_000)
	eq("üst sınır", EventService.ImpostorPayment(1_000_000, 1), 50_000)
	eq("tavan", EventService.ImpostorPayment(1e12, 1), Config.ImpostorPayCap)
	eq("parasız", EventService.ImpostorPayment(0, 0.5), 0)
	-- Tek oyunculu sunucuda impostor seçilmiyor
	eq("tek oyuncuyla başlamıyor", EventService.Begin("Impostor"), false)
	-- Impostor olmayan hırsız yakalanınca kimse ödemiyor
	eq("impostor değilse ödeme yok", EventService.OnCaught(ctx.player, ctx.player, 0.5), 0)
end)

-- ─── Hızlı çalma ────────────────────────────────────────────────────────────

case("Hızlı çalma: pass iksirden güçlü, alt sınır var, istemciye yayınlanıyor", function(ctx)
	ok("pass iksirden güçlü", Config.PassFastStealMultiplier < Config.PotionFastStealMultiplier)
	ok("ikisi de gerçekten hızlandırıyor", Config.PotionFastStealMultiplier < 1)

	near("normal", Config.GetPersonalStealHold(4, 0.6), 2.4, 0.001)
	eq("alt sınır", Config.GetPersonalStealHold(2 * Config.LightsOutHoldMul, Config.PassFastStealMultiplier), Config.MinStealHold)
	near("taban zaten kısaysa dokunma", Config.GetPersonalStealHold(0.8, 0.5), 0.8, 0.001)

	MonetizationService.ClearBoosts(ctx.player)
	MonetizationService.PublishStealHold(ctx.player)
	eq("iksirsiz nitelik 1", ctx.player:GetAttribute("StealHoldMul"), 1)

	MonetizationService.GrantBoost(ctx.player, "steal", 60)
	eq("iksir çarpanı", MonetizationService.GetStealHoldMultiplier(ctx.player), Config.PotionFastStealMultiplier)
	MonetizationService.PublishStealHold(ctx.player)
	eq("iksir niteliği", ctx.player:GetAttribute("StealHoldMul"), Config.PotionFastStealMultiplier)

	MonetizationService.ClearBoosts(ctx.player)
	MonetizationService.PublishStealHold(ctx.player)
	eq("iksir bitince 1", ctx.player:GetAttribute("StealHoldMul"), 1)

	-- Sunucu çalma promptuna tabanı nitelik olarak yazıyor
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	assert(podium, "boş kaide yok")
	PlotService.PlaceUnit(podium, Config.Units[10].id)
	task.wait()
	local prompt = podium:FindFirstChild("StealPrompt") :: ProximityPrompt
	near("taban niteliği", prompt:GetAttribute("BaseHold") or -1, prompt.HoldDuration, 0.001)
	clearPlot(ctx.plot)
end)

-- ─── Ek oda görevleri ──────────────────────────────────────────────────────

case("Görev (oda): konsollar kurulu ve tanımlar tutarlı", function()
	local consoles = TaskService.GetConsoles()
	for _, def in Config.Tasks do
		ok(def.id .. " konsolu var", consoles[def.id] ~= nil)
		local c = consoles[def.id]
		ok(def.id .. " promptu var", c ~= nil and c:FindFirstChild("TaskPrompt") ~= nil)
		ok(def.id .. " süreler mantıklı", def.minSeconds > 0 and def.maxSeconds > def.minSeconds and def.cooldown >= 60)
	end
end)

case("Görev (oda): ödül sunucuda doğrulanıyor", function(ctx)
	local def = Config.Tasks[1]
	local original = TaskService.NearConsole
	TaskService.NearConsole = function()
		return true
	end
	TaskService._Reset(ctx.player)
	setCash(ctx.player, 0)
	local T = 5000

	eq("bilinmeyen görev yok", TaskService.TryComplete(ctx.player, "Nope", T), nil)
	eq("sayı kimlik yok", TaskService.TryComplete(ctx.player, 42, T), nil)
	eq("başlamadan yok", TaskService.TryComplete(ctx.player, def.id, T), nil)
	TaskService.Begin(ctx.player, def.id, T)
	eq("çok hızlı yok", TaskService.TryComplete(ctx.player, def.id, T + def.minSeconds - 0.5), nil)
	local reward = TaskService.TryComplete(ctx.player, def.id, T + def.minSeconds + 0.5)
	ok("geçerli bitiş ödül", reward ~= nil and reward >= def.minReward, tostring(reward))
	eq("nakit eklendi", EconomyService.GetCash(ctx.player), reward or -1)
	ok("hazır olma zamanı yazıldı", (ctx.player:GetAttribute("TaskReady_" .. def.id) or 0) > os.time())

	-- Bekleme içinde ikinci ödül yok; başka görev etkilenmiyor
	TaskService.Begin(ctx.player, def.id, T + 10)
	eq("beklemede yok", TaskService.TryComplete(ctx.player, def.id, T + 10 + def.minSeconds + 1), nil)
	local other = Config.Tasks[2]
	TaskService.Begin(ctx.player, other.id, T + 20)
	ok("başka görev bağımsız", TaskService.TryComplete(ctx.player, other.id, T + 20 + other.minSeconds + 1) ~= nil)

	-- Konsoldan uzak: test oyuncusu kendi üssünde
	TaskService.NearConsole = original
	TaskService._Reset(ctx.player)
	TaskService.Begin(ctx.player, def.id, T)
	eq("uzaktan yok", TaskService.TryComplete(ctx.player, def.id, T + def.minSeconds + 1), nil)
	TaskService._Reset(ctx.player)
end)

-- ─── Kozmetikler ────────────────────────────────────────────────────────────

case("Kozmetik: tanımlar tutarlı, her şapkanın modeli var", function()
	local seen = {}
	local prevHat, prevTrail = 0, 0
	for _, def in Config.Cosmetics do
		ok(def.id .. " tekil", not seen[def.id])
		seen[def.id] = true
		ok(def.id .. " türü", def.kind == "hat" or def.kind == "trail", def.kind)
		ok(def.id .. " nadirlik", Config.Rarities[def.rarity] ~= nil)
		if def.kind == "hat" then
			ok(def.id .. " fiyat sırası", def.price > prevHat)
			prevHat = def.price
			local model = CosmeticModel.BuildHat(def.id, true)
			ok(def.id .. " modeli kuruluyor", model ~= nil and model.PrimaryPart ~= nil)
			if model then
				model:Destroy()
			end
		else
			ok(def.id .. " fiyat sırası", def.price > prevTrail)
			prevTrail = def.price
		end
	end
	ok("ses tanımlı", Config.HasNotifyCue(CosmeticService.NotifyKind))
end)

case("Kozmetik: satın alma parayla, takma sahiplikle, karaktere takılıyor", function(ctx)
	local p = ctx.profile
	p.cosmetics = {}
	p.hat = ""
	p.trail = ""
	local hat = Config.Cosmetics[1]
	setCash(ctx.player, 0)
	ok("parasız alınmıyor", not CosmeticService.TryBuy(ctx.player, hat.id))
	ok("sahip olunmayan takılmıyor", not CosmeticService.Equip(ctx.player, "hat", hat.id))
	ok("bilinmeyen alınmıyor", not CosmeticService.TryBuy(ctx.player, "NoSuchHat"))

	setCash(ctx.player, hat.price)
	ok("alındı", CosmeticService.TryBuy(ctx.player, hat.id))
	eq("parası düştü", EconomyService.GetCash(ctx.player), 0)
	ok("profilde", p.cosmetics[hat.id] == true)
	eq("alınca takıldı", p.hat, hat.id)
	ok("ikinci kez alınmıyor", not CosmeticService.TryBuy(ctx.player, hat.id))
	ok("karakterde şapka", ctx.player.Character:FindFirstChild("CosmeticHat") ~= nil)
	ok("nitelik yayınlandı", string.find(tostring(ctx.player:GetAttribute("CosmeticsOwned")), hat.id, 1, true) ~= nil)

	ok("yanlış türe takılmıyor", not CosmeticService.Equip(ctx.player, "trail", hat.id))
	ok("çıkarıldı", CosmeticService.Equip(ctx.player, "hat", ""))
	eq("şapka yok", ctx.player.Character:FindFirstChild("CosmeticHat"), nil)

	-- İz: kök parçaya Trail takılıyor
	local trail: any = nil
	for _, def in Config.Cosmetics do
		if def.kind == "trail" then
			trail = def
			break
		end
	end
	p.cosmetics[trail.id] = true
	ok("iz takıldı", CosmeticService.Equip(ctx.player, "trail", trail.id))
	ok("karakterde iz", ctx.player.Character.HumanoidRootPart:FindFirstChild("CosmeticTrail") ~= nil)
	CosmeticService.Equip(ctx.player, "trail", "")
	eq("iz kalktı", ctx.player.Character.HumanoidRootPart:FindFirstChild("CosmeticTrail"), nil)
end)

-- ─── Sabotajlar ─────────────────────────────────────────────────────────────

case("Sabotaj: tanımlar tutarlı, fiyat gelire göre", function()
	for _, def in Config.Sabotages do
		ok(def.id .. " süre", def.duration > 0 and def.duration <= 45)
		ok(def.id .. " dokunulmazlık süreden uzun", Config.SabotageTargetImmunity > def.duration)
		eq(def.id .. " taban fiyat", Config.GetSabotagePrice(def, 0), def.minimum)
		eq(def.id .. " gelirle", Config.GetSabotagePrice(def, 1e6), def.seconds * 1e6)
	end
	ok("ses tanımlı", Config.HasNotifyCue(SabotageService.NotifyKind))
	ok("remote dinleniyor", Net.IsClientToServer("SabotageAction"))
end)

case("Sabotaj: satın alma parayla, yığın sınırlı, kendine kullanılmıyor", function(ctx)
	local p = ctx.profile
	p.sabotages = {}
	local def = Config.Sabotages[1]
	clearPlot(ctx.plot)
	setCash(ctx.player, 0)
	ok("parasız alınmıyor", not SabotageService.TryBuy(ctx.player, def.id))
	ok("bilinmeyen alınmıyor", not SabotageService.TryBuy(ctx.player, "NoSuchThing"))

	local price = Config.GetSabotagePrice(def, EconomyService.GetIncome(ctx.player))
	setCash(ctx.player, price * (Config.SabotageMaxStack + 1))
	for _ = 1, Config.SabotageMaxStack do
		SabotageService.TryBuy(ctx.player, def.id)
	end
	eq("yığın dolu", SabotageService.GetCount(ctx.player, def.id), Config.SabotageMaxStack)
	ok("sınırın üstü alınmıyor", not SabotageService.TryBuy(ctx.player, def.id))
	eq("fazla para düşmedi", EconomyService.GetCash(ctx.player), price)
	ok("nitelik yayınlandı", string.find(tostring(ctx.player:GetAttribute("Sabotages")),
		def.id .. "=" .. Config.SabotageMaxStack, 1, true) ~= nil)

	eq("kendine olmaz", SabotageService.TryUse(ctx.player, def.id, ctx.player), "self")
	p.lastSabotageAt = 0
	eq("hedefsiz olmaz", SabotageService.TryUse(ctx.player, def.id, nil), "target")
	-- Kullanan 25 dk bekliyor; bekleme profilde (unix saati)
	p.lastSabotageAt = os.time()
	eq("beklemede", SabotageService.TryUse(ctx.player, def.id, nil), "cooldown")
	eq("bekleme bitince geçiyor", SabotageService.TryUse(ctx.player, def.id, nil, nil,
		os.time() + Config.SabotageUserCooldown + 1), "target")
	ok("bekleme 20-30 dk", Config.SabotageUserCooldown >= 1200 and Config.SabotageUserCooldown <= 1800)
	eq("adet düşmedi", SabotageService.GetCount(ctx.player, def.id), Config.SabotageMaxStack)
	p.sabotages = {}
	eq("olmayan kullanılmıyor", SabotageService.TryUse(ctx.player, def.id, nil), "none")
end)

case("Sabotaj: etkiler üsse uygulanıp süre sonunda kalkıyor", function(ctx)
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	assert(podium, "boş kaide yok")
	PlotService.PlaceUnit(podium, Config.Units[10].id)
	task.wait()
	local prompt = podium:FindFirstChild("StealPrompt") :: ProximityPrompt
	local normal = prompt.HoldDuration

	-- Blackout: ışıklar sönüyor, çalma kısalıyor
	SabotageService._Apply("Blackout", ctx.player)
	task.wait()
	ok("karanlık niteliği", ctx.plot:GetAttribute("Blackout") == true)
	near("çalma kısaldı", prompt.HoldDuration, normal * Config.BlackoutHoldMul, 0.001)
	local lit = 0
	for _, d in ctx.plot:GetDescendants() do
		if d:IsA("Light") and d.Enabled and d.Parent and d.Parent.Name ~= "LockButton"
			and not d:IsDescendantOf(ctx.plot.Podiums)
		then
			lit += 1
		end
	end
	eq("ışıklar söndü", lit, 0)

	SabotageService._Reset(ctx.player)
	task.wait()
	near("çalma geri geldi", prompt.HoldDuration, normal, 0.001)
	local off = 0
	for _, d in ctx.plot:GetDescendants() do
		if d:GetAttribute("SabotageOff") then
			off += 1
		end
	end
	eq("ışıklar geri yandı", off, 0)

	-- Lock Jam: kilitliyse kısa süre sonra düşüyor
	ctx.plot:SetAttribute("Locked", true)
	ctx.plot:SetAttribute("LockUsedAt", os.clock())
	SabotageService._Apply("LockJam", ctx.player)
	ok("bozuk niteliği", ctx.plot:GetAttribute("LockJam") == true)
	ok("kilit hemen düşmüyor", ctx.plot:GetAttribute("Locked") == true)
	task.wait(Config.LockJamDropDelay + 0.3)
	ok("kilit düştü", ctx.plot:GetAttribute("Locked") == false)

	-- Comms Jam: kurbanın niteliği
	SabotageService._Apply("CommsJam", ctx.player)
	ok("iletişim kesik", ctx.player:GetAttribute("CommsJam") == true)

	SabotageService._Reset(ctx.player)
	eq("bozukluk kalktı", ctx.plot:GetAttribute("LockJam"), nil)
	eq("iletişim geri", ctx.player:GetAttribute("CommsJam"), nil)
	ctx.plot:SetAttribute("LockUsedAt", 0)
	clearPlot(ctx.plot)
end)

-- ─── Gezen impostor ─────────────────────────────────────────────────────────

case("Impostor NPC: ayarlar yakalanabilir, ödül gelire göre", function()
	ok("kaçarken oyuncudan yavaş", Config.RogueFleeSpeed < Config.NormalWalkSpeed)
	ok("yaklaşırken oyuncudan yavaş", Config.RogueApproachSpeed < Config.NormalWalkSpeed)
	ok("aralık mantıklı", Config.RogueIntervalMin >= 180 and Config.RogueIntervalMax >= Config.RogueIntervalMin)
	eq("gelirsizlik 5 dk", Config.RogueOfflineSeconds, 300)
	eq("taban ödül", Config.GetRogueReward(0), Config.RogueRewardMin)
	eq("gelirle ödül", Config.GetRogueReward(1e6), Config.RogueRewardSeconds * 1e6)
	ok("ses tanımlı", Config.HasNotifyCue(RogueService.NotifyKind))
	ok("vent kapakları var", #VentService.GetPads() >= 2)
	-- Her üsten en az bir kaçış vent'i yeterince uzakta olmalı (kovalamaca olsun)
	for _, plot in PlotService.GetAllPlots() do
		local far = false
		for _, pad in VentService.GetPads() do
			if (pad.Position - plot.Base.Position).Magnitude >= Config.RogueEscapeMinDistance then
				far = true
			end
		end
		ok(plot.Name .. " uzak vent", far)
	end
	ok("kaçış 10 sn'den uzun", Config.RogueEscapeMinDistance / Config.RogueFleeSpeed >= 10)
end)

case("Impostor NPC: sahibi durdurunca ödül alıyor, kilit korumuyor", function(ctx)
	RogueService._Reset()
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	assert(podium, "boş kaide yok")
	PlotService.PlaceUnit(podium, Config.Units[10].id)

	-- Kilitli üs de hedef olabiliyor
	ctx.plot:SetAttribute("Locked", true)
	local found = false
	for _, c in RogueService.GetCandidates() do
		if c.podium == podium then
			found = true
		end
	end
	ok("kilitli üs hedef", found)
	ctx.plot:SetAttribute("Locked", false)

	eq("yokken yakalanmaz", (RogueService.TryCatch(ctx.player)), "none")
	ok("çıktı", RogueService.Spawn(ctx.plot, podium, true))
	ok("ikincisi çıkmıyor", not RogueService.Spawn(ctx.plot, podium, true))
	local r = RogueService.GetCurrent()
	ok("sahibi doğru", r ~= nil and r.owner == ctx.player)
	ok("modeli dünyada", r ~= nil and r.model.Parent == workspace)
	ok("promptu var", r ~= nil and r.root:FindFirstChild("RoguePrompt") ~= nil)
	-- Kök yürüyünce gövde de gelmeli (kaynaklar dünyada kurulmazsa vent'te kalıyordu)
	if r then
		local body = r.model:FindFirstChild("Body") :: BasePart
		local before = body.Position
		r.root.CFrame += Vector3.new(0, 0, 5)
		task.wait()
		near("gövde kökle geliyor", (body.Position - before).Z, 5, 0.05)
		-- Gövde kökün hemen üstünde (kaynak yanlış anda kurulunca yüzlerce stud uzakta kalıyordu)
		ok("gövde kökün yanında", (body.Position - r.root.Position).Magnitude < 4,
			tostring((body.Position - r.root.Position).Magnitude))
		local _, size = r.model:GetBoundingBox()
		near("ayaklar zeminde", r.root.Position.Y - r.lift - (r.model:GetBoundingBox().Position.Y - size.Y / 2), 0, 0.05)
	end

	RogueService._Grab()
	local ghosted = false
	for _, d in podium.Unit:GetDescendants() do
		if d:GetAttribute("RogueGhost") ~= nil then
			ghosted = true
		end
	end
	ok("kapınca karakter soluk", ghosted)
	ok("sırtında kopya", r ~= nil and r.carried ~= nil)

	setCash(ctx.player, 0)
	local caught0 = ctx.profile.caught
	local reason, reward = RogueService.TryCatch(ctx.player)
	eq("durdurdu", reason, "ok")
	-- En az ödül kadar: yakalama sayacı bir unvan açarsa onun ödülü de ekleniyor
	ok("ödül geldi", EconomyService.GetCash(ctx.player) >= reward, tostring(EconomyService.GetCash(ctx.player)))
	ok("ödül tabandan az değil", reward >= Config.RogueRewardMin)
	eq("yakalama sayıldı", ctx.profile.caught, caught0 + 1)
	eq("sahneden gitti", RogueService.GetCurrent(), nil)
	eq("gelir kesilmedi", podium:GetAttribute("OfflineUntil"), nil)
	local still = false
	for _, d in podium.Unit:GetDescendants() do
		if d:GetAttribute("RogueGhost") ~= nil then
			still = true
		end
	end
	ok("karakter normale döndü", not still)
	clearPlot(ctx.plot)
end)

case("Impostor NPC: kaçarsa karakter 5 dk para üretmiyor", function(ctx)
	RogueService._Reset()
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	assert(podium, "boş kaide yok")
	PlotService.PlaceUnit(podium, Config.Units[10].id)
	local income = EconomyService.GetIncome(ctx.player)
	ok("önce gelir var", income > 0)

	ok("çıktı", RogueService.Spawn(ctx.plot, podium, true))
	RogueService._Grab()
	RogueService._Escape()
	-- Gecikmeli "karakter kondu" sinyali işareti silmemeli
	task.wait()
	eq("sahneden gitti", RogueService.GetCurrent(), nil)
	local untilAt = podium:GetAttribute("OfflineUntil")
	ok("gelirsiz", typeof(untilAt) == "number" and untilAt > workspace:GetServerTimeNow() + 290)
	eq("gelir kesildi", EconomyService.GetIncome(ctx.player), 0)
	eq("karakter kaidede duruyor", podium:GetAttribute("UnitId"), Config.Units[10].id)
	ok("geri sayım etiketi", podium:FindFirstChild("OfflineLabel") ~= nil)
	local found = false
	for _, c in RogueService.GetCandidates() do
		if c.podium == podium then
			found = true
		end
	end
	ok("gelirsiz kaide tekrar hedef değil", not found)

	-- Karakter değişince (satıldı / çalındı) gelirsizlik bitiyor
	PlotService.ClearUnit(podium)
	task.wait()
	eq("boşalınca temizlendi", podium:GetAttribute("OfflineUntil"), nil)

	PlotService.PlaceUnit(podium, Config.Units[10].id)
	RogueService._Reset(podium)
	eq("gelir geri geldi", EconomyService.GetIncome(ctx.player), income)
	clearPlot(ctx.plot)
end)

case("Impostor NPC: fiziksiz rota, zemine oturuyor, herkese aynı", function(ctx)
	local RogueTrack = require(ReplicatedStorage.Shared.RogueTrack)
	-- Rota örnekleme: iki parça, 10 + 5 stud
	local track = RogueTrack.New({ Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(10, 0, 0), Vector3.new(10, 0, 5) }, 100, 5)
	eq("çift nokta atıldı", #track.points, 3)
	near("toplam yol", track.total, 15, 1e-6)
	local p, dir = RogueTrack.At(track, 12)
	near("ikinci parçada", (p - Vector3.new(10, 0, 2)).Magnitude, 0, 1e-6)
	ok("yön ikinci parçanın", dir.Unit:Dot(Vector3.zAxis) > 0.99)
	near("zamandan yol", RogueTrack.Distance(track, 102), 10, 1e-6)
	ok("bitmedi", not RogueTrack.Done(track, 102))
	ok("bitti", RogueTrack.Done(track, 103.1))
	-- Kodlama gidiş-dönüş (istemci aynı rotayı okuyor)
	local back = RogueTrack.Decode(RogueTrack.Encode(track))
	ok("çözüldü", back ~= nil)
	if back then
		near("aynı uzunluk", back.total, track.total, 0.05)
		eq("aynı başlangıç", back.start, track.start)
	end
	eq("boş rota yok", RogueTrack.Decode(""), nil)
	eq("bozuk rota yok", RogueTrack.Decode("{bozuk"), nil)

	-- Model: Humanoid yok (fizikle tırmanmasın), kök çapalı, istemci için Lift
	clearPlot(ctx.plot)
	local podium = PlotService.GetPodiums(ctx.plot)[1]
	PlotService.PlaceUnit(podium, Config.Units[10].id)
	RogueService._Reset(podium)
	ok("çıktı", RogueService.Spawn(ctx.plot, podium, true))
	local r = RogueService.GetCurrent()
	if r then
		eq("Humanoid yok", r.model:FindFirstChildWhichIsA("Humanoid", true), nil)
		ok("kök çapalı", r.root.Anchored)
		ok("Lift niteliği", typeof(r.model:GetAttribute("Lift")) == "number")
		eq("dururken rota boş", r.model:GetAttribute("RogueTrack"), "")
		-- Doğduğu yerde ayaklar zeminde (havada değil): altında 0.5 stud içinde zemin
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { r.model }
		params.CollisionGroup = "RogueNPC"
		local hit = workspace:Raycast(r.pos + Vector3.new(0, 1, 0), Vector3.new(0, -3, 0), params)
		ok("ayak altında zemin", hit ~= nil and math.abs(hit.Position.Y - r.pos.Y) < 0.5,
			if hit then tostring(hit.Position.Y - r.pos.Y) else "yok")
	end
	RogueService._Reset(podium)
	clearPlot(ctx.plot)
end)

-- ─── Harita: tüneller ve admin masası ──────────────────────────────────────

case("Tünel: iki rampa ve tünel kurulu, yol bulucu içinden geçiyor", function()
	local tunnels = workspace.Decor:FindFirstChild("Tunnels")
	ok("tünel klasörü", tunnels ~= nil)
	if not tunnels then
		return
	end
	eq("iki tünel", #tunnels:GetChildren(), 2)
	for _, t in tunnels:GetChildren() do
		local ramps = 0
		for _, d in t:GetChildren() do
			if d.Name == "TunnelRamp" then
				ramps += 1
			end
		end
		eq(t.Name .. " iki rampa", ramps, 2)
	end
	-- Rampa girişinden öteki girişe yol tünelden geçmeli
	local t1 = tunnels:FindFirstChild("Tunnel1")
	local floorPart = t1 and t1:FindFirstChild("TunnelFloor") :: BasePart?
	if floorPart then
		local x = floorPart.Position.X
		local z0 = floorPart.Position.Z - floorPart.Size.Z / 2
		local z1 = floorPart.Position.Z + floorPart.Size.Z / 2
		local path = game:GetService("PathfindingService"):CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
		path:ComputeAsync(Vector3.new(x, 4, z0 - 4), Vector3.new(x, 3, z1 + 4))
		eq("yol bulundu", path.Status, Enum.PathStatus.Success)
		local minY = math.huge
		for _, wp in path:GetWaypoints() do
			minY = math.min(minY, wp.Position.Y)
		end
		ok("yol yeraltından", minY < -10, tostring(minY))
	end
end)

case("Admin masası: bölgeler ölçülüyor, konum doğru odaya düşüyor", function(ctx)
	local zones = AdminMapService.GetZones()
	ok("bölgeler var", #zones >= 10, tostring(#zones))
	local screen = workspace.Decor.AdminTable:FindFirstChild("AdminScreen")
	ok("ekranda harita", screen ~= nil and screen:FindFirstChild("AdminMap") ~= nil)

	local base = ctx.plot:FindFirstChild("Base") :: BasePart
	local z = AdminMapService.Classify(base.Position + Vector3.new(0, 3, 0))
	eq("üs", z and z.name, ctx.plot.Name)
	-- Tünel zemininin ortası omurganın altındaki odada; tünel noktası oradan 30 stud güneyde
	local tunnelFloor = workspace.Decor.Tunnels.Tunnel1.TunnelFloor :: BasePart
	local t = AdminMapService.Classify(tunnelFloor.Position + Vector3.new(0, 2, -30))
	eq("tünel", t and t.kind, "tunnel")
	local security = AdminMapService.Classify(tunnelFloor.Position + Vector3.new(0, 2, 0))
	eq("tünelin ortası Security odası", security and security.name, "Security")
	local adminRoom = AdminMapService.Classify(screen.Position + Vector3.new(0, 1, 0))
	eq("masa Admin odasında", adminRoom and adminRoom.name, "Admin")
	local pad = workspace.Decor:FindFirstChild("TeleportPad")
	local padPart = pad and pad:FindFirstChildWhichIsA("BasePart", true)
	if padPart then
		local lobby = AdminMapService.Classify(padPart.Position + Vector3.new(0, 2, -12))
		eq("cafeteria", lobby and lobby.name, "Lobby")
	end
	local hall = AdminMapService.Classify(Vector3.new(180, 3, 58))
	eq("koridor", hall and hall.kind, "hall")

	-- Kendi üssünde: nokta var, davetsiz misafir yok
	ctx.player.Character.HumanoidRootPart.CFrame = CFrame.new(base.Position + Vector3.new(0, 4, 0))
	task.wait()
	AdminMapService.Update()
	local frame = z and z.frame
	local dots = 0
	if frame then
		for _, d in frame.Dots:GetChildren() do
			if d:IsA("Frame") and d.Visible then
				dots += 1
			end
		end
	end
	eq("kendi üssünde bir nokta", dots, 1)
	ok("kendi üssü kırmızı değil", frame ~= nil and frame.BackgroundColor3 ~= Color3.fromRGB(200, 50, 60))
end)

-- ─── Çalıştırıcı ────────────────────────────────────────────────────────────

--[[
	Tüm testleri koşar ve özet basar. Başarısız test sayısını döner,
	yani 0 dönüyorsa her şey yolunda.
]]
function ServerTests.Run(player: Player?): number
	if not player then
		warn("[Tests] Oyuncu gerekli: Tests.Run(Players:GetPlayers()[1])")
		return -1
	end

	local profile = DataService.Get(player)
	if not profile then
		warn("[Tests] Profil yüklenmemiş, testler atlandı")
		return -1
	end

	local plot = PlotService.GetPlotOf(player)
	if not plot then
		warn("[Tests] Oyuncunun üssü yok, testler atlandı")
		return -1
	end

	--[[
		Testler sürerken gerçek kayda hiçbir şey yazılmıyor (servisler
		rebirth/kat/çark sonrası hemen kaydediyor; deneme parası oyuncunun
		kaydına geçiyordu). Sonda geri yüklenen profil bir kez kaydediliyor.
	]]
	DataService._SetSavingPaused(true)

	-- Testler profili değiştiriyor; sonunda geri yüklenecek
	local backup = {
		cash = profile.cash,
		rebirths = profile.rebirths,
		upgrades = table.clone(profile.upgrades),
		lastSpinAt = profile.lastSpinAt,
		titles = table.clone(profile.titles),
		robbed = profile.robbed,
		caught = profile.caught,
		maxStreak = profile.maxStreak,
		tutorialStep = profile.tutorialStep,
		stolen = profile.stolen,
		titleManual = profile.titleManual,
		activeTitle = profile.activeTitle,
		quests = profile.quests,
		potions = table.clone(profile.potions),
		floorsBought = profile.floorsBought,
		bought = profile.bought,
		sold = profile.sold,
		spins = profile.spins,
		earned = profile.earned,
		-- Sonradan eklenen alanlar: testler bunlara da dokunuyor
		pets = table.clone(profile.pets),
		equippedPets = table.clone(profile.equippedPets),
		discovered = table.clone(profile.discovered),
		dailyStreak = profile.dailyStreak,
		lastDailyDay = profile.lastDailyDay,
		playtimeDay = profile.playtimeDay,
		playtimeSeconds = profile.playtimeSeconds,
		playtimeClaimed = table.clone(profile.playtimeClaimed),
		indexClaimed = table.clone(profile.indexClaimed),
		gear = table.clone(profile.gear),
		cosmetics = table.clone(profile.cosmetics),
		sabotages = table.clone(profile.sabotages),
		lastSabotageAt = profile.lastSabotageAt,
		hat = profile.hat,
		trail = profile.trail,
	}
	local backupFloors = plot:GetAttribute("UnlockedFloors")

	--[[
		Gelir çarpanına giren nitelikler (takılı petler, indeks ödülü).
		Testler taban geliri ölçüyor; oyuncunun kendi petleri sayılara
		karışınca gelir testleri %35 fazla ölçüyordu. Koşu boyunca sıfır,
		sonunda geri.
	]]
	local backupAttributes = {
		PetIncomeBonus = player:GetAttribute("PetIncomeBonus"),
		PetSpeedBonus = player:GetAttribute("PetSpeedBonus"),
		IndexBonus = player:GetAttribute("IndexBonus"),
		IndexClaimed = player:GetAttribute("IndexClaimed"),
		FriendBonus = player:GetAttribute("FriendBonus"),
	}
	player:SetAttribute("PetIncomeBonus", 0)
	player:SetAttribute("PetSpeedBonus", 0)
	player:SetAttribute("IndexBonus", 0)

	player:SetAttribute("FriendBonus", 0)

	local ctx = { player = player, plot = plot, profile = profile }

	--[[
		Periyodik taramalar koşu boyunca dursun. Testler profili doğrudan
		kurcalıyor; tarama araya girerse gerçekten kazanılmamış ödüller
		dağıtılıyor ve nakit sayan testler tutmuyor.
	]]
	TitleService.SetPaused(true)
	TutorialService.SetPaused(true)
	QuestService.SetPaused(true)
	-- Olay takvimi de dursun; süren bir olay gelir/süre ölçen testleri bozar
	EventService.SetPaused(true)
	EventService.End()
	-- Gezen impostor da çıkmasın; sahnede varsa kaldır
	RogueService.SetPaused(true)
	RogueService._Reset()

	print("═══ SUNUCU REGRESYON TESTLERİ ═══")

	local totalPassed, totalFailed, failedCases = 0, 0, 0
	local started = os.clock()

	for _, entry in cases do
		current = { passed = 0, failed = 0, notes = {} }

		local success, err = pcall(entry.fn, ctx)
		if not success then
			current.failed += 1
			table.insert(current.notes, "      çalışma hatası: " .. tostring(err))
		end

		totalPassed += current.passed
		totalFailed += current.failed
		if current.failed > 0 then
			failedCases += 1
		end

		print(string.format("  [%s] %-52s %d/%d",
			current.failed == 0 and "OK" or "HATA",
			entry.name,
			current.passed,
			current.passed + current.failed))

		for _, note in current.notes do
			print(note)
		end
	end

	-- Ortamı geri yükle
	TitleService.SetPaused(false)
	TutorialService.SetPaused(false)
	QuestService.SetPaused(false)
	EventService.End()
	EventService.SetPaused(false)
	RogueService.SetPaused(false)
	-- Testler iksir içiyor; kalan takviyeyi canlı oturuma bırakma
	MonetizationService.ClearBoosts(player)

	profile.cash = backup.cash
	profile.rebirths = backup.rebirths
	profile.upgrades = backup.upgrades
	profile.lastSpinAt = backup.lastSpinAt
	profile.titles = backup.titles
	profile.robbed = backup.robbed
	profile.caught = backup.caught
	profile.maxStreak = backup.maxStreak
	profile.tutorialStep = backup.tutorialStep
	profile.stolen = backup.stolen
	profile.titleManual = backup.titleManual
	profile.activeTitle = backup.activeTitle
	profile.quests = backup.quests
	profile.potions = backup.potions
	profile.floorsBought = backup.floorsBought
	profile.bought = backup.bought
	profile.sold = backup.sold
	profile.spins = backup.spins
	profile.earned = backup.earned
	profile.pets = backup.pets
	profile.equippedPets = backup.equippedPets
	profile.discovered = backup.discovered
	profile.dailyStreak = backup.dailyStreak
	profile.lastDailyDay = backup.lastDailyDay
	profile.playtimeDay = backup.playtimeDay
	profile.playtimeSeconds = backup.playtimeSeconds
	profile.playtimeClaimed = backup.playtimeClaimed
	profile.indexClaimed = backup.indexClaimed
	profile.gear = backup.gear
	profile.cosmetics = backup.cosmetics
	profile.sabotages = backup.sabotages
	profile.lastSabotageAt = backup.lastSabotageAt
	SabotageService.Publish(player)
	profile.hat = backup.hat
	profile.trail = backup.trail
	CosmeticService.Apply(player)
	CosmeticService.Publish(player)
	for name, value in backupAttributes do
		player:SetAttribute(name, value)
	end
	-- Petler geri yüklendi: bonusu ve sahadaki modelleri gerçek profile göre kur
	PetService.Apply(player)
	setCash(player, backup.cash)
	PlotService.SetUnlockedFloors(plot, backupFloors)
	FloorService.Publish(player)
	clearPlot(plot)

	-- Kayıt yeniden açık; diskteki kopya geri yüklenen profille aynı olsun
	DataService._SetSavingPaused(false)
	DataService.Save(player)

	print("═══════════════════════════════════")
	print(string.format("  %d test, %d başarısız", #cases, failedCases))
	print(string.format("  %d kontrol geçti, %d kaldı (%.2f sn)",
		totalPassed, totalFailed, os.clock() - started))
	print(string.format("  SONUÇ: %s", totalFailed == 0 and "TEMİZ" or "SORUN VAR"))

	return totalFailed
end

return ServerTests
