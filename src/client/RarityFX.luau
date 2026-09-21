--!strict
-- Kaidedeki karakterin nadirliğine göre görsel vurgu.
--
-- Oyunun bütün amacı pahalı karakter toplamak ama Amogus Prime ile Red
-- Crewmate kaidede aynı görünüyordu. Hedef görünmezse hedef değildir.
--
-- Etki basamaklı: ucuzlar sade kalıyor, Rare'den itibaren ışık sütunu ve
-- kademeye ÖZEL bir sergi yapısı geliyor (altıgen çerçeve, cam vitrin,
-- kanat, mızraklı kafes, obsidyen levha). Böylece hem uzaktan "orada
-- değerli bir şey var" okunuyor, hem de hangi kademe olduğu şekilden
-- anlaşılıyor.
--
-- Tamamen istemci tarafı. Her oyuncu kendi makinesinde üretiyor, ağda
-- hiçbir şey taşınmıyor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local RarityFX = {}

local FX_NAME = "RarityFX"

--[[
	Kademeler. order 1-2 (Common, Uncommon) kasıtlı olarak boş: her kaide
	ışıldarsa hiçbiri öne çıkmaz. Vurgu ancak zıtlıkla çalışıyor.
]]
local function tierOf(order: number): { beam: number, particles: boolean }
	if order <= 2 then
		return { beam = 0, particles = false }
	elseif order == 3 then
		return { beam = 7, particles = false }      -- Rare
	elseif order == 4 then
		return { beam = 10, particles = false }     -- Epic
	elseif order == 5 then
		return { beam = 14, particles = true }      -- Legendary
	elseif order == 6 then
		return { beam = 18, particles = true }      -- Mythic
	end
	return { beam = 24, particles = true }          -- Secret
end

--[[
	Karaktere özel süslemeler. Nadirlik kademesi "ne kadar değerli" diyor,
	bu tablo "bu ne" diyor. Reactor Meltdown ile Ejected Into Space aynı
	kademede ama biri erimiş bir reaktör, diğeri uzaya fırlatılmış bir ceset —
	kaidede de öyle görünmeliler.

	Her giriş isteğe bağlı: tanımlanmayan karakter sadece nadirlik vurgusunu
	alır, hata vermez.
]]
type Accent = {
	tint: Color3?,          -- efekt rengini bastır
	halo: boolean?,         -- baş üstünde halka
	spikes: number?,        -- çevresine dikey çubuklar
	smoke: boolean?,        -- yukarı süzülen ağır parçacık
	grate: boolean?,        -- altında havalandırma kapağı
	scan: boolean?,         -- aşağı yukarı süzülen tarama çizgisi
	pulse: boolean?,        -- nabız gibi atan zemin halkası
}

local ACCENTS: { [string]: Accent } = {
	Guardian = { halo = true, tint = Color3.fromRGB(235, 235, 255) },
	Janitor = { grate = true, tint = Color3.fromRGB(150, 110, 60) },
	VentCrawler = { grate = true },
	MedbayScan = { scan = true, tint = Color3.fromRGB(90, 200, 255) },
	Sheriff = { spikes = 5, tint = Color3.fromRGB(218, 165, 32) },
	Impostor = { spikes = 4, tint = Color3.fromRGB(190, 20, 20) },
	Reactor = { smoke = true, tint = Color3.fromRGB(255, 120, 20), pulse = true },
	O2Sabotage = { scan = true, pulse = true, tint = Color3.fromRGB(120, 220, 255) },
	Emergency = { pulse = true, tint = Color3.fromRGB(255, 60, 60) },
	Ejected = { smoke = true, tint = Color3.fromRGB(60, 60, 140) },
	Polus = { smoke = true, tint = Color3.fromRGB(190, 210, 225) },
	TheSkeld = { spikes = 2, tint = Color3.fromRGB(150, 165, 185) },
	Airship = { spikes = 3, smoke = true, tint = Color3.fromRGB(150, 118, 70) },
	DoubleImp = { spikes = 6, tint = Color3.fromRGB(220, 10, 70) },
	TripleImp = { spikes = 9, smoke = true, tint = Color3.fromRGB(150, 0, 45) },
	Jester = { halo = true, spikes = 6, pulse = true, tint = Color3.fromRGB(238, 84, 187) },
	AmogusPrime = { halo = true, spikes = 8, smoke = true, pulse = true },
	TheCrewmate = { halo = true, scan = true, smoke = true, pulse = true, tint = Color3.fromRGB(215, 224, 240) },
}

