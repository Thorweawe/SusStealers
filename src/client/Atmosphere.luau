--!strict
-- İstemci tarafı görsel ayarı: uzay/alacakaranlık havası.
--
-- Neden istemcide: Lighting ortak alan (Batur'un şeridi sayılır). İstemciden
-- değiştirince place dosyası değişmiyor ama her oyuncu bu script'i çalıştırdığı
-- için efekt herkeste görünüyor. Batur'un Studio'sunda düzenleme modunda
-- görünmez, sadece oyunu çalıştırınca görünür.
--
-- Ayarları kurcalamak istersen hepsi aşağıdaki sabitlerde.

local Lighting = game:GetService("Lighting")

local Atmosphere = {}

-- CLOCK_TIME en önemli ayar: 6'nın altında güneş ufkun altında kalır, sahnede
-- hiç yönlü ışık olmaz ve ortam ışığını ne kadar yükseltirsen yükselt her şey
-- düz gri görünür. Karanlık geliyorsa önce burayı yükselt.
-- 7.5 = sabah güneşi, 12 = tam tepe, 18 = gün batımı.
local CLOCK_TIME = 7.6
local BRIGHTNESS = 3.0
local AMBIENT = Color3.fromRGB(130, 138, 158)
local OUTDOOR_AMBIENT = Color3.fromRGB(155, 166, 192)
local EXPOSURE = 0.15

local HAZE_DENSITY = 0.18
local HAZE_COLOR = Color3.fromRGB(150, 165, 200)
local HAZE_DECAY = Color3.fromRGB(80, 90, 120)

--[[ Aynı isimde efekt varsa onu kullanır, yoksa yaratır. İki kez
     çalıştırılırsa efektler üst üste binmesin diye. ]]
local function ensure<T>(className: string, name: string): any
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

function Atmosphere.Start()
	Lighting.ClockTime = CLOCK_TIME
	Lighting.Brightness = BRIGHTNESS
	Lighting.Ambient = AMBIENT
	Lighting.OutdoorAmbient = OUTDOOR_AMBIENT
	Lighting.GeographicLatitude = 20
	Lighting.ExposureCompensation = EXPOSURE
	Lighting.EnvironmentDiffuseScale = 0.85
	Lighting.EnvironmentSpecularScale = 0.75

	local haze = ensure("Atmosphere", "SusAtmosphere")
	haze.Density = HAZE_DENSITY
	haze.Offset = 0.1
	haze.Color = HAZE_COLOR
	haze.Decay = HAZE_DECAY
	haze.Glare = 0.2
	haze.Haze = 1.2

	local bloom = ensure("BloomEffect", "SusBloom")
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.1

	-- Kaidelerdeki nadirlik ışıkları ve mutasyon renkleri biraz daha çıksın.
	local grade = ensure("ColorCorrectionEffect", "SusGrade")
	grade.Saturation = 0.08
	grade.Contrast = 0.10
	grade.Brightness = 0
	grade.TintColor = Color3.fromRGB(240, 245, 255)
end

return Atmosphere
