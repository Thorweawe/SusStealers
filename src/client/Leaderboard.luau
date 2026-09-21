--!strict
-- Canlı sıralama tablosu: kim ne kadar para biriktirmiş, saniyede ne basıyor.
-- Sunucuya hiç dokunmuyor; Cash/Income nitelikleri zaten istemciye replike oluyor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Leaderboard = {}

local player = Players.LocalPlayer

local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local GOOD = Color3.fromRGB(120, 255, 150)
local MINE = Color3.fromRGB(255, 190, 90)
local PANEL = Color3.fromRGB(18, 20, 28)

local MAX_ROWS = 6
local ROW_HEIGHT = 20

export type Board = {
	Update: () -> (),
}

type Row = {
	frame: Frame,
	rank: TextLabel,
	name: TextLabel,
	stolen: TextLabel,
	income: TextLabel,
	cash: TextLabel,
}

--[[ Saniyelik gelir. Nitelik olarak istemciye replike oluyor. ]]
local function incomeOf(p: Player): number
	local value = p:GetAttribute("Income")
	return if typeof(value) == "number" then value else 0
end

local function cashOf(p: Player): number
	local value = p:GetAttribute("Cash")
	return if typeof(value) == "number" then value else 0
end

--[[ Çalma sayısı leaderstats'ta tutuluyor; profil yüklenene kadar yok olabilir. ]]
local function stolenOf(p: Player): number
	local stats = p:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Stolen")
	if value and value:IsA("IntValue") then
		return value.Value
	end
	return 0
end

function Leaderboard.Create(screen: ScreenGui): Board
	local holder = Instance.new("Frame")
	holder.Name = "Leaderboard"
	holder.Position = UDim2.new(0, 24, 0, 104)
	holder.Size = UDim2.new(0, 360, 0, 42 + MAX_ROWS * ROW_HEIGHT + 10)
	holder.BackgroundColor3 = PANEL
	holder.BackgroundTransparency = 0.2
	holder.BorderSizePixel = 0
	holder.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = holder

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = holder

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = MUTED
	title.Text = "TOP PLAYERS"
	title.Parent = holder

	--[[ Sütun başlıkları. Önce satır içinde bir simge (↯) denendi ama Gotham
	     fontunda o karakter yok, kutu olarak çıkıyordu. ]]
	local function newHeader(text: string, rightOffset: number, width: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = text
		label.AnchorPoint = Vector2.new(1, 0)
		label.Position = UDim2.new(1, -rightOffset, 0, 20)
		label.Size = UDim2.new(0, width, 0, 14)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 10
		label.TextXAlignment = Enum.TextXAlignment.Right
		label.TextColor3 = MUTED
		label.TextTransparency = 0.35
		label.Text = text
		label.Parent = holder
		return label
	end

	newHeader("STOLEN", 170, 44)
	newHeader("INCOME", 92, 72)
	newHeader("CASH", 0, 88)

	local rows: { Row } = {}
	for index = 1, MAX_ROWS do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. index
		frame.Position = UDim2.new(0, 0, 0, 38 + (index - 1) * ROW_HEIGHT)
		frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		frame.BackgroundTransparency = 1
		frame.Visible = false
		frame.Parent = holder

		local rank = Instance.new("TextLabel")
		rank.Size = UDim2.new(0, 20, 1, 0)
		rank.BackgroundTransparency = 1
		rank.Font = Enum.Font.GothamBold
		rank.TextSize = 13
		rank.TextXAlignment = Enum.TextXAlignment.Left
		rank.TextColor3 = MUTED
		rank.Parent = frame

		local name = Instance.new("TextLabel")
		name.Position = UDim2.new(0, 20, 0, 0)
		name.Size = UDim2.new(1, -226, 1, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamMedium
		name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = INK
		name.Parent = frame

		local stolen = Instance.new("TextLabel")
		stolen.AnchorPoint = Vector2.new(1, 0)
		stolen.Position = UDim2.new(1, -170, 0, 0)
		stolen.Size = UDim2.new(0, 44, 1, 0)
		stolen.BackgroundTransparency = 1
		stolen.Font = Enum.Font.GothamMedium
		stolen.TextSize = 13
		stolen.TextXAlignment = Enum.TextXAlignment.Right
		stolen.TextColor3 = MUTED
		stolen.Parent = frame

		local income = Instance.new("TextLabel")
		income.AnchorPoint = Vector2.new(1, 0)
		income.Position = UDim2.new(1, -92, 0, 0)
		income.Size = UDim2.new(0, 72, 1, 0)
		income.BackgroundTransparency = 1
		income.Font = Enum.Font.GothamMedium
		income.TextSize = 13
		income.TextXAlignment = Enum.TextXAlignment.Right
		income.TextColor3 = MUTED
		income.Parent = frame

		local cash = Instance.new("TextLabel")
		cash.AnchorPoint = Vector2.new(1, 0)
		cash.Position = UDim2.new(1, 0, 0, 0)
		cash.Size = UDim2.new(0, 88, 1, 0)
		cash.BackgroundTransparency = 1
		cash.Font = Enum.Font.GothamBold
		cash.TextSize = 13
		cash.TextXAlignment = Enum.TextXAlignment.Right
		cash.TextColor3 = GOOD
		cash.Parent = frame

		table.insert(rows, { frame = frame, rank = rank, name = name, stolen = stolen, income = income, cash = cash })
	end

	local function update()
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			return cashOf(a) > cashOf(b)
		end)

		for index, row in rows do
			local entry = list[index]
			if not entry then
				row.frame.Visible = false
				continue
			end

			local isMine = entry == player
			row.frame.Visible = true
			row.rank.Text = tostring(index)
			row.rank.TextColor3 = if isMine then MINE else MUTED
			row.name.Text = entry.DisplayName
			row.name.TextColor3 = if isMine then MINE else INK
			row.stolen.Text = tostring(stolenOf(entry))
			row.stolen.TextColor3 = if isMine then MINE else MUTED
			row.income.Text = "+$" .. Config.FormatCash(incomeOf(entry)) .. "/s"
			row.income.TextColor3 = if isMine then MINE else MUTED
			row.cash.Text = "$" .. Config.FormatCash(cashOf(entry))
			row.cash.TextColor3 = if isMine then MINE else GOOD
		end

		-- Oyuncu sayısı azaldıysa panel de kısalsın
		local shown = math.min(#list, MAX_ROWS)
		holder.Size = UDim2.new(0, 360, 0, 42 + math.max(shown, 1) * ROW_HEIGHT + 10)
	end

	return { Update = update }
end

return Leaderboard
