--!strict
--[[
	ADMIN odası (Among Us'taki gibi): doğu tünelinin omurga altındaki
	yeraltı odası (K.underRooms()[2]; kabuğu tunnels.luau kuruyor).

	Ortada tünelin yürüme yolu, doğu yarısında harita masası: üstündeki
	"AdminScreen" parçasına istasyonun haritasını ve oda başına oyuncu
	noktalarını sunucu çiziyor (src/server/AdminMapService). Masadaki
	"AdminPrompt" haritayı ekranın ortasında büyük açıyor (istemci,
	AdminView). Batı yarısında kart okuyucu ve duvar ekranları.

	Eskiden masa Cafeteria'da skor panolarının önündeydi; oyuncu "admin
	odası" diye bir yer göremiyordu.
]]

return {
	folders = { "AdminTable", "AdminRoom" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local f = K.folder("AdminTable")
		local deco = K.folder("AdminRoom")

		local room = K.underRooms()[2]
		local x = M.TUNNEL_X[2]
		local hw = M.TUNNEL_W / 2
		local floor = M.TUNNEL_FLOOR
		local rmid = (room[2] + room[4]) / 2

		-- ─── Harita masası: yolun doğusunda ──────────────────────────────────
		local cx = (x + hw + room[3]) / 2
		local cz = rmid
		local topY = floor + 3.0

		K.box(f, "AdminFoot", cx, floor + 0.15, cz, 8.4, 0.3, 10.4, C.wallKick)
		K.box(f, "AdminBase", cx, (floor + 0.3 + topY - 0.3) / 2, cz, 7, topY - 0.6 - floor, 9, C.metalDark, { material = Enum.Material.Metal })
		local top = K.box(f, "AdminTop", cx, topY - 0.15, cz, 11.6, 0.3, 13.6, C.frame)

		--[[
			Harita ekranı: sunucu buraya SurfaceGui kuruyor (adı sabit).
			180° döndürülmüş: üst yüzdeki SurfaceGui'nin "yukarısı" parçanın
			-X'i, döndürünce dünyanın +x'i (doğu). Masaya yürüme yolundan
			(batıdan) bakan oyuncu için harita düz duruyor: haritanın kuzeyi
			(AdminMapService, kuzey yukarı) oyuncunun karşısında.
		]]
		K.boxAt(f, "AdminScreen", CFrame.new(cx, topY + 0.05, cz) * CFrame.Angles(0, math.rad(180), 0),
			Vector3.new(10.4, 0.1, 12.4), C.screenDark)

		-- Ekran çevresinde parlayan yeşil kenar (Skeld admin masasının hologram yeşili)
		local holo = rgb(90, 240, 150)
		for _, s in { -1, 1 } do
			K.box(f, "AdminRim", cx, topY + 0.04, cz + s * 6.45, 10.9, 0.08, 0.3, holo, { emit = "Screen" })
			K.box(f, "AdminRim", cx + s * 5.45, topY + 0.04, cz, 0.3, 0.08, 12.6, holo, { emit = "Screen" })
		end
		-- Masanın altından yayılan soluk ışık: oda yeşile boyansın
		K.light(top, holo, 16, 0.6)

		-- Kart okuyucu: masanın yola bakan (batı) kenarında
		local slotX = cx - 5.8 - 0.35
		K.box(f, "CardReader", slotX, topY - 0.6, cz - 3, 0.7, 1.2, 2.4, C.metalDark)
		K.box(f, "CardSlot", slotX - 0.36, topY - 0.45, cz - 3, 0.05, 0.12, 1.8, C.shadow)
		K.box(f, "CardLight", slotX - 0.36, topY - 0.95, cz - 3.8, 0.06, 0.25, 0.25, C.green, { emit = "Indicator" })

		-- Prompt: masayı ekranda büyük aç (istemci AdminView)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AdminPrompt"
		prompt.ActionText = "Use Admin Map"
		prompt.ObjectText = "Admin"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt.Parent = top

		-- Yola bakan (batı) yüzde küçük "ADMIN" plakası
		local plateX = cx - 3.56
		local plate = K.boxAt(f, "AdminPlate", CFrame.lookAt(Vector3.new(plateX, floor + 1.7, cz + 1.5), Vector3.new(plateX - 10, floor + 1.7, cz + 1.5)),
			Vector3.new(5, 1.1, 0.12), C.shadow)
		K.text(plate, Enum.NormalId.Front, "ADMIN", holo, { h = 0.8 })

		-- ─── Duvarlar: tabela ve ekranlar ────────────────────────────────────
		local wallX = room[3] - 0.4
		local signCf = CFrame.lookAt(Vector3.new(wallX - 0.45, floor + 8.2, cz), Vector3.new(wallX - 10, floor + 8.2, cz))
		K.sign(deco, "AdminSign", signCf, 12, 2.4, "ADMIN", holo)

		-- Batı yarısı: iki duvar ekranı (istasyon durumu), altlarında konsol
		local westX = room[1] + 0.4
		for i, z in { rmid - 6, rmid + 6 } do
			local cf = CFrame.lookAt(Vector3.new(westX + 0.3, floor + 5.2, z), Vector3.new(westX + 10, floor + 5.2, z))
			K.boxAt(deco, "WallScreenBezel", cf * CFrame.new(0, 0, 0.1), Vector3.new(7.4, 4.2, 0.3), C.frame)
			local screen = K.boxAt(deco, "WallScreen", cf * CFrame.new(0, 0, -0.08), Vector3.new(6.8, 3.6, 0.1), rgb(14, 34, 30), { emit = "Screen" })
			K.text(screen, Enum.NormalId.Front, if i == 1 then "O2  98%" else "REACTOR  OK", holo, { h = 0.34, y = 0.33 })
			K.box(deco, "WallConsole", westX + 1.2, floor + 1.2, z, 2, 2.4, 6, C.metalDark)
			K.box(deco, "WallConsoleTop", westX + 1.2, floor + 2.5, z, 2.2, 0.2, 6.2, C.frame)
			for k = -1, 1 do
				K.box(deco, "ConsoleButton", westX + 1.7, floor + 2.65, z + k * 1.6, 0.6, 0.12, 0.6,
					if k == 0 then C.red else C.green, { emit = "Indicator" })
			end
		end
	end,
}
