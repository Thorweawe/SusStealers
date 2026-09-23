--!strict
--[[
	İstasyon gövdesi: zemin (koridor karoları + oda zeminleri), dört duvar
	(Skeld pencereleri, lobiye açılan kapı), tavan (ışık panelleri, omurga
	üstünde yıldızlara bakan cam şerit) ve dış gövde.
]]

return {
	folders = { "Floor", "Hull", "Ceiling" },

	build = function(K: any)
		local M, C = K.M, K.C
		local T = M.WALL_T

		-- ─── Zemin ──────────────────────────────────────────────────────────
		local floor = K.folder("Floor")

		K.box(floor, "Deck", M.centerX, -0.5, M.centerZ, M.X1 - M.X0 + T, 1, M.Z1 - M.Z0 + T, C.hallGrout)

		local roomRects = {}
		for i = 1, M.PLOT_COUNT do
			table.insert(roomRects, K.roomRect(i))
		end

		local holes = table.clone(roomRects)
		table.insert(holes, M.REACTOR_RECT)
		table.insert(holes, M.NAV_RECT)

		--[[
			Koridor karoları. 12'lik kare; odaların, reaktörün ve kokpitin
			olduğu yerde kesiliyor — altında gizli karo kalmıyor.
		]]
		local hall = K.folder("Hall", floor)
		K.tiles(hall, { M.IX0, M.IZ0, M.IX1, M.IZ1 }, 12, 12, 0.5, M.TILE_TOP, 0.24,
			C.hallTile, C.hallTile2, holes, "HallTile")

		--[[
			Oda zeminleri: her odanın kendi rengi (Skeld haritasındaki gibi:
			Reaktör mor, Güvenlik yeşil, Elektrik zeytin...). Altta oluk
			renginde ince levha, üstünde karolar; üssün kendi zemini (Base)
			karoların üstünde durduğu için orası boş bırakılıyor.
		]]
		local rooms = K.folder("Rooms", floor)
		for i = 1, M.PLOT_COUNT do
			local r = roomRects[i]
			local th = K.theme(i)
			local rf = K.folder("Room" .. i, rooms)
			K.box(rf, "RoomBase", (r[1] + r[3]) / 2, 0.06, (r[2] + r[4]) / 2, r[3] - r[1], 0.12, r[4] - r[2], th.grout)
			K.tiles(rf, { r[1] + 1, r[2], r[3] - 1, r[4] }, 10, 10, 0.45, M.TILE_TOP, 0.24,
				th.tile, th.tile2, { K.plotRect(i, 0.2) }, "RoomTile")
		end

		-- ─── Duvarlar ───────────────────────────────────────────────────────
		local hull = K.folder("Hull")

		local spec = {
			h = M.WALL_H, winBottom = 20, winTop = 40, winW = 16, winGap = 12,
			exterior = C.hullOut,
		}

		-- Arka (kuzey) duvar: +x yönünde, iç taraf +z
		K.wall(hull, Vector2.new(M.X0 - T / 2, M.Z0), Vector2.new(M.X1 + T / 2, M.Z0), 1,
			K.merge(spec, { name = "North", inset0 = T + 0.6, inset1 = T + 0.6 }))

		-- Ön (güney) duvar: -x yönünde, lobi kapısı ortada
		local a = Vector2.new(M.X1 + T / 2, M.Z1)
		local b = Vector2.new(M.X0 - T / 2, M.Z1)
		local u0 = (M.X1 + T / 2) - (M.centerX + M.GATE_W / 2)
		local u1 = (M.X1 + T / 2) - (M.centerX - M.GATE_W / 2)
		K.wall(hull, a, b, 1, K.merge(spec, {
			name = "South", inset0 = T + 0.6, inset1 = T + 0.6,
			doors = { { u0 = u0, u1 = u1, h = M.GATE_H } },
		}))
		K.door(hull, a, b, 1, u0, u1, M.GATE_H)

		-- Batı: reaktörün arkası, pencere kuşağı devam ediyor
		K.wall(hull, Vector2.new(M.X0, M.Z1 - T / 2), Vector2.new(M.X0, M.Z0 + T / 2), 1,
			K.merge(spec, { name = "West" }))

		--[[
			Doğu: kokpitin önünde büyük ön cam. Normal pencere dizisi yerine
			geniş bir açıklık; camı ve çerçevesini "Landmarks" kuruyor.
		]]
		local eastA = Vector2.new(M.X1, M.Z0 + T / 2)
		local nav = M.NAV_RECT
		local wu0 = (nav[2] - 6) - eastA.Y
		local wu1 = (nav[4] + 6) - eastA.Y
		K.wall(hull, eastA, Vector2.new(M.X1, M.Z1 - T / 2), 1, K.merge(spec, {
			name = "East",
			openings = { { u0 = wu0, u1 = wu1, y0 = 10, y1 = 42 } },
		}))

		-- Dış gövde: güvertenin altında kademeli daralan karın
		local W = M.X1 - M.X0 + T
		local D = M.Z1 - M.Z0 + T
		K.box(hull, "Belly", M.centerX, -5, M.centerZ, W + 1.6, 8, D + 1.6, C.hullOut)
		K.box(hull, "BellyMid", M.centerX, -12, M.centerZ, W - 24, 6, D - 24, C.wallKick)
		K.box(hull, "Keel", M.centerX, -17, M.centerZ, W - 80, 4, D - 70, C.hullOut)
		-- Karın çizgisi: yandan bakınca gövde kalınlığı okunsun
		K.box(hull, "BellyStripe", M.centerX, -2.2, M.Z1 + T / 2 + 0.9, W + 1.8, 1.2, 0.4, C.hazard, { collide = false })

		--[[
			Duvar tepesinde dış korniş. Alt yüzü 51.8'de: tavan levhasının alt
			yüzüyle (52.0) aynı düzlemde olmasın. Yan kornişler köşede ön/arka
			kornişin BİTTİĞİ yerden başlıyor, üst üste binmiyor.
		]]
		local CT = T + 1.4
		for _, z in { M.Z0, M.Z1 } do
			K.box(hull, "Cornice", M.centerX, M.WALL_H + 0.6, z, W + 2, 1.6, CT, C.frameDark)
		end
		for _, x in { M.X0, M.X1 } do
			K.box(hull, "Cornice", x, M.WALL_H + 0.6, M.centerZ, CT, 1.6, (M.Z1 - M.Z0) - CT - 0.04, C.frameDark)
		end

		-- ─── Tavan ──────────────────────────────────────────────────────────
		local ceil = K.folder("Ceiling")
		local CY = M.WALL_H + 0.6

		-- Omurganın üstünde yıldızlara bakan cam şerit
		local sky = { -30, M.SPINE_Z0 + 8, 390, M.SPINE_Z1 - 8 }
		local slabArea = { M.IX0, M.IZ0, M.IX1, M.IZ1 }
		for _, r in K.rectSubtract(slabArea, sky) do
			K.box(ceil, "CeilingSlab", (r[1] + r[3]) / 2, CY, (r[2] + r[4]) / 2, r[3] - r[1], 1.2, r[4] - r[2], C.ceiling)
		end

		K.box(ceil, "Skylight", (sky[1] + sky[3]) / 2, CY + 0.2, (sky[2] + sky[4]) / 2, sky[3] - sky[1], 0.4, sky[4] - sky[2], C.glass,
			{ material = Enum.Material.Glass, transparency = 0.55, collide = true })
		-- Cam şeridin kirişleri
		local beams = math.floor((sky[3] - sky[1]) / 30)
		for k = 0, beams do
			local x = sky[1] + k * (sky[3] - sky[1]) / beams
			K.box(ceil, "SkyBeam", x, CY - 0.7, (sky[2] + sky[4]) / 2, 1.4, 1.2, sky[4] - sky[2] + 1.4, C.frame, { collide = false })
		end
		for _, z in { sky[2], sky[4] } do
			K.box(ceil, "SkyRail", (sky[1] + sky[3]) / 2, CY - 0.7, z, sky[3] - sky[1] + 1.4, 1.2, 1.4, C.frame, { collide = false })
		end

		--[[
			Işık panelleri: Among Us 3D'deki gibi tavana gömme geniş beyaz
			paneller. Işığı SurfaceLight aşağı yayıyor; nokta ışığa göre çok
			daha az kaynakla bütün odayı eşit aydınlatıyor.
		]]
		local function panel(x: number, z: number, w: number, d: number, range: number, bright: number)
			K.box(ceil, "LightFrame", x, CY - 0.75, z, w + 1.2, 0.3, d + 1.2, C.frame, { collide = false })
			local p = K.box(ceil, "LightPanel", x, CY - 0.95, z, w, 0.2, d, C.lamp, { emit = "Fixture" })
			K.surfaceLight(p, Enum.NormalId.Bottom, C.lamp, range, bright, 140)
		end

		for i = 1, M.PLOT_COUNT do
			local r = K.roomRect(i)
			local cx = (r[1] + r[3]) / 2
			local cz = (r[2] + r[4]) / 2
			panel(cx - 20, cz, 14, 5, 58, 1.6)
			panel(cx + 20, cz, 14, 5, 58, 1.6)
		end
		-- Omurga: cam şeridin iki yanında
		for k = 0, 5 do
			local x = M.IX0 + 40 + k * (M.IX1 - M.IX0 - 80) / 5
			for _, z in { M.SPINE_Z0 + 3, M.SPINE_Z1 - 3 } do
				panel(x, z, 12, 3, 50, 1.3)
			end
		end
	end,
}
