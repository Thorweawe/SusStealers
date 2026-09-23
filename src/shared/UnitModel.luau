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

	--[[
		Among Us fasulyesi. Yuvarlak şekiller Roblox'un yerleşik ağlarından
		(SpecialMesh Head = yuvarlatılmış silindir, Sphere = elips) — mağaza
		varlığı değil, her yerde yükleniyor.

		Eski hâli keskin kenarlı silindir, küre ve KUTU vizördü; uzaktan
		bakınca vizör yüze yapıştırılmış mavi bir tuğla gibi duruyordu.
		Ölçüler aynı (boy 4.0, kafa merkezi 3.0): şapkalar yerinde kalıyor.
	]]
	local function rounded(part: Part, meshType: Enum.MeshType): Part
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = meshType
		mesh.Parent = part
		return part
	end

	-- Gövde: kenarları yuvarlatılmış silindir (dik, döndürmeye gerek yok)
	local body = rounded(newPart("Body", Vector3.new(2.05, 2.5, 2.0), bodyColor, Enum.Material.SmoothPlastic), Enum.MeshType.Head)
	body.CFrame = CFrame.new(0, 1.85, 0)
	body.Parent = model

	local head = newPart("Head", Vector3.new(2.05, 2.05, 2.05), bodyColor, Enum.Material.SmoothPlastic)
	head.Shape = Enum.PartType.Ball
	head.CFrame = CFrame.new(0, 3.0, 0)
	head.Parent = model

	-- Vizör: arkada koyu çerçeve, önde elips cam ve iki parlama
	local rim = rounded(newPart("VisorRim", Vector3.new(1.62, 1.04, 0.5), bodyColor:Lerp(Color3.new(0, 0, 0), 0.5), Enum.Material.SmoothPlastic), Enum.MeshType.Sphere)
	rim.CFrame = CFrame.new(0.12, 3.02, -0.7)
	rim.Parent = model

	local visor = rounded(newPart("Visor", Vector3.new(1.46, 0.88, 0.6), Color3.fromRGB(150, 216, 240), Enum.Material.Glass), Enum.MeshType.Sphere)
	visor.CFrame = CFrame.new(0.12, 3.04, -0.8)
	visor.Reflectance = 0.2
	visor.Parent = model

	for index, spec in { { 0.42, 3.22, 0.42, 0.22 }, { 0.62, 2.98, 0.16, 0.12 } } do
		local glint = rounded(newPart("VisorGlint" .. index, Vector3.new(spec[3], spec[4], 0.06), Color3.fromRGB(245, 252, 255), Enum.Material.Neon), Enum.MeshType.Sphere)
		glint.CFrame = CFrame.new(spec[1], spec[2], -1.09)
		glint.Parent = model
	end

	-- Kafada cilalı parıltı: oyuncak gibi okunsun
	local shine = rounded(newPart("BodyGlint", Vector3.new(0.42, 0.26, 0.06), Color3.fromRGB(255, 255, 255), Enum.Material.Neon), Enum.MeshType.Sphere)
	shine.CFrame = CFrame.new(-0.55, 3.62, -0.5) * CFrame.Angles(math.rad(-35), math.rad(-35), math.rad(25))
	shine.Transparency = 0.45
	shine.Parent = model

	-- Sırt çantası: yuvarlatılmış
	local pack = rounded(newPart("Backpack", Vector3.new(0.85, 1.9, 0.95), bodyColor:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.SmoothPlastic), Enum.MeshType.Head)
	pack.CFrame = CFrame.new(0, 2.05, 1.18)
	pack.Parent = model

	-- Bacaklar: kısa ve yuvarlak uçlu
	for index, offset in { -0.55, 0.55 } do
		local leg = rounded(newPart("Leg" .. index, Vector3.new(0.8, 1.3, 1.02), bodyColor, Enum.Material.SmoothPlastic), Enum.MeshType.Head)
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

	-- Metal aksam ve gölge tonu: her kademede tekrar ettiği için bir kez
	local METAL = Color3.fromRGB(198, 206, 214)
	local DARK = Color3.fromRGB(26, 28, 34)

	if def.rarity == "Uncommon" then
		--[[ Kep. Tepe + siperlik + dikiş bandı + tepe düğmesi. İlk hâli iki
		     parçaydı ve "kutu" gibi duruyordu; dikiş ve düğme onu giyilmiş
		     bir eşya yapıyor. ]]
		cosmetic("HatCrown", Vector3.new(1.75, 0.6, 1.75), CFrame.new(0, 4.05, 0), accent)
		cosmetic("HatSeam", Vector3.new(1.85, 0.16, 1.85), CFrame.new(0, 3.78, 0), DARK)
		cosmetic("HatBrim", Vector3.new(1.6, 0.2, 1.25), CFrame.new(0, 3.82, -1.05), accent)
		cosmetic("HatBrimEdge", Vector3.new(1.6, 0.1, 0.25), CFrame.new(0, 3.76, -1.6), DARK)
		cosmetic("HatButton", Vector3.new(0.34, 0.22, 0.34), CFrame.new(0, 4.42, 0), DARK)

	elseif def.rarity == "Rare" then
		--[[ Miğfer. Kubbe + çene bandı + yan kulaklık + anten + anten ucu.
		     Kubbe hafif saydam: altından vizör görünsün, kafayı tamamen
		     yutmasın. ]]
		local dome = cosmetic("HatDome", Vector3.new(2.15, 2.15, 2.15), CFrame.new(0, 4.05, 0.1), accent)
		dome.Shape = Enum.PartType.Ball
		dome.Transparency = 0.12

		cosmetic("HelmBand", Vector3.new(2.25, 0.3, 2.25), CFrame.new(0, 3.55, 0.1), METAL)
		for _, s in { -1, 1 } do
			cosmetic("HelmEar", Vector3.new(0.35, 0.8, 0.8), CFrame.new(s * 1.05, 3.9, 0.1), METAL)
		end
		cosmetic("HatAntenna", Vector3.new(0.16, 1.2, 0.16), CFrame.new(0.65, 4.95, 0.1), METAL)
		local bulb = cosmetic("AntennaTip", Vector3.new(0.34, 0.34, 0.34), CFrame.new(0.65, 5.6, 0.1), accent, Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball

	elseif def.rarity == "Epic" then
		--[[ Silindir şapka. Kenar + gövde + kurdele + toka + üst kapak.
		     Toka silueti kırıyor: düz silindir uzaktan sadece bir sütun. ]]
		cosmetic("HatBrim", Vector3.new(2.7, 0.24, 2.7), CFrame.new(0, 3.95, 0), accent)
		cosmetic("HatBrimLip", Vector3.new(2.9, 0.12, 2.9), CFrame.new(0, 3.86, 0), DARK)
		cosmetic("HatBody", Vector3.new(1.65, 1.6, 1.65), CFrame.new(0, 4.85, 0), accent)
		cosmetic("HatBand", Vector3.new(1.78, 0.42, 1.78), CFrame.new(0, 4.32, 0), DARK)
		cosmetic("HatBuckle", Vector3.new(0.5, 0.5, 0.2), CFrame.new(0, 4.32, -0.92), METAL)
		cosmetic("HatTop", Vector3.new(1.72, 0.14, 1.72), CFrame.new(0, 5.7, 0), DARK)

	elseif def.rarity == "Legendary" then
		--[[ Taç. Halka + beş uç + her ucun tepesinde taş + önde büyük taş.
		     Uçlar dışa doğru eğik; dimdik duran uçlar tarak gibi görünüyordu. ]]
		cosmetic("CrownBase", Vector3.new(2.05, 0.28, 2.05), CFrame.new(0, 3.9, 0), METAL)
		cosmetic("CrownRing", Vector3.new(1.95, 0.5, 1.95), CFrame.new(0, 4.16, 0), accent)

		for i = 1, 5 do
			local a = (i - 1) * (math.pi * 2 / 5)
			local seat = CFrame.new(0, 4.62, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 0.76)
			cosmetic("CrownSpike", Vector3.new(0.3, 1.5, 0.3), seat * CFrame.Angles(math.rad(-9), 0, 0), accent)
			local gem = cosmetic("CrownGem", Vector3.new(0.34, 0.34, 0.34), seat * CFrame.new(0, 0.86, -0.12), METAL, Enum.Material.Neon)
			gem.Shape = Enum.PartType.Ball
		end

		local front = cosmetic("CrownJewel", Vector3.new(0.6, 0.6, 0.28), CFrame.new(0, 4.24, -0.98), METAL, Enum.Material.Neon)
		front.Transparency = 0.1

	elseif def.rarity == "Mythic" then
		--[[ Boynuzlu taç. Halka + iki boynuz + boynuz halkaları + arkada
		     yüzen ay. Halka artık DÖNMÜYOR (dönen her şey kaldırıldı), hafif
		     eğik duruyor ki tabak gibi görünmesin. ]]
		cosmetic("CrownBase", Vector3.new(2.35, 0.3, 2.35), CFrame.new(0, 3.92, 0), DARK)
		cosmetic("CrownRing", Vector3.new(2.25, 0.55, 2.25), CFrame.new(0, 4.2, 0), accent)

		for _, s in { -1, 1 } do
			cosmetic("CrownHorn", Vector3.new(0.38, 2.0, 0.38),
				CFrame.new(s * 0.88, 5.1, 0) * CFrame.Angles(0, 0, math.rad(-s * 24)), accent)
			cosmetic("HornRing", Vector3.new(0.52, 0.16, 0.52),
				CFrame.new(s * 1.16, 5.6, 0) * CFrame.Angles(0, 0, math.rad(-s * 24)), METAL)
			local tip = cosmetic("HornTip", Vector3.new(0.3, 0.3, 0.3),
				CFrame.new(s * 1.35, 6.05, 0), accent, Enum.Material.Neon)
			tip.Shape = Enum.PartType.Ball
		end

		local halo = cosmetic("Halo", Vector3.new(3.1, 0.18, 3.1),
			CFrame.new(0, 5.75, 0) * CFrame.Angles(math.rad(10), 0, math.rad(6)), accent, Enum.Material.Neon)
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
