--!strict
--[[
	Görev paneli: 30 dakikalık, 3 saatlik ve günlük hedefler.

	Sunucu (QuestService) "Quests" remote'uyla vade listesini gönderiyor;
	burada sadece çiziliyor. İlerleme sunucuda hesaplanıyor, istemci onu
	değiştiremiyor.

	Yer: sol kenar, nakit/gelir satırlarının altı. Sohbet de sol üstte
	durduğu için panel onun hemen altına düşüyor — oyuncunun gözü zaten
	oraya alışkın. Sağ üst üs paneline, alt orta bildirimlere ayrılmış.

	Geri sayım istemcide dönüyor: sunucu bitiş anını gönderiyor, saniyede
	bir paket yollamıyor.

	Başlığa tıklayınca katlanıyor. Ekran kalabalıksa oyuncu kapatabilmeli;
	kapalıyken bile başlıkta kaç görevin bittiği yazıyor.

	Kullanım (init.client.luau içinde, screen kurulduktan sonra):
		local QuestPanel = require(script.QuestPanel)
		local quests = QuestPanel.Create(screen)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local QuestPanel = {}

local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local ACCENT = Color3.fromRGB(255, 190, 90)
local GOOD = Color3.fromRGB(120, 255, 150)
local PANEL = Color3.fromRGB(18, 20, 28)
local TRACK = Color3.fromRGB(44, 50, 62)

local WIDTH = 300

export type Panel = {
	Destroy: () -> (),
}

type Entry = {
	id: string,
	text: string,
	value: number,
	goal: number,
	done: boolean,
	cash: boolean,
}

type Tier = {
	id: string,
	name: string,
	secondsLeft: number,
	reward: number,
	entries: { Entry },
}

function QuestPanel.Create(screen: ScreenGui): Panel
	local root = Instance.new("Frame")
	root.Name = "Quests"
	root.Position = UDim2.new(0, 24, 0, 104)
	root.Size = UDim2.new(0, WIDTH, 0, 40)
	root.BackgroundColor3 = PANEL
	root.BackgroundTransparency = 0.15
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = root

	-- ─── Başlık ─────────────────────────────────────────────────────────────

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 34)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextSize = 14
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = ACCENT
	header.Text = "  QUESTS"
	header.AutoButtonColor = false
	header.Parent = root

	local headerCount = Instance.new("TextLabel")
	headerCount.Name = "Count"
	headerCount.AnchorPoint = Vector2.new(1, 0)
	headerCount.Position = UDim2.new(1, -14, 0, 0)
	headerCount.Size = UDim2.new(0, 70, 0, 34)
	headerCount.BackgroundTransparency = 1
	headerCount.Font = Enum.Font.GothamMedium
	headerCount.TextSize = 13
	headerCount.TextXAlignment = Enum.TextXAlignment.Right
	headerCount.TextColor3 = MUTED
	headerCount.Text = ""
	headerCount.Parent = root

	-- ─── Gövde ──────────────────────────────────────────────────────────────

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.new(0, 0, 0, 34)
	body.Size = UDim2.new(1, 0, 0, 0)
	body.BackgroundTransparency = 1
	body.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = body

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = body

	--[[
		Vade bölümleri yeniden yaratılmıyor, güncelleniyor. Her pakette
		baştan kurmak, oyuncu tam tıklarken paneli altından çekiyordu.
	]]
	type Section = {
		frame: Frame,
		title: TextLabel,
		timer: TextLabel,
		rows: { { frame: Frame, label: TextLabel, fill: Frame, track: Frame } },
	}

	local sections: { [string]: Section } = {}
	local expanded = true
	local timers: { [string]: number } = {}

	local function newSection(tier: Tier, order: number): Section
		local frame = Instance.new("Frame")
		frame.Name = tier.id
		frame.LayoutOrder = order
		frame.Size = UDim2.new(1, 0, 0, 30)
		frame.BackgroundTransparency = 1
		frame.Parent = body

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(0.6, 0, 0, 18)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 12
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = MUTED
		title.Text = string.upper(tier.name)
		title.Parent = frame

		local timer = Instance.new("TextLabel")
		timer.Name = "Timer"
		timer.AnchorPoint = Vector2.new(1, 0)
		timer.Position = UDim2.new(1, 0, 0, 0)
		timer.Size = UDim2.new(0.4, 0, 0, 18)
		timer.BackgroundTransparency = 1
		timer.Font = Enum.Font.GothamMedium
		timer.TextSize = 12
		timer.TextXAlignment = Enum.TextXAlignment.Right
		timer.TextColor3 = MUTED
		timer.Text = ""
		timer.Parent = frame

		return { frame = frame, title = title, timer = timer, rows = {} }
	end

	local function newRow(section: Section, index: number)
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. index
		frame.Position = UDim2.new(0, 0, 0, 18 + (index - 1) * 34)
		frame.Size = UDim2.new(1, 0, 0, 32)
		frame.BackgroundTransparency = 1
		frame.Parent = section.frame

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 18)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = INK
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = ""
		label.Parent = frame

		local track = Instance.new("Frame")
		track.Position = UDim2.new(0, 0, 0, 21)
		track.Size = UDim2.new(1, 0, 0, 5)
		track.BackgroundColor3 = TRACK
		track.BorderSizePixel = 0
		track.Parent = frame

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = track

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = ACCENT
		fill.BorderSizePixel = 0
		fill.Parent = track

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill

		table.insert(section.rows, { frame = frame, label = label, fill = fill, track = track })
	end

	--[[ Panelin toplam yüksekliği içeriğe göre. ]]
	local function resize()
		if not expanded then
			root.Size = UDim2.new(0, WIDTH, 0, 34)
			return
		end

		local height = 12
		for _, section in sections do
			if section.frame.Visible then
				height += section.frame.AbsoluteSize.Y + 8
			end
		end

		body.Size = UDim2.new(1, 0, 0, height)
		root.Size = UDim2.new(0, WIDTH, 0, 34 + height)
	end

	local function apply(payload: { Tier })
		local doneCount, totalCount = 0, 0

		for order, tier in payload do
			local section = sections[tier.id]
			if not section then
				section = newSection(tier, order)
				sections[tier.id] = section
			end

			section.frame.Visible = true
			section.title.Text = string.upper(tier.name)
			timers[tier.id] = os.time() + tier.secondsLeft

			-- Eksik satırları yarat; fazlası gizleniyor
			while #section.rows < #tier.entries do
				newRow(section, #section.rows + 1)
			end
			for index = #tier.entries + 1, #section.rows do
				section.rows[index].frame.Visible = false
			end

			for index, entry in tier.entries do
				local row = section.rows[index]
				row.frame.Visible = true

				totalCount += 1
				if entry.done then
					doneCount += 1
				end

				local shown = if entry.cash
					then Config.FormatCash(entry.value)
					else tostring(entry.value)
				local target = if entry.cash
					then Config.FormatCash(entry.goal)
					else tostring(entry.goal)

				if entry.done then
					row.label.Text = "✓  " .. entry.text
					row.label.TextColor3 = GOOD
					row.fill.BackgroundColor3 = GOOD
					row.track.Visible = false
				else
					row.label.Text = string.format("%s   %s / %s", entry.text, shown, target)
					row.label.TextColor3 = INK
					row.fill.BackgroundColor3 = ACCENT
					row.track.Visible = true
				end

				TweenService:Create(
					row.fill,
					TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.new(math.clamp(entry.value / math.max(1, entry.goal), 0, 1), 0, 1, 0) }
				):Play()
			end

			section.frame.Size = UDim2.new(1, 0, 0, 18 + #tier.entries * 34)
		end

		-- Sunucudan gelmeyen vadeyi gizle
		for id, section in sections do
			local found = false
			for _, tier in payload do
				if tier.id == id then
					found = true
					break
				end
			end
			section.frame.Visible = found
		end

		headerCount.Text = string.format("%d / %d", doneCount, totalCount)
		headerCount.TextColor3 = if doneCount == totalCount and totalCount > 0 then GOOD else MUTED
		resize()
	end

	header.Activated:Connect(function()
		expanded = not expanded
		body.Visible = expanded
		header.Text = if expanded then "  QUESTS" else "  QUESTS  ▸"
		resize()
	end)

	local connection = Net.Get("Quests").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			apply(payload)
		end
	end)

	--[[
		Geri sayım. Saniyede bir yeter; her karede güncellemek aynı metni
		altmış kez yazmak olurdu.
	]]
	local elapsed = 0
	local tick = RunService.Heartbeat:Connect(function(delta)
		elapsed += delta
		if elapsed < 1 then
			return
		end
		elapsed = 0

		local now = os.time()
		for id, section in sections do
			local endsAt = timers[id]
			if endsAt then
				local left = math.max(0, endsAt - now)
				section.timer.Text = Config.FormatDuration(left)
				section.timer.TextColor3 = if left < 300 then ACCENT else MUTED
			end
		end
	end)

	return {
		Destroy = function()
			connection:Disconnect()
			tick:Disconnect()
			root:Destroy()
		end,
	}
end

return QuestPanel
