--!strict
-- Among Us tarzı karakteri koddan üretir. Hazır asset gerekmiyor;
-- MCP bağlanınca modelleri Creator Store'dan değiştirmek isterse
-- sadece Build fonksiyonunu değiştirmek yeterli.

local Config = require(script.Parent.Config)

local UnitModel = {}

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

--[[
	Verilen karakter tanımı için bir Model üretir.
	Model'in PrimaryPart'ı gövdedir, ayakların tabanı y=0 hizasındadır.
]]
function UnitModel.Build(unitId: string, mutationId: string?): Model
	local def = Config.GetUnit(unitId)
	assert(def, string.format("UnitModel: bilinmeyen karakter '%s'", unitId))

	local mutation = Config.GetMutation(mutationId)
	local bodyColor = def.color
	if mutation and mutation.tint then
		bodyColor = def.color:Lerp(mutation.tint, 0.65)
	end

	local model = Instance.new("Model")
	model.Name = def.id

	-- Gövde (Among Us fasulyesi: dikey silindir + yuvarlak üst)
	local body = newPart("Body", Vector3.new(2.0, 2.4, 2.0), bodyColor, Enum.Material.SmoothPlastic)
	body.Shape = Enum.PartType.Cylinder
	-- Cylinder ekseni X'tir, dikey durması için Z etrafında 90° çeviriyoruz
	body.CFrame = CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(90))
	body.Parent = model

	local head = newPart("Head", Vector3.new(2.0, 2.0, 2.0), bodyColor, Enum.Material.SmoothPlastic)
	head.Shape = Enum.PartType.Ball
	head.CFrame = CFrame.new(0, 3.0, 0)
	head.Parent = model

	-- Vizör
	local visor = newPart("Visor", Vector3.new(1.35, 0.85, 0.55), Color3.fromRGB(150, 220, 255), Enum.Material.Glass)
	visor.Shape = Enum.PartType.Block
	visor.CFrame = CFrame.new(0, 3.05, -0.85)
	visor.Reflectance = 0.25
	visor.Parent = model

	-- Sırt çantası
	local pack = newPart("Backpack", Vector3.new(0.8, 1.9, 0.9), bodyColor, Enum.Material.SmoothPlastic)
	pack.CFrame = CFrame.new(0, 2.0, 1.25)
	pack.Parent = model

	-- Bacaklar
	for index, offset in { -0.55, 0.55 } do
		local leg = newPart("Leg" .. index, Vector3.new(0.75, 1.3, 1.0), bodyColor, Enum.Material.SmoothPlastic)
		leg.CFrame = CFrame.new(offset, 0.65, 0)
		leg.Parent = model
	end

	local rarity = Config.Rarities[def.rarity]

	--[[
		═══ NADİRLİK KOZMETİĞİ ═══════════════════════════════════════════════

		Among Us'ta bir karakteri diğerinden ayıran şey tulum rengi değil,
		KAFASINA TAKTIĞI ŞEY. Oyunun bütün kozmetik ekonomisi şapka üstüne
		kurulu. Bizde de nadirlik sadece etiket rengiyle anlatılıyordu:
		kaidedeki sekiz karakter uzaktan birbirinin aynıydı, hangisinin
		değerli olduğunu anlamak için yanına gidip yazıyı okumak gerekiyordu.

		Artık her nadirlik kademesinin kendi başlığı var. Silueti farklı
		olduğu için koridorun öbür ucundan bile okunuyor — hırsız hangi üsse
		gideceğine bakmadan karar verebiliyor.

		Kademeler kasten ARTAN SİLUET büyüklüğünde: Common'da hiçbir şey yok,
		Mythic'te kafanın iki katı bir taç var. Değer arttıkça karakter
		fiziksel olarak da büyüyor gibi duruyor.
	]]
	local function cosmetic(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
		local part = newPart(name, size, color, material or Enum.Material.SmoothPlastic)
		part.CFrame = cf
		part.Parent = model
		return part
	end

	local accent = rarity.color

	if def.rarity == "Uncommon" then
		-- Kep: düz tepe + siperlik
		cosmetic("HatCrown", Vector3.new(1.7, 0.55, 1.7), CFrame.new(0, 4.05, 0), accent)
		cosmetic("HatBrim", Vector3.new(1.5, 0.22, 1.1), CFrame.new(0, 3.85, -1.0), accent)

	elseif def.rarity == "Rare" then
		-- Miğfer: kafayı saran kubbe + anten
		local dome = cosmetic("HatDome", Vector3.new(2.1, 2.1, 2.1), CFrame.new(0, 4.0, 0.1), accent)
		dome.Shape = Enum.PartType.Ball
		dome.Transparency = 0.15
		cosmetic("HatAntenna", Vector3.new(0.16, 1.5, 0.16), CFrame.new(0.65, 5.1, 0.1), accent)

	elseif def.rarity == "Epic" then
		-- Silindir şapka: yüksek gövde + geniş kenar
		cosmetic("HatBrim", Vector3.new(2.6, 0.22, 2.6), CFrame.new(0, 3.95, 0), accent)
		cosmetic("HatBody", Vector3.new(1.6, 1.5, 1.6), CFrame.new(0, 4.8, 0), accent)
		cosmetic("HatBand", Vector3.new(1.75, 0.3, 1.75), CFrame.new(0, 4.25, 0), Color3.fromRGB(26, 28, 34))

	elseif def.rarity == "Legendary" then
		-- Taç: halka + beş uç
		cosmetic("CrownRing", Vector3.new(1.9, 0.45, 1.9), CFrame.new(0, 4.1, 0), accent)
		for i = 1, 5 do
			local a = (i - 1) * (math.pi * 2 / 5)
			cosmetic(
				"CrownSpike",
				Vector3.new(0.3, 0.95, 0.3),
				CFrame.new(0, 4.6, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 0.72),
				accent
			)
		end

	elseif def.rarity == "Mythic" then
		-- Boynuzlu taç + arkada yüzen halka: siluet iyice büyüyor
		cosmetic("CrownRing", Vector3.new(2.2, 0.5, 2.2), CFrame.new(0, 4.15, 0), accent)
		for _, s in { -1, 1 } do
			cosmetic(
				"CrownHorn",
				Vector3.new(0.35, 1.9, 0.35),
				CFrame.new(s * 0.85, 5.0, 0) * CFrame.Angles(0, 0, math.rad(-s * 22)),
				accent
			)
		end
		local halo = cosmetic("Halo", Vector3.new(3.1, 0.18, 3.1), CFrame.new(0, 5.6, 0), accent, Enum.Material.Neon)
		halo.Transparency = 0.35

	elseif def.rarity == "Secret" then
		--[[
			Gizli kademe hiçbir şey TAKMIYOR: tam tersine, karakterin kendisi
			yarı saydam ve gövdesi karanlık. "Bu ne takmış" değil "bu ne
			böyle" dedirtiyor. En üst kademede kozmetik yarışına girmek yerine
			kuralı bozmak daha güçlü bir sinyal.
		]]
		body.Transparency = 0.35
		head.Transparency = 0.35
		pack.Transparency = 0.35
		local shroud = cosmetic("Shroud", Vector3.new(2.6, 2.6, 2.6), CFrame.new(0, 3.0, 0), accent, Enum.Material.Neon)
		shroud.Shape = Enum.PartType.Ball
		shroud.Transparency = 0.86
	end

	--[[
		Nadirlik ışığı. Eskiden her karakter ışık saçıyordu; bir üste sekiz
		karakter konunca sekiz ışık kaynağı oluyor ve sahne yıkanıyordu
		("her yerde çok fazla parıltı var"). Artık sadece Epic ve üstü ışık
		veriyor — ışığın kendisi bir ödül. Alt kademeler kozmetikten okunuyor.
	]]
	local LIT = { Epic = true, Legendary = true, Mythic = true, Secret = true }
	if LIT[def.rarity] or mutation then
		local light = Instance.new("PointLight")
		light.Color = rarity.color
		light.Range = if mutation then 9 else 7
		light.Brightness = if mutation then 1.4 else 0.8
		light.Parent = body
	end

	-- Pivot parçası: ayakların tabanında ve dönüşsüz.
	-- Gövde silindir olduğu için 90° çevrili duruyor. Onu PrimaryPart yaparsak
	-- model pivotu da çevrili olur; PivotTo pivotu hedefe birebir oturttuğu için
	-- o dönüşü sıfırlar ve karakter yan yatıp kaideye gömülür.
	local root = newPart("Root", Vector3.new(0.2, 0.2, 0.2), bodyColor, Enum.Material.SmoothPlastic)
	root.CFrame = CFrame.new(0, 0, 0)
	root.Transparency = 1
	root.Parent = model

	model.PrimaryPart = root

	-- Meta bilgiler: diğer sistemler modelden okuyabilsin
	local unitTag = Instance.new("StringValue")
	unitTag.Name = "UnitId"
	unitTag.Value = def.id
	unitTag.Parent = model

	local mutationTag = Instance.new("StringValue")
	mutationTag.Name = "MutationId"
	mutationTag.Value = if mutation then mutation.id else ""
	mutationTag.Parent = model

	return model
end

--[[ Karakterin üstünde duran isim/gelir etiketi. ]]
function UnitModel.BuildLabel(unitId: string, mutationId: string?): BillboardGui
	local def = Config.GetUnit(unitId)
	assert(def, string.format("UnitModel: bilinmeyen karakter '%s'", unitId))

	local mutation = Config.GetMutation(mutationId)
	local rarity = Config.Rarities[def.rarity]
	local income = def.income * (if mutation then mutation.incomeMul else 1)

	local gui = Instance.new("BillboardGui")
	gui.Name = "UnitLabel"
	gui.Size = UDim2.fromScale(7, 2.2)
	--[[
		Etiket PrimaryPart'a (Root) bağlanıyor, o da ayak hizasında.
		Nadirlik kozmetikleri gelince karakterin boyu 4.10'dan 6.05'e çıktı
		(Mythic tacı + halkası); etiket 5.0'da kalınca tacın içinden geçiyordu.
		En uzun figürün üstünde kalacak kadar yukarı alındı.
	]]
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.8, 0)

	--[[
		Boyut küçültüldü. Kaideler 6.5 stud arayla dizili; 7 stud genişliğinde
		etiket komşusununkiyle üst üste biniyor ve yaklaşınca ikisi de
		okunmaz hale geliyordu. MaxDistance da düştü: uzaktan onlarca etiket
		birbirine girmesin, yaklaşınca okunsun.
	]]
	gui.Size = UDim2.fromScale(4.6, 1.5)
	-- AlwaysOnTop kapali: acikken etiketler duvarlarin ve 2B HUD'un uzerine
	-- ciziliyor, kaide sirasina yaklasinca ekran okunmaz hale geliyordu.
	gui.AlwaysOnTop = false
	gui.MaxDistance = 70

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.55)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = rarity.color
	title.TextStrokeTransparency = 0.2
	title.Text = if mutation then string.format("[%s] %s", mutation.name, def.name) else def.name
	title.Parent = gui

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Income"
	subtitle.Position = UDim2.fromScale(0, 0.55)
	subtitle.Size = UDim2.fromScale(1, 0.45)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(120, 255, 150)
	subtitle.TextStrokeTransparency = 0.4
	subtitle.Text = "$" .. Config.FormatCash(income) .. "/s"
	subtitle.Parent = gui

	return gui
end

return UnitModel
