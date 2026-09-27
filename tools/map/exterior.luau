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

		-- Çatı: güneş paneli dizileri, antenler, radar
		do
			local roof = K.folder("Roof", beyond)
			local top = M.WALL_H + 1
			local panelBlue = rgb(38, 70, 150)
			for i, x in { M.X0 + 60, M.X0 + 170, M.X0 + 280, M.X0 + 390, M.X0 + 500 } do
				for _, z in { M.Z0 + 40, M.Z1 - 40 } do
					K.vcyl(roof, "SolarMast", x, top + 3, z, 6, 1.2, C.frameDark, ghost)
					local tilt = CFrame.new(x, top + 6.5, z) * CFrame.Angles(math.rad(if z < M.centerZ then -22 else 22), 0, 0)
					K.boxAt(roof, "SolarFrame", tilt, Vector3.new(34, 0.5, 14), C.frame, ghost)
					for k = 0, 3 do
						K.boxAt(roof, "SolarCell", tilt * CFrame.new(-12.6 + k * 8.4, 0.3, 0), Vector3.new(7.8, 0.3, 13), panelBlue,
							{ ghost = true, material = Enum.Material.Glass, reflect = 0.2 })
					end
				end
				-- Anten: ucunda yanıp sönen kırmızı lamba
				local az = M.centerZ + (if i % 2 == 0 then 30 else -30)
				K.vcyl(roof, "Antenna", x + 30, top + 12, az, 24, 0.7, C.metal, ghost)
				K.vcyl(roof, "AntennaBar", x + 30, top + 18, az, 0.5, 6, C.frameDark, ghost)
				local tip = K.ball(roof, "AntennaTip", x + 30, top + 24.6, az, 1.6, C.red, glow())
				tip:SetAttribute("PulsePeriod", 1.4 + i * 0.13)
			end
			-- Dönen radar çanağı (doğu ucunda, burnun üstünde)
			local rx, rz = M.X1 - 40, M.centerZ
			K.vcyl(roof, "RadarBase", rx, top + 2, rz, 4, 8, C.frameDark, ghost)
			K.vcyl(roof, "RadarMast", rx, top + 7, rz, 8, 1.6, C.metal, ghost)
			local dish = K.boxAt(roof, "RadarDish", CFrame.new(rx, top + 13, rz) * CFrame.Angles(0, 0, math.rad(-60)),
				Vector3.new(1.2, 16, 16), C.frame, { ghost = true, shape = Enum.PartType.Cylinder })
			dish:SetAttribute("SpinSpeed", 25)
			K.ball(roof, "RadarEye", rx, top + 13, rz, 2.4, C.green, glow())
			-- Çatı kenarı seyir lambaları
			for x = M.X0 + 20, M.X1 - 20, 60 do
				for _, z in { M.Z0 + 3.3, M.Z1 - 3.3 } do
					local l = K.box(roof, "RoofLight", x, top + 0.9, z, 1.6, 0.8, 1.6, if z < M.centerZ then C.red else C.green, glow())
					l:SetAttribute("PulsePeriod", 2.2)
				end
			end
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
