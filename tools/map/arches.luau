--!strict
--[[
	Omurga koridorunun kemerleri (2026-09-28, "içeriden bakınca dümdüz
	dikdörtgen; kavisli hissiyat olsun" — referans: bilim kurgu koridoru,
	lacivert yay çerçeveler, içlerinde camgöbeği neon).

	Omurga (SPINE_Z0..SPINE_Z1, 60 stud geniş) boyunca, odaların ARASINDAKİ
	boşluk hizalarında (ve iki uçta) yarım daire kemer: iki ayak koridor
	kenarında, yay tavanın hemen altında; tavandaki cam şerit kemerlerin
	arasından görünüyor. Yay CSG (silindir − iç silindir − alt yarı),
	K.carved ile boyut başına bir kez kesiliyor.

	Kemerler çarpışmasız (hayalet): odaların önü koridora tamamen açık
	kalmalı (OYUNU ENGELLEMEME KURALI), ayaklar kimseyi takmıyor.
]]

return {
	folders = { "Arches" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local FLOOR = M.TILE_TOP
		local f = K.folder("Arches")

		local frame = rgb(34, 62, 138)
		local frameDark = rgb(20, 36, 84)
		local neon = rgb(70, 220, 255)

		local z0, z1 = M.SPINE_Z0, M.SPINE_Z1
		local cz = (z0 + z1) / 2
		local R = (z1 - z0) / 2          -- dış yarıçap: koridor kenarından kenarına
		local band = 2.8                 -- çerçeve kalınlığı (radyal)
		local depth = 3.2                -- koridor boyunca kalınlık
		local springY = FLOOR + 20       -- yayın başladığı yükseklik (tavan ~51)
		local turned = CFrame.identity   -- silindir ekseni X = koridor boyu

		local function halfRing(name: string, outer: number, inner: number, d: number, color: Color3, at: CFrame, emit: boolean?)
			local key = string.format("arch %.2f %.2f %.2f", outer, inner, d)
			local p = K.carved(f, name, at, color, key, function()
				local body = K.boxAt(workspace, "Body", turned, Vector3.new(d, outer * 2, outer * 2), color, { shape = Enum.PartType.Cylinder })
				local hole = K.boxAt(workspace, "Hole", turned, Vector3.new(d + 2, inner * 2, inner * 2), color, { shape = Enum.PartType.Cylinder })
				local lower = K.boxAt(workspace, "Lower", CFrame.new(0, -(outer + 1) / 2, 0), Vector3.new(d + 2, outer + 1, outer * 2 + 2), color)
				return body, { hole, lower }
			end, false)
			if emit then
				p.Material = Enum.Material.Neon
				p.CastShadow = false
			end
			return p
		end

		-- Kemer hizaları: odalar arası boşluklar + iki uç (reaktör ve kokpit önü)
		local xs = { M.IX0 + 36 }
		for i = 1, M.COLUMNS - 1 do
			table.insert(xs, K.plotOrigin(i).X + M.PLOT_SPACING / 2)
		end
		table.insert(xs, M.IX1 - 36)

		for _, x in xs do
			local center = CFrame.new(x, springY, cz)
			halfRing("ArchFrame", R, R - band, depth, frame, center)
			-- İçteki neon şerit (çerçevenin iç yüzünde, daha ince)
			halfRing("ArchNeon", R - band + 0.35, R - band - 0.25, depth * 0.45, neon, center, true)
			-- Dış kenar kuşağı (koyu)
			halfRing("ArchLip", R + 0.4, R - 0.6, depth + 0.6, frameDark, center)
			for _, s in { -1, 1 } do
				local lz = cz + s * (R - band / 2)
				local legH = springY - FLOOR
				K.box(f, "ArchLeg", x, FLOOR + legH / 2, lz, depth, legH, band, frame, { ghost = true })
				K.box(f, "ArchLegLip", x, FLOOR + 0.3 + (legH - 0.6) / 2, cz + s * (R - 0.1), depth + 0.6, legH - 0.6, 1, frameDark, { ghost = true })
				local strip = K.box(f, "ArchLegNeon", x, FLOOR + 1.2 + (legH - 1.6) / 2, cz + s * (R - band - 0.05), depth * 0.45, legH - 1.6, 0.5, neon,
					{ ghost = true, emit = "Fixture" })
				strip.CastShadow = false
				K.box(f, "ArchFoot", x, FLOOR + 0.6, lz, depth + 1.4, 1.2, band + 1.4, frameDark, { ghost = true })
			end
		end

		-- Tavan: cam şeridin iki kenarı boyunca camgöbeği neon hat
		for _, z in { z0 + 8 - 1.2, z1 - 8 + 1.2 } do
			local strip = K.box(f, "CeilingNeon", (M.X0 + M.X1) / 2, M.WALL_H - 0.9, z, (M.X1 - M.X0) - 96, 0.35, 0.6, neon,
				{ ghost = true, emit = "Fixture" })
			strip.CastShadow = false
		end
	end,
}
