--!strict
--[[
	Sunucu olaylarının istemci yüzü (olayları EventService yönetiyor):

	  Şerit      — ekranın üst ortasında: süren olay + kalan süre (yalnızca
	               olay sürerken).
	  Çizelge    — SAĞ ALT köşede: bütün olaylar, her birinin yanında kendi
	               ikonu ve ne zaman başlayacağı. Süren olay üstte büyük
	               kartta, ikonu nabız gibi atıyor. Oyuncu "10 dakika sonra
	               toplantı var, çıkmayayım" diyebilsin.
	               Eskiden sıradaki olay üst ortada tek satır yazıydı ("Next:
	               Lights Sabotage in 21:34") ve sahnenin ortasında isim
	               etiketlerinin üstüne biniyordu.
	  Karanlık   — Lights Sabotage'ta ışıklar yerelde kısılıyor. Sunucudan
	               Lighting'i değiştirseydik geçiş animasyonu her karede
	               herkese paket olurdu; burada yumuşak geçiş bedava.

	Veriler workspace niteliklerinden (EventId, EventEndsAt, NextEvent...);
	sunucuya hiçbir şey göndermiyor.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
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

--[[
	Olay ikonları — Frame'den (UiKit'in "hazır görsel yok" kuralı):

	  Meeting    kırmızı acil durum düğmesi, cam kubbesiyle (kafeteryadaki masa)
	  LightsOut  üstü çizili ampul
	  Meltdown   sarı-siyah reaktör uyarı işareti, ortada yeşil çekirdek
	  Impostor   kırmızı mürettebat, elinde bıçak
]]
local function drawEventIcon(parent: Instance, size: number, id: string): Frame
	local h = UiKit.Canvas(parent, "EventIcon", size)
	local S = UiKit.Shape
	local WHITE = Color3.new(1, 1, 1)

	if id == "Meeting" then
		S(h, 0.5, 0.8, 0.86, 0.2, Color3.fromRGB(120, 132, 146), 1, 0.3)
		S(h, 0.5, 0.7, 0.66, 0.1, Color3.fromRGB(176, 188, 196), 2, 0.4)
		S(h, 0.5, 0.52, 0.52, 0.38, Color3.fromRGB(226, 44, 44), 3, 0.5)
		S(h, 0.42, 0.44, 0.12, 0.1, WHITE, 4, 0.5).BackgroundTransparency = 0.3
		UiKit.Ring(h, 0.5, 0.5, 0.78, 0.62, Color3.fromRGB(170, 220, 250), math.max(1.5, size * 0.05), 4)
	elseif id == "LightsOut" then
		S(h, 0.5, 0.4, 0.6, 0.6, Color3.fromRGB(255, 214, 60), 1, 0.5)
		S(h, 0.5, 0.74, 0.3, 0.12, Color3.fromRGB(150, 160, 172), 2, 0.2)
		S(h, 0.5, 0.84, 0.24, 0.08, Color3.fromRGB(110, 118, 128), 2, 0.3)
		S(h, 0.4, 0.3, 0.12, 0.14, WHITE, 3, 0.5).BackgroundTransparency = 0.35
		S(h, 0.5, 0.5, 1.0, 0.11, Color3.fromRGB(40, 36, 60), 4, 0.5, -45)
		S(h, 0.5, 0.5, 0.94, 0.06, Color3.fromRGB(226, 60, 60), 5, 0.5, -45)
	elseif id == "Meltdown" then
		S(h, 0.5, 0.5, 0.92, 0.92, Color3.fromRGB(252, 204, 48), 1, 0.5)
		for k = 0, 2 do
			local a = math.rad(90 + k * 120)
			S(h, 0.5 + math.cos(a) * 0.22, 0.5 - math.sin(a) * 0.22, 0.3, 0.24,
				Color3.fromRGB(34, 32, 38), 2, 0.2, -(90 + k * 120) + 90)
		end
		S(h, 0.5, 0.5, 0.2, 0.2, Color3.fromRGB(34, 32, 38), 3, 0.5)
		S(h, 0.5, 0.5, 0.12, 0.12, Color3.fromRGB(90, 255, 170), 4, 0.5)
	elseif id == "Impostor" then
		local host = S(h, 0.44, 0.52, 0.8, 0.8, WHITE, 1)
		host.BackgroundTransparency = 1
		UiKit.Crewmate(host, size * 0.72, Color3.fromRGB(198, 40, 48))
		S(h, 0.84, 0.44, 0.08, 0.36, Color3.fromRGB(214, 224, 232), 6, 0.3, 25)
		S(h, 0.78, 0.66, 0.1, 0.14, Color3.fromRGB(96, 64, 40), 6, 0.2, 25)
	else
		S(h, 0.5, 0.5, 0.8, 0.8, UiKit.MUTED, 1, 0.5)
	end
	return h
end

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

	local SUBTEXT: { [string]: string } = {
		Meeting = "2x income for everyone",
		LightsOut = "Stealing is faster in the dark",
		Meltdown = "Grab the glowing reactor cores!",
		Impostor = "Catching the impostor costs YOU money",
	}

	-- ─── Çizelge (sağ alt) ───────────────────────────────────────────────

	local ROW_H = 38
	local CARD_H = 70
	local HEAD_H = 28
	local WIDTH = 252

	local panel = Instance.new("Frame")
	panel.Name = "EventSchedule"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -22, 1, -22)
	panel.Size = UDim2.fromOffset(WIDTH, HEAD_H + #Config.Events * ROW_H + 12)
	panel.BackgroundColor3 = UiKit.SHELL_DEEP
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = screen
	UiKit.Corner(panel, 14)
	local panelStroke = UiKit.Stroke(panel, UiKit.VISOR, 1.8, 0.45)

	-- Başlık: tıklayınca liste daralıyor (yalnızca sıradaki olay kalıyor)
	local head = Instance.new("TextButton")
	head.Name = "Head"
	head.Position = UDim2.fromOffset(12, 4)
	head.Size = UDim2.new(1, -24, 0, HEAD_H - 4)
	head.BackgroundTransparency = 1
	head.AutoButtonColor = false
	head.Font = Enum.Font.GothamBlack
	head.TextSize = 13
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.TextColor3 = UiKit.MUTED
	head.Text = "EVENTS"
	head.Parent = panel

	local fold = Instance.new("TextLabel")
	fold.AnchorPoint = Vector2.new(1, 0)
	fold.Position = UDim2.new(1, -12, 0, 4)
	fold.Size = UDim2.fromOffset(60, HEAD_H - 4)
	fold.BackgroundTransparency = 1
	fold.Font = Enum.Font.GothamBold
	fold.TextSize = 11
	fold.TextXAlignment = Enum.TextXAlignment.Right
	fold.TextColor3 = UiKit.DIM
	fold.Text = "HIDE ▾"
	fold.Parent = panel

	-- Süren olayın kartı: büyük ikon, ad, açıklama, kalan süre
	local card = Instance.new("Frame")
	card.Name = "Live"
	card.Position = UDim2.fromOffset(8, HEAD_H)
	card.Size = UDim2.new(1, -16, 0, CARD_H - 6)
	card.BackgroundColor3 = UiKit.ROW
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = panel
	UiKit.Corner(card, 12)
	local cardStroke = UiKit.Stroke(card, UiKit.CREW.RED, 2, 0.1)

	local cardIcon = Instance.new("Frame")
	cardIcon.AnchorPoint = Vector2.new(0, 0.5)
	cardIcon.Position = UDim2.new(0, 8, 0.5, 0)
	cardIcon.Size = UDim2.fromOffset(48, 48)
	cardIcon.BackgroundColor3 = UiKit.SHELL_DEEP
	cardIcon.BorderSizePixel = 0
	cardIcon.Parent = card
	UiKit.Corner(cardIcon, 12)
	local cardPulse = Instance.new("UIScale")
	cardPulse.Parent = cardIcon
	-- İkon ayrı bir kapta: değişince yalnızca o temizleniyor (köşe ve ölçek kalıyor)
	local cardIconHost = Instance.new("Frame")
	cardIconHost.Size = UDim2.fromScale(1, 1)
	cardIconHost.BackgroundTransparency = 1
	cardIconHost.Parent = cardIcon

	local cardLive = Instance.new("TextLabel")
	cardLive.Position = UDim2.fromOffset(64, 6)
	cardLive.Size = UDim2.new(1, -72, 0, 14)
	cardLive.BackgroundTransparency = 1
	cardLive.Font = Enum.Font.GothamBlack
	cardLive.TextSize = 11
	cardLive.TextXAlignment = Enum.TextXAlignment.Left
	cardLive.TextColor3 = UiKit.CREW.RED
	cardLive.Text = "● LIVE"
	cardLive.Parent = card

	local cardTime = Instance.new("TextLabel")
	cardTime.AnchorPoint = Vector2.new(1, 0)
	cardTime.Position = UDim2.new(1, -8, 0, 6)
	cardTime.Size = UDim2.fromOffset(70, 14)
	cardTime.BackgroundTransparency = 1
	cardTime.Font = Enum.Font.GothamBlack
	cardTime.TextSize = 12
	cardTime.TextXAlignment = Enum.TextXAlignment.Right
	cardTime.TextColor3 = Color3.new(1, 1, 1)
	cardTime.Parent = card

	local cardName = Instance.new("TextLabel")
	cardName.Position = UDim2.fromOffset(64, 20)
	cardName.Size = UDim2.new(1, -72, 0, 20)
	cardName.BackgroundTransparency = 1
	cardName.Font = Enum.Font.FredokaOne
	cardName.TextSize = 17
	cardName.TextXAlignment = Enum.TextXAlignment.Left
	cardName.TextColor3 = Color3.new(1, 1, 1)
	cardName.TextTruncate = Enum.TextTruncate.AtEnd
	cardName.Parent = card

	local cardSub = Instance.new("TextLabel")
	cardSub.Position = UDim2.fromOffset(64, 41)
	cardSub.Size = UDim2.new(1, -72, 0, 14)
	cardSub.BackgroundTransparency = 1
	cardSub.Font = Enum.Font.GothamMedium
	cardSub.TextSize = 11
	cardSub.TextXAlignment = Enum.TextXAlignment.Left
	cardSub.TextColor3 = UiKit.MUTED
	cardSub.TextTruncate = Enum.TextTruncate.AtEnd
	cardSub.Parent = card

	-- Sıradaki olayların satırları (sabit sayıda; sırası her tikte güncelleniyor)
	type Row = { frame: Frame, icon: Frame, name: TextLabel, time: TextLabel, id: string }
	local rows: { Row } = {}
	for index = 1, #Config.Events do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. index
		frame.Size = UDim2.new(1, -16, 0, ROW_H - 4)
		frame.BackgroundColor3 = UiKit.ROW
		frame.BackgroundTransparency = 0.4
		frame.BorderSizePixel = 0
		frame.Parent = panel
		UiKit.Corner(frame, 10)

		local icon = Instance.new("Frame")
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 6, 0.5, 0)
		icon.Size = UDim2.fromOffset(28, 28)
		icon.BackgroundTransparency = 1
		icon.Parent = frame

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(42, 0)
		name.Size = UDim2.new(1, -120, 1, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = UiKit.INK
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = frame

		local time = Instance.new("TextLabel")
		time.AnchorPoint = Vector2.new(1, 0)
		time.Position = UDim2.new(1, -8, 0, 0)
		time.Size = UDim2.new(0, 74, 1, 0)
		time.BackgroundTransparency = 1
		time.Font = Enum.Font.GothamBlack
		time.TextSize = 13
		time.TextXAlignment = Enum.TextXAlignment.Right
		time.TextColor3 = UiKit.MUTED
		time.Parent = frame

		table.insert(rows, { frame = frame, icon = icon, name = name, time = time, id = "" })
	end

	local collapsed = false
	head.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		fold.Text = if collapsed then "SHOW ▴" else "HIDE ▾"
	end)

	local cardId = ""
	local function layoutSchedule(activeId: string, now: number)
		-- Süren olay kartı
		local live = activeId ~= ""
		card.Visible = live
		if live then
			if cardId ~= activeId then
				cardId = activeId
				UiKit.ClearSlot(cardIconHost)
				drawEventIcon(cardIconHost, 40, activeId)
			end
			local color = ACCENT[activeId] or UiKit.CREW.RED
			cardStroke.Color = color
			cardLive.TextColor3 = color
			card.BackgroundColor3 = UiKit.ROW:Lerp(color, 0.14)
			panelStroke.Color = color
			local endsAt = workspace:GetAttribute("EventEndsAt") :: number?
			cardName.Text = tostring(workspace:GetAttribute("EventName") or activeId)
			cardSub.Text = SUBTEXT[activeId] or ""
			cardTime.Text = "ENDS " .. clock((endsAt or now) - now)
		else
			cardId = ""
			panelStroke.Color = UiKit.VISOR
		end

		-- Sıradakiler: başlangıcı en yakın olan üstte, süren olay listede yok
		local upcoming: { { def: Config.EventDef, at: number } } = {}
		for _, def in Config.Events do
			if def.id ~= activeId then
				table.insert(upcoming, { def = def, at = Config.GetNextEventStart(def, now) })
			end
		end
		table.sort(upcoming, function(a, b)
			return a.at < b.at
		end)

		local y = HEAD_H + (if live then CARD_H else 0)
		for index, row in rows do
			local entry = upcoming[index]
			local visible = entry ~= nil and (not collapsed or index == 1)
			row.frame.Visible = visible
			if not entry or not visible then
				continue
			end
			row.frame.Position = UDim2.fromOffset(8, y)
			y += ROW_H
			if row.id ~= entry.def.id then
				row.id = entry.def.id
				UiKit.ClearSlot(row.icon)
				drawEventIcon(row.icon, 26, entry.def.id)
				row.name.Text = entry.def.name
			end
			local left = entry.at - now
			row.time.Text = "in " .. clock(left)
			-- Uyarı süresine (Config.EventWarning) girince sarı: "şimdi başlıyor"
			row.time.TextColor3 = if left <= Config.EventWarning then UiKit.WARN else UiKit.MUTED
		end
		panel.Size = UDim2.fromOffset(WIDTH, y + 8)
	end

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

		layoutSchedule(if typeof(id) == "string" then id else "", now)

		if typeof(id) == "string" and id ~= "" then
			local endsAt = workspace:GetAttribute("EventEndsAt") :: number?
			local name = workspace:GetAttribute("EventName")
			local color = ACCENT[id] or UiKit.CREW.RED
			stroke.Color = color
			title.TextColor3 = color
			title.Text = string.upper(tostring(name)) .. "  " .. clock((endsAt or now) - now)
			sub.Text = SUBTEXT[id] or ""
			bar.Visible = not hidden
			setDark(id == "LightsOut")
		else
			bar.Visible = false
			setDark(false)
		end
	end)

	-- Süren olayın ikonu nabız gibi atıyor (her karede; döngü 0.25 sn'de bir)
	local pulseTime = 0
	local pulseConnection = RunService.RenderStepped:Connect(function(dt)
		if not card.Visible then
			return
		end
		pulseTime += dt
		cardPulse.Scale = 1 + 0.08 * math.sin(pulseTime * 6)
	end)

	return {
		Destroy = function()
			connection:Disconnect()
			pulseConnection:Disconnect()
			bar:Destroy()
			panel:Destroy()
			dim:Destroy()
		end,
	}
end

return EventFX
