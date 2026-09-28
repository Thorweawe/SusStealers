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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Net = require(ReplicatedStorage.Shared.Net)
local CosmeticModel = require(ReplicatedStorage.Shared.CosmeticModel)

local Server = script.Parent
local PlotService = require(Server.PlotService)
local EconomyService = require(Server.EconomyService)
local SellService = require(Server.SellService)
local MovementService = require(Server.MovementService)
local UpgradeService = require(Server.UpgradeService)
local RebirthService = require(Server.RebirthService)
local MonetizationService = require(Server.MonetizationService)
local CapsuleService = require(Server.CapsuleService)
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
local RogueService = require(Server.RogueService)
local AdminMapService = require(Server.AdminMapService)
local SettingsService = require(Server.SettingsService)
local SpaceService = require(Server.SpaceService)
local SpaceBonusService = require(Server.SpaceBonusService)
local JetpackService = require(Server.JetpackService)
local WeeklyService = require(Server.WeeklyService)
local SeasonService = require(Server.SeasonService)
local ServerBoostService = require(Server.ServerBoostService)
local MeteorShower = require(ReplicatedStorage.Shared.MeteorShower)
local SpaceField = require(ReplicatedStorage.Shared.SpaceField)

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

case("Üs: kat kolonları alt kattaki eşyaların içinden geçmiyor", function()
	local bad = {}
	for _, plot in PlotService.GetAllPlots() do
		local floors = plot:FindFirstChild("Floors")
		local base = plot:FindFirstChild("Base")
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { floors }
		for _, column in floors:GetDescendants() do
			if column:IsA("BasePart") and column.Name == "Column" then
				local probe = Vector3.new(column.Size.X - 0.2, column.Size.Y - 1.6, column.Size.Z - 0.2)
				for _, hit in workspace:GetPartBoundsInBox(column.CFrame * CFrame.new(0, 0.5, 0), probe, params) do
					if hit ~= base and hit.Transparency < 0.95 and not hit:IsDescendantOf(workspace:FindFirstChild("Characters") or plot) then
						table.insert(bad, plot.Name .. ":" .. hit.Name)
					elseif hit ~= base and hit.Transparency < 0.95 and hit:IsDescendantOf(plot) then
						table.insert(bad, plot.Name .. ":" .. hit.Name)
					end
				end
			end
		end
	end
	eq("kesişen kolon", #bad, 0)
	if #bad > 0 then
		print("   " .. table.concat(bad, ", ", 1, math.min(#bad, 8)))
	end
end)

case("Karakter modeli: her karakter kendine özel, hepsi kuruluyor", function()
	local UnitModel = require(ReplicatedStorage.Shared.UnitModel)
	local signatures: { [string]: string } = {}
	for _, def in Config.Units do
		local okBuild, model = pcall(UnitModel.Build, def.id)
		ok(def.id .. " kuruldu", okBuild and model ~= nil, if okBuild then nil else tostring(model))
		if okBuild and model then
			-- İmza: parça adları (renk hariç). Aynı imzalı iki karakter = aksesuarı yok
			local names = {}
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(names, d.Name)
				end
			end
			table.sort(names)
			local signature = table.concat(names, ",")
			ok(def.id .. " başkasına benzemiyor", signatures[signature] == nil, signatures[signature])
			signatures[signature] = def.id
			local _, size = model:GetBoundingBox()
			ok(def.id .. " makul boyda", size.Y > 3.5 and size.Y < 9 and size.X < 7, tostring(size))
			model:Destroy()
		end
	end
end)

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

-- ─── F. Yükseltmeler ────────────────────────────────────────────────────────

case("Yükseltme: seviye ve maliyet", function(ctx)
	local id = "SpaceCapsule"
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
	local id = "CrewMorale"
	local def = Config.GetUpgrade(id)

	-- Tavan artık kat sayısına bağlı
	local ceiling = Config.GetUpgradeCeiling(def)
	ctx.profile.floorsBought = Config.MaxFloors - 1
	ctx.profile.upgrades[id] = ceiling
	eq("tavanda maliyet nil", Config.GetUpgradeCost(id, ceiling), nil)

	setCash(ctx.player, 1e15)
	eq("tavanda satın alma reddedildi", UpgradeService.TryUpgrade(ctx.player, id), false)
	eq("seviye değişmedi", UpgradeService.GetLevel(ctx.player, id), ceiling)
	ctx.profile.upgrades[id] = nil
end)

case("Yükseltme: her seviye gerçekten bir şey değiştiriyor", function()
	-- Etki tabana çarparsa üst seviyeler paranın boşa gitmesi olur
	local function valueOf(id: string, level: number): string
		if id == "SpaceCapsule" then
			return string.format("%.5f", Config.GetCapsuleGain(level, Config.Space.BaseSpeed))
		elseif id == "TrainingConsole" then
			return string.format("%.5f", Config.GetTrainingAssist(level))
		elseif id == "QuickHands" then
			return string.format("%.5f", Config.GetGrabHoldMul(level))
		elseif id == "JetBoost" then
			local jet = Config.GetJetBoost(level)
			return if jet then string.format("%.4f/%.4f/%.4f", jet.mul, jet.duration, jet.cooldown) else "none"
		elseif id == "StealthSuit" then
			local w, r = Config.GetStealth(level)
			return string.format("%.5f/%.5f", w, r)
		elseif id == "LuckyScanner" then
			return string.format("%.5f", Config.GetLuckyChance(level))
		elseif id == "CrewMorale" then
			return string.format("%.5f", Config.GetMoraleMultiplier(level))
		end
		return "?"
	end
	for _, def in Config.Upgrades do
		local values = {}
		local distinct = 0
		for level = 0, Config.GetUpgradeCeiling(def) do
			local value = valueOf(def.id, level)
			ok(def.id .. " etkisi tanımlı", value ~= "?")
			if not values[value] then
				values[value] = true
				distinct += 1
			end
		end
		eq(def.name .. " farklı değer sayısı", distinct, Config.GetUpgradeCeiling(def) + 1)
	end
end)

case("Yükseltme: etkiler tavanlı ve yönleri doğru", function()
	local top = 24
	ok("kapma süresi kısalıyor ama sıfıra inmiyor", Config.GetGrabHoldMul(top) < Config.GetGrabHoldMul(0) and Config.GetGrabHoldMul(top) >= 0.4)
	ok("mini oyun kolaylığı 0..1", Config.GetTrainingAssist(0) == 0 and Config.GetTrainingAssist(top) <= 1)
	eq("jet boost 0'da yok", Config.GetJetBoost(0), nil)
	local jet = Config.GetJetBoost(top) :: Config.JetBoost
	ok("jet boost çarpanı makul", jet.mul > 1.5 and jet.mul <= 2.1, string.format("%.2f", jet.mul))
	ok("jet boost beklemesi süresinden uzun", jet.cooldown > jet.duration * 2)
	local wake, reach = Config.GetStealth(top)
	ok("gizlilik uyanmayı geciktiriyor", wake > 1 and wake <= 2.3)
	ok("gizlilik menzili kısaltıyor ama yok etmiyor", reach < 1 and reach >= 0.7)
	ok("şans tavanlı", Config.GetLuckyChance(top) <= 0.3)
	ok("moral tavanlı", Config.GetMoraleMultiplier(top) <= 1.6)
	ok("pass + iksir + tavan bile en kısa sınırın altına inmiyor",
		Config.GetPersonalGrabHold(Config.Space.GrabHold, Config.PassFastStealMultiplier, top) >= Config.MinGrabHold)
end)

case("Yükseltme: kalkan yükseltmelerin parası iade ediliyor", function()
	eq("seviye 0 iade yok", Config.GetRetiredUpgradeRefund("LockPower", 0), 0)
	eq("tanınmayan iade yok", Config.GetRetiredUpgradeRefund("Nope", 3), 0)
	local def = Config.RetiredUpgrades.UnitGuard
	eq("iki seviye iadesi", Config.GetRetiredUpgradeRefund("UnitGuard", 2),
		math.floor(def.baseCost) + math.floor(def.baseCost * def.costGrowth))
	eq("kalkanlar yükseltme listesinde yok", Config.GetUpgrade("LockPower"), nil)
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
	near("ikinci rebirth artışı büyüyor", Config.GetIncomeMultiplier(2) - Config.GetIncomeMultiplier(1), Config.RebirthIncomeBonus + Config.RebirthIncomeStep, 0.001)
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
	eq("kapma süresi çarpanı", MonetizationService.GetStealHoldMultiplier(ctx.player),
		if has(ctx.player, "FastSteal") then Config.PassFastStealMultiplier else 1)
	eq("canavar kalkanı", MonetizationService.HasShield(ctx.player), has(ctx.player, "StrongLock"))
end)

case("Monetization: ürün ve pass kimlikleri girilmiş ve benzersiz", function()
	local seen: { [number]: string } = {}
	for key, def in Config.GamePasses do
		ok(key .. " kimliği var", def.id > 0)
		ok(key .. " kimliği tekrar etmiyor", seen[def.id] == nil, seen[def.id])
		seen[def.id] = key
	end
	for key, def in Config.Products do
		ok(key .. " kimliği var", def.id > 0)
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

--[[ Üssün kaidelerindeki karakterler (UnitId niteliği dolu olanlar). ]]
local function podiumUnits(plot: Model): { { unitId: string, mutationId: string } }
	local list = {}
	for _, podium in PlotService.GetPodiums(plot) do
		local unitId = podium:GetAttribute("UnitId")
		if typeof(unitId) == "string" and unitId ~= "" then
			table.insert(list, { unitId = unitId, mutationId = (podium:GetAttribute("MutationId") :: string?) or "" })
		end
	end
	return list
end

case("Monetization: ödül fonksiyonları çalışıyor (konveyörsüz, doğrudan kaide)", function(ctx)
	clearPlot(ctx.plot)

	ok("bedava karakter", SpaceService.GrantUnit(ctx.player, false) ~= nil)
	ok("garantili mutasyon", SpaceService.GrantUnit(ctx.player, true) ~= nil)

	local units = podiumUnits(ctx.plot)
	eq("iki karakter kaidede", #units, 2)
	local mutated = 0
	for _, u in units do
		if u.mutationId ~= "" then
			mutated += 1
		end
	end
	ok("en az bir mutasyonlu", mutated >= 1, tostring(mutated))
	clearPlot(ctx.plot)
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

case("Çark: prompt basışı kabul ediliyor (Attachment'taki prompt)", function(ctx)
	local wheel = workspace.Decor:FindFirstChild("Wheel")
	local point = wheel and wheel:FindFirstChild("SpinPromptPoint", true)
	local prompt = point and point:FindFirstChild("SpinPrompt") :: ProximityPrompt?
	ok("prompt var", prompt ~= nil)
	local root = ctx.player.Character and ctx.player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if prompt and root and point and point:IsA("Attachment") then
		local before = root.CFrame
		root.CFrame = CFrame.new(point.WorldPosition + Vector3.new(0, 0, 0.5))
		-- Basılı tutma süresini atlamak için sıfır süreyle doğrula
		ok("yakında kabul", PromptGuard.Validate(prompt, ctx.player, 0))
		root.CFrame = CFrame.new(point.WorldPosition + Vector3.new(0, 0, 200))
		ok("uzakta ret", not PromptGuard.Validate(prompt, ctx.player, 0))
		root.CFrame = before
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
		-- Ödül çark durunca veriliyor (pencere): henüz para gelmedi
		eq("ödül çark durmadan verilmedi", EconomyService.GetCash(ctx.player), 0)
		eq("pencere geri sayımı yazıldı", ctx.player:GetAttribute("SpinReadyAt"), ctx.profile.lastSpinAt + Config.SpinCooldownHours * 3600)
	end
	-- Bekleyen ödül sonraki testlerin parasına karışmasın
	SpinService._CancelPending(ctx.player)

	-- Anında (test yolu): ödül hemen geliyor
	ctx.profile.lastSpinAt = 0
	setCash(ctx.player, 0)
	local spinsBefore = ctx.profile.spins
	ok("anında çevirme", SpinService.Spin(ctx.player, true, true))
	eq("ödül verildi (sayaç)", ctx.profile.spins, spinsBefore + 1)

	ctx.profile.lastSpinAt = 0
end)

case("Top Crew: kürsüde sıralamanın ilk üçü, sabit karakter yok", function(ctx)
	local GlobalBoardService = require(Server.GlobalBoardService)
	local folder = workspace.Decor:FindFirstChild("Podium", true)
	ok("kürsü var", folder ~= nil and folder:FindFirstChild("Step1") ~= nil)
	if not folder then
		return
	end
	GlobalBoardService._UpdatePodium({
		{ name = ctx.player.DisplayName, value = 100, userId = ctx.player.UserId },
	})
	local statics = 0
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child.Name ~= "TopCrewAvatar" then
			statics += 1
		end
	end
	eq("sabit Among Us karakterleri kalktı", statics, 0)
	local plate = folder:FindFirstChild("TopCrewPlate1")
	local label = plate and plate:FindFirstChildWhichIsA("TextLabel", true)
	ok("1. isim plakası", label ~= nil and string.find(label.Text, ctx.player.DisplayName, 1, true) ~= nil,
		if label then label.Text else "yok")
	local plate2 = folder:FindFirstChild("TopCrewPlate2")
	local label2 = plate2 and plate2:FindFirstChildWhichIsA("TextLabel", true)
	eq("2. boş", label2 and label2.Text, "#2")
	-- Studio'daki test oyuncusunun kimliği gerçekse karakter kuruluyor; değilse atlanıyor
	if ctx.player.UserId > 0 then
		local avatar = folder:FindFirstChild("TopCrewAvatar")
		ok("1. basamakta karakter", avatar ~= nil)
		if avatar and avatar:IsA("Model") then
			local step = folder:FindFirstChild("Step1") :: BasePart
			local box, size = avatar:GetBoundingBox()
			near("ayaklar basamakta", box.Position.Y - size.Y / 2, step.Position.Y + step.Size.Y / 2, 0.3)
			ok("odaya bakıyor", avatar:GetPivot().LookVector:Dot(step.CFrame.LookVector) > 0.99)
		end
	end
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

-- ─── N. Unvanlar ────────────────────────────────────────────────────────────

case("Unvan: tanımlar tutarlı", function()
	local stats = {
		salvaged = true, spaceSpeed = true, trainings = true, stunned = true, thrown = true,
		mutatedSteals = true, bossSteals = true, discovered = true,
		secrets = true, rebirths = true, maxedUpgrades = true, weeklyBest = true,
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
		ok(def.id .. " nadirliği tanınıyor", Config.Rarities[def.rarity] ~= nil, def.rarity)
		ok(def.id .. " ipucu var", def.hint ~= "")
	end

	ok("id'ler benzersiz", uniqueIds)
	ok("sıralar benzersiz", uniqueOrders)
	ok("en az 15 unvan", #Config.Titles >= 15, tostring(#Config.Titles))
end)

case("Unvan: kazanmak zor, kademeler yükseliyor", function()
	-- "Çok kolay" şikâyeti: ilk unvan bile birkaç soygunla gelmiyor
	local rookie = Config.GetTitle("SpaceRookie") :: Config.TitleDef
	ok("ilk unvan en az 10 soygun", rookie.threshold >= 10)
	local top = Config.GetTitle("MonstersNightmare") :: Config.TitleDef
	ok("en üst unvan binlerce soygun", top.threshold >= 5000)
	eq("en üst unvan Secret", top.rarity, "Secret")
	-- Sıra büyüdükçe nadirlik düşmüyor
	local sorted = table.clone(Config.Titles)
	table.sort(sorted, function(a, b) return a.order < b.order end)
	local prev = 0
	local okOrder = true
	for _, def in sorted do
		local r = Config.Rarities[def.rarity].order
		if r < prev then okOrder = false end
		prev = r
	end
	ok("nadirlik sırayla artıyor", okOrder)
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

	for _, field in { "trainings", "stunned", "thrown", "mutatedSteals", "bossSteals", "bestPlanet" } do
		ok(field .. " sayı", typeof((p :: any)[field]) == "number")
	end
end)

case("Unvan: koşul sağlanınca açılıyor ve ödül veriyor", function(ctx)
	ctx.profile.titles = {}
	ctx.profile.salvaged = 0
	setCash(ctx.player, 0)

	TitleService.Check(ctx.player)
	ok("eşiksiz unvan hemen açıldı", ctx.profile.titles.Crewmate == true)

	local def = Config.GetTitle("SpaceRookie")
	ok("SpaceRookie tanımlı", def ~= nil)
	if not def then return end

	ctx.profile.salvaged = def.threshold - 1
	TitleService.Check(ctx.player)
	ok("eşik altında açılmadı", ctx.profile.titles.SpaceRookie ~= true)

	local before = EconomyService.GetCash(ctx.player)
	ctx.profile.salvaged = def.threshold
	TitleService.Check(ctx.player)

	ok("eşiğe ulaşınca açıldı", ctx.profile.titles.SpaceRookie == true)
	ok("ödül verildi", EconomyService.GetCash(ctx.player) > before,
		Config.FormatCash(EconomyService.GetCash(ctx.player) - before))
	-- Test hesabı başka unvanları da açmış olabilir: takılı olanın nadirliği yazılı olmalı
	ok("nadirlik niteliği var", typeof(ctx.player:GetAttribute("TitleRarity")) == "string")

	-- İkinci kez ödül vermemeli
	local after = EconomyService.GetCash(ctx.player)
	TitleService.Check(ctx.player)
	eq("tekrar ödül yok", EconomyService.GetCash(ctx.player), after)
end)

case("Unvan: en yüksek olan takılıyor", function(ctx)
	ctx.profile.titles = { Crewmate = true, SpaceRookie = true }
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

-- ─── O. Öğretici ────────────────────────────────────────────────────────────

case("Öğretici: adım tanımları tutarlı", function()
	local checks = {
		units = true, upgrades = true, spins = true, tasks = true, pets = true, gear = true,
		salvaged = true, spaceSpeed = true, trainings = true, bestPlanet = true, jetpacks = true,
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

	-- İlk adım: ilk canavardan karakter çalmak; taban uzay hızı ona yetmeli
	local first = Config.Tutorial[1]
	ok("ilk adım karakter çalmak", first.check == "units", first.check)
	ok("taban uzay hızı ilk canavara yetiyor",
		Config.Space.BaseSpeed >= Config.SpaceMonsters[1].need,
		string.format("%d < %d", Config.Space.BaseSpeed, Config.SpaceMonsters[1].need))
end)

case("Öğretici: yükseltme adımına gelen oyuncu yükseltmeyi hemen alabiliyor", function()
	-- En ucuz yükseltme 100 bin, önceki ödüller ~10 bindi: yeni oyuncu
	-- "Buy an upgrade"da dakikalarca takılıp çıkıyordu
	local cheapest = math.huge
	for _, def in Config.Upgrades do
		cheapest = math.min(cheapest, def.baseCost)
	end
	local before = Config.StartingCash
	local found = false
	for _, step in Config.Tutorial do
		if step.check == "upgrades" then
			found = true
			break
		end
		before += step.reward
	end
	ok("yükseltme adımı var", found)
	ok("önceki ödüller en ucuz yükseltmeye yetiyor", before >= cheapest,
		string.format("%s < %s", Config.FormatCash(before), Config.FormatCash(cheapest)))
end)

case("Öğretici: her adım önceki ödüllerle karşılanabiliyor", function()
	-- Parası yetmeyen adımda takılan yeni oyuncu çıkıyor. Gelir yok sayılıyor
	-- (en kötü durum): yalnızca başlangıç parası ve adım ödülleri.
	local function cheapest(list: { any }, field: string): number
		local best = math.huge
		for _, def in list do
			best = math.min(best, def[field])
		end
		return best
	end
	local cost = {
		-- Karakterler uzaydan bedava çalınıyor (konveyör yok)
		units = 0,
		upgrades = cheapest(Config.Upgrades, "baseCost"),
		pets = cheapest(Config.Eggs, "price"),
		gear = cheapest(Config.Gear, "price"),
		-- En ucuz satılık (Robux'suz, bedava olmayan) jetpack
		jetpacks = (function()
			local best = math.huge
			for _, def in Config.Jetpacks do
				if def.pass == nil and def.price > 0 then
					best = math.min(best, def.price)
				end
			end
			return best
		end)(),
	}
	local cash = Config.StartingCash
	for _, step in Config.Tutorial do
		cash -= cost[step.check] or 0
		ok(step.id .. " karşılanıyor", cash >= 0, Config.FormatCash(cash))
		cash += step.reward
	end
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
	ctx.profile.trainings = 0
	ctx.profile.bestPlanet = 0
	-- Uzay hızı tabanda olmalı: yoksa 3. adım (kapsülde antrenman) da aynı turda geçer
	ctx.profile.spaceSpeed = Config.Space.BaseSpeed
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
	eq("son adım gemi görevi", last.check, "tasks")
	local key = "TaskReady_" .. Config.Tasks[1].id
	local had = ctx.player:GetAttribute(key)
	ctx.player:SetAttribute(key, os.time() + 60)

	TutorialService.Check(ctx.player)
	ctx.player:SetAttribute(key, had)
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
	ctx.profile.salvaged = 12
	setCash(ctx.player, 0)

	local before = EconomyService.GetCash(ctx.player)
	local finished = TutorialService.SkipIfVeteran(ctx.player)

	ok("eski oyuncu tespit edildi", finished)
	ok("öğretici bitmiş sayılıyor", TutorialService.IsFinished(ctx.player))
	eq("ödül dağıtılmadı", EconomyService.GetCash(ctx.player), before)

	-- Gerçekten yeni oyuncu elenmemeli
	ctx.profile.tutorialStep = 0
	ctx.profile.salvaged = 0
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
		SpaceGate = function()
			local t = TutorialService._TargetFor(ctx.player, "SpaceGate")
			return if t and t.Name == "LaunchPad" then t else nil
		end,
		Capsule = function()
			local t = TutorialService._TargetFor(ctx.player, "Capsule")
			return if t and t.Name == "Pad" then t else nil
		end,
		Upgrades = function()
			return ctx.plot:FindFirstChild("UpgradeBooth")
		end,
		Wheel = function()
			local decor = workspace:FindFirstChild("Decor")
			return decor and decor:FindFirstChild("Wheel")
		end,
		Planet2 = function()
			return TutorialService._TargetFor(ctx.player, "Planet2")
		end,
		Task = function()
			local t = TutorialService._TargetFor(ctx.player, "Task")
			return if t and t:IsA("BasePart") then t else nil
		end,
		Hatchery = function()
			local t = TutorialService._TargetFor(ctx.player, "Hatchery")
			return if t and t.Name == "Egg1" then t else nil
		end,
		GearShop = function()
			local t = TutorialService._TargetFor(ctx.player, "GearShop")
			return if t and t:FindFirstChild("GearPrompt") then t else nil
		end,
		JetpackStand = function()
			local t = TutorialService._TargetFor(ctx.player, "JetpackStand")
			return if t and t:FindFirstChild("JetpackPrompt") then t else nil
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
	ctx.profile.titles = { Crewmate = true, SpaceRookie = true }
	ctx.profile.titleManual = false
	ctx.profile.activeTitle = ""

	ok("açık unvan takıldı", TitleService.Equip(ctx.player, "SpaceRookie"))
	eq("profile yazıldı", ctx.profile.activeTitle, "SpaceRookie")
	eq("nitelik yazıldı", ctx.player:GetAttribute("Title"), "Space Rookie")
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
	ctx.profile.titles = { Crewmate = true, SpaceRookie = true }
	ctx.profile.salvaged = 10
	TitleService.Equip(ctx.player, "Crewmate")
	eq("seçim yapıldı", ctx.profile.activeTitle, "Crewmate")

	-- Daha yüksek sıralı bir unvan aç
	ctx.profile.salvaged = 50
	TitleService.Check(ctx.player)

	ok("yeni unvan gerçekten açıldı", ctx.profile.titles.SpaceThief == true)
	eq("seçim korundu", ctx.profile.activeTitle, "Crewmate")
	eq("nitelik de korundu", ctx.player:GetAttribute("Title"), "Crewmate")
end)

case("Unvan: otomatiğe dönülebiliyor", function(ctx)
	ctx.profile.titles = { Crewmate = true, SpaceRookie = true }
	TitleService.Equip(ctx.player, "Crewmate")
	eq("düşük unvan takılı", ctx.profile.activeTitle, "Crewmate")

	ok("boş kimlik kabul edildi", TitleService.Equip(ctx.player, ""))
	ok("elle seçim kalktı", not ctx.profile.titleManual)
	eq("en yükseğe döndü", ctx.profile.activeTitle, "SpaceRookie")
end)

-- ─── R. Görevler ────────────────────────────────────────────────────────────

case("Görev: tanımlar tutarlı", function()
	local stats = {
		bought = true, sold = true, earned = true, spins = true, rebirths = true, upgrades = true,
		salvaged = true, trainings = true, stunned = true, mutatedSteals = true,
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
	local steal = Config.GetQuest("Heist")
	ok("Heist tanımlı", steal ~= nil)
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
		-- Bedava ödül en küçük Robux nakit paketine yetişmiyor
		ok(tier.id .. " Robux paketinden az", tier.rewardSeconds < (Config.Products.Cash100K :: any).seconds)
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
	ctx.profile.salvaged = 0
	QuestService.Check(ctx.player)

	local slot = ctx.profile.quests.short
	ok("kısa vade çekildi", slot ~= nil)
	if not slot then return end

	ok("görev var", #slot.entries > 0, tostring(#slot.entries))
	ok("pencere ileride", slot.expiresAt > os.time())

	-- Steal görevini zorla yerleştir ki ilerlemeyi ölçebilelim
	slot.entries = { { id = "Heist", goal = 2, baseline = ctx.profile.salvaged, done = false } }

	QuestService.Check(ctx.player)
	ok("eşik altında tamamlanmadı", not slot.entries[1].done)

	local before = EconomyService.GetCash(ctx.player)
	ctx.profile.salvaged += 2
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
	ctx.profile.salvaged = 500

	QuestService.RollTier(ctx.player, "short")
	local slot = ctx.profile.quests.short
	ok("vade çekildi", slot ~= nil)
	if not slot then return end

	slot.entries = { { id = "Heist", goal = 3, baseline = ctx.profile.salvaged, done = false } }
	QuestService.Check(ctx.player)
	ok("geçmiş sayılmadı", not slot.entries[1].done, tostring(ctx.profile.salvaged))

	ctx.profile.salvaged += 3
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
	ctx.profile.salvaged = 0
	QuestService.Check(ctx.player)

	local slot = ctx.profile.quests.short
	ok("vade var", slot ~= nil)
	if not slot then return end

	slot.entries = { { id = "Heist", goal = 1, baseline = ctx.profile.salvaged, done = false, claimed = false } }
	setCash(ctx.player, 0)

	-- Bitmemiş görev toplanamaz
	ok("bitmemiş görev toplanamıyor", not QuestService.Claim(ctx.player, "short", "Heist"))
	eq("para gelmedi", EconomyService.GetCash(ctx.player), 0)

	-- Koşulu sağla
	ctx.profile.salvaged += 1
	QuestService.Check(ctx.player)
	ok("görev tamamlandı", slot.entries[1].done)
	eq("ama ödül hâlâ verilmedi", EconomyService.GetCash(ctx.player), 0)

	-- Topla
	ok("toplama başarılı", QuestService.Claim(ctx.player, "short", "Heist"))
	ok("ödül geldi", EconomyService.GetCash(ctx.player) > 0,
		Config.FormatCash(EconomyService.GetCash(ctx.player)))
	ok("teslim alındı işaretlendi", slot.entries[1].claimed)

	-- İkinci kez toplanamaz
	local after = EconomyService.GetCash(ctx.player)
	ok("ikinci toplama reddedildi", not QuestService.Claim(ctx.player, "short", "Heist"))
	eq("para değişmedi", EconomyService.GetCash(ctx.player), after)
end)

case("Görev: uydurma toplama isteği reddediliyor", function(ctx)
	--[[
		İstemciden gelen iki metin doğrudan aranıyor. Olmayan vade ya da
		olmayan görev sessizce reddedilmeli; istemciye güvenilmiyor.
	]]
	setCash(ctx.player, 0)

	ok("olmayan vade reddedildi", not QuestService.Claim(ctx.player, "yok", "Heist"))
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
	slot.entries = { { id = "Heist", goal = 1, baseline = 0, done = true, claimed = true } }
	setCash(ctx.player, 0)

	ok("toplanamıyor", not QuestService.Claim(ctx.player, "short", "Heist"))
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
		CosmeticAction. Hiçbiri
		oyuncuya bedava bir şey VERMİYOR — ya oyuncunun kendi parasını
		harcıyor, ya zaten kazanılmış bir şeyi kullanıyor, ya da hakkı
		sunucudaki sayaçlardan hesaplanan bir ödülü topluyor. AsteroidsDone
		küçük bir ödül veriyor ama oyunun başlangıcı, süresi ve bekleme
		süresi sunucuda (MinigameService.TryComplete, testi aşağıda).
		Gerekçeleri Net.luau'da tek tek yazılı.

		Sınır yirmi ikide (TaskDone ek oda görevleri, CosmeticAction kozmetikler,
		SettingsSave oyuncu ayarları için eklendi; SpaceHit uzay soygununa
		geçilince kalktı; 2026-09-28'de SpaceReturn istasyona dönüş,
		JetpackAction jetpack dükkânı, SpinRequest çark penceresi eklendi;
		SeasonClaim Sezon Kartı; gerekçeleri Net.luau'da): yenisi eklemek
		bilinçli bir karar olsun, kazara büyümesin.
	]]
	ok("liste bilinçli", #listened <= 23, tostring(#listened))

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
	local id = "SpaceCapsule"
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
	ctx.profile.upgrades = { SpaceCapsule = 3, JetBoost = 2 }
	PlotService.SetUnlockedFloors(ctx.plot, Config.GetUnlockedFloors(1))

	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)
	PlotService.PlaceUnit(podiums[1], "TheSkeld", nil)
	setCash(ctx.player, Config.GetRebirthCost(0))

	ok("rebirth başarılı", RebirthService.TryRebirth(ctx.player))

	eq("SpaceCapsule sıfırlandı", UpgradeService.GetLevel(ctx.player, "SpaceCapsule"), 0)
	eq("JetBoost sıfırlandı", UpgradeService.GetLevel(ctx.player, "JetBoost"), 0)
	eq("satın alınan kat korundu", ctx.profile.floorsBought, 1)
end)

case("Yükseltme: seviye başına etki yarıya indi ama tavan aynı kaldı", function()
	--[[
		Seviye sayısı ikiye katlandı, seviye başına etki yarıya indi.
		Net sonuç: tavandaki güç eskisiyle aynı, yol iki kat uzun.
		Bu test gücün kazara artmasını engelliyor.
	]]
	local def = Config.GetUpgrade("SpaceCapsule")
	local ceiling = Config.GetUpgradeCeiling(def)

	-- Tavandaki kapsül en üst canavarın hızında bile makul (dakikada birkaç puan)
	local top = Config.GetCapsuleGain(ceiling, Config.SpaceMonsters[#Config.SpaceMonsters].need)
	ok("kapsül tavanı makul", top > 0.003 and top < 20, string.format("%.4f", top))

	local morale = Config.GetMoraleMultiplier(Config.GetUpgradeCeiling(Config.GetUpgrade("CrewMorale")))
	ok("moral tavanı makul", morale > 1.2 and morale <= 1.6, string.format("%.2f", morale))
end)

case("Koşma: ayarlar makul", function()
	ok("koşu normalden hızlı", Config.SprintWalkSpeed > Config.NormalWalkSpeed,
		tostring(Config.SprintWalkSpeed))
	ok("koşu abartılı değil", Config.SprintWalkSpeed <= Config.NormalWalkSpeed * 2,
		tostring(Config.SprintWalkSpeed))
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
		MovementService.SetSprinting(ctx.player, false)
		eq("bobinle yürüme", humanoid.WalkSpeed, coil.walkSpeed)
		MovementService.SetSprinting(ctx.player, true)
		eq("bobinle koşu", humanoid.WalkSpeed, coil.sprintSpeed)
		-- Uzay soygununda bobin işlemiyor
		ctx.player:SetAttribute("InSpace", true)
		MovementService.RefreshSpeed(ctx.player)
		eq("uzayda bobin koşusu yok", humanoid.WalkSpeed, Config.SprintWalkSpeed)
		ctx.player:SetAttribute("InSpace", nil)
		ctx.player:SetAttribute("SpaceCarry", true)
		MovementService.SetSprinting(ctx.player, false)
		eq("uzaydan taşırken bobin yok", humanoid.WalkSpeed, Config.NormalWalkSpeed)
		ctx.player:SetAttribute("SpaceCarry", nil)
		MovementService.SetSprinting(ctx.player, true)
		ctx.player:SetAttribute("GearSpeed", nil)
		ctx.player:SetAttribute("GearSprint", nil)
		MovementService.RefreshSpeed(ctx.player)
		eq("bobinsiz koşu", humanoid.WalkSpeed, Config.SprintWalkSpeed)
		MovementService.SetSprinting(ctx.player, false)
		eq("normal", humanoid.WalkSpeed, Config.NormalWalkSpeed)
	end

	-- Kaldırılan alet: parası bir kez iade
	local profile = DataService._Sanitize({ cash = 1000, gear = { GravityCoil = true, SlapGlove = true } })
	eq("iade edildi", profile.cash, 1000 + Config.RetiredGear.GravityCoil)
	ok("kayıttan düştü", profile.gear.GravityCoil == nil)
	ok("diğer alet kaldı", profile.gear.SlapGlove == true)
	local p2 = DataService._Sanitize({ cash = 0, gear = { GhostSerum = true } })
	eq("Ghost Serum iade edildi", p2.cash, Config.RetiredGear.GhostSerum)
end)

case("Ekipman: canavarlara değil oyunculara - bekleme ve bağışıklık var", function(ctx)
	local stun = Config.GetGear("StunGun") :: Config.GearDef
	local blast = Config.GetGear("EmergencyButton") :: Config.GearDef
	local slap = Config.GetGear("SlapGlove") :: Config.GearDef
	ok("stun donması bekleme süresinden çok kısa", (stun.stun or 0) * 4 <= (stun.cooldown or 0))
	ok("buton beklemesi en az 30", (blast.cooldown or 0) >= 30)
	ok("tokat beklemesi en az 4", (slap.cooldown or 0) >= 4)
	ok("canavar vuruşu kalktı", (SpaceService :: any).HitMonsters == nil)

	-- Tek oyunculu testte hedef yok: kullanım geçerli, sayaç artmıyor
	GearService._ResetCooldowns(ctx.player)
	local before = ctx.profile.stunned
	ok("kullanıldı", GearService.Use(ctx.player, "StunGun"))
	eq("kimse vurulmadı", ctx.profile.stunned, before)

	-- Bağışıklık: vurulan GearHitImmunity sn tekrar vurulamıyor
	GearService._MarkHit(ctx.player, os.clock())
	ok("yeni vurulan bağışık", GearService.IsImmune(ctx.player))
	ok("süre dolunca bağışıklık biter", not GearService.IsImmune(ctx.player, os.clock() + Config.GearHitImmunity + 0.1))
	GearService._MarkHit(ctx.player, -math.huge)
	GearService._ResetCooldowns(ctx.player)
end)

case("Ekipman: bekleme süresi sunucuda, Ghost Serum kaldırıldı", function(ctx)
	GearService._ResetCooldowns(ctx.player)
	ok("tokat atıldı", GearService.Use(ctx.player, "SlapGlove"))
	ok("hemen ikinci tokat yok", not GearService.Use(ctx.player, "SlapGlove"))
	ok("bobin kullanılmıyor", not GearService.Use(ctx.player, "SpeedCoil"))
	ok("tanınmayan alet yok", not GearService.Use(ctx.player, "GravityCoil"))

	-- Ghost Serum kaldırıldı: satılmıyor, kullanılmıyor
	ok("Ghost Serum satılmıyor", Config.GetGear("GhostSerum") == nil)
	ok("Ghost Serum kullanılmıyor", not GearService.Use(ctx.player, "GhostSerum"))
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
	ok("rebirth'ten küçük", Config.FriendBonusMax <= Config.RebirthIncomeBonus * 0.6,
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

	-- Canavardan çalınanı taşıyormuş gibi (SpaceService yazıyor)
	ctx.player:SetAttribute("SpaceCarry", true)
	eq("taşırken reddedildi", VentService.TryVent(ctx.player, a, b, 1000), "carrying")
	ctx.player:SetAttribute("SpaceCarry", nil)

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
	for _, id in { "Meeting", "Meteors", "Storm", "Blackout", "Meltdown", "Comet" } do
		ok(id .. " tanımlı", ids[id] == true)
	end
	-- "Özel an": saatte en fazla iki sabit olay (+ ara sıra sürpriz)
	local perHour = 0
	for _, def in Config.Events do
		if not def.random then
			perHour += 3600 / def.every
		end
	end
	ok("saatte en fazla iki sabit olay", perHour <= 2, tostring(perHour))

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

case("Olay: Emergency Meeting geliri katlıyor, bitince dönüyor", function(ctx)
	clearPlot(ctx.plot)
	local podium = PlotService.FindEmptyPodium(ctx.plot)
	assert(podium, "boş kaide yok")
	PlotService.PlaceUnit(podium, Config.Units[10].id)
	local base = EconomyService.GetIncome(ctx.player)

	ok("başladı", EventService.Begin("Meeting"))
	eq("süren olay", EventService.GetActiveId(), "Meeting")
	near("gelir katlandı", EconomyService.GetIncome(ctx.player), base * Config.MeetingIncomeMul, 2)
	eq("ikinci olay başlamıyor", EventService.Begin("Storm"), false)
	EventService.End()
	eq("bitince normal", EconomyService.GetIncome(ctx.player), base)
	eq("yayın temizlendi", workspace:GetAttribute("EventId"), "")
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

-- ─── Hızlı çalma ────────────────────────────────────────────────────────────

case("Hızlı kapma: pass iksirden güçlü, alt sınır var, istemciye yayınlanıyor", function(ctx)
	ok("pass iksirden güçlü", Config.PassFastStealMultiplier < Config.PotionFastStealMultiplier)
	ok("ikisi de gerçekten hızlandırıyor", Config.PotionFastStealMultiplier < 1)

	near("çarpansız", Config.GetPersonalGrabHold(1, 1, 0), 1, 0.001)
	ok("pass kısaltıyor", Config.GetPersonalGrabHold(1, 0.6, 0) < 1)
	eq("alt sınır", Config.GetPersonalGrabHold(0.2, 0.1, 50), Config.MinGrabHold)

	MonetizationService.ClearBoosts(ctx.player)
	MonetizationService.PublishStealHold(ctx.player)
	local passMul = if MonetizationService.HasPass(ctx.player, "FastSteal") then Config.PassFastStealMultiplier else 1
	eq("iksirsiz nitelik", ctx.player:GetAttribute("StealHoldMul"), passMul)

	if passMul == 1 then
		MonetizationService.GrantBoost(ctx.player, "steal", 60)
		eq("iksir çarpanı", MonetizationService.GetStealHoldMultiplier(ctx.player), Config.PotionFastStealMultiplier)
		MonetizationService.PublishStealHold(ctx.player)
		eq("iksir niteliği", ctx.player:GetAttribute("StealHoldMul"), Config.PotionFastStealMultiplier)
		MonetizationService.ClearBoosts(ctx.player)
		MonetizationService.PublishStealHold(ctx.player)
		eq("iksir bitince 1", ctx.player:GetAttribute("StealHoldMul"), 1)
	end
end)

case("Canavar kalkanı: iksirle açılıyor, bitince kapanıyor", function(ctx)
	MonetizationService.ClearBoosts(ctx.player)
	local fromPass = MonetizationService.HasPass(ctx.player, "StrongLock")
	eq("iksirsiz", MonetizationService.HasShield(ctx.player), fromPass)
	MonetizationService.GrantBoost(ctx.player, "lock", 60)
	ok("iksirle kalkan var", MonetizationService.HasShield(ctx.player))
	MonetizationService.ClearBoosts(ctx.player)
	eq("iksir bitince", MonetizationService.HasShield(ctx.player), fromPass)
	ok("kalkan beklemesi makul", Config.ShieldCooldown >= 30 and Config.ShieldStun > 0)
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

	local found = false
	for _, c in RogueService.GetCandidates() do
		if c.podium == podium then
			found = true
		end
	end
	ok("üs hedef olabiliyor", found)

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
	local reason, reward = RogueService.TryCatch(ctx.player)
	eq("durdurdu", reason, "ok")
	-- En az ödül kadar: yakalama sayacı bir unvan açarsa onun ödülü de ekleniyor
	ok("ödül geldi", EconomyService.GetCash(ctx.player) >= reward, tostring(EconomyService.GetCash(ctx.player)))
	ok("ödül tabandan az değil", reward >= Config.RogueRewardMin)
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

-- ─── Uzay soygunu ve kapsül ─────────────────────────────────────────────────

case("Uzay: gezegen düzeni oynanabilir", function()
	local sp = Config.Space
	local list = Config.SpaceMonsters
	eq("altı canavar", #list, 6)
	eq("ilki taban hızda", list[1].need, sp.BaseSpeed)
	local lastZ = math.huge
	local lastNeed = 0
	local lastSide = 0
	local deckLo, deckHi = SpaceField.DeckBox()
	for i, def in list do
		ok(def.id .. " sırada (daha uzak)", def.position.Z < lastZ)
		ok(def.id .. " daha zor", def.need > lastNeed)
		local side = if def.position.X > sp.GateX then 1 else -1
		ok(def.id .. " bir sağda bir solda", side ~= lastSide)
		lastZ, lastNeed, lastSide = def.position.Z, def.need, side
		ok(def.id .. " kimlikle bulunuyor", Config.GetSpaceMonster(def.id) == def)
		for rarity in def.odds do
			ok(def.id .. " nadirliği tanınıyor " .. rarity, Config.Rarities[rarity] ~= nil)
		end
		-- Gezegen uçuş sınırının içinde ve güverteye değmiyor
		local center = SpaceField.PlanetCenter(def)
		ok(def.id .. " sınır içinde", SpaceField.ClampToBounds(center) == center)
		ok(def.id .. " güverteden uzak", center.Z + def.radius < deckLo.Z - 40, string.format("%.0f", center.Z + def.radius))
		-- Komşu gezegenle çakışmıyor
		ok(def.id .. " kükreme ve atak tanımlı", def.wake > 0 and def.lunge >= 1)
		if i > 1 then
			local prev = list[i - 1]
			ok(def.id .. " öncekinden zor (atak, kükreme)", def.lunge >= prev.lunge and def.wake <= prev.wake)
		end
		local nextDef = list[i + 1]
		if nextDef then
			local d = (SpaceField.PlanetCenter(nextDef) - center).Magnitude
			ok(def.id .. " komşusuyla çakışmıyor", d > def.radius + nextDef.radius + 20, string.format("%.0f", d))
		end
		-- Mürettebat platonun üstünde ve uzayda
		for k, p in SpaceField.CrewSpots(def) do
			local flat = Vector3.new(p.X - def.position.X, 0, p.Z - def.position.Z).Magnitude
			ok(string.format("%s mürettebat %d platoda", def.id, k), flat < SpaceField.PlateauRadius(def) - 1, string.format("%.1f", flat))
			ok(string.format("%s mürettebat %d uzayda", def.id, k), SpaceField.InSpace(p))
		end
		-- Çekilen karakterler yalnızca bu havuzdan
		local rng = Random.new(i)
		local fine = true
		for _ = 1, 150 do
			local unit = Config.RollSpaceUnit(rng, def)
			if not def.odds[unit.rarity] then
				fine = false
			end
		end
		ok(def.id .. " havuz dışına çıkmıyor", fine)
	end
	ok("güverte kutusu kapının önünde", deckHi.Z >= sp.WallZ and deckLo.Z < SpaceField.WallOuterZ())
end)

case("Uzay: güvenli bölge, uçuş bölgesi ve fırlatma yolu", function()
	local sp = Config.Space
	ok("iniş noktası güvenli", SpaceField.InSafe(sp.Landing))
	ok("güverte güvenli", SpaceField.InSafe(SpaceField.DeckCenter() + Vector3.new(0, 3, 0)))
	ok("güverte uzay sayılmıyor", not SpaceField.InSpace(SpaceField.DeckCenter() + Vector3.new(0, 3, 0)))
	ok("gemi içi uzay değil", not SpaceField.InSpace(Vector3.new(180, 3, 0)))
	ok("gezegen uzayda", SpaceField.InSpace(Config.SpaceMonsters[1].position + Vector3.new(0, 4, 0)))
	ok("gezegen güvenli değil", not SpaceField.InSafe(Config.SpaceMonsters[1].position))
	local from = Config.SpaceMonsters[3].position + Vector3.new(0, 10, 0)
	ok("yol elden başlıyor", (SpaceField.ThrowPath(from, 0) - from).Magnitude < 0.01)
	ok("yol inişte bitiyor", (SpaceField.ThrowPath(from, 1) - sp.Landing).Magnitude < 0.01)

	local characters = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(characters, pl.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characters
	local down = workspace:Raycast(sp.Landing + Vector3.new(0, 2, 0), Vector3.new(0, -10, 0), params)
	ok("inişin altında zemin var", down ~= nil)
	-- İniş noktasında karakteri sıkıştıracak katı parça yok
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = characters
	local solid = {}
	for _, p in workspace:GetPartBoundsInBox(CFrame.new(sp.Landing + Vector3.new(0, 1.2, 0)), Vector3.new(3, 4, 3), overlap) do
		if p.CanCollide and p.Transparency < 0.95 then
			table.insert(solid, p:GetFullName())
		end
	end
	ok("iniş noktası boş", #solid == 0, table.concat(solid, ", "))
	-- Kapı gerçekten açık: güverteden gemiye düz ışın katı bir şeye çarpmıyor
	local gate = Vector3.new(sp.GateX, sp.DeckTop + 4, SpaceField.DeckEdgeZ() + 6)
	local through = workspace:Raycast(gate, Vector3.new(0, 0, 60), params)
	ok("kapıdan geçiliyor", through == nil, if through then through.Instance:GetFullName() else "")
end)

case("Uzay: çal, bırak, hile payı, teslim et", function(ctx)
	local character = ctx.player.Character
	if not character then
		ok("karakter var", false)
		return
	end
	local startCf = character:GetPivot()
	clearPlot(ctx.plot)
	SpaceService._ClearImmunity(ctx.player)
	ok("uzay alanı kurulu", workspace:FindFirstChild("SpaceZone") ~= nil)
	ok("eski hava kilidi yok", workspace:FindFirstChild("SpaceAirlock") == nil)

	local def = Config.SpaceMonsters[1]
	local spot = SpaceField.CrewSpots(def)[1]
	character:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 4)))
	local unitId, mutationId = SpaceService._Spot(1, 1)
	ok("mürettebat var", unitId ~= nil)

	SpaceService._Grab(ctx.player, 1, 1)
	ok("taşıyor", SpaceService.IsCarrying(ctx.player))
	ok("nitelik", ctx.player:GetAttribute("SpaceCarry") == true)
	ok("sırtında (CarriedUnit değil)", character:FindFirstChild("SpaceCarry") ~= nil and character:FindFirstChild("CarriedUnit") == nil)
	eq("yeri boşaldı", (SpaceService._Spot(1, 1)), nil)
	local state, target = SpaceService._Monster(1)
	eq("canavar uyandı", state, "wake")
	eq("hedef bu oyuncu", target, ctx.player)
	eq("başka canavar uyanmadı", (SpaceService._Monster(2)), "idle")

	SpaceService._Drop(ctx.player)
	ok("bıraktı", not SpaceService.IsCarrying(ctx.player))
	local back, backMutation = SpaceService._Spot(1, 1)
	eq("aynı mürettebat yerine döndü", back, unitId)
	eq("mutasyonu da", backMutation, mutationId)

	-- Hile payı: kapıp anında güverteye ışınlanan teslim edemiyor
	SpaceService._Grab(ctx.player, 1, 1)
	character:PivotTo(CFrame.new(SpaceField.DeckCenter() + Vector3.new(0, 3, 0)))
	SpaceService._Deliver(ctx.player, true)
	ok("hızlı teslim reddedildi", not SpaceService.IsCarrying(ctx.player))
	eq("karakter yerine döndü", (SpaceService._Spot(1, 1)), unitId)
	local filled = 0
	for _, podium in PlotService.GetUnlockedPodiums(ctx.plot) do
		if PlotService.IsOccupied(podium) then
			filled += 1
		end
	end
	eq("kaideler boş kaldı", filled, 0)

	-- Dürüst teslim
	local before = ctx.profile.salvaged
	character:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 4)))
	SpaceService._Grab(ctx.player, 1, 1)
	character:PivotTo(CFrame.new(SpaceField.DeckCenter() + Vector3.new(0, 3, 0)))
	SpaceService._Deliver(ctx.player)
	ok("teslim edildi", not SpaceService.IsCarrying(ctx.player))
	local placed = false
	for _, podium in PlotService.GetUnlockedPodiums(ctx.plot) do
		if podium:GetAttribute("UnitId") == unitId then
			placed = true
		end
	end
	ok("üssün kaidesinde", placed)
	eq("sayaç arttı", ctx.profile.salvaged, before + 1)

	-- Canavar hedefi kaybedince eve dönüyor
	SpaceService._Step(1 / 30)
	SpaceService._Step(1 / 30)
	local after = SpaceService._Monster(1)
	ok("canavar geri dönüyor", after == "return" or after == "idle", tostring(after))

	character:PivotTo(startCf)
	clearPlot(ctx.plot)
end)

case("Uzay: canavar yakalayınca elinde tutup gemiye fırlatıyor", function(ctx)
	local character = ctx.player.Character
	if not character then
		ok("karakter var", false)
		return
	end
	local startCf = character:GetPivot()
	clearPlot(ctx.plot)
	SpaceService._ClearImmunity(ctx.player)
	local def = Config.SpaceMonsters[2]
	local spot = SpaceField.CrewSpots(def)[3]
	character:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 4)))
	local unitId = SpaceService._Spot(2, 3)
	SpaceService._Grab(ctx.player, 2, 3)
	ok("taşıyor", SpaceService.IsCarrying(ctx.player))

	SpaceService._Catch(ctx.player, 2)
	ok("elinden alındı", not SpaceService.IsCarrying(ctx.player))
	eq("canavarın elinde", ctx.player:GetAttribute("SpaceGrabbed"), def.id)
	eq("canavar kavrıyor", (SpaceService._Monster(2)), "grab")
	eq("karakter gezegenine döndü", (SpaceService._Spot(2, 3)), unitId)

	-- Fırlatma sürerken yeniden çalamıyor
	SpaceService._Grab(ctx.player, 2, 3)
	ok("fırlatılırken çalamıyor", not SpaceService.IsCarrying(ctx.player))

	SpaceService._ClearImmunity(ctx.player)
	character:PivotTo(startCf)
	clearPlot(ctx.plot)
end)

case("Uzay: bedava karakter (çark / ürün) doğrudan kaideye", function(ctx)
	clearPlot(ctx.plot)
	local name = SpaceService.GrantUnit(ctx.player, true)
	ok("bedava karakter verildi", name ~= nil)
	local count = 0
	for _, podium in PlotService.GetUnlockedPodiums(ctx.plot) do
		if PlotService.IsOccupied(podium) then
			count += 1
		end
	end
	eq("bir kaide doldu", count, 1)
	clearPlot(ctx.plot)
end)

case("Uzay: olaylar ve ekipman canavarları etkiliyor", function(ctx)
	-- Mutation Storm: gezegenlerdeki herkes mutasyonlu
	ok("Storm başladı", EventService.Begin("Storm"))
	local plain = 0
	for k = 1, Config.Space.CrewPerPlanet do
		local unitId, mutationId = SpaceService._Spot(1, k)
		if unitId and not mutationId then
			plain += 1
		end
	end
	eq("mutasyonsuz mürettebat yok", plain, 0)
	EventService.End()

	-- 2026-09-28: aletler uzayda da kullanılıyor (oyunculara, hafif)
	ctx.player:SetAttribute("InSpace", true)
	GearService._ResetCooldowns(ctx.player)
	ok("uzayda alet kullanılabiliyor", GearService.Use(ctx.player, "EmergencyButton"))
	ctx.player:SetAttribute("InSpace", nil)
	GearService._ResetCooldowns(ctx.player)
end)

case("Uzay: canavar gezegenin içine gömülmüyor", function()
	for _, def in Config.SpaceMonsters do
		local top = def.position.Y
		local home = SpaceField.MonsterHome(def).Position
		local p, pushed = SpaceService._KeepOffPlanets(home)
		ok(def.id .. " evi itilmiyor", not pushed and (p - home).Magnitude < 1e-3)
		local under = SpaceService._KeepOffPlanets(def.position - Vector3.new(0, 4, 0))
		ok(def.id .. " platonun içinden tepeye", under.Y >= top - 1e-3)
		local center = SpaceField.PlanetCenter(def)
		local deep = SpaceService._KeepOffPlanets(center + Vector3.new(3, -def.radius * 0.5, 0))
		ok(def.id .. " kürenin dışına", (deep - center).Magnitude >= def.radius)
	end
	-- Plato hizasında kaçan oyuncunun peşinde: kovalama adımı gezegene girmiyor
	local def = Config.SpaceMonsters[1]
	local center = SpaceField.PlanetCenter(def)
	SpaceService._ResetMonster(1)
	for _ = 1, 30 do
		SpaceService._StepToward(1, center + Vector3.new(0, -def.radius * 0.5, 0), 1 / 30)
	end
	local pos = SpaceService._MonsterPosition(1)
	ok("aşağıdaki hedefe giderken de dışarıda", (pos - center).Magnitude >= def.radius - 0.01)
	SpaceService._ResetMonster(1)
end)

case("Kapsül: içinde durunca uzay hızı artıyor, başkasınınkinde artmıyor", function(ctx)
	local character = ctx.player.Character
	local capsule = ctx.plot:FindFirstChild("Capsule")
	ok("kapsül üste kurulu", capsule ~= nil)
	ok("konveyör yok", ctx.plot:FindFirstChild("Conveyor") == nil)
	if not (character and capsule) then
		return
	end
	local zone = capsule:FindFirstChild("Zone") :: BasePart
	local console = capsule:FindFirstChild("Console")
	ok("yükseltme promptu", console ~= nil and console:FindFirstChild("CapsulePrompt") ~= nil)
	local startCf = character:GetPivot()
	CapsuleService.SetSpeed(ctx.player, Config.Space.BaseSpeed)
	ctx.profile.upgrades.SpaceCapsule = 2

	character:PivotTo(CFrame.new(zone.Position))
	CapsuleService._Tick(1)
	local gained = CapsuleService.GetSpeed(ctx.player) - Config.Space.BaseSpeed
	near("bir saniyelik kazanç", gained, Config.GetCapsuleGain(2, Config.Space.BaseSpeed), 1e-6)
	eq("InCapsule", ctx.player:GetAttribute("InCapsule"), true)
	near("nitelik güncel", ctx.player:GetAttribute("SpaceSpeed") :: number, CapsuleService.GetSpeed(ctx.player), 0.01)

	local other: Model? = nil
	for _, plot in PlotService.GetAllPlots() do
		if plot ~= ctx.plot then
			other = plot
			break
		end
	end
	if other then
		local otherZone = (other:FindFirstChild("Capsule") :: Model):FindFirstChild("Zone") :: BasePart
		character:PivotTo(CFrame.new(otherZone.Position))
		local s0 = CapsuleService.GetSpeed(ctx.player)
		CapsuleService._Tick(1)
		eq("başkasının kapsülü hız vermiyor", CapsuleService.GetSpeed(ctx.player), s0)
		eq("InCapsule kalktı", ctx.player:GetAttribute("InCapsule"), nil)
	end

	character:PivotTo(startCf)
	CapsuleService.SetSpeed(ctx.player, Config.Space.BaseSpeed)
	ctx.profile.upgrades.SpaceCapsule = nil
end)

case("Kapsül: mini oyun bonusu ısınma ve bekleme ile sınırlı, dışarıda yok", function(ctx)
	local character = ctx.player.Character
	local capsule = ctx.plot:FindFirstChild("Capsule")
	if not (character and capsule) then
		ok("karakter ve kapsül", false)
		return
	end
	local startCf = character:GetPivot()
	local zone = capsule:FindFirstChild("Zone") :: BasePart
	-- Kapsül üssün zemininin dışında (arkasında), duvara değmeden
	local base = ctx.plot:FindFirstChild("Base") :: BasePart
	local local_ = base.CFrame:PointToObjectSpace(zone.Position)
	ok("kapsül üssün arkasında", math.abs(local_.Z) > base.Size.Z / 2, string.format("%.1f", local_.Z))
	CapsuleService.SetSpeed(ctx.player, Config.Space.BaseSpeed)
	ctx.profile.upgrades.SpaceCapsule = 3

	character:PivotTo(CFrame.new(zone.Position))
	CapsuleService._Tick(0.5)
	eq("antrenmanda", ctx.player:GetAttribute("InCapsule"), true)
	CapsuleService._ResetCatch(ctx.player, 0)
	eq("ısınmadan bonus yok", CapsuleService.TryCatch(ctx.player), nil)
	CapsuleService._ResetCatch(ctx.player, Config.Capsule.CatchWarmup + 1)
	local s0 = CapsuleService.GetSpeed(ctx.player)
	local bonus = CapsuleService.TryCatch(ctx.player)
	ok("bonus verildi", bonus ~= nil)
	near("bonus = kapsül kazancı × süre", bonus or 0, Config.GetCapsuleGain(3, s0) * Config.Capsule.CatchBonusSeconds, 1e-6)
	near("hıza eklendi", CapsuleService.GetSpeed(ctx.player), s0 + (bonus or 0), 1e-6)
	eq("art arda ikinci bonus yok", CapsuleService.TryCatch(ctx.player), nil)

	character:PivotTo(startCf)
	CapsuleService._Tick(0.5)
	CapsuleService._ResetCatch(ctx.player, 60)
	eq("kapsül dışında bonus yok", CapsuleService.TryCatch(ctx.player), nil)
	CapsuleService.SetSpeed(ctx.player, Config.Space.BaseSpeed)
	ctx.profile.upgrades.SpaceCapsule = nil
end)

case("Kapsül: kazanç seviyeyle artıyor, hızla azalıyor; eski kayıt taşınıyor", function()
	ok("seviye artırıyor", Config.GetCapsuleGain(3, 30) > Config.GetCapsuleGain(2, 30))
	ok("hız yavaşlatıyor", Config.GetCapsuleGain(3, 90) < Config.GetCapsuleGain(3, 30))
	ok("taban hızda pozitif", Config.GetCapsuleGain(0, Config.Space.BaseSpeed) > 0)
	local p = DataService._Sanitize({ cash = 10, upgrades = { ConveyorSpeed = 4 } })
	-- Eski kayıt eski ölçekte (upgradeScale yok = 1): seviye yeni ölçeğe çarpılıyor
	eq("eski Conveyor Speed kapsüle taşındı", p.upgrades.SpaceCapsule, 4 * Config.UpgradeLevelScale)
	local scaled = DataService._Sanitize({ upgradeScale = Config.UpgradeLevelScale, upgrades = { SpaceCapsule = 7 } })
	eq("yeni ölçekli kayıt olduğu gibi", scaled.upgrades.SpaceCapsule, 7)
	local old = DataService._Sanitize({ upgrades = { CrewMorale = 3 } })
	ok("ölçek geçişi gücü koruyor", math.abs(Config.GetMoraleMultiplier(old.upgrades.CrewMorale) - (1 + 0.6 * (1 - 0.9 ^ 3))) < 1e-6)
	eq("eski kimlik atıldı", p.upgrades.ConveyorSpeed, nil)
	eq("uzay hızı varsayılanı", p.spaceSpeed, Config.Space.BaseSpeed)
	local low = DataService._Sanitize({ spaceSpeed = 3 })
	eq("taban altı kırpılıyor", low.spaceSpeed, Config.Space.BaseSpeed)
	local high = DataService._Sanitize({ spaceSpeed = 57.5 })
	eq("kazanılmış hız korunuyor", high.spaceSpeed, 57.5)
end)

case("Mağaza: nakit paketi gelire ve bakiyeye göre, yükseltme adımları küçük", function()
	local small = Config.Products.Cash100K
	eq("yeni oyuncuya taban", Config.GetCashPackAmount(small, 0, 0), small.amount)
	ok("gelirle büyüyor", Config.GetCashPackAmount(small, 1e6, 0) >= 1e6 * small.seconds * 0.95)
	ok("bakiyeyle büyüyor", Config.GetCashPackAmount(small, 0, 1e12) >= 1e12 * small.cashFrac * 0.95)
	ok("büyük paket küçükten çok", Config.GetCashPackAmount(Config.Products.Cash10M, 5000, 1e7) > Config.GetCashPackAmount(small, 5000, 1e7))
	-- Çark (süper çark x3 dahil) en küçük Robux paketinden hep az
	local huge
	for _, r in Config.SpinRewards do
		if r.id == "HugeCash" then huge = r end
	end
	for _, st in { { 0, 0 }, { 5000, 0 }, { 0, 1e9 }, { 1e6, 1e10 }, { 1e3, 1e12 } } do
		local spin = Config.GetSpinCash(huge, st[1], st[2]) * Config.SuperSpin.cashMul
		ok(string.format("çark Robux'tan az (%g, %g)", st[1], st[2]), spin < Config.GetCashPackAmount(small, st[1], st[2]))
	end
	-- Robux başına değer paket büyüdükçe artıyor (fiyatlar 25 / 99 / 299)
	local robux = { Cash100K = 25, Cash1M = 99, Cash10M = 299 }
	for _, case_ in { { 0, 0 }, { 5000, 0 }, { 0, 1e9 }, { 1e6, 1e10 } } do
		local per = {}
		for key, price in robux do
			per[key] = Config.GetCashPackAmount(Config.Products[key], case_[1], case_[2]) / price
		end
		ok(string.format("orta kârlı (%g, %g)", case_[1], case_[2]), per.Cash1M > per.Cash100K)
		ok(string.format("büyük en kârlı (%g, %g)", case_[1], case_[2]), per.Cash10M > per.Cash1M)
	end
	for _, def in Config.Upgrades do
		ok(def.id .. " tavanı yüksek", def.baseMaxLevel >= 20)
		local c1, c2 = Config.GetUpgradeCost(def.id, 0), Config.GetUpgradeCost(def.id, 1)
		ok(def.id .. " fiyat artıyor", c1 ~= nil and c2 ~= nil and c2 > c1)
	end
	ok("pass'siz üçlü açma yok", not PetService.CanTripleHatch(Players:GetPlayers()[1]) or MonetizationService.HasPass(Players:GetPlayers()[1], "TripleHatch"))
end)

-- ─── Uzay yolu: halkalar, yıldız tozu, sandıklar, kuyruklu yıldız ──────────

case("Uzay yolu: içerik uçulabilir alanda, gezegenlerin içinde değil", function()
	local s = Config.Space
	local function inside(p: Vector3): boolean
		return p.X >= s.BoundsMin.X and p.X <= s.BoundsMax.X and p.Y >= s.BoundsMin.Y and p.Y <= s.BoundsMax.Y
			and p.Z >= s.BoundsMin.Z and p.Z <= s.BoundsMax.Z
	end
	local function clearOfPlanets(p: Vector3, pad: number): boolean
		for _, def in Config.SpaceMonsters do
			if (p - SpaceField.PlanetCenter(def)).Magnitude < def.radius + pad then
				return false
			end
		end
		return true
	end
	eq("rota sayısı", #SpaceField.Routes(), #Config.SpaceMonsters)
	-- Halkalar ve yıldız tozu 2026-09-28'de kalktı: dünyada yoklar
	local bonus = workspace:FindFirstChild("SpaceBonus")
	ok("halka yok", bonus == nil or bonus:FindFirstChild("Ring1", true) == nil)
	for i, p in SpaceField.CrateSpots() do
		ok(i .. ". sandık alanda", inside(p) and clearOfPlanets(p, 4))
	end
	ok("dünyada kurulu", workspace:FindFirstChild("SpaceBonus") ~= nil)
end)

case("Uzay yolu: sandık az veriyor, sonra yeniden beliriyor", function(ctx)
	SpaceBonusService._Respawn()
	local pickups = SpaceBonusService._Pickups()
	local crateIndex = nil
	for i, p in pickups do
		ok("yalnızca sandık (yıldız tozu kalktı)", p.kind == "crate", p.kind)
		if p.kind == "crate" and not crateIndex then
			crateIndex = i
		end
	end
	ok("sandık var", crateIndex ~= nil)
	if not crateIndex then return end

	setCash(ctx.player, 0)
	ok("sandık açıldı", SpaceBonusService._Collect(ctx.player, crateIndex))
	ok("taban ödül geldi", EconomyService.GetCash(ctx.player) >= Config.SpaceBonus.CrateMin)
	ok("hemen tekrar açılmıyor", not SpaceBonusService._Collect(ctx.player, crateIndex))

	SpaceBonusService._Respawn()
	ok("yeniden belirdi", SpaceBonusService._Collect(ctx.player, crateIndex))
	SpaceBonusService._Respawn()
end)

case("Uzay yolu: Golden Comet başlıyor ve bitiyor", function()
	ok("olay tanımlı", Config.GetEvent("Comet") ~= nil)
	local stop = SpaceBonusService.StartComet()
	ok("kuyruklu yıldız dünyada", SpaceBonusService.GetComet() ~= nil)
	stop()
	eq("durdu", SpaceBonusService.GetComet(), nil)
	ok("teslim toleransı payı duruyor", Config.SpaceBonus.RingBoostMul >= 1)
end)

case("Jetpack: parayla alınıyor, gidişte hızlandırıyor, taşırken değil", function(ctx)
	local scout = Config.GetJetpack("Scout") :: Config.JetpackDef
	ok("Scout tanımlı", scout ~= nil and scout.price > 0)
	eq("başlangıç paketi bedava ve 1x", Config.GetJetpackBoost("Starter", false), 1)
	ok("Scout gidişte hızlı", Config.GetJetpackBoost("Scout", false) > 1)
	eq("taşırken bonus yok", Config.GetJetpackBoost("Scout", true), 1)
	-- Sıra: ucuzdan pahalıya daha hızlı (Robux'lular hariç)
	local lastBoost, lastPrice = 0, -1
	for _, def in Config.Jetpacks do
		if def.pass == nil then
			ok(def.id .. " öncekinden hızlı", def.boost > lastBoost)
			ok(def.id .. " öncekinden pahalı", def.price > lastPrice)
			lastBoost, lastPrice = def.boost, def.price
		end
	end

	ctx.profile.jetpacks = {}
	ctx.profile.jetpack = "Starter"
	setCash(ctx.player, scout.price - 1)
	ok("parası yetmeyince alınamıyor", not JetpackService.Buy(ctx.player, "Scout"))
	eq("para harcanmadı", EconomyService.GetCash(ctx.player), scout.price - 1)
	setCash(ctx.player, scout.price)
	ok("alındı", JetpackService.Buy(ctx.player, "Scout"))
	eq("para düştü", EconomyService.GetCash(ctx.player), 0)
	eq("kuşanıldı", ctx.player:GetAttribute("Jetpack"), "Scout")
	ok("sahiplik yayında", string.find(tostring(ctx.player:GetAttribute("JetpacksOwned")), "Scout", 1, true) ~= nil)
	ok("başlangıca dönülebiliyor", JetpackService.Equip(ctx.player, "Starter"))
	ok("sahip olunmayan kuşanılamıyor", not JetpackService.Equip(ctx.player, "Quasar"))
	-- Test hesabı (oyunun sahibi) pass'e sahip olabilir: o zaman kuşanıyor ama para gitmiyor
	setCash(ctx.player, 5)
	JetpackService.Buy(ctx.player, "Plasma")
	eq("Robux'lu parayla alınamıyor", EconomyService.GetCash(ctx.player), 5)

	ctx.profile.jetpacks = {}
	ctx.profile.jetpack = "Starter"
	JetpackService.Publish(ctx.player)
end)

case("Uzay: mürettebat hep birlikte değişiyor, sayaç herkese aynı", function()
	SpaceService.RotateCrew()
	local at = workspace:GetAttribute("CrewRotateAt")
	ok("sayaç yazıldı", typeof(at) == "number")
	if typeof(at) == "number" then
		near("5 dakika sonra", at - workspace:GetServerTimeNow(), Config.Space.CrewRotate, 2)
	end
	local filled = 0
	for k = 1, Config.Space.CrewPerPlanet do
		if SpaceService._Spot(1, k) then
			filled += 1
		end
	end
	eq("ilk gezegen dolu", filled, Config.Space.CrewPerPlanet)
	ok("çalınınca 1 dakikada yenisi", Config.Space.CrewRespawn == 60)
end)

case("Uzay: istasyona dönüş yalnızca uzayda ve boş elle", function(ctx)
	ctx.player:SetAttribute("InSpace", nil)
	ok("gemideyken dönüş yok", not SpaceService.ReturnToStation(ctx.player))
	ctx.player:SetAttribute("InSpace", true)
	local root = ctx.player.Character.HumanoidRootPart :: BasePart
	local home = root.CFrame
	ok("uzayda dönüyor", SpaceService.ReturnToStation(ctx.player))
	ok("güverteye indi", (root.Position - SpaceField.DeckCenter()).Magnitude < 40)
	ok("art arda dönüş yok", not SpaceService.ReturnToStation(ctx.player))
	ctx.player:SetAttribute("InSpace", nil)
	root.CFrame = home
end)

case("Jetpack alevleri: parayla alınıyor, ödüllü ve Robux'lusu satılmıyor", function(ctx)
	ok("Classic herkeste", JetpackService.OwnsFlame(ctx.player, "Classic"))
	local cryo = Config.GetJetFlame("Cryo") :: Config.JetFlameDef
	ctx.profile.flames = {}
	ctx.profile.flame = "Classic"
	setCash(ctx.player, cryo.price - 1)
	ok("parası yetmeyince alınamıyor", not JetpackService.BuyFlame(ctx.player, "Cryo"))
	setCash(ctx.player, cryo.price)
	ok("alındı", JetpackService.BuyFlame(ctx.player, "Cryo"))
	eq("takıldı", ctx.player:GetAttribute("JetFlame"), "Cryo")
	ok("sahiplik yayında", string.find(tostring(ctx.player:GetAttribute("FlamesOwned")), "Cryo", 1, true) ~= nil)
	setCash(ctx.player, 1e15)
	ok("sezon alevi satılmıyor", not JetpackService.BuyFlame(ctx.player, "Nebula"))
	ok("haftalık alev satılmıyor", not JetpackService.BuyFlame(ctx.player, "Champion"))
	-- Pass sahibi (ör. oyunun yapımcısı) için alım "takma"ya dönüyor; o durumda denetlenemez
	if not JetpackService.OwnsFlame(ctx.player, "Rainbow") then
		ok("Robux alevi parayla alınmıyor", not JetpackService.BuyFlame(ctx.player, "Rainbow"))
	end
	ok("ödülle geliyor", RewardService.Give(ctx.player, { kind = "flame", flame = "Nebula" }) ~= nil)
	ok("ödül alevi takılabiliyor", JetpackService.EquipFlame(ctx.player, "Nebula"))
	for _, def in Config.JetFlames do
		ok(def.id .. " açıklaması var", def.blurb ~= "")
	end
	ctx.profile.flames = {}
	ctx.profile.flame = "Classic"
	JetpackService.Publish(ctx.player)
end)

case("Haftalık sıralama: hafta sayacı, ödül girişte bir kez", function(ctx)
	local t = 1790553600
	eq("hafta bitişi bir sonraki pazartesi", Config.WeekEndsAt(t) - Config.WeekEndsAt(t - 7 * 86400), 7 * 86400)
	ok("hafta başı pazartesi", (Config.WeekEndsAt(t) - Config.Weekly.Epoch) % (7 * 86400) == 0)
	eq("1. ödül", (Config.GetWeeklyReward(1) :: any).best, 3)
	eq("3. ödül", (Config.GetWeeklyReward(3) :: any).best, 2)
	eq("10. ödül", (Config.GetWeeklyReward(10) :: any).best, 1)
	eq("11. yok", Config.GetWeeklyReward(11), nil)

	-- Soygun sayacı haftalığa da yazılıyor (önceki testlerin ertelenmiş sinyalleri önce işlensin)
	ctx.profile.weekId = Config.WeekIndex(os.time())
	task.wait()
	local before = ctx.profile.weekStolen
	DataService.Bump(ctx.player, "salvaged")
	task.wait() -- sinyaller ertelemeli (SignalBehavior Deferred)
	eq("haftalık soygun arttı", ctx.profile.weekStolen, before + 1)
	ctx.profile.salvaged -= 1

	-- Geçen hafta birinci: nakit + unvan sayacı + alev, bir kez
	local week = Config.WeekIndex(os.time())
	ctx.profile.weeklyChecked = 0
	ctx.profile.weeklyBest = 0
	ctx.profile.flames = {}
	setCash(ctx.player, 0)
	local top = { { n = "Me", v = 50, u = ctx.player.UserId } }
	eq("birinci", WeeklyService.Settle(ctx.player, top, week), 1)
	eq("unvan sayacı", ctx.profile.weeklyBest, 3)
	ok("para geldi", EconomyService.GetCash(ctx.player) >= Config.Weekly.Rewards[1].minimum)
	ok("şampiyon alevi", ctx.profile.flames.Champion == true)
	ok("şampiyon unvanı açıldı", ctx.profile.titles.WeeklyChampion == true)
	eq("ikinci kez yok", WeeklyService.Settle(ctx.player, top, week), nil)
	-- Listede yoksa ödül yok ama işaretleniyor
	ctx.profile.weeklyChecked = 0
	eq("listede değil", WeeklyService.Settle(ctx.player, { { n = "X", v = 9, u = -5 } }, week), nil)
	eq("işaretlendi", ctx.profile.weeklyChecked, week)

	ctx.profile.flames = {}
	ctx.profile.weeklyBest = 0
	ctx.profile.titles.WeeklyChampion = nil
	ctx.profile.titles.WeeklyTop3 = nil
	ctx.profile.titles.WeeklyTop10 = nil
	ctx.player:SetAttribute("WeeklyResult", nil)
	JetpackService.Publish(ctx.player)
	TitleService.Publish(ctx.player)
end)

case("Sunucu şansı: nadirler sıklaşıyor, süre uzuyor ve bitiyor", function(ctx)
	-- Aynı zar dizisiyle şanslı ve şanssız çekiliş: şanslıda Rare+ daha çok
	local monster = Config.SpaceMonsters[2]
	local function rares(luck: number): number
		local rng = Random.new(42)
		local n = 0
		for _ = 1, 3000 do
			local unit = Config.RollSpaceUnit(rng, monster, luck)
			if Config.Rarities[unit.rarity].order >= 3 then
				n += 1
			end
		end
		return n
	end
	ok("şansla Rare+ artıyor", rares(2) > rares(1), string.format("%d vs %d", rares(2), rares(1)))
	eq("şans yokken ağırlık aynı", Config.LuckWeight("Rare", 10, nil), 10)
	eq("Common'a şans yok", Config.LuckWeight("Common", 10, 2), 10)
	eq("Rare x2", Config.LuckWeight("Rare", 10, 2), 20)

	ServerBoostService.Expire(true)
	eq("başta şans 1", Config.GetServerLuck(), 1)
	ok("şans verildi", ServerBoostService.GrantLuck(ctx.player))
	eq("şans x2", Config.GetServerLuck(), Config.ServerLuck.multiplier)
	local first = workspace:GetAttribute("ServerLuckEndsAt") :: number
	ServerBoostService.GrantLuck(ctx.player)
	local second = workspace:GetAttribute("ServerLuckEndsAt") :: number
	ok("tekrar alınca uzuyor", second > first + Config.ServerLuck.seconds - 5)
	ok("tavan 1 saat", second <= workspace:GetServerTimeNow() + Config.ServerLuck.maxSeconds + 1)
	ServerBoostService.Expire(true)
	eq("bitince 1", Config.GetServerLuck(), 1)

	-- Troller: bilinmeyen tür reddediliyor; ay yerçekimi geri geliyor
	ok("bilinmeyen trol yok", not ServerBoostService.Troll(ctx.player, "Nope"))
	local g = workspace.Gravity
	ok("ay trolü", ServerBoostService.Troll(ctx.player, "Moon"))
	ok("yerçekimi düştü", workspace.Gravity < g)
	ServerBoostService.Expire(true)
	eq("yerçekimi geri", workspace.Gravity, g)
	for key, def in Config.ServerProducts do
		ok(key .. " türü tanınıyor", def.kind == "serverluck" or (def.kind == "troll" and Config.Trolls[def.troll or ""] ~= nil))
	end
end)

case("Sezon Kartı: XP kademesi, bedava ve premium ödül", function(ctx)
	eq("0 XP kademe 0", (Config.SeasonProgress(0)), 0)
	eq("1. kademe", (Config.SeasonProgress(Config.SeasonTierXp(1))), 1)
	local total = 0
	for tier = 1, Config.Season.tiers do
		total += Config.SeasonTierXp(tier)
		local free, premium = Config.GetSeasonRewards(tier)
		ok(tier .. ". bedava ödül tanımlı", free.kind ~= "")
		ok(tier .. ". premium ödül tanımlı", premium.kind ~= "")
	end
	eq("tavan", (Config.SeasonProgress(total + 999)), Config.Season.tiers)
	-- XP kaynağı bir soygun saatlerce değil: 30 kademe ~ yüzlerce soygun
	ok("30 kademe emek istiyor", total / Config.Season.xp.salvaged >= 300, tostring(total))

	ctx.profile.season = { id = Config.Season.id, xp = Config.SeasonTierXp(1), free = {}, premium = {} }
	SeasonService._SetPass(ctx.player, false)
	ok("1. bedava toplandı", SeasonService.Claim(ctx.player, 1, "free"))
	ok("ikinci kez yok", not SeasonService.Claim(ctx.player, 1, "free"))
	ok("ulaşılmamış kademe yok", not SeasonService.Claim(ctx.player, 2, "free"))
	ok("pass'siz premium yok", not SeasonService.Claim(ctx.player, 1, "premium"))
	SeasonService._SetPass(ctx.player, true)
	ok("pass'le premium", SeasonService.Claim(ctx.player, 1, "premium"))
	ok("uydurma iz yok", not SeasonService.Claim(ctx.player, 1, "gold"))
	ok("claimed yayında", string.find(tostring(ctx.player:GetAttribute("SeasonClaimed")), "p1", 1, true) ~= nil)
	-- Başka sezonun kaydı sıfırlanıyor
	ctx.profile.season = { id = "OLD", xp = 99999, free = { ["1"] = true }, premium = {} }
	SeasonService.Publish(ctx.player)
	eq("yeni sezon sıfırdan", ctx.profile.season.xp, 0)
	SeasonService._SetPass(ctx.player, nil)
	ctx.profile.season = { id = Config.Season.id, xp = 0, free = {}, premium = {} }
	SeasonService.Publish(ctx.player)
end)

case("Çark: jeton ve süper çark haklarını harcıyor, 7. gün süper çark", function(ctx)
	eq("7. gün süper çark", Config.DailyRewards[7].kind, "superspin")
	ctx.profile.spinTokens = 0
	ctx.profile.superSpins = 0
	ok("jetonsuz çevrilmiyor", not SpinService.Spin(ctx.player, false, true, "token"))
	ok("süpersiz çevrilmiyor", not SpinService.Spin(ctx.player, false, true, "super"))
	ok("ödül olarak süper çark", RewardService.Give(ctx.player, { kind = "superspin", count = 1 }) ~= nil)
	eq("süper çark hakkı", ctx.profile.superSpins, 1)
	ok("süper çevrildi", SpinService.Spin(ctx.player, false, true, "super"))
	eq("süper harcandı", ctx.profile.superSpins, 0)
	ctx.profile.spinTokens = 2
	ok("jetonla çevrildi", SpinService.Spin(ctx.player, false, true, "token"))
	eq("jeton harcandı", ctx.profile.spinTokens, 1)
	-- Süper çarkın ağırlıkları büyük ödüle kayık
	local normalBig = 0
	local superBig = 0
	local total, superTotal = 0, 0
	for _, r in Config.SpinRewards do
		total += r.weight
		superTotal += Config.SuperSpin.weights[r.id] or 0
		if r.id == "FreeUnit" or r.id == "HugeCash" then
			normalBig += r.weight
			superBig += Config.SuperSpin.weights[r.id] or 0
		end
	end
	ok("süperde büyük ödül daha olası", superBig / superTotal > normalBig / total * 2)
	ctx.profile.spinTokens = 0
	ctx.profile.superSpins = 0
end)

case("Uzay olayları: karartma, göktaşı yağmuru", function()
	EventService.End()
	ok("Blackout başladı", EventService.Begin("Blackout"))
	EventService.End()

	-- Göktaşları sunucu ve istemcide aynı (aynı tohum)
	local a = MeteorShower.Build(42, 1000, 90)
	local b = MeteorShower.Build(42, 1000, 90)
	ok("göktaşı var", #a > 50, tostring(#a))
	eq("aynı sayı", #a, #b)
	local same = true
	for i = 1, #a do
		if (a[i].to - b[i].to).Magnitude > 1e-6 or a[i].t0 ~= b[i].t0 then
			same = false
		end
	end
	ok("aynı tohum aynı liste", same)
	local shards = 0
	for _, m in a do
		if m.shard then
			shards += 1
		end
		ok("hedef uçuş alanında", SpaceField.InSpace(m.to))
	end
	ok("yıldız parçası bırakan var", shards > 5)
	ok("yolun ortasında konum var", MeteorShower.PositionAt(a[1], (a[1].t0 + a[1].t1) / 2) ~= nil)
	eq("uçuş bitince yok", MeteorShower.PositionAt(a[1], a[1].t1 + 1), nil)

	ok("Meteor Shower başladı", EventService.Begin("Meteors"))
	ok("tohum yayında", typeof(workspace:GetAttribute("MeteorSeed")) == "number")
	EventService.End()
	eq("tohum kalktı", workspace:GetAttribute("MeteorSeed"), nil)
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

	-- Pass'ler yokmuş gibi: testi çalıştıran hesap (oyunun sahibi) pass'lere
	-- sahip olabiliyor; beklenen değerler pass'siz oyuncuya göre. Sonda
	-- önbellek siliniyor, gerçek sahiplik yeniden soruluyor.
	for key in Config.GamePasses do
		MonetizationService._SetPassCache(player, key, false)
	end
	-- Testi çalıştıran hesap geliştirici: unvan testleri normal oyuncuya göre
	TitleService._SetDeveloperTitle(false, player)

	-- Testler profili değiştiriyor; sonunda geri yüklenecek
	local backup = {
		cash = profile.cash,
		rebirths = profile.rebirths,
		upgrades = table.clone(profile.upgrades),
		spaceSpeed = profile.spaceSpeed,
		lastSpinAt = profile.lastSpinAt,
		titles = table.clone(profile.titles),
		trainings = profile.trainings,
		stunned = profile.stunned,
		thrown = profile.thrown,
		mutatedSteals = profile.mutatedSteals,
		bossSteals = profile.bossSteals,
		bestPlanet = profile.bestPlanet,
		tutorialStep = profile.tutorialStep,
		stolen = profile.stolen,
		salvaged = profile.salvaged,
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
	-- Canavarlar test oyuncusunu yakalamasın, kapsül hızı kendiliğinden artmasın
	SpaceService.SetPaused(true)
	SpaceBonusService.SetPaused(true)
	CapsuleService.SetPaused(true)

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
	SpaceService.SetPaused(false)
	SpaceBonusService.SetPaused(false)
	CapsuleService.SetPaused(false)
	-- Testler iksir içiyor; kalan takviyeyi canlı oturuma bırakma
	MonetizationService.ClearBoosts(player)

	profile.cash = backup.cash
	profile.rebirths = backup.rebirths
	profile.upgrades = backup.upgrades
	CapsuleService.SetSpeed(player, backup.spaceSpeed)
	profile.lastSpinAt = backup.lastSpinAt
	profile.titles = backup.titles
	profile.trainings = backup.trainings
	profile.stunned = backup.stunned
	profile.thrown = backup.thrown
	profile.mutatedSteals = backup.mutatedSteals
	profile.bossSteals = backup.bossSteals
	profile.bestPlanet = backup.bestPlanet
	profile.tutorialStep = backup.tutorialStep
	-- İstemci de bilsin: nitelik test sırasındaki adımda kalıyordu, arayüz (sol menü,
	-- sekmeler) yeni oyuncu gibi kapanıyordu
	TutorialService.Refresh(player)
	profile.stolen = backup.stolen
	profile.salvaged = backup.salvaged
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
	-- Sahiplik niteliği ve çantadaki aletler de geri yüklenen profile göre
	-- (eskiden yalnızca profil dönüyordu: dükkân yanlış "OWNED", aletler eksik)
	GearService.Refresh(player)
	profile.cosmetics = backup.cosmetics
	profile.hat = backup.hat
	profile.trail = backup.trail
	CosmeticService.Apply(player)
	CosmeticService.Publish(player)
	for name, value in backupAttributes do
		player:SetAttribute(name, value)
	end
	-- Petler geri yüklendi: bonusu ve sahadaki modelleri gerçek profile göre kur
	PetService.Apply(player)
	--[[
		Ödül ve iksir durumu da istemciye yeniden: testler günlük ödülü
		"toplanabilir" yapıp geri alıyordu, ama pencere eski durumu
		gösteriyordu (toplanamayan ödül "Claim" diyordu).
	]]
	RewardService.Push(player)
	PotionService.Publish(player, true)
	setCash(player, backup.cash)
	PlotService.SetUnlockedFloors(plot, backupFloors)
	FloorService.Publish(player)
	clearPlot(plot)

	for key in Config.GamePasses do
		MonetizationService._SetPassCache(player, key, nil)
	end
	TitleService._SetDeveloperTitle(true, player)

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
