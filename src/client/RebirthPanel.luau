--!strict
-- Rebirth arayüzü.
--
-- Rebirth üssün önündeki tabelaya bağlı bir "R'ye basılı tut"tu. Oyunun en
-- büyük kararı sıradan bir promptun arkasındaydı ve rakibin üssüne giden
-- oyuncu kendi tabelasına yanlışlıkla basabiliyordu.
--
-- Artık sağ alttaki REBIRTH düğmesinden açılıyor: ne kaybedeceğin, ne
-- kazanacağın ve fiyat tek ekranda. Doğrulama sunucuda (TryRebirth).
--
-- Görsel dil: referans olarak bakılan "anka" amblemlerinin kompozisyonu
-- (madalyon + kanat + yükselen alev) ama figür anka değil, MÜRETTEBAT —
-- yanan bir tulum, küllerinden yeniden doğuyor. Hepsi Frame'den kuruluyor,
-- hazır görsel yok.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

-- Yalnızca tek pencere kuralı için (UiKit.Exclusive)
local UiKit = require(script.Parent.UiKit)

local RebirthPanel = {}

local player = Players.LocalPlayer

local SHELL = Color3.fromRGB(30, 24, 30)
local SHELL_DEEP = Color3.fromRGB(20, 16, 21)
local INK = Color3.fromRGB(240, 236, 232)
local MUTED = Color3.fromRGB(168, 156, 158)
local EMBER = Color3.fromRGB(240, 148, 42)      -- alev: dış
local CORE = Color3.fromRGB(252, 214, 96)       -- alev: iç
local ASH = Color3.fromRGB(96, 82, 88)
local LOSS = Color3.fromRGB(226, 108, 96)
local GAIN = Color3.fromRGB(128, 224, 150)

export type Panel = {
	Update: () -> (),
	Toggle: () -> (),
	Destroy: () -> (),
}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = parent
	return s
end

--[[
	═══ AMBLEM ══════════════════════════════════════════════════════════════

	Dairesel madalyon, içinde mürettebat silueti, arkasında yükselen alev
	dilleri ve iki yana açılan kanat.

	Tamamen Frame'den kuruluyor: her alev dili döndürülmüş bir dikdörtgen,
	kanatlar da kademeli dikdörtgen dizisi. Hazır bir görsel kullanmak daha
	kolay olurdu ama o zaman oyunun içindeki tek "resim" bu olurdu ve
	geri kalan her şey koddan üretilmiş geometriyle çelişirdi.

	`flames` dışarı döndürülüyor: panel açıkken nefes alıyorlar.
]]
local function buildEmblem(parent: Frame): { Frame }
	local flames: { Frame } = {}

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(132, 132)
	disc.BackgroundColor3 = SHELL_DEEP
	disc.BorderSizePixel = 0
	disc.Parent = parent
	corner(disc, 66)
	stroke(disc, EMBER, 2, 0.25)

	-- Alev dilleri: madalyonun arkasından çıkıyorlar
	for i = 1, 9 do
		local a = -70 + (i - 1) * 17.5
		local long = (i % 3 == 0)

		local flame = Instance.new("Frame")
		flame.Name = "Flame" .. i
		flame.AnchorPoint = Vector2.new(0.5, 1)
		flame.Position = UDim2.fromScale(0.5, 0.5)
		flame.Size = UDim2.fromOffset(if long then 9 else 6, if long then 86 else 62)
		flame.Rotation = a
		flame.BackgroundColor3 = if long then CORE else EMBER
		flame.BackgroundTransparency = 0.25
		flame.BorderSizePixel = 0
		flame.ZIndex = 0
		flame.Parent = parent
		corner(flame, 4)
		table.insert(flames, flame)
	end

	-- Kanatlar: iki yana açılan kademeli tüyler
	for _, side in { -1, 1 } do
		for i = 1, 4 do
			local feather = Instance.new("Frame")
			feather.Name = "Feather"
			feather.AnchorPoint = Vector2.new(0.5, 0.5)
			feather.Position = UDim2.fromScale(0.5, 0.5)
			feather.Size = UDim2.fromOffset(10, 34 + i * 9)
			feather.Rotation = side * (58 + i * 9)
			feather.BackgroundColor3 = EMBER:Lerp(SHELL_DEEP, i * 0.15)
			feather.BackgroundTransparency = 0.3
			feather.BorderSizePixel = 0
			feather.ZIndex = 0
			feather.Parent = parent
			corner(feather, 5)
		end
	end

	--[[
		Mürettebat silueti: gövde + sırt çantası + vizör. Oyunun her yerinde
		aynı üç parça; arayüzde de aynı olmalı ki "bu benim karakterim"
		bağlantısı kurulsun.
	]]
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.52)
	body.Size = UDim2.fromOffset(52, 66)
	body.BackgroundColor3 = CORE
	body.BorderSizePixel = 0
	body.ZIndex = 3
	body.Parent = disc
	corner(body, 24)

	local pack = Instance.new("Frame")
	pack.AnchorPoint = Vector2.new(0.5, 0.5)
	pack.Position = UDim2.fromScale(1.02, 0.52)
	pack.Size = UDim2.fromOffset(16, 34)
	pack.BackgroundColor3 = EMBER
	pack.BorderSizePixel = 0
	pack.ZIndex = 2
	pack.Parent = body
	corner(pack, 7)

	local visor = Instance.new("Frame")
	visor.AnchorPoint = Vector2.new(0.5, 0.5)
	visor.Position = UDim2.fromScale(0.38, 0.32)
	visor.Size = UDim2.fromOffset(30, 15)
	visor.BackgroundColor3 = SHELL_DEEP
	visor.BorderSizePixel = 0
	visor.ZIndex = 4
	visor.Parent = body
	corner(visor, 7)

	-- Küller: madalyonun altında dağılan noktalar
	for i = 1, 7 do
		local ash = Instance.new("Frame")
		ash.AnchorPoint = Vector2.new(0.5, 0.5)
		ash.Position = UDim2.fromScale(0.16 + i * 0.11, 0.9 + (i % 3) * 0.03)
		ash.Size = UDim2.fromOffset(4 + (i % 3), 4 + (i % 3))
		ash.BackgroundColor3 = ASH
		ash.BackgroundTransparency = 0.35
		ash.BorderSizePixel = 0
		ash.Parent = parent
		corner(ash, 3)
	end

	return flames
