--!strict
--[[
	Son kat: haritayı canlandıran ve oynanışa dokunan rötuşlar. EN SONDA
	kuruluyor, çünkü diğer bölümlerin parçalarına da bakıyor (gölgeler,
	vent kopyaları).

	  Tabelalar  — her üs odasının koridora bakan ağzında, tavandan sarkan
	               oda adı (Skeld'in oda etiketleri). Oyuncu "Electrical'a
	               koş" diyebilsin.
	  Kasalar    — odalar arasındaki boşlukların duvar dibinde erzak yığını
	  İşaret lambaları — duvardaki kırmızı uyarı lambaları. Yanıp sönmesi
	               istemcide (MapLife): sunucudan her karede ışık değiştirmek
	               ağı boşuna meşgul ederdi.
	  Vent ağı   — Among Us havalandırmaları. Eşli kapaklar; VentService
	               üstündeki "VentPad"e prompt kuruyor ve eşine ışınlıyor.
	               Karakter TAŞIRKEN kullanılamıyor: çalmanın bütün riski
	               rakip üssünden koşarak kaçmak, vent bunu silmemeli.
	  Gölge      — küçük parçalar, tavan ve zeminde CastShadow kapalı.
	               Telefonda gölge haritası en pahalı iş; 1 stud'luk vidanın
	               gölgesi görünmüyor bile.

	MALZEME DEĞİŞMEDİ: kit'in stil kuralı (her yer SmoothPlastic, çizgi
	film görünümü) bilinçli; metal dokusu temayı bozuyor.

	Kısmi yeniden kurulumda (_G.MAP_ONLY) bu bölümü de listeye ekle:
	landmarks yeniden kurulursa vent kopyaları, diğerleri kurulursa gölge
	ayarı kaybolur.
]]

