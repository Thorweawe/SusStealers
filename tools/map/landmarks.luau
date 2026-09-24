--!strict
--[[
	İstasyonun simge noktaları:
	  Reaktör     — omurga koridorunun batı ucu (Skeld'de motorların arası)
	  Navigasyon  — doğu ucu: dev ön cam, gösterge paneli, iki pilot koltuğu
	  Havalandırma kapakları — Skeld'in yuvarlak köşeli ızgaraları
	  Güvenlik kameraları, yön tabelaları
]]

return {
	folders = { "Landmarks", "Vents" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local FLOOR = M.TILE_TOP
		local lm = K.folder("Landmarks")
		local midZ = (M.SPINE_Z0 + M.SPINE_Z1) / 2

		-- ─── Reaktör ────────────────────────────────────────────────────────
		do
			local f = K.folder("Reactor", lm)
			local r = M.REACTOR_RECT
			local purple, purple2, purpleGrout = rgb(132, 112, 190), rgb(120, 100, 176), rgb(78, 62, 120)
			K.box(f, "ReactorBase", (r[1] + r[3]) / 2, 0.06, (r[2] + r[4]) / 2, r[3] - r[1], 0.12, r[4] - r[2], purpleGrout)
			K.tiles(f, { r[1], r[2], r[3], r[4] }, 7, 8, 0.45, FLOOR, 0.24, purple, purple2, nil, "ReactorTile")

			local cx, cz = r[1] + 13, midZ
			K.vcyl(f, "CorePlinth", cx, FLOOR + 1, cz, 2, 17, C.metal)
			K.vcyl(f, "CoreRing", cx, FLOOR + 2.3, cz, 0.6, 18.4, purple)
			local glass = K.vcyl(f, "CoreGlass", cx, FLOOR + 2 + 11, cz, 22, 12, C.glass,
				{ material = Enum.Material.Glass, transparency = 0.55 })
			glass.CastShadow = false
			local core = K.vcyl(f, "Core", cx, FLOOR + 2 + 11, cz, 20.5, 5.5, C.cyan, { emit = "Fixture" })
			K.light(core, C.cyan, 34, 1.6)
			core:SetAttribute("PulsePeriod", 3.2)
			for _, y in { 8, 14, 20 } do
				K.vcyl(f, "CoreBand", cx, FLOOR + y, cz, 1, 12.8, C.metal)
			end
			K.vcyl(f, "CoreCap", cx, FLOOR + 25.3, cz, 2.6, 15, C.metal)
			K.vcyl(f, "CoreCrown", cx, FLOOR + 27.1, cz, 1, 9, purple)
			for k = 0, 3 do
				local a = math.rad(45 + k * 90)
				K.vcyl(f, "CorePipe", cx + math.cos(a) * 5, (FLOOR + 27.6 + M.WALL_H) / 2, cz + math.sin(a) * 5,
					M.WALL_H - FLOOR - 27.6, 1.6, C.metalDark)
			end
			local beacon = K.ball(f, "Beacon", cx, FLOOR + 28.4, cz, 1.8, C.red, { emit = "Fixture" })
			beacon:SetAttribute("PulsePeriod", 1.6)

			-- El okuyucuları (Reaktör erimesi): iki yanda
			for _, s in { -1, 1 } do
				local z = cz + s * 14
				K.box(f, "ScannerStand", cx + 6, FLOOR + 2.5, z, 3, 5, 3, C.metal)
				local tilt = CFrame.new(cx + 6, FLOOR + 5.4, z) * CFrame.Angles(0, 0, math.rad(35))
				K.boxAt(f, "ScannerPad", tilt, Vector3.new(0.6, 4, 4), C.shadow)
				local palm = tilt * CFrame.new(0.35, -0.3, 0)
				K.boxAt(f, "Palm", palm, Vector3.new(0.1, 1.6, 1.4), C.cyan, { emit = "Screen" })
				for k = -1.5, 1.5 do
					K.boxAt(f, "Finger", palm * CFrame.new(0, 1.3, k * 0.36), Vector3.new(0.1, 1, 0.26), C.cyan, { emit = "Screen" })
				end
			end

			-- Tabela yok: reaktör kendini anlatıyor (sarkan tabela boruların
			-- arkasında kalıp yarım okunuyordu). Platformun kenarında uyarı şeridi
			K.hazard(f, r[3] - 0.6, FLOOR + 0.07 + M.LIFT, cz, r[4] - r[2] - 2, 0.9, "z", 2.4)
		end

		-- ─── Navigasyon ─────────────────────────────────────────────────────
		do
			local f = K.folder("Navigation", lm)
			local r = M.NAV_RECT
			local beige, beige2, grout = rgb(226, 210, 170), rgb(212, 196, 156), rgb(160, 142, 104)
			K.box(f, "NavBase", (r[1] + r[3]) / 2, 0.06, (r[2] + r[4]) / 2, r[3] - r[1], 0.12, r[4] - r[2], grout)
			K.tiles(f, r, 7, 8, 0.45, FLOOR, 0.24, beige, beige2, nil, "NavTile")

			-- Ön cam: doğu duvarındaki açıklığa (y 10..42, z r2-6..r4+6)
			local z0, z1 = r[2] - 6, r[4] + 6
			local x = M.X1
			K.box(f, "Windshield", x, 26, (z0 + z1) / 2, 0.4, 32, z1 - z0, C.glass,
				{ material = Enum.Material.Glass, transparency = 0.7, collide = true, reflect = 0.05 })
			local n = 4
			for k = 1, n - 1 do
				K.box(f, "ShieldMullion", x, 26, z0 + k * (z1 - z0) / n, 1.2, 32.2, 1, C.frame)
			end
			K.box(f, "ShieldTransom", x, 34, (z0 + z1) / 2, 1.2, 0.8, z1 - z0 + 0.2, C.frame)
			-- Kenar dikmeleri açıklığa 0.3 taşıyor: duvarın kesik yüzüyle aynı düzlemde kalmasın
			for _, s in { -1, 1 } do
				K.box(f, "ShieldFrame", x - 1.6, 26, if s < 0 then z0 - 0.6 else z1 + 0.6, 1, 34, 1.8, C.frame)
			end
			-- Üst/alt bar açıklığa 0.3 taşıyor: kesiğin yüzüyle aynı düzlemde değil
			K.box(f, "ShieldFrame", x - 1.6, 42.6, (z0 + z1) / 2, 1, 1.8, z1 - z0 + 3.6, C.frame)
			K.box(f, "ShieldFrame", x - 1.6, 9.4, (z0 + z1) / 2, 1, 1.8, z1 - z0 + 3.6, C.frame)

			-- Gösterge paneli: camın önünde, eğik üst yüzeyli
			local dash = r[3] - 4
			K.box(f, "Dash", dash, FLOOR + 2.5, (r[2] + r[4]) / 2, 5, 5, r[4] - r[2] - 4, C.metal)
			local top = CFrame.new(dash - 0.6, FLOOR + 5.6, (r[2] + r[4]) / 2) * CFrame.Angles(0, 0, math.rad(20))
			K.boxAt(f, "DashTop", top, Vector3.new(5.4, 0.6, r[4] - r[2] - 4), C.frame)
			-- Düğmeler ve yıldız haritası
			local tones = { C.red, C.green, C.cyan, C.hazard, rgb(236, 90, 190) }
			for k = 0, 13 do
				local z = r[2] + 4 + k * ((r[4] - r[2] - 8) / 13)
				local btn = K.boxAt(f, "DashButton", top * CFrame.new(-1.2 + (k % 2) * 1.4, 0.36, z - (r[2] + r[4]) / 2),
					Vector3.new(0.8, 0.14, 0.8), tones[k % #tones + 1], { emit = "Indicator" })
				if k % 4 == 0 then
					btn:SetAttribute("PulsePeriod", 1.1 + k * 0.1)
				end
			end
			local chart = K.boxAt(f, "StarChart", top * CFrame.new(1.3, 0.36, 0), Vector3.new(2, 0.1, 12), rgb(20, 40, 90), { emit = "Screen" })
			chart.CastShadow = false
			for k = -2, 2 do
				K.boxAt(f, "ChartStar", top * CFrame.new(1.3 + (k % 2) * 0.4, 0.42, k * 2.2), Vector3.new(0.3, 0.06, 0.3), C.white,
					{ emit = "Indicator" })
			end

			-- Pilot koltukları camın tarafına bakıyor
			for k, z in { midZ - 6, midZ + 6 } do
				local seat = CFrame.lookAt(Vector3.new(r[1] + 10, FLOOR, z), Vector3.new(r[1] + 20, FLOOR, z))
				K.boxAt(f, "SeatPost", seat * CFrame.new(0, 1.2, 0), Vector3.new(0.9, 2.4, 0.9), C.metalDark)
				K.boxAt(f, "Seat", seat * CFrame.new(0, 2.7, 0), Vector3.new(3.8, 0.8, 3.8), if k == 1 then C.red else rgb(70, 110, 220))
				K.boxAt(f, "SeatBack", seat * CFrame.new(0, 5.2, 1.8), Vector3.new(3.8, 4.2, 0.8), if k == 1 then C.red else rgb(70, 110, 220))
			end
			-- Dümen kolu
			K.vcyl(f, "Stick", r[1] + 13, FLOOR + 2, midZ, 4, 0.5, C.metalDark)
			K.ball(f, "StickKnob", r[1] + 13, FLOOR + 4.2, midZ, 1.1, C.red)

			K.hazard(f, r[1] + 0.6, FLOOR + 0.07 + M.LIFT, midZ, r[4] - r[2] - 2, 0.9, "z", 2.4)
		end

		-- ─── Yön tabelası: kafeteryaya giden koridor ────────────────────────
		do
			local f = K.folder("Wayfinding", lm)
			-- Kapının üstünde (istasyon içinden). Koridorda sarkan ikinci
			-- tabela kalabalık yaptığı için kaldırıldı.
			local over = CFrame.lookAt(Vector3.new(M.centerX, M.GATE_H + 6.5, M.IZ1 - 1.2), Vector3.new(M.centerX, M.GATE_H + 6.5, M.IZ1 - 2.2))
			K.sign(f, "GateSign", over, 30, 5, "CAFETERIA · EGGS · SHOP", K.rgb(90, 150, 212))
		end

		-- ─── Havalandırma kapakları ─────────────────────────────────────────
		--[[
			Skeld kapağı: yuvarlak köşeli çerçeve, içinde beş dikey yarık, dört
			köşede vida. Zemine yatık, üstünde yürünüyor.
		]]
		local vents = K.folder("Vents")
		local function vent(x: number, z: number, rot: number)
			local cf = CFrame.new(x, FLOOR, z) * CFrame.Angles(0, math.rad(rot), 0)
			K.boxAt(vents, "VentFrame", cf * CFrame.new(0, 0.1 + M.LIFT, 0), Vector3.new(6.4, 0.2, 4), C.metal)
			for _, sx in { -1, 1 } do
				K.boxAt(vents, "VentRound", cf * CFrame.new(sx * 3.2, 0.1 + M.LIFT, 0) * CFrame.Angles(0, 0, math.rad(90)),
					Vector3.new(0.2, 4, 4), C.metal, { shape = Enum.PartType.Cylinder })
			end
			K.boxAt(vents, "VentWell", cf * CFrame.new(0, 0.14 + M.LIFT, 0), Vector3.new(6, 0.2, 2.8), C.shadow)
			for k = -2, 2 do
				K.boxAt(vents, "VentSlat", cf * CFrame.new(k * 1.2, 0.2 + M.LIFT, 0), Vector3.new(0.55, 0.16, 2.6), C.metalDark)
			end
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					K.boxAt(vents, "VentScrew", cf * CFrame.new(sx * 3.9, 0.22 + M.LIFT, sz * 1.3) * CFrame.Angles(0, 0, math.rad(90)),
						Vector3.new(0.1, 0.5, 0.5), C.metalDark, { shape = Enum.PartType.Cylinder })
				end
			end
		end

		--[[
			Üsler arasındaki koridorlarda ve omurgada kapak YOK: yolun
			ortasındaki koyu ızgaralar uzaktan zeminde delik gibi okunuyordu
			("önümde boşluklar var"). Yalnızca iki uç köşede, yürüme yolunun
			dışında birer tane kaldı.
		]]
		vent(M.IX0 + 16, M.IZ0 + 24, 90)
		vent(M.IX1 - 16, M.IZ1 - 24, 90)

		-- ─── Güvenlik kameraları: koridor köşelerinde, kırmızı kayıt lambası ─
		local cams = K.folder("Cameras", lm)
		local function camera(pos: Vector3, lookAt: Vector3)
			local cf = CFrame.lookAt(pos, lookAt)
			K.boxAt(cams, "CamBody", cf, Vector3.new(1.8, 1.8, 3.4), C.frame)
			K.boxAt(cams, "CamLens", cf * CFrame.new(0, 0, -1.8) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.3, 1.3, 1.3), C.shadow,
				{ shape = Enum.PartType.Cylinder })
			local rec = K.boxAt(cams, "CamLight", cf * CFrame.new(0.6, 1.05, -1), Vector3.new(0.45, 0.45, 0.45), C.red,
				{ shape = Enum.PartType.Ball, emit = "Fixture" })
			rec:SetAttribute("PulsePeriod", 1.3)
			K.boxAt(cams, "CamArm", cf * CFrame.new(0, 0, 2.3), Vector3.new(0.5, 0.5, 1.4), C.metalDark)
		end
		camera(Vector3.new(M.centerX - 22, 18.6, M.IZ1 - 2.7), Vector3.new(M.centerX - 60, 2, midZ))
		camera(Vector3.new(M.centerX + 22, 18.6, M.IZ1 - 2.7), Vector3.new(M.centerX + 60, 2, midZ))
		camera(Vector3.new(M.IX0 + 2.7, 18.6, M.IZ0 + 30), Vector3.new(M.IX0 + 60, 2, midZ))
		camera(Vector3.new(M.IX1 - 2.7, 18.6, M.IZ0 + 30), Vector3.new(M.IX1 - 60, 2, midZ))
	end,
}
