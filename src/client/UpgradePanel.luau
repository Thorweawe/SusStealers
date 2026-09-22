--!strict
-- Yükseltme arayüzü. Üssündeki kulübenin önüne basınca açılıyor.
--
-- Eskiden her yükseltme için üsse fiziksel bir tabela dikiliyordu ve her
-- biri ayrı ProximityPrompt istiyordu: dört tabela, dört "basılı tut",
-- üssün etrafı kalabalık. Şimdi kulübenin önünde görünmez bir alan var;
-- oyuncu oraya basınca bütün liste tek seferde açılıyor.
--
-- Seviyeler oyuncunun niteliklerinden okunuyor (UpgradeService yazıyor),
-- maliyet Config'ten hesaplanıyor. Satın alma UpgradeBuy remote'una
-- gidiyor; doğrulamanın tamamı sunucuda.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UpgradePanel = {}

local player = Players.LocalPlayer

--[[
	Palet. Among Us'ın kendi arayüzü: koyu mavi-gri gövde, açık gri kenar,
	dolgu için mürettebat renkleri. Referans olarak bakılan Roblox
	yükseltme arayüzleri parlak mavi/kırmızıydı; o ton haritanın geri
	kalanıyla çakışıyordu.
]]
local SHELL = Color3.fromRGB(38, 46, 56)
local SHELL_DARK = Color3.fromRGB(27, 33, 41)
local EDGE = Color3.fromRGB(150, 164, 178)
local INK = Color3.fromRGB(236, 242, 248)
local MUTED = Color3.fromRGB(150, 163, 180)
local GOLD = Color3.fromRGB(226, 190, 96)
local GOOD = Color3.fromRGB(120, 220, 140)
-- Kutucuk yuvası sayısı. Tavan bundan büyükse her kutucuk birden fazla
-- seviyeyi temsil ediyor; 24 ayrı kutucuk çizilecek yer yok.
local PIP_SLOTS = 12

local DIM = Color3.fromRGB(64, 74, 88)

-- Her yükseltmenin kendi mürettebat rengi: satırlar birbirinden ayrılsın
local TINT: { [string]: Color3 } = {
	ConveyorSpeed = Color3.fromRGB(56, 200, 190),
	UnitGuard = Color3.fromRGB(120, 180, 90),
	CarrySpeed = Color3.fromRGB(226, 150, 70),
	LockPower = Color3.fromRGB(190, 110, 210),
}

--[[
	Tetik alanının yarıçapı.

	11 studda panel kulübenin epey uzağından açılıyordu: oyuncu yanından
	geçerken ekranın yarısı doluyor, kapatmak için geri çekilmek
	gerekiyordu. 6'da kulübenin önüne GELMEK gerekiyor — açılması bir
	niyet, kaza değil.
]]
local REACH = 6

export type Panel = {
	Update: () -> (),
	Destroy: () -> (),
}

type Row = {
	frame: Frame,
	name: TextLabel,
	cost: TextLabel,
	button: TextButton,
	pips: { Frame },
	def: Config.UpgradeDef,
}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = parent
end

