--!strict
--[[
	Sıralama tablosu: sunucudaki mürettebat, paraya göre.

	Roblox'un kendi oyuncu listesi kapalı (init.client, SetCoreGuiEnabled)
	ve yerini bu alıyor. Aynı yerde duruyor — sağ üst, oyuncunun listeyi
	aradığı köşe — ama oyunun dilinde: her satırda o oyuncunun ÜS RENGİNDE
	bir mürettebat. Sahada gördüğün renk ile tabloda gördüğün renk aynı,
	yani "şu mor üs kimin" sorusu tabloya bakınca cevaplanıyor.

	Sunucuya dokunmuyor: Cash/Income nitelik, Stolen leaderstats olarak
	zaten istemciye replike oluyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local UiKit = require(script.Parent.UiKit)

local Leaderboard = {}

local player = Players.LocalPlayer

local WIDTH = 260
local HEADER = 38
local ROW_H = 40
--[[
	En fazla altı satır. Sekiz oyuncunun hepsi gösterilince tablo 364
	piksele uzuyor ve küçük ekranda sağ alttaki düğme rayına iniyordu.
	Oyuncu ilk altıda değilse son satır ONUN satırı oluyor (gerçek
	sırasıyla): kendini her zaman görüyor.
]]
local MAX_ROWS = 6

-- İlk üçün sıra rozeti: altın, gümüş, bronz
local PODIUM = {
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(200, 210, 222),
	Color3.fromRGB(214, 140, 80),
}

export type Board = {
	Update: (colorOf: ((Player) -> Color3)?) -> (),
}

type Row = {
	frame: Frame,
	rank: TextLabel,
	figure: Frame,
	name: TextLabel,
	detail: TextLabel,
	cash: TextLabel,
	stroke: UIStroke,
	shownColor: Color3?,
}

local function number(p: Player, attribute: string): number
	local value = p:GetAttribute(attribute)
	return if typeof(value) == "number" then value else 0
end

--[[ Çalma sayısı leaderstats'ta; profil yüklenene kadar yok olabilir. ]]
local function stolenOf(p: Player): number
	local stats = p:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Stolen")
	if value and value:IsA("IntValue") then
		return value.Value
	end
	return 0
end

function Leaderboard.Create(screen: ScreenGui): Board
	local holder = UiKit.Shell(screen, "Leaderboard", UiKit.VISOR)
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -22, 0, 20)
	holder.Size = UDim2.fromOffset(WIDTH, HEADER + ROW_H + 8)
	holder.BackgroundTransparency = 0.08
	holder.ClipsDescendants = true

	-- ─── Başlık ─────────────────────────────────────────────────────────────

	local badge = Instance.new("Frame")
	badge.Position = UDim2.fromOffset(12, 8)
	badge.Size = UDim2.fromOffset(22, 22)
	badge.BackgroundTransparency = 1
	badge.Parent = holder
	UiKit.Crewmate(badge, 20, UiKit.VISOR)

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(40, 0)
	title.Size = UDim2.new(1, -110, 0, HEADER)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = UiKit.VISOR
	title.Text = "CREW"
	title.Parent = holder

	local count = Instance.new("TextLabel")
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -14, 0, 0)
	count.Size = UDim2.fromOffset(70, HEADER)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamBold
	count.TextSize = 12
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = UiKit.MUTED
	count.Parent = holder

	-- Başlığın altında ince ayraç
	local rule = Instance.new("Frame")
	rule.Position = UDim2.fromOffset(12, HEADER - 2)
	rule.Size = UDim2.new(1, -24, 0, 1)
	rule.BackgroundColor3 = UiKit.DIM
	rule.BackgroundTransparency = 0.5
	rule.BorderSizePixel = 0
	rule.Parent = holder

	-- ─── Satırlar ───────────────────────────────────────────────────────────

	local rows: { Row } = {}
	for index = 1, MAX_ROWS do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. index
		frame.Position = UDim2.fromOffset(6, HEADER + 4 + (index - 1) * ROW_H)
		frame.Size = UDim2.new(1, -12, 0, ROW_H - 4)
		frame.BackgroundColor3 = UiKit.ROW
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = holder
		UiKit.Corner(frame, 8)
		local stroke = UiKit.Stroke(frame, UiKit.VISOR, 1.2, 1)

		local rank = Instance.new("TextLabel")
		rank.Position = UDim2.fromOffset(4, 0)
		rank.Size = UDim2.new(0, 16, 1, 0)
		rank.BackgroundTransparency = 1
		rank.Font = Enum.Font.GothamBlack
		rank.TextSize = 12
		rank.TextColor3 = UiKit.MUTED
		rank.Parent = frame

		--[[ Oyuncunun üs rengindeki mürettebat. Renk OwnerColors'tan;
		     değişmedikçe yeniden çizilmiyor. ]]
		local figure = Instance.new("Frame")
		figure.Position = UDim2.fromOffset(22, 4)
		figure.Size = UDim2.fromOffset(28, 28)
		figure.BackgroundColor3 = UiKit.SHELL_DEEP
		figure.BorderSizePixel = 0
		figure.Parent = frame
		UiKit.Corner(figure, 14)

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(56, 3)
		name.Size = UDim2.new(1, -140, 0, 16)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = UiKit.INK
		name.Parent = frame

		local detail = Instance.new("TextLabel")
		detail.Position = UDim2.fromOffset(56, 19)
		detail.Size = UDim2.new(1, -140, 0, 13)
		detail.BackgroundTransparency = 1
		detail.Font = Enum.Font.GothamMedium
		detail.TextSize = 10
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.TextTruncate = Enum.TextTruncate.AtEnd
		detail.TextColor3 = UiKit.MUTED
		detail.Parent = frame

		local cash = Instance.new("TextLabel")
		cash.AnchorPoint = Vector2.new(1, 0.5)
		cash.Position = UDim2.new(1, -8, 0.5, 0)
		cash.Size = UDim2.fromOffset(78, 20)
		cash.BackgroundTransparency = 1
		cash.Font = Enum.Font.GothamBlack
		cash.TextSize = 13
		cash.TextXAlignment = Enum.TextXAlignment.Right
		cash.TextColor3 = UiKit.CREW.LIME
		cash.Parent = frame

		table.insert(rows, {
			frame = frame, rank = rank, figure = figure, name = name,
			detail = detail, cash = cash, stroke = stroke, shownColor = nil,
		})
	end

	local function update(colorOf: ((Player) -> Color3)?)
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			return number(a, "Cash") > number(b, "Cash")
		end)

		count.Text = string.format("%d / %d", #list, Config.PlotCount)

		-- Gösterilecekler: ilk altı; oyuncu dışarıda kaldıysa son satır onun
		local shownRanks: { number } = {}
		for index = 1, math.min(#list, MAX_ROWS) do
			shownRanks[index] = index
		end
		local myRank = table.find(list, player)
		if myRank and myRank > MAX_ROWS then
			shownRanks[MAX_ROWS] = myRank
		end

		for index, row in rows do
			local rank = shownRanks[index]
			local entry = if rank then list[rank] else nil
			if not entry or not rank then
				row.frame.Visible = false
				continue
			end

			local isMine = entry == player
			row.frame.Visible = true

			-- Kendi satırın: hafif dolgu + vizör çerçeve; göz seni arıyor
			row.frame.BackgroundTransparency = if isMine then 0.2 else 1
			row.stroke.Transparency = if isMine then 0.35 else 1

			row.rank.Text = tostring(rank)
			row.rank.TextColor3 = PODIUM[rank] or UiKit.DIM

			local tone = if colorOf then colorOf(entry) else UiKit.MUTED
			if row.shownColor ~= tone then
				row.shownColor = tone
				UiKit.ClearSlot(row.figure)
				UiKit.Corner(row.figure, 14)
				UiKit.Crewmate(row.figure, 20, tone)
			end

			row.name.Text = entry.DisplayName
			row.name.TextColor3 = if isMine then UiKit.VISOR else UiKit.INK
			row.detail.Text = string.format("+$%s/s  ·  %d stolen",
				Config.FormatCash(number(entry, "Income")), stolenOf(entry))
			row.cash.Text = "$" .. Config.FormatCash(number(entry, "Cash"))
		end

		local shown = math.clamp(#list, 1, MAX_ROWS)
		holder.Size = UDim2.fromOffset(WIDTH, HEADER + 6 + shown * ROW_H)
	end

	return { Update = update }
end

return Leaderboard
