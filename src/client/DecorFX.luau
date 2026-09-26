--!strict
-- Dekordaki hareketli parçalar: dönen radar, nabız gibi atan uyarı lambaları.
--
-- İstemcide çalışıyor çünkü tamamen görsel: sunucunun bunu bilmesine gerek yok,
-- ağ trafiği üretmiyor ve her oyuncuda kendi karesinde akıcı dönüyor.
--
-- Hangi parçanın nasıl hareket edeceğini parçanın kendi nitelikleri söylüyor
-- (SpinSpeed, PulsePeriod). Böylece dekora yeni bir hareketli parça eklemek
-- için burayı değiştirmek gerekmiyor — build_decor'da niteliği koymak yeterli.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WheelSpin = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WheelSpin"))

local DecorFX = {}

--[[
	═══ PERFORMANS ═════════════════════════════════════════════════════════

	Haritada yüzlerce hareketli parça var ve eskiden HEPSİ her karede
	taşınıyordu — oyuncu istasyonun öbür ucundayken lobideki çarkın
	dilimleri de. Anchored parçanın CFrame'ini yazmak motorun uzamsal
	yapısını güncelletiyor; istemci ölçümünde karede 464 parça taşınıyordu.

	  - Uzaklığa göre sıklık: kameraya NEAR_RADIUS içindeki parça her
	    karede, MID_RADIUS içindeki 3 karede bir, daha uzağı 12 karede bir
	    yazılıyor. Tamamen dondurmak olmazdı — salon açık, 250 stud ötedeki
	    radar da görünüyor; uzakta 20 fps'lik dönüş fark edilmiyor. Konum
	    saatten hesaplandığı için seyrek yazmak sıçrama yapmıyor.
	  - Toplu yazma: kalanlar tek workspace:BulkMoveTo çağrısıyla; tek tek
	    CFrame yazmaktan çok daha ucuz.
	  - Lambanın ışığı kayıtta bir kez bulunuyor (eskiden her karede
	    FindFirstChildOfClass).
]]
local NEAR_RADIUS = 150
local MID_RADIUS = 400

-- center/axisVec verilmişse ortak bir eksen etrafında döner (çarkın dilimleri).
-- wheel: şans çarkının modeli — açısı sunucu saatinden (shared/WheelSpin)
type Spinner = { part: BasePart, speed: number, base: CFrame, axis: string, center: Vector3?, axisVec: Vector3?, angle: number?, wheel: Instance? }
type Pulser = { part: BasePart, period: number, phase: number, light: PointLight? }
type Drifter = { model: Model, speed: number, range: number, base: CFrame }
-- Bant çıtaları gibi tek parça kaydırmalar için: Model yaratmaya değmiyor
type Slider = { part: BasePart, speed: number, range: number, phase: number, base: CFrame }
-- Kuluçkadaki yumurtalar gibi yerinde süzülenler: aşağı-yukarı + hafif sallanma
-- wobble: sallanma açısı (derece); 0 ise yalnızca yukarı-aşağı (MedBay tarama halkası)
type Bobber = { part: BasePart, height: number, period: number, phase: number, wobble: number, base: CFrame }

export type FX = {
	Stop: () -> (),
}

