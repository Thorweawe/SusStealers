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

	İki modüle bölündü: Roblox bir betiğin kaynağını 200.000 karakterle
	sınırlıyor ve tek dosya 199.5K'ya dayanmıştı. Bu modül altyapıyı,
	A-T bölümlerini ve çalıştırıcıyı tutuyor; U bölümünden (petler)
	sonrası tests/ServerTests2.luau'da (Studio'da Server.Tests2). İkisini
	de aktar; Tests2 eksikse require hata verir, testler sessizce eksik
	koşmaz. Yeni testleri küçük olan dosyaya ekle.
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
local CosmeticService = require(Server.CosmeticService)
local EventService = require(Server.EventService)
local RogueService = require(Server.RogueService)
local SettingsService = require(Server.SettingsService)
local SpaceService = require(Server.SpaceService)
local SpaceBonusService = require(Server.SpaceBonusService)

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
		elseif id == "SprintBoots" then
			return string.format("%.5f", Config.GetSprintMul(level))
		elseif id == "SlapPower" then
			return string.format("%.5f", Config.GetSlapPower(level))
		elseif id == "StunCharge" then
			return string.format("%.5f", Config.GetStunCharge(level))
		elseif id == "GearRecharge" then
			return string.format("%.5f", Config.GetGearRecharge(level))
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
	local saved = ctx.profile.rebirths
	ok("tavan son kilidin üstünde", Config.MaxRebirths >= 10)
	ctx.profile.rebirths = Config.MaxRebirths
	setCash(ctx.player, 1e30)
	eq("tavanda reddedildi", RebirthService.TryRebirth(ctx.player), false)
	eq("seviye değişmedi", ctx.profile.rebirths, Config.MaxRebirths)
	ctx.profile.rebirths = Config.MaxFloors - 1
	setCash(ctx.player, 0)
	setCash(ctx.player, Config.GetRebirthCost(ctx.profile.rebirths))
	ok("kat tavanından sonra rebirth", RebirthService.TryRebirth(ctx.player))
	eq("R3", ctx.profile.rebirths, Config.MaxFloors)
	ctx.profile.rebirths = saved
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
		defenseWaves = true,
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

