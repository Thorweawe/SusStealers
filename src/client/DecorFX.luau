--!strict
-- Dekordaki hareketli parçalar: dönen radar, nabız gibi atan uyarı lambaları.
--
-- İstemcide çalışıyor çünkü tamamen görsel: sunucunun bunu bilmesine gerek yok,
-- ağ trafiği üretmiyor ve her oyuncuda kendi karesinde akıcı dönüyor.
--
-- Hangi parçanın nasıl hareket edeceğini parçanın kendi nitelikleri söylüyor
-- (SpinSpeed, PulsePeriod). Böylece dekora yeni bir hareketli parça eklemek
-- için burayı değiştirmek gerekmiyor — build_decor'da niteliği koymak yeterli.

local RunService = game:GetService("RunService")

local DecorFX = {}

-- center/axisVec verilmişse ortak bir eksen etrafında döner (çarkın dilimleri)
type Spinner = { part: BasePart, speed: number, base: CFrame, axis: string, center: Vector3?, axisVec: Vector3?, angle: number? }
type Pulser = { part: BasePart, period: number, phase: number }
type Drifter = { model: Model, speed: number, range: number, base: CFrame }
-- Bant çıtaları gibi tek parça kaydırmalar için: Model yaratmaya değmiyor
type Slider = { part: BasePart, speed: number, range: number, base: CFrame }
-- Kuluçkadaki yumurtalar gibi yerinde süzülenler: aşağı-yukarı + hafif sallanma
type Bobber = { part: BasePart, height: number, period: number, phase: number, base: CFrame }

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
				})
			end

			local period = obj:GetAttribute("PulsePeriod")
			if typeof(period) == "number" and period > 0 then
				-- Faz kaydırması: hepsi aynı anda yanıp sönerse yapay duruyor
				table.insert(pulsers, { part = obj, period = period, phase = #pulsers * 0.37 })
			end

			-- Bant çıtası: kendi ekseninde değil, bir hat boyunca kayıyor
			local bob = obj:GetAttribute("BobHeight")
			local bobPeriod = obj:GetAttribute("BobPeriod")
			if typeof(bob) == "number" and typeof(bobPeriod) == "number" and bobPeriod > 0 then
				table.insert(bobbers, {
					part = obj,
					height = bob,
					period = bobPeriod,
					-- Yan yana yumurtalar aynı anda inip kalkmasın
					phase = #bobbers * 0.9,
					base = obj.CFrame,
				})
			end

			local slide = obj:GetAttribute("SlideSpeed")
			local slideRange = obj:GetAttribute("SlideRange")
			if typeof(slide) == "number" and typeof(slideRange) == "number" and slideRange > 0 then
				table.insert(sliders, {
					part = obj,
					speed = slide,
					range = slideRange,
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
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt

		for _, s in spinners do
			--[[
				Hız her karede okunuyor: SpinService çevirme sırasında
				niteliği 14 katına çıkarıyor. Açı birikimli tutuluyor ki hız
				değişince parça sıçramasın.
			]]
			local live = s.part:GetAttribute("SpinSpeed")
			local speed = if typeof(live) == "number" then live else s.speed
			s.angle = (s.angle or 0) + speed * dt
			local a = math.rad(s.angle)
			if s.center and s.axisVec then
				local pivot = CFrame.new(s.center)
				s.part.CFrame = pivot * CFrame.fromAxisAngle(s.axisVec, a) * pivot:Inverse() * s.base
			else
				local rot = if s.axis == "Z" then CFrame.Angles(0, 0, a)
					elseif s.axis == "X" then CFrame.Angles(a, 0, 0)
					else CFrame.Angles(0, a, 0)
				s.part.CFrame = s.base * rot
			end
		end

		for _, p in pulsers do
			local t = (elapsed / p.period + p.phase) % 1
			-- Keskin parlama, yavaş sönme: gerçek uyarı lambası böyle davranır
			local intensity = math.clamp(1 - t * 1.8, 0, 1)
			p.part.Transparency = 0.15 + (1 - intensity) * 0.55

			local light = p.part:FindFirstChildOfClass("PointLight")
			if light then
				light.Brightness = 0.35 + intensity * 2.2
			end
		end

		--[[
			Süzülen nesneler x ekseninde ilerliyor, menzilin sonuna gelince
			başa dönüyor. Modulo ile hesaplandığı için birikmiş hata olmuyor
			ve nesne her turda tam aynı yoldan geçiyor.
		]]
		for _, d in drifters do
			local travelled = (d.speed * elapsed) % d.range
			d.model:PivotTo(d.base * CFrame.new(travelled, 0, 0))
		end

		--[[
			Bant çıtaları. Parçanın kendi yerel x ekseninde kayıyorlar, yani
			konveyör hangi yöne dönükse çıta da o yöne akıyor — dünya eksenine
			bağlamak üsler döndüğünde ters yöne akmalarına yol açardı.
		]]
		for _, s in sliders do
			local travelled = (s.speed * elapsed) % s.range
			s.part.CFrame = s.base * CFrame.new(travelled, 0, 0)
		end

		--[[
			Süzülme: sinüsle yukarı-aşağı ve çok hafif sallanma. Sallanma
			olmasa yumurta asansör gibi dümdüz iniş çıkış yapıyordu; birkaç
			derecelik eğilme onu "canlı bir şey" yapıyor.
		]]
		for _, b in bobbers do
			local t = elapsed * (2 * math.pi) / b.period + b.phase
			b.part.CFrame = b.base
				* CFrame.new(0, math.sin(t) * b.height, 0)
				* CFrame.Angles(0, 0, math.rad(math.sin(t * 0.5) * 4))
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
