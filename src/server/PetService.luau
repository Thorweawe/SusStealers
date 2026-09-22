--!strict
--[[
	Petler: yumurta açma, envanter, takma ve peşinden gelme.

	═══ GÜVENLİK ══════════════════════════════════════════════════════════

	İstemciden iki remote dinleniyor ve ikisi de bedava bir şey VERMİYOR:

	  PetHatch — oyuncunun KENDİ parasını harcıyor. Fiyatı ve çekilişi
	             sunucu yapıyor; istemci yalnızca hangi yumurta olduğunu
	             söylüyor ve o kimlik Config'de aranıyor.
	  PetEquip — zaten sahip olunan bir peti takıyor/çıkarıyor. Sahiplik
	             profilden doğrulanıyor, slot sayısı sunucuda sınırlanıyor.

	Aynı kalıp UpgradeService'te de var; yeni bir saldırı yüzeyi açılmıyor.

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

local PetService = {}

local NOTIFY_KIND = "pet"
PetService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent
local petsRemote: RemoteEvent

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
	Yumurta açar. Başarılıysa petin tanımını döndürür.

	Envanter tavanı adet başına: aynı petten 99'dan fazlası birikmesin.
	Tavana çarpan oyuncunun parası ALINMIYOR — yoksa açtığı yumurta
	hiçbir şey vermeden yanardı.
]]
function PetService.TryHatch(player: Player, eggId: string): Config.PetDef?
	local egg = Config.GetEgg(eggId)
	if not egg then
		notify(player, "That egg does not exist", true)
		return nil
	end

	local profile = DataService.Get(player)
	if not profile then
		return nil
	end

	--[[
		Çekiliş ÖNCE, harcama SONRA. Tersi olsaydı çekiliş nil dönen bir
		yapılandırma hatasında oyuncunun parası yanardı.
	]]
	local def = Config.RollPet(rng, eggId)
	if not def then
		notify(player, "That egg is empty", true)
		return nil
	end

	local have = profile.pets[def.id] or 0
	if have >= Config.PetStackLimit then
		notify(player, string.format("You already have %d %s", have, def.name), true)
		return nil
	end

	if not EconomyService.TrySpend(player, egg.price) then
		notify(player, "Not enough cash for that egg", true)
		return nil
	end

	profile.pets[def.id] = have + 1

	--[[
		İlk pet otomatik takılıyor. Yoksa oyuncu yumurtayı açıyor, bir şey
		kazandığını görüyor ama hiçbir şey değişmiyor ve sistemi anlamadan
		bırakıyor.
	]]
	if #profile.equippedPets < Config.PetEquipSlots then
		table.insert(profile.equippedPets, def.id)
	end

	apply(player)
	notify(player, string.format("%s hatched a %s!", egg.name, def.name), false)
	return def
end

--[[
	Peti takar ya da çıkarır. Dönen değer işlemin tuttuğu.

	Aynı petten iki tane varsa iki slotta duramıyor: kopya takmak bonusu
	iki katına çıkarırdı ve "çeşit topla" hedefi anlamsızlaşırdı.
]]
function PetService.TryEquip(player: Player, petId: string, equip: boolean): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local index = table.find(profile.equippedPets, petId)

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

	if (profile.pets[petId] or 0) <= 0 then
		notify(player, "You do not own that pet", true)
		return false
	end

	if #profile.equippedPets >= Config.PetEquipSlots then
		notify(player, string.format("Only %d pets at a time", Config.PetEquipSlots), true)
		return false
	end

	table.insert(profile.equippedPets, petId)
	apply(player)
	return true
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
	for _, id in profile.equippedPets do
		if #cleaned >= Config.PetEquipSlots then
			break
		end
		if Config.GetPet(id) and (profile.pets[id] or 0) > 0 and not table.find(cleaned, id) then
			table.insert(cleaned, id)
		end
	end
	profile.equippedPets = cleaned

	apply(player)
end

function PetService.Start()
	notifyRemote = Net.Get("Notify")
	petsRemote = Net.Get("Pets")

	Net.Get("PetHatch").OnServerEvent:Connect(function(player, eggId)
		if typeof(eggId) == "string" then
			PetService.TryHatch(player, eggId)
		end
	end)

	Net.Get("PetEquip").OnServerEvent:Connect(function(player, petId, equip)
		if typeof(petId) == "string" and typeof(equip) == "boolean" then
			PetService.TryEquip(player, petId, equip)
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
end

return PetService
