--!strict
--[[
	Petler: yumurta açma, envanter, takma ve peşinden gelme.

	═══ GÜVENLİK ══════════════════════════════════════════════════════════

	İstemciden üç remote dinleniyor ve hiçbiri bedava bir şey VERMİYOR:

	  PetHatch — oyuncunun KENDİ parasını harcıyor. Fiyatı ve çekilişi
	             sunucu yapıyor; istemci yalnızca hangi yumurta olduğunu
	             söylüyor ve o kimlik Config'de aranıyor.
	  PetEquip — zaten sahip olunan bir peti takıyor/çıkarıyor. Sahiplik
	             profilden doğrulanıyor, slot sayısı sunucuda sınırlanıyor.
	  PetFuse  — üç kopyayı yakıp bir tane veriyor. Adet sunucuda
	             sayılıyor, sonuç sunucuda çekiliyor.

	Lobideki yumurta standı remote kullanmıyor: ProximityPrompt doğrudan
	sunucuda tetikleniyor ve PromptGuard'dan geçiyor.

	Envanter ANAHTAR tutuyor: "MiniCrew" ya da "MiniCrew:Golden"
	(Config.PetKey). Mutasyonlu kopya ayrı satır, ayrı eşya.

	═══ BONUSLAR NASIL ULAŞIYOR ═══════════════════════════════════════════

	EconomyService ve StealService peti BİLMİYOR. Bunun yerine bu servis
	oyuncuya iki nitelik yazıyor:

	    PetIncomeBonus  (gelire eklenen oran)
	    PetSpeedBonus   (taşıma hızına eklenen stud/s)

	Neden nitelik? Çünkü doğrudan require etmek DÖNGÜ yaratıyordu:
	yumurta açmak EconomyService.TrySpend'e muhtaç, gelir hesabı da
	PetService'e muhtaç olurdu. Nitelik tek yönlü bir kanal ve istemci
	onu yazamıyor — aynı yöntem yükseltmelerde de kullanılıyor.

	═══ TAKİP ═════════════════════════════════════════════════════════════

	Pet modeli Anchored ve her karede CFrame'i elle yazılıyor. Fizik
	(BodyPosition / AlignPosition) denendi: petler duvarlara takılıyor,
	oyuncuyu itiyor ve sunucuda fizik maliyeti çıkarıyorlardı. Anchored
	takip görsel olarak aynı, hiçbir şeye çarpmıyor ve bedava.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PetModel = require(Shared.PetModel)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local AnnounceService = require(script.Parent.AnnounceService)
local PromptGuard = require(script.Parent.PromptGuard)

local PetService = {}

local NOTIFY_KIND = "pet"
PetService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent
local petsRemote: RemoteEvent
local hatchedRemote: RemoteEvent

-- Summons kanalına düşecek kademeler: konveyördekiyle aynı eşik
local ANNOUNCE_RARITIES = { Mythic = true, Secret = true }

-- Oyuncu -> sahadaki pet modelleri (takılı sırada)
local spawned: { [Player]: { Model } } = {}

local rng = Random.new()

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, NOTIFY_KIND)
	end
end

-- ─── Envanter ───────────────────────────────────────────────────────────────

--[[
	İstemciye giden tablo. Config'i istemci de okuyabiliyor ama sahiplik
	ve takılı sıra sunucunun bilgisi; sadece onlar gidiyor.
]]
local function push(player: Player)
	local profile = DataService.Get(player)
	if not profile or not petsRemote then
		return
	end

	petsRemote:FireClient(player, {
		owned = table.clone(profile.pets),
		equipped = table.clone(profile.equippedPets),
	})
end

--[[
	Bonusları niteliklere yazar ve sahadaki petleri tazeler.

	Tek giriş noktası: envanter değişen her yol buradan geçiyor, böylece
	"bonus yazılmayı unuttu" hatası mümkün değil.
]]
local function apply(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local income, speed = Config.GetPetBonus(profile.equippedPets)
	player:SetAttribute("PetIncomeBonus", income)
	player:SetAttribute("PetSpeedBonus", speed)

	PetService.Respawn(player)
	push(player)
end

PetService.Apply = apply

-- ─── Sahadaki petler ────────────────────────────────────────────────────────

local function clearSpawned(player: Player)
	local own = spawned[player]
	if not own then
		return
	end
	for _, model in own do
		model:Destroy()
	end
	spawned[player] = nil
end

--[[
	Takılı petlerin modellerini kurar. Zaten doğru petler duruyorsa
	hiçbir şey yapmıyor — her bonus güncellemesinde modelleri yıkıp
	yeniden kurmak petlerin gözle görülür şekilde "zıplamasına" yol
	açıyordu.
]]
function PetService.Respawn(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		clearSpawned(player)
		return
	end

	local wanted = profile.equippedPets
	local own = spawned[player]

	if own and #own == #wanted then
		local same = true
		for index, model in own do
			if model.Name ~= wanted[index] or not model.Parent then
				same = false
				break
			end
		end
		if same then
			return
		end
	end

	clearSpawned(player)

	if #wanted == 0 then
		return
	end

	local folder = workspace:FindFirstChild("Pets")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Pets"
		folder.Parent = workspace
	end

	local models: { Model } = {}
	for index, id in wanted do
		if index > Config.PetEquipSlots then
			break
		end
		local model = PetModel.Build(id)
		if model then
			model.Parent = folder
			table.insert(models, model)
		end
	end

	if #models > 0 then
		spawned[player] = models
	end
end

--[[
	Petleri oyuncunun arkasına dizer.

	Yerleşim: oyuncunun ARKASINDA, yana yayılmış ve hafif salınan bir yay.
	Öne koysaydık görüşü kapatırlardı; tam arkaya üst üste koysaydık üç pet
	tek pet gibi görünürdü.

	Yumuşatma (lerp) şart: doğrudan hedefe yazmak peti oyuncuya kilitliyor
	ve pet "takip eden bir şey" değil "karaktere yapışmış bir parça" gibi
	duruyor.
]]
local function stepFollow(delta: number)
	local now = os.clock()
	local alpha = math.clamp(delta * 6, 0, 1)

	for player, models in spawned do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

		if not root then
			for _, model in models do
				model.Parent = nil
			end
			continue
		end

		local count = #models
		for index, model in models do
			local primary = model.PrimaryPart
			if not primary then
				continue
			end

			if not model.Parent then
				local folder = workspace:FindFirstChild("Pets")
				if folder then
					model.Parent = folder
				end
			end

			-- Yay: tek pet tam arkada, üç pet -1/0/+1 sütunlarda
			local spread = if count > 1 then (index - 1) / (count - 1) - 0.5 else 0
			local offset = Vector3.new(spread * 5.5, 0, 4.2 + math.abs(spread) * 1.2)

			-- Her pet kendi fazında süzülüyor; aynı anda inip kalkarlarsa
			-- tek bir nesnenin kopyaları gibi duruyorlar
			local bob = math.sin(now * 2.4 + index * 1.7) * 0.22
			local target = root.CFrame * CFrame.new(offset) + Vector3.new(0, 1.4 + bob, 0)
			local goal = CFrame.new(target.Position, target.Position + root.CFrame.LookVector)

			model:PivotTo(primary.CFrame:Lerp(goal, alpha))
		end
	end
end

-- ─── İşlemler ───────────────────────────────────────────────────────────────

--[[
	Envantere bir anahtar ekler; tavandaysa false döner.

	İlk pet otomatik takılıyor. Yoksa oyuncu yumurtayı açıyor, bir şey
	kazandığını görüyor ama hiçbir şey değişmiyor ve sistemi anlamadan
	bırakıyor.
]]
local function grant(player: Player, key: string): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local have = profile.pets[key] or 0
	if have >= Config.PetStackLimit then
		return false
	end

	profile.pets[key] = have + 1
	if #profile.equippedPets < Config.PetEquipSlots and not table.find(profile.equippedPets, key) then
		table.insert(profile.equippedPets, key)
	end
	return true
end

--[[ "Golden Mini Crew" gibi okunur ad. ]]
local function displayName(key: string): string
	local def, mutation = Config.ParsePetKey(key)
	if not def then
		return key
	end
	return if mutation then mutation.name .. " " .. def.name else def.name
end

--[[
	Nadir sonuçları Summons kanalına yazar. Kademe VE mutasyon ayrı
	ayrı sayılıyor: Cosmic bir Common da en nadir mutasyon, duyurulmaya
	değer.
]]
local function announce(player: Player, key: string, verb: string)
	local def, mutation = Config.ParsePetKey(key)
	if not def then
		return
	end
	local rare = ANNOUNCE_RARITIES[def.rarity] or (mutation ~= nil and mutation.id == "Cosmic")
	if not rare then
		return
	end
	local rarity = Config.Rarities[def.rarity]
	AnnounceService.Summon(string.format("%s %s a %s!",
		player.DisplayName, verb, AnnounceService.Paint(displayName(key), rarity.color)))
end

--[[
	Yumurta açar. Başarılıysa envanter anahtarını döndürür.

	Çekiliş ÖNCE, harcama SONRA. Tersi olsaydı çekiliş nil dönen bir
	yapılandırma hatasında ya da tavana çarpan bir sonuçta oyuncunun
	parası hiçbir şey vermeden yanardı.
]]
function PetService.TryHatch(player: Player, eggId: string): string?
	local egg = Config.GetEgg(eggId)
	if not egg then
		notify(player, "That egg does not exist", true)
		return nil
	end

	local profile = DataService.Get(player)
	if not profile then
		return nil
	end

	local def = Config.RollPet(rng, eggId)
	if not def then
		notify(player, "That egg is empty", true)
		return nil
	end

	local mutation = Config.RollPetMutation(rng)
	local key = Config.PetKey(def.id, if mutation then mutation.id else nil)

	if (profile.pets[key] or 0) >= Config.PetStackLimit then
		notify(player, string.format("You already have %d %s", Config.PetStackLimit, displayName(key)), true)
		return nil
	end

	if not EconomyService.TrySpend(player, egg.price) then
		notify(player, "Not enough cash for that egg", true)
		return nil
	end

	grant(player, key)
	apply(player)

	notify(player, string.format("%s hatched a %s!", egg.name, displayName(key)), false)
	if hatchedRemote then
		hatchedRemote:FireClient(player, key, "egg")
	end
	announce(player, key, "hatched")
	return key
end

--[[
	Üç kopyayı bir üst kademeye birleştirir. Başarılıysa yeni anahtarı
	döndürür.

	Mutasyon KORUNUYOR: üç Golden Common -> bir Golden Uncommon. Böylece
	mutasyonlu kopya biriktirmenin de bir karşılığı var.

	Kopyalar yandıktan sonra elde kalmayan anahtar takılıysa çıkarılıyor;
	yoksa bonus artık sahip olunmayan bir petten gelmeye devam ederdi.
]]
function PetService.TryFuse(player: Player, key: string): string?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end

	local def, mutation = Config.ParsePetKey(key)
	if not def then
		return nil
	end

	local have = profile.pets[key] or 0
	if have < Config.PetFuseCount then
		notify(player, string.format("You need %d of the same pet to fuse", Config.PetFuseCount), true)
		return nil
	end

	local nextRarity = Config.GetNextRarity(def.rarity)
	if not nextRarity then
		notify(player, "Secret pets are already the top tier", true)
		return nil
	end

	local result = Config.RollPetOfRarity(rng, nextRarity)
	if not result then
		return nil
	end

	local newKey = Config.PetKey(result.id, if mutation then mutation.id else nil)
	if (profile.pets[newKey] or 0) >= Config.PetStackLimit then
		notify(player, string.format("You already have %d %s", Config.PetStackLimit, displayName(newKey)), true)
		return nil
	end

	local left = have - Config.PetFuseCount
	profile.pets[key] = if left > 0 then left else nil
	if left <= 0 then
		local index = table.find(profile.equippedPets, key)
		if index then
			table.remove(profile.equippedPets, index)
		end
	end

	grant(player, newKey)
	apply(player)

	notify(player, string.format("Fused into a %s!", displayName(newKey)), false)
	if hatchedRemote then
		hatchedRemote:FireClient(player, newKey, "fuse")
	end
	announce(player, newKey, "fused")
	return newKey
end

--[[
	Peti takar ya da çıkarır. Dönen değer işlemin tuttuğu.

	Aynı anahtar iki slotta duramıyor: kopya takmak bonusu katlardı ve
	"çeşit topla" hedefi anlamsızlaşırdı. Düz ve Golden aynı pet farklı
	anahtar sayılıyor — mutasyonlu kopya ayrı bir eşya.
]]
function PetService.TryEquip(player: Player, key: string, equip: boolean): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local index = table.find(profile.equippedPets, key)

	if not equip then
		if not index then
			return false
		end
		table.remove(profile.equippedPets, index)
		apply(player)
		return true
	end

	if index then
		return false
	end

	if (profile.pets[key] or 0) <= 0 then
		notify(player, "You do not own that pet", true)
		return false
	end

	if #profile.equippedPets >= Config.PetEquipSlots then
		notify(player, string.format("Only %d pets at a time", Config.PetEquipSlots), true)
		return false
	end

	table.insert(profile.equippedPets, key)
	apply(player)
	return true
end

-- ─── Lobideki yumurta standı ────────────────────────────────────────────────

--[[
	Yumurtaların dünyadaki yeri. Panelden de açılabiliyor ama kazanma anı
	ekranda değil DÜNYADA olmalı: oyuncu bir şeyin önünde durup ona
	basıyor, etrafındakiler de görüyor.

	═══ KONUM ══════════════════════════════════════════════════════════════

	Çarkın AYNASI: lobinin orta eksenine göre simetrik. Çark sol tarafta
	(x=86..116), stand sağda aynı yerde. Konum sabit yazılmıyor, lobi
	zemininden ve çarkın kendisinden hesaplanıyor — lobi yeniden kurulursa
	stand yine doğru yere düşüyor.

	Ölçüldü: aynadaki bölgede (x 244..274, z 317..335) hiçbir parça yok.
	En yakın komşu sağdaki dolap (x 275'te başlıyor, 1 stud boşluk) ve
	arkadaki heykel kaidesi (z 342.7'de başlıyor).

	Stand sunucuda kuruluyor (build_decor'da değil) çünkü promptlarının
	sunucu mantığına bağlanması gerekiyor.
]]
local SHELL = Color3.fromRGB(58, 66, 78)
local SHELL_DARK = Color3.fromRGB(34, 39, 47)
local TRIM = Color3.fromRGB(150, 160, 172)
local HAZARD = Color3.fromRGB(240, 196, 60)

local function eggTint(egg: Config.EggDef): Color3
	local best, bestOrder = TRIM, 0
	for rarity in egg.weights do
		local info = Config.Rarities[rarity]
		if info and info.order > bestOrder then
			best, bestOrder = info.color, info.order
		end
	end
	return best
end

local function standPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, collide: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = collide ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function findPart(root: Instance, name: string): BasePart?
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			return d
		end
	end
	return nil
end

function PetService.BuildStand(): Model?
	local decor = workspace:FindFirstChild("Decor")
	local lobbyDeck = decor and findPart(decor, "LobbyDeck")
	local wheelDeck = decor and findPart(decor, "WheelDeck")
	if not (lobbyDeck and wheelDeck) then
		warn("[PetService] Lobi ya da cark bulunamadi, yumurta standi kurulmadi")
		return nil
	end

	local old = workspace:FindFirstChild("EggStand")
	if old then
		old:Destroy()
	end

	local cx = 2 * lobbyDeck.Position.X - wheelDeck.Position.X
	local cz = wheelDeck.Position.Z
	local floorTop = lobbyDeck.Position.Y + lobbyDeck.Size.Y / 2

	local stand = Instance.new("Model")
	stand.Name = "EggStand"

	local W, D = 30, 18
	local deckTop = floorTop + 1

	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(cx + x, y, cz + z)
	end

	-- Zemin: çarkın platformuyla aynı ölçüde
	standPart(stand, "StandDeck", Vector3.new(W, 1, D), at(0, floorTop + 0.5, 0), SHELL_DARK)

	--[[ Ön kenarda tehlike şeridi. Zeminden 0.02 yukarıda: aynı yüksekliğe
	     koyunca iki üst yüz aynı düzlemde kalıp titriyordu. ]]
	standPart(stand, "StandHazard", Vector3.new(W - 0.4, 0.1, 0.8),
		at(0, deckTop + 0.07, -D / 2 + 0.6), HAZARD, false)

	-- Arka pano ve üstünde tabela
	local back = standPart(stand, "StandBack", Vector3.new(W, 12, 1), at(0, deckTop + 6, D / 2 - 0.5), SHELL)
	standPart(stand, "StandBackTrim", Vector3.new(W + 0.6, 0.8, 1.6), at(0, deckTop + 12.4, D / 2 - 0.5), TRIM)

	local sign = Instance.new("SurfaceGui")
	sign.Name = "Sign"
	sign.Face = Enum.NormalId.Front
	sign.CanvasSize = Vector2.new(600, 240)
	sign.LightInfluence = 0
	sign.Parent = back

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.42, 0)
	title.Position = UDim2.fromScale(0, 0.08)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(238, 132, 195)
	title.Text = "PET EGGS"
	title.Parent = sign

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, 0, 0.16, 0)
	subtitle.Position = UDim2.fromScale(0, 0.52)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(190, 198, 210)
	subtitle.Text = "Walk up to an egg to hatch it"
	subtitle.Parent = sign

	-- Dört kaide, yumurta başına bir tane
	local count = #Config.Eggs
	local spacing = 7
	for index, egg in Config.Eggs do
		local x = (index - (count + 1) / 2) * spacing
		local tint = eggTint(egg)

		local pedestal = standPart(stand, "Pedestal", Vector3.new(5, 3, 5), at(x, deckTop + 1.5, -1), SHELL)
		standPart(stand, "PedestalCap", Vector3.new(5.4, 0.3, 5.4), at(x, deckTop + 3.15, -1), TRIM)

		--[[ Kaidenin önünde yumurtanın adı ve fiyatı. SurfaceGui: yüzeye
		     boyanıyor, derinlikle yarışmıyor (BillboardGui kameraya döndüğü
		     için yan yana dört tanesi birbirinin üstüne biniyordu). ]]
		local label = Instance.new("SurfaceGui")
		label.Face = Enum.NormalId.Front
		label.CanvasSize = Vector2.new(250, 150)
		label.LightInfluence = 0
		label.Parent = pedestal

		local eggName = Instance.new("TextLabel")
		eggName.Size = UDim2.new(1, 0, 0.45, 0)
		eggName.Position = UDim2.fromScale(0, 0.08)
		eggName.BackgroundTransparency = 1
		eggName.Font = Enum.Font.GothamBlack
		eggName.TextScaled = true
		eggName.TextColor3 = tint
		eggName.Text = string.upper(egg.name)
		eggName.Parent = label

		local price = Instance.new("TextLabel")
		price.Size = UDim2.new(1, 0, 0.35, 0)
		price.Position = UDim2.fromScale(0, 0.56)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.GothamBold
		price.TextScaled = true
		price.TextColor3 = Color3.fromRGB(128, 224, 150)
		price.Text = "$" .. Config.FormatCash(egg.price)
		price.Parent = label

		-- Yumurtanın altında kademe renginde halka
		local ring = standPart(stand, "EggRing", Vector3.new(0.2, 4, 4),
			at(x, deckTop + 3.4, -1) * CFrame.Angles(0, 0, math.rad(90)), tint, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.25

		--[[ Yumurta: küre ağı ile uzatılmış parça. Ball şekli her yönde
		     eşit kalıyor, ağ ise parçanın boyutuna uyuyor. ]]
		local shell = standPart(stand, "Egg", Vector3.new(3, 4, 3), at(x, deckTop + 5.5, -1), tint, false)
		shell.Reflectance = 0.08
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = shell

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HatchPrompt"
		prompt.ActionText = "Hatch"
		prompt.ObjectText = string.format("%s  $%s", egg.name, Config.FormatCash(egg.price))
		prompt.HoldDuration = 0.35
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = shell

		local eggId = egg.id
		PromptGuard.Connect(prompt, function(player)
			PetService.TryHatch(player, eggId)
		end)
	end

	stand.Parent = workspace
	return stand
end

-- ─── Yaşam döngüsü ──────────────────────────────────────────────────────────

--[[
	Profil yüklendiğinde çağrılıyor. Kayıttan gelen takılı liste burada
	TEMİZLENİYOR: artık sahip olunmayan ya da Config'den kaldırılmış bir
	pet listede kalırsa bonus yanlış hesaplanır.
]]
function PetService.OnProfileReady(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local cleaned: { string } = {}
	for _, key in profile.equippedPets do
		if #cleaned >= Config.PetEquipSlots then
			break
		end
		if (Config.ParsePetKey(key)) ~= nil and (profile.pets[key] or 0) > 0 and not table.find(cleaned, key) then
			table.insert(cleaned, key)
		end
	end
	profile.equippedPets = cleaned

	apply(player)
end

function PetService.Start()
	notifyRemote = Net.Get("Notify")
	petsRemote = Net.Get("Pets")
	hatchedRemote = Net.Get("PetHatched")

	Net.Get("PetHatch").OnServerEvent:Connect(function(player, eggId)
		if typeof(eggId) == "string" then
			PetService.TryHatch(player, eggId)
		end
	end)

	Net.Get("PetEquip").OnServerEvent:Connect(function(player, key, equip)
		if typeof(key) == "string" and typeof(equip) == "boolean" then
			PetService.TryEquip(player, key, equip)
		end
	end)

	Net.Get("PetFuse").OnServerEvent:Connect(function(player, key)
		if typeof(key) == "string" then
			PetService.TryFuse(player, key)
		end
	end)

	--[[
		Profil ne zaman hazır olacağını bilmiyoruz (DataService asenkron
		yüklüyor), o yüzden oyuncu girince kısa bir süre bekliyoruz.
		Yüklenmezse pet çıkmıyor ama oyun çalışmaya devam ediyor.
	]]
	local function onPlayerAdded(player: Player)
		task.spawn(function()
			for _ = 1, 60 do
				if DataService.Get(player) then
					PetService.OnProfileReady(player)
					return
				end
				task.wait(0.5)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		clearSpawned(player)
	end)

	RunService.Heartbeat:Connect(stepFollow)

	-- Stand lobiye bağlı; lobi (Decor) yüklenmemişse kurulmuyor ama
	-- oyunun geri kalanı çalışıyor
	local ok, err = pcall(PetService.BuildStand)
	if not ok then
		warn("[PetService] Yumurta standi kurulamadi: " .. tostring(err))
	end
end

return PetService