--!strict
--[[
	Ek odalar: istasyonun güney duvarından, yan koridorların ucundan açılan
	iki küçük görev odası (ölçüler kit.luau'da, M.ANNEX_*). Bilerek küçük:
	oyunun asıl alanı istasyon koridoru, bunlar kısa bir sapma.

	  STORAGE     (batı kapı) — Skeld'in deposu: yakıt tankı ("Fuel Engines")
	                ve kablo panosu ("Fix Wiring"), kasalar, variller
	  LABORATORY  (doğu kapı) — Polus laboratuvarı: kart okuyucu masası
	                ("Swipe Card"), numune tüpleri

	Görev konsolları "TaskId" niteliği taşıyor; TaskService promptu adıyla
	değil bu nitelikle buluyor (Config.Tasks'taki kimlik).

	Kapıların kendisi station.luau'da (güney duvarı); bu bölüm yalnızca
	duvarın arkasını kuruyor. Station yeniden kurulmadan kapı açılmaz.
]]

return {
	folders = { "Annex" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local T = M.WALL_T
		local FLOOR = M.TILE_TOP
		local H = M.ANNEX_H
		local root = K.folder("Annex")

		local z0 = M.Z1
		local z1 = M.Z1 + M.ANNEX_D
		local cz = (z0 + z1) / 2
		--[[
			İstasyon duvarının dış yüzü. Odanın duvarları, tavanı ve zemini ya
			bu yüzden başlıyor ya da duvarın İÇİNE giriyor; aynı düzlemde
			duran iki yüz kamera oynadıkça titreşiyordu (harita denetimi).
		]]
		local zWall = z0 + T / 2

		--[[
			Oda kabuğu: zemin, üç duvar (dördüncüsü istasyonun güney duvarı,
			kapısı orada), tavan, iki ışık paneli ve kapının istasyon tarafında
			oda tabelası.
		]]
		local function room(name: string, label: string, ax: number, tile: Color3, tile2: Color3, grout: Color3, accent: Color3): Folder
			local f = K.folder(name, root)
			local x0, x1 = ax - M.ANNEX_W / 2, ax + M.ANNEX_W / 2

			K.box(f, "AnnexDeck", ax, -0.5, (zWall + z1) / 2, x1 - x0, 1, z1 - zWall, grout)
			K.box(f, "AnnexBelly", ax, -4.5, (zWall + z1) / 2, x1 - x0 - 3, 7, z1 - zWall - 1.5, C.hullOut)
			K.tiles(f, { x0 + T / 2, z0 + T / 2, x1 - T / 2, z1 - T / 2 }, 8, 8, 0.4, FLOOR, 0.24, tile, tile2, nil, name .. "Tile")

			local spec = { h = H, winBottom = 10, winTop = 17, winW = 7, winGap = 6, rail = 8, exterior = C.hullOut }
			local solid = { windows = false }
			local C0, C1 = T + 1, T + 1.4
			-- Dış (güney) duvarda küçük pencereler: yıldızlar ve lobinin ışığı
			K.wall(f, Vector2.new(x1 + T / 2, z1), Vector2.new(x0 - T / 2, z1), 1, K.merge(spec, { name = "AnnexS", inset0 = C1, inset1 = C1 }))
			-- Yan duvarlar düz (önlerine eşya geliyor) ve istasyon duvarının
			-- içinden başlıyor: uç yüzleri gizli kalıyor
			K.wall(f, Vector2.new(x1, z0 + 0.3), Vector2.new(x1, z1 - T / 2), 1, K.merge(spec, K.merge(solid, { name = "AnnexE" })))
			K.wall(f, Vector2.new(x0, z1 - T / 2), Vector2.new(x0, z0 + 0.3), 1, K.merge(spec, K.merge(solid, { name = "AnnexW" })))

			local ceilZ0 = z0 + 0.3
			K.box(f, "AnnexCeiling", ax, H + 0.6, (ceilZ0 + z1 - T / 2) / 2, x1 - x0 - T, 1.2, (z1 - T / 2) - ceilZ0, C.ceiling)
			K.box(f, "AnnexRoof", ax, H + 1.6, (ceilZ0 + z1 + T / 2 + 0.5) / 2, x1 - x0 + T + 1, 0.8, (z1 + T / 2 + 0.5) - ceilZ0, C.hullOut)
			for _, t in { 0.3, 0.7 } do
				local z = z0 + (z1 - z0) * t
				K.box(f, "LightFrame", ax, H - 0.15, z, 20.2, 0.3, 4.2, C.frame)
				local p = K.box(f, "LightPanel", ax, H - 0.35, z, 19, 0.2, 3, C.lamp, { emit = "Fixture" })
				K.surfaceLight(p, Enum.NormalId.Bottom, C.lamp, 30, 1.3, 140)
			end

			-- Kapının istasyon tarafında tabela: koridordan okunsun
			-- Kapı lentosunun üstünde ve önünde: lentoyla aynı düzleme düşmesin
			local signPos = Vector3.new(ax, M.ANNEX_DOOR_H + 4.8, z0 - T / 2 - 1.1)
			K.sign(f, "AnnexSign", CFrame.lookAt(signPos, signPos - Vector3.zAxis), 16, 3.2, label, accent)
			-- Kapıdan içeri uzanan şerit: "burası bir oda, gir"
			-- Karo kenarıyla hizalanmasın (aynı düzlemde yan yüzler titreşiyordu)
			K.hazard(f, ax, FLOOR + M.LIFT, z0 + T / 2 + 1.6, M.ANNEX_DOOR_W, 1.2, "x")
			return f
		end

		--[[
			Görev konsolu: `part` promptun bağlanacağı parça. Üstündeki sarı
			"!" işaretini istemci koyuyor (TaskGames), görev hazırsa görünüyor —
			Among Us'taki sarı görev işareti.
		]]
		local function taskConsole(part: BasePart, taskId: string)
			part.Name = "TaskConsole"
			part:SetAttribute("TaskId", taskId)
			part.CanQuery = true
		end

		-- ═══ STORAGE ══════════════════════════════════════════════════════════
		do
			local ax = M.ANNEX_X[1]
			local f = room("Storage", "STORAGE", ax, C.weapTile, C.weapTile2, C.weapGrout, C.orange)
			local x0, x1 = ax - M.ANNEX_W / 2, ax + M.ANNEX_W / 2

			-- Yakıt tankı: güney duvarının önünde, büyük turuncu silindir
			local tx, tz = ax - 10, z1 - 7
			K.vcyl(f, "FuelTankBase", tx, FLOOR + 0.5, tz, 1, 9, C.metalDark)
			K.vcyl(f, "FuelTank", tx, FLOOR + 5.5, tz, 9, 7.6, rgb(222, 96, 44))
			for _, y in { 2.6, 8.4 } do
				K.vcyl(f, "FuelBand", tx, FLOOR + y, tz, 0.6, 7.9, C.metalDark)
			end
			K.vcyl(f, "FuelCap", tx, FLOOR + 10.4, tz, 0.8, 3, C.metal)
			local label = K.box(f, "FuelLabel", tx, FLOOR + 5.5, tz - 3.9, 4, 1.6, 0.1, C.shadow)
			K.text(label, Enum.NormalId.Front, "FUEL", C.hazard)
			-- Pompa konsolu: tankın yanında, görevin kendisi
			local pump = K.box(f, "FuelPump", tx + 7, FLOOR + 2.4, tz, 3, 4.8, 3, C.metal)
			local screen = K.box(f, "FuelScreen", tx + 7, FLOOR + 3.6, tz - 1.55, 2.2, 1.6, 0.1, C.green, { emit = "Screen" })
			taskConsole(pump, "Fuel")
			K.light(screen, C.green, 8, 0.6)

			-- Kablo panosu: doğu duvarında
			-- Duvar korkuluğunun önünde (arka yüzü korkulukla aynı düzlemde kalmasın)
			local wx = x1 - T / 2 - 0.9
			local panel = K.box(f, "WiringPanel", wx, FLOOR + 6, cz, 0.8, 6, 7, C.shadow)
			K.box(f, "WiringFrame", wx + 0.15, FLOOR + 6, cz, 0.7, 6.8, 7.8, C.frameDark)
			local wireColors = { C.red, rgb(60, 110, 240), C.hazard, rgb(240, 90, 200) }
			for i, col in wireColors do
				local y = FLOOR + 3.8 + i * 1.1
				K.box(f, "WireStub", wx - 0.5, y, cz - 2.9, 0.3, 0.35, 1.2, col)
				K.box(f, "WireStub", wx - 0.5, y, cz + 2.9, 0.3, 0.35, 1.2, col)
			end
			taskConsole(panel, "Wiring")

			-- Depo süsü: kasalar ve variller batı duvarı boyunca
			local CRATE, STRAP = rgb(196, 160, 108), rgb(120, 92, 58)
			local function crate(cx: number, cy: number, czz: number, s: number, yaw: number)
				local cf = CFrame.new(cx, cy, czz) * CFrame.Angles(0, math.rad(yaw), 0)
				K.boxAt(f, "Crate", cf, Vector3.new(s, s, s), CRATE)
				for _, y in { -s * 0.32, s * 0.32 } do
					K.boxAt(f, "CrateStrap", cf * CFrame.new(0, y, 0), Vector3.new(s + 0.08, s * 0.12, s + 0.08), STRAP)
				end
			end
			crate(x0 + 4, FLOOR + 2.5, z1 - 6, 5, 0)
			crate(x0 + 4.2, FLOOR + 6.3, z1 - 6.2, 3.4, 15)
			crate(x0 + 4, FLOOR + 2, z1 - 12, 4, -10)
			for k = 0, 2 do
				K.vcyl(f, "Barrel", x0 + 4, FLOOR + 2.2, z0 + 8 + k * 4.2, 4.4, 3.4, rgb(70, 110, 170))
			end
		end

		-- ═══ LABORATORY ═══════════════════════════════════════════════════════
		do
			local ax = M.ANNEX_X[2]
			local f = room("Laboratory", "LABORATORY", ax, C.medTile, C.medTile2, C.medGrout, C.cyan)
			local x0, x1 = ax - M.ANNEX_W / 2, ax + M.ANNEX_W / 2

			-- Kart okuyucu masası: güney duvarının önünde
			local dz = z1 - 6
			K.box(f, "LabDesk", ax, FLOOR + 1.8, dz, 12, 3.6, 4, C.frame)
			K.box(f, "LabDeskTop", ax, FLOOR + 3.7, dz, 12.6, 0.3, 4.6, C.metalDark)
			local reader = K.box(f, "CardReader", ax + 2, FLOOR + 4.4, dz - 0.4, 3.2, 1.1, 2, C.shadow)
			K.box(f, "CardSlot", ax + 2, FLOOR + 5, dz - 0.4, 2.8, 0.1, 0.25, C.green, { emit = "Indicator" })
			taskConsole(reader, "Card")
			-- Masadaki ekran
			K.box(f, "LabMonitor", ax - 3, FLOOR + 5.4, dz + 0.8, 4, 2.6, 0.3, C.shadow)
			local ms = K.box(f, "LabMonitorScreen", ax - 3, FLOOR + 5.4, dz + 0.62, 3.6, 2.2, 0.06, C.cyan, { emit = "Screen" })
			K.light(ms, C.cyan, 8, 0.5)

			-- Numune tüpleri: batı duvarı boyunca, cam içinde yeşil sıvı
			for k = 0, 2 do
				local tz = z0 + 9 + k * 9
				local tx = x0 + 4
				K.vcyl(f, "TubeBase", tx, FLOOR + 0.6, tz, 1.2, 5, C.metalDark)
				-- Sıvı opak, cam çok saydam: yoksa cam sıvıyı mavinin altında boğuyordu
				K.vcyl(f, "TubeLiquid", tx, FLOOR + 4.2, tz, 6, 3.2, rgb(110, 240, 140), { emit = "Screen" })
				K.vcyl(f, "TubeGlass", tx, FLOOR + 4.6, tz, 7.2, 4, C.glass, { material = Enum.Material.Glass, transparency = 0.82 })
				K.vcyl(f, "TubeCap", tx, FLOOR + 8.5, tz, 0.6, 4.4, C.metal)
			end
			-- Doğu duvarında bilgi panosu
			local board = K.box(f, "LabBoard", x1 - T / 2 - 0.3, FLOOR + 7, cz, 0.4, 5, 9, C.shadow)
			K.text(board, Enum.NormalId.Left, "SPECIMEN LOG", C.cyan)
		end
	end,
}
