--!strict
--[[
	Admin masası (Among Us'taki gibi): Cafeteria'nın kuzey ucunda, skor
	panolarının önünde. Üstündeki "AdminScreen" parçasına harita ve oda
	başına oyuncu noktalarını sunucu çiziyor (src/server/AdminMapService).
	Burası yalnızca masanın gövdesi.

	Yeri bilerek yol üstünde değil: köprüden gelen akış masanın güneyinden
	geçiyor, panolara bakan oyuncu masayı da görüyor.
]]

return {
	folders = { "AdminTable" },

	build = function(K: any)
		local M, C = K.M, K.C
		local f = K.folder("AdminTable")

		local cx = M.centerX
		local cz = M.LOBBY_Z1 - 22
		local topY = 3.2

		-- Ayak ve gövde
		K.box(f, "AdminBase", cx, 1.6, cz, 9, 3.2 - 0.3 - M.TILE_TOP, 7, C.metalDark, { material = Enum.Material.Metal })
		-- Karo üstünde ayak tabanı (karolarla aynı düzlemde değil)
		K.box(f, "AdminFoot", cx, M.TILE_TOP + 0.15, cz, 10.4, 0.3, 8.4, C.wallKick)
		K.box(f, "AdminTop", cx, topY - 0.15, cz, 13.6, 0.3, 11.6, C.frame)

		--[[
			Harita ekranı: sunucu buraya SurfaceGui kuruyor (adı sabit).
			90° döndürülmüş: üst yüzdeki SurfaceGui'nin "yukarısı" parçanın
			-X'i. Döndürünce masaya güneyden bakan oyuncu için harita ve
			yazılar düz duruyor (yukarı = +z, sağ = -x).
		]]
		K.boxAt(f, "AdminScreen", CFrame.new(cx, topY + 0.05, cz) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(10.4, 0.1, 12.4), C.screenDark)

		-- Ekran çevresinde parlayan kenar
		for _, s in { -1, 1 } do
			K.box(f, "AdminRim", cx + s * 6.45, topY + 0.04, cz, 0.3, 0.08, 10.9, C.cyan, { emit = "Screen" })
			K.box(f, "AdminRim", cx, topY + 0.04, cz + s * 5.45, 12.6, 0.08, 0.3, C.cyan, { emit = "Screen" })
		end

		-- Önde (güneyde) küçük "ADMIN" plakası
		local plate = K.boxAt(f, "AdminPlate", CFrame.lookAt(Vector3.new(cx, 1.7, cz - 3.56), Vector3.new(cx, 1.7, cz - 10)),
			Vector3.new(5, 1.1, 0.12), C.shadow)
		K.text(plate, Enum.NormalId.Front, "ADMIN", C.cyan, { h = 0.8 })
	end,
}
