--!strict
--[[
	Peti koddan üretir. UnitModel'in küçük kardeşi: aynı kural, hazır
	varlık yok, her şey Part'tan.

	═══ NEDEN BEŞ BİÇİM ═══════════════════════════════════════════════════

	Yirmi pet için yirmi ayrı model yazmak, yirmi ayrı bakım yükü demek ve
	hiçbiri birbirine benzemezse oyun "pet koleksiyonu" değil "rastgele
	nesne çantası" gibi durur.

	Bunun yerine beş SİLUET var (blob, orb, bot, crab, shard) ve her pet
	birine bağlı. Renk petten, taç nadirlikten geliyor. Sonuç: uzaktan
	bakınca türünü, yakından bakınca kademesini okuyorsun.

	Biçim eşlemesi Config'de DEĞİL burada: hangi petin neye benzediği
	görsel bir karar, denge tablosunun içinde durmamalı.

	═══ ÖLÇÜ ══════════════════════════════════════════════════════════════

	Pet ~1.6 stud: karakterin (4.2) bel hizasında. Daha büyüğü oyuncunun
	kendi görüşünü kapatıyordu, daha küçüğü koşarken kayboluyordu.
	Modelin tabanı y = 0; havada durması çağıranın işi (PetService).
]]

local Config = require(script.Parent.Config)

local PetModel = {}

-- Pet -> siluet. Listede olmayan pet "blob" oluyor; yeni pet eklenince
-- model yine de çıkıyor, sadece jenerik görünüyor.
local FORMS: { [string]: string } = {
	MiniCrew = "blob",     Bolt = "shard",       VentRat = "crab",
	BrainSlug = "blob",    SparePod = "orb",     Hamster = "blob",
	MedDrone = "orb",      TaskBot = "bot",      VentCrab = "crab",
	SusShadow = "blob",    CoreShard = "shard",  SecurityCam = "bot",
	MiniImp = "blob",      EscapePod = "orb",    SnowPal = "blob",
	GhostCrew = "blob",    MeetingBell = "orb",
	TheEgg = "orb",        VoidShard = "shard",
}

local VISOR = Color3.fromRGB(150, 220, 255)
local METAL = Color3.fromRGB(198, 206, 214)
local DARK = Color3.fromRGB(26, 28, 34)

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

