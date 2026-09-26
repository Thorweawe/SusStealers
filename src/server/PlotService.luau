--!strict
-- Üsleri koddan kurar, oyunculara dağıtır, kaide (podium) durumunu tutar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local UnitModel = require(Shared.UnitModel)

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local BadgeService = require(script.Parent.BadgeService)

local PlotService = {}

local plotsFolder: Folder
local plots: { Model } = {}
local ownerByPlot: { [Model]: Player? } = {}
local plotByOwner: { [Player]: Model } = {}

-- Start() tekrar çağrılabilsin diye: eski bağlantılar burada tutulur,
-- yeniden kurarken kesilir. Yoksa PlayerAdded iki kez tetiklenir.
local connections: { RBXScriptConnection } = {}

-- Oyuncu çıkarken üssü boşaltılıyor. O sırada profile yazarsak kayıtlı
-- karakterleri kaydedilmeden hemen önce sileriz. Bu bayrak onu engelliyor.
local releasing: { [Player]: boolean } = {}

-- Üs bekleyen oyuncular, giriş sırasına göre
local waiting: { Player } = {}

local notifyRemote: RemoteEvent

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "plot"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
PlotService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
	end
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

--[[
	GÖRÜNÜM: harita The Skeld (tools/map). Üs, içinde durduğu odanın rengini
	alıyor (Config.BayRooms); gövde parçaları haritayla aynı açık, düz
	renkli çizgi film paleti. Eskiden koyu gri beton ve metal dokuydu,
	renkli odaların ortasında sönük bir blok gibi duruyordu.
]]
local LOOK = {
	frame = Color3.fromRGB(226, 236, 242),
	metal = Color3.fromRGB(176, 188, 196),
	shell = Color3.fromRGB(84, 112, 128),
	accent = Color3.fromRGB(252, 204, 48),
	dark = Color3.fromRGB(30, 38, 46),
	lamp = Color3.fromRGB(255, 250, 238),
	lane = Color3.fromRGB(186, 204, 214),
	belt = Color3.fromRGB(58, 72, 86),
}

local function newAnchoredPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

--[[
	═══ ÜS YERLEŞİMİ ════════════════════════════════════════════════════════

	Bütün üs tek bir koordinat sözleşmesine göre kuruluyor. Buradaki sayılar
	hem zemini hem üst katları hem de kaideleri bağlar; tek yerde durmaları
	bilinçli, yoksa biri değişince diğeri kayıyor.

	x ekseni (üs genişliği 72, yani ±36):
	    -36 .. -25   merdiven kuyusu (STAIR_W = 11)
	    -25 .. +36   güverte
	    kaideler ortada, ±11.25 ve ±3.75
	    bonus kaideler ±18.75
	    yükseltme kulübesi +27 civarı

	z ekseni (üs derinliği 52, yani ±26):
	    -25   tabela
	    -18   doğuş pedi
	     -9   ön kaide sırası
	      0   bonus kaide sırası
	     +9   arka kaide sırası
	    +21   konveyör

	KAİDE DAĞILIMI — "5'e 3 olmuş, 4'e 4 olmalı" şikâyetinin sebebi:
	eskiden 10 kaide sırayla ikiye bölünüyordu (1-5 ön, 6-10 arka) ve bonus
	olanlar 9-10'du. Yani ön sırada 5 kullanılabilir, arka sırada 3 kalıyordu.
	Artık 8 temel kaide 4+4 ortada, 2 bonus kaide de yanlarda ayrı duruyor.
	Bonus alınmasa bile temel diziliş simetrik.
]]
local LAYOUT = {
	STAIR_W = 11,
	-- Dekor da aynı sayıyı kullanıyor, o yüzden Config'te (bkz. PodiumRowZ)
	ROW_Z = Config.PodiumRowZ,
	BONUS_X = 2.5,       -- bonus kaidenin kaç "PodiumSpacing" kadar yanda olduğu
	DECK_INSET = 6,      -- güvertenin ön/arka kenarının üs kenarından içeride kalması
}

--[[
	Bir kaidenin üs merkezine göre konumu. Hem zemin hem üst katlar bunu
	kullanıyor, böylece katlar birbirinin tam üstüne oturuyor.

	index 1..PodiumsPerPlot  → temel kaideler, 4+4 ortada
	index sonrası            → bonus kaideler, yanlarda simetrik
]]
local function podiumOffset(index: number): Vector3
	local base = Config.PodiumsPerPlot
	local spacing = Config.PodiumSpacing

	if index <= base then
		local perRow = math.ceil(base / 2)
		local front = index <= perRow
		local column = if front then index - 1 else index - perRow - 1
		return Vector3.new(
			(column - (perRow - 1) / 2) * spacing,
			0,
			if front then -LAYOUT.ROW_Z else LAYOUT.ROW_Z
		)
	end

	-- Bonus: merkezin iki yanında, sıraların arasındaki boş şeritte
	local n = index - base
	local side = if n % 2 == 1 then -1 else 1
	local rank = math.floor((n - 1) / 2)
	return Vector3.new(side * (LAYOUT.BONUS_X + rank) * spacing, 0, 0)
end

