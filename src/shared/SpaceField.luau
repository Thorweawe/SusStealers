--!strict
--[[
	Uzay yürüyüşü alanının geometrisi ve asteroitleri. Sunucu (SpaceService)
	ve istemci (SpaceFX) AYNI hesabı kullanıyor.

	Yerleşim Config.Space.Origin'e göre, yol -Z yönünde:

	    RIHTIM (0,0,0) ── yol parçaları (aralarında atlanacak boşluklar) ── YUVA

	  Rıhtım   — hava kilidinin uzaydaki ucu: doğuş noktası, teslim alanı,
	             gemiye dönüş konsolu. Canavarlar buraya giremiyor.
	  Yol      — Config.Space.Segments: kaya platformlar; aralardaki boşluk
	             düşük yerçekiminde kolay atlanıyor ama düşen kaybediyor.
	  Yuva     — Void Beast'lerin yuvası; kayıp mürettebatlar balonlarda.

	ASTEROİTLER DETERMİNİSTİK: her şerit sunucu saatinden hesaplanıyor
	(RogueTrack / WheelSpin ile aynı fikir). Ağda tek bir asteroit konumu
	gitmiyor; her istemci kendi ekranında her karede çiziyor, sunucu da aynı
	formülle "gerçekten çarptı mı" diye doğruluyor.

	    şerit: z, hız, periyot, yarıçap, yükseklik, yön, faz
	    d = ((t + faz) mod periyot) × hız      (0 .. span arası görünür)
	    x = (−span/2 + d) × yön
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local SpaceField = {}

export type Lane = Config.SpaceLane

local function space()
	return Config.Space
end

--[[ Yerel (Origin'e göre) noktayı dünyaya çevirir. ]]
function SpaceField.World(localPos: Vector3): Vector3
	return space().Origin + localPos
end

function SpaceField.DockCenter(): Vector3
	return space().Origin
end

--[[ Rıhtımdaki doğuş noktası (yola, -Z'ye bakıyor). ]]
function SpaceField.DockSpawn(): CFrame
	local p = space().Origin + Vector3.new(0, 3.5, 8)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, -1))
end

function SpaceField.NestCenter(): Vector3
	return space().Origin + Vector3.new(0, 0, space().NestZ)
end

--[[ Yuvadaki kayıp mürettebat balonlarının yerleri (dünya). ]]
function SpaceField.SpotPositions(): { Vector3 }
	local s = space()
	local center = SpaceField.NestCenter()
	local list = {}
	for i = 1, s.NestSpots do
		-- Yolun karşısındaki yarım halkaya diziliyor: oyuncu yuvaya girip derine yürüyor
		local a = math.rad(-150 + (i - 1) * (300 / math.max(1, s.NestSpots - 1)))
		local r = s.SpotRing
		table.insert(list, center + Vector3.new(math.sin(a) * r, s.SpotHeight, -math.cos(a) * r * 0.85 - 6))
	end
	return list
end

--[[ Canavarların uyuduğu yerler (dünya). ]]
function SpaceField.MonsterHomes(): { Vector3 }
	local s = space()
	local center = SpaceField.NestCenter()
	local list = {}
	for i = 1, s.MonsterCount do
		local a = math.rad(-60 + (i - 1) * (120 / math.max(1, s.MonsterCount - 1)))
		table.insert(list, center + Vector3.new(math.sin(a) * 22, s.MonsterHover, -math.cos(a) * 22 - 4))
	end
	return list
end

--[[ Rıhtımda mı (teslim ve canavarların giremediği güvenli alan). ]]
function SpaceField.InDock(position: Vector3): boolean
	local d = position - space().Origin
	return math.abs(d.X) <= space().DockHalf.X and d.Z <= space().DockHalf.Y and d.Z >= -space().DockHalf.Y - 4
		and math.abs(d.Y) <= 18
end

--[[ Uzay alanına düşüp kayboldu mu (yolun çok altında). ]]
function SpaceField.Fell(position: Vector3): boolean
	return position.Y < space().Origin.Y - space().FallDepth
end

-- ─── Asteroitler ────────────────────────────────────────────────────────────

--[[
	Şeridin t anındaki asteroit konumu (dünya); şerit o an boşsa nil.
	`t` sunucu saati (workspace:GetServerTimeNow()).
]]
function SpaceField.AsteroidAt(lane: Lane, t: number): Vector3?
	local span = space().LaneSpan
	local cycle = (t + lane.phase) % lane.period
	local d = cycle * lane.speed
	if d > span then
		return nil
	end
	local x = (-span / 2 + d) * lane.dir
	return space().Origin + Vector3.new(x, lane.height, lane.z)
end

--[[
	Şerit yolun üstünü ne zaman kesecek: şu an kesiyorsa 0, yoksa kaç
	saniye sonra (istemci uyarı şeridini buna göre yakıyor).
]]
function SpaceField.SecondsUntilCrossing(lane: Lane, t: number): number
	local s = space()
	local half = s.PathHalfWidth + lane.radius
	-- Yolun ortasına varış mesafesi: span/2; yola giriş: span/2 - half
	local enter = (s.LaneSpan / 2 - half) / lane.speed
	local leave = (s.LaneSpan / 2 + half) / lane.speed
	local cycle = (t + lane.phase) % lane.period
	if cycle >= enter and cycle <= leave then
		return 0
	end
	if cycle < enter then
		return enter - cycle
	end
	return lane.period - cycle + enter
end

--[[
	Bu noktaya çarpan asteroit şeridinin numarası (yoksa nil). `pad` oyuncu
	gövdesinin yarıçapı gibi eklenen pay.
]]
function SpaceField.HitAt(t: number, position: Vector3, pad: number): number?
	for i, lane in space().Lanes do
		local rock = SpaceField.AsteroidAt(lane, t)
		if rock and (rock - position).Magnitude <= lane.radius + pad then
			return i
		end
	end
	return nil
end

--[[
	Sunucu doğrulaması: `lane` şeridinin asteroidi [t0, t1] aralığında bu
	noktaya `tolerance` kadar yaklaştı mı. İstemci çarpmayı kendi ekranında
	görüyor; arada ağ gecikmesi olduğu için bir pencere taranıyor.
]]
function SpaceField.CameNear(laneIndex: number, t0: number, t1: number, position: Vector3, tolerance: number): boolean
	local lane = space().Lanes[laneIndex]
	if not lane then
		return false
	end
	local t = t0
	while t <= t1 do
		local rock = SpaceField.AsteroidAt(lane, t)
		if rock and (rock - position).Magnitude <= lane.radius + tolerance then
			return true
		end
		t += 0.05
	end
	return false
end

return SpaceField
