--!strict
--[[
	Gemi dışı: pencerelerden görünenler.
	  Motorlar   — batıda iki dev motor gövdesi, arkalarında mavi alev
	               (Skeld'in iticileri). Batı pencerelerinden görünüyor.
	  Burun      — doğuda, kokpit camının altından uzanan sivri pruva
	  Uzay       — uzakta bir gezegen ve uydusu; pencerelerin önünden yavaşça
	               geçen asteroitler ve fırlatılmış bir mürettebat (DecorFX
	               DriftSpeed/DriftRange ile kaydırıyor)
	Ötesi      — (2026-09-28, "dışarıya bir sürü şey ekle, boş kalmasın";
	               lombozlar artık gerçek açıklık) çatıda güneş panelleri,
	               antenler ve dönen radar; süzülen uydular, yük gemileri,
	               asteroit kuşakları, fırlatılmış mürettebatlar; uzakta halka
	               istasyon, nebulalar, kuyruklu yıldız, parıldayan yıldızlar.

	KURAL: uzay soygununun uçuş hacmine (Config.Space.BoundsMin/Max, kuzey)
	hiçbir şey girmiyor — orada gezegen yolunun kendi içeriği var ve yıldız
	tozuyla karışırdı. Her şey hayalet (çarpışmasız), istasyonun dışında.
]]

return {
	folders = { "Exterior", "Drifters", "Beyond" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local ex = K.folder("Exterior")
		local T = M.WALL_T
		local hull = C.hullOut
		local cobalt = rgb(52, 92, 196)

		-- ─── Motorlar ───────────────────────────────────────────────────────
		for _, z in { 0, M.ROW_SPACING } do
			local f = K.folder("Engine", ex)
			local x0 = M.X0 - T / 2
			local cy = 14
			local along = CFrame.new(0, cy, z)
			local function seg(name: string, xa: number, xb: number, dia: number, color: Color3, extra: { [string]: any }?)
				return K.boxAt(f, name, along * CFrame.new(-(xa + xb) / 2, 0, 0) + Vector3.new(0, 0, 0), Vector3.new(xb - xa, dia, dia), color,
					K.merge({ shape = Enum.PartType.Cylinder }, extra))
			end
			-- Gövdeye bağlayan ayak: duvarın dış yüzüne 0.1 kala biter (pencere çerçeveleriyle aynı düzlemde olmasın)
			K.box(f, "Pylon", x0 - 5.1, cy, z, 10, 16, 20, hull)
			-- Motor gövdesi: batıya doğru (x azalıyor)
			seg("Nacelle", -x0 + 8, -x0 + 70, 38, rgb(150, 164, 176))
			for _, b in { 16, 36, 56 } do
				seg("NacelleBand", -x0 + b, -x0 + b + 3, 39.6, rgb(96, 110, 122), { ghost = true })
			end
			seg("NacelleStripe", -x0 + 24, -x0 + 28, 39.4, cobalt, { ghost = true })
			seg("NozzleRing", -x0 + 70, -x0 + 76, 32, rgb(70, 82, 94))
			seg("NozzleThroat", -x0 + 76, -x0 + 77, 26, C.shadow)
			-- Alev: iç içe iki parlak silindir + küre; DecorFX nabız veriyor
			local flame = seg("Flame", -x0 + 77, -x0 + 91, 24, rgb(90, 190, 255), { emit = "Fixture", transparency = 0.25, ghost = true })
			flame.CastShadow = false
			flame:SetAttribute("PulsePeriod", 0.5)
			local inner = seg("FlameCore", -x0 + 77, -x0 + 101, 14, rgb(210, 245, 255), { emit = "Fixture", transparency = 0.1, ghost = true })
			inner.CastShadow = false
			local tip = K.ball(f, "FlameTip", x0 - 101, cy, z, 14, rgb(150, 220, 255), { emit = "Fixture", transparency = 0.35, ghost = true })
			tip.CastShadow = false
			K.light(flame, rgb(110, 190, 255), 60, 2.2)
		end

		-- ─── Burun ──────────────────────────────────────────────────────────
		do
			--[[
				Plan görünüşünde sivri üçgen pruva: iki dik üçgen prizma, taban
				kenarı doğu duvarının DIŞ yüzünde. Tamamen gövdenin dışında —
				ilk denemede 45° dönmüş kare kullanılmıştı ve yarısı istasyonun
				içinden, üslerin zemininden çıkıyordu. Üstü kokpit camının
				altında (y 8): pilot camdan bakınca geminin burnunu görüyor.
			]]
			local f = K.folder("Nose", ex)
			local xw = M.X1 + T / 2
			local L = 130
			local half = (M.Z1 - M.Z0) / 2 + T / 2
			local czn = M.centerZ
			local apex = Vector2.new(xw + L, czn)
			local foot = Vector2.new(xw, czn)
			for _, s in { -1, 1 } do
				K.flatTriangle(f, "Prow", Vector2.new(xw, czn + s * half), apex, foot, -5.6, 27, hull)
				K.flatTriangle(f, "ProwDeck", Vector2.new(xw, czn + s * (half - 4)), Vector2.new(xw + L - 10, czn), foot, 8.2, 0.6, rgb(120, 138, 152))
			end
			K.box(f, "ProwStripe", xw + 40, 8.6, czn, 60, 0.2, 3, C.hazard, { ghost = true })
			local nav = K.ball(f, "NoseLight", xw + L - 8, 9.5, czn, 3, C.red, { emit = "Fixture" })
			nav:SetAttribute("PulsePeriod", 1.8)
		end

		-- Kuzey kanatçıkları KALKTI (2026-09-28): Launch Bay'den çıkarken iki yanda
		-- duran mavi kamalar "saçma duruyor" denildi.
		K.folder("Wings", ex):Destroy()

		-- ─── Uzay ───────────────────────────────────────────────────────────
		do
			local f = K.folder("Space", ex)
			-- Gezegen: kuzeyde, uzakta; cam şeritten ve kuzey pencerelerinden görünüyor
			-- Uzay soygununun gezegen sırası (z -330..-2520) bunun önünde kalsın
			local planet = K.ball(f, "Planet", M.centerX - 520, 360, M.Z0 - 3900, 1200, rgb(226, 150, 96), { ghost = true })
			planet.CastShadow = false
			K.ball(f, "PlanetBand", M.centerX - 520, 430, M.Z0 - 3896, 1184, rgb(236, 180, 120), { ghost = true }).CastShadow = false
			local moon = K.ball(f, "Moon", M.centerX + 420, 330, M.Z0 - 1100, 140, rgb(196, 204, 214), { ghost = true })
			moon.CastShadow = false
			-- Güneyde ikinci gezegen: lobi pencerelerinden
			local p2 = K.ball(f, "Planet2", M.centerX + 700, 120, M.LOBBY_Z1 + 1300, 520, rgb(90, 140, 230), { ghost = true })
			p2.CastShadow = false
		end

		-- ─── Süzülenler ─────────────────────────────────────────────────────
		local drift = K.folder("Drifters")
		local function asteroid(x: number, y: number, z: number, s: number, speed: number, range: number)
			local m = Instance.new("Model")
			m.Name = "Asteroid"
			m.Parent = drift
			local core = K.ball(m, "Rock", x, y, z, 6 * s, rgb(120, 112, 104), { ghost = true })
			K.ball(m, "Rock", x + 2.4 * s, y + 1.2 * s, z - 1 * s, 4 * s, rgb(104, 96, 90), { ghost = true })
			K.ball(m, "Rock", x - 2 * s, y - 1.5 * s, z + 1.4 * s, 3.4 * s, rgb(136, 128, 118), { ghost = true })
			m.PrimaryPart = core
			m:SetAttribute("DriftSpeed", speed)
			m:SetAttribute("DriftRange", range)
		end
		asteroid(M.X0 - 120, 30, M.Z0 - 90, 2.2, 5, 700)
		asteroid(M.X0 - 60, 12, M.Z0 - 150, 3, 3.5, 700)
		asteroid(M.X0 - 200, 44, M.Z0 - 60, 1.4, 7, 800)
		asteroid(M.X0 - 160, 20, M.Z1 + 30, 1.6, 4, 760)
		asteroid(M.CAF_X0 - 260, 26, M.LOBBY_Z1 + 80, 2.6, 4.5, 820)

		-- Fırlatılmış mürettebat: "... was not The Impostor."
		local ejected = K.crewmate(drift, CFrame.new(M.X0 - 140, 30, M.Z0 - 120) * CFrame.Angles(math.rad(20), math.rad(60), math.rad(35)),
			K.crew(1), 2.2)
		ejected.Name = "Ejected"
		ejected:SetAttribute("DriftSpeed", 4)
		ejected:SetAttribute("DriftRange", 760)

		-- ─── Ötesi ──────────────────────────────────────────────────────────
		local beyond = K.folder("Beyond")
		local rng = Random.new(20260928)
		local ghost = { ghost = true }
		local function glow(extra: { [string]: any }?): { [string]: any }
			return K.merge({ ghost = true, emit = "Fixture" }, extra)
		end
		local space = K.Config.Space or { BoundsMin = Vector3.new(-220, -200, -2650), BoundsMax = Vector3.new(580, 280, -68) }
		-- Uçuş hacmi + pay: buraya hiçbir şey konmuyor
		local keepOutMin = space.BoundsMin - Vector3.new(120, 120, 120)
		local keepOutMax = space.BoundsMax + Vector3.new(120, 120, 60)
		local function outsideFlight(p: Vector3): boolean
			return p.X < keepOutMin.X or p.X > keepOutMax.X or p.Y < keepOutMin.Y or p.Y > keepOutMax.Y
				or p.Z < keepOutMin.Z or p.Z > keepOutMax.Z
		end

		--[[
			Üst yapı (2026-09-28, "gemi çok kare, Star Wars gemilerine
			benzesin"): Star Destroyer dili.
			  - İki yandan yükselen eğimli zırh (kama): kuzey ve güney duvar
			    üstünden ortaya doğru yükseliyor. Ortada tavandaki cam şeridin
			    (Skylight, z 42..86) üstü açık kalıyor: bir "hendek".
			  - Zırhta panel çizgileri, kule topları, hendek ışıkları.
			  - Batıda (arka) basamaklı komuta kulesi: köprü, iki algılayıcı
			    küre, anten; arkasında üçüncü, en büyük motor.
			Hepsi hayalet (çarpışmasız) ve duvarların DIŞINDA / ÜSTÜNDE.
		]]
		do
			local sup = K.folder("Superstructure", beyond)
			local armor = rgb(158, 166, 178)
			local armorDark = rgb(112, 120, 134)
			local panel = rgb(96, 104, 118)
			local top = M.WALL_H + 1.15
			local xa, xb = M.X0 - T / 2 - 0.3, M.X1 + T / 2 + 0.3
			local sky0, sky1 = M.centerZ - 24, M.centerZ + 24
			local H1 = 12      -- alt kademe (duvardan kırılma çizgisine)
			local H2 = 18      -- üst kademe (kırılmadan hendek kenarına), daha dik

			--[[ Kama: alçak kenarı zLow'da (yükseklik 0), yüksek kenarı zHigh'ta (H). ]]
			local function slope(name: string, x0: number, x1: number, zLow: number, zHigh: number, y0: number, h: number, color: Color3): WedgePart
				local w = Instance.new("WedgePart")
				w.Name = name
				w.Anchored = true
				w.CanCollide = false
				w.CanQuery = false
				w.CanTouch = false
				w.CastShadow = true
				w.Material = Enum.Material.SmoothPlastic
				w.Color = color
				w.Size = Vector3.new(x1 - x0, h, math.abs(zHigh - zLow))
				local center = Vector3.new((x0 + x1) / 2, y0 + h / 2, (zLow + zHigh) / 2)
				local toLow = Vector3.new(0, 0, if zLow < zHigh then -1 else 1)
				w.CFrame = CFrame.lookAt(center, center + toLow)
				w.Parent = sup
				return w
			end
			-- Eğimin yüzeyindeki nokta ve yüzey normali (dışa)
			local function onSlope(zLow: number, zHigh: number, z: number, h: number): (number, Vector3)
				local len = math.abs(zHigh - zLow)
				local t = math.clamp(math.abs(z - zLow) / len, 0, 1)
				local theta = math.atan2(h, len)
				local dirLow = if zLow < zHigh then -1 else 1
				return top + h * t, Vector3.new(0, math.cos(theta), dirLow * math.sin(theta))
			end

			local nLow, nHigh = M.Z0 - T / 2 - 0.4, sky0 - 2
			local sLow, sHigh = M.Z1 + T / 2 + 0.4, sky1 + 2
			--[[
				İki kademe: alt kademe duvar kenarından hendeğe yayvan; üst
				kademe ortadan başlayıp daha dik yükseliyor. Kırılma çizgisinde
				koyu bir kaburga. Doğu ucunda kalça (burna doğru inen kama).
			]]
			slope("ArmorNorth", xa, xb, nLow, nHigh, top, H1, armor)
			slope("ArmorSouth", xa, xb, sLow, sHigh, top, H1, armor)
			local nMid, sMid = (nLow + nHigh) / 2, (sLow + sHigh) / 2
			slope("ArmorNorthUpper", xa, xb - 8, nMid, nHigh, top + H1 / 2, H2, armorDark:Lerp(armor, 0.55))
			slope("ArmorSouthUpper", xa, xb - 8, sMid, sHigh, top + H1 / 2, H2, armorDark:Lerp(armor, 0.55))
			for _, z in { nMid, sMid } do
				K.box(sup, "ArmorRib", (xa + xb) / 2 - 4, top + H1 / 2 + 0.35, z, xb - xa - 8, 0.9, 1.6, panel, { ghost = true })
			end
			-- Doğu kalçası: hendek bitince (cam şeridin doğusu) burna doğru inen kama
			do
				local hx0, hx1 = M.X1 - 44, xb
				local w = Instance.new("WedgePart")
				w.Name = "ArmorHip"
				w.Anchored = true
				w.CanCollide = false
				w.CanQuery = false
				w.CanTouch = false
				w.Material = Enum.Material.SmoothPlastic
				w.Color = armor
				local height = H1 / 2 + H2
				w.Size = Vector3.new(sLow - nLow, height, hx1 - hx0)
				local center = Vector3.new((hx0 + hx1) / 2, top + height / 2, (nLow + sLow) / 2)
				w.CFrame = CFrame.lookAt(center, center + Vector3.xAxis)
				w.Parent = sup
			end

			-- Panel çizgileri: eğime yatık ince şeritler
			for _, side in { { nLow, nHigh }, { sLow, sHigh } } do
				for k = 1, 3 do
					local z = side[1] + (side[2] - side[1]) * (k / 7)
					local y, n = onSlope(side[1], side[2], z, H1)
					local pos = Vector3.new((xa + xb) / 2, y, z) + n * 0.12
					K.boxAt(sup, "PanelLine", CFrame.fromMatrix(pos, Vector3.xAxis, n), Vector3.new(xb - xa - 8, 0.2, 1.1), panel, { ghost = true })
				end
				-- Dikine derzler (alt kademe)
				for x = M.X0 + 40, M.X1 - 60, 64 do
					local zm = side[1] + (side[2] - side[1]) * 0.25
					local y, n = onSlope(side[1], side[2], zm, H1)
					local len = math.abs(side[2] - side[1]) * 0.5 - 6
					local along = n:Cross(Vector3.xAxis)
					K.boxAt(sup, "PanelSeam", CFrame.fromMatrix(Vector3.new(x, y, zm) + n * 0.14, Vector3.xAxis, n, along),
						Vector3.new(0.9, 0.2, len), panel, { ghost = true })
				end
				-- Kule topları (turbolaser): dış kenara yakın ve ortada
				for _, frac in { 0.12, 0.36 } do
					local z = side[1] + (side[2] - side[1]) * frac
					for x = M.X0 + 70, M.X1 - 60, 90 do
						local y, n = onSlope(side[1], side[2], z, H1)
						local base = Vector3.new(x, y, z)
						K.boxAt(sup, "TurretBase", CFrame.fromMatrix(base + n * 0.6, Vector3.xAxis, n), Vector3.new(4.4, 1.4, 4.4), armorDark,
							{ ghost = true, shape = Enum.PartType.Cylinder })
						K.ball(sup, "TurretDome", base.X, base.Y + 1.6, base.Z, 3.6, armor, { ghost = true })
						local out = if side[1] < side[2] then -1 else 1
						for _, dx in { -0.6, 0.6 } do
							K.boxAt(sup, "TurretGun", CFrame.new(base.X + dx, base.Y + 2, base.Z + out * 2.4), Vector3.new(0.35, 0.35, 3.2), panel, { ghost = true })
						end
					end
				end
			end

			-- Hendek ışıkları: eğimlerin tepe kenarında, cam şerit boyunca
			for _, z in { nHigh - 0.3, sHigh + 0.3 } do
				local strip = K.box(sup, "TrenchLight", (M.X0 + M.X1) / 2 - 20, top + H1 / 2 + H2 + 0.3, z, M.X1 - M.X0 - 90, 0.4, 0.4, rgb(110, 210, 255),
					{ ghost = true, emit = "Fixture" })
				strip.CastShadow = false
			end
			-- Seyir lambaları: dış köşelerde yanıp sönen
			for _, p in { { xb - 2, nLow + 1, C.green }, { xb - 2, sLow - 1, C.red }, { xa + 2, nLow + 1, C.green }, { xa + 2, sLow - 1, C.red } } do
				local l = K.ball(sup, "NavLight", p[1], top + 1, p[2], 1.8, p[3], glow())
				l:SetAttribute("PulsePeriod", 1.6)
			end

			-- ── Komuta kulesi (batı ucu, cam şeridin dışında) ───────────────
			local tx0, tx1 = xa, M.X0 + 46
			local tz = M.centerZ
			K.box(sup, "TowerBase", (tx0 + tx1) / 2, top + 16, tz, tx1 - tx0, 32, 96, armor, { ghost = true })
			K.box(sup, "TowerMid", (tx0 + tx1) / 2 + 1, top + 37.8, tz, 38, 12, 70, armor, { ghost = true })
			K.box(sup, "TowerMidBand", (tx0 + tx1) / 2 + 1, top + 37.8, tz, 38.6, 1.4, 70.6, armorDark, { ghost = true })
			K.box(sup, "TowerNeck", (tx0 + tx1) / 2 + 2, top + 50.6, tz, 16, 14, 20, armorDark, { ghost = true })
			local bridgeX = (tx0 + tx1) / 2 + 2
			local bridgeY = top + 61.4
			K.box(sup, "Bridge", bridgeX, bridgeY, tz, 44, 8, 96, armor, { ghost = true })
			K.box(sup, "BridgeTop", bridgeX, bridgeY + 4.4, tz, 40, 1, 90, armorDark, { ghost = true })
			-- Köprü camları: doğuya (burna) bakıyor
			local win = K.box(sup, "BridgeWindows", bridgeX + 22.05, bridgeY + 0.6, tz, 0.4, 1.8, 88, rgb(150, 230, 255),
				{ ghost = true, emit = "Screen" })
			win.CastShadow = false
			-- Algılayıcı küreler
			for _, dz in { -34, 34 } do
				K.vcyl(sup, "SensorMast", bridgeX - 4, bridgeY + 8.5, tz + dz, 8, 2, armorDark, { ghost = true })
				K.ball(sup, "SensorGlobe", bridgeX - 4, bridgeY + 16, tz + dz, 13, armor, { ghost = true })
			end
			-- Anten ve dönen radar
			K.vcyl(sup, "Antenna", bridgeX + 6, bridgeY + 11, tz, 16, 0.6, C.metal, { ghost = true })
			local tip = K.ball(sup, "AntennaTip", bridgeX + 6, bridgeY + 19.4, tz, 1.4, C.red, glow())
			tip:SetAttribute("PulsePeriod", 1.3)
			local dish = K.boxAt(sup, "RadarDish", CFrame.new(bridgeX - 12, bridgeY + 7, tz) * CFrame.Angles(0, 0, math.rad(-60)),
				Vector3.new(1, 10, 10), C.frame, { ghost = true, shape = Enum.PartType.Cylinder })
			dish:SetAttribute("SpinSpeed", 25)

			-- ── Hançer gövde: istasyonun ALTINDA, burna doğru sivrilen üçgen ──
			--[[
				Yukarıdan bakınca Star Destroyer'ın üçgeni. İstasyonun zemini ve
				tünelleri y -19'a kadar iniyor; gövde onun altında (-24'ten
				aşağı), iç mekâna girmiyor. İki basamak: alttaki geniş, üstteki
				biraz dar; kenarında ince ışık hattı.
			]]
			local apex = Vector2.new(M.X1 + 230, M.centerZ)
			for i, spec in { { -39, 14, 150, rgb(128, 136, 150) }, { -28.4, 7, 128, armor } } do
				local halfW = spec[3]
				local back = xa - 20
				local foot = Vector2.new(back, M.centerZ)
				for _, s2 in { -1, 1 } do
					K.flatTriangle(sup, "DaggerHull" .. i, Vector2.new(back, M.centerZ + s2 * halfW), apex - Vector2.new(i * 18, 0), foot,
						spec[1], spec[2], spec[4], { CanCollide = false, CastShadow = true })
				end
			end
			-- Kenar ışıkları: üçgenin iki kenarı boyunca
			for _, s2 in { -1, 1 } do
				local p0 = Vector2.new(xa - 20, M.centerZ + s2 * 128)
				local p1 = apex - Vector2.new(36, 0)
				local mid = (p0 + p1) / 2
				local dir = (p1 - p0)
				local light = K.boxAt(sup, "DaggerEdgeLight", CFrame.lookAt(Vector3.new(mid.X, -24.7, mid.Y), Vector3.new(p1.X, -24.7, p1.Y)),
					Vector3.new(0.5, 0.4, dir.Magnitude - 20), rgb(110, 210, 255), glow())
				light.CastShadow = false
			end

			-- ── Ana motor: kulenin arkasında, en büyüğü ─────────────────────
			local ey = top + 14
			local x0 = xa
			local function eseg(name: string, dxa: number, dxb: number, dia: number, color: Color3, extra: { [string]: any }?)
				return K.boxAt(sup, name, CFrame.new(x0 - (dxa + dxb) / 2, ey, tz), Vector3.new(dxb - dxa, dia, dia), color,
					K.merge({ shape = Enum.PartType.Cylinder, ghost = true }, extra))
			end
			eseg("MainNacelle", 0, 46, 30, rgb(150, 164, 176))
			eseg("MainBand", 14, 17, 31.4, armorDark)
			eseg("MainBand", 32, 35, 31.4, armorDark)
			eseg("MainNozzle", 46, 52, 26, rgb(70, 82, 94))
			eseg("MainThroat", 52, 53, 21, C.shadow)
			local flame = eseg("MainFlame", 53, 66, 20, rgb(90, 190, 255), { emit = "Fixture", transparency = 0.25 })
			flame.CastShadow = false
			flame:SetAttribute("PulsePeriod", 0.5)
			local core = eseg("MainFlameCore", 53, 76, 11, rgb(210, 245, 255), { emit = "Fixture", transparency = 0.1 })
			core.CastShadow = false
			K.light(flame, rgb(110, 190, 255), 60, 2)
		end

		-- Uydu: gövde, altın folyo, iki güneş kanadı, çanak, anten
		local function satellite(cf: CFrame, s: number, speed: number, range: number)
			local m = Instance.new("Model")
			m.Name = "Satellite"
			m.Parent = drift
			local body = K.boxAt(m, "Body", cf, Vector3.new(6, 6, 8) * s, C.metal, ghost)
			K.boxAt(m, "Foil", cf, Vector3.new(6.2, 4, 6) * s, rgb(214, 170, 60), { ghost = true, material = Enum.Material.Foil })
			for _, side in { -1, 1 } do
				K.boxAt(m, "Boom", cf * CFrame.new(side * 6 * s, 0, 0), Vector3.new(6, 0.5, 0.5) * s, C.frameDark, ghost)
				for k = 0, 2 do
					K.boxAt(m, "Wing", cf * CFrame.new(side * (10 + k * 5.2) * s, 0, 0), Vector3.new(5, 0.3, 7) * s, rgb(40, 76, 160),
						{ ghost = true, material = Enum.Material.Glass, reflect = 0.25 })
				end
			end
			K.boxAt(m, "Dish", cf * CFrame.new(0, 0, -5.2 * s) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.8, 7, 7) * s, C.frame,
				{ ghost = true, shape = Enum.PartType.Cylinder })
			K.boxAt(m, "Mast", cf * CFrame.new(0, 5 * s, 0), Vector3.new(0.3, 4, 0.3) * s, C.frameDark, ghost)
			local blink = K.boxAt(m, "Blink", cf * CFrame.new(0, 7.2 * s, 0), Vector3.one * 0.9 * s, C.red, glow({ shape = Enum.PartType.Ball }))
			blink:SetAttribute("PulsePeriod", 1.1)
			m.PrimaryPart = body
			m:SetAttribute("DriftSpeed", speed)
			m:SetAttribute("DriftRange", range)
		end
		satellite(CFrame.new(-560, 60, 40) * CFrame.Angles(0.3, 0.8, 0.2), 1.6, 3, 220)
		satellite(CFrame.new(840, 70, 150) * CFrame.Angles(-0.2, 2.4, 0.4), 1.8, 2.5, 260)
		satellite(CFrame.new(260, 80, 820) * CFrame.Angles(0.5, 1.2, -0.3), 2, 3, 300)
		satellite(CFrame.new(-420, 20, 620) * CFrame.Angles(0.1, -0.6, 0.6), 1.4, 2, 200)
		satellite(CFrame.new(980, 110, -300) * CFrame.Angles(0.4, 0.3, 0.1), 2.2, 2, 240)

		-- Yük gemisi: uzun gövde, köprü, renkli konteynerler, mavi motor ışığı
		local function freighter(cf: CFrame, s: number, speed: number, range: number)
			local m = Instance.new("Model")
			m.Name = "Freighter"
			m.Parent = drift
			local hull = K.boxAt(m, "Hull", cf, Vector3.new(120, 16, 24) * s, rgb(120, 132, 146), ghost)
			K.boxAt(m, "Keel", cf * CFrame.new(0, -9 * s, 0), Vector3.new(104, 3, 16) * s, rgb(80, 90, 104), ghost)
			K.boxAt(m, "Bow", cf * CFrame.new(66 * s, 0, 0), Vector3.new(14, 12, 18) * s, rgb(140, 152, 166), ghost)
			K.boxAt(m, "Bridge", cf * CFrame.new(-44 * s, 14 * s, 0), Vector3.new(16, 12, 18) * s, C.frame, ghost)
			K.boxAt(m, "BridgeGlass", cf * CFrame.new(-35.9 * s, 16 * s, 0), Vector3.new(0.4, 3, 15) * s, rgb(140, 220, 255), glow())
			local colors = { rgb(214, 70, 60), rgb(240, 180, 50), rgb(60, 150, 210), rgb(90, 190, 110), rgb(200, 110, 200) }
			for k = 0, 5 do
				local c = colors[rng:NextInteger(1, #colors)]
				K.boxAt(m, "Container", cf * CFrame.new((-22 + k * 14) * s, 12 * s, 0), Vector3.new(12, 8, 20) * s, c, ghost)
			end
			for _, side in { -1, 1 } do
				local eng = K.boxAt(m, "Engine", cf * CFrame.new(-64 * s, 0, side * 7 * s), Vector3.new(10, 9, 9) * s, rgb(70, 82, 94),
					{ ghost = true, shape = Enum.PartType.Cylinder })
				eng.CastShadow = false
				local flame = K.boxAt(m, "Exhaust", cf * CFrame.new(-72 * s, 0, side * 7 * s), Vector3.new(8, 7, 7) * s, rgb(110, 200, 255),
					glow({ shape = Enum.PartType.Cylinder, transparency = 0.25 }))
				flame:SetAttribute("PulsePeriod", 0.4)
			end
			for _, side in { -1, 1 } do
				local nav = K.boxAt(m, "NavLight", cf * CFrame.new(40 * s, 0, side * 12.4 * s), Vector3.one * 1.2 * s,
					if side < 0 then C.red else C.green, glow({ shape = Enum.PartType.Ball }))
				nav:SetAttribute("PulsePeriod", 1.6)
			end
			m.PrimaryPart = hull
			m:SetAttribute("DriftSpeed", speed)
			m:SetAttribute("DriftRange", range)
		end
		-- Doğuda uzaklaşan, güneyde lobinin önünden geçen, batıda uzakta bir tane
		freighter(CFrame.new(900, 140, -40) * CFrame.Angles(0, math.rad(-20), 0), 1.4, 6, 900)
		freighter(CFrame.new(-700, 90, 1150) * CFrame.Angles(0, math.rad(-5), 0), 1.8, 5, 1600)
		freighter(CFrame.new(-1300, 200, 300) * CFrame.Angles(0, math.rad(80), 0), 1.2, 4, 700)

		-- Asteroit kuşakları: batı, doğu, güney (uçuş hacminin dışında)
		local function rock(x: number, y: number, z: number, s: number, speed: number, range: number)
			local m = Instance.new("Model")
			m.Name = "Asteroid"
			m.Parent = drift
			local tone = rng:NextNumber(0.85, 1.15)
			local base = rgb(math.floor(118 * tone), math.floor(108 * tone), math.floor(100 * tone))
			local core = K.ball(m, "Rock", x, y, z, 6 * s, base, ghost)
			for _ = 1, rng:NextInteger(2, 4) do
				local o = Vector3.new(rng:NextNumber(-2.6, 2.6), rng:NextNumber(-2, 2), rng:NextNumber(-2.6, 2.6)) * s
				K.ball(m, "Rock", x + o.X, y + o.Y, z + o.Z, rng:NextNumber(2.6, 4.4) * s, base:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.25)), ghost)
			end
			-- Bazılarında parlayan kristal
			if rng:NextNumber() < 0.3 then
				K.ball(m, "Crystal", x + 2.4 * s, y + 2.2 * s, z, 1.6 * s, rgb(120, 230, 255), glow({ transparency = 0.1 }))
			end
			m.PrimaryPart = core
			m:SetAttribute("DriftSpeed", speed)
			m:SetAttribute("DriftRange", range)
		end
		local function belt(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, count: number, maxX: number?)
			local placed = 0
			local tries = 0
			while placed < count and tries < count * 20 do
				tries += 1
				local p = Vector3.new(rng:NextNumber(x0, x1), rng:NextNumber(y0, y1), rng:NextNumber(z0, z1))
				local range = rng:NextNumber(200, 600)
				-- Kayarken istasyona girmesin (x ekseninde kayıyor)
				if maxX and p.X + range > maxX then
					range = math.max(60, maxX - p.X)
				end
				if outsideFlight(p) and outsideFlight(p + Vector3.new(range, 0, 0)) then
					rock(p.X, p.Y, p.Z, rng:NextNumber(1, 4), rng:NextNumber(1.5, 6), range)
					placed += 1
				end
			end
		end
		belt(-1400, -500, -60, 160, -120, 560, 22, -320)
		belt(700, 1300, -60, 180, -60, 520, 16)
		belt(-600, 900, -80, 200, 600, 1100, 18)

		-- Fırlatılmış mürettebatlar: her yönde bir tane
		for i, spot in {
			{ CFrame.new(-420, 42, 260), 5 },
			{ CFrame.new(760, 34, 60), 9 },
			{ CFrame.new(120, 56, 660), 3 },
			{ CFrame.new(-360, 24, -20), 11 },
		} do
			local c = K.crewmate(drift, spot[1] * CFrame.Angles(math.rad(30 * i), math.rad(70 * i), math.rad(40 + 20 * i)), K.crew(spot[2]), 2.4)
			c.Name = "Ejected"
			c:SetAttribute("DriftSpeed", 2 + i * 0.6)
			c:SetAttribute("DriftRange", 260)
		end

		-- Halka istasyon: güneydoğuda, uzakta; göbek, dört kol, pencereli halka
		do
			local f = K.folder("RingStation", beyond)
			local center = CFrame.new(1500, 320, 1500) * CFrame.Angles(math.rad(62), math.rad(-35), 0)
			local R, N = 170, 32
			for k = 0, N - 1 do
				local a = k / N * math.pi * 2
				local seg = center * CFrame.Angles(0, 0, a) * CFrame.new(R, 0, 0)
				K.boxAt(f, "RingHull", seg, Vector3.new(22, 2 * math.pi * R / N + 2, 26), rgb(190, 200, 212), ghost).CastShadow = false
				K.boxAt(f, "RingLights", seg * CFrame.new(-11.2, 0, 0), Vector3.new(0.6, 2 * math.pi * R / N - 6, 6),
					if k % 2 == 0 then rgb(255, 230, 150) else rgb(150, 220, 255), glow()).CastShadow = false
			end
			K.ball(f, "Hub", center.X, center.Y, center.Z, 60, rgb(210, 218, 228), ghost).CastShadow = false
			K.boxAt(f, "HubBand", center * CFrame.Angles(0, math.rad(90), 0), Vector3.new(8, 62, 62), rgb(90, 200, 255),
				glow({ shape = Enum.PartType.Cylinder })).CastShadow = false
			for k = 0, 3 do
				local a = k / 4 * math.pi * 2 + math.pi / 4
				K.boxAt(f, "Spoke", center * CFrame.Angles(0, 0, a) * CFrame.new(R / 2 + 15, 0, 0), Vector3.new(R - 30, 10, 10), rgb(150, 162, 176), ghost).CastShadow = false
			end
		end

		-- Nebulalar: çok saydam, dev parlak bulutlar (uzakta, ufukta)
		local function nebula(center: Vector3, size: number, a: Color3, b: Color3)
			local f = K.folder("Nebula", beyond)
			-- Çok sayıda, çok saydam küre üst üste: ortası yoğun, kenarı yumuşak
			for k = 1, 9 do
				local o = Vector3.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.5, 0.5)) * size
				local d = size * rng:NextNumber(0.35, 0.9)
				local cloud = K.ball(f, "Cloud", center.X + o.X, center.Y + o.Y, center.Z + o.Z, d, a:Lerp(b, (k - 1) / 8),
					glow({ transparency = 0.955 }))
				cloud.CastShadow = false
			end
		end
		nebula(Vector3.new(-2800, 400, 700), 900, rgb(200, 80, 255), rgb(255, 100, 180))
		nebula(Vector3.new(3000, 250, 600), 800, rgb(60, 220, 230), rgb(80, 120, 255))
		nebula(Vector3.new(600, 500, 3400), 1100, rgb(255, 150, 60), rgb(255, 80, 120))

		-- Kuyruklu yıldız: doğu göğünde, sabit; parlak baş, sönen kuyruk
		do
			local f = K.folder("Comet", beyond)
			local head = Vector3.new(2200, 800, -500)
			local dir = Vector3.new(0.8, 0.25, -0.55).Unit
			K.ball(f, "CometHead", head.X, head.Y, head.Z, 40, rgb(220, 250, 255), glow()).CastShadow = false
			for k = 1, 9 do
				local p = head + dir * k * 38
				K.ball(f, "CometTail", p.X, p.Y, p.Z, 40 - k * 2.6, rgb(120, 210, 255), glow({ transparency = 0.3 + k * 0.07 })).CastShadow = false
			end
		end

		-- Parıldayan yıldızlar: istasyonun çevresinde uzak bir kabukta
		do
			local f = K.folder("Stars", beyond)
			local center = Vector3.new(M.centerX, 0, M.centerZ)
			local placed = 0
			while placed < 90 do
				local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.35, 1), rng:NextNumber(-1, 1))
				if dir.Magnitude < 0.2 then
					continue
				end
				local p = center + dir.Unit * rng:NextNumber(1800, 3200)
				if not outsideFlight(p) then
					continue
				end
				local star = K.ball(f, "Star", p.X, p.Y, p.Z, rng:NextNumber(5, 14),
					if rng:NextNumber() < 0.2 then rgb(255, 220, 160) else rgb(235, 245, 255), glow())
				star.CastShadow = false
				placed += 1
			end
		end
	end,
}