export type FX = {
	Update: () -> (),
	Stop: () -> (),
}


function RarityFX.Create(): FX
	-- Kayan tarama çizgileri ve nabız atan halkalar. Ayrı listeler, çünkü
	-- biri dikey kayıyor diğeri boyut/saydamlık değiştiriyor.
	local scanners: { { part: BasePart, base: number } } = {}
	local pulseRings: { { part: BasePart, seed: number, base: CFrame } } = {}

	--[[ Ebeveyni gitmiş parçaları listelerden düşürür. Efekt silindiğinde
	     tek tek listeleri taramak yerine burada toplu temizleniyor. ]]
	local function prune<T>(list: { T }, get: (T) -> BasePart)
		for i = #list, 1, -1 do
			if not get(list[i]).Parent then
				table.remove(list, i)
			end
		end
	end

	local function clear(podium: BasePart)
		local old = podium:FindFirstChild(FX_NAME)
		if old then
			old:Destroy()
		end
	end

	local function build(podium: BasePart, unitId: string, mutationId: string?)
		local def = Config.GetUnit(unitId)
		if not def then
			return
		end

		local rarity = Config.Rarities[def.rarity]
		if not rarity then
			return
		end

		local tier = tierOf(rarity.order)
		if tier.beam <= 0 then
			return -- ucuz karakter, vurgu yok
		end

		local color = rarity.color
		local mutation = Config.GetMutation(mutationId)
		if mutation and mutation.tint then
			-- Mutasyonlu karakter kendi rengini bastırsın: zaten özel
			color = color:Lerp(mutation.tint, 0.6)
		end

		local holder = Instance.new("Folder")
		holder.Name = FX_NAME
		holder.Parent = podium

		local top = podium.Position + Vector3.new(0, podium.Size.Y / 2, 0)

		--[[
			Işık sütunu: yukarı doğru incelen ve sönen bir huzme. Tek parça
			yerine üç katman, çünkü tek saydam kutu düz bir levha gibi
			duruyor; katmanlar derinlik veriyor.
		]]
		for layer = 1, 3 do
			local t = layer / 3
			local beam = Instance.new("Part")
			beam.Name = "Beam"
			beam.Size = Vector3.new(5.2 * (1 - t * 0.55), tier.beam * (1 - t * 0.2), 5.2 * (1 - t * 0.55))
			beam.CFrame = CFrame.new(top + Vector3.new(0, beam.Size.Y / 2, 0))
			beam.Color = color
			beam.Material = Enum.Material.Neon
			beam.Transparency = 0.88 + t * 0.06
			beam.Anchored = true
			beam.CanCollide = false
			beam.CanQuery = false
			beam.CanTouch = false
			beam.CastShadow = false
			beam.Parent = holder
		end

		-- Zemin halkası ve ışık
		local base = Instance.new("Part")
		base.Name = "Halo"
		base.Size = Vector3.new(6.4, 0.08, 6.4)
		base.CFrame = CFrame.new(top + Vector3.new(0, 0.06, 0))
		base.Color = color
		base.Material = Enum.Material.Neon
		base.Transparency = 0.25
		base.Anchored = true
		base.CanCollide = false
		base.CanQuery = false
		base.CanTouch = false
		base.CastShadow = false
		base.Parent = holder

		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10 + rarity.order * 2.5
		light.Brightness = 0.8 + rarity.order * 0.25
		light.Parent = base

		--[[
			═══ NADİRLİĞE ÖZEL SERGİ YAPISI ═══════════════════════════════

			Eskiden her üst kademe aynı şeyi alıyordu: kafasının üstünde
			dönen halka(lar). Sadece SAYI değişiyordu — Epic bir, Mythic
			iki, Secret üç. Yani kademeler birbirinden ayırt edilmiyordu,
			sadece "daha çok dönen şey" oluyordu. Dönüş de sürekli hareket
			ettiği için gözü yoruyor ve kaidedeki asıl nesneden çalıyordu.

			Artık her kademenin kendi SABİT yapısı var — bir müzede farklı
			değerdeki eserlerin farklı vitrinlerde durması gibi. Hareket yok,
			siluet var; uzaktan hangi kademe olduğu şekilden okunuyor.

			  Rare      altıgen kaide çerçevesi
			  Epic      dört köşeli cam vitrin
			  Legendary iki yandan kanat + önde madalyon
			  Mythic    altı mızraklı kafes, uçları tepede birleşiyor
			  Secret    obsidyen levha + sekiz kıymık, ters yönde aşağı
		]]
		local function piece(name: string, size: Vector3, cf: CFrame, c: Color3, trans: number, mat: Enum.Material?): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.CFrame = cf
			p.Color = c
			p.Material = mat or Enum.Material.Neon
			p.Transparency = trans
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = holder
			return p
		end

		local dark = color:Lerp(Color3.new(0, 0, 0), 0.55)

		if rarity.order == 3 then
			-- Rare: altıgen kaide çerçevesi. Altı kenar parçası + köşe topuzları.
			for i = 1, 6 do
				local a = (i - 1) * (math.pi / 3)
				piece("FrameEdge", Vector3.new(3.1, 0.35, 0.5),
					CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.3, 2.7),
					color, 0.2)
				piece("FrameKnob", Vector3.new(0.6, 1.1, 0.6),
					CFrame.new(top) * CFrame.Angles(0, a + math.pi / 6, 0) * CFrame.new(0, 0.7, 3.1),
					dark, 0.1, Enum.Material.Metal)
			end

		elseif rarity.order == 4 then
			-- Epic: cam vitrin. Dört dikme + dört cam yüzey + kapak.
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					piece("CasePost", Vector3.new(0.35, 7, 0.35),
						CFrame.new(top + Vector3.new(sx * 2.9, 3.5, sz * 2.9)),
						dark, 0, Enum.Material.Metal)
				end
			end
			for i = 0, 3 do
				local a = i * (math.pi / 2)
				piece("CaseGlass", Vector3.new(5.8, 7, 0.12),
					CFrame.new(top + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.9),
					color, 0.9, Enum.Material.Glass)
			end
			piece("CaseLid", Vector3.new(6.4, 0.4, 6.4),
				CFrame.new(top + Vector3.new(0, 7.2, 0)), dark, 0.1, Enum.Material.Metal)

		elseif rarity.order == 5 then
			--[[ Legendary: iki yanda yukarı açılan kanat. Her kanat üç
			     dilimden; dıştaki daha uzun ve daha dik — tek parça düz bir
			     levha gibi duruyordu. ]]
			for _, s in { -1, 1 } do
				for i = 1, 3 do
					piece("Wing", Vector3.new(0.4, 1.4 + i * 1.5, 2.6 - i * 0.5),
						CFrame.new(top + Vector3.new(s * (2.6 + i * 0.55), 1.4 + i * 0.8, 0))
							* CFrame.Angles(0, 0, math.rad(-s * (12 + i * 9))),
						color, 0.18)
				end
			end
			-- Önde madalyon
			piece("Medal", Vector3.new(2.4, 2.4, 0.3),
				CFrame.new(top + Vector3.new(0, 1.6, -3.1)), color, 0.1)
			piece("MedalRim", Vector3.new(3.1, 3.1, 0.18),
				CFrame.new(top + Vector3.new(0, 1.6, -3.2)), dark, 0, Enum.Material.Metal)

		elseif rarity.order == 6 then
			--[[ Mythic: altı mızrak. Tabandan çıkıp tepede birleşiyorlar;
			     kafes gibi kapatıyor ama içerisi görünüyor. ]]
			for i = 1, 6 do
				local a = (i - 1) * (math.pi / 3)
				piece("Spear", Vector3.new(0.45, 9.5, 0.45),
					CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(3.4, 4.6, 0)
						* CFrame.Angles(math.rad(13), 0, 0),
					color, 0.15)
				piece("SpearTip", Vector3.new(0.85, 0.85, 0.85),
					CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(2.3, 9.4, 0),
					color, 0)
			end
			piece("Capstone", Vector3.new(1.8, 1.8, 1.8),
				CFrame.new(top + Vector3.new(0, 10.2, 0)) * CFrame.Angles(0, math.rad(45), math.rad(45)),
				color, 0)

		elseif rarity.order >= 7 then
			--[[ Secret: kural bozuluyor. Işık yukarı değil, kaide AŞAĞI
			     doğru açılıyor — altında bir boşluk varmış gibi. Sekiz
			     kıymık dışa doğru saçılmış, hiçbiri simetrik değil. ]]
			piece("VoidSlab", Vector3.new(7.6, 0.3, 7.6),
				CFrame.new(top + Vector3.new(0, 0.2, 0)), Color3.fromRGB(8, 8, 12), 0, Enum.Material.Glass)
			piece("VoidWell", Vector3.new(5.4, 0.2, 5.4),
				CFrame.new(top + Vector3.new(0, 0.32, 0)), Color3.fromRGB(2, 2, 4), 0, Enum.Material.SmoothPlastic)

			for i = 1, 8 do
				local a = (i - 1) * (math.pi / 4) + (i % 3) * 0.19
				local len = 2.6 + (i % 4) * 1.1
				piece("Shard", Vector3.new(0.3, len, 0.3),
					CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(3.6, len / 2 + 0.2, 0)
						* CFrame.Angles(0, 0, math.rad(18 + (i % 3) * 11)),
					Color3.fromRGB(150, 120, 210), 0.25)
			end
		end

		if tier.particles then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Color = ColorSequence.new(color)
			emitter.Size = NumberSequence.new(0.35, 0)
			emitter.Transparency = NumberSequence.new(0.35, 1)
			emitter.Lifetime = NumberRange.new(1.4, 2.4)
			emitter.Rate = 6 + rarity.order * 3
			emitter.Speed = NumberRange.new(1.5, 3.5)
			emitter.SpreadAngle = Vector2.new(22, 22)
			emitter.LightEmission = 1
			emitter.Parent = base
		end

		-- ─── Karaktere özel süsleme ─────────────────────────────────────────

		local accent = ACCENTS[unitId]
		if not accent then
			return
		end

		local tone = accent.tint or color

		local function deco(name: string, size: Vector3, cf: CFrame, c: Color3, trans: number): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.CFrame = cf
			p.Color = c
			p.Material = Enum.Material.Neon
			p.Transparency = trans
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = holder
			return p
		end

		if accent.halo then
			--[[
				Koruyucu Melek: başın üstünde halka. Artık DÖNMÜYOR — gerçek
				bir hale de dönmez, ve dönen her şey kaidedeki asıl nesneden
				dikkat çalıyordu. Sabit ama hafifçe eğik: düz duran halka
				tabak gibi görünüyordu.
			]]
			deco("Halo", Vector3.new(4.2, 0.22, 4.2),
				CFrame.new(top + Vector3.new(0, 5.4, 0)) * CFrame.Angles(math.rad(8), 0, math.rad(5)),
				tone, 0.1)
		end

		if accent.spikes then
			-- Hain ve türevleri: çevresine dikey çubuklar
			for i = 1, accent.spikes do
				local a = (i - 1) * (math.pi * 2 / accent.spikes)
				deco("Spike", Vector3.new(0.3, 3.6, 0.3),
					CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(3.2, 1.8, 0),
					tone, 0.2)
			end
		end

		if accent.grate then
			-- Kanal Sürüngeni: altında havalandırma kapağı
			deco("Grate", Vector3.new(5.4, 0.1, 4.2),
				CFrame.new(top + Vector3.new(0, 0.14, 0)), Color3.fromRGB(50, 58, 70), 0)
			for i = -1, 1 do
				deco("GrateSlat", Vector3.new(4.8, 0.16, 0.5),
					CFrame.new(top + Vector3.new(0, 0.2, i * 1.2)), tone, 0.35)
			end
		end

		if accent.scan then
			--[[
				Revir Tarayıcı: aşağı yukarı süzülen tarama çizgisi. Dönen
				halka listesine katmıyoruz çünkü o dönüyor, bu kayıyor —
				hareketi aşağıdaki döngü yürütüyor.
			]]
			local line = deco("ScanLine", Vector3.new(5.6, 0.14, 5.6),
				CFrame.new(top + Vector3.new(0, 1, 0)), tone, 0.35)
			table.insert(scanners, { part = line, base = top.Y + 0.4 })
		end

		if accent.pulse then
			-- Reaktör / Acil Toplantı: nabız gibi atan zemin halkası
			local ring = deco("PulseRing", Vector3.new(7.4, 0.1, 7.4),
				CFrame.new(top + Vector3.new(0, 0.1, 0)), tone, 0.3)
			table.insert(pulseRings, { part = ring, seed = math.random(), base = ring.CFrame })
		end

		if accent.smoke then
			-- Erime / uzay tozu: ağır, yavaş yükselen parçacık
			local smoke = Instance.new("ParticleEmitter")
			smoke.Color = ColorSequence.new(tone)
			smoke.Size = NumberSequence.new(0.8, 2.6)
			smoke.Transparency = NumberSequence.new(0.65, 1)
			smoke.Lifetime = NumberRange.new(2.6, 4.2)
			smoke.Rate = 5
			smoke.Speed = NumberRange.new(0.6, 1.4)
			smoke.SpreadAngle = Vector2.new(40, 40)
			smoke.LightEmission = 0.4
			smoke.Parent = base
		end
	end

	--[[ Kaidedeki karakter değişince efekti yeniden kur. ]]
	local function refresh(podium: BasePart)
		local unitId = podium:GetAttribute("UnitId")
		local mutationId = podium:GetAttribute("MutationId")

		clear(podium)

		if typeof(unitId) == "string" and unitId ~= "" then
			build(podium, unitId, if typeof(mutationId) == "string" and mutationId ~= "" then mutationId else nil)
		end
	end

	local hooked: { [BasePart]: boolean } = {}

	local function update()
		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			return
		end

		for _, plot in plots:GetChildren() do
			if not plot:IsA("Model") then
				continue
			end

			for _, podium in plot:GetDescendants() do
				if not (podium:IsA("BasePart") and podium.Name == "Podium") then
					continue
				end

				if not hooked[podium] then
					hooked[podium] = true
					podium:GetAttributeChangedSignal("UnitId"):Connect(function()
						refresh(podium)
					end)
					refresh(podium)
				end
			end
		end
	end

	local connection = RunService.RenderStepped:Connect(function()
		local t = os.clock()

		-- Tarama çizgisi: aşağıdan yukarı süzülüp başa dönüyor
		for _, s in scanners do
			if s.part.Parent then
				local h = (t * 1.6) % 5
				s.part.CFrame = CFrame.new(s.part.Position.X, s.base + h, s.part.Position.Z)
				-- Tepeye yaklaşırken sönüyor: sert kesilme olmasın
				s.part.Transparency = 0.3 + (h / 5) * 0.55
			end
		end

		-- Nabız halkası: büyüyüp sönen dalga
		for _, p in pulseRings do
			if p.part.Parent then
				local phase = (t * 0.8 + p.seed) % 1
				local scale = 1 + phase * 0.9
				p.part.Size = Vector3.new(7.4 * scale, 0.1, 7.4 * scale)
				p.part.Transparency = 0.25 + phase * 0.7
			end
		end

		-- Silinmiş efektleri listelerden düşür
		if math.floor(t * 2) % 8 == 0 then
			prune(scanners, function(s)
				return s.part
			end)
			prune(pulseRings, function(p)
				return p.part
			end)
		end
	end)

	return {
		Update = update,
		Stop = function()
			connection:Disconnect()
		end,
	}
end

return RarityFX