return {
	folders = { "Polish" },

	build = function(K: any)
		local M, C = K.M, K.C
		local root = K.folder("Polish")
		local rgb = K.rgb

		-- ─── Ölçüler (üs yerleşiminden) ──────────────────────────────────────

		-- Arka sıra odaları koridora +Z'den, ön sıra -Z'den bakıyor
		local backRowZ = K.plotOrigin(1).Z
		local frontRowZ = K.plotOrigin(M.COLUMNS + 1).Z
		local corridorZ = (backRowZ + frontRowZ) / 2

		-- Salonun iç duvar yüzleri: zemin karolarının sınırı
		local hallMinZ, hallMaxZ = math.huge, -math.huge
		local floor = K.root:FindFirstChild("Floor")
		if floor then
			for _, d in floor:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "HallTile" then
					hallMinZ = math.min(hallMinZ, d.Position.Z - d.Size.Z / 2)
					hallMaxZ = math.max(hallMaxZ, d.Position.Z + d.Size.Z / 2)
				end
			end
		end
		if hallMinZ == math.huge then
			warn("map/polish: HallTile yok, önce station kurulmalı")
			return
		end

		-- Odalar arası boşlukların x merkezleri (sütunlar arası)
		local gaps: { number } = {}
		for c = 1, M.COLUMNS - 1 do
			local a = K.plotOrigin(c).X
			local b = K.plotOrigin(c + 1).X
			table.insert(gaps, (a + b) / 2)
		end

		-- ─── Oda tabelaları ──────────────────────────────────────────────────

		local ceilingY = 52
		local ceiling = K.root:FindFirstChild("Ceiling")
		if ceiling then
			for _, d in ceiling:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "CeilingSlab" then
					ceilingY = d.Position.Y - d.Size.Y / 2
				end
			end
		end

		local signs = K.folder("RoomSigns", root)
		local SIGN_Y, SIGN_W, SIGN_H = 17, 24, 4.2
		for i = 1, M.PLOT_COUNT do
			local origin = K.plotOrigin(i)
			local theme = K.theme(i)
			local back = origin.Z < corridorZ
			-- Tabela odanın koridora açılan kenarında, yazısı koridora bakıyor
			local rect = K.roomRect(i)
			local edgeZ = if back then rect[4] else rect[2]
			local pos = Vector3.new(origin.X, SIGN_Y, edgeZ)
			local facing = if back then Vector3.zAxis else -Vector3.zAxis
			local cf = CFrame.lookAt(pos, pos + facing)
			K.sign(signs, "RoomSign", cf, SIGN_W, SIGN_H, theme.name, theme.accent)
			-- Arkası da okunsun: odanın içinden bakan da adı görsün
			local rear = K.boxAt(signs, "RoomSignRear", cf * CFrame.new(0, 0, 0.62), Vector3.new(SIGN_W, SIGN_H, 0.1), C.shadow, { collide = false })
			K.text(rear, Enum.NormalId.Back, theme.name, C.white, { h = 0.78, y = 0.08 })
			-- Tavana iki askı
			local rodLength = ceilingY - (SIGN_Y + SIGN_H / 2 + 0.6)
			for _, x in { -SIGN_W * 0.36, SIGN_W * 0.36 } do
				K.boxAt(signs, "SignRod",
					cf * CFrame.new(x, SIGN_H / 2 + 0.6 + rodLength / 2, 0.3),
					Vector3.new(0.3, rodLength, 0.3), C.metalDark, { collide = false })
			end
		end

		-- ─── Kasalar ve işaret lambaları ─────────────────────────────────────

		local props = K.folder("Props", root)
		local CRATE = rgb(196, 160, 108)
		local STRAP = rgb(120, 92, 58)

		local function crate(cf: CFrame, s: number)
			K.boxAt(props, "Crate", cf, Vector3.new(s, s, s), CRATE)
			-- Kenar bantları: kutuyu "kasa" yapan tek şey
			for _, y in { -s * 0.32, s * 0.32 } do
				K.boxAt(props, "CrateStrap", cf * CFrame.new(0, y, 0), Vector3.new(s + 0.08, s * 0.12, s + 0.08), STRAP, { collide = false })
			end
		end

		local beacons = K.folder("Beacons", root)
		local function beacon(pos: Vector3, facing: Vector3)
			local cf = CFrame.lookAt(pos, pos + facing)
			K.boxAt(beacons, "BeaconBase", cf * CFrame.new(0, -0.9, -0.3), Vector3.new(1.4, 0.4, 1.2), C.metalDark, { collide = false })
			local lamp = K.boxAt(beacons, "WarnBeacon", cf * CFrame.new(0, -0.1, -0.3), Vector3.new(1.1, 1.2, 1.1), C.red,
				{ shape = Enum.PartType.Ball, collide = false, emit = "Indicator" })
			-- Parlaklık 0: istemci (MapLife) yakıp söndürüyor
			K.light(lamp, C.red, 14, 0)
		end

		for gi, gx in gaps do
			for _, back in { true, false } do
				local wallZ = if back then hallMinZ else hallMaxZ
				local inward = if back then 1 else -1
				local facing = Vector3.new(0, 0, inward)
				-- Ortadaki boşlukta kasa yığını; yanlardakinde vent var (aşağıda)
				if gi == math.ceil(#gaps / 2) then
					local base = Vector3.new(gx - 4, 2.5, wallZ + inward * 3.2)
					crate(CFrame.new(base), 5)
					crate(CFrame.new(base + Vector3.new(5.4, -0.6, 0.4)) * CFrame.Angles(0, math.rad(12), 0), 3.8)
					crate(CFrame.new(base + Vector3.new(0.3, 4.3, 0)) * CFrame.Angles(0, math.rad(-18), 0), 3.6)
				end
				-- Ön duvarda ek oda kapısı olan koridorlarda lamba kapının yerine düşerdi
				local hasDoor = not back and table.find(M.ANNEX_X or {}, gx) ~= nil
				if not hasDoor then
					beacon(Vector3.new(gx, 11, wallZ + inward * 0.4), facing)
				end
			end
		end

		-- ─── Vent ağı ────────────────────────────────────────────────────────

		--[[
			Yeni kapaklar landmarks'ın kurduğu kapağın BİREBİR kopyası: parça
			parça yeniden yazmak yerine ilk kapağı buluyor ve taşıyoruz. Stil
			tek yerde kalıyor.
		]]
		local vents = K.root:FindFirstChild("Vents")
		local sample: { BasePart } = {}
		local sampleCenter: Vector3? = nil
		if vents then
			for _, d in vents:GetChildren() do
				if d:IsA("BasePart") and d.Name == "VentFrame" then
					sampleCenter = Vector3.new(d.Position.X, 0, d.Position.Z)
					break
				end
			end
			if sampleCenter then
				for _, d in vents:GetChildren() do
					if d:IsA("BasePart") and (Vector3.new(d.Position.X, 0, d.Position.Z) - sampleCenter).Magnitude < 5 then
						table.insert(sample, d)
					end
				end
			end
		end

		local ventFolder = K.folder("VentNet", root)

		local function ventCopy(center: Vector3)
			if not sampleCenter then
				return
			end
			for _, part in sample do
				local copy = part:Clone()
				copy.CFrame = part.CFrame + (center - sampleCenter)
				copy.Parent = ventFolder
			end
		end

		-- Pad: görünmez, promptun bağlandığı ve varış noktası olan parça
		local function pad(center: Vector3, pair: string)
			local p = K.box(ventFolder, "VentPad", center.X, 1.2, center.Z, 5, 2, 5, C.shadow,
				{ collide = false, transparency = 1 })
			p.CanQuery = false
			p.CastShadow = false
			p:SetAttribute("VentPair", pair)
		end

		-- Mevcut iki kapak (landmarks): batı-arka ve doğu-ön köşeler
		local existing: { Vector3 } = {}
		if vents then
			for _, d in vents:GetChildren() do
				if d:IsA("BasePart") and d.Name == "VentFrame" then
					table.insert(existing, Vector3.new(d.Position.X, 0, d.Position.Z))
				end
			end
		end
		table.sort(existing, function(a, b)
			return a.X < b.X
		end)

		--[[
			Eşler çapraz: kapak seni haritanın öbür ucuna atıyor. Böylece
			her üssün yakınında bir kapak var ve hiçbir üs ventle diğerlerinden
			belirgin şekilde daha erişilebilir değil.
		]]
		if #existing >= 2 then
			pad(existing[1], "A")
			pad(existing[#existing], "A")

			-- Öbür köşeler: mevcutların koridor eksenine göre aynası
			local westMirror = Vector3.new(existing[1].X, 0, 2 * corridorZ - existing[1].Z)
			local eastMirror = Vector3.new(existing[#existing].X, 0, 2 * corridorZ - existing[#existing].Z)
			ventCopy(westMirror)
			ventCopy(eastMirror)
			pad(westMirror, "B")
			pad(eastMirror, "B")
		end

		-- Yan boşluklar: arka-sol ↔ ön-sağ, arka-sağ ↔ ön-sol
		if #gaps >= 3 then
			local left, right = gaps[1] + 6, gaps[#gaps] - 6
			local backZ, frontZ = hallMinZ + 9, hallMaxZ - 9
			-- Ön duvarda bu koridorların ucunda ek oda kapısı var (annex):
			-- kapak kapının önüne değil, yanına
			local fLeft, fRight = gaps[1] + 12, gaps[#gaps] - 12
			local spots = {
				{ Vector3.new(left, 0, backZ), "C" }, { Vector3.new(fRight, 0, frontZ), "C" },
				{ Vector3.new(right, 0, backZ), "D" }, { Vector3.new(fLeft, 0, frontZ), "D" },
			}
			for _, s in spots do
				ventCopy(s[1])
				pad(s[1], s[2])
			end
		end

		-- ─── Gölgeler ────────────────────────────────────────────────────────

		local NO_SHADOW_FOLDERS = { Ceiling = true, Floor = true }
		local turnedOff = 0
		for _, d in K.root:GetDescendants() do
			if not d:IsA("BasePart") or not d.CastShadow then
				continue
			end
			local top = d
			while top.Parent and top.Parent ~= K.root do
				top = top.Parent :: any
			end
			local small = math.max(d.Size.X, d.Size.Y, d.Size.Z) < 3
			local flat = d.Size.Y <= 0.6
			if NO_SHADOW_FOLDERS[top.Name] or small or flat or d.Material == Enum.Material.Glass then
				d.CastShadow = false
				turnedOff += 1
			end
		end
		print(string.format("  [polish] gölge kapatılan parça: %d", turnedOff))
	end,
}