--[[
	═══ ÜST KAT ═════════════════════════════════════════════════════════════

	Tek merdiven SOL uçta (kuyu x ∈ [-halfX, -halfX + STAIR_W]); sağ uç
	tamamen güverte. Güverte merdiven şeridinin bittiği yerden başlıyor,
	ikisi hiç kesişmiyor. Merdivenin kendisi aşağıda ("Merdiven").

	floor: kurulan katın numarası (2, 3...). Merdiven bir alt kattan bu
	kata çıkıyor; 3. kat ve üstünde merdivenin dibinde bir alt katın
	ön sahanlığı da bu katla birlikte kuruluyor (kat kilitliyken gizli).
]]
local function buildUpperFloor(parent: Instance, origin: Vector3, deckTop: number, room: Config.BayRoom, floor: number)
	local halfX = Config.PlotSize.X / 2
	local rise = Config.FloorHeight

	local stairW = LAYOUT.STAIR_W
	local deckZ = Config.PlotSize.Z - LAYOUT.DECK_INSET * 2

	-- Merdiven şeridi solda: x ∈ [-halfX, -halfX + stairW]
	local stairX = -halfX + stairW / 2
	-- Güverte onun sağında başlıyor, üssün sağ kenarına kadar
	local deckX0 = -halfX + stairW
	local deckW = halfX - deckX0
	local deckCX = deckX0 + deckW / 2

	--[[
		Üst katlar tavana YAKIN: istasyon tavanındaki ışık panelleri (y=51,
		aşağı bakan, 50-58 stud menzil) zemin katı menzilin ucunda loş
		aydınlatıyor ama 2. katı ~30 stud'dan, 3. katı ~15 stud'dan
		vuruyor. Açık renkli plakalar beyaza kaçıyordu ("floor 2 niye bu
		kadar parlak"). Asıl düzeltme panel menzilinde; üst katın yürünen
		yüzeyleri de kata göre biraz koyulaşıyor.
	]]
	-- Tavan panellerinin menzili de kısaldı (tools/map/station.luau); burası ince ayar
	local shade = math.clamp(0.1 * (floor - 1), 0, 0.25)
	local function dim(c: Color3): Color3
		return c:Lerp(Color3.new(0, 0, 0), shade)
	end

	-- Güverte odanın oluk renginde; üstündeki plakalar odanın karoları
	local DECK_COLOR = dim(room.grout)
	local TILE_A, TILE_B = dim(room.tile), dim(room.tile2)
	local TRIM_COLOR = LOOK.frame
	local RAIL_COLOR = LOOK.metal

	local function slab(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		return newAnchoredPart(name, size, CFrame.new(origin + offset), color, parent)
	end

	-- ── Ana güverte ────────────────────────────────────────────────────────
	slab("Deck", Vector3.new(deckW, 1, deckZ), Vector3.new(deckCX, deckTop - 0.5, 0), DECK_COLOR)

	-- Kenar süpürgeliği: levhanın kalınlığı okunsun
	for _, sz in { -1, 1 } do
		slab("DeckEdge", Vector3.new(deckW, 1.4, 0.8),
			Vector3.new(deckCX, deckTop - 0.78, sz * deckZ / 2), TRIM_COLOR)
	end
	slab("DeckEdge", Vector3.new(0.8, 1.4, deckZ),
		Vector3.new(halfX - 0.4, deckTop - 0.78, 0), TRIM_COLOR)

	--[[
		── Merdiven ───────────────────────────────────────────────────────

		"Mantığa daha yatkın" yeniden tasarım. Eskisi ARKADAN (konveyörün
		dibinden) başlayıp öne tırmanıyordu: üsse önden giren oyuncu önce
		arkaya yürümek zorundaydı, üstte de dar bir sahanlık ve kemer vardı.
		Üçüncü katın basamakları ikinci katın merdiveninin tam üstünde
		havada başlıyordu, ancak güvertenin kenarından yana adım atılarak
		ulaşılıyordu.

		Şimdi:
		  - Her kat merdiveni ÖNDEN (girişin ve doğuş pedinin olduğu taraf)
		    başlıyor, ARKAYA doğru tırmanıyor. Katlar aynı yönde üst üste:
		    her merdivenin altında bir kat aşağısının merdiveni, arada tam
		    bir kat yüksekliği boşluk var.
		  - Üstte GENİŞ arka sahanlık güverteye yandan bağlanıyor; bir üst
		    katın merdiveni o katın ÖN sahanlığından başlıyor (3. kat).
		  - İki yanda da korkuluk (dikmeli, katı): merdivene yalnızca dibinden
		    çıkılıyor, yandan düşülmüyor. Güvertenin kuyuya bakan kenarında
		    da korkuluk var.
		  - Basamak burnunda sarı uyarı şeridi, alnında odanın vurgu renginde
		    ışık; dipte yukarı bakan oklar, tepede "FLOOR N" kemeri.

		Basamak sayısı yükseklikten türetiliyor (en fazla 1.2 stud): Roblox
		karakteri zıplamadan tırmanıyor ve FloorHeight değişirse merdiven
		kendiliğinden uyuyor.
	]]
	local deckFront = -deckZ / 2
	local deckBack = deckZ / 2
	local FRONT_LANDING = 4
	local zStart = deckFront + FRONT_LANDING
	local baseY = deckTop - rise

	local STEPS = math.max(8, math.ceil(rise / 1.2))
	local stepRise = rise / STEPS
	-- Arka sahanlığa en az 6 stud kalsın
	local stepRun = math.min(1.8, (deckBack - 6 - zStart) / STEPS)
	local flightLen = STEPS * stepRun
	local zEnd = zStart + flightLen
	local stepW = stairW - 1.2

	-- Basamağın ön kenarındaki yükseklik (eğim çizgisi): stringer ve korkuluk buna göre
	local function pitchY(z: number): number
		return baseY + stepRise + (z - zStart) * (rise / flightLen)
	end

	--[[
		Basamaklar. 2. katın merdiveni zeminden yükseliyor: her basamak
		zemine kadar dolu, altından geçilen bir boşluk kalmıyor. Üst
		katlarınki kalın bir tabla (altında bir kat aşağısının merdiveni
		var, doldurmak onun baş boşluğunu kapatırdı).
	]]
	for i = 1, STEPS do
		local top = baseY + i * stepRise
		local z0 = zStart + (i - 1) * stepRun
		local height = if floor == 2 then top - baseY else stepRise + 1
		local p = newAnchoredPart(
			"Step",
			Vector3.new(stepW, height, stepRun),
			CFrame.new(origin + Vector3.new(stairX, top - height / 2, z0 + stepRun / 2)),
			if i % 2 == 0 then room.tile else room.tile2,
			parent
		)
		p.CanCollide = true

		-- Burun şeridi: basamağın ön kenarı uzaktan seçilsin
		local nose = slab("StepNose", Vector3.new(stepW, 0.12, 0.45),
			Vector3.new(stairX, top + 0.06, z0 + 0.23), LOOK.accent)
		nose.CanCollide = false

		-- Alın ışığı: basamağın öne bakan yüzünde odanın vurgu renginde
		local glow = slab("StepGlow", Vector3.new(stepW - 1.4, 0.22, 0.1),
			Vector3.new(stairX, top - stepRise * 0.55, z0 - 0.05), room.accent)
		glow.Material = Enum.Material.Neon
		glow.CanCollide = false
		glow.CastShadow = false
	end

	--[[
		Kiriş (stringer) ve korkuluklar: iki yanda, eğim boyunca. Eğim çizgisi
		ilk basamağın burnundan son basamağın burnuna; kiriş sahanlığın
		üstüne taşmasın diye son basamağın burnunda bitiyor.
	]]
	local pitchLen = flightLen - stepRun
	local slope = math.atan2(rise - stepRise, pitchLen)
	local slopeLen = math.sqrt((rise - stepRise) ^ 2 + pitchLen ^ 2)
	local zMid = zStart + pitchLen / 2
	for _, side in { -1, 1 } do
		local sx = stairX + side * (stairW / 2 - 0.3)

		newAnchoredPart("StairStringer", Vector3.new(0.6, 1.8, slopeLen),
			CFrame.new(origin + Vector3.new(sx, pitchY(zMid) - 0.5, zMid)) * CFrame.Angles(-slope, 0, 0),
			TRIM_COLOR, parent)

		-- Kirişin dışında vurgu çizgisi
		local band = newAnchoredPart("StairStringerBand", Vector3.new(0.12, 0.35, slopeLen - 0.6),
			CFrame.new(origin + Vector3.new(sx + side * 0.36, pitchY(zMid) - 0.5, zMid)) * CFrame.Angles(-slope, 0, 0),
			room.accent, parent)
		band.Material = Enum.Material.Neon
		band.CanCollide = false
		band.CastShadow = false

		-- Tırabzan: kirişin üstünde, eğim çizgisinin 3.4 yukarısında
		newAnchoredPart("StairRail", Vector3.new(0.4, 0.4, slopeLen),
			CFrame.new(origin + Vector3.new(sx, pitchY(zMid) + 3.4, zMid)) * CFrame.Angles(-slope, 0, 0),
			RAIL_COLOR, parent)

		-- Dikmeler: üç basamakta bir, uçlarda mutlaka
		local posts = math.max(2, math.floor(STEPS / 3))
		for k = 0, posts do
			local z = zStart + 0.4 + (pitchLen - 0.8) * (k / posts)
			slab("StairPost", Vector3.new(0.35, 3.4, 0.35), Vector3.new(sx, pitchY(z) + 1.7, z), RAIL_COLOR)
		end
	end

	-- ── Arka sahanlık: güverteye yandan bağlanıyor ─────────────────────────
	local backLen = deckBack - zEnd
	slab("Landing", Vector3.new(stairW, 1, backLen),
		Vector3.new(stairX, deckTop - 0.5, zEnd + backLen / 2), DECK_COLOR)
	slab("LandingTile", Vector3.new(stairW - 1, 0.2, backLen - 1),
		Vector3.new(stairX, deckTop + 0.1, zEnd + backLen / 2), TILE_A)

	-- Arka kenarda güverte duvarının devamı, dış kenarda korkuluk
	slab("LandingWall", Vector3.new(stairW, 7, 1), Vector3.new(stairX, deckTop + 3.5, deckBack - 0.5), LOOK.shell)
	slab("LandingWallTrim", Vector3.new(stairW, 0.6, 1.6), Vector3.new(stairX, deckTop + 7.2, deckBack - 0.5), TRIM_COLOR)

	local function edgeRail(name: string, cx: number, cz: number, length: number, along: string, y: number)
		local size = if along == "x" then Vector3.new(length, 0.35, 0.35) else Vector3.new(0.35, 0.35, length)
		slab(name, size, Vector3.new(cx, y + 3.2, cz), RAIL_COLOR)
		local posts = math.max(1, math.floor(length / 5))
		for k = 0, posts do
			local t = k / posts
			slab(name .. "Post", Vector3.new(0.35, 3.2, 0.35), Vector3.new(
				if along == "x" then cx - length / 2 + length * t else cx,
				y + 1.6,
				if along == "z" then cz - length / 2 + length * t else cz
			), RAIL_COLOR)
		end
	end

	edgeRail("LandingRail", -halfX + 0.3, zEnd + backLen / 2, backLen - 1.2, "z", deckTop)

	--[[
		Güvertenin kuyuya bakan kenarı: merdivenin yanı boyunca korkuluk.
		Sahanlıkların önü açık kalıyor — güverteye oradan geçiliyor.
	]]
	edgeRail("DeckSideRail", deckX0 + 0.3, zStart + flightLen / 2, flightLen - 0.8, "z", deckTop)

	-- ── Ön sahanlık (3. kat ve üstü): bir alt katta, merdivenin dibinde ──
	if floor > 2 then
		slab("FrontLanding", Vector3.new(stairW, 1, FRONT_LANDING),
			Vector3.new(stairX, baseY - 0.5, deckFront + FRONT_LANDING / 2), DECK_COLOR)
		edgeRail("FrontLandingRail", -halfX + 0.3, deckFront + FRONT_LANDING / 2, FRONT_LANDING - 0.6, "z", baseY)
		edgeRail("FrontLandingRail", stairX, deckFront + 0.3, stairW - 1.2, "x", baseY)
	end

	-- Dipte yukarı bakan oklar: merdivenin nereden başladığı zeminden okunsun
	for k = 0, 1 do
		for _, side in { -1, 1 } do
			local arrow = newAnchoredPart("StairChevron", Vector3.new(2.6, 0.1, 0.6),
				CFrame.new(origin + Vector3.new(stairX + side * 1.05, baseY + 0.12 + k * 0.01, zStart - 1.2 - k * 1.3))
					* CFrame.Angles(0, math.rad(side * 35), 0),
				room.accent, parent)
			arrow.Material = Enum.Material.Neon
			arrow.CanCollide = false
			arrow.CastShadow = false
		end
	end

	--[[
		── Güverte korkuluğu ──────────────────────────────────────────────
		Sadece DIŞ kenarlara: sağ uç ve ön/arka kenarların uçları. Kaidelerin
		önü açık kalıyor, yoksa karakterler korkuluğun arkasında kalıyor.
	]]
	local function railing(cx: number, cz: number, length: number, along: string)
		local size = if along == "x"
			then Vector3.new(length, 0.35, 0.35)
			else Vector3.new(0.35, 0.35, length)

		-- Korkuluk KATI: eskiden geçirgendi, oyuncu içinden yürüyüp düşüyordu
		slab("Rail", size, Vector3.new(cx, deckTop + 3.2, cz), RAIL_COLOR)

		local posts = math.max(2, math.floor(length / 8))
		for i = 0, posts do
			local t = i / posts
			slab("RailPost", Vector3.new(0.35, 3.2, 0.35), Vector3.new(
				if along == "x" then cx - length / 2 + length * t else cx,
				deckTop + 1.6,
				if along == "z" then cz - length / 2 + length * t else cz
			), RAIL_COLOR)
		end
	end

	railing(halfX - 0.5, 0, deckZ, "z")
	for _, sz in { -1, 1 } do
		railing(halfX - 10, sz * (deckZ / 2 - 0.5), 18, "x")
	end

	--[[
		── Kolonlar ───────────────────────────────────────────────────────
		Güverteyi alt kata bağlıyorlar. Yapısal olarak gereksiz (her şey
		anchored) ama görsel olarak şart: kolonsuz üst kat havada asılı
		duruyor. Kaidelerin arasına denk gelmesinler diye köşelere yakın.
	]]
	for _, sx in { 0.06, 0.94 } do
		for _, sz in { -1, 1 } do
			slab("Column", Vector3.new(2, rise, 2), Vector3.new(
				deckX0 + deckW * sx,
				deckTop - rise / 2 - 1,
				sz * (deckZ / 2 - 1.5)
			), TRIM_COLOR)
		end
	end

	--[[
		Güvertenin altına gömme aydınlatma: alt kat karanlıkta kalmasın.

		SPOT, AŞAĞI BAKIYOR. Eskiden PointLight'tı: Roblox'ta ışık (gölge
		kapalıyken) parçaların İÇİNDEN geçiyor. Lamba güverte yüzeyinin
		yalnızca 1.2 stud altında olduğu için ışığı levhadan yukarı sızıp
		ÜST KATIN zemininde bembeyaz lekeler yapıyordu ("2. katta hâlâ bir
		parlama var"). Spot yalnızca alt yarıküreyi aydınlatıyor.
	]]
	for _, t in { 0.3, 0.7 } do
		local lamp = newAnchoredPart(
			"DeckLamp",
			Vector3.new(deckW * 0.36, 0.3, 3),
			CFrame.new(origin + Vector3.new(deckX0 + deckW * t, deckTop - 1.2, 0)),
			Color3.fromRGB(255, 244, 222),
			parent
		)
		lamp.Material = Enum.Material.Neon
		lamp.CanCollide = false

		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 150
		light.Color = Color3.fromRGB(255, 244, 222)
		light.Range = 26
		light.Brightness = 0.9
		light.Shadows = true
		light.Parent = lamp
	end

	--[[
		═══ KAT DEKORU ══════════════════════════════════════════════════════

		Üst kat "boş bir levha" gibi duruyordu: güverte, korkuluk, kaideler,
		bitti. Oyuncu milyarlarını verip açtığı katta bir alt kattan farklı
		hiçbir şey görmüyordu.

		Bu blok katı BİR ODA yapıyor. Hepsi alt katta zaten olan dille
		kuruluyor (aynı plaka, oluk, uyarı şeridi), böylece katlar arasında
		uyum var — ama her katın kendi numarası ve kendi renk aksanı var.
	]]
	-- Katın vurgu rengi odanın rengi: üst kat da aynı odanın parçası
	local tint = room.accent

	-- Zemin plakaları: alt kattaki güverte dokusunun aynısı
	local TILE = 14
	local cols = math.max(1, math.floor(deckW / TILE))
	local rowsT = math.max(1, math.floor(deckZ / TILE))
	for i = 0, cols - 1 do
		for j = 0, rowsT - 1 do
			slab("DeckPlate", Vector3.new(deckW / cols - 0.8, 0.2, deckZ / rowsT - 0.8), Vector3.new(
				deckX0 + (i + 0.5) * (deckW / cols),
				deckTop + 0.16,
				-deckZ / 2 + (j + 0.5) * (deckZ / rowsT)
			), if (i + j) % 2 == 0 then TILE_A else TILE_B)
		end
	end

	-- Kaide sıralarının arasındaki yürüme yolu, kenarında uyarı şeridi
	slab("DeckLane", Vector3.new(deckW - 4, 0.12, 7), Vector3.new(deckCX, deckTop + 0.26, 0),
		dim(LOOK.lane))
	for _, sz in { -1, 1 } do
		local step = 5
		local count = math.floor((deckW - 4) / step)
		for i = 0, count - 1 do
			slab("DeckStripe", Vector3.new(step * 0.55, 0.14, 0.7), Vector3.new(
				deckCX - (deckW - 4) / 2 + (i + 0.5) * step,
				deckTop + 0.3,
				sz * 3.5
			), if i % 2 == 0 then LOOK.accent else LOOK.dark)
		end
	end

	--[[
		Arka duvar paneli. Kaidelerin arkasını kapatıyor; açık kenardan
		aşağı bakınca kat "kesilmiş" gibi duruyordu. Korkuluk yerine dolu
		panel çünkü bu kenarda geçiş yok.
	]]
	slab("DeckWall", Vector3.new(deckW, 7, 1), Vector3.new(deckCX, deckTop + 3.5, deckZ / 2 - 0.5), LOOK.shell)
	slab("DeckWallTrim", Vector3.new(deckW, 0.6, 1.6), Vector3.new(deckCX, deckTop + 7.2, deckZ / 2 - 0.5), TRIM_COLOR)
	slab("DeckWallBand", Vector3.new(deckW - 6, 0.5, 1.4), Vector3.new(deckCX, deckTop + 5.4, deckZ / 2 - 0.9), tint)

	--[[
		Duvara gömme aydınlatma: kat kendi ışığını taşısın. Odaya (-Z) bakan
		spot, gölgeli: PointLight bir üst katın zeminine de sızıyordu (bkz.
		DeckLamp).
	]]
	for _, t in { 0.22, 0.48, 0.74 } do
		local wall = newAnchoredPart(
			"DeckWallLamp",
			Vector3.new(deckW * 0.18, 0.3, 0.5),
			CFrame.new(origin + Vector3.new(deckX0 + deckW * t, deckTop + 6.4, deckZ / 2 - 1.1)),
			Color3.fromRGB(255, 244, 222),
			parent
		)
		wall.Material = Enum.Material.Neon
		wall.CanCollide = false

		local wl = Instance.new("SpotLight")
		wl.Face = Enum.NormalId.Front
		wl.Angle = 120
		wl.Color = Color3.fromRGB(255, 244, 222)
		wl.Range = 20
		wl.Brightness = 0.7
		wl.Shadows = true
		wl.Parent = wall
	end

	--[[
		KAT NUMARASI PLAKASI KALDIRILDI.

		Duvara "FLOOR 2" yazan bir pano vardı ama duvardaki renk bandı ve
		üçüncü gömme lamba tam önüne geliyordu; yazının yarısı okunmuyordu.
		Hizalamak yerine tamamen çıkarıldı — oyuncu hangi kata çıktığını
		merdivenden zaten biliyor ve katın kendi renk aksanı da söylüyor.
		Duvarda okunmayan bir yazı hiç olmayandan kötü.
	]]

	--[[
		Merdivenin tepesinde kemer: çıkan oyuncu hangi kata vardığını
		karşısında okuyor. Yazı kemerin iki yüzünde (merdivenden ve
		sahanlıktan bakınca).
	]]
	local archZ = zEnd + 0.8
	for _, side in { -1, 1 } do
		-- Dış yüzü kirişin/bandın yüzüyle aynı düzlemde olmasın (0.3 içeride)
		slab("StairArchLeg", Vector3.new(1, 7.6, 1.2), Vector3.new(
			stairX + side * (stairW / 2 - 0.8), deckTop + 3.8, archZ), TRIM_COLOR)
	end
	local beam = slab("StairArchBeam", Vector3.new(stairW, 2.2, 1.6), Vector3.new(stairX, deckTop + 9, archZ), LOOK.dark)
	slab("StairArchBand", Vector3.new(stairW, 0.4, 1.8), Vector3.new(stairX, deckTop + 7.7, archZ), tint)

	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local surface = Instance.new("SurfaceGui")
		surface.Name = "FloorLabel" .. face.Name
		surface.Face = face
		surface.CanvasSize = Vector2.new(220, 44)
		surface.LightInfluence = 0
		surface.Parent = beam

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = tint
		text.Text = string.format("FLOOR %d", floor)
		text.Parent = surface
	end
end

--[[
	═══ YÜKSELTME KULÜBESİ ══════════════════════════════════════════════════

	İlk sürüm fazla kalabalıktı: tezgâh, arka pano, iki direk, çatı, eğik
	tente, tabela, lamba — ve üstüne UpgradeService'in dört fiziksel panosu.
	Tezgâh 15 stud, panolar 26 stud yer istiyordu; birbirine ve direklere
	giriyorlardı. Eğik tente de karşıdan bakınca havada duran turuncu bir
	levha gibi görünüyordu.

	Sadeleştirildi. Kalanlar:
	    tezgâh          — satıcının arkasına geçtiği yüzey
	    arka pano       — kulübeyi bir "dükkân" yapan düz yüzey
	    çift yüzlü tabela — iki taraftan da UPGRADES yazıyor
	    tavan + lamba   — tezgâhı aydınlatan gömme armatür
	    satıcı          — uzun, eşsiz görünümlü görevli
	    tetik alanı     — üstüne basınca arayüz açılan görünmez daire

	Yükseltme listesi artık fiziksel değil: oyuncu tetik alanına girince
	istemcideki UpgradePanel açılıyor.
]]
local function buildUpgradeBooth(parent: Instance, origin: Vector3)
	local halfX = Config.PlotSize.X / 2
	local halfZ = Config.PlotSize.Z / 2
	local topY = Config.PlotSize.Y / 2

	--[[
		Sağ kenarda, ön ve arka arasında. Çakışma kontrolü:
		    doğuş pedi   x ±4,   z -23..-15
		    kaideler     x ±11.2 (sıralar), ±18.8 (bonus)
		    konveyör     z +21
		    merdiven     x -36..-25
		Kulübe x 22..34, z -10..-2 → hiçbiriyle kesişmiyor.
	]]
	local bx = halfX - 8
	local bz = -6

	local booth = Instance.new("Model")
	booth.Name = "UpgradeBooth"
	booth.Parent = parent

	local SHELL = LOOK.shell
	local TRIM = LOOK.frame
	local ACCENT = LOOK.accent
	local DARK = LOOK.dark

	local root = Vector3.new(bx, topY, bz)

	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, collide: boolean?): Part
		local p = newAnchoredPart(name, size, CFrame.new(origin + root + offset), color, booth)
		p.CanCollide = collide ~= false
		return p
	end

	-- Tezgâh: oyuncunun karşısında, -z tarafında
	--[[
		Genişlik yan duvarların İÇ yüzüne göre: duvarlar x = ±6'da ve 1
		stud kalın, yani aradaki açıklık 11. Tezgâh 12, tablası 13 genişti;
		ikisinin de uçları duvarların içine giriyordu ve beyaz tabla gri
		duvarla çakışıyordu.
	]]
	part("Counter", Vector3.new(10.6, 4, 2.6), Vector3.new(0, 2, -2.6), SHELL)
	part("CounterTop", Vector3.new(10.8, 0.6, 4), Vector3.new(0, 4.3, -2.8), TRIM)
	part("CounterStripe", Vector3.new(10.4, 0.5, 0.3), Vector3.new(0, 3.1, -3.95), ACCENT, false)

	-- Arka pano ve yan duvarlar: dükkân hissi
	part("BoothBack", Vector3.new(13, 10, 1), Vector3.new(0, 5, 2.2), SHELL)
	for _, s in { -1, 1 } do
		part("BoothSide", Vector3.new(1, 10, 5.4), Vector3.new(s * 6, 5, -0.3), SHELL)
	end

	-- Tavan: düz, taşkın yok. Eğik tente kaldırıldı.
	part("BoothRoof", Vector3.new(14.4, 0.8, 7.4), Vector3.new(0, 10.4, -0.4), TRIM)

	--[[
		Tabela ÇİFT YÜZLÜ. Üssün iki yanından da gelinebiliyor; tek yüzlü
		tabela arkadan bakınca boş bir levha oluyordu.
	]]
	local sign = part("BoothSign", Vector3.new(12, 2.8, 0.5), Vector3.new(0, 12.2, -0.4), DARK, false)

	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local surface = Instance.new("SurfaceGui")
		surface.Name = "Label" .. face.Name
		surface.Face = face
		surface.CanvasSize = Vector2.new(240, 56)
		surface.LightInfluence = 0
		surface.Parent = sign

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = ACCENT
		text.Text = "UPGRADES"
		text.Parent = surface
	end

	-- Tavana gömme lamba
	local lamp = part("BoothLamp", Vector3.new(10, 0.3, 2), Vector3.new(0, 9.75, -1.4), Color3.fromRGB(255, 244, 222), false)
	lamp.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 244, 222)
	light.Range = 22
	light.Brightness = 0.8
	light.Parent = lamp

	--[[
		═══ TETİK ALANI ═════════════════════════════════════════════════════

		Tezgâhın önünde görünmez bir daire. Oyuncu üstüne basınca istemci
		yükseltme arayüzünü açıyor, çıkınca kapatıyor.

		ProximityPrompt yerine alan kullanılmasının sebebi: prompt tek bir
		yükseltme için "basılı tut" istiyor ve dört yükseltme dört prompt
		demek. Alan tek seferde bütün listeyi açıyor ve oyuncunun hiçbir
		tuşa basması gerekmiyor — dükkâna girer gibi.

		CanCollide kapalı (içinden geçilebilir), CanQuery açık: istemci
		oyuncunun mesafesini buna göre ölçüyor.
	]]
	--[[
		ÇAP = 2 × UpgradePanel.REACH. Daire 16 studdu ama panel 6'da
		açılıyordu: zemindeki sarı alan etkileşim alanından iki kat büyük
		görünüyor, oyuncu dairenin içinde durduğu hâlde panel açılmıyordu.
		İkisi artık aynı ölçüde; halkaya bastığın an açılıyor.
	]]
	local ZONE_D = 12

	local zone = newAnchoredPart(
		"UpgradeZone",
		Vector3.new(ZONE_D, 0.4, ZONE_D),
		CFrame.new(origin + root + Vector3.new(0, 0.2, -8)) * CFrame.Angles(0, 0, math.rad(90)),
		ACCENT,
		booth
	)
	zone.Shape = Enum.PartType.Cylinder
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanTouch = false

	-- Zeminde alanın nerede olduğunu gösteren soluk halka
	part("ZoneRing", Vector3.new(ZONE_D, 0.14, ZONE_D), Vector3.new(0, 0.13, -8), ACCENT, false).Transparency = 0.8
	part("ZoneRingInner", Vector3.new(ZONE_D - 2.4, 0.16, ZONE_D - 2.4), Vector3.new(0, 0.22, -8), DARK, false).Transparency = 0.55

	--[[
		═══ SATICI ══════════════════════════════════════════════════════════

		Uzatıldı: gövde ölçüleri 1.35 kat ve tezgâhın üstünden görünsün diye
		yükseltildi. Önceki hâlinde tezgâhın arkasında kalıyor, sadece
		kafasının üstü görünüyordu.

		Kasten EŞSİZ: rengi hiçbir mürettebat tulumunda yok (soluk mor-gri),
		vizörü sarı (hepsininki mavi), kulaklığı da hiçbir nadirlik
		kademesinde yok. Bakınca "bu satılık bir karakter değil, görevli"
		anlaşılıyor.
	]]
	local SKIN = Color3.fromRGB(122, 112, 148)
	local VISOR = Color3.fromRGB(240, 226, 150)
	local S = 1.35                       -- ölçek
	local FEET = 0.6                     -- tezgâhın arkasında bir basamak

	-- z: sirt cantasi 1.35*1 = 1.35 derin ve arka pano z = bz+2.2'de.
	-- 0.4'te canta panonun icine giriyordu; -0.9 onu tamamen one aliyor.
	local vroot = Vector3.new(bx, topY + FEET, bz - 0.9)

	local function vendor(name: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?): Part
		local p = newAnchoredPart(name, size * S, CFrame.new(origin + vroot + offset * S), color, booth)
		p.Material = Enum.Material.SmoothPlastic
		-- Satıcı katı: içinden geçilen hiçbir şey olmasın
		p.CanCollide = true
		if shape then
			p.Shape = shape
		end
		return p
	end

	-- Satıcının üstünde durduğu basamak: tezgâhın üstünden görünsün
	part("VendorStep", Vector3.new(6, FEET, 3), Vector3.new(0, FEET / 2, 0.4), SHELL)

	-- Gövde silindir; ekseni X olduğu için Z etrafında 90° çevriliyor
	local body = vendor("VendorBody", Vector3.new(2.2, 2.6, 2.2), Vector3.new(0, 1.9, 0), SKIN, Enum.PartType.Cylinder)
	body.CFrame = CFrame.new(origin + vroot + Vector3.new(0, 1.9 * S, 0)) * CFrame.Angles(0, 0, math.rad(90))

	vendor("VendorHead", Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 3.2, 0), SKIN, Enum.PartType.Ball)
	vendor("VendorVisor", Vector3.new(1.5, 0.95, 0.6), Vector3.new(0, 3.25, -0.95), VISOR)
	vendor("VendorPack", Vector3.new(0.9, 2.1, 1), Vector3.new(0, 2.1, 1.35), SKIN)
	for _, s in { -1, 1 } do
		vendor("VendorLeg", Vector3.new(0.8, 1.4, 1.1), Vector3.new(s * 0.6, 0.7, 0), SKIN)
		vendor("VendorPhone", Vector3.new(0.5, 1, 1), Vector3.new(s * 1.2, 3.3, 0), TRIM)
	end
	-- Kulaklık köprüsü: iki kulaklığı birleştiren bant
	vendor("VendorBridge", Vector3.new(2.5, 0.35, 0.9), Vector3.new(0, 4.3, 0), TRIM)
	vendor("VendorCap", Vector3.new(1.9, 0.55, 1.9), Vector3.new(0, 4.62, 0), ACCENT)
	vendor("VendorCapTip", Vector3.new(1.5, 0.22, 1.1), Vector3.new(0, 4.4, -1.1), ACCENT)
