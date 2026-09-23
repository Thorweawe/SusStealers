--!strict
--[[
	Odalar (üs bölgeleri): alçak bölme duvarları, yan kapılar, koridora
	bakan oda tabelası, üssün kendi süslemesi (kaide pedleri, çerçeve,
	konveyör kapakları) ve koridordaki üs işareti.

	Adı sabit parçalar (istemci/test bunlara bakıyor):
	  Plots.PlotN.PodiumPad      — kaidelerin altında (test hizayı ölçüyor)
	  Plots.PlotN.FrameX/FrameZ/PillarBand — sahibin rengine boyanıyor
	  Plots.PlotN.HatchHood      — makine uğultusu buraya bağlanıyor
	  Doorways.DoorGlowN         — oda tabelasının altındaki şerit (sahip rengi)
	  BayMarkers.BayPadN         — koridordaki zemin işareti (sahip rengi)
]]

return {
	folders = { "Partitions", "Plots", "Doorways", "BayMarkers" },

	build = function(K: any)
		local M, C = K.M, K.C
		local T = 2                      -- bölme duvarı kalınlığı
		local H = M.PART_WALL_H

		local parts = K.folder("Partitions")
		local plotsF = K.folder("Plots")
		local doorways = K.folder("Doorways")
		local markers = K.folder("BayMarkers")

		for i = 1, M.PLOT_COUNT do
			local o = K.plotOrigin(i)
			local ox, oz = o.X, o.Z
			local flip = K.plotFlip(i)
			local facing = K.plotFacing(i)
			local th = K.theme(i)
			local r = K.roomRect(i)
			local zFront = if facing > 0 then r[4] else r[2]
			local zWall = if facing > 0 then M.IZ0 else M.IZ1

			-- ─── Bölme duvarları ────────────────────────────────────────────
			--[[
				Yan duvarlar arka duvardan odanın önüne kadar; ortada 18'lik
				kapı (üssün tam yanına açılıyor). Ön taraf koridora açık,
				köşelerde yalnızca kısa birer ayak var — oda çerçevelensin
				ama geçiş kapanmasın.
			]]
			local pf = K.folder("Room" .. i, parts)
			-- Duvar gövdenin 0.3 içinden başlıyor: uç yüzü süpürgelikle aynı düzlemde kalmasın
			zWall -= facing * 0.3
			local doorU = math.abs(oz - zWall)
			local wspec = {
				h = H, t = T, windows = false, winBottom = H, winTop = H, noCove = true,
				twoSided = true, cap = C.wallCap, lowColor = C.wallLow,
				inset0 = 1.6, inset1 = 1.6,
				-- Kapı 10.5: lentonun üstü korkuluk bandının üstüyle aynı hizaya düşmesin
				doors = { { u0 = doorU - 9, u1 = doorU + 9, h = 10.5 } },
				name = "Side",
			}
			for _, sx in { -1, 1 } do
				local x = ox + sx * M.ROOM_HX
				local a = Vector2.new(x, zWall)
				local b = Vector2.new(x, zFront + facing * T / 2)
				-- iç taraf odaya bakıyor (kapı lambası ve söveler iki yüzlü)
				local inside = if sx < 0 then -facing else facing
				K.wall(pf, a, b, inside, wspec)
				K.door(pf, a, b, inside, doorU - 9, doorU + 9, 10.5, T)
			end

			-- Ön köşe ayakları
			for _, sx in { -1, 1 } do
				-- Ayak yan duvarın içinden başlıyor (uç yüzü görünmesin)
				local x0 = ox + sx * (M.ROOM_HX + 0.3)
				local x1 = ox + sx * (M.ROOM_HX - T / 2 - 7)
				local inside = if sx < 0 then facing else -facing
				K.wall(pf, Vector2.new(x0, zFront), Vector2.new(x1, zFront), inside, {
					h = H, t = T, windows = false, winBottom = H, winTop = H, noCove = true,
					twoSided = true, cap = C.wallCap, inset0 = 0.6, inset1 = 0.6, name = "Stub",
				})
				-- Ayağın ucunda tema renginde dikey şerit: odanın rengi koridordan okunsun
				K.box(pf, "StubAccent", x1 + sx * 0.0, H / 2, zFront, 0.5, H - 3, T + 0.3, th.accent, { emit = "Screen" })
			end

			-- ─── Oda tabelası ───────────────────────────────────────────────
			--[[
				Tavandan sarkan, iki yüzlü. Yüksekte (y 43): 2. ve 3. kattaki
				oyuncuların koridora bakışını kapatmasın. Among Us'ın oda
				etiketleri gibi beyaz, konturlu.
			]]
			local dw = K.folder("Door" .. i, doorways)
			local signY = 43
			local look = CFrame.lookAt(Vector3.new(ox, signY, zFront), Vector3.new(ox, signY, zFront + facing))
			local board = K.sign(dw, "RoomSign", look, 36, 6, th.name, nil)
			K.text(board, Enum.NormalId.Back, th.name, C.white, { h = 0.78, y = 0.08, guiName = "LabelBack" })
			for _, sx in { -1, 1 } do
				K.box(dw, "SignRod", ox + sx * 13, signY + 3 + (M.WALL_H - signY - 3) / 2, zFront, 0.5, M.WALL_H - signY - 3, 0.5, C.frameDark, { collide = false })
			end
			-- Sahip rengi şeridi (istemci boyuyor)
			K.box(dw, "DoorGlow" .. i, ox, signY - 3.9, zFront, 32, 0.6, 0.6, C.frameDark, { emit = "Screen" })

			-- ─── Koridordaki üs işareti ─────────────────────────────────────
			local mz = zFront + facing * 5
			K.box(markers, "BayPad" .. i, ox, M.TILE_TOP + 0.06 + M.LIFT, mz, 18, 0.12, 6, C.hallLane)
			for _, s in { -1, 1 } do
				K.hazard(markers, ox, M.TILE_TOP + 0.07 + M.LIFT, mz + s * 3.5, 18, 0.8, "x", 2)
			end

			-- ─── Üssün kendi süslemesi ──────────────────────────────────────
			local plot = K.folder("Plot" .. i, plotsF)
			local topY = M.topY

			-- Kaide pedleri: yuvarlak, açık kenarlı
			local perRow = math.ceil(M.PODIUMS / 2)
			for slot = 1, M.PODIUMS do
				local front = slot <= perRow
				local col = if front then slot - 1 else slot - perRow - 1
				local px = ox + (col - (perRow - 1) / 2) * M.PODIUM_GAP
				local pz = oz + (if front then -M.PODIUM_ROW_Z else M.PODIUM_ROW_Z)
				K.vcyl(plot, "PodiumPad", px, topY + 0.12 + M.LIFT, pz, 0.24, 6.4, C.frame, { collide = false })
				K.vcyl(plot, "PodiumRing", px, topY + 0.15 + M.LIFT, pz, 0.3, 5.2, th.grout, { collide = false })
			end

			-- Çerçeve: sahibin rengi (istemci boyuyor)
			local fy = topY + 0.125 + M.LIFT
			for _, s in { -1, 1 } do
				K.box(plot, "FrameX", ox + s * M.halfX, fy, oz, 0.8, 0.25, M.PLOT_SIZE.Z, C.frameDark, { emit = "Screen" })
				K.box(plot, "FrameZ", ox, fy, oz + s * M.halfZ, M.PLOT_SIZE.X, 0.25, 0.8, C.frameDark, { emit = "Screen" })
			end

			-- Köşe dikmeleri: kısa, geçirgen; bandı sahibin renginde
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local px = ox + sx * (M.halfX + 2.4)
					local pz = oz + sz * (M.halfZ + 2.4)
					K.box(plot, "Bollard", px, M.TILE_TOP + 2, pz, 1.6, 4, 1.6, C.metal, { collide = false })
					K.box(plot, "PillarBand", px, M.TILE_TOP + 2.8, pz, 1.8, 0.6, 1.8, C.frameDark, { emit = "Screen" })
					K.box(plot, "BollardCap", px, M.TILE_TOP + 4.2, pz, 2, 0.4, 2, C.frame, { collide = false })
				end
			end

			-- ─── Konveyör sahnesi ───────────────────────────────────────────
			local convZ = oz + flip * (M.halfZ - 5)
			local beltY = topY + 1
			local beltLen = M.PLOT_SIZE.X - 12

			for _, e in { -1, 1 } do
				K.hazard(plot, ox, topY + 0.06 + M.LIFT, convZ + e * 3.2, beltLen + 4, 0.7, "x", 2.4)
			end

			-- Bant çıtaları: kapaktan girişe akıyor
			local SLATS = 8
			local gap = beltLen / SLATS
			local dx = ox - flip * beltLen / 2
			for k = 0, SLATS - 1 do
				local slat = K.box(plot, "BeltSlat", dx + flip * k * gap, beltY + 0.09 + M.LIFT, convZ, 0.9, 0.18, 4.4, C.metalDark)
				slat:SetAttribute("SlideSpeed", 5 * flip)
				slat:SetAttribute("SlideRange", beltLen)
			end

			--[[
				Kargo kapakları: iki uçta aynı gövde. Çıkışta (karakterlerin
				doğduğu uç) sıcak ışık ve yeşil lamba, girişte soğuk ışık.
				Gövde üssün kenarından biraz taşıyor; hepsi geçirgen, üs
				kenarında oyuncu takılmasın.
			]]
			local function chute(name: string, ax: number, dir: number, tone: Color3, lampColor: Color3)
				local W, HH, D = 7, 9, 8.4
				local bx = ax + dir * (W / 2 + 0.6)
				local body = K.box(plot, name .. "Body", bx, M.TILE_TOP + (10.4 - M.TILE_TOP) / 2, convZ, W, 10.4 - M.TILE_TOP, D, C.frame, { collide = false })
				local hood = K.cyl(plot, if name == "Hatch" then "HatchHood" else name .. "Hood",
					CFrame.new(bx, 10.4, convZ) * CFrame.Angles(0, math.rad(90), 0), D, W, C.frame, { collide = false })
				-- Gövdenin üstünde tema renginde bant
				K.box(plot, name .. "Band", bx, 7.6, convZ, W + 0.2, 1.2, D + 0.3, th.accent, { collide = false })
				-- Ağız çerçevesi
				for _, e in { -1, 1 } do
					K.box(plot, name .. "Jamb", ax, beltY + HH / 2 - 0.5, convZ + e * 3.7, 1.4, HH - 1, 1.2, C.metal, { collide = false })
				end
				K.box(plot, name .. "Lintel", ax, beltY + HH - 0.5, convZ, 1.6, 1.4, 8.8, C.metal, { collide = false })
				-- Karanlık boğaz ve ışıklı ağız
				-- Boğaz gövdeden 0.15 taşıyor: ön yüzleri aynı düzlemde olmasın
				K.box(plot, name .. "Throat", ax + dir * 1.4, beltY + (HH - 1.5) / 2, convZ, 1.9, HH - 1.6, 6.2, C.shadow, { collide = false })
				local mouth = K.box(plot, name .. "Mouth", ax + dir * 0.55, beltY + (HH - 1.5) / 2 + 0.1, convZ, 0.3, HH - 2.4, 5.8, tone, { emit = "Screen", transparency = 0.35 })
				K.light(mouth, tone, 12, 0.9)
				-- Lento üstünde uyarı dişleri
				for k = -1, 1 do
					K.box(plot, name .. "Tooth", ax - dir * 0.85, beltY + HH - 0.5, convZ + k * 2.6, 0.2, 1.1, 1.2, if k == 0 then C.hazardDark else C.hazard, { collide = false })
				end
				-- Tepede durum lambası
				local lamp = K.ball(plot, name .. "Lamp", bx, 10.4 + W / 2 + 0.3, convZ, 1.2, lampColor, { emit = "Indicator" })
				lamp:SetAttribute("PulsePeriod", 2.2)
				return body, hood
			end

			chute("Hatch", dx, -flip, K.rgb(255, 196, 110), C.green)
			chute("Intake", ox + flip * beltLen / 2, flip, C.cyan, C.orange)
		end
	end,
}
