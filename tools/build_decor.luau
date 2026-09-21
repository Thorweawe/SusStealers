--!strict
--[[
	Harita dekorunu koddan kurar. Studio'da MCP ile çalıştırılır:

	    local src = game:GetService("HttpService"):GetAsync(
	        "http://127.0.0.1:8788/tools/build_decor.luau")
	    loadstring(src)()

	Her şey workspace.Decor altına gider. PlotService.Start() sadece
	workspace.Plots'u siliyor, o yüzden dekor sunucu yeniden başlayınca
	kaybolmaz.

	Tekrar çalıştırılabilir: varsa eski Decor klasörünü silip yeniden kurar.

	ÖNEMLİ: Üsler arasına kapalı duvar YOK. Çalmak için rakip üsse koşmak
	gerekiyor; duvar koymak oyunu kilitler. Ayrım hissini köşe sütunları
	ve neon çerçeve veriyor, geçişler açık kalıyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local DEEP = Color3.fromRGB(26, 30, 40)        -- zemin
local METAL = Color3.fromRGB(58, 66, 82)       -- sütunlar
local NEON = Color3.fromRGB(80, 220, 255)      -- çerçeve ışığı
local NEON_TOP = Color3.fromRGB(150, 245, 255) -- sütun başlığı

local folder = workspace:FindFirstChild("Decor")
if folder then
	folder:Destroy()
end

folder = Instance.new("Folder")
folder.Name = "Decor"
folder.Parent = workspace

local function newPart(
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	collide: boolean,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = collide
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- ─── Ölçüler ────────────────────────────────────────────────────────────────
-- Üsler x ekseninde sıralı: i. üssün merkezi (i-1) * PlotSpacing
-- Taban y=0 merkezli, yüksekliği PlotSize.Y, yani üstü y = PlotSize.Y/2

local halfX = Config.PlotSize.X / 2
local halfZ = Config.PlotSize.Z / 2
local topY = Config.PlotSize.Y / 2
local span = (Config.PlotCount - 1) * Config.PlotSpacing

-- ─── Zemin ──────────────────────────────────────────────────────────────────
--[[
	Ayrı bir zemin parçası koymuyoruz. Varsayılan Baseplate'in üstü zaten
	y=0'da ve üs tabanları y=-1..+1 arasında, yani üsler onun 1 stud üstünde
	duruyor. Araya kendi zeminimizi koyarsak ya altta kalıp görünmez ya da
	aynı hizada titrer (z-fighting).

	Onun yerine Baseplate'i istasyon zeminine çeviriyoruz: fazladan parça yok,
	2048x2048 olduğu için kenarından düşme riski de yok.

	Eski hali: Color 163,162,165 / Material Plastic / içinde kareli Texture.
]]
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate and baseplate:IsA("BasePart") then
	baseplate.Color = DEEP
	baseplate.Material = Enum.Material.Slate
	baseplate.TopSurface = Enum.SurfaceType.Smooth

	-- Varsayılan kareli doku temayla uyuşmuyor
	for _, child in baseplate:GetChildren() do
		if child:IsA("Texture") or child:IsA("Decal") then
			child:Destroy()
		end
	end
end

-- ─── Üs başına çerçeve ve sütunlar ──────────────────────────────────────────

local FRAME_W = 0.8
local FRAME_H = 0.25
local PILLAR = 2.2
local PILLAR_H = 13

for index = 1, Config.PlotCount do
	local originX = (index - 1) * Config.PlotSpacing

	local plotFolder = Instance.new("Folder")
	plotFolder.Name = string.format("Plot%dDecor", index)
	plotFolder.Parent = folder

	-- Neon çerçeve: tabanın hemen üstünde, dört kenar.
	-- CanCollide false, yoksa kenarda zıplarken takılırsın.
	local frameY = topY + FRAME_H / 2

	for _, side in { -1, 1 } do
		-- Uzun kenarlar (z boyunca)
		newPart(
			"FrameX",
			Vector3.new(FRAME_W, FRAME_H, Config.PlotSize.Z),
			Vector3.new(originX + side * halfX, frameY, 0),
			NEON,
			Enum.Material.Neon,
			false,
			plotFolder
		)
		-- Kısa kenarlar (x boyunca)
		newPart(
			"FrameZ",
			Vector3.new(Config.PlotSize.X, FRAME_H, FRAME_W),
			Vector3.new(originX, frameY, side * halfZ),
			NEON,
			Enum.Material.Neon,
			false,
			plotFolder
		)
	end

	-- Köşe sütunları: ayrım hissi versin ama geçişi kapatmasın
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local px = originX + sx * halfX
			local pz = sz * halfZ

			newPart(
				"Pillar",
				Vector3.new(PILLAR, PILLAR_H, PILLAR),
				Vector3.new(px, topY + PILLAR_H / 2, pz),
				METAL,
				Enum.Material.Metal,
				true,
				plotFolder
			)

			-- Sütun başlığı: tepede parlayan küçük blok
			newPart(
				"PillarCap",
				Vector3.new(PILLAR + 0.6, 0.5, PILLAR + 0.6),
				Vector3.new(px, topY + PILLAR_H + 0.25, pz),
				NEON_TOP,
				Enum.Material.Neon,
				false,
				plotFolder
			)
		end
	end
end

-- ─── Özet ───────────────────────────────────────────────────────────────────

local parts = 0
for _, d in folder:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end

print(string.format(
	"Decor kuruldu: %d us, %d parca. Zemin %.0f x %.0f stud.",
	Config.PlotCount,
	parts,
	span + Config.PlotSize.X + 60,
	Config.PlotSize.Z + 60
))