end

--[[
	═══ KİLİT KONSOLU ═══════════════════════════════════════════════════════

	Kilit promptu üssün ÖNÜNDEKİ tabelaya bağlıydı. Tabela koridora bakıyor,
	yani oyuncu üssünü kilitlemek için dışarı çıkıp kapının önüne gitmek
	zorundaydı — hırsız içerideyken yapılacak en son şey.

	Artık üssün İÇİNDE, kaidelerin yanında fiziksel bir düğme var: kırmızı
	kubbe, altında kaide, çevresinde uyarı şeridi. Acil toplantı düğmesinin
	küçük kardeşi; oyunun kendi diliyle "bu bir acil durum düğmesi" diyor.

	Sol ön köşede duruyor — yükseltme kulübesi sağda, doğuş pedi ortada,
	merdiven daha solda; arada kalan boşluk burası.
]]
local function buildLockConsole(parent: Instance, origin: Vector3)
	local halfZ = Config.PlotSize.Z / 2
	local topY = Config.PlotSize.Y / 2

	local cx = -Config.PlotSize.X / 2 + 18
	local cz = -halfZ + 11

	local console = Instance.new("Model")
	console.Name = "LockConsole"
	console.Parent = parent

	local SHELL = LOOK.shell
	local TRIM = LOOK.frame

	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, collide: boolean?): Part
		local p = newAnchoredPart(name, size, CFrame.new(origin + Vector3.new(cx, topY, cz) + offset), color, console)
		p.CanCollide = collide ~= false
		return p
	end

	-- Zeminde uyarı halkası: düğmenin alanı belli olsun
	part("LockRing", Vector3.new(9, 0.14, 9), Vector3.new(0, 0.13, 0), LOOK.accent, false).Transparency = 0.7

	part("LockBase", Vector3.new(6, 1.2, 6), Vector3.new(0, 0.6, 0), TRIM)
	part("LockColumn", Vector3.new(3.4, 3.4, 3.4), Vector3.new(0, 2.9, 0), SHELL)
	part("LockCollar", Vector3.new(5, 0.4, 5), Vector3.new(0, 4.7, 0), TRIM)

	-- Kırmızı kubbe: promptun bağlandığı parça
	local dome = part("LockButton", Vector3.new(3.2, 3.2, 3.2), Vector3.new(0, 5.6, 0), Color3.fromRGB(178, 44, 40))
	dome.Shape = Enum.PartType.Ball
	dome.Material = Enum.Material.Neon

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(178, 44, 40)
	light.Range = 12
	light.Brightness = 0.9
	light.Parent = dome
