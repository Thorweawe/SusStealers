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

type Spinner = { part: BasePart, speed: number, base: CFrame, axis: string }
type Pulser = { part: BasePart, period: number, phase: number }
type Drifter = { model: Model, speed: number, range: number, base: CFrame }
-- Bant çıtaları gibi tek parça kaydırmalar için: Model yaratmaya değmiyor
type Slider = { part: BasePart, speed: number, range: number, base: CFrame }

export type FX = {
	Stop: () -> (),
}

function DecorFX.Start(): FX
	local spinners: { Spinner } = {}
	local pulsers: { Pulser } = {}
	local drifters: { Drifter } = {}
	local sliders: { Slider } = {}

	local decor = workspace:FindFirstChild("Decor")
	if not decor then
		-- Dekor henüz kurulmamış olabilir; sessizce çık
		return { Stop = function() end }
	end

	-- Bütün dekoru tarıyoruz: hareketli parçalar tek bir klasörde değil,
	-- hangi niteliği taşıyorsa ona göre davranıyor.
	for _, obj in decor:GetDescendants() do
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
				})
			end

			local period = obj:GetAttribute("PulsePeriod")
			if typeof(period) == "number" and period > 0 then
				-- Faz kaydırması: hepsi aynı anda yanıp sönerse yapay duruyor
				table.insert(pulsers, { part = obj, period = period, phase = #pulsers * 0.37 })
			end

			-- Bant çıtası: kendi ekseninde değil, bir hat boyunca kayıyor
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
			if typeof(drift) == "number" and typeof(range) == "number" and obj.PrimaryPart then
				table.insert(drifters, {
					model = obj,
					speed = drift,
					range = range,
					base = obj:GetPivot(),
				})
			end
		end
	end

	local elapsed = 0
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt

		for _, s in spinners do
			local a = math.rad(s.speed * elapsed)
			local rot = if s.axis == "Z" then CFrame.Angles(0, 0, a)
				elseif s.axis == "X" then CFrame.Angles(a, 0, 0)
				else CFrame.Angles(0, a, 0)
			s.part.CFrame = s.base * rot
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
	end)

	return {
		Stop = function()
			connection:Disconnect()
		end,
	}
end

return DecorFX
