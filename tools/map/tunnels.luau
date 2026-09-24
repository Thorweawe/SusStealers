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
]]

return {
	folders = { "Tunnels" },

	build = function(K: any)
		local M, C = K.M, K.C
		local root = K.folder("Tunnels")

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

			-- ─── Zemin, duvar, tavan ─────────────────────────────────────────
			K.box(f, "TunnelFloor", x, floorTop - 0.1, midZ, W, 0.2, len, C.metalDark, { material = Enum.Material.DiamondPlate })
			for _, s in { -1, 1 } do
				-- Duvar: karo hizasının hemen altına kadar (güverte üst yüzüyle aynı düzlemde değil)
				local wallTop = -0.05
				local wy = (floorTop + wallTop) / 2
				K.box(f, "TunnelWall", x + s * (hw - 0.22), wy, midZ, 0.4, wallTop - floorTop, len, C.wallLow)
				-- Alt bant ve acil şerit
				K.box(f, "TunnelKick", x + s * (inner - 0.15), floorTop + 0.9, midZ, 0.3, 1.8, len - 0.4, C.wallKick)
				K.box(f, "TunnelStrip", x + s * (inner - 0.06), floorTop + 2.1, midZ, 0.12, 0.25, len - 0.8, C.red, { emit = "Indicator" })
			end

			-- Tavan: iki rampa arasında, güverte alt yüzünün biraz altında
			local ceilZ0, ceilZ1 = zS + ramp, zN - ramp
			local ceilMid, ceilLen = (ceilZ0 + ceilZ1) / 2, ceilZ1 - ceilZ0
			K.box(f, "TunnelCeiling", x, -1.35, ceilMid, 2 * inner, 0.3, ceilLen, C.ceiling)

			-- Tavan ışıkları: her 20 stud
			local count = math.floor(ceilLen / 20)
			for k = 0, count do
				local z = ceilZ0 + 6 + k * ((ceilLen - 12) / math.max(1, count))
				local lamp = K.box(f, "TunnelLamp", x, -1.62, z, 3.2, 0.24, 1.2, C.lamp, { emit = "Fixture" })
				K.light(lamp, K.rgb(255, 236, 200), 20, 1.1)
			end

			-- Borular: üst köşelerde, rampa ağızları arasında
			for _, s in { -1, 1 } do
				K.cyl(f, "TunnelPipe", CFrame.new(x + s * (inner - 0.6), -2.6, ceilMid) * CFrame.Angles(0, math.rad(90), 0), ceilLen, 0.8, C.metal)
			end
			K.cyl(f, "TunnelPipe", CFrame.new(x - (inner - 1.6), -2.2, ceilMid) * CFrame.Angles(0, math.rad(90), 0), ceilLen, 0.45, C.orange)

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
			K.sign(f, "TunnelSign", southCf, 12, 2.6, "MAINTENANCE", C.hazard)
			K.sign(f, "TunnelSign", northCf, 12, 2.6, "MAINTENANCE", C.hazard)
		end
	end,
}