end

--[[
	Kat kolonlarını alt kattaki eşyalardan kaçırır.

	ESKİ HATA ("ikinci katta duvar iç içe girmiş"): kolonlar güvertenin
	köşelerine sabit konuyordu; biri konveyörün giriş makinesinin (Decor
	IntakeHood/IntakeBody) tam ortasından, diğerleri kilit konsolunun ve
	yükseltme kulübesinin halkalarından geçiyordu. Üs tamamen kurulup
	dünyaya konduktan sonra her kolonun gövdesi (zeminden ve güverteden
	biraz payla) yoklanıyor; bir şeye giriyorsa üssün ortasına doğru
	kaydırılıyor, boş yer yoksa kaldırılıyor (kolonlar yalnızca görsel).
]]
local function clearColumns(plot: Model)
	local floors = plot:FindFirstChild("Floors")
	if not floors then
		return
	end
	local base = plot:FindFirstChild("Base")
	local center = if base and base:IsA("BasePart") then base.Position else plot:GetPivot().Position
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { floors }

	local function blocked(cf: CFrame, size: Vector3): boolean
		-- Alttan 1.3 (zemin kaplamaları), üstten 0.3 (güverte) pay
		local probe = Vector3.new(size.X - 0.2, size.Y - 1.6, size.Z - 0.2)
		for _, hit in workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0.5, 0), probe, params) do
			if hit ~= base and hit.Transparency < 0.95 then
				return true
			end
		end
		return false
	end

	for _, column in floors:GetDescendants() do
		if not (column:IsA("BasePart") and column.Name == "Column") then
			continue
		end
		local start = column.CFrame
		if not blocked(start, column.Size) then
			continue
		end
		local sx = if start.Position.X > center.X then -1 else 1
		local sz = if start.Position.Z > center.Z then -1 else 1
		local moved = false
		for step = 1, 8 do
			for _, offset in { Vector3.new(sx * step * 2, 0, 0), Vector3.new(0, 0, sz * step * 2), Vector3.new(sx * step * 2, 0, sz * step * 2) } do
				local cf = start + offset
				if not blocked(cf, column.Size) then
					column.CFrame = cf
					moved = true
					break
				end
			end
			if moved then
				break
			end
		end
		if not moved then
			column:Destroy()
		end
	end