function DecorFX.Start(): FX
	local spinners: { Spinner } = {}
	local pulsers: { Pulser } = {}
	local drifters: { Drifter } = {}
	local sliders: { Slider } = {}
	local bobbers: { Bobber } = {}

	--[[
		Hareketli parçalar tek bir klasörde değil; hangi niteliği taşıyorsa
		ona göre davranıyor. Parça SONRADAN da gelebilir (yerleşimde
		StreamingEnabled açık): eskiden yalnızca açılış anında taranıyordu ve
		o an henüz gelmemiş çark, kapsül, alev hiç hareket etmiyordu.
	]]
	local registered: { [Instance]: boolean } = {}
	local function register(obj: Instance)
		if registered[obj] then
			return
		end
		registered[obj] = true
		if obj:IsA("BasePart") then
			local speed = obj:GetAttribute("SpinSpeed")
			if typeof(speed) == "number" then
				--[[
					Dönüş ekseni niteliğe bağlı. Radar yatay döner (Y), dik
					duran çark ekrana bakan eksende döner (Z). Varsayılan Y,
					çünkü çoğu şey yataydır.
				]]
				local axis = obj:GetAttribute("SpinAxis")
				table.insert(spinners, {
					part = obj,
					speed = speed,
					base = obj.CFrame,
					axis = if typeof(axis) == "string" then axis else "Y",
					-- Ortak eksen (çark): parçalar kendi merkezinde değil göbekte dönüyor
					center = if typeof(obj:GetAttribute("SpinCenter")) == "Vector3" then obj:GetAttribute("SpinCenter") else nil,
					axisVec = if typeof(obj:GetAttribute("SpinAxisVec")) == "Vector3" then (obj:GetAttribute("SpinAxisVec") :: Vector3).Unit else nil,
					wheel = if obj:GetAttribute("SpinCenter") ~= nil then obj:FindFirstAncestor("Wheel") else nil,
				})
			end

			local period = obj:GetAttribute("PulsePeriod")
			if typeof(period) == "number" and period > 0 then
				-- Faz kaydırması: hepsi aynı anda yanıp sönerse yapay duruyor
				table.insert(pulsers, {
					part = obj, period = period, phase = #pulsers * 0.37,
					light = obj:FindFirstChildOfClass("PointLight"),
				})
			end

			-- Bant çıtası: kendi ekseninde değil, bir hat boyunca kayıyor
			-- Kuluçka yumurtaları (Hatchery.EggN) EggStyle'da: her birinin kendi animasyonu var
			local isHatchEgg = string.match(obj.Name, "^Egg%d+$") ~= nil
				and obj.Parent ~= nil and obj.Parent.Name == "Hatchery"
			local bob = obj:GetAttribute("BobHeight")
			local bobPeriod = obj:GetAttribute("BobPeriod")
			if not isHatchEgg and typeof(bob) == "number" and typeof(bobPeriod) == "number" and bobPeriod > 0 then
				table.insert(bobbers, {
					part = obj,
					height = bob,
					period = bobPeriod,
					-- Yan yana yumurtalar aynı anda inip kalkmasın
					phase = #bobbers * 0.9,
					wobble = if typeof(obj:GetAttribute("BobWobble")) == "number" then obj:GetAttribute("BobWobble") else 4,
					base = obj.CFrame,
				})
			end

			--[[
				Konveyör çıtaları (BeltSlat) burada DEĞİL, ConveyorFX'te:
				hızları sabit değil, üssün bant saatine bağlı ve bandın
				üstündeki karakterlerle birlikte çiziliyorlar.
			]]
			local slide = obj:GetAttribute("SlideSpeed")
			local slideRange = obj:GetAttribute("SlideRange")
			if obj.Name ~= "BeltSlat" and typeof(slide) == "number" and typeof(slideRange) == "number" and slideRange > 0 then
				local phase = obj:GetAttribute("SlidePhase")
				table.insert(sliders, {
					part = obj,
					speed = slide,
					range = slideRange,
					phase = if typeof(phase) == "number" then phase else 0,
					base = obj.CFrame,
				})
			end

		elseif obj:IsA("Model") then
			local drift = obj:GetAttribute("DriftSpeed")
			local range = obj:GetAttribute("DriftRange")
			if typeof(drift) == "number" and typeof(range) == "number" then
				-- Model parça parça gelebilir: gövdesi oturunca kaydet
				task.defer(function()
					if obj.PrimaryPart then
						table.insert(drifters, {
							model = obj,
							speed = drift,
							range = range,
							base = obj:GetPivot(),
						})
					end
				end)
			end
		end
	end

	-- Dekoru beklemek çekirdek HUD'u bekletmesin: ayrı görevde
	local added: RBXScriptConnection? = nil
	task.spawn(function()
		local decor = workspace:FindFirstChild("Decor") or workspace:WaitForChild("Decor", 30)
		if not decor then
			return
		end
		added = decor.DescendantAdded:Connect(register)
		for _, obj in decor:GetDescendants() do
			register(obj)
		end
	end)

	local elapsed = 0
	-- Toplu yazma tamponları: her karede yeniden kullanılıyor (çöp üretmesin)
	local moveParts: { BasePart } = {}
	local moveCFrames: { CFrame } = {}
	local function queue(part: BasePart, cf: CFrame)
		local n = #moveParts + 1
		moveParts[n] = part
		moveCFrames[n] = cf
	end

	local frameNo = 0
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		frameNo += 1
		local cam = workspace.CurrentCamera.CFrame.Position
		local midTurn = frameNo % 3 == 0
		local farTurn = frameNo % 12 == 0
		-- Bu karede bu konumdaki parça yazılmalı mı (uzaklığa göre sıklık)
		local function near(pos: Vector3): boolean
			local d = (pos - cam).Magnitude
			if d <= NEAR_RADIUS then
				return true
			elseif d <= MID_RADIUS then
				return midTurn
			end
			return farTurn
		end
		table.clear(moveParts)
		table.clear(moveCFrames)

		for _, s in spinners do
			--[[
				Şans çarkı: açı sunucu saatinden, herkeste aynı; çevirmede
				kazanılan dilimde duruyor (WheelSpin). Diğerleri birikimli
				açıyla — uzaktayken de ilerliyor, yalnızca yazılmıyor.
			]]
			if s.wheel then
				s.angle = WheelSpin.Angle(s.wheel, workspace:GetServerTimeNow(), s.speed)
			else
				local live = s.part:GetAttribute("SpinSpeed")
				local speed = if typeof(live) == "number" then live else s.speed
				s.angle = (s.angle or 0) + speed * dt
			end
			if not near(s.center or s.base.Position) then
				continue
			end
			local a = math.rad(s.angle)
			if s.center and s.axisVec then
				local pivot = CFrame.new(s.center)
				queue(s.part, pivot * CFrame.fromAxisAngle(s.axisVec, a) * pivot:Inverse() * s.base)
			else
				local rot = if s.axis == "Z" then CFrame.Angles(0, 0, a)
					elseif s.axis == "X" then CFrame.Angles(a, 0, 0)
					else CFrame.Angles(0, a, 0)
				queue(s.part, s.base * rot)
			end
		end

		for _, p in pulsers do
			if not near(p.part.Position) then
				continue
			end
			local t = (elapsed / p.period + p.phase) % 1
			-- Keskin parlama, yavaş sönme: gerçek uyarı lambası böyle davranır
			local intensity = math.clamp(1 - t * 1.8, 0, 1)
			p.part.Transparency = 0.15 + (1 - intensity) * 0.55
			if p.light then
				p.light.Brightness = 0.35 + intensity * 2.2
			end
		end

		--[[
			Süzülen nesneler x ekseninde ilerliyor, menzilin sonuna gelince
			başa dönüyor. Modulo ile hesaplandığı için birikmiş hata olmuyor
			ve nesne her turda tam aynı yoldan geçiyor.
		]]
		for _, d in drifters do
			local travelled = (d.speed * elapsed) % d.range
			local cf = d.base * CFrame.new(travelled, 0, 0)
			-- Uzaydaki süzülenler geniş bir alanda; yolun ortası yakınsa çiz
			if near(cf.Position) or near(d.base.Position) then
				d.model:PivotTo(cf)
			end
		end

		--[[
			Bant çıtaları. Parçanın kendi yerel x ekseninde kayıyorlar, yani
			konveyör hangi yöne dönükse çıta da o yöne akıyor — dünya eksenine
			bağlamak üsler döndüğünde ters yöne akmalarına yol açardı.
		]]
		--[[
			Yol hep [0, range] içinde; hız negatifse aynı yol ters yönde
			(taban noktasından -x'e). Eskiden negatif hızda parça tabandan
			+x'e bir menzil boyu taşıyordu.
		]]
		for _, s in sliders do
			if not near(s.base.Position) then
				continue
			end
			local travelled = (s.phase + math.abs(s.speed) * elapsed) % s.range
			local sign = if s.speed < 0 then -1 else 1
			queue(s.part, s.base * CFrame.new(travelled * sign, 0, 0))
		end

		--[[
			Süzülme: sinüsle yukarı-aşağı ve çok hafif sallanma. Sallanma
			olmasa yumurta asansör gibi dümdüz iniş çıkış yapıyordu; birkaç
			derecelik eğilme onu "canlı bir şey" yapıyor.
		]]
		for _, b in bobbers do
			if not near(b.base.Position) then
				continue
			end
			local t = elapsed * (2 * math.pi) / b.period + b.phase
			-- Yükseklik DÜNYA yukarısında: dik duran (döndürülmüş) silindirde
			-- yerel Y yatay kalıyordu ve halka yana kayıyordu
			queue(b.part, (b.base + Vector3.new(0, math.sin(t) * b.height, 0))
				* CFrame.Angles(0, 0, math.rad(math.sin(t * 0.5) * b.wobble)))
		end

		if #moveParts > 0 then
			workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)

	return {
		Stop = function()
			connection:Disconnect()
			if added then
				added:Disconnect()
			end
		end,
	}
end

return DecorFX
