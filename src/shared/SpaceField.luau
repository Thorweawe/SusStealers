--!strict
--[[
	Uzay soygununun geometrisi. Sunucu (SpaceService) ve istemci (SpaceFX)
	AYNI hesabı kullanıyor: güvenli bölge, uçuş sınırı, gezegen düzeni,
	mürettebat yerleri, canavarların evi.

	    GEMİ (z > -68)  │ kapı │  LAUNCH BAY (güverte)  │   UZAY → gezegenler (-z)

	  Güvenli   — gemi içi + güverte kutusu. Canavar giremiyor, taşınan
	              karakter burada teslim ediliyor.
	  Uzay      — kuzey duvarın dışı (güverte hariç). Burada oyuncu uçuyor.
	  Gezegen   — Config.SpaceMonsters[i].position platonun üst yüzü;
	              küre merkezi onun radius × PLATEAU_DROP altında.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local SpaceField = {}

-- Platonun küredeki yeri: merkezden radius × bu kadar yukarıda kesiliyor
SpaceField.PLATEAU_DROP = 0.8

local function space()
	return Config.Space
end

--[[ Kuzey duvarın dış yüzü (güvertenin iç kenarı). ]]
function SpaceField.WallOuterZ(): number
	return space().WallZ - space().WallThickness / 2
end

--[[ Güverte kutusu: {min, max} (güvenli bölge). ]]
function SpaceField.DeckBox(): (Vector3, Vector3)
	local s = space()
	local z1 = SpaceField.WallOuterZ()
	return Vector3.new(s.GateX - s.DeckHalfWidth - 4, s.DeckTop - 8, z1 - s.DeckDepth - 4),
		Vector3.new(s.GateX + s.DeckHalfWidth + 4, s.DeckTop + s.SafeHeight, s.WallZ + 1)
end

--[[ Güvertenin dış (uzaya bakan) kenarının z'si. ]]
function SpaceField.DeckEdgeZ(): number
	return SpaceField.WallOuterZ() - space().DeckDepth
end

function SpaceField.DeckCenter(): Vector3
	local s = space()
	return Vector3.new(s.GateX, s.DeckTop, SpaceField.WallOuterZ() - s.DeckDepth / 2)
end

function SpaceField.InDeck(p: Vector3): boolean
	local lo, hi = SpaceField.DeckBox()
	return p.X >= lo.X and p.X <= hi.X and p.Y >= lo.Y and p.Y <= hi.Y and p.Z >= lo.Z and p.Z <= hi.Z
end

--[[ Gemi ya da güverte: canavar erişemez, teslim burada. ]]
function SpaceField.InSafe(p: Vector3): boolean
	-- Gemi içi: kuzey duvarın içi ve istasyonun x aralığı (lobi dahil)
	local inShip = p.Z > SpaceField.WallOuterZ() and p.X > -90 and p.X < 450 and p.Y > -40 and p.Y < 120
	return inShip or SpaceField.InDeck(p)
end

--[[ Uçuş bölgesi: kuzey duvarın dışı, güverte hariç. ]]
function SpaceField.InSpace(p: Vector3): boolean
	return p.Z <= SpaceField.WallOuterZ() and not SpaceField.InDeck(p)
end

--[[ Noktayı uçuş sınırının içine kırpar (değişmediyse aynısı). ]]
function SpaceField.ClampToBounds(p: Vector3): Vector3
	local lo, hi = space().BoundsMin, space().BoundsMax
	return Vector3.new(math.clamp(p.X, lo.X, hi.X), math.clamp(p.Y, lo.Y, hi.Y), math.clamp(p.Z, lo.Z, hi.Z))
end

-- ─── Gezegenler ─────────────────────────────────────────────────────────────

--[[
	Küre platonun ALTINDA: merkez tepe yüzeyinin radius + 0.3 altında.
	ESKİ HATA: merkez 0.8 × radius aşağıdaydı, kürenin tepesi platodan
	0.2 × radius taşıyor, canavar ve mürettebat kürenin içinde kalıyordu.
]]
function SpaceField.PlanetCenter(def: Config.SpaceMonsterDef): Vector3
	return def.position - Vector3.new(0, def.radius + 0.3, 0)
end

--[[ Platonun kalınlığı: kenarı kürenin yüzeyine gömülecek kadar (mesa gibi). ]]
function SpaceField.PlateauDepth(def: Config.SpaceMonsterDef): number
	local r = def.radius
	local edge = SpaceField.PlateauRadius(def)
	return r + 0.3 - math.sqrt(r * r - edge * edge) + 2
end

function SpaceField.PlateauRadius(def: Config.SpaceMonsterDef): number
	return def.radius * math.sqrt(1 - SpaceField.PLATEAU_DROP ^ 2)
end

--[[ Canavarın baktığı yön: güverteye doğru, yatay. ]]
function SpaceField.Facing(def: Config.SpaceMonsterDef): Vector3
	local d = SpaceField.DeckCenter() - def.position
	local flat = Vector3.new(d.X, 0, d.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
end

--[[ Canavarın evi (ayaklarının bastığı nokta): platonun arka yarısı. ]]
function SpaceField.MonsterHome(def: Config.SpaceMonsterDef): CFrame
	local facing = SpaceField.Facing(def)
	local p = def.position - facing * (SpaceField.PlateauRadius(def) * 0.38)
	return CFrame.lookAt(p, p + facing)
end

--[[ Mürettebatların durduğu noktalar (ayak hizası, dünya), canavarın önünde yay. ]]
function SpaceField.CrewSpots(def: Config.SpaceMonsterDef): { Vector3 }
	local s = space()
	local facing = SpaceField.Facing(def)
	local right = facing:Cross(Vector3.yAxis)
	local center = def.position + facing * (SpaceField.PlateauRadius(def) * 0.1)
	local list = {}
	local n = s.CrewPerPlanet
	for i = 1, n do
		local a = math.rad(-62 + (i - 1) * (124 / math.max(1, n - 1)))
		local offset = facing * math.cos(a) * s.CrewRing + right * math.sin(a) * s.CrewRing
		table.insert(list, center + offset)
	end
	return list
end

--[[ Canavarın yakalama menzili. ]]
function SpaceField.CatchRadius(def: Config.SpaceMonsterDef): number
	return space().CatchRadius + def.scale * 2
end

--[[
	Fırlatma yolu: canavarın elinden gemiye. Önce güverte kapısının önündeki
	bir noktaya yüksek bir yayla, oradan içeri düz; t 0..1.
]]
function SpaceField.ThrowPath(from: Vector3, t: number): Vector3
	local s = space()
	local door = Vector3.new(s.GateX, s.DeckTop + 14, SpaceField.DeckEdgeZ() - 10)
	local landing = s.Landing
	local split = 0.78
	if t <= split then
		local u = t / split
		local peak = (from + door) / 2 + Vector3.new(0, 40 + (from - door).Magnitude * 0.12, 0)
		local a = from:Lerp(peak, u)
		local b = peak:Lerp(door, u)
		return a:Lerp(b, u)
	end
	local u = (t - split) / (1 - split)
	-- İçeri girerken hafif kavis: yere yumuşak insin
	return door:Lerp(landing, u) + Vector3.new(0, math.sin(u * math.pi) * 3, 0)
end

return SpaceField
