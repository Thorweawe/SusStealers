--!strict
--[[
	Sunucu olaylarının istemci yüzü (olayları EventService yönetiyor):

	  Şerit      — ekranın üst ortasında: süren olay + kalan süre; olay
	               yoksa küçük harfle sıradaki olay ve ne kadar kaldığı.
	               Oyuncu "10 dakika sonra toplantı var, çıkmayayım" diyebilsin.
	  Karanlık   — Lights Sabotage'ta ışıklar yerelde kısılıyor. Sunucudan
	               Lighting'i değiştirseydik geçiş animasyonu her karede
	               herkese paket olurdu; burada yumuşak geçiş bedava.

	Veriler workspace niteliklerinden (EventId, EventEndsAt, NextEvent...);
	sunucuya hiçbir şey göndermiyor.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent.UiKit)

local EventFX = {}

export type Handle = {
	Destroy: () -> (),
}

local ACCENT: { [string]: Color3 } = {
	Meeting = Color3.fromRGB(255, 80, 80),
	LightsOut = Color3.fromRGB(255, 214, 60),
	Meltdown = Color3.fromRGB(90, 255, 170),
	Impostor = Color3.fromRGB(255, 60, 60),
}

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

function EventFX.Create(screen: ScreenGui): Handle
	-- ─── Şerit ───────────────────────────────────────────────────────────

	local bar = Instance.new("Frame")
	bar.Name = "EventBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 10)
	bar.Size = UDim2.fromOffset(340, 52)
	bar.BackgroundColor3 = UiKit.SHELL_DEEP
	bar.BackgroundTransparency = 0.1
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = screen
	UiKit.Corner(bar, 14)
	local stroke = UiKit.Stroke(bar, UiKit.CREW.RED, 2.4, 0.1)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 5)
	title.Size = UDim2.new(1, -28, 0, 26)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 22
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.4
	title.Parent = bar

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(14, 30)
	sub.Size = UDim2.new(1, -28, 0, 16)
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 13
	sub.TextColor3 = UiKit.MUTED
	sub.Parent = bar

	-- Olay yokken: küçük "sıradaki" satırı
	local nextLine = Instance.new("TextLabel")
	nextLine.Name = "NextEvent"
	nextLine.AnchorPoint = Vector2.new(0.5, 0)
	nextLine.Position = UDim2.new(0.5, 0, 0, 10)
	nextLine.Size = UDim2.fromOffset(300, 20)
	nextLine.BackgroundTransparency = 1
	nextLine.Font = Enum.Font.GothamBold
	nextLine.TextSize = 14
	nextLine.TextColor3 = UiKit.MUTED
	nextLine.TextStrokeTransparency = 0.5
	nextLine.Visible = false
	nextLine.Parent = screen

	local SUBTEXT: { [string]: string } = {
		Meeting = "2x income for everyone",
		LightsOut = "Stealing is faster in the dark",
		Meltdown = "Grab the glowing reactor cores!",
		Impostor = "Catching the impostor costs YOU money",
	}

	-- ─── Karanlık ────────────────────────────────────────────────────────

	local dim = Instance.new("ColorCorrectionEffect")
	dim.Name = "SabotageDim"
	dim.Brightness = 0
	dim.Saturation = 0
	dim.TintColor = Color3.new(1, 1, 1)
	dim.Parent = Lighting

	local dark = false
	local function setDark(on: boolean)
		if dark == on then
			return
		end
		dark = on
		local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(dim, info, {
			Brightness = if on then -0.32 else 0,
			Saturation = if on then -0.35 else 0,
			TintColor = if on then Color3.fromRGB(190, 200, 255) else Color3.new(1, 1, 1),
		}):Play()
	end

	-- ─── Güncelleme ──────────────────────────────────────────────────────

	local accum = 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.25 then
			return
		end
		accum = 0

		local now = workspace:GetServerTimeNow()
		local id = workspace:GetAttribute("EventId")
		local hidden = screen:GetAttribute("UiHidden") == true

		-- Otomatik yumurta şeridi de üst ortada; açıksa onun altına in
		local auto = screen:FindFirstChild("AutoHatchBar")
		local top = if auto and auto:IsA("GuiObject") and auto.Visible then 62 else 10
		bar.Position = UDim2.new(0.5, 0, 0, top)
		nextLine.Position = UDim2.new(0.5, 0, 0, top)

		if typeof(id) == "string" and id ~= "" then
			local endsAt = workspace:GetAttribute("EventEndsAt") :: number?
			local name = workspace:GetAttribute("EventName")
			local color = ACCENT[id] or UiKit.CREW.RED
			stroke.Color = color
			title.TextColor3 = color
			title.Text = string.upper(tostring(name)) .. "  " .. clock((endsAt or now) - now)
			sub.Text = SUBTEXT[id] or ""
			bar.Visible = not hidden
			nextLine.Visible = false
			setDark(id == "LightsOut")
		else
			bar.Visible = false
			setDark(false)
			local nextName = workspace:GetAttribute("NextEventName")
			local nextAt = workspace:GetAttribute("NextEventAt") :: number?
			if typeof(nextName) == "string" and nextAt and nextAt > now then
				nextLine.Text = string.format("Next: %s in %s", nextName, clock(nextAt - now))
				nextLine.Visible = not hidden
			else
				nextLine.Visible = false
			end
		end
	end)

	return {
		Destroy = function()
			connection:Disconnect()
			bar:Destroy()
			nextLine:Destroy()
			dim:Destroy()
		end,
	}
end

return EventFX
