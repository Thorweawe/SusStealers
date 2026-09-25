--!strict
--[[
	Bakım tünelleri: iki üs sırasının arkasından zemine inen rampalar ve
	sıraların + omurga koridorunun altından geçen tünel (ölçüler kit.luau,
	M.TUNNEL_*). Zemindeki açıklıklar ve gövde oyukları station.luau'da;
	burası içini döşüyor.

	  Rampa     — kama (WedgePart), üst ucu karo hizasında, dibi tünel
	              zemininde. Girişi duvar tarafında; üç yanı korkuluklu.
	  Tünel     — ızgara zemin, iki yanda panel duvar, tavan paneli, tavan
	              ışıkları, zeminde kırmızı acil şerit, üst köşelerde borular.
	  Tabela    — rampa girişinin üstünde duvarda "MAINTENANCE".

	Karanlık ve dar: kovalamacada görüş hattı kesilsin diye. Yine de yolu
	kaybettirmesin: iki uçta yeşil çıkış ışığı.

	Yeraltı odası: tünel omurga koridorunun altında bir odaya açılıyor
	(K.underRooms). Batıda SECURITY, doğuda ADMIN. Burası odanın kabuğunu
	(zemin, duvar, tavan, ışık) kuruyor, içini security.luau ve admin.luau
	dolduruyor. Tünelin duvarları, tavanı ve boruları oda boyunca kesik.
]]