end

function RebirthPanel.Create(screen: ScreenGui): Panel
	local root = Instance.new("Frame")
	root.Name = "RebirthPanel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.5, 0)
	root.Size = UDim2.fromOffset(420, 470)
	root.BackgroundColor3 = SHELL
	root.BorderSizePixel = 0
	root.Visible = false
	root.ZIndex = 12
	root.Parent = screen
	-- Açılınca diğer pencereleri kapatır (mağaza, indeks...)
	UiKit.Exclusive(root)
	corner(root, 16)
	-- Diğer pencerelerle aynı kalın çerçeve (UiKit.Shell ile aynı değerler)
	stroke(root, EMBER:Lerp(Color3.new(1, 1, 1), 0.15), 2.6, 0.08)

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(22, 16)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = CORE
	title.Text = "REBIRTH"
	title.ZIndex = 13
	title.Parent = root

	local rank = Instance.new("TextLabel")
	rank.Position = UDim2.fromOffset(22, 42)
	rank.Size = UDim2.new(1, -80, 0, 16)
	rank.BackgroundTransparency = 1
	rank.Font = Enum.Font.GothamMedium
	rank.TextSize = 13
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.TextColor3 = MUTED
	rank.Text = ""
	rank.ZIndex = 13
	rank.Parent = root

	-- Kapatma düğmesi her pencerede aynı: kırmızı daire (UiKit.CloseButton)
	local close = UiKit.CloseButton(root)
	close.ZIndex = 14

	-- ─── Amblem ─────────────────────────────────────────────────────────────

	local art = Instance.new("Frame")
	art.Name = "Emblem"
	art.Position = UDim2.fromOffset(0, 62)
	art.Size = UDim2.new(1, 0, 0, 190)
	art.BackgroundTransparency = 1
	art.ZIndex = 13
	art.Parent = root

	local flames = buildEmblem(art)

	-- ─── Kazanç / kayıp ─────────────────────────────────────────────────────

	local ledger = Instance.new("Frame")
	ledger.Position = UDim2.fromOffset(22, 258)
	ledger.Size = UDim2.new(1, -44, 0, 118)
	ledger.BackgroundColor3 = SHELL_DEEP
	ledger.BorderSizePixel = 0
	ledger.ZIndex = 13
	ledger.Parent = root
	corner(ledger, 10)

	local ledgerPad = Instance.new("UIPadding")
	ledgerPad.PaddingTop = UDim.new(0, 10)
	ledgerPad.PaddingLeft = UDim.new(0, 12)
	ledgerPad.PaddingRight = UDim.new(0, 12)
	ledgerPad.Parent = ledger

	local ledgerLayout = Instance.new("UIListLayout")
	ledgerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ledgerLayout.Padding = UDim.new(0, 4)
	ledgerLayout.Parent = ledger

	--[[
		Ne kaybediyorsun / ne kazanıyorsun. Rebirth geri alınamaz; oyuncunun
		bedeli ÖNCEDEN görmesi gerekiyor. Prompt'ta sadece fiyat vardı, ne
		gittiğini kimse bilmiyordu.
	]]
	local function ledgerRow(order: number, mark: string, text: string, color: Color3): TextLabel
		local row = Instance.new("TextLabel")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 18)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 13
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = color
		row.Text = mark .. "  " .. text
		row.ZIndex = 14
		row.Parent = ledger
		return row
	end

	ledgerRow(1, "−", "All crewmates on your podiums", LOSS)
	ledgerRow(2, "−", "Every upgrade level", LOSS)
	ledgerRow(3, "−", "Your cash", LOSS)
	local gainRow = ledgerRow(4, "+", "", GAIN)
	ledgerRow(5, "+", "Unlocks the next floor for purchase", GAIN)

	-- ─── Onay ───────────────────────────────────────────────────────────────

	local confirm = Instance.new("TextButton")
	confirm.AnchorPoint = Vector2.new(0.5, 1)
	confirm.Position = UDim2.new(0.5, 0, 1, -20)
	confirm.Size = UDim2.new(1, -44, 0, 44)
	confirm.BackgroundColor3 = EMBER
	confirm.BorderSizePixel = 0
	confirm.AutoButtonColor = false
	confirm.Font = Enum.Font.GothamBold
	confirm.TextSize = 17
	confirm.TextColor3 = Color3.fromRGB(28, 18, 10)
	confirm.Text = "—"
	confirm.ZIndex = 13
	confirm.Parent = root
	corner(confirm, 10)

	local note = Instance.new("TextLabel")
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = UDim2.new(0.5, 0, 1, -68)
	note.Size = UDim2.new(1, -44, 0, 16)
	note.BackgroundTransparency = 1
	note.Font = Enum.Font.GothamMedium
	note.TextSize = 12
	note.TextColor3 = MUTED
	note.Text = "This cannot be undone."
	note.ZIndex = 13
	note.Parent = root

	local remote = Net.Get("RebirthBuy")
	confirm.MouseButton1Click:Connect(function()
		remote:FireServer()
	end)
	confirm.MouseEnter:Connect(function()
		confirm.BackgroundColor3 = EMBER:Lerp(Color3.new(1, 1, 1), 0.2)
	end)
	confirm.MouseLeave:Connect(function()
		confirm.BackgroundColor3 = EMBER
	end)

	-- ─── Durum ──────────────────────────────────────────────────────────────

	local function refresh()
		local rebirths = player:GetAttribute("Rebirths")
		rebirths = if typeof(rebirths) == "number" then rebirths else 0

		rank.Text = string.format("Rebirth %d", rebirths)

		--[[
			Tavan Config.MaxFloors - 1: üçüncü kat ikinci rebirth ile
			açılıyor, sonrasında rebirth'in verecek bir şeyi kalmıyor.
			Sunucudaki TryRebirth de aynı kuralı uyguluyor.
		]]
		if rebirths >= Config.MaxFloors - 1 then
			gainRow.Text = "+  Nothing left to unlock"
			confirm.Text = "MAXED"
			confirm.BackgroundColor3 = ASH
			confirm.Active = false
			note.Text = "You have every rebirth."
			return
		end

		local cost = player:GetAttribute("RebirthCost")
		cost = if typeof(cost) == "number" then cost else Config.GetRebirthCost(rebirths)

		gainRow.Text = string.format("+  Permanent income bonus (rebirth %d)", rebirths + 1)
		confirm.Text = "REBIRTH  ·  $" .. Config.FormatCash(cost)
		confirm.BackgroundColor3 = EMBER
		confirm.Active = true
		note.Text = "This cannot be undone."
	end

	-- ─── Görünürlük ─────────────────────────────────────────────────────────

	local shown = false
	local anim: RBXScriptConnection? = nil

	local function setShown(value: boolean)
		shown = value
		root.Visible = value

		if value then
			refresh()
			root.Size = UDim2.fromOffset(392, 440)
			TweenService:Create(
				root,
				TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(420, 470) }
			):Play()

			--[[ Alevler sadece panel AÇIKKEN canlanıyor. Kapalıyken her
			     karede dokuz Frame güncellemenin anlamı yok. ]]
			if not anim then
				anim = RunService.RenderStepped:Connect(function()
					local t = os.clock()
					for i, flame in flames do
						local phase = t * 2.1 + i * 0.7
						flame.BackgroundTransparency = 0.2 + (math.sin(phase) * 0.5 + 0.5) * 0.4
					end
				end)
			end
		elseif anim then
			anim:Disconnect()
			anim = nil
		end
	end

	close.MouseButton1Click:Connect(function()
		setShown(false)
	end)

	return {
		Update = function()
			if shown then
				refresh()
			end
		end,
		Toggle = function()
			setShown(not shown)
		end,
		Destroy = function()
			if anim then
				anim:Disconnect()
			end
			root:Destroy()
		end,
	}
end

return RebirthPanel
