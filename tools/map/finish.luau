--!strict
--[[
	Son rötuşlar: ışık ayarları, varsayılan doğuş noktası ve Baseplate.

	IŞIK: Among Us parlak, pastel bir oyun. Kapalı tavanlı istasyonda güneş
	içeri girmediği için ortam ışığı (Ambient) sahnenin asıl aydınlığı;
	armatürler (SurfaceLight) üstüne yumuşak ışık havuzları ekliyor. Renk
	düzeltmesi doygunluğu hafif artırıyor — çizgi film tonu.
]]

return {
	folders = {},

	build = function(K: any)
		local M = K.M
		local Lighting = game:GetService("Lighting")

		Lighting.Ambient = Color3.fromRGB(128, 134, 150)
		Lighting.OutdoorAmbient = Color3.fromRGB(140, 148, 168)
		Lighting.Brightness = 2.4
		Lighting.ClockTime = 14.5
		Lighting.EnvironmentDiffuseScale = 0.6
		Lighting.EnvironmentSpecularScale = 0.4
		Lighting.ExposureCompensation = 0.15
		Lighting.GlobalShadows = true

		local cc = Lighting:FindFirstChild("SkeldGrade")
		if not cc then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "SkeldGrade"
			cc.Parent = Lighting
		end
		local grade = cc :: ColorCorrectionEffect
		grade.Saturation = 0.12
		grade.Contrast = 0.06
		grade.Brightness = 0.02
		grade.TintColor = Color3.fromRGB(255, 252, 248)

		local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
		if bloom then
			-- 0.7 / 1.6'da nadir karakterlerin neon sergileri kareyi yıkıyordu
			bloom.Intensity = 0.45
			bloom.Size = 22
			bloom.Threshold = 2.0
		end

		-- Uzayda sis olmaz: atmosfer uzaktaki gezegenleri griye boğuyordu
		local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmo then
			atmo.Density = 0
			atmo.Haze = 0
			atmo.Glare = 0
		end

		-- Derinlik bulanıklığı uzaktaki tabelaları okunmaz yapıyordu
		local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		if dof then
			dof.Enabled = false
		end

		--[[
			Varsayılan doğuş noktası: oyuncular kendi üslerinde doğuyor
			(PlotService SpawnPad), bunun işlevi yok. Studio boş yerleşimde
			yeniden yarattığı için silinmiyor; kapatılıp gövdenin altına
			saklanıyor.
		]]
		local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
		if spawn then
			spawn.Enabled = false
			spawn.Transparency = 1
			spawn.CanCollide = false
			spawn.CFrame = CFrame.new(M.centerX, -40, M.centerZ)
			for _, d in spawn:GetChildren() do
				if d:IsA("Decal") or d:IsA("Texture") then
					d:Destroy()
				end
			end
		end

		-- Baseplate: gövdenin altında, bir şey düşerse yakalasın ama görünmesin
		local bp = workspace:FindFirstChild("Baseplate")
		if bp and bp:IsA("BasePart") then
			bp.Size = Vector3.new(M.X1 - M.X0 - 120, 4, M.Z1 - M.Z0 - 100)
			bp.CFrame = CFrame.new(M.centerX, -30, M.centerZ)
			bp.Color = K.C.hullOut
			bp.Material = Enum.Material.SmoothPlastic
			bp.Anchored = true
			bp.Transparency = 0
		end
	end,
}
