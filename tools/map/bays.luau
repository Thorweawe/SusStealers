--!strict
--[[
	Odalar (üs bölgeleri): alçak bölme duvarları, yan kapılar ve üssün
	kendi süslemesi (kaide pedleri, çerçeve, konveyör kapakları).

	Adı sabit parçalar (istemci/test bunlara bakıyor):
	  Plots.PlotN.PodiumPad      — kaidelerin altında (test hizayı ölçüyor)
	  Plots.PlotN.FrameX/FrameZ  — sahibin rengine boyanıyor
	  Plots.PlotN.HatchHood      — makine uğultusu buraya bağlanıyor
]]

return {
	-- Doorways/BayMarkers eski sürümün klasörleri: yeniden kurulumda silinsin
	folders = { "Partitions", "Plots", "Doorways", "BayMarkers" },

	build = function(K: any)
		local M, C = K.M, K.C
		local plotsF = K.folder("Plots")

		for i = 1, M.PLOT_COUNT do
			local o = K.plotOrigin(i)
			local ox, oz = o.X, o.Z
			local flip = K.plotFlip(i)
			local facing = K.plotFacing(i)
			local th = K.theme(i)
			--[[
				BÖLME DUVARI YOK. Odaların yan duvarları, kapıları ve köşe
				ayakları vardı; üsler arası geçişi bölüyor ve sahneyi
				kalabalıklaştırıyordu. Oda kimliği zemin rengi ve arka duvardaki
				eşyalardan okunuyor; tabela ve koridor pedi de yok.
			]]

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


			-- ─── Konveyör sahnesi ───────────────────────────────────────────
			local convZ = oz + flip * (M.halfZ - 5)
			local beltY = topY + 1
			local beltLen = M.PLOT_SIZE.X - 12

			for _, e in { -1, 1 } do
				K.hazard(plot, ox, topY + 0.06 + M.LIFT, convZ + e * 3.2, beltLen + 4, 0.7, "x", 2.4)
			end

			--[[
				Bant çıtaları: kapaktan girişe akıyor. Hepsi bandın BAŞINDAN
				başlıyor, aralarındaki mesafe faz (SlidePhase) olarak veriliyor.
				Eskiden her çıta kendi yerinden bir bant boyu daha kayıyordu ve
				bandın dışına, üssün arkasına kadar uzanan gri çizgiler oluyordu.
			]]
			local SLATS = 8
			local gap = beltLen / SLATS
			local dx = ox - flip * beltLen / 2
			for k = 0, SLATS - 1 do
				local slat = K.box(plot, "BeltSlat", dx, beltY + 0.09 + M.LIFT, convZ, 0.9, 0.18, 4.4, C.metalDark)
				slat:SetAttribute("SlideSpeed", 5 * flip)
				slat:SetAttribute("SlideRange", beltLen)
				slat:SetAttribute("SlidePhase", k * gap)
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
