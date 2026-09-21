--!strict
-- Ekran geri bildirimi: renk parlaması ve kamera sarsıntısı.
--
-- Çalınma olayını sadece köşedeki yazıdan öğrenmek yetmiyordu; oyuncu
-- saldırıya uğradığını hissetmeli. Kısa bir kırmızı parlama ve sarsıntı
-- olayı bedensel hale getiriyor.
--
-- Tamamen istemci tarafı ve tamamen görsel: oyun kurallarına dokunmuyor.

local RunService = game:GetService("RunService")

local ScreenFX = {}

export type FX = {
	Flash: (color: Color3, strength: number, duration: number) -> (),
	Shake: (strength: number, duration: number) -> (),
}

local SHAKE_BINDING = "SusStealersShake"

function ScreenFX.Create(screen: ScreenGui): FX
	-- ─── Parlama katmanı ────────────────────────────────────────────────────

	local veil = Instance.new("Frame")
	veil.Name = "ScreenFlash"
	veil.Size = UDim2.fromScale(1, 1)
	veil.Position = UDim2.fromScale(0, 0)
	veil.BackgroundColor3 = Color3.new(1, 1, 1)
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	-- Bütün HUD'un üstünde dursun ama tıklamayı engellemesin
	veil.ZIndex = 100
	veil.Active = false
	veil.Parent = screen

	local flashToken = 0

	local function flash(color: Color3, strength: number, duration: number)
		flashToken += 1
		local token = flashToken

		veil.BackgroundColor3 = color
		veil.BackgroundTransparency = 1 - strength

		local elapsed = 0
		task.spawn(function()
			while elapsed < duration do
				local dt = task.wait()
				if token ~= flashToken then
					return -- yeni bir parlama başladı, bu eskisi
				end
				elapsed += dt
				local t = math.clamp(elapsed / duration, 0, 1)
				veil.BackgroundTransparency = 1 - strength * (1 - t)
			end
			if token == flashToken then
				veil.BackgroundTransparency = 1
			end
		end)
	end

	-- ─── Kamera sarsıntısı ──────────────────────────────────────────────────

	local shakeStrength = 0
	local shakeDecay = 0

	--[[
		Kamera güncellemesinden SONRA çalışıyor (Camera + 1). Roblox her kare
		kamerayı sıfırdan hesapladığı için buradaki kayma birikmiyor; sarsıntı
		bitince kamera kendiliğinden yerine dönüyor.
	]]
	RunService:BindToRenderStep(SHAKE_BINDING, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		if shakeStrength <= 0.0001 then
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local s = shakeStrength
		local offset = CFrame.new(
			(math.random() - 0.5) * s,
			(math.random() - 0.5) * s,
			0
		) * CFrame.Angles(
			(math.random() - 0.5) * s * 0.02,
			(math.random() - 0.5) * s * 0.02,
			(math.random() - 0.5) * s * 0.03
		)

		camera.CFrame = camera.CFrame * offset
		shakeStrength = math.max(0, shakeStrength - shakeDecay * dt)
	end)

	local function shake(strength: number, duration: number)
		-- Üst üste gelen sarsıntılarda güçlü olan kazansın
		shakeStrength = math.max(shakeStrength, strength)
		shakeDecay = strength / math.max(duration, 0.05)
	end

	return { Flash = flash, Shake = shake }
end

return ScreenFX
