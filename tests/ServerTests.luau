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

local Server = script.Parent
local PlotService = require(Server.PlotService)
local EconomyService = require(Server.EconomyService)
local SellService = require(Server.SellService)
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

case("Üs: her katın rampası kendi zeminine ulaşıyor", function(ctx)
	local floors = ctx.plot:FindFirstChild("Floors")
	if not floors then
		ok("Floors klasörü var", false)
		return
	end

	for _, floorModel in floors:GetChildren() do
		local ramp = floorModel:FindFirstChild("Ramp")
		local deck = floorModel:FindFirstChild("Deck")
		if ramp and deck then
			local half = ramp.Size.Z / 2
			local a = (ramp.CFrame * CFrame.new(0, 0.5, -half)).Y
			local b = (ramp.CFrame * CFrame.new(0, 0.5, half)).Y
			local deckTop = deck.Position.Y + deck.Size.Y / 2

			near(floorModel.Name .. " rampası deck'e ulaşıyor", math.max(a, b), deckTop, 0.7)
		end
	end
end)

-- ─── C. Ekonomi ─────────────────────────────────────────────────────────────

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

	ctx.profile.upgrades[id] = def.maxLevel
	eq("tavanda maliyet nil", Config.GetUpgradeCost(id, def.maxLevel), nil)

	setCash(ctx.player, 1e15)
	eq("tavanda satın alma reddedildi", UpgradeService.TryUpgrade(ctx.player, id), false)
	eq("seviye değişmedi", UpgradeService.GetLevel(ctx.player, id), def.maxLevel)
end)

case("Yükseltme: her seviye gerçekten bir şey değiştiriyor", function()
	-- Etki tabana çarparsa üst seviyeler paranın boşa gitmesi olur
	for _, def in Config.Upgrades do
		local values = {}
		local distinct = 0

		for level = 0, def.maxLevel do
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

		eq(def.name .. " farklı değer sayısı", distinct, def.maxLevel + 1)
	end
end)

case("Yükseltme: maliyet eğrisi rebirth'ten sonra da iş bırakıyor", function()
	local total = 0
	for _, def in Config.Upgrades do
		for level = 0, def.maxLevel - 1 do
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

	eq("gelir çarpanı 1", MonetizationService.GetIncomeMultiplier(ctx.player), 1)
	eq("ekstra kaide 0", MonetizationService.GetExtraPodiumsPerFloor(ctx.player), 0)
	eq("çalma süresi çarpanı 1", MonetizationService.GetStealHoldMultiplier(ctx.player), 1)
end)

case("Monetization: ürün tanımları tutarlı", function()
	local kinds = { cash = true, conveyor = true, lucky = true, rebirth = true, spin = true }

	for key, def in Config.Products do
		ok(key .. " tipi tanınıyor", kinds[def.kind] == true, def.kind)
		if def.kind == "cash" then
			ok(key .. " tutarı pozitif", (def.amount or 0) > 0)
		end
	end
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
		local anchor = wheel:FindFirstChild("WheelHub") or wheel:FindFirstChild("WheelPlinth")
		ok("çark gövdesi bulundu", anchor ~= nil)
		if anchor then
			ok("SpinPrompt kurulu", anchor:FindFirstChild("SpinPrompt") ~= nil)
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
	end

	ctx.profile.lastSpinAt = 0
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
			for _, child in ctx.plot:GetChildren() do
				if string.sub(child.Name, 1, 8) == "Upgrade_" then
					return child
				end
			end
			return nil
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
	ok("ödül verildi", EconomyService.GetCash(ctx.player) > before,
		Config.FormatCash(EconomyService.GetCash(ctx.player) - before))

	-- İkinci kez ödül vermemeli
	local after = EconomyService.GetCash(ctx.player)
	QuestService.Check(ctx.player)
	eq("tekrar ödül yok", EconomyService.GetCash(ctx.player), after)
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

	local total = 0
	for _, count in ctx.profile.potions do
		total += count
	end
	ok("iksir verildi", total > 0, tostring(total))

	-- İkinci taramada tekrar vermemeli
	QuestService.Check(ctx.player)
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

	ok("liste küçük", #listened <= 4, tostring(#listened))

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

case("Kat: pedi dünyada kurulu ve promptu var", function(ctx)
	local pad = ctx.plot:FindFirstChild("FloorPad")
	ok("ped var", pad ~= nil)
	if not (pad and pad:IsA("BasePart")) then return end

	local prompt = pad:FindFirstChild("FloorPrompt")
	ok("prompt var", prompt ~= nil)
	if prompt and prompt:IsA("ProximityPrompt") then
		ok("basılı tutma istiyor", prompt.HoldDuration > 0, tostring(prompt.HoldDuration))
		ok("menzil makul", prompt.MaxActivationDistance <= 20,
			tostring(prompt.MaxActivationDistance))
	end

	local gui = pad:FindFirstChild("FloorLabel")
	ok("etiket var", gui ~= nil)

	-- Ped üssün içinde durmalı, başka üssün üstüne taşmamalı
	local base = ctx.plot:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		local delta = pad.Position - base.Position
		ok("ped üs sınırları içinde",
			math.abs(delta.X) <= Config.PlotSize.X / 2
			and math.abs(delta.Z) <= Config.PlotSize.Z / 2,
			string.format("%.1f, %.1f", delta.X, delta.Z))
	end
end)

case("Kat: hepsi alınınca ped gizleniyor", function(ctx)
	ctx.profile.floorsBought = Config.MaxFloors - 1
	FloorService.Refresh(ctx.plot)

	local pad = ctx.plot:FindFirstChild("FloorPad")
	if not (pad and pad:IsA("BasePart")) then return end

	local prompt = pad:FindFirstChild("FloorPrompt")
	ok("ped görünmez", pad.Transparency >= 1, tostring(pad.Transparency))
	if prompt and prompt:IsA("ProximityPrompt") then
		ok("prompt kapalı", not prompt.Enabled)
	end

	-- Alınacak kat varken geri gelmeli
	ctx.profile.floorsBought = 0
	FloorService.Refresh(ctx.plot)
	ok("ped geri geldi", pad.Transparency < 1, tostring(pad.Transparency))
	if prompt and prompt:IsA("ProximityPrompt") then
		ok("prompt açık", prompt.Enabled)
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
	}
	local backupFloors = plot:GetAttribute("UnlockedFloors")

	local ctx = { player = player, plot = plot, profile = profile }

	--[[
		Periyodik taramalar koşu boyunca dursun. Testler profili doğrudan
		kurcalıyor; tarama araya girerse gerçekten kazanılmamış ödüller
		dağıtılıyor ve nakit sayan testler tutmuyor.
	]]
	TitleService.SetPaused(true)
	TutorialService.SetPaused(true)
	QuestService.SetPaused(true)

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
	setCash(player, backup.cash)
	PlotService.SetUnlockedFloors(plot, backupFloors)
	FloorService.Refresh(plot)
	clearPlot(plot)

	print("═══════════════════════════════════")
	print(string.format("  %d test, %d başarısız", #cases, failedCases))
	print(string.format("  %d kontrol geçti, %d kaldı (%.2f sn)",
		totalPassed, totalFailed, os.clock() - started))
	print(string.format("  SONUÇ: %s", totalFailed == 0 and "TEMİZ" or "SORUN VAR"))

	return totalFailed
end

return ServerTests
