--!strict
--[[
	Oda eşyaları: her üs bölgesinin arka duvarına, o Skeld odasının simge
	eşyaları. Oyun alanına girmiyorlar — hepsi arka duvardan en fazla 18
	stud içeride ve oda genişliğinin içinde (üssün arkasında ~20 stud
	yürüme payı kalıyor).

	Yerel çerçeve: orijin arka duvarın iç yüzü, x duvar boyunca, y yerden
	yukarı, d duvardan odaya doğru uzaklık.
]]

return {
	folders = { "RoomProps" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local root = K.folder("RoomProps")
		local FLOOR = M.TILE_TOP

		for i = 1, M.PLOT_COUNT do
			local o = K.plotOrigin(i)
			local facing = K.plotFacing(i)
			local th = K.theme(i)
			local zWall = if facing > 0 then M.IZ0 else M.IZ1
			local base = CFrame.lookAt(Vector3.new(o.X, FLOOR, zWall), Vector3.new(o.X, FLOOR, zWall + facing))
			local f = K.folder("Room" .. i, root)

			local function R(x: number, y: number, d: number): CFrame
				return base * CFrame.new(x, y, -d)
			end
			-- Yerel kutu: (x, y, d) merkez, (sx, sy, sd) boyut
			local function bx(name: string, x: number, y: number, d: number, sx: number, sy: number, sd: number, color: Color3, extra: { [string]: any }?): Part
				-- Duvara yaslanan eşya duvarın 0.1 içine gömülüyor: arka yüzü
				-- süpürgelik/derz çıtalarıyla aynı düzlemde kalmasın
				if math.abs(d - sd / 2) < 0.05 then
					sd += 0.2
					d -= 0.1
				end
				return K.boxAt(f, name, R(x, y, d), Vector3.new(sx, sy, sd), color, extra)
			end
			-- Dikey silindir
			local function vc(name: string, x: number, y: number, d: number, h: number, dia: number, color: Color3, extra: { [string]: any }?): Part
				return K.boxAt(f, name, R(x, y, d) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(h, dia, dia), color,
					K.merge({ shape = Enum.PartType.Cylinder }, extra))
			end
			-- Duvar boyunca (yerel X) yatan silindir
			local function xc(name: string, x: number, y: number, d: number, len: number, dia: number, color: Color3, extra: { [string]: any }?): Part
				return K.boxAt(f, name, R(x, y, d), Vector3.new(len, dia, dia), color, K.merge({ shape = Enum.PartType.Cylinder }, extra))
			end
			-- Odaya bakan (yerel Z ekseninde) disk
			local function zc(name: string, x: number, y: number, d: number, len: number, dia: number, color: Color3, extra: { [string]: any }?): Part
				return K.boxAt(f, name, R(x, y, d) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(len, dia, dia), color,
					K.merge({ shape = Enum.PartType.Cylinder }, extra))
			end
			local function screen(name: string, x: number, y: number, d: number, w: number, h: number, glow: Color3)
				bx(name .. "Bezel", x, y, d, w + 0.8, h + 0.8, 0.6, C.shadow, { collide = false })
				bx(name, x, y, d + 0.35, w, h, 0.1, glow, { emit = "Screen" })
			end
			local function chair(x: number, d: number, color: Color3)
				vc("ChairPost", x, 1.2, d, 2.4, 0.9, C.metalDark)
				vc("ChairFoot", x, 0.2, d, 0.4, 3.2, C.metalDark, { collide = false })
				bx("ChairSeat", x, 2.7, d, 3.6, 0.8, 3.6, color)
				bx("ChairBack", x, 5, d + 1.6, 3.6, 4, 0.7, color)
			end
			local function label(part: Part, text: string, color: Color3)
				K.text(part, Enum.NormalId.Front, text, color, { h = 0.7, y = 0.15 })
			end

			-- ═══ ENGINE ═══════════════════════════════════════════════════════
			if th.id == "Engine" then
				local red = rgb(186, 74, 74)
				for _, x in { -13, 13 } do
					bx("Cradle", x, 2.5, 9, 4, 5, 10, C.metalDark)
				end
				-- Duvara bağlanan kanal
				bx("Duct", 0, 11, 0.9, 14, 11, 1.8, C.metal)
				local body = xc("EngineBody", 0, 12, 9, 40, 15, red)
				body.CastShadow = true
				for _, x in { -16, -8, 8, 16 } do
					xc("EngineBand", x, 12, 9, 2, 15.8, C.metal, { collide = false })
				end
				for _, s in { -1, 1 } do
					xc("EngineCap", s * 21.5, 12, 9, 3, 12, C.metal)
					xc("Nozzle", s * 24, 12, 9, 2.4, 8.5, C.metalDark)
					xc("NozzleGlow", s * 25.3, 12, 9, 0.3, 6.5, C.cyan, { emit = "Screen" })
				end
				-- Motor üstünde ızgaralı kapak ve tavana çıkan turuncu borular
				bx("TopVent", 0, 20, 9, 12, 1.2, 6, C.metal)
				for k = -2, 2 do
					bx("VentSlat", k * 2.2, 20.7, 9, 0.6, 0.3, 5, C.shadow, { collide = false })
				end
				for _, x in { -4.5, 4.5 } do
					vc("Pipe", x, 36.3, 9, 32, 1.5, C.orange, { collide = false })
				end
				xc("WallPipe", 0, 5.5, 0.9, 72, 1.6, C.orange, { collide = false })
				for _, x in { -30, -15, 15, 30 } do
					xc("PipeCollar", x, 5.5, 0.9, 1, 2.2, C.metal, { collide = false })
				end
				-- Yakıt tankı
				vc("FuelTank", 31, 3.8, 5, 7, 5.4, C.hazard)
				vc("FuelBand", 31, 3.8, 5, 1.2, 5.7, C.hazardDark, { collide = false })
				vc("FuelCap", 31, 7.6, 5, 0.6, 2, C.metalDark, { collide = false })
				local fuel = bx("FuelSign", 31, 11, 0.4, 6, 2.4, 0.3, C.shadow, { collide = false })
				label(fuel, "FUEL", C.hazard)
				-- Motor hizalama konsolu
				bx("AlignConsole", -31, 2.2, 3, 7, 4.4, 4, C.metal)
				bx("AlignScreen", -31, 4.8, 3.4, 6, 0.3, 3.2, C.cyan, { emit = "Screen" })

			-- ═══ SECURITY ═════════════════════════════════════════════════════
			elseif th.id == "Security" then
				bx("Desk", 0, 1.7, 5.5, 30, 3.4, 5, C.metal)
				bx("DeskTop", 0, 3.6, 5.6, 31, 0.4, 5.8, C.frame)
				for k, x in { -10.5, -3.5, 3.5, 10.5 } do
					screen("Monitor" .. k, x, 9, 0.6, 6.4, 4.4, C.screenDark)
					-- Kamera görüntüsü: koridor karesi
					bx("Feed", x - 1, 8.6, 1.02, 3, 2, 0.06, if k % 2 == 0 then C.cyan else C.green, { emit = "Indicator", collide = false })
				end
				for k, x in { -7, 7 } do
					screen("TopMonitor" .. k, x, 14.2, 0.6, 6.4, 3.6, C.screenDark)
					bx("Feed", x + 1, 14.2, 1.02, 3.4, 1.6, 0.06, C.cyan, { emit = "Indicator", collide = false })
				end
				chair(0, 12, C.red)
				-- Duvar kamerası: kırmızı kayıt lambası yanıp sönüyor
				bx("CamMount", 32, 13, 0.8, 1.6, 2, 1.6, C.metalDark)
				bx("CamBody", 32, 12.4, 2.6, 2, 2, 3.6, C.frame)
				zc("CamLens", 32, 12.4, 4.5, 0.4, 1.4, C.shadow, { collide = false })
				local rec = K.ball(f, "CamLight", 0, 0, 0, 0.5, C.red, { emit = "Fixture" })
				rec.CFrame = R(32.7, 13.6, 4)
				rec:SetAttribute("PulsePeriod", 1.2)
				-- Kamera odası dolabı
				bx("Locker", -30, 5, 2, 7, 10, 3.6, C.wallLow)
				bx("LockerDoor", -31.7, 5, 3.85, 3.2, 9, 0.1, C.frameDark, { collide = false })
				bx("LockerDoor", -28.3, 5, 3.85, 3.2, 9, 0.1, C.frameDark, { collide = false })

			-- ═══ COMMS ════════════════════════════════════════════════════════
			elseif th.id == "Comms" then
				for _, x in { -33, -26, 26, 33 } do
					bx("Rack", x, 8, 3, 6, 16, 5, rgb(74, 90, 108))
					bx("RackFace", x, 8, 5.55, 5, 14.6, 0.1, C.shadow, { collide = false })
					for row = 0, 4 do
						for col = -1, 1 do
							local tone = if (row + col) % 3 == 0 then C.red elseif (row + col) % 3 == 1 then C.green else C.cyan
							local led = bx("Led", x + col * 1.4, 3 + row * 2.6, 5.65, 0.7, 0.5, 0.1, tone, { emit = "Indicator" })
							if (row * 3 + col) % 4 == 0 then
								led:SetAttribute("PulsePeriod", 0.9 + (row % 3) * 0.4)
							end
						end
					end
				end
				-- Dünya haritası ekranı
				screen("MapScreen", 0, 11, 0.6, 14, 6.4, rgb(24, 70, 88))
				for k, p in { { -3, 11.5, 4, 1.6 }, { 2, 10, 3, 2.2 }, { 4.5, 12.4, 2, 1 }, { -4.5, 9.4, 2.2, 1 } } do
					bx("Land" .. k, p[1], p[2], 1.02, p[3], p[4], 0.06, C.green, { emit = "Indicator", collide = false })
				end
				-- Telsiz masası
				bx("RadioDesk", 8, 1.7, 5.5, 14, 3.4, 5, C.metal)
				bx("RadioTop", 8, 3.6, 5.6, 15, 0.4, 5.8, C.frame)
				bx("Radio", 8, 5.6, 4.6, 8, 3.6, 3, C.metalDark)
				zc("Dial", 6, 5.6, 6.15, 0.5, 2.4, C.frame, { collide = false })
				bx("DialNeedle", 6, 6.1, 6.45, 0.2, 1, 0.1, C.red, { collide = false })
				for k = 0, 3 do
					bx("Grille", 9.6 + k * 0.7, 5.6, 6.15, 0.3, 2.4, 0.1, C.shadow, { collide = false })
				end
				-- Uydu çanağı: kaide üstünde, yukarı bakıyor
				vc("DishPost", -16, 3.5, 12, 7, 1.6, C.metal)
				vc("DishBase", -16, 0.4, 12, 0.8, 5, C.metalDark, { collide = false })
				local tilt = R(-16, 9, 12) * CFrame.Angles(math.rad(-50), 0, 0)
				K.boxAt(f, "Dish", tilt * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.8, 10, 10), C.frame, { shape = Enum.PartType.Cylinder })
				K.boxAt(f, "DishInner", tilt * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.4, 8.4, 8.4), C.metal, { shape = Enum.PartType.Cylinder, collide = false })
				K.boxAt(f, "DishArm", tilt * CFrame.new(0, 0, -2.6), Vector3.new(0.4, 0.4, 4.6), C.metalDark, { collide = false })
				K.boxAt(f, "DishFeed", tilt * CFrame.new(0, 0, -5), Vector3.new(1.2, 1.2, 1.2), C.red, { shape = Enum.PartType.Ball, collide = false })

			-- ═══ O2 ═══════════════════════════════════════════════════════════
			elseif th.id == "O2" then
				for _, x in { -28, 28 } do
					vc("TankBase", x, 0.8, 7, 1.6, 9.4, C.metal)
					vc("Soil", x, 2.1, 7, 1, 8, rgb(110, 80, 56), { collide = false })
					local glass = vc("TankGlass", x, 8, 7, 12, 8.2, C.glass, { material = Enum.Material.Glass, transparency = 0.6 })
					glass.CastShadow = false
					vc("TankCap", x, 14.6, 7, 1.2, 9.4, C.metal)
					vc("TankPipe", x, 33.3, 7, 36.2, 1.4, C.metalDark, { collide = false })
					-- Bitki: gövde + yaprak kümeleri
					vc("Stem", x, 5, 7, 5, 0.6, rgb(60, 140, 70), { collide = false })
					for k, p in { { 0, 8.4, 0, 4.6 }, { -1.6, 6.8, 1, 3.4 }, { 1.7, 7.2, -0.8, 3.2 }, { 0.4, 10.4, 0.6, 3 } } do
						K.ellipsoid(f, "Leaf" .. k, R(x + p[1], p[2], 7 + p[3]), Vector3.new(p[4], p[4] * 0.8, p[4]),
							if k % 2 == 0 then rgb(88, 190, 96) else rgb(64, 160, 80), { collide = false })
					end
				end
				-- Oksijen tüpleri
				bx("CanRack", -4, 6, 2.2, 22, 0.6, 4.4, C.metalDark, { collide = false })
				for k = 0, 4 do
					local x = -12 + k * 4
					vc("Canister", x, 4.8, 2.2, 9, 3, C.white)
					vc("CanCap", x, 9.8, 2.2, 1, 2, rgb(70, 140, 230))
					vc("CanBand", x, 6, 2.2, 0.7, 3.2, rgb(70, 140, 230), { collide = false })
				end
				-- Filtre paneli
				bx("Filter", 16, 7, 1.1, 8, 8, 2.2, C.metal)
				for k = 0, 5 do
					bx("FilterSlat", 16, 4 + k * 1.2, 2.3, 6.4, 0.4, 0.2, C.shadow, { collide = false })
				end
				local ok = bx("FilterLamp", 16, 11.6, 2.25, 1, 0.6, 0.1, C.green, { emit = "Indicator" })
				ok.CastShadow = false
				xc("O2Pipe", 0, 13, 0.9, 70, 1.4, rgb(90, 160, 230), { collide = false })

			-- ═══ ELECTRICAL ═══════════════════════════════════════════════════
			elseif th.id == "Electrical" then
				local wires = { C.red, rgb(60, 110, 230), C.hazard, rgb(236, 90, 190) }
				for _, x in { -24, -10, 4 } do
					bx("Panel", x, 8, 0.9, 10, 12, 1.8, C.metal)
					bx("PanelDoor", x, 8, 1.85, 9, 11, 0.1, C.frameDark, { collide = false })
					for k, col in wires do
						local y = 4.2 + k * 1.9
						bx("Wire", x, y, 1.98, 7, 0.45, 0.16, col, { collide = false })
						for _, s in { -1, 1 } do
							bx("Terminal", x + s * 3.9, y, 2.0, 0.8, 0.8, 0.22, C.metalDark, { collide = false })
						end
					end
				end
				-- Şalter kutusu
				bx("Breaker", 20, 7, 1.1, 8, 10, 2.2, C.shadow)
				for row = 0, 1 do
					for k = 0, 4 do
						local up = (k + row) % 2 == 0
						bx("Lever", 17 + k * 1.5, 5 + row * 4 + (if up then 0.4 else -0.4), 2.5, 0.6, 1.2, 0.6, if up then C.green else C.red, { collide = false })
					end
				end
				-- Trafo: sarı-siyah
				bx("Transformer", 32, 4.5, 4, 7, 9, 6, C.hazard)
				bx("TransformerBand", 32, 4.5, 4, 7.2, 1.4, 6.2, C.hazardDark, { collide = false })
				local volt = bx("VoltSign", 32, 7.4, 7.06, 4, 2, 0.1, C.shadow, { collide = false })
				label(volt, "HIGH VOLTAGE", C.hazard)
				-- Panellerin önünde zemin şeridi (dünya koordinatında)
				local stripe = R(-10, FLOOR, 5)
				K.hazard(f, stripe.X, FLOOR + 0.07 + M.LIFT, stripe.Z, 40, 1, "x", 2.4)
				-- "Elektrikte ceset" — oyunun en bilinen sahnesi
				K.crewmate(f, R(-3, 0, 13) * CFrame.Angles(0, math.rad(35), 0), K.crew(11), 1.25, "dead")

			-- ═══ ADMIN ════════════════════════════════════════════════════════
			elseif th.id == "Admin" then
				vc("TableBase", 0, 1.8, 11, 3.6, 13, C.metal)
				vc("TableTop", 0, 3.9, 11, 0.6, 17, C.frame)
				vc("TableScreen", 0, 4.25, 11, 0.12, 14.6, rgb(20, 60, 44), { collide = false })
				-- Hologram harita: Skeld'in kabaca planı
				for k, p in { { 0, 11, 5, 3 }, { -4.5, 11, 3, 5.5 }, { 4.2, 11, 3.2, 4 }, { 0, 8.2, 2, 2 }, { 0, 13.8, 3, 1.6 }, { -2, 11, 1, 0.8 } } do
					bx("Holo" .. k, p[1], 4.36, p[2], p[3], 0.1, p[4], C.green, { emit = "Screen", collide = false })
				end
				local glow = vc("HoloGlow", 0, 6.2, 11, 3.6, 13, C.green, { emit = "Screen", transparency = 0.86, collide = false })
				glow.CastShadow = false
				chair(-12, 11, C.red)
				chair(12, 11, C.red)
				-- Kart okuyucu
				bx("Swipe", 26, 6, 0.8, 5, 3.4, 1.6, C.shadow)
				bx("SwipeSlot", 26, 6.9, 1.65, 4, 0.3, 0.1, C.metal, { collide = false })
				bx("SwipeLamp", 27.6, 5.2, 1.65, 0.8, 0.5, 0.1, C.green, { emit = "Indicator" })
				bx("Card", 24.6, 5.4, 1.75, 1.4, 1, 0.08, C.white, { collide = false })
				-- Veri yükleme konsolu
				bx("Upload", -26, 2.2, 3, 7, 4.4, 4, C.metal)
				screen("UploadScreen", -26, 8, 0.6, 7, 4, C.screenDark)
				bx("Progress", -27.2, 7.4, 1.02, 3.8, 0.6, 0.06, C.green, { emit = "Indicator", collide = false })

			-- ═══ SHIELDS ══════════════════════════════════════════════════════
			elseif th.id == "Shields" then
				bx("HexPanel", 0, 9, 0.5, 15, 11, 1, C.shadow)
				local cells = { { 0, 0 } }
				for k = 0, 5 do
					local a = math.rad(60 * k + 30)
					table.insert(cells, { math.cos(a) * 3.5, math.sin(a) * 3.5 })
				end
				for k, p in cells do
					local on = k ~= 3 and k ~= 6
					zc("Hex" .. k, p[1], 9 + p[2], 1.2, 0.4, 3.1, if on then th.accent else C.metalDark,
						{ emit = if on then "Screen" else nil, collide = false })
				end
				for _, x in { -25, 25 } do
					vc("DomeRing", x, 0.8, 9, 1.6, 12, C.metal)
					local dome = K.ball(f, "Dome", 0, 0, 0, 10, rgb(255, 232, 140), { emit = "Screen", transparency = 0.35 })
					dome.CFrame = R(x, 0.8, 9)
					dome.CanCollide = true
					dome.CastShadow = false
					vc("DomeCap", x, 6.1, 9, 0.6, 2, C.metal, { collide = false })
				end
				bx("PrimeConsole", 0, 2.2, 13, 7, 4.4, 4, C.metal)
				bx("PrimeScreen", 0, 4.8, 12.6, 6, 0.3, 3.2, th.accent, { emit = "Screen" })
			end
		end
	end,
}