return {
	folders = { "Tunnels", "UnderRooms" },

	build = function(K: any)
		local M, C = K.M, K.C
		local root = K.folder("Tunnels")
		local roomsRoot = K.folder("UnderRooms")
		local underRooms = K.underRooms()

		local W = M.TUNNEL_W
		local hw = W / 2
		-- Panel iç yüzü. Dış yüzü oyuğun kenarından 0.02 içeride: güverte
		-- kesiminin yan yüzüyle aynı düzlemde olmasın
		local inner = hw - 0.42
		local floorTop = M.TUNNEL_FLOOR
		local deckTop = M.TILE_TOP
		local ramp = M.TUNNEL_RAMP
		local rise = deckTop - floorTop
		local slope = math.atan(rise / ramp)

		local function wedge(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3): WedgePart
			local p = Instance.new("WedgePart")
			p.Name = name
			p.Size = size
			p.CFrame = cf
			p.Anchored = true
			p.CanCollide = true
			p.CanQuery = true
			p.CanTouch = false
			p.Material = Enum.Material.DiamondPlate
			p.Color = color
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Parent = parent
			return p
		end

		for index, x in M.TUNNEL_X do
			local f = K.folder("Tunnel" .. index, root)
			local zS, zN = M.TUNNEL_S0, M.TUNNEL_N1
			local midZ = (zS + zN) / 2
			local len = zN - zS
			local room = underRooms[index]
			local rz0, rz1 = room[2], room[4]

			--[[ [a, b] aralığının oda dışında kalan parçaları (tünel odada kesik). ]]
			local function spans(a: number, b: number): { { number } }
				local out = {}
				if rz0 > a then
					table.insert(out, { a, math.min(b, rz0) })
				end
				if rz1 < b then
					table.insert(out, { math.max(a, rz1), b })
				end
				return out
			end

			-- ─── Zemin, duvar, tavan ─────────────────────────────────────────
			K.box(f, "TunnelFloor", x, floorTop - 0.1, midZ, W, 0.2, len, C.metalDark, { material = Enum.Material.DiamondPlate })
			for _, s in { -1, 1 } do
				-- Duvar: karo hizasının hemen altına kadar (güverte üst yüzüyle aynı düzlemde değil)
				local wallTop = -0.05
				local wy = (floorTop + wallTop) / 2
				for _, sp in spans(zS, zN) do
					local a, b = sp[1], sp[2]
					K.box(f, "TunnelWall", x + s * (hw - 0.22), wy, (a + b) / 2, 0.4, wallTop - floorTop, b - a, C.wallLow)
					-- Alt bant ve acil şerit
					K.box(f, "TunnelKick", x + s * (inner - 0.15), floorTop + 0.9, (a + b) / 2, 0.3, 1.8, b - a - 0.4, C.wallKick)
					K.box(f, "TunnelStrip", x + s * (inner - 0.06), floorTop + 2.1, (a + b) / 2, 0.12, 0.25, b - a - 0.8, C.red, { emit = "Indicator" })
				end
			end

			-- Tavan: iki rampa arasında, güverte alt yüzünün biraz altında
			local ceilZ0, ceilZ1 = zS + ramp, zN - ramp
			for _, sp in spans(ceilZ0, ceilZ1) do
				local a, b = sp[1], sp[2]
				K.box(f, "TunnelCeiling", x, -1.35, (a + b) / 2, 2 * inner, 0.3, b - a, C.ceiling)

				-- Tavan ışıkları: her 20 stud
				local segLen = b - a
				local count = math.floor(segLen / 20)
				for k = 0, count do
					local z = a + 6 + k * ((segLen - 12) / math.max(1, count))
					local lamp = K.box(f, "TunnelLamp", x, -1.62, z, 3.2, 0.24, 1.2, C.lamp, { emit = "Fixture" })
					K.light(lamp, K.rgb(255, 236, 200), 20, 1.1)
				end

				-- Borular: üst köşelerde, rampa ağızları ile oda arasında
				for _, s in { -1, 1 } do
					K.cyl(f, "TunnelPipe", CFrame.new(x + s * (inner - 0.6), -2.6, (a + b) / 2) * CFrame.Angles(0, math.rad(90), 0), segLen, 0.8, C.metal)
				end
				K.cyl(f, "TunnelPipe", CFrame.new(x - (inner - 1.6), -2.2, (a + b) / 2) * CFrame.Angles(0, math.rad(90), 0), segLen, 0.45, C.orange)
			end

			-- ─── Yeraltı odası: kabuk ─────────────────────────────────────────
			do
				local name = M.UNDER_ROOM_NAMES[index] or ("Room" .. index)
				local rf = K.folder(name, roomsRoot)
				local x0, x1 = room[1], room[3]
				local rmid = (rz0 + rz1) / 2
				local depth = rz1 - rz0
				local floorTint = if name == "Security" then K.rgb(92, 116, 104) else K.rgb(96, 110, 132)
				local wallTint = if name == "Security" then K.rgb(78, 104, 96) else K.rgb(80, 100, 124)
				local wallTop = -1.05
				local wy = (floorTop + wallTop) / 2
				local wh = wallTop - floorTop

				-- Zemin: tünel şeridinin iki yanı (tünel zemini ortada devam ediyor)
				for _, s in { -1, 1 } do
					local a = if s < 0 then x0 else x + hw
					local b = if s < 0 then x - hw else x1
					K.box(rf, "RoomFloor", (a + b) / 2, floorTop - 0.1, rmid, b - a, 0.2, depth, floorTint)
				end
				-- Doğu-batı duvarları
				for _, s in { -1, 1 } do
					local wx = if s < 0 then x0 + 0.2 else x1 - 0.2
					K.box(rf, "RoomWall", wx, wy, rmid, 0.4, wh, depth, wallTint)
					K.box(rf, "RoomKick", wx - s * 0.3, floorTop + 0.6, rmid, 0.2, 1.2, depth - 0.8, C.wallKick)
				end
				-- Kuzey-güney duvarları: ortada tünelin ağzı açık
				for _, zs in { -1, 1 } do
					local wz = if zs < 0 then rz0 + 0.2 else rz1 - 0.2
					for _, s in { -1, 1 } do
						local a = if s < 0 then x0 + 0.4 else x + hw
						local b = if s < 0 then x - hw else x1 - 0.4
						K.box(rf, "RoomWall", (a + b) / 2, wy, wz, b - a, wh, 0.4, wallTint)
						K.box(rf, "RoomKick", (a + b) / 2, floorTop + 0.6, wz - zs * 0.3, b - a - 0.2, 1.2, 0.2, C.wallKick)
					end
					-- Ağzın iki yanında kapı pervazı
					for _, s in { -1, 1 } do
						-- Arka yüzü duvarın içinde: süpürgelik ve tavan kenarıyla aynı düzlemde kalmasın
					-- Alt ucu zeminin içinde, üst ucu tavanın içinde: duvarla aynı düzlemde bitmesin
					K.box(rf, "RoomJamb", x + s * (hw + 0.35), wy - 0.25, wz - zs * 0.35, 1, wh - 0.1, 0.7, C.frame)
					end
				end
				-- Tavan ve ışık panelleri
				K.box(rf, "RoomCeiling", (x0 + x1) / 2, -1.35, rmid, x1 - x0 - 0.8, 0.3, depth - 0.8, C.ceiling)
				for _, px in { x0 + (x - hw - x0) / 2, x + hw + (x1 - x - hw) / 2 } do
					local panel = K.box(rf, "RoomLight", px, -1.62, rmid, 8, 0.24, 3, C.lamp, { emit = "Fixture" })
					K.surfaceLight(panel, Enum.NormalId.Bottom, C.lamp, 22, 1.2, 140)
				end
				local mid = K.box(rf, "RoomLight", x, -1.62, rmid, 3.2, 0.24, 6, C.lamp, { emit = "Fixture" })
				K.surfaceLight(mid, Enum.NormalId.Bottom, C.lamp, 18, 1, 140)
			end

			-- ─── Rampalar ─────────────────────────────────────────────────────
			--[[
				Kama yerel +Z'de yüksek. Güneyde üst uç duvar tarafında (-z),
				kuzeyde de duvar tarafında (+z): güneydeki 180° çevriliyor.
			]]
			local size = Vector3.new(2 * inner, rise, ramp)
			local cy = floorTop + rise / 2
			wedge(f, "TunnelRamp", CFrame.new(x, cy, zS + ramp / 2) * CFrame.Angles(0, math.pi, 0), size, C.metal)
			wedge(f, "TunnelRamp", CFrame.new(x, cy, zN - ramp / 2), size, C.metal)

			-- Basamak çizgileri (yürünür, ince)
			for _, ends in { { zS, 1 }, { zN, -1 } } do
				local top, dir = ends[1], ends[2]
				local steps = math.floor(ramp / 2.6)
				for k = 1, steps - 1 do
					local along = k * (ramp / steps)
					local y = deckTop - along * (rise / ramp)
					local cf = CFrame.new(x, y + 0.06, top + dir * along) * CFrame.Angles(dir * slope, 0, 0)
					K.boxAt(f, "TunnelTread", cf, Vector3.new(2 * inner - 0.6, 0.1, 0.35), C.hazardDark)
				end
			end

			-- ─── Açıklık kenarı: korkuluk ve uyarı şeridi ────────────────────
			for _, ends in { { zS, 1 }, { zN, -1 } } do
				local top, dir = ends[1], ends[2]
				local far = top + dir * ramp
				local mid = top + dir * ramp / 2
				local railY = deckTop

				-- Uzun kenarlar
				for _, s in { -1, 1 } do
					local rx = x + s * (hw + 0.3)
					K.hazard(f, x + s * (hw + 0.55), deckTop + 0.06, mid, ramp, 0.9, "z", 2.4)
					for k = 0, 4 do
						K.box(f, "RailPost", rx, railY + 1.75, top + dir * (0.4 + k * (ramp - 0.8) / 4), 0.35, 3.5, 0.35, C.metal)
					end
					K.box(f, "Rail", rx, railY + 3.4, mid, 0.3, 0.3, ramp, C.hazard, { collide = true })
					K.box(f, "Rail", rx, railY + 1.9, mid, 0.25, 0.25, ramp, C.metal, { collide = true })
				end
				-- Uzak uç (tünel ağzının üstü)
				local fz = far + dir * 0.3
				K.hazard(f, x, deckTop + 0.06, far + dir * 0.55, W + 1.8, 0.9, "x", 2.4)
				for k = -1, 1 do
					K.box(f, "RailPost", x + k * hw, railY + 1.75, fz, 0.35, 3.5, 0.35, C.metal)
				end
				K.box(f, "Rail", x, railY + 3.4, fz, W + 0.6, 0.3, 0.3, C.hazard, { collide = true })
				K.box(f, "Rail", x, railY + 1.9, fz, W + 0.6, 0.25, 0.25, C.metal, { collide = true })

				-- Giriş: zeminde uyarı şeridi
				K.hazard(f, x, deckTop + 0.06, top - dir * 0.55, W, 0.9, "x", 2.4)

				-- Tünel içinde çıkış ışığı: rampanın dibinde, tavanda
				local exit = K.box(f, "TunnelExitLamp", x, -1.62, far + dir * 1.5, 2.4, 0.3, 0.6, C.green, { emit = "Indicator" })
				K.light(exit, C.green, 12, 0.8)
			end

			-- ─── Tabelalar: rampa girişinin üstünde, duvarda ─────────────────
			-- Merkezden dışa 2.5 kaydırılmış: kuzey duvarda ek oda kapısının çerçevesine yapışmasın
			local signY = 8
			local sx = x + (if x < M.centerX then -2.5 else 2.5)
			local southCf = CFrame.lookAt(Vector3.new(sx, signY, M.IZ0 + 0.6), Vector3.new(sx, signY, M.IZ0 + 10))
			local northCf = CFrame.lookAt(Vector3.new(sx, signY, M.IZ1 - 0.6), Vector3.new(sx, signY, M.IZ1 - 10))
			-- Rampa girişinde odanın adı: aşağıda ne olduğu yukarıdan okunsun
			local label = string.upper(M.UNDER_ROOM_NAMES[index] or "MAINTENANCE")
			local accent = if index == 1 then C.green else C.cyan
			K.sign(f, "TunnelSign", southCf, 12, 2.6, label, accent)
			K.sign(f, "TunnelSign", northCf, 12, 2.6, label, accent)
		end
	end,
}
