--!strict
--[[
	SECURITY odası (Among Us'taki gibi): batı tünelinin omurga altındaki
	yeraltı odası (K.underRooms()[1]; kabuğu tunnels.luau kuruyor).

	Batı duvarında 2x2 kamera ekranı ve önünde konsol + koltuk. Konsoldaki
	"SecurityPrompt" kamera görüntüsünü açıyor (istemci, SecurityCams):
	harita üstündeki güvenlik kameralarının (K.securityCamera) gözünden
	bakılıyor, oklarla kameralar arasında geziliyor. Doğu yarısında sunucu
	dolapları.

	Kameraların bir kısmı istasyon koridorunda (landmarks.luau); burası
	Cafeteria, MedBay ve Weapons'a da birer kamera ekliyor.
]]

return {
	folders = { "SecurityRoom", "SecurityCams" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local f = K.folder("SecurityRoom")

		local room = K.underRooms()[1]
		local x = M.TUNNEL_X[1]
		local hw = M.TUNNEL_W / 2
		local floor = M.TUNNEL_FLOOR
		local rmid = (room[2] + room[4]) / 2
		local wallX = room[1] + 0.4     -- batı duvarının iç yüzü
		local green = rgb(110, 240, 140)

		-- ─── Kamera ekranları: batı duvarında 2x2 ────────────────────────────
		local camIndex = 0
		for _, y in { floor + 6.7, floor + 4.1 } do
			for _, dz in { -2.4, 2.4 } do
				camIndex += 1
				local cf = CFrame.lookAt(Vector3.new(wallX + 0.25, y, rmid + dz), Vector3.new(wallX + 10, y, rmid + dz))
				K.boxAt(f, "MonitorBezel", cf * CFrame.new(0, 0, 0.1), Vector3.new(4.7, 2.5, 0.3), C.metalDark)
				local screen = K.boxAt(f, "Monitor", cf * CFrame.new(0, 0, -0.08), Vector3.new(4.3, 2.1, 0.1), rgb(28, 46, 40), { emit = "Screen" })
				K.text(screen, Enum.NormalId.Front, "CAM " .. camIndex, green, { h = 0.3, y = 0.06 })
				-- Kayıt noktası: köşede kırmızı, yanıp sönüyor (DecorFX)
				local rec = K.boxAt(f, "MonitorRec", cf * CFrame.new(1.8, 0.8, -0.16), Vector3.new(0.22, 0.22, 0.05), C.red, { emit = "Indicator" })
				rec:SetAttribute("PulsePeriod", 1.1)
			end
		end
		local signCf = CFrame.lookAt(Vector3.new(wallX + 0.45, floor + 9.6, rmid), Vector3.new(wallX + 10, floor + 9.6, rmid))
		K.sign(f, "SecuritySign", signCf, 10, 1.4, "SECURITY", green)

		-- ─── Konsol ve koltuk ───────────────────────────────────────────────
		local deskX = wallX + 1.8
		local deskTop = floor + 2.6
		K.box(f, "SecurityDeskBase", deskX, (floor + deskTop - 0.2) / 2, rmid, 3.2, deskTop - 0.2 - floor, 11, C.metalDark)
		local console = K.box(f, "SecurityConsole", deskX, deskTop - 0.1, rmid, 3.6, 0.2, 11.6, C.frame)
		-- Konsol üstünde tuş sıraları ve joystick
		for k = -2, 2 do
			K.box(f, "ConsoleKey", deskX + 0.6, deskTop + 0.06, rmid + k * 1.4, 0.8, 0.12, 0.8,
				if k == 0 then C.red else rgb(80, 200, 120), { emit = "Indicator" })
		end
		K.vcyl(f, "Joystick", deskX + 0.9, deskTop + 0.45, rmid - 4.4, 0.8, 0.2, C.shadow)
		K.ball(f, "JoystickKnob", deskX + 0.9, deskTop + 0.9, rmid - 4.4, 0.4, C.red)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SecurityPrompt"
		prompt.ActionText = "Watch Cameras"
		prompt.ObjectText = "Security"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = console

		-- Koltuk: konsola dönük, oturulabilir
		local seatX = deskX + 4.4
		local seatY = floor + 1.5
		K.vcyl(f, "ChairStem", seatX, floor + 0.65, rmid, 1.3, 0.4, C.metalDark)
		K.vcyl(f, "ChairFoot", seatX, floor + 0.08, rmid, 0.16, 2.2, C.shadow)
		K.boxAt(f, "SecuritySeat", CFrame.lookAt(Vector3.new(seatX, seatY, rmid), Vector3.new(seatX - 5, seatY, rmid)),
			Vector3.new(2.4, 0.5, 2.4), rgb(60, 106, 170), { seat = true })
		K.box(f, "ChairBack", seatX + 1.3, seatY + 1.4, rmid, 0.4, 2.4, 2.4, rgb(60, 106, 170))

		-- ─── Doğu yarısı: sunucu dolapları ──────────────────────────────────
		local eastX = room[3] - 0.4
		for _, dz in { -6, 6 } do
			local rx = eastX - 1.3
			K.box(f, "ServerRack", rx, floor + 3.6, rmid + dz, 2.4, 7.2, 3.4, rgb(46, 54, 64))
			for row = 0, 5 do
				local light = K.box(f, "RackLight", rx - 1.22, floor + 1.2 + row * 1.05, rmid + dz + (if row % 2 == 0 then -0.8 else 0.8),
					0.05, 0.2, 0.2, if row % 3 == 0 then C.red else green, { emit = "Indicator" })
				light:SetAttribute("PulsePeriod", 0.7 + row * 0.23)
			end
		end
		-- Dolaplar arası kablo demeti (yerde, kenar boyunca)
		K.box(f, "CableRun", eastX - 0.6, floor + 0.15, rmid, 0.8, 0.3, 8, C.shadow)

		-- ─── Ek kameralar: Cafeteria, MedBay, Weapons ───────────────────────
		local cams = K.folder("SecurityCams")
		K.securityCamera(cams, Vector3.new(M.centerX + 50, 38, M.LOBBY_Z0 + 3.6), Vector3.new(M.centerX, 2, M.LOBBY_CZ), "Cafeteria", 5)
		K.securityCamera(cams, Vector3.new(M.CAF_X1 + M.WING_W - 4, 24, M.LOBBY_CZ - 34.4), Vector3.new(M.CAF_X1 + 40, 2, M.LOBBY_CZ), "MedBay", 6)
		K.securityCamera(cams, Vector3.new(M.CAF_X0 - M.WING_W + 4, 24, M.LOBBY_CZ - 34.4), Vector3.new(M.CAF_X0 - 40, 2, M.LOBBY_CZ), "Weapons", 7)
	end,
}
