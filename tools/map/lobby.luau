--!strict
--[[
	Lobi = KAFETERYA (Skeld'in buluşma odası) ve istasyona bağlayan köprü.

	Sekizgen oda, krem damalı zemin, beş yuvarlak mavi masa. Ortadaki
	masada ACİL TOPLANTI DÜĞMESİ — oyunda üsse ışınlanma noktası
	(Lobby.luau "TeleportPad.PadColumn"a yaklaşınca paneli açıyor).
	Güney duvarında üç küresel sıralama ekranı, güneybatı köşede şans
	çarkı, güneydoğuda "en iyi mürettebat" kürsüsü. Doğu kapısı MedBay'e
	(yumurtalar), batı kapısı Weapons'a (ekipman) açılıyor.

	Adı sabit parçalar:
	  Lobby.LobbyDeck            — müzik bölgesi (sınırları okunuyor)
	  TeleportPad.PadColumn      — ışınlanma paneli buna yakınlıkla açılıyor
	  Boards.BoardScreenN.Display.{Header,Body} — sunucu dolduruyor
	  Wheel (Model).WheelHub/WheelPlinth — SpinService promptu; SpinSpeed
]]

return {
	folders = { "Bridge", "Lobby", "TeleportPad", "Boards", "Wheel" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local T = M.WALL_T
		local FLOOR = M.TILE_TOP

		local cx = M.centerX
		local z0, z1 = M.LOBBY_Z0, M.LOBBY_Z1
		local x0, x1 = M.CAF_X0, M.CAF_X1
		local ch = M.CAF_CHAMFER
		local cz = M.LOBBY_CZ
		local H = M.CAF_H

		-- ─── Köprü ──────────────────────────────────────────────────────────
		do
			local f = K.folder("Bridge")
			local bx0 = cx - M.GATE_W / 2 - T / 2
			local bx1 = cx + M.GATE_W / 2 + T / 2
			local za, zb = M.Z1, z0
			local BH = 26
			K.box(f, "BridgeDeck", cx, -0.5, (za + zb) / 2, bx1 - bx0 + T, 1, zb - za, C.hallGrout)
			K.box(f, "BridgeBelly", cx, -4, (za + zb) / 2 + 0.6, bx1 - bx0 + T - 4, 6, zb - za - 3.6, C.hullOut)
			K.tiles(f, { cx - M.GATE_W / 2, za + T / 2, cx + M.GATE_W / 2, zb - T / 2 }, 12, 12, 0.5, FLOOR, 0.24,
				C.hallTile, C.hallTile2, nil, "BridgeTile")
			-- Ortada açık renkli yürüme şeridi
			K.box(f, "BridgeLane", cx, FLOOR + 0.05 + M.LIFT, (za + zb) / 2, 6, 0.1, zb - za - 8, C.hallLane)
			local spec = {
				h = BH, winBottom = 9, winTop = 21, winW = 9, winGap = 5, rail = 5.5,
				inset0 = 1.4, inset1 = 1.4, exterior = C.hullOut, name = "Bridge",
			}
			--[[
				Köprü duvarları iki ucun DIŞ yüzünde başlayıp bitiyor. Duvar
				gövdesinin içine girselerdi iç yüzleri, kapı kesiğinin uç
				yüzüyle aynı düzlemde kalıyordu (ikisi de x=162).
			]]
			-- 0.8 pay: iki gövdenin dış kuşağından da kurtuluyor; aradaki
			-- boşluğu kapı sövesi (derinliği 2.1) örtüyor
			local wa, wb = za + T / 2 + 0.8, zb - T / 2 - 0.8
			K.wall(f, Vector2.new(bx0, wa), Vector2.new(bx0, wb), -1, spec)
			K.wall(f, Vector2.new(bx1, wa), Vector2.new(bx1, wb), 1, spec)
			local ceilY = BH + 0.6
			K.box(f, "BridgeCeiling", cx, ceilY, (za + zb) / 2, bx1 - bx0 - T, 1.2, zb - za - T, C.ceiling)
			K.box(f, "BridgeRoof", cx, ceilY + 1, (za + zb) / 2, bx1 - bx0 + T + 1, 0.8, zb - za - T, C.hullOut)
			for k = 0, 1 do
				local z = za + (zb - za) * (0.3 + 0.4 * k)
				K.box(f, "LightFrame", cx, ceilY - 0.75, z, 13.2, 0.3, 4.2, C.frame)
				local p = K.box(f, "LightPanel", cx, ceilY - 0.95, z, 12, 0.2, 3, C.lamp, { emit = "Fixture" })
				K.surfaceLight(p, Enum.NormalId.Bottom, C.lamp, 34, 1.4, 140)
			end
		end

		-- ─── Kafeterya kabuğu ───────────────────────────────────────────────
		local f = K.folder("Lobby")

		-- Müzik bölgesi: kafeterya + iki kanat (görünmez, katı değil)
		local deckX0 = x0 - M.WING_W
		local deckX1 = x1 + M.WING_W
		local deck = K.box(f, "LobbyDeck", (deckX0 + deckX1) / 2, -2.5, (z0 + z1) / 2, deckX1 - deckX0, 1, z1 - z0, C.hallGrout,
			{ transparency = 1 })
		deck.CastShadow = false

		local V = {
			Vector2.new(x0 + ch, z0), Vector2.new(x1 - ch, z0), Vector2.new(x1, z0 + ch), Vector2.new(x1, z1 - ch),
			Vector2.new(x1 - ch, z1), Vector2.new(x0 + ch, z1), Vector2.new(x0, z1 - ch), Vector2.new(x0, z0 + ch),
		}

		-- Sekizgen yüzey: orta dikdörtgen + iki yan + dört üçgen köşe
		local function octSlab(name: string, y: number, thick: number, color: Color3, inset: number)
			local i = inset
			K.box(f, name, cx, y, cz, (x1 - x0) - 2 * ch, thick, (z1 - z0) - 2 * i, color)
			for _, s in { -1, 1 } do
				local sx = if s < 0 then (x0 + i + x0 + ch) / 2 else (x1 - ch + x1 - i) / 2
				K.box(f, name, sx, y, cz, ch - i, thick, (z1 - z0) - 2 * ch, color)
			end
			local corners = {
				{ Vector2.new(x0 + ch, z0 + i), Vector2.new(x0 + i, z0 + ch), Vector2.new(x0 + ch, z0 + ch) },
				{ Vector2.new(x1 - ch, z0 + i), Vector2.new(x1 - i, z0 + ch), Vector2.new(x1 - ch, z0 + ch) },
				{ Vector2.new(x0 + ch, z1 - i), Vector2.new(x0 + i, z1 - ch), Vector2.new(x0 + ch, z1 - ch) },
				{ Vector2.new(x1 - ch, z1 - i), Vector2.new(x1 - i, z1 - ch), Vector2.new(x1 - ch, z1 - ch) },
			}
			for _, t in corners do
				K.flatTriangle(f, name .. "Corner", t[1], t[2], t[3], y, thick, color)
			end
		end

		octSlab("CafDeck", -0.5, 1, C.cafGrout, 0)
		octSlab("CafBelly", -4.5, 7, C.hullOut, 1.5)

		--[[
			Zemin karoları: krem dama, 12.8'lik KARE karo. Ölçü seçilmiş:
			iç genişlik 217.6 = 17 karo, iç derinlik 153.6 = 12 karo; böylece
			pah köşesine paralel bir kesim çizgisi tam karo köşelerinden
			geçiyor ve çizgiyi kesen karolar tam ortadan ikiye bölünüyor
			(üçgen yarım karo). Duvar ile kesim çizgisi arasındaki şeridi
			bordür dolduruyor — testere dişi boşluk kalmıyor.
		]]
		local tf = K.folder("CafTiles", f)
		local TILE = 12.8
		local GAP = 0.5
		local gx0, gz0 = x0 + T / 2, z0 + T / 2
		local nx = math.floor((x1 - x0 - T) / TILE + 0.5)
		local nz = math.floor((z1 - z0 - T) / TILE + 0.5)
		-- Kesim seviyesi (karo biriminde): pah çizgisinden en az bir duvar
		-- kalınlığı içeride kalan ilk karo köşegeni
		local LEVEL = math.ceil((ch - T + T * 0.75) / TILE)
		local border = C.cafGrout:Lerp(C.cafTile, 0.35)

		-- Bir karonun dört köşesinin, en yakın köşeye göre seviyesi
		local function level(i: number, j: number): number
			local li = math.min(i, nx - i)
			local lj = math.min(j, nz - j)
			return li + lj
		end
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				local ax, az = gx0 + i * TILE, gz0 + j * TILE
				local color = if (i + j) % 2 == 0 then C.cafTile else C.cafTile2
				-- Köşe seviyeleri
				local corners = {
					{ level(i, j), Vector2.new(ax, az) }, { level(i + 1, j), Vector2.new(ax + TILE, az) },
					{ level(i, j + 1), Vector2.new(ax, az + TILE) }, { level(i + 1, j + 1), Vector2.new(ax + TILE, az + TILE) },
				}
				local minL = math.huge
				for _, c in corners do
					minL = math.min(minL, c[1])
				end
				if minL >= LEVEL then
					K.box(tf, "CafTile", ax + TILE / 2, FLOOR - 0.12, az + TILE / 2, TILE - GAP, 0.24, TILE - GAP, color)
				elseif minL == LEVEL - 1 then
					-- Bir köşesi çizginin dışında: kalan üç köşe üçgen yarım karo
					local keep = {}
					for _, c in corners do
						if c[1] >= LEVEL then
							table.insert(keep, c[2])
						end
					end
					if #keep == 3 then
						-- Dik açı, köşegenin karşısındaki köşe (en içteki)
						local centroid = (keep[1] + keep[2] + keep[3]) / 3
						local shrink = function(v: Vector2): Vector2
							return centroid + (v - centroid) * 0.955
						end
						local rightIdx = 1
						local best = -1
						for k = 1, 3 do
							local lv = level(if keep[k].X > ax + 0.1 then i + 1 else i, if keep[k].Y > az + 0.1 then j + 1 else j)
							if lv > best then
								best = lv
								rightIdx = k
							end
						end
						local others = {}
						for k = 1, 3 do
							if k ~= rightIdx then
								table.insert(others, shrink(keep[k]))
							end
						end
						K.flatTriangle(tf, "CafTileHalf", others[1], others[2], shrink(keep[rightIdx]), FLOOR - 0.12, 0.24, color)
					end
				end
			end
		end

		-- Pah bordürü: duvar ile kesim çizgisi arası (dikdörtgen + iki uç üçgeni)
		local cutPerp = (LEVEL * TILE + T) / math.sqrt(2) - ch / math.sqrt(2)
		for k = 0, 3 do
			local a = V[k * 2 + 2]
			local b = V[(k * 2 + 2) % 8 + 1]
			local mid = (a + b) / 2
			local dir = (b - a).Unit
			local nrm = Vector2.new(-dir.Y, dir.X)
			local len = (b - a).Magnitude
			local w = cutPerp
			local c = mid + nrm * (w / 2)
			K.boxAt(tf, "Border", CFrame.lookAt(Vector3.new(c.X, FLOOR - 0.12, c.Y), Vector3.new(c.X + nrm.X, FLOOR - 0.12, c.Y + nrm.Y)),
				Vector3.new(len, 0.24, w), border)
			-- Uç üçgenleri: bordürü düz duvarlara kadar tamamlıyor
			-- Dik açı köşesi q; üçüncü köşe düz duvarın merkez çizgisinde
			local qa = a + nrm * w
			local qb = b + nrm * w
			K.flatTriangle(tf, "BorderEnd", a, qa - dir * w, qa, FLOOR - 0.12, 0.24, border)
			K.flatTriangle(tf, "BorderEnd", b, qb + dir * w, qb, FLOOR - 0.12, 0.24, border)
		end

		-- ─── Duvarlar ───────────────────────────────────────────────────────
		--[[
		inset: süpürgelik/korkuluk/ışık bandı köşeden 5 stud önce bitiyor.
		135° birleşimlerde iki duvarın bantları uca kadar uzanınca birbirinin
		içinden geçiyor, köşeler "kırık" görünüyordu. Aradaki boşluğu kalın
		köşe sütunu kapatıyor.
	]]
	local ws = { h = H, winBottom = 18, winTop = 34, winW = 12, winGap = 8, rail = 15, exterior = C.hullOut,
		inset0 = T + 2.6, inset1 = T + 2.6 }
		local doorN = { u0 = (cx - x0 - ch) - M.GATE_W / 2, u1 = (cx - x0 - ch) + M.GATE_W / 2, h = 24 }
		local wingDoor = { u0 = (cz - z0 - ch) - 18, u1 = (cz - z0 - ch) + 18, h = 22 }

		local walls = {
			{ V[1], V[2], K.merge(ws, { name = "CafN", doors = { doorN } }), doorN },
			{ V[2], V[3], K.merge(ws, { name = "CafNE" }) },
			{ V[3], V[4], K.merge(ws, { name = "CafE", doors = { wingDoor } }), wingDoor },
			{ V[4], V[5], K.merge(ws, { name = "CafSE" }) },
			{ V[5], V[6], K.merge(ws, { name = "CafS", windows = false }) },
			{ V[6], V[7], K.merge(ws, { name = "CafSW", windows = false }) },
			{ V[7], V[8], K.merge(ws, { name = "CafW", doors = { wingDoor } }), wingDoor },
			{ V[8], V[1], K.merge(ws, { name = "CafNW" }) },
		}
		local wf = K.folder("CafWalls", f)
		for _, w in walls do
			local a, b = w[1], w[2]
			-- Uçları bir tık uzat: 135° köşede dış yüzde çentik kalmasın
			local dir = (b - a).Unit
			local ea, eb = a - dir * 0.5, b + dir * 0.5
			local spec = w[3]
			if w[4] then
				spec.doors = { { u0 = w[4].u0 + 0.5, u1 = w[4].u1 + 0.5, h = w[4].h } }
			end
			K.wall(wf, ea, eb, 1, spec)
			if w[4] then
				K.door(wf, ea, eb, 1, w[4].u0 + 0.5, w[4].u1 + 0.5, w[4].h)
			end
		end
		-- Köşe sütunları: birleşimi ve bantların uçlarını örtüyor
		for _, v in V do
			K.vcyl(wf, "CornerPost", v.X, H / 2, v.Y, H, T + 3.4, C.wallHigh)
			K.vcyl(wf, "CornerFoot", v.X, 1.4, v.Y, 2.8, T + 4.2, C.wallKick)
			K.vcyl(wf, "CornerBand", v.X, 15.3, v.Y, 1.2, T + 4, C.wallRail)
		end
		-- Tavan
		local ceilY = H + 0.6
		octSlab("CafCeiling", ceilY, 1.2, C.ceiling, T / 2)
		octSlab("CafRoof", ceilY + 1, 0.8, C.hullOut, -0.5)

		-- ─── Masalar ────────────────────────────────────────────────────────
		local tables = K.folder("Tables", f)
		local function bench(parent: Instance, tx: number, tz: number, radius: number)
			for q = 0, 3 do
				for s = 0, 2 do
					local a = math.rad(q * 90 + 15 + s * 20 + 10)
					local px, pz = tx + math.cos(a) * radius, tz + math.sin(a) * radius
					local look = CFrame.lookAt(Vector3.new(px, FLOOR, pz), Vector3.new(tx, FLOOR, tz))
					local seg = 2 * radius * math.sin(math.rad(10)) + 0.25
					K.boxAt(parent, "BenchLeg", look * CFrame.new(0, 0.8, 0), Vector3.new(seg - 0.6, 1.6, 2.2), C.frameDark)
					-- Oturulabilir (Seat): oyuncu masaya dönük oturuyor
				K.boxAt(parent, "BenchSeat", look * CFrame.new(0, 2.0, 0), Vector3.new(seg, 0.8, 2.9), C.bench, { seat = true })
				end
			end
		end
		local function cafTable(parent: Instance, tx: number, tz: number): BasePart
			local post = K.vcyl(parent, "TablePost", tx, FLOOR + 1.7, tz, 3.4, 3, C.metal)
			K.vcyl(parent, "TableFoot", tx, FLOOR + 0.2, tz, 0.4, 6, C.metalDark)
			K.vcyl(parent, "TableRim", tx, FLOOR + 3.7, tz, 0.6, 15.2, C.tableRim)
			K.vcyl(parent, "TableTop", tx, FLOOR + 3.9, tz, 0.8, 14, C.tableTop)
			bench(parent, tx, tz, 10.2)
			return post
		end

		local spots = { { cx - 52, cz - 36 }, { cx + 52, cz - 36 }, { cx - 52, cz + 34 }, { cx + 52, cz + 34 } }
		for k, s in spots do
			local t = K.folder("Table" .. k, tables)
			cafTable(t, s[1], s[2])
		end

		-- ─── Orta masa: ACİL TOPLANTI DÜĞMESİ = üsse dönüş ──────────────────
		do
			local tp = K.folder("TeleportPad")
			local post = cafTable(tp, cx, cz)
			post.Name = "PadColumn"
			post:SetAttribute("TeleportHub", true)
			local top = FLOOR + 4.3
			K.vcyl(tp, "ButtonBase", cx, top + 0.4, cz, 0.8, 6.4, C.frame)
			local button = K.ball(tp, "EmergencyButton", cx, top + 1.1, cz, 3.8, rgb(232, 40, 40))
			button.Material = Enum.Material.SmoothPlastic
			K.light(button, rgb(255, 80, 70), 16, 1.1)
			local dome = K.ball(tp, "ButtonGlass", cx, top + 0.9, cz, 5.8, C.glass,
				{ material = Enum.Material.Glass, transparency = 0.7 })
			dome.CastShadow = false
			-- Üstünde yüzen etiket
			local anchor = K.box(tp, "PadLabel", cx, top + 7.5, cz, 1, 1, 1, C.frame, { transparency = 1 })
			local gui = Instance.new("BillboardGui")
			gui.Name = "Label"
			gui.Size = UDim2.fromScale(14, 3.4)
			gui.MaxDistance = 140
			gui.LightInfluence = 0
			gui.Parent = anchor
			local title = Instance.new("TextLabel")
			title.Size = UDim2.fromScale(1, 0.62)
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.FredokaOne
			title.TextScaled = true
			title.TextColor3 = rgb(255, 90, 80)
			title.TextStrokeTransparency = 0.1
			title.TextStrokeColor3 = rgb(20, 20, 28)
			title.Text = "EMERGENCY"
			title.Parent = gui
			local sub = Instance.new("TextLabel")
			sub.Position = UDim2.fromScale(0, 0.62)
			sub.Size = UDim2.fromScale(1, 0.38)
			sub.BackgroundTransparency = 1
			sub.Font = Enum.Font.FredokaOne
			sub.TextScaled = true
			sub.TextColor3 = C.white
			sub.TextStrokeTransparency = 0.2
			sub.TextStrokeColor3 = rgb(20, 20, 28)
			sub.Text = "return to your base"
			sub.Parent = gui
		end

		-- Tavan lambaları: her masanın üstünde yuvarlak armatür
		local lamps = K.folder("Lamps", f)
		local allSpots = table.clone(spots)
		table.insert(allSpots, { cx, cz })
		for _, s in allSpots do
			K.vcyl(lamps, "LampRim", s[1], H - 0.55, s[2], 0.5, 11, C.frame)
			local lamp = K.vcyl(lamps, "Lamp", s[1], H - 0.85, s[2], 0.3, 9.4, C.lamp, { emit = "Fixture" })
			-- Dik silindirin yerel -X yüzü aşağı bakıyor (Z etrafında 90° dönük)
			K.surfaceLight(lamp, Enum.NormalId.Left, C.lamp, 40, 1.5, 150)
		end
		-- Kenar lambaları (kanat kapılarının önü ve güney)
		for _, p in { { cx, z0 + 18 }, { x0 + 26, cz }, { x1 - 26, cz }, { cx, z1 - 30 } } do
			K.box(lamps, "LightFrame", p[1], H - 0.15, p[2], 13.2, 0.3, 4.2, C.frame)
			local lp = K.box(lamps, "LightPanel", p[1], H - 0.35, p[2], 12, 0.2, 3, C.lamp, { emit = "Fixture" })
			K.surfaceLight(lp, Enum.NormalId.Bottom, C.lamp, 40, 1.3, 140)
		end

		-- ─── Tabelalar ──────────────────────────────────────────────────────
		local signs = K.folder("Signs", f)
		local function wallSign(name: string, pos: Vector3, lookDir: Vector3, w: number, text: string, accent: Color3)
			K.sign(signs, name, CFrame.lookAt(pos, pos + lookDir), w, 5.5, text, accent)
		end
		wallSign("CafSign", Vector3.new(cx, 31, z0 + T / 2 + 0.8), Vector3.new(0, 0, 1), 34, "CAFETERIA", rgb(90, 150, 212))
		wallSign("MedSign", Vector3.new(x1 - T / 2 - 0.8, 29, cz), Vector3.new(-1, 0, 0), 30, "MEDBAY · EGGS", rgb(120, 230, 150))
		wallSign("WeapSign", Vector3.new(x0 + T / 2 + 0.8, 29, cz), Vector3.new(1, 0, 0), 30, "WEAPONS · GEAR", rgb(255, 150, 80))

		-- ─── Sıralama ekranları ─────────────────────────────────────────────
		do
			local bf = K.folder("Boards")
			local zb = z1 - T / 2
			local titles = { "TOP EARNERS", "MOST STOLEN", "TOP INCOME" }
			for i, title in titles do
				-- Odadan bakınca soldan sağa 1-2-3 (bakış yönü +z, sol = +x)
				local x = cx - (i - 2) * 46
				K.box(bf, "BoardFrame", x, 17, zb - 0.4, 42, 24, 1.1, C.frame)
				K.box(bf, "BoardBack", x, 17, zb - 0.1, 43.5, 25.5, 0.6, C.frameDark)
				local screen = K.box(bf, "BoardScreen" .. i, x, 17, zb - 1.1, 39.6, 21.2, 0.3, rgb(14, 24, 38))
				local surface = Instance.new("SurfaceGui")
				surface.Name = "Display"
				surface.Face = Enum.NormalId.Front
				surface.CanvasSize = Vector2.new(430, 230)
				surface.LightInfluence = 0
				surface.Parent = screen
				-- Kenar yuvarlatma ve ince çerçeve
				local header = Instance.new("TextLabel")
				header.Name = "Header"
				header.Size = UDim2.new(1, 0, 0, 38)
				header.BackgroundColor3 = rgb(64, 124, 196)
				header.BorderSizePixel = 0
				header.Font = Enum.Font.FredokaOne
				header.TextSize = 26
				header.TextColor3 = C.white
				header.TextStrokeTransparency = 0.4
				header.Text = title
				header.Parent = surface
				local body = Instance.new("TextLabel")
				body.Name = "Body"
				body.Position = UDim2.fromOffset(14, 46)
				body.Size = UDim2.new(1, -28, 1, -52)
				body.BackgroundTransparency = 1
				body.Font = Enum.Font.GothamBold
				body.TextSize = 20
				body.TextXAlignment = Enum.TextXAlignment.Left
				body.TextYAlignment = Enum.TextYAlignment.Top
				body.TextColor3 = rgb(230, 238, 248)
				body.Text = "..."
				body.Parent = surface
				-- Ekranın altında küçük kürsü lambası
				K.box(bf, "BoardLip", x, 4.6, zb - 1.6, 42.6, 0.6, 2, C.frame)
			end
		end

		-- ─── Şans çarkı (güneybatı pahı) ────────────────────────────────────
		do
			local wheel = Instance.new("Model")
			wheel.Name = "Wheel"
			wheel.Parent = K.root
			local a, b = V[6], V[7]
			local mid = (a + b) / 2
			local dir = (b - a).Unit
			local nrm = Vector2.new(-dir.Y, dir.X)          -- odaya bakan
			local c = mid + nrm * 11
			-- Çerçeve: yerel -Z odaya (izleyiciye) bakıyor
			local base = CFrame.lookAt(Vector3.new(c.X, FLOOR, c.Y), Vector3.new(c.X + nrm.X, FLOOR, c.Y + nrm.Y))
			local function W(x: number, y: number, z: number): CFrame
				return base * CFrame.new(x, y, -z)
			end
			local R, SLICES, hubY, SPIN = 10, 12, 15, 26

			local plinth = K.boxAt(wheel, "WheelPlinth", W(0, 2.5, 0), Vector3.new(14, 5, 9), C.frame)
			wheel.PrimaryPart = plinth
			K.boxAt(wheel, "WheelPlinthBand", W(0, 3.6, 0), Vector3.new(14.3, 1.1, 9.3), rgb(64, 124, 196))
			K.boxAt(wheel, "WheelDeck", W(0, 0.35, 1.5), Vector3.new(26, 0.7, 14), C.frameDark)
			for _, s in { -1, 1 } do
				K.boxAt(wheel, "WheelLeg", W(s * 7.2, 5 + (hubY - 5) / 2, -1) * CFrame.Angles(0, 0, math.rad(-s * 10)),
					Vector3.new(2.2, hubY - 3, 2.2), C.frame)
			end
			-- Arka levha yuvarlak: kare levha duvarın önünde koyu bir kutu gibi duruyordu
			K.boxAt(wheel, "WheelBacking", W(0, hubY, -2.2) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.8, R * 2 + 6, R * 2 + 6),
				rgb(40, 58, 80), { shape = Enum.PartType.Cylinder })
			local BULBS = 24
			for i = 1, BULBS do
				local ang = (i - 1) * (math.pi * 2 / BULBS)
				local bulb = K.boxAt(wheel, "WheelBulb", W(0, hubY, -1.6) * CFrame.Angles(0, 0, ang) * CFrame.new(R + 2.4, 0, 0),
					Vector3.new(1.2, 1.2, 1.2), if i % 2 == 0 then C.lamp else C.hazard, { shape = Enum.PartType.Ball, emit = "Indicator" })
				bulb:SetAttribute("PulsePeriod", 1.4)
			end
			--[[
				Dönen parçalar çarkın GÖBEĞİ etrafında dönmeli. Eskiden her
				dilim kendi merkezi etrafında dönüyordu (DecorFX parçayı kendi
				ekseninde çeviriyordu) ve çark dönerken dilimler dağılıyordu.
				SpinCenter/SpinAxisVec verilince DecorFX ortak eksen kullanıyor.
			]]
			local hubPos = W(0, hubY, 0).Position
			local function spins(p: BasePart): BasePart
				p:SetAttribute("SpinSpeed", SPIN)
				p:SetAttribute("SpinAxis", "Z")
				p:SetAttribute("SpinCenter", hubPos)
				p:SetAttribute("SpinAxisVec", base.LookVector)
				return p
			end
			spins(K.boxAt(wheel, "WheelDisc", W(0, hubY, -0.6), Vector3.new(R * 2 - 1, R * 2 - 1, 0.9), rgb(40, 58, 80)))
			local taper = math.tan(math.pi / SLICES)
			local chord = 2 * R * math.sin(math.pi / SLICES)
			for i = 1, SLICES do
				local ang = (i - 1) * (math.pi * 2 / SLICES)
				local pivot = W(0, hubY, 0.2) * CFrame.Angles(0, 0, ang)
				for j = 1, 5 do
					local rMid = R * (j - 0.5) / 5
					spins(K.boxAt(wheel, "WheelSlice", pivot * CFrame.new(rMid, 0, 0),
						Vector3.new(R / 5 + 0.05, 2 * rMid * taper * 0.98, 0.7), K.crew(i):Lerp(Color3.new(1, 1, 1), (j - 1) / 5 * 0.18)))
				end
				spins(K.boxAt(wheel, "WheelSpoke", pivot * CFrame.Angles(0, 0, math.pi / SLICES) * CFrame.new(R * 0.5, 0, -0.1),
					Vector3.new(R * 0.96, 0.5, 1), C.frame))
				spins(K.boxAt(wheel, "WheelRim", pivot * CFrame.new(R + 0.4, 0, 0), Vector3.new(1.6, chord + 0.3, 2.2), C.frame))
				spins(K.boxAt(wheel, "WheelPeg", pivot * CFrame.Angles(0, 0, math.pi / SLICES) * CFrame.new(R + 1.6, 0, -0.2),
					Vector3.new(1, 0.7, 0.7), C.lamp))
			end
			K.boxAt(wheel, "WheelHub", W(0, hubY, 1.2) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(2, 5.4, 5.4), C.frame,
				{ shape = Enum.PartType.Cylinder })
			K.boxAt(wheel, "WheelHubCap", W(0, hubY, 2.2) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.6, 2.6, 2.6), C.red,
				{ shape = Enum.PartType.Cylinder })
			-- Durdurucu dil
			K.boxAt(wheel, "TickerMount", W(0, hubY + R + 4, 0.2), Vector3.new(3, 1.6, 3), C.frame)
			K.boxAt(wheel, "TickerArm", W(0, hubY + R + 1.8, 0.2) * CFrame.Angles(0, 0, math.rad(7)), Vector3.new(1.2, 3.6, 1.6), C.metal)
			K.boxAt(wheel, "TickerTip", W(0, hubY + R - 0.2, 0.2), Vector3.new(2.2, 1.4, 2), C.red, { emit = "Indicator" })
			-- Tabela
			local signY = hubY + R + 9.5
			local board = K.boxAt(wheel, "SignBoard", W(0, signY, -0.4), Vector3.new(26, 5.6, 0.8), rgb(40, 58, 80))
			K.boxAt(wheel, "SignFrame", W(0, signY, -0.9), Vector3.new(27.4, 7, 0.4), C.frame)
			K.text(board, Enum.NormalId.Front, "LUCKY SPIN", C.hazard, { h = 0.8, y = 0.1 })
			for _, s in { -1, 1 } do
				K.boxAt(wheel, "SignPost", W(s * 11, hubY + R + 5.4, -0.9), Vector3.new(1, 2.8, 1), C.frame)
			end
			-- Çarkın başındaki mürettebat: odaya (oyunculara) bakıyor, hafif ortaya dönük.
			-- Eskiden -150° ile çarka dönüktü; oyuncu yalnızca sırtını görüyordu.
			K.crewmate(wheel, W(10, 0.7, 5) * CFrame.Angles(0, math.rad(20), 0), K.crew(6), 1.4)
		end

		-- ─── Güneydoğu: en iyi mürettebat kürsüsü ───────────────────────────
		do
			local sf = K.folder("Podium", f)
			local a, b = V[4], V[5]
			local mid = (a + b) / 2
			local dir = (b - a).Unit
			local nrm = Vector2.new(-dir.Y, dir.X)
			local c = mid + nrm * 12
			local base = CFrame.lookAt(Vector3.new(c.X, FLOOR, c.Y), Vector3.new(c.X + nrm.X, FLOOR, c.Y + nrm.Y))
			-- Odadan bakınca 2-1-3 dizilişi: 2. solda (+x yerel sağ), 3. sağda
			local steps = { { 0, 5.4, rgb(255, 204, 60), 6 }, { 9, 3.6, rgb(206, 216, 228), 8 }, { -9, 2.2, rgb(222, 146, 84), 5 } }
			for k, s in steps do
				K.boxAt(sf, "Step" .. k, base * CFrame.new(s[1], s[2] / 2, 0), Vector3.new(8.8, s[2], 9), C.frame)
				K.boxAt(sf, "StepBand" .. k, base * CFrame.new(s[1], s[2] - 0.5, -4.55), Vector3.new(8.8, 1, 0.1), s[3], { emit = "Screen" })
				local num = K.boxAt(sf, "StepNum" .. k, base * CFrame.new(s[1], (s[2] - 1) / 2, -4.56), Vector3.new(3.6, math.max(1.2, s[2] - 1.4), 0.05), C.frame, { transparency = 1 })
				K.text(num, Enum.NormalId.Front, tostring(k), s[3], { h = 1, y = 0 })
				K.crewmate(sf, base * CFrame.new(s[1], s[2], 0), K.crew(s[4]), 1.7)
			end
			local look = base * CFrame.new(0, 17.5, 3.5)
			K.sign(sf, "PodiumSign", look, 24, 4.4, "TOP CREW", rgb(255, 204, 60))
		end

		-- ─── Kuzey köşeleri: çöp kanalı ve otomat ───────────────────────────
		do
			local nf = K.folder("Corners", f)
			-- Kuzeybatı: çöp kanalı (Empty Garbage görevi)
			local a, b = V[8], V[1]
			local mid, dir = (a + b) / 2, (b - a).Unit
			local nrm = Vector2.new(-dir.Y, dir.X)
			local c = mid + nrm * 4.5
			local base = CFrame.lookAt(Vector3.new(c.X, FLOOR, c.Y), Vector3.new(c.X + nrm.X, FLOOR, c.Y + nrm.Y))
			K.boxAt(nf, "Chute", base * CFrame.new(0, 7, 0), Vector3.new(10, 14, 5), C.metal)
			K.boxAt(nf, "ChuteMouth", base * CFrame.new(0, 7.5, -2.55), Vector3.new(7, 5, 0.1), C.shadow)
			K.boxAt(nf, "ChuteLever", base * CFrame.new(4, 9, -3.2), Vector3.new(0.6, 3, 0.6), C.red)
			for k = -2, 2 do
				K.boxAt(nf, "ChuteStripe", base * CFrame.new(k * 2, 2, -2.56), Vector3.new(1, 1.4, 0.06), if k % 2 == 0 then C.hazard else C.hazardDark)
			end
			-- Kuzeydoğu: atıştırmalık otomatı
			a, b = V[2], V[3]
			mid, dir = (a + b) / 2, (b - a).Unit
			nrm = Vector2.new(-dir.Y, dir.X)
			c = mid + nrm * 4.5
			base = CFrame.lookAt(Vector3.new(c.X, FLOOR, c.Y), Vector3.new(c.X + nrm.X, FLOOR, c.Y + nrm.Y))
			K.boxAt(nf, "Vending", base * CFrame.new(0, 7, 0), Vector3.new(9, 14, 5), rgb(220, 70, 70))
			K.boxAt(nf, "VendGlass", base * CFrame.new(-1, 8, -2.55), Vector3.new(5.6, 9, 0.1), C.glass,
				{ material = Enum.Material.Glass, transparency = 0.4 })
			for row = 0, 2 do
				for col = -1, 1 do
					K.boxAt(nf, "Snack", base * CFrame.new(-1 + col * 1.7, 5.2 + row * 2.8, -2.3), Vector3.new(1.2, 1.6, 0.3),
						K.crew(row * 3 + col + 3))
				end
			end
			K.boxAt(nf, "VendPad", base * CFrame.new(3.2, 9, -2.55), Vector3.new(1.6, 4, 0.1), C.shadow)
			local vl = K.boxAt(nf, "VendLogo", base * CFrame.new(0, 13.2, -2.56), Vector3.new(7, 1.2, 0.05), C.white, { transparency = 1 })
			K.text(vl, Enum.NormalId.Front, "SNACKS", C.white, { h = 1, y = 0 })
			-- Saksı bitkileri: kapıların iki yanında
			for _, p in { { cx - 26, z0 + 5 }, { cx + 26, z0 + 5 } } do
				K.vcyl(nf, "Pot", p[1], FLOOR + 1.5, p[2], 3, 4, C.frame)
				K.vcyl(nf, "PotSoil", p[1], FLOOR + 3.05, p[2], 0.1, 3.4, rgb(110, 80, 56))
				K.ellipsoid(nf, "Bush", CFrame.new(p[1], FLOOR + 5.4, p[2]), Vector3.new(5, 5, 5), rgb(80, 180, 96))
				K.ellipsoid(nf, "Bush", CFrame.new(p[1] + 1.2, FLOOR + 7, p[2] - 0.6), Vector3.new(3.4, 3.4, 3.4), rgb(100, 200, 110))
			end
		end
	end,
}
