--!strict
--[[
	Odalar (üs bölgeleri): alçak bölme duvarları, yan kapılar ve üssün
	kendi süslemesi (kaide pedleri, çerçeve).

	Adı sabit parçalar (istemci/test bunlara bakıyor):
	  Plots.PlotN.PodiumPad      — kaidelerin altında (test hizayı ölçüyor)
	  Plots.PlotN.FrameX/FrameZ  — sahibin rengine boyanıyor
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
				K.vcyl(plot, "PodiumPad", px, topY + 0.12 + M.LIFT, pz, 0.24, 6.4, C.frame)
				K.vcyl(plot, "PodiumRing", px, topY + 0.15 + M.LIFT, pz, 0.3, 5.2, th.grout)
			end

			-- Çerçeve: sahibin rengi (istemci boyuyor)
			local fy = topY + 0.125 + M.LIFT
			for _, s in { -1, 1 } do
				K.box(plot, "FrameX", ox + s * M.halfX, fy, oz, 0.8, 0.25, M.PLOT_SIZE.Z, C.frameDark, { emit = "Screen" })
				K.box(plot, "FrameZ", ox, fy, oz + s * M.halfZ, M.PLOT_SIZE.X, 0.25, 0.8, C.frameDark, { emit = "Screen" })
			end


			-- Konveyör sahnesi 2026-09-27'de kalktı: yerinde uzay kapsülü
			-- (PlotService çalışma anında kuruyor, shared/CapsuleModel)
			local _ = flip
		end
	end,
}
