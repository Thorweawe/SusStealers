--!strict
--[[
	Sunucu şansı ve trollerin ekrandaki hâli (sunucusu ServerBoostService).

	  Şans hapı — sol üstte, şans sürerken: yonca, "SERVER LUCK x2", kalan
	              süre, alanın adı. workspace niteliklerinden (ServerLuck*).
	  Afiş      — biri şans ya da trol alınca ekranın üst ortasında büyük
	              yazı ("ATCIKM used SHRINK EVERYONE!"), büyüyerek gelip
	              sönüyor.
	  Alarm     — Impostor Alarm trolünde (alan hariç): kırmızı yanıp sönen
	              kenarlar, siren, kamera sarsıntısı (ayarlarda sarsıntı
	              kapalıysa sarsıntı yok).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local FancyKit = require(script.Parent.FancyKit)
local Quiet = require(script.Parent.Quiet)
local SoundFX = require(script.Parent.SoundFX)
local UiArt = require(script.Parent.UiArt)

local ServerBoostFX = {}

local player = Players.LocalPlayer
local OUTLINE = Color3.fromRGB(22, 20, 34)
local WHITE = Color3.new(1, 1, 1)

local TROLL_TEXT: { [string]: string } = {
	Tiny = "SHRINK EVERYONE",
	Moon = "MOON GRAVITY",
	Alarm = "IMPOSTOR ALARM",
}

local function label(parent: Instance, text: string, size: number, color: Color3, z: number, stroke: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.ZIndex = z
	l.Parent = parent
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = stroke
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	return l
end

-- Oyuncunun baş resmi (beklemesiz: rbxthumb adresi)
local function headshot(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

local function clock(seconds: number): string
	local t = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", t // 60, t % 60)
end

function ServerBoostFX.Create(screen: ScreenGui)
	-- ─── Şans hapı ───────────────────────────────────────────────────────
	local pill = Instance.new("Frame")
	pill.Name = "ServerLuckPill"
	pill.Position = UDim2.fromOffset(22, 12)
	pill.Size = UDim2.fromOffset(250, 58)
	pill.BackgroundColor3 = WHITE
	pill.Visible = false
	pill.ZIndex = 20
	pill.Parent = screen
	FancyKit.corner(pill, 16)
	FancyKit.border(pill, OUTLINE, 3)
	FancyKit.gradient(pill, { Color3.fromRGB(90, 220, 90), Color3.fromRGB(30, 140, 60) }, 90)
	local driver = FancyKit.driver(pill)
	FancyKit.halftone(pill, WHITE, 0.85, 20, true)
	FancyKit.gleam(pill, driver, 3.5, 0, 0.45)
	local icon = Instance.new("ImageLabel")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromOffset(30, 27)
	icon.Size = UDim2.fromOffset(62, 62)
	icon.BackgroundTransparency = 1
	icon.Image = UiArt.Image("Icon", "ServerLuck")
	icon.ZIndex = 23
	icon.Parent = pill
	FancyKit.bob(icon, driver, 2, 2.2, 0, 8)
	local title = label(pill, "SERVER LUCK x2", 20, Color3.fromRGB(255, 244, 150), 23, 2.5)
	title.Position = UDim2.fromOffset(62, 4)
	title.Size = UDim2.new(1, -120, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local byFace = Instance.new("ImageLabel")
	byFace.Position = UDim2.fromOffset(62, 31)
	byFace.Size = UDim2.fromOffset(20, 20)
	byFace.BackgroundColor3 = Color3.fromRGB(30, 90, 40)
	byFace.ZIndex = 23
	byFace.Parent = pill
	FancyKit.corner(byFace, 10)
	FancyKit.border(byFace, OUTLINE, 1.5)
	local by = label(pill, "", 14, WHITE, 23, 1.6)
	by.Position = UDim2.fromOffset(86, 31)
	by.Size = UDim2.new(1, -144, 0, 20)
	by.TextXAlignment = Enum.TextXAlignment.Left
	by.TextTruncate = Enum.TextTruncate.AtEnd
	local timer = label(pill, "", 22, WHITE, 23, 2.5)
	timer.AnchorPoint = Vector2.new(1, 0.5)
	timer.Position = UDim2.new(1, -10, 0.5, 0)
	timer.Size = UDim2.fromOffset(62, 30)
	timer.TextXAlignment = Enum.TextXAlignment.Right

	local lastPaint = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() - lastPaint < 0.25 then
			return
		end
		lastPaint = os.clock()
		local luck = Config.GetServerLuck()
		pill.Visible = luck > 1
		if luck > 1 then
			local ends = workspace:GetAttribute("ServerLuckEndsAt") :: number
			title.Text = string.format("SERVER LUCK x%d", luck)
			local name = workspace:GetAttribute("ServerLuckBy")
			local byId = workspace:GetAttribute("ServerLuckById")
			by.Text = if typeof(name) == "string" then "by " .. name else ""
			byFace.Visible = typeof(byId) == "number"
			if typeof(byId) == "number" then
				local img = headshot(byId)
				if byFace.Image ~= img then
					byFace.Image = img
				end
			end
			timer.Text = clock(ends - Config.ServerNow())
		end
	end)

	-- ─── Afiş ────────────────────────────────────────────────────────────
	local bannerHolder = Instance.new("Frame")
	bannerHolder.Name = "ServerBoostBanner"
	bannerHolder.AnchorPoint = Vector2.new(0.5, 0)
	-- Ekranın üst ortası (üst şeridin hemen altı, oyun alanını kapatmıyor)
	bannerHolder.Position = UDim2.new(0.5, 0, 0, 2)
	bannerHolder.Size = UDim2.fromOffset(760, 110)
	bannerHolder.BackgroundTransparency = 1
	bannerHolder.Visible = false
	bannerHolder.ZIndex = 60
	bannerHolder.Parent = screen
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = bannerHolder
	local bannerDriver = FancyKit.driver(bannerHolder)
	local bannerTitle: Frame? = nil
	-- Alanın satırı: avatar + sarı büyük ad + ne yaptığı
	local who = Instance.new("Frame")
	who.AnchorPoint = Vector2.new(0.5, 0)
	who.Position = UDim2.new(0.5, 0, 0, 66)
	who.Size = UDim2.fromOffset(0, 52)
	who.AutomaticSize = Enum.AutomaticSize.X
	who.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
	who.BackgroundTransparency = 0.25
	who.ZIndex = 61
	who.Parent = bannerHolder
	FancyKit.corner(who, 26)
	FancyKit.border(who, OUTLINE, 3)
	local whoPad = Instance.new("UIPadding")
	whoPad.PaddingLeft = UDim.new(0, 5)
	whoPad.PaddingRight = UDim.new(0, 18)
	whoPad.Parent = who
	local whoList = Instance.new("UIListLayout")
	whoList.FillDirection = Enum.FillDirection.Horizontal
	whoList.VerticalAlignment = Enum.VerticalAlignment.Center
	whoList.Padding = UDim.new(0, 10)
	whoList.Parent = who
	local whoFace = Instance.new("ImageLabel")
	whoFace.Size = UDim2.fromOffset(44, 44)
	whoFace.BackgroundColor3 = Color3.fromRGB(60, 66, 96)
	whoFace.ZIndex = 62
	whoFace.Parent = who
	FancyKit.corner(whoFace, 22)
	FancyKit.border(whoFace, Color3.fromRGB(255, 226, 60), 3)
	local bannerSub = label(who, "", 26, WHITE, 62, 2.6)
	bannerSub.LayoutOrder = 2
	bannerSub.RichText = true
	bannerSub.AutomaticSize = Enum.AutomaticSize.X
	bannerSub.Size = UDim2.fromOffset(0, 44)
	local bannerToken = 0

	local function banner(big: string, sub: string, top: Color3, bottom: Color3, userId: number?)
		bannerToken += 1
		local token = bannerToken
		if bannerTitle then
			bannerTitle:Destroy()
		end
		local t = FancyKit.title(bannerHolder, big, 50, top, bottom, 61, bannerDriver)
		t.Size = UDim2.new(1, 0, 0, 60)
		bannerTitle = t
		bannerSub.Text = sub
		whoFace.Visible = typeof(userId) == "number" and userId > 0
		if typeof(userId) == "number" and userId > 0 then
			whoFace.Image = headshot(userId)
		end
		bannerHolder.Visible = true
		bannerScale.Scale = 0.3
		TweenService:Create(bannerScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		SoundFX.Success()
		task.delay(4.5, function()
			if bannerToken ~= token then
				return
			end
			TweenService:Create(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
			task.wait(0.27)
			if bannerToken == token then
				bannerHolder.Visible = false
			end
		end)
	end

	-- ─── Alarm ───────────────────────────────────────────────────────────
	--[[
		2026-10-01 ("ekran kırmızılaşmıyor"): alarm ana ekranın içindeydi;
		üstteki pencereler (çark, karşılama) ve üst şerit kenarları örtüyordu,
		kenarlar da soluktu. Artık kendi ScreenGui'sinde, her şeyin üstünde,
		üst şerit dahil bütün ekranı kaplayan kırmızı yanıp sönme + kalın kenarlar.
	]]
	local alarmGui = Instance.new("ScreenGui")
	alarmGui.Name = "TrollAlarmGui"
	alarmGui.DisplayOrder = 200
	alarmGui.IgnoreGuiInset = true
	alarmGui.ResetOnSpawn = false
	alarmGui.AutoLocalize = false  -- "IMPOSTOR ALERT!" çevrilince "Sahtekar Uyarısı!" oluyordu
	alarmGui.Parent = screen.Parent
	local alarm = Instance.new("Frame")
	alarm.Name = "TrollAlarm"
	alarm.Size = UDim2.fromScale(1, 1)
	alarm.BackgroundTransparency = 1
	alarm.Visible = false
	alarm.ZIndex = 55
	alarm.Parent = alarmGui
	local tint = Instance.new("Frame")
	tint.Name = "RedTint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Color3.fromRGB(255, 0, 20)
	tint.BackgroundTransparency = 0.7
	tint.BorderSizePixel = 0
	tint.ZIndex = 54
	tint.Parent = alarm
	local edges: { Frame } = {}
	for _, spec in {
		{ UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.22, 0), 90 },
		{ UDim2.fromScale(0, 0.78), UDim2.new(1, 0, 0.22, 0), 270 },
		{ UDim2.fromScale(0, 0), UDim2.new(0.18, 0, 1, 0), 0 },
		{ UDim2.fromScale(0.82, 0), UDim2.new(0.18, 0, 1, 0), 180 },
	} do
		local e = Instance.new("Frame")
		e.Position = spec[1]
		e.Size = spec[2]
		e.BackgroundColor3 = Color3.fromRGB(255, 20, 40)
		e.BorderSizePixel = 0
		e.ZIndex = 55
		e.Parent = alarm
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new(0.1, 1)
		g.Parent = e
		table.insert(edges, e)
	end
	local alarmText = label(alarm, "IMPOSTOR ALERT!", 64, Color3.fromRGB(255, 60, 70), 56, 4)
	alarmText.AnchorPoint = Vector2.new(0.5, 0.5)
	alarmText.Position = UDim2.fromScale(0.5, 0.5)
	alarmText.Size = UDim2.fromOffset(800, 80)
	local alarmUntil = 0

	local function shakeEnabled(): boolean
		return player:GetAttribute("SettingShake") ~= false
	end

	local function startAlarm(seconds: number)
		alarmUntil = math.max(alarmUntil, os.clock() + seconds)
		if alarm.Visible then
			return
		end
		alarm.Visible = true
		SoundFX.AlarmUntil(function()
			return os.clock() < alarmUntil
		end, seconds + 1)
		local camera = workspace.CurrentCamera
		RunService:BindToRenderStep("TrollAlarm", Enum.RenderPriority.Camera.Value + 1, function()
			local left = alarmUntil - os.clock()
			if left <= 0 then
				RunService:UnbindFromRenderStep("TrollAlarm")
				alarm.Visible = false
				return
			end
			local blink = (math.sin(os.clock() * 12) + 1) / 2
			for _, e in edges do
				e.BackgroundTransparency = blink * 0.35
			end
			tint.BackgroundTransparency = 0.62 + blink * 0.25
			alarmText.TextTransparency = blink * 0.6
			alarmText.Rotation = math.sin(os.clock() * 20) * 3
			if shakeEnabled() and camera then
				local k = math.min(1, left) * 0.012
				camera.CFrame *= CFrame.Angles((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
			end
		end)
	end

	-- ─── Olaylar ─────────────────────────────────────────────────────────
	-- Ad sarı ve kalın, gerisi beyaz
	local function whoText(name: string, rest: string): string
		return string.format('<font color="#FFE13C">%s</font> %s', name, rest)
	end

	Net.Get("ServerFX").OnClientEvent:Connect(function(kind, a, b, c, d)
		if kind == "luck" and typeof(a) == "string" then
			local mine = c == player.UserId
			-- Başkasının aldığı şans bandı yeni oyuncunun sessiz döneminde yok (etki yine geçerli)
			if not mine and Quiet.Active() then
				return
			end
			banner(string.format("SERVER LUCK x%d!", Config.ServerLuck.multiplier),
				whoText(if mine then "You" else a, "made everyone luckier for 15 minutes!"),
				Color3.fromRGB(190, 255, 120), Color3.fromRGB(60, 200, 70), if typeof(c) == "number" then c else nil)
		elseif kind == "troll" and typeof(a) == "string" and typeof(b) == "string" then
			local seconds = if typeof(c) == "number" then c else 10
			local mine = d == player.UserId
			if mine or not Quiet.Active() then
				banner(TROLL_TEXT[a] or a, whoText(if mine then "You" else b, "trolled the server!"),
					Color3.fromRGB(255, 170, 230), Color3.fromRGB(230, 60, 170), if typeof(d) == "number" then d else nil)
			end
			--[[
				2026-09-30: alan da görüyor (kısa). Eskiden yalnızca başkalarında
				çalıyordu; tek başına alan oyuncu Robux ödeyip hiçbir şey görmüyordu.
			]]
			if a == "Alarm" then
				-- Alan da tam süre görüyor (Robux ödedi; eskiden 4 sn'de kesiliyordu)
				startAlarm(seconds)
			end
		end
	end)
end

return ServerBoostFX
