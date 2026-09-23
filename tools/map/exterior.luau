--!strict
--[[
	Gemi dışı: pencerelerden görünenler.
	  Motorlar   — batıda iki dev motor gövdesi, arkalarında mavi alev
	               (Skeld'in iticileri). Batı pencerelerinden görünüyor.
	  Burun      — doğuda, kokpit camının altından uzanan sivri pruva
	  Kanatlar   — kuzeyde iki kobalt mavisi yüzgeç
	  Uzay       — uzakta bir gezegen ve uydusu; pencerelerin önünden yavaşça
	               geçen asteroitler ve fırlatılmış bir mürettebat (DecorFX
	               DriftSpeed/DriftRange ile kaydırıyor)
]]

return {
	folders = { "Exterior", "Drifters" },

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
				seg("NacelleBand", -x0 + b, -x0 + b + 3, 39.6, rgb(96, 110, 122), { collide = false })
			end
			seg("NacelleStripe", -x0 + 24, -x0 + 28, 39.4, cobalt, { collide = false })
			seg("NozzleRing", -x0 + 70, -x0 + 76, 32, rgb(70, 82, 94))
			seg("NozzleThroat", -x0 + 76, -x0 + 77, 26, C.shadow)
			-- Alev: iç içe iki parlak silindir + küre; DecorFX nabız veriyor
			local flame = seg("Flame", -x0 + 77, -x0 + 91, 24, rgb(90, 190, 255), { emit = "Fixture", transparency = 0.25, collide = false })
			flame.CastShadow = false
			flame:SetAttribute("PulsePeriod", 0.5)
			local inner = seg("FlameCore", -x0 + 77, -x0 + 101, 14, rgb(210, 245, 255), { emit = "Fixture", transparency = 0.1, collide = false })
			inner.CastShadow = false
			local tip = K.ball(f, "FlameTip", x0 - 101, cy, z, 14, rgb(150, 220, 255), { emit = "Fixture", transparency = 0.35, collide = false })
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
			K.box(f, "ProwStripe", xw + 40, 8.6, czn, 60, 0.2, 3, C.hazard, { collide = false })
			local nav = K.ball(f, "NoseLight", xw + L - 8, 9.5, czn, 3, C.red, { emit = "Fixture" })
			nav:SetAttribute("PulsePeriod", 1.8)
		end

		-- ─── Kanatlar (kuzey) ───────────────────────────────────────────────
		do
			local f = K.folder("Wings", ex)
			for _, x in { 40, 320 } do
				local w = Instance.new("WedgePart")
				w.Name = "Fin"
				w.Anchored = true
				w.CanQuery = false
				w.CanTouch = false
				w.Material = Enum.Material.SmoothPlastic
				w.Color = cobalt
				w.Size = Vector3.new(4, 30, 60)
				-- Eğim kuzeye doğru alçalıyor
				w.CFrame = CFrame.new(x, 10, M.Z0 - T / 2 - 30) * CFrame.Angles(0, math.rad(180), 0)
				w.Parent = f
				K.box(f, "FinTip", x, -4.2, M.Z0 - T / 2 - 58, 4.4, 1.6, 4, C.red, { emit = "Indicator" })
			end
		end

		-- ─── Uzay ───────────────────────────────────────────────────────────
		do
			local f = K.folder("Space", ex)
			-- Gezegen: kuzeyde, uzakta; cam şeritten ve kuzey pencerelerinden görünüyor
			local planet = K.ball(f, "Planet", M.centerX - 300, 260, M.Z0 - 1500, 700, rgb(226, 150, 96), { collide = false })
			planet.CastShadow = false
			K.ball(f, "PlanetBand", M.centerX - 300, 300, M.Z0 - 1497, 690, rgb(236, 180, 120), { collide = false }).CastShadow = false
			local moon = K.ball(f, "Moon", M.centerX + 420, 330, M.Z0 - 1100, 140, rgb(196, 204, 214), { collide = false })
			moon.CastShadow = false
			-- Güneyde ikinci gezegen: lobi pencerelerinden
			local p2 = K.ball(f, "Planet2", M.centerX + 700, 120, M.LOBBY_Z1 + 1300, 520, rgb(90, 140, 230), { collide = false })
			p2.CastShadow = false
		end

		-- ─── Süzülenler ─────────────────────────────────────────────────────
		local drift = K.folder("Drifters")
		local function asteroid(x: number, y: number, z: number, s: number, speed: number, range: number)
			local m = Instance.new("Model")
			m.Name = "Asteroid"
			m.Parent = drift
			local core = K.ball(m, "Rock", x, y, z, 6 * s, rgb(120, 112, 104), { collide = false })
			K.ball(m, "Rock", x + 2.4 * s, y + 1.2 * s, z - 1 * s, 4 * s, rgb(104, 96, 90), { collide = false })
			K.ball(m, "Rock", x - 2 * s, y - 1.5 * s, z + 1.4 * s, 3.4 * s, rgb(136, 128, 118), { collide = false })
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
	end,
}
