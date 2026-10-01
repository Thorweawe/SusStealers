--!strict
--[[
	Sunucu regresyon testleri, ikinci yarı (U bölümünden sonrası).

	Server.Tests tek dosyada Roblox'un 200.000 karakter betik sınırına
	dayanınca ikiye bölündü. Bu modül tek başına koşmuyor: Server.Tests
	yüklenirken Register'ı çağırıp case/ok/eq/near ve ortam
	yardımcılarını veriyor, vakalar aynı listeye ekleniyor. Çalıştırma
	yine Tests.Run ile (bkz. ServerTests.luau başı).

	Studio'da ServerScriptService.Server.Tests2 olarak durmalı.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local CosmeticModel = require(ReplicatedStorage.Shared.CosmeticModel)

local Server = script.Parent
local PlotService = require(Server.PlotService)
local EconomyService = require(Server.EconomyService)
local MovementService = require(Server.MovementService)
local MonetizationService = require(Server.MonetizationService)
local CapsuleService = require(Server.CapsuleService)
local DataService = require(Server.DataService)
local SpinService = require(Server.SpinService)
local TitleService = require(Server.TitleService)
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
local ReferralService = require(Server.ReferralService)
local RebirthService = require(Server.RebirthService)
local NotifyService = require(Server.NotifyService)
local LobbyBoardService = require(Server.LobbyBoardService)
local LimitedEventService = require(Server.LimitedEventService)
local DefenseService = require(Server.DefenseService)
local DefenseConfig = require(ReplicatedStorage.Shared.DefenseConfig)
local DefenseSim = require(ReplicatedStorage.Shared.DefenseSim)
local MeteorShower = require(ReplicatedStorage.Shared.MeteorShower)
local SpaceField = require(ReplicatedStorage.Shared.SpaceField)

local ServerTests2 = {}

export type Kit = {
	case: (name: string, fn: (any) -> ()) -> (),
	ok: (label: string, condition: boolean, detail: string?) -> (),
	eq: (label: string, actual: any, expected: any) -> (),
	near: (label: string, actual: number, expected: number, tolerance: number) -> (),
	clearPlot: (plot: Model) -> (),
	setCash: (player: Player, amount: number) -> (),
}

--[[ Vakaları Server.Tests'in listesine ekler; bir kez, Tests yüklenirken. ]]
function ServerTests2.Register(kit: Kit)
	local case, ok, eq, near = kit.case, kit.ok, kit.eq, kit.near
	local clearPlot, setCash = kit.clearPlot, kit.setCash

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
		eq("Titan -> Colossal", PetService.TryFuse(ctx.player, "MiniCrew:Titan"), "MiniCrew:Colossal")
		ctx.profile.pets = { ["MiniCrew:Galactic"] = 3 }
		eq("Galactic'in üstü yok", PetService.TryFuse(ctx.player, "MiniCrew:Galactic"), nil)
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
		eq("pet sayısı (yumurta başına kademe başına bir)", #Config.Pets, 39)

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
		local perHour, limitedPerHour = 0, 0
		for _, def in Config.Events do
			if def.limited then
				limitedPerHour += 3600 / def.every
			elseif not def.random then
				perHour += 3600 / def.every
			end
		end
		ok("saatte en fazla iki sabit olay", perHour <= 2, tostring(perHour))
		-- Sınırlı etkinlikte yağmur da ekleniyor: yine de saatte en fazla dört an
		ok("etkinlikte saatte en fazla dört an", perHour + limitedPerHour <= 4, tostring(perHour + limitedPerHour))

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
		-- 6 herkese açık + 5 rebirth canavarı (2026-09-29)
		eq("on bir canavar", #list, 11)
		eq("herkese açık altı", #Config.BaseSpaceMonsters(), 6)
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

		-- Hile payı: kapıp anında güverteye ışınlanan teslim edemiyor. Hız
		-- taban değerde: test hesabının uzay hızı ve pet bonusu (hile payını
		-- büyütüyor) sonucu değiştirmesin.
		local savedSpeed = ctx.player:GetAttribute("SpaceSpeed")
		local savedPet = ctx.player:GetAttribute("PetSpeedBonus")
		ctx.player:SetAttribute("SpaceSpeed", Config.Space.BaseSpeed)
		ctx.player:SetAttribute("PetSpeedBonus", 0)
		SpaceService._Grab(ctx.player, 1, 1)
		character:PivotTo(CFrame.new(SpaceField.DeckCenter() + Vector3.new(0, 3, 0)))
		SpaceService._Deliver(ctx.player, true)
		ctx.player:SetAttribute("SpaceSpeed", savedSpeed)
		ctx.player:SetAttribute("PetSpeedBonus", savedPet)
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

	case("Heyecan: şanslı soygun, close call, kıl payı ve nadir doğuş kuralları", function(ctx)
		-- Zar sırası: Jackpot önce, sonra Lucky, gerisi bonussuz
		eq("zar 0.005 jackpot", (Config.RollLuckySteal(0.005) or {} :: any).id, "Jackpot")
		eq("zar 0.05 lucky", (Config.RollLuckySteal(0.05) or {} :: any).id, "Lucky")
		eq("zar 0.5 bonus yok", Config.RollLuckySteal(0.5), nil)
		-- Beklenen değer küçük kalmalı (ekonomiyi kaydırmasın): soygun başına < 10 sn gelir
		local ev, total = 0, 0
		for _, b in Config.Hype.LuckySteal do
			ev += b.chance * b.seconds
			total += b.chance
		end
		ok("şans beklenen değeri küçük", ev < 10, string.format("(%.1f sn)", ev))
		ok("toplam şans makul", total > 0.05 and total < 0.25, tostring(total))

		ok("Secret nadir doğuş", Config.IsHypeSpawn("TheCrewmate", nil))
		ok("Epic + IMPOSTOR nadir doğuş", Config.IsHypeSpawn("Impostor", "Impostor"))
		ok("Common + IMPOSTOR değil", not Config.IsHypeSpawn("RedCrew", "Impostor"))
		ok("Mythic tek başına değil (her rotasyonda alarm olurdu)", not Config.IsHypeSpawn("DoubleImp", nil))
		-- Rebirth gezegenlerinde Secret/Celestial sıradan: alarm yok; IMPOSTOR mutasyonu yine var
		local rebirthPlanet: number? = nil
		for i, m in Config.SpaceMonsters do
			if (m :: any).rebirths and not rebirthPlanet then
				rebirthPlanet = i
			end
		end
		if rebirthPlanet then
			ok("rebirth gezegeninde Secret alarm değil", not Config.IsHypeSpawn("TheCrewmate", nil, rebirthPlanet))
			ok("rebirth gezegeninde IMPOSTOR alarm", Config.IsHypeSpawn("TheCrewmate", "Impostor", rebirthPlanet))
		end
		-- 2026-10-01: gezegendeki gerçek ihtimale göre
		ok("Rift Stalker'da Secret (%2, en nadir kademe) alarm", Config.IsHypeSpawn("TheCrewmate", nil, 5))
		ok("Leviathan'da Secret (%12, sık) alarm değil", not Config.IsHypeSpawn("TheCrewmate", nil, 6))
		ok("Leviathan'da IMPOSTOR mutasyonlu alarm", Config.IsHypeSpawn("TheCrewmate", "Impostor", 6))
		ok("Glorp'ta sade Common alarm değil", not Config.IsHypeSpawn("RedCrew", nil, 1))
		local p = Config.SpawnChance("TheCrewmate", nil, 5)
		ok("doğma ihtimali hesaplanıyor", p ~= nil and p > 0.015 and p < 0.02, tostring(p))
		-- Sıklık: temel gezegenlerde (5'er mürettebat) rotasyon başına beklenen alarm sayısı az olmalı
		local expected = 0
		for planetIndex, planet in Config.SpaceMonsters do
			if not (planet :: any).rebirths then
				for _, unit in Config.Units do
					local total, wsum = 0, 0
					for _, u in Config.Units do
						if u.rarity == unit.rarity and (u.monster == nil) then
							wsum += u.weight
						end
					end
					if wsum > 0 and unit.monster == nil then
						local muts = { "" }
						for _, m in Config.Mutations do
							table.insert(muts, m.id)
						end
						for _, mid in muts do
							local c = Config.SpawnChance(unit.id, if mid == "" then nil else mid, planetIndex)
							if c and Config.IsHypeSpawn(unit.id, if mid == "" then nil else mid, planetIndex) then
								total += c * unit.weight / wsum
							end
						end
					end
					expected += total * 5
				end
			end
		end
		ok("temel gezegenlerde rotasyon başına alarm < 0.4", expected < 0.4, string.format("%.3f", expected))

		-- Çark ihtimalleri gösterilebilir: her ödülün ağırlığı var, toplamlar pozitif
		local spinTotal, superTotal = 0, 0
		for _, r in Config.SpinRewards do
			spinTotal += r.weight
			superTotal += Config.SuperSpin.weights[r.id] or 0
		end
		ok("çark ağırlıkları", spinTotal > 0 and superTotal > 0)

		-- Teslimde jackpot: nakit en az tabanı kadar artıyor
		local character = ctx.player.Character
		if not character then
			ok("karakter var", false)
			return
		end
		local startCf = character:GetPivot()
		clearPlot(ctx.plot)
		SpaceService._ClearImmunity(ctx.player)
		local def = Config.SpaceMonsters[1]
		local spot = SpaceField.CrewSpots(def)[2]
		character:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 4)))
		SpaceService._Grab(ctx.player, 1, 2)
		ok("taşıyor", SpaceService.IsCarrying(ctx.player))
		character:PivotTo(CFrame.new(SpaceField.DeckCenter() + Vector3.new(0, 3, 0)))
		setCash(ctx.player, 0)
		SpaceService._SetLuckRoll(0)
		SpaceService._Deliver(ctx.player)
		SpaceService._SetLuckRoll(0.99)
		ok("teslim edildi", not SpaceService.IsCarrying(ctx.player))
		local jackpot = Config.Hype.LuckySteal[1]
		ok("jackpot nakdi", EconomyService.GetCash(ctx.player) >= jackpot.minimum, tostring(EconomyService.GetCash(ctx.player)))
		SpaceService._Step(1 / 30)
		character:PivotTo(startCf)
		clearPlot(ctx.plot)
	end)

	case("Geri getirme: davet ödülü, bildirim zamanı, lobi geri sayımı", function(ctx)
		local p = ctx.profile
		local keepBy, keepCount = p.referredBy, p.referrals
		ReferralService._NoStore = true

		-- Davet eden kimliği: LaunchData önce, sonra Roblox'un ReferredByPlayerId'si
		eq("LaunchData", ReferralService.InviterOf(ctx.player, { LaunchData = "ref:123" }), 123)
		eq("ReferredByPlayerId", ReferralService.InviterOf(ctx.player, { ReferredByPlayerId = 55 }), 55)
		eq("kendini davet yok", ReferralService.InviterOf(ctx.player, { LaunchData = "ref:" .. ctx.player.UserId }), nil)
		eq("bozuk veri yok", ReferralService.InviterOf(ctx.player, { LaunchData = "ref:abc" }), nil)

		-- Eski oyuncu (ilk ziyaret değil) davetli sayılmıyor
		p.referredBy = 0
		eq("eski oyuncuya ödül yok", ReferralService.HandleJoin(ctx.player, { LaunchData = "ref:999" }, false), nil)
		eq("referredBy boş kaldı", p.referredBy, 0)
		-- İlk ziyaret: hoş geldin ödülü bir kez
		eq("ilk ziyarette işlendi", ReferralService.HandleJoin(ctx.player, { LaunchData = "ref:999" }, true), 999)
		eq("davet eden yazıldı", p.referredBy, 999)
		eq("ikinci kez işlenmiyor", ReferralService.HandleJoin(ctx.player, { LaunchData = "ref:999" }, true), nil)

		-- Davet edenin ödülü tavanlı
		p.referrals = Config.Referral.MaxRewards - 1
		ok("tavandan önce ödül", ReferralService.RewardInviter(ctx.player, "Test"))
		eq("sayaç arttı", p.referrals, Config.Referral.MaxRewards)
		ok("tavanda ödül yok", not ReferralService.RewardInviter(ctx.player, "Test"))
		p.referredBy, p.referrals = keepBy, keepCount
		ReferralService._NoStore = false

		-- Bildirim zamanı: seri yoksa yok; bugün alındıysa yarın; dün alındıysa gün bitmeden
		local now = 100 * 86400 + 5 * 3600
		eq("seri yok", (NotifyService.DailyAt({ dailyStreak = 0, lastDailyDay = 100 }, now)), nil)
		eq("bugün alındı: yarın", (NotifyService.DailyAt({ dailyStreak = 3, lastDailyDay = 100 }, now)), 101 * 86400 + 600)
		local warnAt = NotifyService.DailyAt({ dailyStreak = 3, lastDailyDay = 99 }, now)
		ok("dün alındı: bugün bitmeden", warnAt ~= nil and warnAt < 101 * 86400 and warnAt > now, tostring(warnAt))
		eq("seri koptu: yok", (NotifyService.DailyAt({ dailyStreak = 3, lastDailyDay = 90 }, now)), nil)

		-- Lobi geri sayımı
		local at = Config.LiveOps.nextUpdate.at
		if at > 0 then
			eq("güncelleme çıktı", LobbyBoardService.CountdownText(at + 5), "OUT NOW!")
			eq("gün + saat", LobbyBoardService.CountdownText(at - (86400 + 3661)), "1d 01:01:01")
		end
		ok("tabela kurulu", workspace:FindFirstChild("LobbyUpdateBoard") ~= nil)
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

	case("Rebirth canavarları: kilit, özel Celestial havuzu, antrenman", function(ctx)
		local seen: { [string]: boolean } = {}
		local expected = { FrostWyrm = 2, CrystalGolem = 4, SolarPhoenix = 6, BlackHole = 8, GalaxyTitan = 10 }
		for id, rb in expected do
			local def = Config.GetSpaceMonster(id)
			ok(id .. " var", def ~= nil)
			if not def then
				continue
			end
			eq(id .. " rebirth", def.rebirths, rb)
			ok(id .. " kilitli (bir eksik)", not Config.MonsterUnlocked(def, rb - 1))
			ok(id .. " açık", Config.MonsterUnlocked(def, rb))
			-- Celestial yalnızca bu canavarın kendi üçlüsü
			local rng = Random.new(7)
			local mine = 0
			for _ = 1, 400 do
				local unit = Config.RollSpaceUnit(rng, def)
				if unit.rarity == "Celestial" then
					ok(id .. " özel havuz", unit.monster == id, unit.id)
					seen[unit.id] = true
					mine += 1
				end
			end
			ok(id .. " Celestial çıkıyor", mine > 0)
		end
		-- Eski canavarlar hiç Celestial vermiyor
		local rng = Random.new(11)
		for _, def in Config.BaseSpaceMonsters() do
			for _ = 1, 200 do
				ok(def.id .. " Celestial vermiyor", Config.RollSpaceUnit(rng, def).rarity ~= "Celestial")
			end
		end
		-- Her kapı bir öncekinin çok üstünde (fiyat 8x/rebirth dengesi)
		local best: { [string]: number } = {}
		for _, unit in Config.Units do
			if unit.monster then
				best[unit.monster] = math.max(best[unit.monster] or 0, unit.income)
			end
		end
		local order = { "FrostWyrm", "CrystalGolem", "SolarPhoenix", "BlackHole", "GalaxyTitan" }
		for i = 2, #order do
			ok(order[i] .. " gelir kapısı", best[order[i]] > best[order[i - 1]] * 5,
				string.format("%s vs %s", Config.FormatCash(best[order[i]]), Config.FormatCash(best[order[i - 1]])))
		end
		-- Rebirth antrenmanı hızlandırıyor
		ok("antrenman çarpanı", Config.GetRebirthTrainingMul(0) == 1 and Config.GetRebirthTrainingMul(4) > 2)
		-- En iyi canavar kilitliyi saymıyor
		eq("hız yetse de kilitli değil", Config.BestSpaceMonster(1000, 0).id, "VoidLeviathan")
		eq("rebirth 4'te golem", Config.BestSpaceMonster(1000, 4).id, "CrystalGolem")
		-- Sunucu: kilitli gezegenden çalınamıyor
		local frostIndex = table.find(Config.SpaceMonsters, Config.GetSpaceMonster("FrostWyrm"))
		local saved = ctx.profile.rebirths
		ctx.profile.rebirths = 0
		SpaceService._ClearImmunity(ctx.player)
		local unitId = SpaceService._Spot(frostIndex, 1)
		if unitId then
			SpaceService._Grab(ctx.player, frostIndex, 1)
			ok("kilitli gezegenden çalınamadı", not SpaceService.IsCarrying(ctx.player))
		end
		ctx.profile.rebirths = saved
		local _ = seen
	end)

	case("Rebirth yumurtaları: kilit, yetenekler, tavan", function(ctx)
		local nebula = Config.GetEgg("NebulaEgg")
		local celestial = Config.GetEgg("CelestialEgg")
		ok("yumurtalar var", nebula ~= nil and celestial ~= nil)
		if not (nebula and celestial) then
			return
		end
		ok("Nebula R1'de kilitli", not Config.EggUnlocked(nebula, 1))
		ok("Nebula R2'de açık", Config.EggUnlocked(nebula, 2))
		ok("Void herkese açık", Config.EggUnlocked(Config.GetEgg("VoidEgg") :: any, 0))
		for _, def in Config.Pets do
			if def.egg == "NebulaEgg" then
				ok(def.id .. " kaçış", (def.escape or 0) > 0 and def.luck == nil)
			elseif def.egg == "CelestialEgg" then
				ok(def.id .. " şans", (def.luck or 0) > 0 and def.escape == nil)
			else
				ok(def.id .. " yeteneksiz", def.escape == nil and def.luck == nil)
			end
		end
		local e1 = Config.GetPetKeyPerks("RiftWalker")
		local eT = Config.GetPetKeyPerks(Config.PetKey("RiftWalker", "Cosmic", "Titan"))
		ok("Titan Cosmic ~x5.5", math.abs(eT / e1 - math.sqrt(30)) < 0.01, tostring(eT / e1))
		local key = Config.PetKey("RiftWalker", "Cosmic", "Titan")
		local escape = Config.GetPetPerks({ key, key, key })
		eq("kaçış tavanı", escape, Config.PetPerkCaps.escape)
		local void = Config.GetPetKeyBonus("VoidShard")
		ok("Rift Walker > Void Shard", Config.GetPetKeyBonus("RiftWalker") > void)
		local saved = ctx.profile.rebirths
		ctx.profile.rebirths = 0
		PetService._ResetBusy(ctx.player)
		setCash(ctx.player, nebula.price * 2)
		eq("kilitli yumurta açılmadı", PetService.TryHatch(ctx.player, "NebulaEgg", 1, false), nil)
		ctx.profile.rebirths = 2
		PetService._ResetBusy(ctx.player)
		local keys = PetService.TryHatch(ctx.player, "NebulaEgg", 1, false)
		ok("R2'de açıldı", keys ~= nil and #keys == 1)
		ctx.profile.pets = { [key] = 1 }
		ctx.profile.equippedPets = { key }
		PetService.Apply(ctx.player)
		ok("kaçış niteliği", (ctx.player:GetAttribute("PetEscapeBonus") or 0) > 0.3)
		ctx.profile.equippedPets = {}
		PetService.Apply(ctx.player)
		eq("çıkarınca nitelik yok", ctx.player:GetAttribute("PetEscapeBonus"), nil)
		ctx.profile.rebirths = saved
		ctx.profile.pets = {}
		PetService._ResetBusy(ctx.player)
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
		-- Rebirth antrenmanı hızlandırıyor (Config.GetRebirthTrainingMul)
		near("bir saniyelik kazanç", gained, Config.GetCapsuleGain(2, Config.Space.BaseSpeed) * Config.GetRebirthTrainingMul(ctx.profile.rebirths), 1e-6)
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
		near("bonus = kapsül kazancı × süre", bonus or 0, Config.GetCapsuleGain(3, s0) * Config.GetRebirthTrainingMul(ctx.profile.rebirths) * Config.Capsule.CatchBonusSeconds, 1e-6)
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

	case("Ödül tabanı: bu rebirth'in tepesi, rebirth'te sıfırlanıyor", function(ctx)
		local saved = ctx.profile.rebirths
		ctx.profile.cyclePeakIncome = 1e12
		ok("tepe ödül tabanında", EconomyService.GetRewardIncome(ctx.player) >= 1e12)
		ctx.profile.rebirths = 0
		ok("rebirth", RebirthService.TryRebirth(ctx.player, true))
		eq("tepe sıfırlandı", ctx.profile.cyclePeakIncome, 0)
		ok("ödül tabanı anlık gelire döndü", EconomyService.GetRewardIncome(ctx.player) < 1e12)
		ctx.profile.rebirths = saved
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
		local steals = total / Config.Season.xp.salvaged
		ok("30 kademe emek istiyor", steals >= 200, tostring(total))
		ok("30 kademe bitirilebilir", steals <= 450, tostring(total))
		ok("antrenman XP veriyor", (Config.Season.xp.trainings or 0) > 0 and Config.Season.playXpPerMinute > 0)
		eq("yeni oyuncuya Supply", Config.ResolveRewardEgg("best", 0, 0), "SupplyEgg")
		eq("zengin ama R0: Void", Config.ResolveRewardEgg("best", 0, 1e15), "VoidEgg")
		eq("R6 zengin: Celestial", Config.ResolveRewardEgg("best", 6, 1e15), "CelestialEgg")
		eq("sabit kimlik aynen", Config.ResolveRewardEgg("SkeldEgg", 0, 0), "SkeldEgg")

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

	-- ─── Sınırlı etkinlik (2026-09-30) ──────────────────────────────────────────

	case("Sınırlı etkinlik: para, günlük bonus, dükkân, etkinlik mutasyonu, sınırlı kozmetik", function(ctx)
		local e = Config.LimitedEvent
		local p = ctx.profile
		local keepStart, keepEnd = e.startsAt, e.endsAt
		local keepLimited = p.limited
		local keepCos, keepHat, keepTrail = table.clone(p.cosmetics), p.hat, p.trail
		local keepSuper = p.superSpins
		local keepTokens = p.spinTokens
		-- Test paraları gerçek ortak toplama / sıralamaya yazılmasın
		LimitedEventService._SetTesting(true)
		local keepGoal = LimitedEventService.CommunityTotal()

		--[[ Tanım denetimi: aktif etkinlik VE Cadılar Bayramı taslağı (ileride
		     Config.LimitedEvent'e konunca bozuk çıkmasın). Fiyat ucuzdan pahalıya
		     (hedef merdiveni), kozmetikler bu etkinliğin sınırlı listesinde,
		     mutasyon normal zarda yok, rayın şapkası ve ödül tanımlı. ]]
		local function checkDef(ev: any, tag: string)
			local prev = 0
			for _, item in ev.shop do
				ok(tag .. item.id .. " fiyatı sıralı", item.price > prev)
				prev = item.price
				ok(tag .. item.id .. " sınırı", item.limit >= 1)
				ok(tag .. item.id .. " türü", item.kind == "unit" or item.kind == "superspin" or item.kind == "cosmetic")
				if item.kind == "cosmetic" then
					local def = if item.cosmetic then Config.GetCosmetic(item.cosmetic) else nil
					ok(tag .. item.id .. " bu etkinliğin sınırlı kozmetiği", def ~= nil and (def :: any).limited == ev.id)
				end
			end
			local mutation = Config.GetMutation(ev.mutation)
			ok(tag .. "mutasyon tanınıyor", mutation ~= nil and mutation.incomeMul > 1)
			for _, m in Config.Mutations do
				ok(tag .. "mutasyon normal zarda yok", m.id ~= ev.mutation)
			end
			local reward = Config.GetCosmetic(ev.leaderboard.reward)
			ok(tag .. "ödül bu etkinliğin sınırlı kozmetiği", reward ~= nil and (reward :: any).limited == ev.id)
			local rail = CosmeticModel.BuildHat(ev.railHat, true)
			ok(tag .. "ray şapkası kuruluyor", rail ~= nil)
			if rail then
				rail:Destroy()
			end
			ok(tag .. "süs türü", ev.decor == "stars" or ev.decor == "pumpkins")
			ok(tag .. "süre", ev.endsAt > ev.startsAt)
			-- Giriş takvimi artıyor, yıldız yolu sıralı ve ödülleri tanınıyor
			ok(tag .. "takvim 7 gün", #ev.dailyLadder == 7)
			for i = 2, #ev.dailyLadder do
				ok(tag .. "takvim artıyor " .. i, ev.dailyLadder[i] >= ev.dailyLadder[i - 1])
			end
			local prevAt = 0
			for i, step in ev.milestones do
				ok(tag .. "yol sıralı " .. i, step.at > prevAt)
				prevAt = step.at
				local kind = step.reward.kind
				ok(tag .. "yol ödülü " .. i, kind == "unit" or kind == "cash" or kind == "spins" or kind == "superspin" or kind == "potion")
				ok(tag .. "yol etiketi " .. i, #step.label > 0)
			end
			local sh = ev.shower
			ok(tag .. "yağmur miktarı", sh.min >= 1 and sh.max >= sh.min and sh.superAmount > sh.max)
			ok(tag .. "yağmur ihtimali", sh.superChance > 0 and sh.superChance < 0.5)
			ok(tag .. "yağmur periyot içinde", sh.duration + Config.EventWarning < sh.every and sh.offset < sh.every)
			ok(tag .. "son gün çarpanı", ev.finalDayMul >= 1)
			ok(tag .. "yol adı", #ev.text.path > 0)
			local prevGoal = 0
			for i, tier in ev.community.tiers do
				ok(tag .. "ortak hedef sıralı " .. i, tier.at > prevGoal)
				prevGoal = tier.at
				local kind = tier.reward.kind
				ok(tag .. "ortak hedef ödülü " .. i, kind == "unit" or kind == "spins" or kind == "superspin" or kind == "cash" or kind == "potion")
			end
			ok(tag .. "ortak hedef adı", #ev.community.name > 0)
		end
		checkDef(e, "aktif: ")
		checkDef(Config.SpookyEventDraft, "cadılar: ")
		ok("taslak aktifle çakışmıyor", Config.SpookyEventDraft.startsAt >= e.endsAt)

		local unitItem, spinItem, hatItem
		for _, item in e.shop do
			if item.kind == "unit" and not unitItem then
				unitItem = item
			elseif item.kind == "superspin" and not spinItem then
				spinItem = item
			elseif item.kind == "cosmetic" and not hatItem then
				local def = Config.GetCosmetic(item.cosmetic :: string)
				if def and def.kind == "hat" then
					hatItem = item
				end
			end
		end
		ok("dükkânda karakter, çark ve şapka var", unitItem ~= nil and spinItem ~= nil and hatItem ~= nil)
		for _, def in Config.LimitedCosmetics do
			ok(def.id .. " sınırlı listede etkinliğe bağlı", def.limited ~= "")
			if def.kind == "hat" then
				local model = CosmeticModel.BuildHat(def.id, true)
				ok(def.id .. " (sınırlı) modeli", model ~= nil and model.PrimaryPart ~= nil)
				if model then
					model:Destroy()
				end
			end
		end
		ok("sınırlı kozmetik parayla alınmıyor", not CosmeticService.TryBuy(ctx.player, hatItem.cosmetic))

		-- Lobi tabelası: yaklaşırken ve sürerken etkinlik, bitince güncelleme
		ok("tabela: yaklaşırken etkinlik", (LobbyBoardService.EventHeadline(e.startsAt - 3600)) ~= nil)
		ok("tabela: sürerken etkinlik", (LobbyBoardService.EventHeadline(e.startsAt + 60)) ~= nil)
		eq("tabela: bitince güncelleme", (LobbyBoardService.EventHeadline(e.endsAt + 60)), nil)

		-- Etkinlik dışında: şeker yok, dükkân kapalı
		e.startsAt, e.endsAt = os.time() + 3600, os.time() + 7200
		eq("dışarıda soygun şekeri yok", Config.GetHeistCandy("RedCrew", nil, os.time()), 0)
		ok("dışarıda dükkân kapalı", not (LimitedEventService.Buy(ctx.player, spinItem.id)))

		-- Takvim: yağmur yalnızca etkinlikte
		local shower: Config.EventDef? = nil
		for _, def in Config.Events do
			if def.id == "EventShower" then
				shower = def
			end
		end
		ok("yağmur takvimde", shower ~= nil and shower.limited == true)
		if shower then
			ok("dışarıda yağmur yok", not Config.IsEventScheduled(shower, os.time()))
		end
		eq("dışarıda yağmur başlamıyor", LimitedEventService.StartShower(), nil)

		-- Etkinlik sürerken (son gün değil)
		e.startsAt, e.endsAt = os.time() - 60, os.time() + 3 * 86400
		local common = e.candyByRarity.Common
		ok("son gün değil", not Config.IsEventFinalDay(os.time()))
		eq("sade soygun", Config.GetHeistCandy("RedCrew", nil, os.time()), common)
		eq("mutasyonlu soygun", Config.GetHeistCandy("RedCrew", "Golden", os.time()), common * e.mutationCandyMul)
		eq("etkinlik mutasyonlu soygun", Config.GetHeistCandy("RedCrew", e.mutation, os.time()), common * e.eventMutationMul)
		if shower then
			ok("etkinlikte yağmur var", Config.IsEventScheduled(shower, os.time()))
		end
		local sh = e.shower
		local amount, super = LimitedEventService.RollStar(0.99, sh.max + 50)
		ok("yıldız en fazla max", amount == sh.max and not super)
		amount, super = LimitedEventService.RollStar(0, nil)
		ok("SUPERNOVA", amount == sh.superAmount and super)
		eq("takvim 1. gün", Config.EventDailyAmount(1), e.dailyLadder[1])
		eq("takvim sonrası son değer", Config.EventDailyAmount(20), e.dailyLadder[#e.dailyLadder])

		-- Son gün: her şey finalDayMul katı, tabela söylüyor
		e.endsAt = os.time() + 3600
		ok("son gün", Config.IsEventFinalDay(os.time()))
		eq("son gün soygun", Config.GetHeistCandy("RedCrew", nil, os.time()), common * e.finalDayMul)
		amount = LimitedEventService.RollStar(0.99, sh.min)
		eq("son gün yıldız", amount, sh.min * e.finalDayMul)
		local title = LobbyBoardService.EventHeadline(os.time())
		ok("tabela son gün", title ~= nil and string.find(title :: string, "FINAL") ~= nil)
		e.endsAt = os.time() + 3 * 86400

		-- Eski etkinliğin sayacı sıfırlanıyor
		p.limited = { id = "OldEvent", candy = 999, bought = { X = 1 }, lastDaily = 0, earned = 999, awarded = 0, days = 4, ms = 3, gt = 2 }
		LimitedEventService.Publish(ctx.player)
		eq("yeni etkinlikte şeker sıfır", p.limited.candy, 0)
		eq("yeni etkinlikte takvim sıfır", p.limited.days, 0)
		eq("yeni etkinlikte yol sıfır", p.limited.ms, 0)
		eq("yeni etkinlikte ortak kademe sıfır", p.limited.gt, 0)
		eq("nitelik", ctx.player:GetAttribute("EventCandy"), 0)

		ok("günlük bonus", LimitedEventService.Daily(ctx.player))
		eq("bonus şekeri (1. gün)", p.limited.candy, e.dailyLadder[1])
		eq("takvim günü", p.limited.days, 1)
		eq("gün niteliği", ctx.player:GetAttribute("EventDays"), 1)
		eq("bugün alındı niteliği", ctx.player:GetAttribute("EventDayDone"), true)
		ok("aynı gün ikinci bonus yok", not LimitedEventService.Daily(ctx.player))
		-- Takvimin ilerisi: 7. gün büyük ödül
		p.limited.days, p.limited.lastDaily, p.limited.candy = 6, 0, 0
		ok("7. gün", LimitedEventService.Daily(ctx.player))
		eq("7. gün şekeri", p.limited.candy, e.dailyLadder[7])

		-- Yıldız yolu: basamağa varınca kendiliğinden, sırayla; atlamada hepsi
		clearPlot(ctx.plot)
		p.limited.earned, p.limited.ms, p.limited.candy = 0, 0, 0
		local ms = e.milestones
		local tokens = p.spinTokens
		LimitedEventService.AddCandy(ctx.player, ms[1].at - 1)
		eq("basamağın altında ödül yok", p.limited.ms, 0)
		LimitedEventService.AddCandy(ctx.player, 1)
		eq("1. basamak", p.limited.ms, 1)
		if ms[1].reward.kind == "spins" then
			eq("1. basamak çarkları", p.spinTokens, tokens + (ms[1].reward.count or 1))
		end
		eq("yol niteliği", ctx.player:GetAttribute("EventMs"), 1)
		local unitStep = 0
		for i, step in ms do
			if step.reward.kind == "unit" and unitStep == 0 then
				unitStep = i
			end
		end
		if unitStep > 0 then
			LimitedEventService.AddCandy(ctx.player, ms[unitStep].at - p.limited.earned)
			eq("atlayınca aradakiler de", p.limited.ms, unitStep)
			local starborn = false
			for _, podium in PlotService.GetUnlockedPodiums(ctx.plot) do
				if podium:GetAttribute("MutationId") == e.mutation then
					starborn = true
				end
			end
			ok("yol mürettebatı etkinlik mutasyonlu", starborn)
		end
		eq("yol candy'yi harcamıyor", p.limited.candy, p.limited.earned)
		clearPlot(ctx.plot)
		p.limited.ms = #ms
		eq("yolun sonu", (Config.EventNextMilestone(#ms)), nil)

		-- Ortak hedef: toplam artıyor, kademeye varınca oynamış herkese, bir kez
		local tiers = e.community.tiers
		LimitedEventService._SetCommunity(0)
		local beforeGoal = LimitedEventService.CommunityTotal()
		LimitedEventService.AddCandy(ctx.player, 7)
		eq("ortak toplama eklendi", LimitedEventService.CommunityTotal(), beforeGoal + 7)
		p.limited.gt = 0
		LimitedEventService._SetCommunity(tiers[1].at - 1)
		eq("kademe altında ödül yok", LimitedEventService.CheckCommunity(ctx.player), 0)
		local goalTokens = p.spinTokens
		LimitedEventService._SetCommunity(tiers[1].at)
		eq("1. kademe", LimitedEventService.CheckCommunity(ctx.player), 1)
		eq("kademe sayacı", p.limited.gt, 1)
		if tiers[1].reward.kind == "spins" then
			eq("1. kademe çarkları", p.spinTokens, goalTokens + (tiers[1].reward.count or 1))
		end
		eq("aynı kademe ikinci kez yok", LimitedEventService.CheckCommunity(ctx.player), 0)
		clearPlot(ctx.plot)
		LimitedEventService._SetCommunity(tiers[#tiers].at)
		LimitedEventService.CheckCommunity(ctx.player)
		eq("bütün kademeler", p.limited.gt, #tiers)
		clearPlot(ctx.plot)
		local keepEarned = p.limited.earned
		p.limited.earned, p.limited.gt = 0, 0
		eq("oynamayana ortak ödül yok", LimitedEventService.CheckCommunity(ctx.player), 0)
		p.limited.earned, p.limited.gt = keepEarned, #tiers
		LimitedEventService._CommunityTick()
		eq("toplam yayınlandı", workspace:GetAttribute("EventGlobal"), tiers[#tiers].at)
		local g1, g2 = LobbyBoardService.GoalColumn(os.time(), 12345)
		ok("tabela ortak hedef", g1 == e.community.name and g2 ~= nil and string.find(g2 :: string, "12,345") ~= nil, tostring(g2))
		ok("tabela hepsi bitti", (select(2, LobbyBoardService.GoalColumn(os.time(), tiers[#tiers].at))) == "ALL GOALS DONE!")
		eq("etkinlik öncesi beğeni hedefi", (LobbyBoardService.GoalColumn(e.startsAt - 10, 0)), nil)

		-- Yağmur: yıldızlar uzaya düşüyor, ilk dokunan alıyor, bitince kayboluyor
		local stop = LimitedEventService.StartShower()
		ok("yağmur başladı", stop ~= nil)
		if stop then
			local list = LimitedEventService._Stars()
			ok("yıldız düştü", #list > 0 and workspace:FindFirstChild("EventStars") ~= nil)
			if #list > 0 then
				local before = p.limited.candy
				local got = LimitedEventService._CollectStar(ctx.player, 1)
				ok("yıldız verdi", got > 0)
				eq("yıldız parası", p.limited.candy, before + got)
			end
			stop()
			eq("bitince yıldız yok", workspace:FindFirstChild("EventStars"), nil)
			eq("liste boş", #LimitedEventService._Stars(), 0)
		end

		-- Dükkân
		p.limited.candy = 0
		ok("parasız alınmıyor", not (LimitedEventService.Buy(ctx.player, spinItem.id)))
		LimitedEventService.AddCandy(ctx.player, 5000)
		eq("para eklendi", p.limited.candy, 5000)
		local spins = p.superSpins
		ok("süper çark alındı", (LimitedEventService.Buy(ctx.player, spinItem.id)))
		eq("süper çark hakkı", p.superSpins, spins + 1)
		eq("para düştü", p.limited.candy, 5000 - spinItem.price)

		local hatId = hatItem.cosmetic :: string
		p.cosmetics[hatId] = nil
		ok("sınırlı şapka alındı", (LimitedEventService.Buy(ctx.player, hatItem.id)))
		ok("sahibi", p.cosmetics[hatId] == true)
		eq("takıldı", p.hat, hatId)
		ok("sınır dolunca alınmıyor", not (LimitedEventService.Buy(ctx.player, hatItem.id)))
		ok("bilinmeyen ürün yok", not (LimitedEventService.Buy(ctx.player, "Nope")))

		-- Robux paketleri: yalnızca harcanabilir para, yarışa sayılmıyor
		local prevAmount = 0
		for i, key in Config.EventProductOrder do
			local def = Config.EventProducts[key]
			ok("paket tanımlı " .. key, def ~= nil and def.kind == "stardust")
			if def then
				ok("paket büyüyor " .. i, def.amount > prevAmount)
				ok("büyük paket Robux başına kârlı " .. i, i == 1 or def.amount / def.robux >= Config.EventProducts[Config.EventProductOrder[i - 1]].amount / Config.EventProducts[Config.EventProductOrder[i - 1]].robux)
				prevAmount = def.amount
			end
		end
		local candyBefore, earnedBefore = p.limited.candy, p.limited.earned
		local goalBefore = LimitedEventService.CommunityTotal()
		ok("paket verildi", LimitedEventService.GrantPurchased(ctx.player, 150))
		eq("paket parası", p.limited.candy, candyBefore + 150)
		eq("paket sıralamaya sayılmıyor", p.limited.earned, earnedBefore)
		eq("paket ortak hedefe sayılmıyor", LimitedEventService.CommunityTotal(), goalBefore)

		clearPlot(ctx.plot)
		ok("etkinlik mutasyonlu karakter alındı", (LimitedEventService.Buy(ctx.player, unitItem.id)))
		local placed = false
		for _, podium in PlotService.GetUnlockedPodiums(ctx.plot) do
			if podium:GetAttribute("MutationId") == e.mutation then
				placed = true
			end
		end
		ok("kaidede etkinlik mutasyonu", placed)
		clearPlot(ctx.plot)

		-- Sıralama ödülü: etkinlik sürerken yok; bitince ilk 10'a sınırlı taç, bir kez
		local reward = e.leaderboard.reward
		p.cosmetics[reward] = nil
		local top = { { n = "A", v = 900, u = 1 }, { n = "B", v = 800, u = 2 }, { n = "Me", v = 700, u = ctx.player.UserId } }
		eq("sürerken ödül yok", LimitedEventService.Settle(ctx.player, top), nil)
		e.startsAt, e.endsAt = os.time() - 7200, os.time() - 10
		p.limited.awarded = 0
		eq("bitince sıra", LimitedEventService.Settle(ctx.player, top), 3)
		ok("sınırlı taç verildi", p.cosmetics[reward] == true)
		eq("ikinci kez yok", LimitedEventService.Settle(ctx.player, top), nil)
		p.cosmetics[reward] = nil
		p.limited.awarded = 0
		local far = {}
		for i = 1, e.leaderboard.rewardTop do
			table.insert(far, { n = "X" .. i, v = 1000 - i, u = i })
		end
		table.insert(far, { n = "Me", v = 1, u = ctx.player.UserId })
		eq("ilk 10 dışında sıra", LimitedEventService.Settle(ctx.player, far), e.leaderboard.rewardTop + 1)
		ok("ilk 10 dışına taç yok", p.cosmetics[reward] == nil)

		-- Geri yükle
		e.startsAt, e.endsAt = keepStart, keepEnd
		p.limited = keepLimited
		p.cosmetics, p.hat, p.trail = keepCos, keepHat, keepTrail
		p.superSpins = keepSuper
		p.spinTokens = keepTokens
		LimitedEventService._SetCommunity(keepGoal)
		workspace:SetAttribute("EventGlobal", keepGoal)
		LimitedEventService._SetTesting(false)
		ctx.player:SetAttribute("SpinTokens", keepTokens)
		ctx.player:SetAttribute("SuperSpins", keepSuper)
		CosmeticService.Apply(ctx.player)
		CosmeticService.Publish(ctx.player)
		LimitedEventService.Publish(ctx.player)
	end)

	-- ─── V. Gezegen savunması ──────────────────────────────────────────────────

	case("Savunma: dalga planı deterministik, kapı sabit, yollar alanda", function()
		local F = DefenseConfig.Field
		local a = DefenseConfig.BuildWave(1, 7, 4242, nil)
		local b = DefenseConfig.BuildWave(1, 7, 4242, nil)
		eq("aynı tohum aynı desen", a.pattern, b.pattern)
		eq("aynı tohum aynı sayı", #a.spawns, #b.spawns)
		eq("ilk dalga düz", DefenseConfig.BuildWave(1, 1, 99, nil).pattern, "straight")
		ok("5. dalga boss", DefenseConfig.BuildWave(1, 5, 99, nil).boss)
		ok("4. dalga boss değil", not DefenseConfig.BuildWave(1, 4, 99, nil).boss)
		local inside, ends = true, true
		for seed = 1, 40 do
			local plan = DefenseConfig.BuildWave(3, 2 + seed % 12, seed, nil)
			for _, path in plan.paths do
				if path[1] ~= F.entrance or path[#path] ~= F.gate then
					ends = false
				end
				for _, pt in path do
					if math.abs(pt.X) > F.halfWidth then
						inside = false
					end
				end
			end
		end
		ok("kapıdan çıkıp rampada bitiyor", ends)
		ok("yol alanın içinde", inside)
		local last = DefenseConfig.BuildWave(1, 6, 7, nil).pattern
		local repeatFree = true
		for seed = 1, 30 do
			if DefenseConfig.BuildWave(1, 6, seed, last).pattern == last then
				repeatFree = false
			end
		end
		ok("aynı desen arka arkaya gelmiyor", repeatFree)
	end)

	case("Savunma: güç farkı küçük, rol herkese var", function()
		near("Red Crewmate ~1", DefenseConfig.GetPower("RedCrew", nil), 1.02, 0.03)
		local top = DefenseConfig.GetPower("StarEmperor", "Impostor")
		ok("en güçlü < 2x", top < 2, tostring(top))
		ok("kazandıran daha güçlü", DefenseConfig.GetPower("Sheriff", nil) > DefenseConfig.GetPower("RedCrew", nil))
		for _, unit in Config.Units do
			if not DefenseConfig.UnitRoles[unit.id] then
				ok("rolü elle yazılmış: " .. unit.id, false)
			end
		end
		ok("bilinmeyen kimliğe de rol", DefenseConfig.GetRole("NoSuchUnit") ~= nil)
	end)

	case("Savunma: yıldız ve altın yalnızca yeni yıldızdan", function()
		eq("kayıpsız 3", DefenseConfig.StarsForLosses(0), 3)
		eq("2 kayıp 2", DefenseConfig.StarsForLosses(2), 2)
		eq("3 kayıp 1", DefenseConfig.StarsForLosses(3), 1)
		eq("3 yıldız 100", DefenseConfig.GoldForImprovement(1, 0, 3), 100)
		eq("1'den 3'e fark", DefenseConfig.GoldForImprovement(1, 1, 3), 70)
		eq("tekrar 3 yıldız 0", DefenseConfig.GoldForImprovement(1, 3, 3), 0)
		eq("düşen yıldız 0", DefenseConfig.GoldForImprovement(1, 3, 1), 0)
		ok("üst gezegen biraz fazla", DefenseConfig.GoldForStars(6, 3) > 100 and DefenseConfig.GoldForStars(6, 3) < 200)
	end)

	case("Savunma: sim — boş alan kaybediyor, güçlü ekip 1. dalgayı kayıpsız geçiyor", function()
		-- 1. dalgada 5 düşman var: gövde 3 iken boş alan dayanamıyor
		local empty = DefenseSim.New(1, 1, 5, {}, nil, 3, 3, nil)
		eq("kimse yok: kayıp", DefenseSim.RunToEnd(empty, 600), "lost")
		eq("düşmanlar gövdeyi yedi", empty.hull, 0)
		local V = Vector2.new
		-- Önde tank ve dövüşçü, arkada (yoldan uzakta) atıcı ve medic
		local crew = {
			{ uid = 1, unitId = "GalaxyGuardian", pos = V(0, 40) },
			{ uid = 2, unitId = "StarEmperor", pos = V(-12, 44) },
			{ uid = 3, unitId = "NebulaWizard", pos = V(12, 44) },
			{ uid = 4, unitId = "TitanHeart", pos = V(0, 48) },
		}
		local lv = { Brawler = 10, Guard = 10, Shooter = 10, Assassin = 10, Medic = 10 }
		local sim = DefenseSim.New(1, 1, 5, crew, lv, 25, 25, nil)
		eq("güçlü ekip kazanıyor", DefenseSim.RunToEnd(sim, 600), "won")
		eq("kayıp yok", sim.losses, 0)
		ok("hepsi öldü", sim.kills == #sim.plan.spawns, string.format("%d/%d", sim.kills, #sim.plan.spawns))
		-- Kilitlenme yok: uzaktaki tank + iyileştiren medic bile dalgayı bitiriyor
		local stuck = DefenseSim.New(1, 9, 11, { { uid = 1, unitId = "AmogusPrime", pos = V(60, 190) },
			{ uid = 2, unitId = "TheCrewmate", pos = V(58, 186) } }, lv, 25, 25, nil)
		ok("dalga sonsuza dek sürmüyor", DefenseSim.RunToEnd(stuck, 900) ~= "fight")
	end)

	case("Savunma: kayıt — hastane kalıyor, görevdeki kaideye dönüyor, alanlar temiz", function()
		local p = DataService._Sanitize({
			units = {
				{ slot = 1, unitId = "RedCrew", away = "hospital" },
				{ slot = 2, unitId = "BlueCrew", away = "mission" },
				{ slot = 3, unitId = "LimeCrew", away = "weird" },
			},
			defense = { gold = 150.7, slots = 2, hull = -3, roles = { Brawler = 4 },
				supports = { Strike = 2 }, planets = { ["1"] = { best = 3, stars = { 3, 2, 1 } }, bad = {} } },
		})
		eq("hastane kaldı", p.units[1].away, "hospital")
		eq("görev kaideye", p.units[2].away, nil)
		eq("bilinmeyen durum yok", p.units[3].away, nil)
		eq("altın", p.defense.gold, 150)
		eq("negatif gövde 0", p.defense.hull, 0)
		eq("rol", p.defense.roles.Brawler, 4)
		eq("destek", p.defense.supports.Strike, 2)
		eq("en iyi bölüm", p.defense.planets["1"].best, 3)
		eq("yıldız dize anahtarlı", p.defense.planets["1"].stars["2"], 2)
		eq("bozuk gezegen yok", p.defense.planets.bad, nil)
		eq("yeni oyuncu altını", DataService._Sanitize({}).defense.gold, 0)
	end)

	case("Savunma: seç → ele gelir, bırak → alanda; gelir yok, satılamaz; geri çekil → döner", function(ctx)
		clearPlot(ctx.plot)
		local podiums = PlotService.GetPodiums(ctx.plot)
		PlotService.PlaceUnit(podiums[1], "Sheriff")
		PlotService.PlaceUnit(podiums[2], "RedCrew")
		local slot = podiums[1]:GetAttribute("SlotIndex") :: number
		local slot2 = podiums[2]:GetAttribute("SlotIndex") :: number
		local before = EconomyService.GetIncome(ctx.player)
		local keepDefense = ctx.profile.defense
		ctx.profile.defense = { gold = 0, goldEarned = 0, slots = 0, hull = 0, saber = 0, roles = {}, supports = {}, planets = {} }
		DefenseService._setPlanet(ctx.player, 1)
		DefenseService._prepare(ctx.player, 1, { slot, slot2, slot }, "Lightsaber")
		local run = DefenseService._sessions[ctx.player].run
		ok("koşu başladı", run ~= nil and run.phase == "prep")
		eq("iki crewmate seçildi (tekrar sayılmıyor)", run and #run.units, 2)
		eq("kılıcı yoksa gear yok", run and run.gear, "")
		local function crewTools(): number
			local n = 0
			for _, container in { ctx.player:FindFirstChildOfClass("Backpack"), ctx.player.Character } do
				if container then
					for _, t in container:GetChildren() do
						if t:IsA("Tool") and t:GetAttribute("DefenseCrew") ~= nil then
							n += 1
						end
					end
				end
			end
			return n
		end
		eq("ikisi de elde", crewTools(), 2)
		eq("kaide görevde", PlotService.GetAway(podiums[1]), "mission")
		local uid1, uid2 = run.units[1].uid, run.units[2].uid
		ok("alana kondu", DefenseService._placeAt(ctx.player, uid1, Vector2.new(0, 40)))
		ok("gelir düştü", EconomyService.GetIncome(ctx.player) < before)
		ok("ayrıldı bayrağı", ctx.player:GetAttribute("DefenseDeployed") == true)
		local entry = nil
		for _, u in ctx.profile.units do
			if u.slot == slot then
				entry = u
			end
		end
		eq("kayıtta görevde", entry and entry.away, "mission")
		ok("aynı crewmate iki kez konmuyor", not DefenseService._placeAt(ctx.player, uid1, Vector2.new(10, 40)))
		ok("çok yakına konmuyor", not DefenseService._placeAt(ctx.player, uid2, Vector2.new(1, 41)))
		ok("alan dışına konmuyor", not DefenseService._placeAt(ctx.player, uid2, Vector2.new(0, 500)))
		local SellService = require(Server.SellService)
		ok("görevdeki satılamıyor", not SellService.Sell(ctx.player, podiums[1]))
		ok("rebirth kapalı", not RebirthService.TryRebirth(ctx.player, true))
		DefenseService._retreat(ctx.player)
		eq("kaideye döndü", PlotService.GetAway(podiums[1]), nil)
		eq("eldeki de döndü", PlotService.GetAway(podiums[2]), nil)
		eq("eldeki aletler gitti", crewTools(), 0)
		eq("gelir geri", EconomyService.GetIncome(ctx.player), before)
		ok("bayrak kalktı", ctx.player:GetAttribute("DefenseDeployed") == nil)
		ok("koşu bitti", DefenseService._sessions[ctx.player].run == nil)
		DefenseService._setPlanet(ctx.player, nil)
		ctx.profile.defense = keepDefense
		clearPlot(ctx.plot)
	end)

	case("Savunma: dalga kaybı → hastane; revive 15 dk'lık kazanç, let go siliyor", function(ctx)
		clearPlot(ctx.plot)
		local podiums = PlotService.GetPodiums(ctx.plot)
		PlotService.PlaceUnit(podiums[1], "RedCrew")
		PlotService.PlaceUnit(podiums[2], "BlueCrew")
		PlotService.PlaceUnit(podiums[3], "YellowCrew")
		local s1 = podiums[1]:GetAttribute("SlotIndex") :: number
		local s2 = podiums[2]:GetAttribute("SlotIndex") :: number
		local s3 = podiums[3]:GetAttribute("SlotIndex") :: number
		local keepDefense = ctx.profile.defense
		ctx.profile.defense = { gold = 0, goldEarned = 0, slots = 0, hull = 0, saber = 0, roles = {}, supports = {}, planets = {} }
		DefenseService._setPlanet(ctx.player, 1)
		DefenseService._prepare(ctx.player, 1, { s1, s2 }, "")
		local run = DefenseService._sessions[ctx.player].run
		-- Alanın en ucuna koy: düşmanlar yanından geçip gemiye ulaşsın. s2 elde kalıyor
		DefenseService._placeAt(ctx.player, run.units[1].uid, Vector2.new(60, 196))
		run.hull = 1
		DefenseService._go(ctx.player)
		eq("savaş başladı", run.phase, "fight")
		for _ = 1, 6000 do
			if DefenseService._sessions[ctx.player].run == nil then
				break
			end
			DefenseService._step(0.1)
		end
		ok("koşu bitti", DefenseService._sessions[ctx.player].run == nil)
		eq("hastanede", PlotService.GetAway(podiums[1]), "hospital")
		eq("dokunulmayan evde", PlotService.GetAway(podiums[2]), nil)
		local cost = DefenseService.GetReviveCost(ctx.player, "RedCrew", nil)
		local perSecond = EconomyService.GetUnitIncome(ctx.player, "RedCrew", nil)
		near("15 dk'lık kazanç", cost, math.max(100, math.ceil(perSecond * 900)), 1)
		setCash(ctx.player, cost - 1)
		ok("parası yetmiyor", not DefenseService.Revive(ctx.player, s1))
		setCash(ctx.player, cost + 10)
		ok("revive", DefenseService.Revive(ctx.player, s1))
		eq("para düştü", EconomyService.GetCash(ctx.player), 10)
		eq("kaideye döndü", PlotService.GetAway(podiums[1]), nil)
		PlotService.SetAway(podiums[3], "hospital")
		ok("let go", DefenseService.Release(ctx.player, s3))
		ok("kaide boşaldı", not PlotService.IsOccupied(podiums[3]))
		ok("evdekini let go olmuyor", not DefenseService.Release(ctx.player, s2))
		DefenseService._setPlanet(ctx.player, nil)
		ctx.profile.defense = keepDefense
		clearPlot(ctx.plot)
	end)

	case("Savunma: dükkânlar altın harcıyor, tavanı aşmıyor", function(ctx)
		local keepDefense = ctx.profile.defense
		ctx.profile.defense = { gold = 100, goldEarned = 0, slots = 0, hull = 0, roles = {}, supports = {}, planets = {} }
		ok("rol", DefenseService.Buy(ctx.player, "role", "Brawler"))
		eq("seviye 1", ctx.profile.defense.roles.Brawler, 1)
		eq("altın düştü", ctx.profile.defense.gold, 100 - (DefenseConfig.RoleUpgradeCost(0) :: number))
		ok("yetmeyen altın", not DefenseService.Buy(ctx.player, "slot"))
		ctx.profile.defense.gold = 100000
		for _ = 1, 20 do
			DefenseService.Buy(ctx.player, "slot")
		end
		eq("slot tavanı", DefenseConfig.GetSlots(ctx.profile.defense.slots), DefenseConfig.BaseSlots + #DefenseConfig.SlotCosts)
		for _ = 1, 10 do
			DefenseService.Buy(ctx.player, "support", "Strike")
		end
		eq("destek tavanı", ctx.profile.defense.supports.Strike, DefenseConfig.SupportStack)
		ok("bilinmeyen tür", not DefenseService.Buy(ctx.player, "free", "gold"))
		ok("bilinmeyen rol", not DefenseService.Buy(ctx.player, "role", "God"))
		ctx.profile.defense = keepDefense
	end)

	case("Savunma: gezegen kilidi rebirth ve önceki gezegen", function(ctx)
		local keepDefense = ctx.profile.defense
		local keepReb = ctx.profile.rebirths
		ctx.profile.defense = { gold = 0, goldEarned = 0, slots = 0, hull = 0, roles = {}, supports = {}, planets = {} }
		ctx.profile.rebirths = 0
		ok("ilk gezegen açık", (DefenseService.IsPlanetUnlocked(ctx.profile, 1)))
		ok("ikinci kapalı", not (DefenseService.IsPlanetUnlocked(ctx.profile, 2)))
		ctx.profile.defense.planets["1"] = { best = DefenseConfig.UnlockSectors, stars = {} }
		ok("bölüm bitince açık", (DefenseService.IsPlanetUnlocked(ctx.profile, 2)))
		for i = 1, 6 do
			ctx.profile.defense.planets[tostring(i)] = { best = 9, stars = {} }
		end
		ok("rebirth gezegeni kilitli", not (DefenseService.IsPlanetUnlocked(ctx.profile, 7)))
		ctx.profile.rebirths = 2
		ok("rebirth 2 ile açık", (DefenseService.IsPlanetUnlocked(ctx.profile, 7)))
		ctx.profile.defense = keepDefense
		ctx.profile.rebirths = keepReb
	end)

	case("Savunma: ışın kılıcı altınla alınıyor, yükseliyor, önündeki düşmana vuruyor", function(ctx)
		local keepDefense = ctx.profile.defense
		ctx.profile.defense = { gold = 1000, goldEarned = 0, slots = 0, hull = 0, saber = 0, roles = {}, supports = {}, planets = {} }
		local S = DefenseConfig.Saber
		ok("alındı", DefenseService.Buy(ctx.player, "saber"))
		eq("seviye 1", ctx.profile.defense.saber, 1)
		eq("fiyat düştü", ctx.profile.defense.gold, 1000 - S.price)
		ctx.profile.defense.gold = 100000
		for _ = 1, 10 do
			DefenseService.Buy(ctx.player, "saber")
		end
		eq("tavan", ctx.profile.defense.saber, #S.upgradeCosts + 1)
		ok("tavanda alınmıyor", not DefenseService.Buy(ctx.player, "saber"))
		ok("seviye hasarı artırıyor", DefenseConfig.SaberDamage(5, 1) > DefenseConfig.SaberDamage(1, 1))

		-- Sim: önündeki düşmana vuruyor, arkasındakine değil
		local sim = DefenseSim.New(1, 1, 3, {}, nil, 25, 25, nil)
		for _ = 1, 200 do
			DefenseSim.Step(sim, 0.1)
			if #sim.enemies > 0 then
				break
			end
		end
		local e = sim.enemies[1]
		ok("düşman çıktı", e ~= nil)
		if e then
			local before = e.hp
			-- Düşmanın 4 stud gerisinde, ona dönük
			local at = e.pos + Vector2.new(0, 4)
			eq("arkaya bakınca vurmuyor", DefenseSim.Slash(sim, at, Vector2.new(0, 1), S.radius, 5), 0)
			eq("önüne bakınca vuruyor", DefenseSim.Slash(sim, at, Vector2.new(0, -1), S.radius, 5), 1)
			near("hasar", e.hp, before - 5, 0.01)
			eq("uzaktakine değmiyor", DefenseSim.Slash(sim, e.pos + Vector2.new(0, 40), Vector2.new(0, -1), S.radius, 5), 0)
		end
		ctx.profile.defense = keepDefense
	end)

	case("Savunma: ışın tabancası alınıyor, önündeki en yakın düşmanı vuruyor", function(ctx)
		local keepDefense = ctx.profile.defense
		ctx.profile.defense = { gold = 1000, goldEarned = 0, slots = 0, hull = 0, saber = 0, raygun = 0, roles = {}, supports = {}, planets = {} }
		local R = DefenseConfig.RayGun
		ok("alındı", DefenseService.Buy(ctx.player, "raygun"))
		eq("seviye 1", ctx.profile.defense.raygun, 1)
		eq("fiyat düştü", ctx.profile.defense.gold, 1000 - R.price)
		ctx.profile.defense.gold = 100000
		for _ = 1, 10 do
			DefenseService.Buy(ctx.player, "raygun")
		end
		eq("tavan", ctx.profile.defense.raygun, #R.upgradeCosts + 1)
		local sim = DefenseSim.New(1, 1, 3, {}, nil, 25, 25, nil)
		for _ = 1, 200 do
			DefenseSim.Step(sim, 0.1)
			if #sim.enemies > 0 then
				break
			end
		end
		local e = sim.enemies[1]
		ok("düşman çıktı", e ~= nil)
		if e then
			local at = e.pos + Vector2.new(0, 12)
			eq("arkaya ateş boşa", DefenseSim.Shoot(sim, at, Vector2.new(0, 1), R.range, R.cone, 5), nil)
			eq("önüne ateş vuruyor", DefenseSim.Shoot(sim, at, Vector2.new(0, -1), R.range, R.cone, 5), e.eid)
			eq("menzil dışı boşa", DefenseSim.Shoot(sim, e.pos + Vector2.new(0, R.range + 5), Vector2.new(0, -1), R.range, R.cone, 5), nil)
		end
		ctx.profile.defense = keepDefense
	end)

	case("Savunma: crewmate menzilindeki düşmana yürüyor, tasmadan öteye gitmiyor, sonra dönüyor", function()
		local post = Vector2.new(20, 60)
		local sim = DefenseSim.New(1, 1, 3, { { uid = 1, unitId = "RedCrew", pos = post } }, nil, 25, 25, nil)
		-- Gerçek dalga çıkmasın: yalnızca elle konan düşman
		sim.plan.spawns = {}
		local u = sim.units[1]
		local role = DefenseConfig.Roles[u.role]
		-- Elle düşman: karakolun yanında (tasma + menzil içinde)
		sim.enemies[1] = {
			eid = 99, kind = "Grub", path = 1, lane = 0, dist = 1000, pos = post + Vector2.new(role.leash, 0),
			hp = 1e6, maxHp = 1e6, dmg = 0, speed = 0, range = 0, cooldown = 1, timer = 1, leak = 0, cleave = 0,
			foe = nil, offPath = true,
		}
		for _ = 1, 30 do
			DefenseSim.Step(sim, 0.1)
		end
		ok("düşmana doğru yürüdü", (u.pos - post).Magnitude > 3, tostring((u.pos - post).Magnitude))
		ok("tasmayı aşmadı", (u.pos - post).Magnitude <= role.leash + 0.01)
		-- Düşman uzaklaştı (dalga bitmesin diye silinmiyor)
		sim.enemies[1].pos = post + Vector2.new(0, 120)
		for _ = 1, 60 do
			DefenseSim.Step(sim, 0.1)
		end
		ok("karakoluna döndü", (u.pos - post).Magnitude < 0.5, tostring((u.pos - post).Magnitude))
	end)
end

return ServerTests2