end

local function buildPlot(index: number): Model
	local plot = Instance.new("Model")
	plot.Name = string.format("Plot%d", index)

	-- Izgara yerleşimi: soldan sağa PlotColumns tane, sonra alt satır.
	-- Tek sıra isteniyorsa Config.PlotColumns = Config.PlotCount yapılır.
	local columns = Config.PlotColumns or Config.PlotCount
	local column = (index - 1) % columns
	local row = math.floor((index - 1) / columns)

	local origin = Vector3.new(
		column * Config.PlotSpacing,
		0,
		row * (Config.PlotRowSpacing or 0)
	)

	-- Zemin: içinde durduğu Skeld odasının renginde, bir tık koyu (sahne gibi okunsun)
	local room = Config.GetBayRoom(index)
	local base = newAnchoredPart("Base", Config.PlotSize, CFrame.new(origin), room.tile2:Lerp(Color3.new(0, 0, 0), 0.08), plot)
	plot.PrimaryPart = base

	-- Kaideler: her katta iki sıra. 1. kat zeminde ve açık gelir,
	-- üst katlar rebirth ile açılır. Slot numaraları katlar boyunca
	-- kesintisiz devam ediyor ki kayıttaki slot -> kaide eşlemesi bozulmasın.
	local podiums = Instance.new("Folder")
	podiums.Name = "Podiums"
	podiums.Parent = plot

	local floors = Instance.new("Folder")
	floors.Name = "Floors"
	floors.Parent = plot

	local groundY = Config.PlotSize.Y / 2   -- 1. katın yürüme yüzeyi

	for floor = 1, Config.MaxFloors do
		local deckTop = groundY + (floor - 1) * Config.FloorHeight

		local floorModel = Instance.new("Model")
		floorModel.Name = string.format("Floor%d", floor)
		floorModel.Parent = floors

		if floor > 1 then
			buildUpperFloor(floorModel, origin, deckTop, room, floor)
		end

		--[[
			Kaide konumu artık podiumOffset'ten geliyor: temel 8 tanesi 4+4
			ortada, bonus olanlar yanlarda. Eskiden sıra sırayla ikiye
			bölünüyordu ve bonuslar arka sıranın sonuna düşüyordu; oyuncu
			ön sırada 5, arka sırada 3 kullanılabilir kaide görüyordu.
		]]
		for index = 1, Config.PodiumsPerFloorTotal do
			local offset = podiumOffset(index) + Vector3.new(0, deckTop + 0.5, 0)

			local podium = newAnchoredPart(
				"Podium",
				Vector3.new(4, 1, 4),
				CFrame.new(origin + offset),
				LOOK.frame,
				podiums
			)
			podium:SetAttribute("SlotIndex", (floor - 1) * Config.PodiumsPerFloorTotal + index)
			podium:SetAttribute("Floor", floor)
			podium:SetAttribute("Bonus", index > Config.PodiumsPerPlot)
			podium:SetAttribute("UnitId", "")
			podium:SetAttribute("MutationId", "")
			podium:SetAttribute("PlacedAt", 0)
		end
	end

	buildUpgradeBooth(plot, origin)
	buildLockConsole(plot, origin)

	-- Konveyör (görsel şerit)
	local conveyor = newAnchoredPart(
		"Conveyor",
		Vector3.new(Config.PlotSize.X - 8, 1, 5),
		CFrame.new(origin + Vector3.new(0, Config.PlotSize.Y / 2 + 0.5, Config.PlotSize.Z / 2 - 5)),
		LOOK.belt,
		plot
	)

	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = plot

	-- Sahip tabelası
	local sign = newAnchoredPart(
		"Sign",
		Vector3.new(6, 0.4, 0.4),
		CFrame.new(origin + Vector3.new(0, 8, -Config.PlotSize.Z / 2 + 1)),
		LOOK.dark,
		plot
	)
	-- Yalnızca etiketin çapası: havada duran koyu çubuk görünmesin
	sign.Transparency = 1
	sign.CanCollide = false

	--[[
		AlwaysOnTop kapali: acikken tabela 2B HUD'un uzerine ciziliyordu.
		Kendi ussune yaklasan oyuncunun ekraninin yarisini "48YUSUF" kapliyor,
		siralama tablosunun ustune biniyordu. Boyut da kucultuldu; 12x3 olcek
		uzaktan devasa duruyordu.
	]]
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerLabel"
	gui.Size = UDim2.fromScale(7, 1.8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 170
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(235, 240, 255)
	label.TextStrokeTransparency = 0.15
	label.Text = "EMPTY BASE"
	label.Parent = gui

	-- Doğuş pedi: oyuncu ortada değil, kendi üssünde başlasın
	local spawnPad = newAnchoredPart(
		"SpawnPad",
		Vector3.new(8, 0.4, 8),
		CFrame.new(origin + Vector3.new(0, Config.PlotSize.Y / 2 + 0.3, -Config.PlotSize.Z / 2 + 7)),
		Color3.fromRGB(120, 206, 255),
		plot
	)
	spawnPad.Material = Enum.Material.Neon
	spawnPad.Transparency = 0.55

	plot:SetAttribute("Locked", false)
	plot:SetAttribute("LockUsedAt", 0)
	plot:SetAttribute("UnlockedFloors", 1)

	--[[
		Satırlar birbirine baksın. Üs varsayılan olarak -Z yönüne bakıyor
		(tabela orada). Iki satırlı düzende üst satır bu haliyle koridorun
		tersine bakıyor, o yüzden 180° çevriliyor. Sonuç: iki sıra üs
		aradaki koridora bakar, oyuncu ortada durup ikisini birden görür.

		180° eksen hizasını bozmuyor, bu yüzden isInsidePlot gibi dünya
		eksenine bakan kontroller çalışmaya devam ediyor. Başka bir açı
		seçilirse oralar da düzeltilmeli.
	]]
	local rowCount = math.ceil(Config.PlotCount / columns)
	if rowCount > 1 and row % 2 == 0 then
		plot:PivotTo(CFrame.new(origin) * CFrame.Angles(0, math.pi, 0))
	end

	plot.Parent = plotsFolder

	--[[
		Kilitli katları HEMEN kapat. Eskiden bu sadece üs bir oyuncuya
		verilince çalışıyordu; sahipsiz üste 2. ve 3. kat tamamen katı ve
		görünür duruyordu, hatta kilitli olmasına rağmen merdiveninden
		çıkılabiliyordu.
	]]
	PlotService.SetUnlockedFloors(plot, 1)
	return plot
end

-- ─── Kaide işlemleri ────────────────────────────────────────────────────────

function PlotService.GetPodiums(plot: Model): { Part }
	local result: { Part } = {}
	local folder = plot:FindFirstChild("Podiums")
	if not folder then
		return result
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Part") then
			table.insert(result, child)
		end
	end

	table.sort(result, function(a, b)
		return (a:GetAttribute("SlotIndex") :: number) < (b:GetAttribute("SlotIndex") :: number)
	end)
	return result
end

function PlotService.IsOccupied(podium: Part): boolean
	return (podium:GetAttribute("UnitId") :: string) ~= ""
end

--[[
	Kaide kullanılabilir mi. İki koşul var: katı açık olacak (rebirth) ve
	bonus kaideyse sahibinin gamepass'i olacak.
]]
function PlotService.IsPodiumUnlocked(podium: Part): boolean
	local plot = PlotService.GetPlotFromDescendant(podium)
	if not plot then
		return false
	end

	local floor = (podium:GetAttribute("Floor") :: number?) or 1
	local unlocked = (plot:GetAttribute("UnlockedFloors") :: number?) or 1
	if floor > unlocked then
		return false
	end

	if podium:GetAttribute("Bonus") then
		local owner = ownerByPlot[plot]
		if not owner or MonetizationService.GetExtraPodiumsPerFloor(owner) <= 0 then
			return false
		end
	end

	return true
end

--[[ Yalnızca açık katlardaki kaideler. ]]
function PlotService.GetUnlockedPodiums(plot: Model): { Part }
	local unlocked = (plot:GetAttribute("UnlockedFloors") :: number?) or 1
	local result: { Part } = {}

	for _, podium in PlotService.GetPodiums(plot) do
		local floor = (podium:GetAttribute("Floor") :: number?) or 1
		if floor <= unlocked and PlotService.IsPodiumUnlocked(podium) then
			table.insert(result, podium)
		end
	end
	return result
end

function PlotService.FindEmptyPodium(plot: Model): Part?
	for _, podium in PlotService.GetUnlockedPodiums(plot) do
		if not PlotService.IsOccupied(podium) then
			return podium
		end
	end
	return nil
end

--[[
	Açık kat sayısını değiştirir ve kapalı katları hayalete çevirir:
	görünür ama üstüne çıkılamaz, kaidesi kullanılamaz. Tamamen
	gizlemek yerine böyle bırakıyoruz ki oyuncu ne kazanacağını görsün.
]]
function PlotService.SetUnlockedFloors(plot: Model, count: number)
	local unlocked = math.clamp(count, 1, Config.MaxFloors)
	plot:SetAttribute("UnlockedFloors", unlocked)

	--[[
		Kilitli kat TAMAMEN yok sayılmalı: görünmez, çarpışmasız, gölgesiz
		ve ışıksız.

		Eski hâli %75 saydam + çarpışma kapalıydı ve iki şikâyete yol
		açıyordu. Birincisi görsel: satın alınmamış katın merdiveni ve
		kaideleri havada asılı hayalet bloklar olarak duruyordu. İkincisi
		daha kötü: bazı parçalar (güverte altı lamba, korkuluk) çarpışması
		açık kalıyor ve oyuncuyu GÖRÜNMEZ biçimde engelliyordu.

		Artık tek geçişte hepsi kapanıyor. Korkuluk gibi zaten çarpışmasız
		olması gereken parçalar için `BaseCollide` niteliği var: kat açılınca
		o parça kendi varsayılanına dönüyor, körü körüne true olmuyor.
	]]
	local function setFloorParts(root: Instance, open: boolean)
		for _, part in root:GetDescendants() do
			-- Yüzey yazısı (merdiven kemerindeki FLOOR N) parça saydamken de
			-- çiziliyor; kilitli katta havada yazı kalmasın
			if part:IsA("SurfaceGui") then
				part.Enabled = open
				continue
			end
			if not part:IsA("BasePart") then
				continue
			end

			if part:GetAttribute("BaseCollide") == nil then
				part:SetAttribute("BaseCollide", part.CanCollide)
			end

			part.CanCollide = open and part:GetAttribute("BaseCollide") == true
			part.Transparency = if open then 0 else 1
			part.CastShadow = open

			-- Her ışık türü (Point / Spot): kilitli katın ışığı açık kalmasın
			for _, light in part:GetChildren() do
				if light:IsA("Light") then
					light.Enabled = open
				end
			end
		end
	end

	local floors = plot:FindFirstChild("Floors")
	if floors then
		for _, floorModel in floors:GetChildren() do
			local index = tonumber(string.match(floorModel.Name, "%d+")) or 1
			setFloorParts(floorModel, index <= unlocked)
		end
	end

	--[[
		Kaideler Floors'un altında değil, ayrı bir klasörde. Kat kilitliyse
		o kata ait kaideler de tamamen gizleniyor.

		Bonus (gamepass) kaideler farklı: katları açıksa görünür kalıyorlar
		ama yarı saydam ve çarpışmasız — "burada bir yer var ama senin
		değil" mesajı. Onları da gizlersek satın alınacak bir şey olduğu
		hiç belli olmaz.
	]]
	for _, podium in PlotService.GetPodiums(plot) do
		local floor = podium:GetAttribute("Floor")
		local floorOpen = typeof(floor) ~= "number" or floor <= unlocked
		local open = PlotService.IsPodiumUnlocked(podium)

		if not floorOpen then
			podium.Transparency = 1
			podium.CanCollide = false
			podium.CastShadow = false
		else
			podium.Transparency = if open then 0 else 0.6
			-- Kilitli bonus kaide de katı: yarı saydam "senin değil" ama içinden geçilmiyor
			podium.CanCollide = true
			podium.CastShadow = true
		end
	end
end

--[[
	Üssün güncel kaide içeriğini sahibinin profiline yazar.
	Profil DataService'in kaydettiği tablo olduğu için ayrıca kaydetmek
	gerekmiyor; bir sonraki autosave veya çıkış kaydı bunu diske alır.
]]
local function syncProfile(podium: Part)
	local plot = PlotService.GetPlotFromDescendant(podium)
	local owner = plot and ownerByPlot[plot]
	if not (plot and owner) or releasing[owner] then
		return
	end

	local profile = DataService.Get(owner)
	if not profile then
		return
	end

	local units = {}
	for _, other in PlotService.GetPodiums(plot) do
		local unitId = other:GetAttribute("UnitId") :: string
		if unitId ~= "" then
			local mutationId = other:GetAttribute("MutationId") :: string
			table.insert(units, {
				slot = other:GetAttribute("SlotIndex") :: number,
				unitId = unitId,
				mutationId = if mutationId == "" then nil else mutationId,
			})
		end
	end

	profile.units = units
end

--[[ Kaideye karakter yerleştirir. Doluysa false döner. ]]
function PlotService.PlaceUnit(podium: Part, unitId: string, mutationId: string?): boolean
	if PlotService.IsOccupied(podium) then
		return false
	end

	-- Kayıt geri yüklenirken kapalı kata denk gelebilir; sessizce atla
	if not PlotService.IsPodiumUnlocked(podium) then
		return false
	end

	local model = UnitModel.Build(unitId, mutationId)
	model.Name = "Unit"
	model:PivotTo(podium.CFrame * CFrame.new(0, podium.Size.Y / 2, 0))

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local label = UnitModel.BuildLabel(unitId, mutationId)
	label.Parent = model.PrimaryPart

	model.Parent = podium

	podium:SetAttribute("UnitId", unitId)
	podium:SetAttribute("MutationId", mutationId or "")
	podium:SetAttribute("PlacedAt", os.clock())

	syncProfile(podium)

	--[[
		Rozetler. Yerleştirme burada tek noktadan geçtiği için kontrol de
		burada: satın alma, çalma ve çark ödülü aynı yoldan geliyor.
	]]
	local plot = PlotService.GetPlotFromDescendant(podium)
	local owner = plot and ownerByPlot[plot]
	if owner then
		-- İndeks: satın alınan, çalınan ya da çarktan gelen her karakter
		DataService.Discover(owner, unitId)

		local def = Config.GetUnit(unitId)
		if def and def.rarity == "Secret" then
			BadgeService.Award(owner, "SecretFind")
		end

		local unlocked = PlotService.GetUnlockedPodiums(plot)
		local occupied = 0
		for _, other in unlocked do
			if PlotService.IsOccupied(other) then
				occupied += 1
			end
		end
		if occupied == #unlocked and #unlocked > 0 then
			BadgeService.Award(owner, "FullHouse")
		end
	end

	return true
end

--[[ Kaideyi boşaltır ve üstündeki karakterin kimliğini döner. ]]
function PlotService.ClearUnit(podium: Part): (string?, string?)
	if not PlotService.IsOccupied(podium) then
		return nil, nil
	end

	local unitId = podium:GetAttribute("UnitId") :: string
	local mutationId = podium:GetAttribute("MutationId") :: string

	local model = podium:FindFirstChild("Unit")
	if model then
		model:Destroy()
	end

	podium:SetAttribute("UnitId", "")
	podium:SetAttribute("MutationId", "")
	podium:SetAttribute("PlacedAt", 0)

	syncProfile(podium)
	return unitId, (if mutationId == "" then nil else mutationId)
end

-- ─── Sahiplik ───────────────────────────────────────────────────────────────

function PlotService.GetPlotOf(player: Player): Model?
	return plotByOwner[player]
end

function PlotService.GetOwner(plot: Model): Player?
	return ownerByPlot[plot]
end

--[[ Herhangi bir parçadan üstteki plot'u bulur. ]]
function PlotService.GetPlotFromDescendant(instance: Instance): Model?
	local current: Instance? = instance
	while current and current ~= plotsFolder do
		if current:IsA("Model") and current.Parent == plotsFolder then
			return current
		end
		current = current.Parent
	end
	return nil
end

function PlotService.GetAllPlots(): { Model }
	return plots
end

local function setSignText(plot: Model, text: string)
	local sign = plot:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("OwnerLabel")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

--[[
	Oturan karakteri koltuktan kaldırır. Işınlamadan ÖNCE çağrılmalı:
	oturmak karakteri koltuğa kaynakla (SeatWeld) bağlıyor ve PivotTo
	kaynaklı her şeyi taşıyor — acil durum masasının bankı oyuncuyla
	birlikte üsse geliyordu. Sunucuda kaynağı silmek kesin çözüm.
]]
function PlotService.Unseat(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not (humanoid and seat) then
		return
	end
	humanoid.Sit = false
	for _, child in seat:GetChildren() do
		if child:IsA("Weld") and child.Name == "SeatWeld" then
			child:Destroy()
		end
	end
end

--[[ Oyuncuyu kendi üssünün doğuş pedine taşır. Üssü yoksa hiçbir şey yapmaz. ]]
function PlotService.TeleportToPlot(player: Player)
	local plot = plotByOwner[player]
	if not plot then
		return
	end

	local pad = plot:FindFirstChild("SpawnPad")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (pad and pad:IsA("BasePart") and root and root:IsA("BasePart")) then
		return
	end

	PlotService.Unseat(character)
	character:PivotTo(pad.CFrame * CFrame.new(0, 4, 0))
end

--[[ Kayıtlı karakterleri oyuncunun kaidelerine geri koyar. ]]
local function restoreUnits(player: Player)
	local plot = plotByOwner[player]
	local profile = DataService.Get(player)
	if not (plot and profile) then
		return
	end

	-- PlaceUnit profile geri yazıyor; kopyayı gezmezsek listeyi altımızdan çeker
	local stored = table.clone(profile.units)
	local podiums = PlotService.GetPodiums(plot)

	for _, entry in stored do
		local podium = podiums[entry.slot]
		if podium and not PlotService.IsOccupied(podium) then
			PlotService.PlaceUnit(podium, entry.unitId, entry.mutationId)
		end
	end
end

local function grantPlot(player: Player, plot: Model)
	ownerByPlot[plot] = player
	plotByOwner[player] = plot
	setSignText(plot, string.upper(player.DisplayName))

	--[[
		İstemci kendi üssünü bundan buluyor.

		Eskiden tabeladaki yazıyı oyuncunun adıyla karşılaştırıyordu ve
		rebirth rozeti eklenince ("ATCIKM  [R1]") eşleşme bozuldu: rebirth
		atan herkeste üs paneli "no base" diyordu, kilit göstergesi ve
		taşıma oku da çalışmıyordu. Nitelik replike olduğu için remote
		gerekmiyor ve tabelanın yazısı serbest kalıyor.
	]]
	player:SetAttribute("Plot", plot.Name)

	PlotService.TeleportToPlot(player)

	-- Profil hâlâ yükleniyor olabilir
	task.spawn(function()
		local profile = DataService.WaitForProfile(player)
		if not profile then
			return
		end

		-- Katları karakterleri geri koymadan ÖNCE aç: kayıtlı karakter
		-- üst kattaysa kapalı kata konamaz ve sessizce kaybolurdu.
		PlotService.SetUnlockedFloors(plot, Config.GetUnlockedFloors(profile.floorsBought))
		PlotService.RefreshSign(plot)
		restoreUnits(player)
	end)
end

--[[
	Boş üs varsa verir, yoksa sıraya alır. Üssü olmayan oyuncu hiçbir şey
	yapamıyor — satın alamıyor, çalamıyor, kazanç üretemiyor. Eskiden bu
	durumda sadece sunucuya uyarı basılıyordu ve oyuncu ne olduğunu
	anlamadan boş bir ekrana bakıyordu.
]]
--[[ Tabelaya sahibin adını ve rebirth seviyesini yazar. ]]
function PlotService.RefreshSign(plot: Model)
	local owner = ownerByPlot[plot]
	if not owner then
		setSignText(plot, "EMPTY BASE")
		return
	end

	local profile = DataService.Get(owner)
	local rebirths = if profile then profile.rebirths else 0

	if rebirths > 0 then
		setSignText(plot, string.format("%s  [R%d]", string.upper(owner.DisplayName), rebirths))
	else
		setSignText(plot, string.upper(owner.DisplayName))
	end
end

local function assignPlot(player: Player)
	for _, plot in plots do
		if ownerByPlot[plot] == nil then
			grantPlot(player, plot)
			return
		end
	end

	if not table.find(waiting, player) then
		table.insert(waiting, player)
	end

	local position = table.find(waiting, player) or #waiting
	notify(player, string.format("All bases taken - you are #%d in line", position), true)
end

--[[ Boşalan üssü sıradaki oyuncuya verir. ]]
local function grantToNextInLine(plot: Model)
	while #waiting > 0 do
		local next = table.remove(waiting, 1)
		if next and next.Parent then
			grantPlot(next, plot)
			notify(next, "A base opened up - it is yours", false)
			return
		end
	end
end

local function releasePlot(player: Player)
	local plot = plotByOwner[player]
	if not plot then
		return
	end

	-- Kaideleri boşaltırken profile dokunma: kayıt henüz alınmamış olabilir
	releasing[player] = true

	for _, podium in PlotService.GetPodiums(plot) do
		PlotService.ClearUnit(podium)
	end

	releasing[player] = nil

	local items = plot:FindFirstChild("Items")
	if items then
		items:ClearAllChildren()
	end

	plot:SetAttribute("Locked", false)
	PlotService.SetUnlockedFloors(plot, 1)
	setSignText(plot, "EMPTY BASE")

	ownerByPlot[plot] = nil
	plotByOwner[player] = nil
	player:SetAttribute("Plot", nil)

	grantToNextInLine(plot)
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function PlotService.Start()
	-- Tekrar çağrılabilir olmalı: eski dünya siliniyorsa ona ait durum da
	-- silinmeli. Aksi halde plots listesinde yok edilmiş modeller kalır ve
	-- oyuncular artık var olmayan üslere atanır.
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(plots)
	table.clear(ownerByPlot)
	table.clear(plotByOwner)
	table.clear(waiting)

	notifyRemote = Net.Get("Notify")

	local existing = workspace:FindFirstChild("Plots")
	if existing then
		existing:Destroy()
	end

	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace

	for index = 1, Config.PlotCount do
		table.insert(plots, buildPlot(index))
	end
	-- Hepsi dünyadayken: kolonlar alt kattaki eşyaların içinden geçmesin
	for _, plot in plots do
		clearColumns(plot)
	end

	-- Üs ver + her doğuşta o üsse taşı
	local function onPlayerAdded(player: Player)
		assignPlot(player)

		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart")
			task.wait(0.1) -- karakter tam oturmadan ışınlarsak geri kayıyor
			PlotService.TeleportToPlot(player)
		end)

		if player.Character then
			PlotService.TeleportToPlot(player)
		end
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		local index = table.find(waiting, player)
		if index then
			table.remove(waiting, index)
		end
		releasePlot(player)
	end))
end

return PlotService