case("Öğretici: eski 11 adımlı kayıt yeni listeye çevriliyor", function()
	eq("başlamamış", Config.MigrateTutorialStep(0), 0)
	eq("atlamış", Config.MigrateTutorialStep(-1), -1)
	eq("eski listeyi bitirmiş", Config.MigrateTutorialStep(#Config.TutorialLegacyOrder), #Config.Tutorial)
	-- Eskide Heist + Fill bitmiş: yenide yalnızca Heist
	eq("iki adım", Config.MigrateTutorialStep(2), 1)
	-- Eskide çarka kadar (5): Heist, CapsuleGame bitti, Upgrade bitmedi
	eq("beş adım", Config.MigrateTutorialStep(5), 2)
	for k = 0, #Config.TutorialLegacyOrder do
		local v = Config.MigrateTutorialStep(k)
		ok(k .. " aralıkta", v >= 0 and v <= #Config.Tutorial, tostring(v))
	end
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
	-- 2. adım kapsül oyunu: sayacı sıfır olsun ki aynı turda geçmesin
	ctx.profile.trainings = 0
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
		Oyuncu iki adımın koşulunu birden sağlarsa (karakter çaldı, kapsül
		oyununu da kazandı) iki adım aynı turda geçmeli. Tek adım ilerleyen
		bir döngü, oyuncuyu bir saniye boyunca bitmiş bir görevle bekletiyordu.
		(2026-09-29: öğretici kısaldı, 2. adım kapsül oyunu.)
	]]
	clearPlot(ctx.plot)
	ctx.profile.tutorialStep = 0
	ctx.profile.trainings = 1
	ctx.profile.bestPlanet = 0
	-- 3. adım (yükseltme) aynı turda geçmesin
	local savedUpgrades = ctx.profile.upgrades
	ctx.profile.upgrades = {}
	setCash(ctx.player, 0)

	local podiums = PlotService.GetUnlockedPodiums(ctx.plot)
	ok("en az bir kaide açık", #podiums >= 1, tostring(#podiums))
	if #podiums < 1 then
		ctx.profile.upgrades = savedUpgrades
		return
	end

	PlotService.PlaceUnit(podiums[1], Config.Units[1].id, nil)

	TutorialService.Check(ctx.player)
	ok("iki adım birden geçti", ctx.profile.tutorialStep >= 2,
		tostring(ctx.profile.tutorialStep))

	local expected = Config.Tutorial[1].reward + Config.Tutorial[2].reward
	eq("iki ödül de verildi", EconomyService.GetCash(ctx.player), expected)

	ctx.profile.upgrades = savedUpgrades
	clearPlot(ctx.plot)
end)

case("Öğretici: bitince bonus veriyor ve susuyor", function(ctx)
	ctx.profile.tutorialStep = #Config.Tutorial - 1
	setCash(ctx.player, 0)

	-- Son adımın koşulunu sağla (2026-10-03: son adım gezegen savunması, bir dalga)
	local last = Config.Tutorial[#Config.Tutorial]
	eq("son adım savunma", last.check, "defenseWaves")
	local hadBest = ctx.profile.defense.bestWave
	ctx.profile.defense.bestWave = last.goal

	TutorialService.Check(ctx.player)
	ctx.profile.defense.bestWave = hadBest
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
		-- Dünyada hedef yok: istemci ⚔ DEFEND düğmesini spotlight'la gösteriyor; mod açık olmalı
		Defend = function()
			local DefenseConfig = require(game:GetService("ReplicatedStorage").Shared.DefenseConfig) :: any
			return if DefenseConfig.IsEnabled() then workspace else nil
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
		SeasonClaim Sezon Kartı; 2026-10-01 Defense gezegen savunması;
		gerekçeleri Net.luau'da): yenisi eklemek bilinçli bir karar olsun,
		kazara büyümesin.
	]]
	ok("liste bilinçli", #listened <= 24, tostring(#listened))

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
		StarChime = true, Harp = true, Fanfare = true, StarFall = true,
		CashReg = true,
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
		eq(def.name .. " tavan en üst kat", Config.GetUpgradeCeiling(def), f3 + Config.GetRebirthUpgradeBonus(Config.MaxRebirths))
		eq(def.name .. " R2 bonus yok", Config.GetUpgradeMaxLevel(def, 3, 2), f3)
		eq(def.name .. " R3 +9", Config.GetUpgradeMaxLevel(def, 3, 3), f3 + 9)
		eq(def.name .. " R10 +30", Config.GetUpgradeMaxLevel(def, 3, 10), f3 + 30)
	end
	local cap = Config.GetUpgradeMaxLevel(Config.GetUpgrade("SpaceCapsule") :: any, 3)
	local k = Config.GetCapsuleGain(cap + 30, 100) / Config.GetCapsuleGain(cap, 100)
	ok("kapsül bonus seviyeleri yavaş", k > 1.2 and k < 1.8, string.format("%.2f", k))
	ok("sprint tavanlı", Config.GetSprintMul(200) <= 1.8 and Config.GetSprintMul(0) == 1)
	ok("bekleme kısalıyor", Config.GetGearRecharge(200) >= 0.55 and Config.GetGearRecharge(0) == 1)
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
	-- En uzak canavarın hızında, o canavarı açan rebirth sayısının antrenman hızlanmasıyla
	local lastDef = Config.SpaceMonsters[#Config.SpaceMonsters]
	local top = Config.GetCapsuleGain(ceiling, lastDef.need) * Config.GetRebirthTrainingMul(lastDef.rebirths or 0)
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

-- ─── İkinci modül ───────────────────────────────────────────────────────────

--[[
	U bölümünden sonrası Server.Tests2'de. Yardımcıları buradan alıp
	vakalarını aynı listeye ekliyor; sıra tek dosyadaki gibi kalıyor.
]]
require(Server.Tests2).Register({
	case = case,
	ok = ok,
	eq = eq,
	near = near,
	clearPlot = clearPlot,
	setCash = setCash,
})

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

	-- Yükseltmeler de sıfırdan: hesabın Crew Morale seviyesi (2. seviye ~%3)
	-- gelir testlerine karışıyordu. Sonda backup.upgrades geri yükleniyor.
	profile.upgrades = {}

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
	-- Sıralama döngüsü kürsüyü yeniden kurmasın (Top Crew testi kendi satırını yazıyor)
	require(Server.GlobalBoardService).SetPaused(true)
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
	-- Teslimdeki şans bonusu nakit ölçen testleri bozmasın (Config.Hype)
	SpaceService._SetLuckRoll(0.99)

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
	SpaceService._SetLuckRoll(nil)
	TitleService.SetPaused(false)
	require(Server.GlobalBoardService).SetPaused(false)
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
