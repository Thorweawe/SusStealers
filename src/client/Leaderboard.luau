--!strict
--[[
	Sıralama tablosu: sunucudaki mürettebat, paraya göre.

	Roblox'un kendi oyuncu listesi kapalı (init.client, SetCoreGuiEnabled)
	ve yerini bu alıyor. Aynı yerde duruyor — sağ üst, oyuncunun listeyi
	aradığı köşe — ama oyunun dilinde.

	Her satırda oyuncunun KENDİ Roblox karakterinin yüzü (headshot), çevresinde
	ÜS RENGİNDE halka; satırın kartı da o renkte. Sahada gördüğün renk ile
	tabloda gördüğün renk aynı, yüz de kim olduğunu söylüyor. (Eskiden yüz
	yerine üs rengi bir Among Us karakteri vardı.) Görünüş mağaza dilinde
	(CardKit): renkli başlık şeridi, ışınlı kartlar, kalın yazılar, ilk üçe
	altın/gümüş/bronz rozet.

	Sunucuya dokunmuyor: Cash/Income nitelik, Stolen leaderstats olarak
	zaten istemciye replike oluyor. Yüz görselleri Roblox'un küçük resim
	servisinden bir kez isteniyor ve önbellekte tutuluyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local CardKit = require(script.Parent.CardKit)
local UiKit = require(script.Parent.UiKit)

local Leaderboard = {}

local player = Players.LocalPlayer

local WIDTH = 270
local HEADER = 36
local ROW_H = 46
--[[
	En fazla altı satır. Sekiz oyuncunun hepsi gösterilince tablo uzuyor ve
	küçük ekranda sağdaki düğme rayına iniyordu. Oyuncu ilk altıda değilse
	son satır ONUN satırı oluyor (gerçek sırasıyla): kendini her zaman görüyor.
]]
local MAX_ROWS = 6
local HEADER_COLOR = Color3.fromRGB(30, 160, 200)

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
	card: Frame,
	rank: TextLabel,
	rankBadge: Frame,
	ring: Frame,
	face: ImageLabel,
	name: TextLabel,
	detail: TextLabel,
	cash: TextLabel,
	mine: UIStroke,
	shownColor: Color3?,
	shownUser: number?,
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

-- Yüz görselleri: UserId -> içerik kimliği (istek bir kez)
local faces: { [number]: string } = {}
local pending: { [number]: boolean } = {}
local function faceOf(userId: number, onReady: (string) -> ())
	local cached = faces[userId]
	if cached then
		onReady(cached)
		return
	end
	if pending[userId] then
		return
	end
	pending[userId] = true
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		pending[userId] = nil
		if ok and typeof(content) == "string" then
			faces[userId] = content
			onReady(content)
		end
	end)
end

function Leaderboard.Create(screen: ScreenGui): Board
	local holder = Instance.new("Frame")
	holder.Name = "Leaderboard"
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -22, 0, 20)
	holder.Size = UDim2.fromOffset(WIDTH, HEADER + ROW_H + 8)
	holder.BackgroundColor3 = CardKit.BODY
	holder.BackgroundTransparency = 0.08
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.Parent = screen
	CardKit.corner(holder, 14)
	CardKit.gradient(holder, CardKit.BODY, CardKit.BODY_DEEP)
	CardKit.border(holder, CardKit.OUTLINE, 3)

	-- ─── Başlık şeridi ──────────────────────────────────────────────────────

	local head = Instance.new("Frame")
	head.Size = UDim2.new(1, 0, 0, HEADER)
	head.BackgroundColor3 = HEADER_COLOR
	head.BorderSizePixel = 0
	head.ClipsDescendants = true
	head.Parent = holder
	CardKit.corner(head, 14)
	CardKit.gradient(head, HEADER_COLOR:Lerp(CardKit.WHITE, 0.2), HEADER_COLOR:Lerp(Color3.new(0, 0, 0), 0.15))
	local foot = Instance.new("Frame")
	foot.Position = UDim2.new(0, 0, 1, -12)
	foot.Size = UDim2.new(1, 0, 0, 12)
	foot.BackgroundColor3 = HEADER_COLOR:Lerp(Color3.new(0, 0, 0), 0.12)
	foot.BorderSizePixel = 0
	foot.Parent = head
	for i, x in { 0.62, 0.7 } do
		local stripe = Instance.new("Frame")
		stripe.AnchorPoint = Vector2.new(0.5, 0.5)
		stripe.Position = UDim2.fromScale(x, 0.5)
		stripe.Size = UDim2.fromOffset(if i == 1 then 22 else 9, 90)
		stripe.Rotation = 30
		stripe.BackgroundColor3 = CardKit.WHITE
		stripe.BackgroundTransparency = 0.8
		stripe.BorderSizePixel = 0
		stripe.Parent = head
	end
	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.Size = UDim2.fromOffset(24, 24)
	icon.BackgroundTransparency = 1
	icon.Parent = head
	UiKit.Crewmate(icon, 22, Color3.fromRGB(230, 250, 255))

	local title = CardKit.bold(head, "CREW", 22, CardKit.WHITE, 3, 2.5)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(40, 0)
	title.Size = UDim2.new(1, -120, 1, 0)

	local count = CardKit.bold(head, "", 16, CardKit.WHITE, 3, 2)
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -12, 0, 0)
	count.Size = UDim2.fromOffset(70, HEADER)
	count.TextXAlignment = Enum.TextXAlignment.Right

	local rule = Instance.new("Frame")
	rule.Position = UDim2.fromOffset(0, HEADER - 2)
	rule.Size = UDim2.new(1, 0, 0, 3)
	rule.BackgroundColor3 = CardKit.OUTLINE
	rule.BorderSizePixel = 0
	rule.Parent = holder

	-- ─── Satırlar ───────────────────────────────────────────────────────────

	local rows: { Row } = {}
	for index = 1, MAX_ROWS do
		local card = CardKit.card(holder, UiKit.VISOR, UDim2.new(1, -12, 0, ROW_H - 5), 2, UDim2.fromScale(0.2, 0.5), 200)
		card.Name = "Row" .. index
		card.Position = UDim2.fromOffset(6, HEADER + 5 + (index - 1) * ROW_H)
		card.Visible = false
		-- Kendi satırın: sarı kalın çerçeve (göz seni arıyor)
		local mine = Instance.new("UIStroke")
		mine.Color = CardKit.YELLOW
		mine.Thickness = 2.5
		mine.Enabled = false
		mine.Parent = card:FindFirstChild("Frame") :: Frame

		-- Yüz: üs rengi halkanın içinde avatarın başı
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0, 0.5)
		ring.Position = UDim2.new(0, 6, 0.5, 0)
		ring.Size = UDim2.fromOffset(34, 34)
		ring.BackgroundColor3 = UiKit.VISOR
		ring.BorderSizePixel = 0
		ring.ZIndex = 4
		ring.Parent = card
		CardKit.corner(ring, 17)
		CardKit.border(ring, CardKit.OUTLINE, 2)
		local face = Instance.new("ImageLabel")
		face.AnchorPoint = Vector2.new(0.5, 0.5)
		face.Position = UDim2.fromScale(0.5, 0.5)
		face.Size = UDim2.new(1, -6, 1, -6)
		face.BackgroundColor3 = Color3.fromRGB(40, 46, 66)
		face.BorderSizePixel = 0
		face.ZIndex = 5
		face.Parent = ring
		CardKit.corner(face, 14)

		-- Sıra rozeti yüzün sol üstünde
		local rankBadge = Instance.new("Frame")
		rankBadge.AnchorPoint = Vector2.new(0.5, 0.5)
		rankBadge.Position = UDim2.fromOffset(8, 8)
		rankBadge.Size = UDim2.fromOffset(18, 18)
		rankBadge.BorderSizePixel = 0
		rankBadge.ZIndex = 7
		rankBadge.Parent = card
		CardKit.corner(rankBadge, 9)
		CardKit.border(rankBadge, CardKit.OUTLINE, 2)
		local rank = CardKit.bold(rankBadge, "", 12, CardKit.WHITE, 8, 1.5)
		rank.Size = UDim2.fromScale(1, 1)

		local name = CardKit.bold(card, "", 16, CardKit.WHITE, 5, 2)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(46, 3)
		name.Size = UDim2.new(1, -130, 0, 20)
		CardKit.fit(name, 16, 9)

		local detail = CardKit.bold(card, "", 11, Color3.fromRGB(220, 230, 250), 5, 1.4)
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.Position = UDim2.fromOffset(46, 22)
		detail.Size = UDim2.new(1, -130, 0, 15)
		CardKit.fit(detail, 11, 7)

		local cash = CardKit.bold(card, "", 17, Color3.fromRGB(124, 255, 91), 5, 2)
		cash.AnchorPoint = Vector2.new(1, 0.5)
		cash.Position = UDim2.new(1, -8, 0.5, 0)
		cash.Size = UDim2.fromOffset(84, 22)
		cash.TextXAlignment = Enum.TextXAlignment.Right
		CardKit.fit(cash, 17, 9)

		table.insert(rows, {
			card = card, rank = rank, rankBadge = rankBadge, ring = ring, face = face,
			name = name, detail = detail, cash = cash, mine = mine, shownColor = nil, shownUser = nil,
		})
	end

	local function update(colorOf: ((Player) -> Color3)?)
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			return number(a, "Cash") > number(b, "Cash")
		end)

		count.Text = string.format("%d / %d", #list, Config.ServerSize)

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
				row.card.Visible = false
				continue
			end

			local isMine = entry == player
			row.card.Visible = true
			row.mine.Enabled = isMine

			row.rank.Text = tostring(rank)
			row.rankBadge.BackgroundColor3 = PODIUM[rank] or Color3.fromRGB(70, 78, 96)

			-- Üs rengi: halka ve kart
			local tone = if colorOf then colorOf(entry) else UiKit.VISOR
			if row.shownColor ~= tone then
				row.shownColor = tone
				row.ring.BackgroundColor3 = tone
				CardKit.tintCard(row.card, tone:Lerp(Color3.new(0, 0, 0), 0.45))
			end

			-- Yüz: kullanıcı değişince yeniden
			if row.shownUser ~= entry.UserId then
				row.shownUser = entry.UserId
				row.face.Image = ""
				local userId = entry.UserId
				faceOf(userId, function(content)
					if row.shownUser == userId then
						row.face.Image = content
					end
				end)
			end

			row.name.Text = entry.DisplayName
			row.name.TextColor3 = if isMine then CardKit.YELLOW else CardKit.WHITE
			row.detail.Text = string.format("+$%s/s  ·  %d stolen",
				Config.FormatCash(number(entry, "Income")), stolenOf(entry))
			row.cash.Text = "$" .. Config.FormatCash(number(entry, "Cash"))
		end

		local shown = math.clamp(#list, 1, MAX_ROWS)
		holder.Size = UDim2.fromOffset(WIDTH, HEADER + 8 + shown * ROW_H)
	end

	return { Update = update }
end

return Leaderboard
