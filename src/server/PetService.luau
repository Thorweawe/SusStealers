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

	Lobideki kuluçkahanenin yumurtaları remote kullanmıyor: ProximityPrompt
	doğrudan sunucuda tetikleniyor ve PromptGuard'dan geçiyor. Birleştirme
	ise yalnızca makinenin yanında kabul ediliyor (NearFuseMachine).

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
local MonetizationService = require(script.Parent.MonetizationService)

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

	--[[
		Petleri SUNUCU taşımıyor: her istemci bütün petleri kendi karesinde
		kendisi yürütüyor (src/client/PetFollow). Eskiden sunucu her
		Heartbeat'te PivotTo yapıyordu; konum ağdan saniyede ~20 kez ve
		gecikmeli geldiği için pet kesik kesik, sahibinin arkasından
		"laglı" geliyordu. İstemci bunun yerine sahibin (zaten akıcı olan)
		karakterini izliyor.

		Kimin peti olduğu ve kaçıncı sırada durduğu nitelikte. Model
		Persistent: sunucudaki konumu hiç değişmediği için akış (streaming)
		onu uzak sanıp istemciden silebilirdi.
	]]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local start = if root and root:IsA("BasePart") then root.CFrame * CFrame.new(0, 0, 4) else nil

	local models: { Model } = {}
	local count = math.min(#wanted, Config.PetEquipSlots)
	for index, id in wanted do
		if index > Config.PetEquipSlots then
			break
		end
		local model = PetModel.Build(id)
		if model then
			model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			model:SetAttribute("OwnerId", player.UserId)
			model:SetAttribute("Slot", index)
			model:SetAttribute("SlotCount", count)
			if start then
				model:PivotTo(start)
			end
			model.Parent = folder
			table.insert(models, model)
		end
	end

	if #models > 0 then
		spawned[player] = models
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

local displayName = Config.PetDisplayName

--[[
	Nadir sonuçları Summons kanalına yazar: yüksek kademe, en nadir
	mutasyon (Cosmic) ya da büyük boyut (Huge, Titan). Üçü de sunucunun
	geri kalanının bilmesi gereken anlar.
]]
local ANNOUNCE_SIZES = { Huge = true, Titan = true }

local function announce(player: Player, key: string, verb: string)
	local def, mutation, size = Config.ParsePetKey(key)
	if not def then
		return
	end
	local rare = ANNOUNCE_RARITIES[def.rarity]
		or (mutation ~= nil and mutation.id == "Cosmic")
		or (size ~= nil and ANNOUNCE_SIZES[size.id] == true)
	if not rare then
		return
	end
	local rarity = Config.Rarities[def.rarity]
	AnnounceService.Summon(string.format("%s %s a %s!",
		player.DisplayName, verb, AnnounceService.Paint(displayName(key), rarity.color)))
end

-- ─── Açılış hakları ─────────────────────────────────────────────────────────

--[[
	Açılış bekleme süresi: oyuncu -> ne zamana kadar meşgul (os.clock).

	Bir yumurta açılırken ikincisi açılamıyor. Eskiden art arda basınca
	animasyonlar üst üste biniyor, sonuçlar kaçıyordu; üstelik bekleme
	olmadığı için otomatik açma sınırsız hızda çalışırdı.
]]
local busyUntil: { [Player]: number } = {}

-- Grup üyeliği ağ çağrısı; oturum boyunca bir kez soruluyor
local groupCache: { [Player]: boolean } = {}

--[[
	Otomatik açma gruba katılanlara açık (Config.GroupId). Grup henüz
	kurulmadıysa (0) kapalı. Studio'da şart aranmıyor ki geliştirici
	denemek için grup kurmak zorunda kalmasın.
]]
function PetService.CanAutoHatch(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if Config.GroupId == 0 then
		return false
	end
	local cached = groupCache[player]
	if cached ~= nil then
		return cached
	end
	local ok, inGroup = pcall(function()
		return player:IsInGroup(Config.GroupId)
	end)
	-- Hata olursa önbelleğe yazmıyoruz: geçici bir ağ sorunu yüzünden
	-- oturum boyunca kilitli kalmasın
	if not ok then
		return false
	end
	groupCache[player] = inGroup
	return inGroup
end

--[[ Üçlü açma gamepass'e bağlı; Studio'da deneme için açık. ]]
function PetService.CanTripleHatch(player: Player): boolean
	return RunService:IsStudio() or MonetizationService.HasPass(player, "TripleHatch")
end

--[[
	Yumurta açar. Başarılıysa çıkan anahtarların listesini döndürür.

	`count` 1 ya da 3 (üçlü açma). `auto` istemcinin otomatik açma döngüsünden
	geliyorsa true — grup şartı ona bakıyor. Döngünün kendisi istemcide;
	sunucu her isteği aynı bekleme süresiyle sınırladığı için otomatik açma
	elle basmaktan hızlı olamıyor.

	Çekiliş ÖNCE, harcama SONRA: çekiliş nil dönen bir yapılandırma
	hatasında ya da tavana çarpan bir sonuçta oyuncunun parası hiçbir şey
	vermeden yanmasın.
]]
function PetService.TryHatch(player: Player, eggId: string, count: number?, auto: boolean?): { string }?
	local egg = Config.GetEgg(eggId)
	if not egg then
		notify(player, "That egg does not exist", true)
		return nil
	end

	local profile = DataService.Get(player)
	if not profile then
		return nil
	end

	-- Bir önceki açılış bitmeden yenisi yok; sessizce, yoksa basılı tutan
	-- oyuncu bildirim yağmuruna tutulurdu
	local now = os.clock()
	if (busyUntil[player] or 0) > now then
		return nil
	end

	local amount = if count == Config.TripleHatchCount then Config.TripleHatchCount else 1
	if amount > 1 and not PetService.CanTripleHatch(player) then
		notify(player, "Triple Hatch needs the Triple Hatch pass (Shop)", true)
		return nil
	end
	if auto and not PetService.CanAutoHatch(player) then
		notify(player, "Join the group to unlock Auto Hatch", true)
		return nil
	end

	local keys: { string } = {}
	local pending: { [string]: number } = {}
	for _ = 1, amount do
		local def = Config.RollPet(rng, eggId)
		if not def then
			notify(player, "That egg is empty", true)
			return nil
		end
		local mutation = Config.RollPetMutation(rng)
		local key = Config.PetKey(def.id, if mutation then mutation.id else nil)
		pending[key] = (pending[key] or 0) + 1
		if (profile.pets[key] or 0) + pending[key] > Config.PetStackLimit then
			notify(player, string.format("You already have %d %s", Config.PetStackLimit, displayName(key)), true)
			return nil
		end
		table.insert(keys, key)
	end

	if not EconomyService.TrySpend(player, egg.price * amount) then
		notify(player, if amount > 1 then "Not enough cash for 3 eggs" else "Not enough cash for that egg", true)
		return nil
	end

	busyUntil[player] = now + Config.HatchDuration

	for _, key in keys do
		grant(player, key)
	end
	apply(player)

	if amount == 1 then
		notify(player, string.format("%s hatched a %s!", egg.name, displayName(keys[1])), false)
	else
		notify(player, string.format("%s x%d hatched!", egg.name, amount), false)
	end
	-- Üçüncü argüman yumurtanın kimliği: istemci açılışı o yumurtanın stilinde oynatıyor
	if hatchedRemote then
		hatchedRemote:FireClient(player, keys, "egg", eggId)
	end
	for _, key in keys do
		announce(player, key, "hatched")
	end
	return keys
end

--[[
	Bedava yumurta açılışı: günlük seri ve oynama süresi ödülleri için.
	Para almıyor, bekleme süresine takılmıyor (ödül toplamak yumurta
	açmayı engellememeli) ama animasyon ve duyuru normal açılışla aynı.
]]
function PetService.GiveEggRoll(player: Player, eggId: string): string?
	local egg = Config.GetEgg(eggId)
	local profile = DataService.Get(player)
	if not (egg and profile) then
		return nil
	end
	local def = Config.RollPet(rng, eggId)
	if not def then
		return nil
	end
	local mutation = Config.RollPetMutation(rng)
	local key = Config.PetKey(def.id, if mutation then mutation.id else nil)
	if not grant(player, key) then
		return nil
	end
	apply(player)
	if hatchedRemote then
		hatchedRemote:FireClient(player, { key }, "egg", eggId)
	end
	announce(player, key, "got")
	return key
end

--[[
	Üç kopyayı bir üst BOYUTA birleştirir: normal -> Big -> Huge -> Titan.
	Tür ve mutasyon aynı kalıyor. Başarılıysa yeni anahtarı döndürür.

	Kopyalar yandıktan sonra elde kalmayan anahtar takılıysa çıkarılıyor;
	yoksa bonus artık sahip olunmayan bir petten gelmeye devam ederdi.
]]
function PetService.TryFuse(player: Player, key: string): string?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end

	local def, mutation, size = Config.ParsePetKey(key)
	if not def then
		return nil
	end

	--[[
		Birleştirme yalnızca lobideki makinenin yanında. Remote her yerden
		gönderilebildiği için kontrol burada, istemcide değil. (Aşağıda
		tanımlı; tablo alanı olarak çağrılıyor ki çağrı anında çözülsün.)
	]]
	if not PetService.NearFuseMachine(player) then
		notify(player, "Use the Fuse Machine in the Pet Hatchery", true)
		return nil
	end

	local have = profile.pets[key] or 0
	if have < Config.PetFuseCount then
		notify(player, string.format("You need %d of the same pet to fuse", Config.PetFuseCount), true)
		return nil
	end

	local nextSize = Config.GetNextPetSize(size)
	if not nextSize then
		notify(player, "Titan is already the biggest size", true)
		return nil
	end

	local newKey = Config.PetKey(def.id, if mutation then mutation.id else nil, nextSize.id)
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
		-- Üçüncü argüman yakılan kopya: istemci makinede üçünü birleştirip gösteriyor
		hatchedRemote:FireClient(player, { newKey }, "fuse", key)
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

-- ─── Kuluçkahane ────────────────────────────────────────────────────────────

--[[
	Lobideki kuluçkahaneyi oyuna bağlar.

	Mimari haritanın kodunda (tools/build_decor.luau, "Hatchery"). Burada
	yalnızca ADI belli parçalara iş bağlanıyor: yumurtalara prompt ve renk,
	ekranlara ad ve fiyat, birleştirme çekirdeğine prompt. Böylece fiyat
	Config'ten geliyor ve haritayı yeniden kurmadan değişebiliyor.

	Harita kurulmamışsa (Decor yok) sessizce atlanıyor: yumurtalar panelden
	yine açılabiliyor.
]]
local FUSE_RANGE = 18
local fuseCore: BasePart? = nil

-- Yumurtanın kendi rengi (Config.Eggs.tint)
local function eggTint(egg: Config.EggDef): Color3
	return egg.tint
end

--[[
	Işık ve yazı için okunur ton. Secret'ın rengi neredeyse siyah (30,30,40):
	Void yumurtasının ekrandaki adı koyu ekranın üstünde okunmuyor, halkası
	ve ışıkları sönük görünüyordu. Çok koyu renk "boşluk moru"na dönüyor
	(petlerde Secret parıltısı da bu renk).
]]
local VOID_GLOW = Color3.fromRGB(170, 120, 255)

local function readable(tint: Color3): Color3
	local luminance = 0.2126 * tint.R + 0.7152 * tint.G + 0.0722 * tint.B
	return if luminance < 0.3 then VOID_GLOW else tint
end

local function screenLabel(part: BasePart, title: string, titleColor: Color3, sub: string)
	local old = part:FindFirstChild("Label")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(300, 130)
	gui.LightInfluence = 0
	gui.Parent = part

	local top = Instance.new("TextLabel")
	top.Position = UDim2.fromScale(0.04, 0.06)
	top.Size = UDim2.fromScale(0.92, 0.5)
	top.BackgroundTransparency = 1
	top.Font = Enum.Font.GothamBlack
	top.TextScaled = true
	top.TextColor3 = titleColor
	top.TextStrokeColor3 = Color3.new(0, 0, 0)
	top.TextStrokeTransparency = 0.3
	top.Text = title
	top.Parent = gui

	local bottom = Instance.new("TextLabel")
	bottom.Position = UDim2.fromScale(0.04, 0.58)
	bottom.Size = UDim2.fromScale(0.92, 0.34)
	bottom.BackgroundTransparency = 1
	bottom.Font = Enum.Font.GothamBold
	bottom.TextScaled = true
	bottom.TextColor3 = Color3.fromRGB(128, 224, 150)
	bottom.Text = sub
	bottom.Parent = gui
end

function PetService.WireHatchery(): boolean
	local decor = workspace:FindFirstChild("Decor")
	local hatchery = decor and decor:FindFirstChild("Hatchery", true)
	if not hatchery then
		warn("[PetService] Decor.Hatchery yok; yumurtalar yalnizca panelden acilabilir")
		return false
	end

	for index, egg in Config.Eggs do
		local shell = hatchery:FindFirstChild("Egg" .. index)
		local ring = hatchery:FindFirstChild("PodRing" .. index)
		local screen = hatchery:FindFirstChild("PodScreen" .. index)
		if not (shell and shell:IsA("BasePart")) then
			continue
		end

		local raw = eggTint(egg)
		local tint = readable(raw)
		-- Kabuk: açık tonlu; koyu (Void) yumurta koyu mor kalıyor ki "boşluk" gibi dursun
		shell.Color = if raw == tint then tint:Lerp(Color3.new(1, 1, 1), 0.35) else Color3.fromRGB(64, 40, 104)
		shell.CanQuery = true
		if ring and ring:IsA("BasePart") then
			ring.Color = tint
		end
		if screen and screen:IsA("BasePart") then
			screenLabel(screen, string.upper(egg.name), tint, "$" .. Config.FormatCash(egg.price))
		end

		--[[
			Kapsülün efekt parçaları (dönen halka, ışık sütunu, kristaller,
			zerreler) haritada "PodTint" niteliğiyle işaretli; burada
			yumurtanın rengine boyanıyor. Efektin KAÇ tane olduğu harita
			kodunda (fiyat sırasına göre artıyor), rengi burada.
		]]
		for _, d in hatchery:GetDescendants() do
			if d:GetAttribute("PodTint") == index then
				if d:IsA("BasePart") then
					d.Color = tint
				end
				for _, child in d:GetChildren() do
					if child:IsA("ParticleEmitter") then
						child.Color = ColorSequence.new(tint, Color3.new(1, 1, 1))
					elseif child:IsA("Light") then
						child.Color = tint
					end
				end
			end
		end

		for _, child in shell:GetChildren() do
			if child:IsA("ProximityPrompt") then
				child:Destroy()
			end
		end

		--[[
			Üç prompt, üç tuş — türün alışılmış düzeni:
			  E  Hatch      tek yumurta
			  R  Hatch x3   üçlü (Triple Hatch pass'i)
			  T  Auto       otomatik açma (grup); İSTEMCİDE işleniyor, döngü
			                orada — sunucu yalnızca her isteği sınırlıyor
		]]
		local function makePrompt(name: string, action: string, key: Enum.KeyCode, order: number): ProximityPrompt
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = name
			prompt.ActionText = action
			prompt.ObjectText = string.format("%s  $%s", egg.name, Config.FormatCash(egg.price))
			prompt.KeyboardKeyCode = key
			prompt.HoldDuration = 0.25
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.UIOffset = Vector2.new(0, (order - 1) * 72)
			prompt.Parent = shell
			return prompt
		end

		local eggId = egg.id
		local single = makePrompt("HatchPrompt", "Hatch", Enum.KeyCode.E, 1)
		PromptGuard.Connect(single, function(player)
			PetService.TryHatch(player, eggId, 1, false)
		end)

		local triple = makePrompt("TriplePrompt", "Hatch x3", Enum.KeyCode.R, 2)
		PromptGuard.Connect(triple, function(player)
			PetService.TryHatch(player, eggId, Config.TripleHatchCount, false)
		end)

		local autoPrompt = makePrompt("AutoPrompt", "Auto Hatch", Enum.KeyCode.T, 3)
		autoPrompt:SetAttribute("EggId", eggId)
	end

	--[[
		Birleştirme makinesi. Prompt SUNUCUDA bir şey yapmıyor; istemci
		kendi tetiklemesini görüp birleştirme penceresini açıyor
		(PetPanel.OpenFuse). Asıl işlem PetFuse remote'uyla geliyor ve
		TryFuse oyuncunun makinenin yanında olduğunu doğruluyor.
	]]
	local core = hatchery:FindFirstChild("FuseCore")
	if core and core:IsA("BasePart") then
		core.CanQuery = true
		fuseCore = core
		local old = core:FindFirstChild("FusePrompt")
		if old then
			old:Destroy()
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FusePrompt"
		prompt.ActionText = "Fuse Pets"
		prompt.ObjectText = "Fuse Machine"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = core
	end

	return true
end

--[[
	Oyuncu birleştirme makinesinin yanında mı. Makine yoksa (harita
	kurulmamış) kısıt uygulanmıyor — yoksa birleştirme hiç yapılamazdı.
]]
local function nearFuseMachine(player: Player): boolean
	if not fuseCore or not fuseCore.Parent then
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	return (root.Position - fuseCore.Position).Magnitude <= FUSE_RANGE
end

PetService.NearFuseMachine = nearFuseMachine
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

	-- (eggId, count, auto): count yalnızca 1 ya da 3 kabul ediliyor
	Net.Get("PetHatch").OnServerEvent:Connect(function(player, eggId, count, auto)
		if typeof(eggId) ~= "string" then
			return
		end
		local amount = if count == Config.TripleHatchCount then Config.TripleHatchCount else 1
		PetService.TryHatch(player, eggId, amount, auto == true)
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
		busyUntil[player] = nil
		groupCache[player] = nil
	end)

	-- Kuluçkahane lobide; harita yoksa atlanıyor, oyun çalışmaya devam ediyor
	local ok, err = pcall(PetService.WireHatchery)
	if not ok then
		warn("[PetService] Kulucka baglanamadi: " .. tostring(err))
	end
end

return PetService