function UpgradePanel.Create(screen: ScreenGui): Panel
	--[[
		Kök çerçeve ekranın ortasında ama biraz aşağıda: üstte nakit ve üs
		paneli var, ortayı tam kaplarsa oyuncu kendi karakterini göremiyor.
	]]
	local root = Instance.new("Frame")
	root.Name = "UpgradePanel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.56, 0)
	--[[
		Panel 460 genişti ve satır başına 64 piksel ayırıyordu; dört
		yükseltmeyle ekranın ortasında 352 piksellik bir blok oluyordu.
		380x(76+52n) aynı bilgiyi veriyor, arkasındaki oyunu kapatmadan.
	]]
	root.Size = UDim2.fromOffset(380, 76 + #Config.Upgrades * 52)
	root.BackgroundColor3 = SHELL
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = screen
	corner(root, 14)
	stroke(root, EDGE, 1.5, 0.4)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = root

	-- ─── Başlık ─────────────────────────────────────────────────────────────

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 38)
	header.BackgroundTransparency = 1
	header.Parent = root

	--[[
		Başlıktaki küçük mürettebat rozeti. Tezgâhın arkasındaki satıcıyla
		aynı renk; arayüzün "o adamdan alıyorum" olduğunu anlatıyor.
	]]
	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromOffset(28, 32)
	badge.Position = UDim2.fromOffset(0, 6)
	badge.BackgroundColor3 = Color3.fromRGB(122, 112, 148)
	badge.BorderSizePixel = 0
	badge.Parent = header
	corner(badge, 12)

	local visor = Instance.new("Frame")
	visor.Size = UDim2.fromOffset(16, 8)
	visor.Position = UDim2.fromOffset(9, 8)
	visor.BackgroundColor3 = Color3.fromRGB(240, 226, 150)
	visor.BorderSizePixel = 0
	visor.Parent = badge
	corner(visor, 4)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(40, 2)
	title.Size = UDim2.new(1, -40, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = GOLD
	title.Text = "UPGRADES"
	title.Parent = header

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Position = UDim2.fromOffset(40, 26)
	hint.Size = UDim2.new(1, -40, 0, 16)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 13
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = MUTED
	hint.Text = "Permanent. Step away to close."
	hint.Parent = header

	-- ─── Satırlar ───────────────────────────────────────────────────────────

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(0, 52)
	list.Size = UDim2.new(1, 0, 1, -44)
	list.BackgroundTransparency = 1
	list.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local rows: { Row } = {}

	for index, def in Config.Upgrades do
		local tint = TINT[def.id] or GOLD

		local frame = Instance.new("Frame")
		frame.Name = def.id
		frame.LayoutOrder = index
		frame.Size = UDim2.new(1, 0, 0, 46)
		frame.BackgroundColor3 = SHELL_DARK
		frame.BorderSizePixel = 0
		frame.Parent = list
		corner(frame, 10)

		-- Sol kenarda renk şeridi: satırları bir bakışta ayırıyor
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 4, 1, -12)
		stripe.Position = UDim2.fromOffset(0, 6)
		stripe.BackgroundColor3 = tint
		stripe.BorderSizePixel = 0
		stripe.Parent = frame
		corner(stripe, 2)

		local name = Instance.new("TextLabel")
		name.Name = "Name"
		name.Position = UDim2.fromOffset(16, 8)
		name.Size = UDim2.new(1, -120, 0, 18)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 16
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = INK
		name.Text = def.name
		name.Parent = frame

		--[[
			Seviye çubuğu tek bir dolgu değil, seviye başına bir KUTUCUK.
			Referans arayüzlerde de öyle: "12 seviyeden 4'ü" bilgisini
			saymadan, bakışta veriyor. Tek dolgulu çubukta oyuncu kaç
			seviye kaldığını bilemiyor.
		]]
		local pips: { Frame } = {}
		local pipArea = Instance.new("Frame")
		pipArea.Name = "Pips"
		pipArea.Position = UDim2.fromOffset(16, 32)
		pipArea.Size = UDim2.new(1, -132, 0, 9)
		pipArea.BackgroundTransparency = 1
		pipArea.Parent = frame

		local pipLayout = Instance.new("UIListLayout")
		pipLayout.FillDirection = Enum.FillDirection.Horizontal
		pipLayout.Padding = UDim.new(0, 3)
		pipLayout.Parent = pipArea

		--[[
			Tavan artık sabit değil: kat açtıkça ikiye katlanıyor
			(6 / 12 / 24). Yirmi dört kutucuk çizilemez, birkaç piksel
			kalırlar. Onun yerine SABİT sayıda kutucuk çiziyoruz ve her
			biri birden fazla seviyeyi temsil edebiliyor; bakışta
			ilerlemeyi yine veriyor, sayısı da yazıda duruyor.
		]]
		local pipCount = math.min(PIP_SLOTS, Config.GetUpgradeCeiling(def))

		for slot = 1, pipCount do
			local pip = Instance.new("Frame")
			pip.Name = "Pip" .. slot
			pip.LayoutOrder = slot
			pip.Size = UDim2.new(1 / pipCount, -3, 1, 0)
			pip.BackgroundColor3 = DIM
			pip.BorderSizePixel = 0
			pip.Parent = pipArea
			corner(pip, 3)
			table.insert(pips, pip)
		end

		local button = Instance.new("TextButton")
		button.Name = "Buy"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Size = UDim2.fromOffset(92, 30)
		button.BackgroundColor3 = tint
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.TextColor3 = Color3.fromRGB(16, 20, 26)
		button.Text = "—"
		button.Parent = frame
		corner(button, 8)

		local cost = Instance.new("TextLabel")
		cost.Name = "Cost"
		cost.AnchorPoint = Vector2.new(1, 0)
		cost.Position = UDim2.new(1, -10, 0, 6)
		cost.Size = UDim2.fromOffset(110, 14)
		cost.BackgroundTransparency = 1
		cost.Font = Enum.Font.GothamMedium
		cost.TextSize = 12
		cost.TextXAlignment = Enum.TextXAlignment.Right
		cost.TextColor3 = MUTED
		cost.Text = ""
		cost.Parent = frame

		--[[
			Tıklama doğrudan remote'a gidiyor, istemci hiçbir şey
			doğrulamıyor. Buton "yeterli paran yok" diye kapatılmıyor
			bilerek: sunucu zaten reddediyor ve oyuncuya fiyatı söyleyen
			bir bildirim basıyor. İstemcide kapatmak, fiyatı okumayan
			oyuncuya hiçbir şey anlatmıyor.
		]]
		local buyRemote = Net.Get("UpgradeBuy")
		button.MouseButton1Click:Connect(function()
			buyRemote:FireServer(def.id)

			-- Küçük basma geri bildirimi
			local press = TweenService:Create(
				button,
				TweenInfo.new(0.08, Enum.EasingStyle.Quad),
				{ Size = UDim2.fromOffset(104, 32) }
			)
			press:Play()
			press.Completed:Connect(function()
				TweenService:Create(
					button,
					TweenInfo.new(0.12, Enum.EasingStyle.Quad),
					{ Size = UDim2.fromOffset(110, 36) }
				):Play()
			end)
		end)

		button.MouseEnter:Connect(function()
			button.BackgroundColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.25)
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = tint
		end)

		table.insert(rows, {
			frame = frame,
			name = name,
			cost = cost,
			button = button,
			pips = pips,
			def = def,
		})
	end

	-- ─── Güncelleme ─────────────────────────────────────────────────────────

	local function refresh()
		for _, row in rows do
			local level = player:GetAttribute("Upg_" .. row.def.id)
			level = if typeof(level) == "number" then level else 0

			--[[
				Tavan oyuncunun açık kat sayısına bağlı. Sunucu onu
				"UpgradeFloors" niteliğine yazıyor; nitelik replike
				olduğu için ayrı remote gerekmiyor.
			]]
			local floors = player:GetAttribute("UpgradeFloors")
			floors = if typeof(floors) == "number" then floors else 1
			local maxLevel = Config.GetUpgradeMaxLevel(row.def, floors)

			-- Kutucuk sayısı sabit, seviye tavanı değişken: doluluk oranla
			local filled = math.floor(#row.pips * (level / math.max(1, maxLevel)) + 0.0001)
			for i, pip in row.pips do
				pip.BackgroundColor3 = if i <= filled then (TINT[row.def.id] or GOLD) else DIM
			end

			row.name.Text = string.format("%s  %d/%d", row.def.name, level, maxLevel)

			local price = Config.GetUpgradeCost(row.def.id, level, floors)
			if price then
				row.button.Text = "$" .. Config.FormatCash(price)
				row.button.BackgroundColor3 = TINT[row.def.id] or GOLD
				row.button.Active = true
				row.cost.Text = "NEXT LEVEL"
				row.cost.TextColor3 = MUTED
			elseif floors < Config.MaxFloors then
				-- Bu katın tavanı doldu ama oyun bitmedi: üst kat devamını açıyor
				row.button.Text = "LOCKED"
				row.button.BackgroundColor3 = DIM
				row.button.Active = false
				row.cost.Text = "NEXT FLOOR"
				row.cost.TextColor3 = MUTED
			else
				row.button.Text = "MAX"
				row.button.BackgroundColor3 = DIM
				row.button.Active = false
				row.cost.Text = "COMPLETE"
				row.cost.TextColor3 = GOOD
			end
		end
	end

	--[[
		Kendi üssümüzün tetik alanına yakın mıyız?

		Sadece KENDİ üssümüzdeki alan sayılıyor: rakibin kulübesine basınca
		açılırsa oyuncu onun yükseltmelerini alıyormuş gibi görünüyor, ki
		sunucu zaten reddediyor ama arayüz yalan söylemiş oluyor.
	]]
	local function nearOwnBooth(): boolean
		local char = player.Character
		local rootPart = char and char:FindFirstChild("HumanoidRootPart")
		if not (rootPart and rootPart:IsA("BasePart")) then
			return false
		end

		local plots = workspace:FindFirstChild("Plots")
		local assigned = player:GetAttribute("Plot")
		if not (plots and typeof(assigned) == "string") then
			return false
		end

		local plot = plots:FindFirstChild(assigned)
		local booth = plot and plot:FindFirstChild("UpgradeBooth")
		local zone = booth and booth:FindFirstChild("UpgradeZone")
		if not (zone and zone:IsA("BasePart")) then
			return false
		end

		-- Yükseklik farkını yok sayıyoruz: üst kattan bakarken açılmasın
		local delta = rootPart.Position - zone.Position
		if math.abs(delta.Y) > 12 then
			return false
		end
		return Vector2.new(delta.X, delta.Z).Magnitude <= REACH
	end

	local shown = false

	local function update()
		local near = nearOwnBooth()

		if near ~= shown then
			shown = near
			root.Visible = near
			if near then
				-- Açılırken küçükten büyüyor: pencerenin nereden geldiği belli
				root.Size = UDim2.fromOffset(440, 86 + #Config.Upgrades * 64)
				TweenService:Create(
					root,
					TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(460, 96 + #Config.Upgrades * 64) }
				):Play()
			end
		end

		if near then
			refresh()
		end
	end

	return {
		Update = update,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return UpgradePanel
