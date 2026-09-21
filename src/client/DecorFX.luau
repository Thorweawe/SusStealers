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

type Spinner = { part: BasePart, speed: number, base: CFrame }
type Pulser = { part: BasePart, period: number, phase: number }

export type FX = {
	Stop: () -> (),
}

function DecorFX.Start(): FX
	local spinners: { Spinner } = {}
	local pulsers: { Pulser } = {}

	local decor = workspace:FindFirstChild("Decor")
	local animated = decor and decor:FindFirstChild("Animated")
	if not animated then
		-- Dekor henüz kurulmamış olabilir; sessizce çık
		return { Stop = function() end }
	end

	for _, part in animated:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end

		local speed = part:GetAttribute("SpinSpeed")
		if typeof(speed) == "number" then
			table.insert(spinners, { part = part, speed = speed, base = part.CFrame })
		end

		local period = part:GetAttribute("PulsePeriod")
		if typeof(period) == "number" and period > 0 then
			-- Faz kaydırması: hepsi aynı anda yanıp sönerse yapay duruyor
			table.insert(pulsers, { part = part, period = period, phase = #pulsers * 0.37 })
		end
	end

	local elapsed = 0
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt

		for _, s in spinners do
			s.part.CFrame = s.base * CFrame.Angles(0, math.rad(s.speed * elapsed), 0)
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
	end)

	return {
		Stop = function()
			connection:Disconnect()
		end,
	}
end

return DecorFX
