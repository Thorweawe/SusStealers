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

	GÖRÜNÜŞ: öbür pencereler gibi mağaza dilinde (CardKit) — olayın
	renginde ışınlı kartlar, kalın konturlu yazılar, ikon rozetleri,
	renkli başlık şeridi. Eskiden koyu düz kutular ve ince yazılardı.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local CardKit = require(script.Parent.CardKit)
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
	local WHITE = CardKit.WHITE
	local NEUTRAL = Color3.fromRGB(60, 110, 220)

	-- ─── Şerit (süren olay, üst orta) ────────────────────────────────────

	local bar = Instance.new("Frame")
	bar.Name = "EventBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 10)
	bar.Size = UDim2.fromOffset(400, 66)
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = screen
	local barCard = CardKit.card(bar, UiKit.CREW.RED, UDim2.fromScale(1, 1), 1, UDim2.fromScale(0.12, 0.5), 320)

	local barBadge = CardKit.badge(bar, 58, UiKit.CREW.RED, 4)
	barBadge.AnchorPoint = Vector2.new(0, 0.5)
	barBadge.Position = UDim2.new(0, 6, 0.5, 0)
	local barPulse = Instance.new("UIScale")
	barPulse.Parent = barBadge
	local barIconHost = barBadge:FindFirstChild("Slot") :: Frame

	local title = CardKit.bold(barCard, "", 26, WHITE, 5, 3.5)
	title.Name = "Title"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(74, 5)
	title.Size = UDim2.new(1, -84, 0, 32)
	CardKit.fit(title, 26, 12)

	local sub = CardKit.bold(barCard, "", 16, CardKit.YELLOW, 5, 2)
	sub.Name = "Sub"
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Position = UDim2.fromOffset(74, 38)
	sub.Size = UDim2.new(1, -84, 0, 20)
	CardKit.fit(sub, 16, 10)

	local SUBTEXT: { [string]: string } = {
		Meeting = "2x income for everyone",
		LightsOut = "Stealing is faster in the dark",
		Meltdown = "Grab the glowing reactor cores!",
		Impostor = "Catching the impostor costs YOU money",
	}

	-- ─── Çizelge (sağ alt) ───────────────────────────────────────────────

	local ROW_H = 54
	local CARD_H = 82
	local HEAD_H = 34
	local WIDTH = 270

	local panel = Instance.new("Frame")
	panel.Name = "EventSchedule"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -22, 1, -22)
	panel.Size = UDim2.fromOffset(WIDTH, HEAD_H + ROW_H + 12)
	panel.BackgroundColor3 = CardKit.BODY
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Parent = screen
	CardKit.corner(panel, 14)
	CardKit.gradient(panel, CardKit.BODY, CardKit.BODY_DEEP)
	CardKit.border(panel, CardKit.OUTLINE, 3)

	-- Başlık şeridi: tıklayınca sıradaki olay satırı gizleniyor / geri geliyor
	local head = Instance.new("TextButton")
	head.Name = "Head"
	head.Size = UDim2.new(1, 0, 0, HEAD_H)
	head.BackgroundColor3 = NEUTRAL
	head.BorderSizePixel = 0
	head.AutoButtonColor = false
	head.Text = ""
	head.Parent = panel
	CardKit.corner(head, 14)
	local headGrad = CardKit.gradient(head, NEUTRAL:Lerp(WHITE, 0.2), NEUTRAL:Lerp(Color3.new(0, 0, 0), 0.15))
	local headFoot = Instance.new("Frame")
	headFoot.Position = UDim2.new(0, 0, 1, -12)
	headFoot.Size = UDim2.new(1, 0, 0, 12)
	headFoot.BackgroundColor3 = NEUTRAL:Lerp(Color3.new(0, 0, 0), 0.12)
	headFoot.BorderSizePixel = 0
	headFoot.Parent = head
	for i, x in { 0.6, 0.68 } do
		local stripe = Instance.new("Frame")
		stripe.AnchorPoint = Vector2.new(0.5, 0.5)
		stripe.Position = UDim2.fromScale(x, 0.5)
		stripe.Size = UDim2.fromOffset(if i == 1 then 22 else 9, 90)
		stripe.Rotation = 30
		stripe.BackgroundColor3 = WHITE
		stripe.BackgroundTransparency = 0.8
		stripe.BorderSizePixel = 0
		stripe.Parent = head
	end
	local headText = CardKit.bold(head, "EVENTS", 20, WHITE, 3, 2.5)
	headText.TextXAlignment = Enum.TextXAlignment.Left
	headText.Position = UDim2.fromOffset(12, 0)
	headText.Size = UDim2.new(1, -90, 1, 0)
	local fold = CardKit.bold(head, "HIDE ▾", 14, WHITE, 3, 2)
	fold.AnchorPoint = Vector2.new(1, 0)
	fold.Position = UDim2.new(1, -10, 0, 0)
	fold.Size = UDim2.fromOffset(70, HEAD_H)
	fold.TextXAlignment = Enum.TextXAlignment.Right
	local rule = Instance.new("Frame")
	rule.Position = UDim2.new(0, 0, 0, HEAD_H - 2)
	rule.Size = UDim2.new(1, 0, 0, 3)
	rule.BackgroundColor3 = CardKit.OUTLINE
	rule.BorderSizePixel = 0
	rule.Parent = panel

	local function paintHead(color: Color3)
		head.BackgroundColor3 = color
		headGrad.Color = ColorSequence.new(color:Lerp(WHITE, 0.2), color:Lerp(Color3.new(0, 0, 0), 0.15))
		headFoot.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.12)
	end

	-- Süren olayın kartı: büyük ikon, ad, açıklama, kalan süre
	local card = CardKit.card(panel, UiKit.CREW.RED, UDim2.new(1, -16, 0, CARD_H - 8), 2, UDim2.fromScale(0.15, 0.5), 260)
	card.Name = "Live"
	card.Position = UDim2.fromOffset(8, HEAD_H + 6)
	card.Visible = false

	local cardIcon = CardKit.badge(card, 60, UiKit.CREW.RED, 5)
	cardIcon.AnchorPoint = Vector2.new(0, 0.5)
	cardIcon.Position = UDim2.new(0, 8, 0.5, 0)
	local cardPulse = Instance.new("UIScale")
	cardPulse.Parent = cardIcon
	-- İkon ayrı bir kapta: değişince yalnızca o temizleniyor (köşe ve ölçek kalıyor)
	local cardIconHost = cardIcon:FindFirstChild("Slot") :: Frame

	local cardLive = CardKit.bold(card, "● LIVE", 14, WHITE, 6, 2)
	cardLive.TextXAlignment = Enum.TextXAlignment.Left
	cardLive.Position = UDim2.fromOffset(76, 6)
	cardLive.Size = UDim2.fromOffset(70, 18)
	cardLive.BackgroundTransparency = 0
	cardLive.BackgroundColor3 = Color3.fromRGB(226, 30, 40)
	CardKit.corner(cardLive, 6)
	CardKit.border(cardLive, CardKit.OUTLINE, 2)
	cardLive.TextXAlignment = Enum.TextXAlignment.Center

	local cardTime = CardKit.bold(card, "", 15, CardKit.YELLOW, 6, 2)
	cardTime.AnchorPoint = Vector2.new(1, 0)
	cardTime.Position = UDim2.new(1, -8, 0, 5)
	cardTime.Size = UDim2.fromOffset(96, 20)
	cardTime.TextXAlignment = Enum.TextXAlignment.Right

	local cardName = CardKit.bold(card, "", 22, WHITE, 6, 3)
	cardName.TextXAlignment = Enum.TextXAlignment.Left
	cardName.Position = UDim2.fromOffset(76, 26)
	cardName.Size = UDim2.new(1, -90, 0, 26)
	CardKit.fit(cardName, 22, 11)

	local cardSub = CardKit.bold(card, "", 13, Color3.fromRGB(235, 240, 255), 6, 1.6)
	cardSub.TextXAlignment = Enum.TextXAlignment.Left
	cardSub.Position = UDim2.fromOffset(76, 52)
	cardSub.Size = UDim2.new(1, -84, 0, 18)
	CardKit.fit(cardSub, 13, 8)

	-- Sıradaki olayların satırları (sabit sayıda; sırası her tikte güncelleniyor)
	type Row = { frame: Frame, badge: Frame, icon: Frame, name: TextLabel, time: TextLabel, scale: UIScale, id: string }
	local rows: { Row } = {}
	for index = 1, #Config.Events do
		local frame = CardKit.card(panel, NEUTRAL, UDim2.new(1, -16, 0, ROW_H - 8), 2, UDim2.fromScale(0.12, 0.5), 220)
		frame.Name = "Row" .. index

		local badge = CardKit.badge(frame, 42, NEUTRAL, 5)
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 6, 0.5, 0)
		local icon = badge:FindFirstChild("Slot") :: Frame

		local name = CardKit.bold(frame, "", 18, WHITE, 6, 2.5)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(56, 4)
		name.Size = UDim2.new(1, -64, 0, 22)
		CardKit.fit(name, 18, 10)

		local time = CardKit.bold(frame, "", 16, CardKit.YELLOW, 6, 2)
		time.TextXAlignment = Enum.TextXAlignment.Left
		time.Position = UDim2.fromOffset(56, 26)
		time.Size = UDim2.new(1, -64, 0, 20)
		local scale = Instance.new("UIScale")
		scale.Parent = time

		table.insert(rows, { frame = frame, badge = badge, icon = icon, name = name, time = time, scale = scale, id = "" })
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
			local color = ACCENT[activeId] or UiKit.CREW.RED
			if cardId ~= activeId then
				cardId = activeId
				UiKit.ClearSlot(cardIconHost)
				drawEventIcon(cardIconHost, 44, activeId)
				CardKit.tintCard(card, color:Lerp(Color3.new(0, 0, 0), 0.25))
				paintHead(color:Lerp(Color3.new(0, 0, 0), 0.1))
			end
			local endsAt = workspace:GetAttribute("EventEndsAt") :: number?
			cardName.Text = tostring(workspace:GetAttribute("EventName") or activeId)
			cardSub.Text = SUBTEXT[activeId] or ""
			cardTime.Text = "ENDS " .. clock((endsAt or now) - now)
		elseif cardId ~= "" then
			cardId = ""
			paintHead(NEUTRAL)
		end

		--[[
			Yalnızca SIRADAKİ olay gösteriliyor (bütün liste kalabalık yapıyordu).
			Rastgele olaylar (Impostor) hiç gösterilmiyor: sürpriz olmalı,
			zamanını sunucu her saat rastgele seçiyor ve kimseye söylemiyor.
		]]
		local upcoming: { { def: Config.EventDef, at: number } } = {}
		for _, def in Config.Events do
			if def.id ~= activeId and not def.random then
				table.insert(upcoming, { def = def, at = Config.GetNextEventStart(def, now) })
			end
		end
		table.sort(upcoming, function(a, b)
			return a.at < b.at
		end)

		local y = HEAD_H + 6 + (if live then CARD_H else 0)
		for index, row in rows do
			local entry = upcoming[index]
			local visible = entry ~= nil and index == 1 and not collapsed
			row.frame.Visible = visible
			if not entry or not visible then
				continue
			end
			row.frame.Position = UDim2.fromOffset(8, y)
			y += ROW_H
			if row.id ~= entry.def.id then
				row.id = entry.def.id
				UiKit.ClearSlot(row.icon)
				drawEventIcon(row.icon, 30, entry.def.id)
				row.name.Text = entry.def.name
				local tone = (ACCENT[entry.def.id] or NEUTRAL):Lerp(Color3.new(0, 0, 0), 0.35)
				CardKit.tintCard(row.frame, tone)
			end
			local left = entry.at - now
			row.time.Text = "starts in " .. clock(left)
			-- Uyarı süresine (Config.EventWarning) girince: "şimdi başlıyor", nabız
			local soon = left <= Config.EventWarning
			row.time.TextColor3 = if soon then Color3.fromRGB(255, 120, 90) else CardKit.YELLOW
			row.scale.Scale = if soon then 1 + 0.06 * math.abs(math.sin(now * 5)) else 1
		end
		panel.Size = UDim2.fromOffset(WIDTH, y + 4)
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
			if bar:GetAttribute("For") ~= id then
				bar:SetAttribute("For", id)
				CardKit.tintCard(barCard, color:Lerp(Color3.new(0, 0, 0), 0.25))
				UiKit.ClearSlot(barIconHost)
				drawEventIcon(barIconHost, 42, id)
			end
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
		barPulse.Scale = 1 + 0.08 * math.sin(pulseTime * 6)
		-- LIVE rozeti yanıp sönüyor
		cardLive.BackgroundTransparency = if math.sin(pulseTime * 5) > 0 then 0 else 0.45
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