--[[
	Pet modelini kurar. PrimaryPart gövdedir, taban y = 0 hizasındadır.

	Bilinmeyen kimlik nil döndürüyor, hata atmıyor: eski bir kayıtta
	kaldırılmış bir pet varsa sunucu düşmemeli.
]]
function PetModel.Build(petId: string): Model?
	local def = Config.GetPet(petId)
	if not def then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = def.id

	local form = FORMS[def.id] or "blob"
	local body: Part

	--[[
		Tacın oturacağı yükseklik. Her biçimin tepesi farklı yerde; tek
		bir sabit kullanınca taç blob'un kafasının İÇİNDE kalıyordu.
	]]
	local headTop = 1.6

	if form == "orb" then
		--[[ Havada duran küre: tek parça gövde + etrafında halka. En sade
		     siluet, o yüzden halka olmadan diğerlerinden ayrılmıyordu. ]]
		body = newPart("Body", Vector3.new(1.5, 1.5, 1.5), def.color)
		body.Shape = Enum.PartType.Ball
		body.CFrame = CFrame.new(0, 0.85, 0)
		body.Parent = model

		headTop = 1.62

		local ring = newPart("Ring", Vector3.new(2.1, 0.12, 2.1), METAL)
		ring.CFrame = CFrame.new(0, 0.85, 0) * CFrame.Angles(math.rad(18), 0, 0)
		ring.Parent = model

	elseif form == "bot" then
		--[[ Kutu gövde + anten. Görev konsollarının küçük hâli. ]]
		body = newPart("Body", Vector3.new(1.25, 1.2, 1.0), def.color)
		body.CFrame = CFrame.new(0, 0.7, 0)
		body.Parent = model

		headTop = 1.32

		local mast = newPart("Antenna", Vector3.new(0.12, 0.7, 0.12), METAL)
		mast.CFrame = CFrame.new(0, 1.6, 0.15)
		mast.Parent = model

		local tip = newPart("AntennaTip", Vector3.new(0.26, 0.26, 0.26), VISOR, Enum.Material.Neon)
		tip.Shape = Enum.PartType.Ball
		tip.CFrame = CFrame.new(0, 1.98, 0.15)
		tip.Parent = model

		for index, side in { -0.42, 0.42 } do
			local tread = newPart("Tread" .. index, Vector3.new(0.3, 0.3, 1.1), DARK)
			tread.CFrame = CFrame.new(side, 0.16, 0)
			tread.Parent = model
		end

	elseif form == "crab" then
		--[[ Alçak ve geniş: havalandırmadan çıkan şey. Bacaklar dışa
		     açık, böylece yandan bakınca gövdeden ayrılıyor. ]]
		body = newPart("Body", Vector3.new(1.5, 0.75, 1.2), def.color)
		body.CFrame = CFrame.new(0, 0.62, 0)
		body.Parent = model

		headTop = 1.02

		for index = 1, 6 do
			local side = if index % 2 == 0 then 1 else -1
			local row = math.floor((index - 1) / 2) - 1
			local leg = newPart("Leg" .. index, Vector3.new(0.5, 0.14, 0.14), DARK)
			leg.CFrame = CFrame.new(side * 0.9, 0.26, row * 0.42)
				* CFrame.Angles(0, 0, math.rad(side * -22))
			leg.Parent = model
		end

	elseif form == "shard" then
		--[[ Açılı kristal. Tek eğik blok; koleksiyondaki tek keskin
		     siluet, o yüzden envanterde hemen ayırt ediliyor. ]]
		body = newPart("Body", Vector3.new(0.9, 1.6, 0.9), def.color)
		body.CFrame = CFrame.new(0, 0.9, 0) * CFrame.Angles(0, math.rad(45), math.rad(12))
		body.Parent = model

		headTop = 1.74

		local core = newPart("ShardCore", Vector3.new(0.4, 0.9, 0.4), def.color:Lerp(Color3.new(1, 1, 1), 0.6), Enum.Material.Neon)
		core.CFrame = body.CFrame
		core.Parent = model

	else
		--[[ Blob: mürettebatın minyatürü. Gövde + vizör + iki ayak.
		     Varsayılan biçim, çünkü oyunun geri kalanının dili bu. ]]
		body = newPart("Body", Vector3.new(1.15, 1.3, 1.15), def.color)
		body.Shape = Enum.PartType.Cylinder
		body.CFrame = CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, math.rad(90))
		body.Parent = model

		headTop = 1.8

		local head = newPart("Head", Vector3.new(1.15, 1.15, 1.15), def.color)
		head.Shape = Enum.PartType.Ball
		head.CFrame = CFrame.new(0, 1.2, 0)
		head.Parent = model

		local visor = newPart("Visor", Vector3.new(0.8, 0.48, 0.32), VISOR, Enum.Material.Glass)
		visor.CFrame = CFrame.new(0, 1.22, -0.5)
		visor.Reflectance = 0.25
		visor.Parent = model

		for index, side in { -0.32, 0.32 } do
			local leg = newPart("Leg" .. index, Vector3.new(0.4, 0.34, 0.5), def.color)
			leg.CFrame = CFrame.new(side, 0.17, 0)
			leg.Parent = model
		end
	end

	--[[
		═══ NADİRLİK ═════════════════════════════════════════════════════

		UnitModel'deki mantığın aynısı: kademe kafaya takılan şeyden
		okunuyor. Burada daha küçük ve daha az parça — pet zaten küçük,
		kafasına beş parçalık taç koyarsak taç peti yutar.

		Common'da hiçbir şey yok. Bu kasten: bir şeyin olmaması da bir
		işaret ve "en alt kademe" mesajını bedavaya veriyor.
	]]
	local rarity = Config.Rarities[def.rarity]
	local accent = rarity.color
	local topY = headTop

	local function crown(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
		local part = newPart(name, size, color, material)
		part.CFrame = cf
		part.Parent = model
	end

	if def.rarity == "Uncommon" then
		crown("Band", Vector3.new(1.0, 0.14, 1.0), CFrame.new(0, topY - 0.1, 0), accent)

	elseif def.rarity == "Rare" then
		crown("Cap", Vector3.new(0.95, 0.3, 0.95), CFrame.new(0, topY, 0), accent)
		crown("CapBrim", Vector3.new(0.85, 0.1, 0.6), CFrame.new(0, topY - 0.14, -0.5), accent)

	elseif def.rarity == "Epic" then
		crown("Dome", Vector3.new(1.15, 1.15, 1.15), CFrame.new(0, topY + 0.02, 0), accent)
		crown("DomeRim", Vector3.new(1.2, 0.1, 1.2), CFrame.new(0, topY - 0.3, 0), DARK)
		local dome = model:FindFirstChild("Dome") :: Part
		dome.Shape = Enum.PartType.Ball
		dome.Transparency = 0.45

	elseif def.rarity == "Legendary" then
		for index = 1, 4 do
			local angle = (index - 1) * math.pi / 2
			crown("Spike" .. index,
				Vector3.new(0.14, 0.5, 0.14),
				CFrame.new(math.sin(angle) * 0.42, topY + 0.18, math.cos(angle) * 0.42),
				accent)
		end
		crown("CrownBand", Vector3.new(1.0, 0.16, 1.0), CFrame.new(0, topY - 0.05, 0), accent)

	elseif def.rarity == "Mythic" then
		for index = 1, 6 do
			local angle = (index - 1) * math.pi / 3
			crown("Spike" .. index,
				Vector3.new(0.14, 0.7, 0.14),
				CFrame.new(math.sin(angle) * 0.46, topY + 0.3, math.cos(angle) * 0.46),
				accent)
		end
		crown("CrownBand", Vector3.new(1.05, 0.2, 1.05), CFrame.new(0, topY - 0.02, 0), accent)
		crown("Gem", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, topY + 0.6, 0), accent, Enum.Material.Neon)

	elseif def.rarity == "Secret" then
		--[[ Secret'ta taç YOK, bunun yerine petin kendisi yarı saydam ve
		     etrafında dönen bir çekirdek var. Diğer kademeler "daha çok
		     şey takmak" üzerine kurulu; Secret o merdivenden çıkıyor ve
		     bu yüzden hemen fark ediliyor. ]]
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = 0.35
				part.Material = Enum.Material.Glass
			end
		end
		crown("SecretCore", Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, topY - 0.2, 0), accent, Enum.Material.Neon)
		local core = model:FindFirstChild("SecretCore") :: Part
		core.Shape = Enum.PartType.Ball
	end

	model.PrimaryPart = body

	local tag = Instance.new("StringValue")
	tag.Name = "PetId"
	tag.Value = def.id
	tag.Parent = model

	return model
end

return PetModel
