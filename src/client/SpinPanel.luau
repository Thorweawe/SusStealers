--!strict
--[[
	Şans çarkı penceresi. Salondaki çarkın promptuna ("SpinPrompt") basınca
	açılıyor: ortada 3B ikonlu dilimli çark, tepede kırmızı işaretçi, altta
	büyük SPIN düğmesi, iki yanında Robux'la ekstra çevirme, en altta
	"+1 free spin in 05:59" geri sayımı.

	Akış: SPIN → "SpinRequest" (sunucu SpinService.TrySpin) → sunucu ödülü
	seçip "SpinResult" (rewardId, ad, süre, dilim, sapma, süper) gönderiyor
	→ çark o dilimde yavaşlayarak duruyor → ödül kartı. Ödülü sunucu tam o
	anda veriyor. Robux'la alınan çevirmede de aynı sonuç geliyor; pencere
	kapalıysa açılıyor.

	Görünüş (2026-09-28, mağazanın dili — FancyKit): çarkın yüzü tek resim
	(tools/ui_wheel.py; dilim sırası Config.SpinWheelSlices, dilim i tepeden
	saat yönünde (i-1)*30..i*30). Dönüş resmin Rotation'ı (saat yönü).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local FancyKit = require(script.Parent.FancyKit)
local SoundFX = require(script.Parent.SoundFX)
local UiArt = require(script.Parent.UiArt)
local UiKit = require(script.Parent.UiKit)

local SpinPanel = {}

local player = Players.LocalPlayer

local Z = 50
local W, H = 500, 640
local HEADER = 70
local R = 190              -- çark yarıçapı (piksel)
local OUTLINE = Color3.fromRGB(22, 20, 34)
local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(70, 200, 70)
local BLUE = Color3.fromRGB(40, 150, 235)
local PURPLE = Color3.fromRGB(150, 80, 235)
local GOLD = Color3.fromRGB(255, 186, 30)
local ROBUX_ICON = "rbxasset://textures/ui/common/robux@3x.png"

-- Ödül kartındaki 3B ikon (çarktaki dilimlerle aynı)
local PRIZE_ICON: { [string]: string } = {
	SmallCash = "Cash100K",
	MedCash = "Cash1M",
	HugeCash = "Cash10M",
	Spawn = "Crewmate",
	Mutation = "LuckyRoll",
	FreeUnit = "Jackpot",
}

export type Panel = {
	Open: () -> (),
	Destroy: () -> (),
}

local function text(parent: Instance, value: string, size: number, color: Color3, z: number, stroke: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.Text = value
	l.ZIndex = z
	l.Parent = parent
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = stroke or math.max(2, size / 9)
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	return l
end

--[[ Düğmenin sağ üst köşesine yapışık fiyat etiketi (Robux simgesi + fiyat). ]]
local function priceTag(holder: Frame, z: number): TextLabel
	local tag = Instance.new("Frame")
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.new(1, 8, 0, 0)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.Size = UDim2.fromOffset(0, 26)
	tag.BackgroundColor3 = WHITE
	tag.BorderSizePixel = 0
	tag.ZIndex = z
	tag.Parent = holder
	FancyKit.corner(tag, 13)
	FancyKit.border(tag, OUTLINE, 3)
	FancyKit.gradient(tag, { Color3.fromRGB(70, 76, 100), Color3.fromRGB(34, 36, 52) }, 90)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tag
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.Parent = tag
	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.fromOffset(16, 16)
	icon.BackgroundTransparency = 1
	icon.Image = ROBUX_ICON
	icon.ZIndex = z + 1
	icon.Parent = tag
	local l = text(tag, "", 16, WHITE, z + 1, 2)
	l.LayoutOrder = 2
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, 22)
	return l
end

function SpinPanel.Create(screen: ScreenGui): Panel
	local slices = Config.SpinWheelSlices
	local n = #slices
	local width = 360 / n

	local root = UiKit.Window(screen, "SpinPanel", GOLD)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(W, H)
	root.Visible = false
	root.ZIndex = Z
	local driver = FancyKit.driver(root)
	local shell = FancyKit.shell(root, "LUCKY SPIN", {
		Color3.fromRGB(255, 80, 170), Color3.fromRGB(170, 70, 240), Color3.fromRGB(255, 140, 40),
	}, HEADER, Z, driver, 50)

	-- ─── Çark ────────────────────────────────────────────────────────────
	local stage = Instance.new("Frame")
	stage.AnchorPoint = Vector2.new(0.5, 0)
	stage.Position = UDim2.new(0.5, 0, 0, HEADER + 8)
	stage.Size = UDim2.fromOffset(R * 2 + 60, R * 2 + 60)
	stage.BackgroundTransparency = 1
	stage.ZIndex = Z + 1
	stage.Parent = root

	-- Arkada ağır dönen ışınlar ve sıcak hale
	local rays = Instance.new("ImageLabel")
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromOffset(R * 2 + 120, R * 2 + 120)
	rays.BackgroundTransparency = 1
	rays.Image = UiArt.Image("Texture", "rays")
	rays.ImageColor3 = Color3.fromRGB(255, 220, 140)
	rays.ImageTransparency = 0.72
	rays.ZIndex = Z + 1
	rays.Parent = stage
	FancyKit.spin(rays, driver, 8)
	local halo = FancyKit.glow(stage, Color3.fromRGB(255, 190, 80), 1.05, 0.45, Z + 1)

	-- Altın çember ve ampuller
	local rim = Instance.new("Frame")
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.fromOffset(R * 2 + 36, R * 2 + 36)
	rim.BackgroundColor3 = WHITE
	rim.ZIndex = Z + 2
	rim.Parent = stage
	FancyKit.corner(rim, R + 18)
	FancyKit.border(rim, OUTLINE, 5)
	local rimGrad = FancyKit.gradient(rim, { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 180, 30), Color3.fromRGB(200, 100, 10) }, 90)
	local bulbs: { Frame } = {}
	for i = 1, 24 do
		local a = math.rad((i - 1) * 15)
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.new(0.5, math.sin(a) * (R + 10), 0.5, -math.cos(a) * (R + 10))
		b.Size = UDim2.fromOffset(11, 11)
		b.BackgroundColor3 = WHITE
		b.BorderSizePixel = 0
		b.ZIndex = Z + 3
		b.Parent = stage
		FancyKit.corner(b, 6)
		FancyKit.border(b, OUTLINE, 2)
		table.insert(bulbs, b)
	end

	local disc = Instance.new("ImageLabel")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(R * 2, R * 2)
	disc.BackgroundTransparency = 1
	disc.Image = UiArt.Image("Texture", "wheel_face")
	disc.ZIndex = Z + 4
	disc.Parent = stage

	-- Göbek: altın düğme (basınca da çeviriyor)
	local hub = Instance.new("TextButton")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(78, 78)
	hub.BackgroundColor3 = WHITE
	hub.AutoButtonColor = false
	hub.Text = ""
	hub.ZIndex = Z + 6
	hub.Parent = stage
	FancyKit.corner(hub, 39)
	FancyKit.border(hub, OUTLINE, 4)
	FancyKit.gradient(hub, { Color3.fromRGB(255, 244, 160), Color3.fromRGB(255, 190, 30), Color3.fromRGB(220, 120, 10) }, 90)
	local hubGloss = Instance.new("Frame")
	hubGloss.AnchorPoint = Vector2.new(0.5, 0)
	hubGloss.Position = UDim2.new(0.5, 0, 0, 7)
	hubGloss.Size = UDim2.fromOffset(52, 22)
	hubGloss.BackgroundColor3 = WHITE
	hubGloss.BackgroundTransparency = 0.6
	hubGloss.BorderSizePixel = 0
	hubGloss.ZIndex = Z + 7
	hubGloss.Parent = hub
	FancyKit.corner(hubGloss, 11)
	local hubText = FancyKit.title(hub, "SPIN", 22, WHITE, Color3.fromRGB(255, 236, 190), Z + 7, driver)
	hubText.Size = UDim2.fromScale(1, 1)
	FancyKit.juicy(hub, hub, 1.1, 0)

	-- İşaretçi (tepede, aşağı bakan kırmızı damla)
	local pointer = Instance.new("ImageLabel")
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.new(0.5, 0, 0.5, -R - 12)
	pointer.Size = UDim2.fromOffset(62, 62)
	pointer.BackgroundTransparency = 1
	pointer.Image = UiArt.Image("Texture", "wheel_pointer")
	pointer.ZIndex = Z + 8
	pointer.Parent = stage

	-- ─── Köşeler: süper çark ve jeton sayısı ─────────────────────────────
	local superBtn = FancyKit.button(root, UDim2.fromOffset(128, 62), GOLD, 18, Z + 10, driver, 0.8)
	superBtn.holder.Position = UDim2.fromOffset(14, HEADER + 14)
	local superTag = text(superBtn.holder, "", 15, Color3.fromRGB(255, 244, 170), Z + 16, 2.5)
	superTag.AnchorPoint = Vector2.new(0.5, 0.5)
	superTag.Position = UDim2.new(0.5, 0, 0, -2)
	superTag.Size = UDim2.fromOffset(120, 18)
	superTag.Rotation = -4

	local tokenPill = Instance.new("Frame")
	tokenPill.AnchorPoint = Vector2.new(1, 0)
	tokenPill.Position = UDim2.new(1, -14, 0, HEADER + 18)
	tokenPill.Size = UDim2.fromOffset(112, 40)
	tokenPill.BackgroundColor3 = WHITE
	tokenPill.ZIndex = Z + 10
	tokenPill.Parent = root
	FancyKit.corner(tokenPill, 20)
	FancyKit.border(tokenPill, OUTLINE, 3)
	FancyKit.gradient(tokenPill, { Color3.fromRGB(90, 190, 255), Color3.fromRGB(40, 110, 220) }, 90)
	FancyKit.gleam(tokenPill, driver, 4.4, 1.6, 0.4)
	local tokenText = text(tokenPill, "", 19, WHITE, Z + 12, 2.5)
	tokenText.Size = UDim2.fromScale(1, 1)

	--[[
		İHTİMALLER (2026-09-29): Robux'la çevirme satılıyor (ücretli rastgele
		ödül) — Roblox kuralı: ihtimaller satın almadan ÖNCE görünmeli.
		"ODDS" düğmesi çarkın üstüne bir tablo açıyor: normal ve süper çark,
		Config.SpinRewards / Config.SuperSpin.weights'ten hesaplanıyor.
	]]
	local oddsBtn = Instance.new("TextButton")
	oddsBtn.Name = "Odds"
	oddsBtn.AnchorPoint = Vector2.new(1, 0)
	oddsBtn.Position = UDim2.new(1, -14, 0, HEADER + 64)
	oddsBtn.Size = UDim2.fromOffset(112, 32)
	oddsBtn.BackgroundColor3 = Color3.fromRGB(34, 36, 52)
	oddsBtn.AutoButtonColor = true
	oddsBtn.Text = ""
	oddsBtn.ZIndex = Z + 10
	oddsBtn.Parent = root
	FancyKit.corner(oddsBtn, 16)
	FancyKit.border(oddsBtn, OUTLINE, 3)
	local oddsLabel = text(oddsBtn, "ⓘ ODDS", 17, WHITE, Z + 11, 2)
	oddsLabel.Size = UDim2.fromScale(1, 1)

	local oddsCard = Instance.new("Frame")
	oddsCard.Name = "OddsTable"
	oddsCard.AnchorPoint = Vector2.new(0.5, 0)
	oddsCard.Position = UDim2.new(0.5, 0, 0, HEADER + 104)
	oddsCard.Size = UDim2.fromOffset(W - 60, 300)
	oddsCard.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
	oddsCard.Visible = false
	oddsCard.ZIndex = Z + 40
	oddsCard.Active = true
	oddsCard.Parent = root
	FancyKit.corner(oddsCard, 16)
	FancyKit.border(oddsCard, OUTLINE, 3)
	do
		local function percents(weightOf: (any) -> number): { [string]: number }
			local total = 0
			for _, r in Config.SpinRewards do
				total += weightOf(r)
			end
			local out = {}
			for _, r in Config.SpinRewards do
				out[r.id] = if total > 0 then weightOf(r) / total * 100 else 0
			end
			return out
		end
		local normal = percents(function(r)
			return r.weight
		end)
		local super = percents(function(r)
			return Config.SuperSpin.weights[r.id] or 0
		end)
		local function pct(v: number): string
			return if v >= 10 or v == math.floor(v) then string.format("%d%%", math.floor(v + 0.5)) else string.format("%.1f%%", v)
		end
		local ROW = 32
		local head = text(oddsCard, "PRIZE", 16, Color3.fromRGB(170, 180, 210), Z + 41, 2)
		head.Position = UDim2.fromOffset(20, 10)
		head.Size = UDim2.new(0.5, -20, 0, 22)
		head.TextXAlignment = Enum.TextXAlignment.Left
		local h1 = text(oddsCard, "SPIN", 16, Color3.fromRGB(170, 180, 210), Z + 41, 2)
		h1.Position = UDim2.new(0.5, 0, 0, 10)
		h1.Size = UDim2.new(0.25, 0, 0, 22)
		local h2 = text(oddsCard, "SUPER", 16, Color3.fromRGB(255, 220, 110), Z + 41, 2)
		h2.Position = UDim2.new(0.75, -10, 0, 10)
		h2.Size = UDim2.new(0.25, 0, 0, 22)
		for i, r in Config.SpinRewards do
			local look = Config.SpinSliceLook[r.id]
			local y = 38 + (i - 1) * ROW
			local name = text(oddsCard, r.name, 20, if look then look.color:Lerp(WHITE, 0.35) else WHITE, Z + 41, 2)
			name.Position = UDim2.fromOffset(20, y)
			name.Size = UDim2.new(0.5, -20, 0, ROW)
			name.TextXAlignment = Enum.TextXAlignment.Left
			local a = text(oddsCard, pct(normal[r.id]), 20, WHITE, Z + 41, 2)
			a.Position = UDim2.new(0.5, 0, 0, y)
			a.Size = UDim2.new(0.25, 0, 0, ROW)
			local b = text(oddsCard, pct(super[r.id]), 20, Color3.fromRGB(255, 230, 140), Z + 41, 2)
			b.Position = UDim2.new(0.75, -10, 0, y)
			b.Size = UDim2.new(0.25, 0, 0, ROW)
		end
		local note = text(oddsCard, "Crewmates roll from the best planet you can reach (Jackpot: one higher).", 14, Color3.fromRGB(170, 180, 210), Z + 41, 1.5)
		note.AnchorPoint = Vector2.new(0.5, 1)
		note.Position = UDim2.new(0.5, 0, 1, -10)
		note.Size = UDim2.new(1, -30, 0, 18)
		oddsCard.Size = UDim2.fromOffset(W - 60, 38 + #Config.SpinRewards * ROW + 40)
	end
	oddsBtn.Activated:Connect(function()
		oddsCard.Visible = not oddsCard.Visible
		oddsLabel.Text = if oddsCard.Visible then "✕ CLOSE" else "ⓘ ODDS"
	end)

	-- ─── Alt kısım: +5 · SPIN · +1 ───────────────────────────────────────
	local ROW_BOTTOM = H - 46
	local spinBtn = FancyKit.button(root, UDim2.fromOffset(190, 76), GREEN, 34, Z + 10, driver, 0)
	spinBtn.holder.AnchorPoint = Vector2.new(0.5, 1)
	spinBtn.holder.Position = UDim2.fromOffset(W / 2, ROW_BOTTOM)

	local packBtn = FancyKit.button(root, UDim2.fromOffset(132, 62), PURPLE, 22, Z + 10, driver, 1.2)
	packBtn.holder.AnchorPoint = Vector2.new(0.5, 1)
	packBtn.holder.Position = UDim2.fromOffset(W / 2 - 173, ROW_BOTTOM)
	local packPrice = priceTag(packBtn.holder, Z + 14)

	local buyBtn = FancyKit.button(root, UDim2.fromOffset(132, 62), BLUE, 22, Z + 10, driver, 2.2)
	buyBtn.holder.AnchorPoint = Vector2.new(0.5, 1)
	buyBtn.holder.Position = UDim2.fromOffset(W / 2 + 173, ROW_BOTTOM)
	local buyPrice = priceTag(buyBtn.holder, Z + 14)
	buyPrice.Text = "..."

	local packLive = Config.SpinPack.id > 0
	packBtn.set(string.format("+%d SPINS", Config.SpinPack.count), if packLive then PURPLE else nil)
	packPrice.Text = if packLive then tostring(Config.SpinPack.robux) else "SOON"
	buyBtn.set("+1 SPIN", BLUE)
	task.spawn(function()
		local product = Config.Products.ExtraSpin
		if not product or product.id <= 0 then
			buyPrice.Text = "SOON"
			return
		end
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(product.id, Enum.InfoType.Product)
		end)
		buyPrice.Text = if ok and info and info.PriceInRobux then tostring(info.PriceInRobux) else "R$"
	end)

	local timerPill = Instance.new("Frame")
	timerPill.AnchorPoint = Vector2.new(0.5, 1)
	timerPill.Position = UDim2.new(0.5, 0, 1, -10)
	timerPill.Size = UDim2.fromOffset(W - 60, 28)
	timerPill.BackgroundColor3 = Color3.new(0, 0, 0)
	timerPill.BackgroundTransparency = 0.65
	timerPill.ZIndex = Z + 2
	timerPill.Parent = root
	FancyKit.corner(timerPill, 14)
	local timer = text(timerPill, "", 17, WHITE, Z + 3, 2)
	timer.Size = UDim2.fromScale(1, 1)
	timer.RichText = true

	-- ─── Ödül kartı ──────────────────────────────────────────────────────
	local prizeHolder = Instance.new("Frame")
	prizeHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	prizeHolder.Position = UDim2.new(0.5, 0, 0, HEADER + 8 + R + 30)
	prizeHolder.Size = UDim2.fromOffset(370, 190)
	prizeHolder.BackgroundTransparency = 1
	prizeHolder.Visible = false
	prizeHolder.ZIndex = Z + 30
	prizeHolder.Parent = root
	local prizeScale = Instance.new("UIScale")
	prizeScale.Parent = prizeHolder
	local prizeCard: Frame? = nil

	-- ─── Durum ───────────────────────────────────────────────────────────
	local requestRemote = Net.Get("SpinRequest")
	local resultRemote = Net.Get("SpinResult")
	local spinning = false
	local angle = 0          -- çarkın dönüşü (derece, saat yönü)
	local idle = true
	local superLook = false

	local function readyIn(): number
		local at = player:GetAttribute("SpinReadyAt")
		if typeof(at) ~= "number" then
			return 0
		end
		return math.max(0, at - Config.ServerNow())
	end

	local function clockText(seconds: number): string
		local t = math.ceil(seconds)
		return string.format("%02d:%02d:%02d", t // 3600, (t % 3600) // 60, t % 60)
	end

	local function count(attr: string): number
		local v = player:GetAttribute(attr)
		return if typeof(v) == "number" then v else 0
	end

	local function paintButton()
		local left = readyIn()
		local tokens = count("SpinTokens")
		local supers = count("SuperSpins")
		local ready = (left <= 0 or tokens > 0) and not spinning
		spinBtn.set(if spinning then "..." elseif left <= 0 then "FREE!" else "SPIN!", if ready then GREEN else nil)
		superBtn.holder.Visible = supers > 0
		superBtn.set("SUPER", if spinning then nil else GOLD)
		superTag.Text = string.format("x%d", supers)
		tokenPill.Visible = tokens > 0
		tokenText.Text = string.format("%d SPIN%s", tokens, if tokens == 1 then "" else "S")
		timer.Text = if left <= 0
			then '<font color="#7CFF6B">FREE SPIN READY!</font>'
			else 'Free spin in <font color="#FFD84A">' .. clockText(left) .. "</font>"
	end

	local function showPrize(rewardId: string, name: string, super: boolean?)
		local look = Config.SpinSliceLook[rewardId]
		local tint = if super then GOLD elseif look then look.color else PURPLE
		if prizeCard then
			prizeCard:Destroy()
		end
		local card = FancyKit.card(prizeHolder, tint, UDim2.fromScale(1, 1), Z + 30, driver, UDim2.fromScale(0.24, 0.5))
		prizeCard = card
		local iconName = PRIZE_ICON[rewardId]
		local icon = Instance.new("ImageLabel")
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.24, 0.5)
		icon.Size = UDim2.fromOffset(150, 150)
		icon.BackgroundTransparency = 1
		icon.Image = if iconName then UiArt.Image("Icon", iconName) else ""
		icon.ZIndex = Z + 33
		icon.Parent = card
		FancyKit.bob(icon, driver, 4, 2, 0, 5)
		local top = FancyKit.title(card, if super then "SUPER PRIZE!" else "YOU WON!", 32, Color3.fromRGB(255, 236, 90), Color3.fromRGB(255, 150, 20), Z + 33, driver)
		top.Position = UDim2.new(0.46, 0, 0, 24)
		top.Size = UDim2.new(0.52, 0, 0, 40)
		local body = FancyKit.title(card, name, 28, WHITE, Color3.fromRGB(230, 236, 255), Z + 33)
		body.Position = UDim2.new(0.46, 0, 0, 76)
		body.Size = UDim2.new(0.52, 0, 0, 80)
		for _, l in body:GetChildren() do
			if l:IsA("TextLabel") then
				l.TextWrapped = true
			end
		end
		prizeHolder.Visible = true
		prizeScale.Scale = 0.3
		TweenService:Create(prizeScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		SoundFX.Success()
		task.delay(2.8, function()
			if prizeCard == card then
				TweenService:Create(prizeScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
				task.wait(0.2)
				if prizeCard == card then
					prizeHolder.Visible = false
				end
			end
		end)
	end

	local function paintRim(super: boolean)
		superLook = super
		rimGrad.Color = if super
			then ColorSequence.new(Color3.fromRGB(255, 255, 220), Color3.fromRGB(255, 220, 90))
			else ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 150)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 30)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 100, 10)),
			})
		halo.ImageTransparency = if super then 0.15 else 0.45
	end

	--[[ Sunucunun seçtiği dilime, en az 5 tur dönüp yavaşlayarak. ]]
	local function spinTo(rewardId: string, name: string, duration: number, index: number, jitter: number, super: boolean?)
		spinning = true
		paintRim(super == true)
		idle = false
		prizeHolder.Visible = false
		paintButton()
		local center = (index - 0.5) * width + jitter * width
		local target = (-center) % 360
		local from = angle
		local base = from + 360 * 5
		local to = base + ((target - base) % 360)
		local started = os.clock()
		local lastSlice = -1
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			local u = math.clamp((os.clock() - started) / math.max(0.5, duration), 0, 1)
			local v = 1 - u
			angle = from + (to - from) * (1 - v * v * v)
			disc.Rotation = angle
			-- İşaretçi dilim sınırından geçerken sekiyor
			local under = math.floor(((-angle) % 360) / width)
			if under ~= lastSlice then
				lastSlice = under
				pointer.Rotation = -20
				TweenService:Create(pointer, TweenInfo.new(0.12), { Rotation = 0 }):Play()
			end
			if u >= 1 and conn then
				conn:Disconnect()
				spinning = false
				paintButton()
				showPrize(rewardId, name, super)
				task.delay(3, function()
					if not spinning then
						idle = true
						if superLook then
							paintRim(false)
						end
					end
				end)
			end
		end)
	end

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, resultRemote.OnClientEvent:Connect(function(rewardId, name, duration, index, jitter, super)
		if typeof(rewardId) ~= "string" or typeof(index) ~= "number" then
			return
		end
		root.Visible = true
		spinTo(rewardId, tostring(name), if typeof(duration) == "number" then duration else Config.SpinDuration, index,
			if typeof(jitter) == "number" then jitter else 0, super == true)
	end))

	local function trySpin()
		if spinning then
			return
		end
		-- Önce günlük bedava, yoksa jeton
		if readyIn() <= 0 then
			requestRemote:FireServer()
		elseif count("SpinTokens") > 0 then
			requestRemote:FireServer("token")
		end
	end
	spinBtn.button.MouseButton1Click:Connect(trySpin)
	hub.MouseButton1Click:Connect(trySpin)
	superBtn.button.MouseButton1Click:Connect(function()
		if not spinning and count("SuperSpins") > 0 then
			requestRemote:FireServer("super")
		end
	end)
	packBtn.button.MouseButton1Click:Connect(function()
		if Config.SpinPack.id > 0 and not spinning then
			MarketplaceService:PromptProductPurchase(player, Config.SpinPack.id)
		end
	end)
	buyBtn.button.MouseButton1Click:Connect(function()
		local product = Config.Products.ExtraSpin
		if product and product.id > 0 and not spinning then
			MarketplaceService:PromptProductPurchase(player, product.id)
		end
	end)
	for _, attr in { "SpinTokens", "SuperSpins" } do
		table.insert(conns, player:GetAttributeChangedSignal(attr):Connect(paintButton))
	end
	shell.close.Activated:Connect(function()
		root.Visible = false
	end)

	table.insert(conns, ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "SpinPrompt" then
			root.Visible = true
			paintButton()
		end
	end))

	-- Boştayken ağır dönüş, ampuller sırayla yanıyor, geri sayım saniyede bir
	local lastPaint = 0
	driver.add(function(t, dt)
		if idle then
			angle += dt * 12
			disc.Rotation = angle
		end
		local step = math.floor(t * (if spinning then 14 else 3))
		for i, b in bulbs do
			local on = (step + i) % 2 == 0
			b.BackgroundColor3 = if on then Color3.fromRGB(255, 255, 220) else Color3.fromRGB(255, 110, 40)
		end
		if t - lastPaint > 0.5 then
			lastPaint = t
			paintButton()
		end
	end)

	return {
		Open = function()
			root.Visible = true
			paintButton()
		end,
		Destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			driver.destroy()
			root:Destroy()
		end,
	}
end

return SpinPanel
