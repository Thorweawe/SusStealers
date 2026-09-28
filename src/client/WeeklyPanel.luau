--!strict
--[[
	Haftalık sıralama penceresi (sunucusu WeeklyService).

	Açılış: sağ üstteki CREW tablosunun 🏆 WEEKLY düğmesi ve lobideki MOST
	HEISTS panosunun "Weekly Top" promptu. İki yerden de çünkü oyuncu
	sıralamayı ya HUD'da (her an) ya da lobide panoların önünde arıyor.

	  Üst:   "WEEKLY HEISTS" + sıfırlanmaya kalan süre (Pazartesi 00:00 UTC)
	  Sol:   ilk 10 — sıra rozeti (altın/gümüş/bronz), yüz, ad, soygun
	  Alt:   SENİN satırın (her zaman görünür): bu haftaki soygunun, sıran
	         ya da ilk 10'a kaç soygun kaldığı
	  Sağ:   ödüller — #1 / #2-3 / #4-10 (nakit, unvan, #1'e Champion alevi)

	Geçen haftanın ödülü girişte verilince ("WeeklyResult" niteliği) pencere
	kendiliğinden açılıp kutlama şeridi gösteriyor.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local UiKit = require(script.Parent.UiKit)

local WeeklyPanel = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(255, 196, 50)
local Z = 50
local PODIUM = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(200, 210, 222), Color3.fromRGB(214, 140, 80) }
local OUTLINE = Color3.fromRGB(14, 16, 28)

export type Panel = {
	Open: () -> (),
	Toggle: () -> (),
	Destroy: () -> (),
}

type Row = { n: string, v: number, u: number }

local function text(parent: Instance, value: string, size: number, color: Color3, z: number, stroke: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.Text = value
	l.ZIndex = z
	l.Parent = parent
	if stroke then
		local s = Instance.new("UIStroke")
		s.Thickness = stroke
		s.Color = OUTLINE
		s.Parent = l
	end
	return l
end

local faces: { [number]: string } = {}
local function face(userId: number, image: ImageLabel)
	if faces[userId] then
		image.Image = faces[userId]
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and typeof(content) == "string" then
			faces[userId] = content
			image.Image = content
		end
	end)
end

local function countdown(seconds: number): string
	local t = math.max(0, math.floor(seconds))
	local d = t // 86400
	local h = (t % 86400) // 3600
	local m = (t % 3600) // 60
	if d > 0 then
		return string.format("%dd %02dh %02dm", d, h, m)
	end
	return string.format("%02dh %02dm %02ds", h, m, t % 60)
end

function WeeklyPanel.Create(screen: ScreenGui): Panel
	local root = UiKit.Window(screen, "WeeklyPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(700, 520)
	root.Visible = false
	root.ZIndex = Z

	local title = text(root, "🏆 WEEKLY HEISTS", 32, ACCENT, Z + 3, 3)
	title.Position = UDim2.fromOffset(20, 10)
	title.Size = UDim2.new(0.6, 0, 0, 40)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local sub = text(root, "Steal the most crewmates this week. Top 10 win rewards!", 14, UiKit.MUTED, Z + 3)
	sub.Font = Enum.Font.GothamBold
	sub.Position = UDim2.fromOffset(22, 48)
	sub.Size = UDim2.new(0.6, 0, 0, 18)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	local timer = text(root, "", 16, Color3.new(1, 1, 1), Z + 3, 2)
	timer.AnchorPoint = Vector2.new(1, 0)
	timer.Position = UDim2.new(1, -60, 0, 18)
	timer.Size = UDim2.fromOffset(220, 22)
	timer.TextXAlignment = Enum.TextXAlignment.Right
	local scope = text(root, "", 11, UiKit.MUTED, Z + 3)
	scope.Font = Enum.Font.GothamBold
	scope.AnchorPoint = Vector2.new(1, 0)
	scope.Position = UDim2.new(1, -60, 0, 42)
	scope.Size = UDim2.fromOffset(220, 16)
	scope.TextXAlignment = Enum.TextXAlignment.Right

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 5

	-- Kutlama şeridi (geçen haftanın ödülü)
	local banner = Instance.new("Frame")
	banner.Position = UDim2.fromOffset(16, 72)
	banner.Size = UDim2.new(1, -32, 0, 34)
	banner.BackgroundColor3 = ACCENT
	banner.Visible = false
	banner.ZIndex = Z + 4
	banner.Parent = root
	UiKit.Corner(banner, 10)
	UiKit.Stroke(banner, OUTLINE, 2, 0)
	local bannerText = text(banner, "", 16, Color3.new(1, 1, 1), Z + 5, 2)
	bannerText.Size = UDim2.fromScale(1, 1)

	-- ─── Sol: ilk 10 ─────────────────────────────────────────────────────
	local listTop = 72
	local list = Instance.new("Frame")
	list.Position = UDim2.fromOffset(16, listTop)
	list.Size = UDim2.new(0, 410, 1, -listTop - 76)
	list.BackgroundTransparency = 1
	list.ZIndex = Z + 1
	list.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	type RowUi = { frame: Frame, rank: TextLabel, badge: Frame, face: ImageLabel, name: TextLabel, value: TextLabel }
	local rowUis: { RowUi } = {}
	for i = 1, Config.Weekly.Rows do
		local f = Instance.new("Frame")
		f.LayoutOrder = i
		f.Size = UDim2.new(1, 0, 0, 34)
		f.BackgroundColor3 = UiKit.ROW
		f.BorderSizePixel = 0
		f.ZIndex = Z + 2
		f.Parent = list
		UiKit.Corner(f, 9)
		local badge = Instance.new("Frame")
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 6, 0.5, 0)
		badge.Size = UDim2.fromOffset(28, 26)
		badge.BackgroundColor3 = PODIUM[i] or UiKit.SHELL_DEEP
		badge.ZIndex = Z + 3
		badge.Parent = f
		UiKit.Corner(badge, 8)
		local rank = text(badge, tostring(i), 15, Color3.new(1, 1, 1), Z + 4, 1.6)
		rank.Size = UDim2.fromScale(1, 1)
		local img = Instance.new("ImageLabel")
		img.AnchorPoint = Vector2.new(0, 0.5)
		img.Position = UDim2.new(0, 40, 0.5, 0)
		img.Size = UDim2.fromOffset(28, 28)
		img.BackgroundColor3 = UiKit.SHELL_DEEP
		img.ZIndex = Z + 3
		img.Parent = f
		UiKit.Corner(img, 14)
		local name = text(f, "", 15, UiKit.INK, Z + 3, 1.4)
		name.Position = UDim2.fromOffset(76, 0)
		name.Size = UDim2.new(1, -170, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local value = text(f, "", 15, ACCENT, Z + 3, 1.4)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -10, 0, 0)
		value.Size = UDim2.fromOffset(90, 34)
		value.TextXAlignment = Enum.TextXAlignment.Right
		table.insert(rowUis, { frame = f, rank = rank, badge = badge, face = img, name = name, value = value })
	end
	local empty = text(list, "No heists yet this week - be the first!", 16, UiKit.MUTED, Z + 3)
	empty.LayoutOrder = 99
	empty.Size = UDim2.new(1, 0, 0, 40)

	-- Senin satırın
	local me = Instance.new("Frame")
	me.AnchorPoint = Vector2.new(0, 1)
	me.Position = UDim2.new(0, 16, 1, -16)
	me.Size = UDim2.fromOffset(410, 50)
	me.BackgroundColor3 = ACCENT:Lerp(UiKit.ROW, 0.7)
	me.ZIndex = Z + 2
	me.Parent = root
	UiKit.Corner(me, 12)
	UiKit.Stroke(me, ACCENT, 2.5, 0)
	local meFace = Instance.new("ImageLabel")
	meFace.AnchorPoint = Vector2.new(0, 0.5)
	meFace.Position = UDim2.new(0, 10, 0.5, 0)
	meFace.Size = UDim2.fromOffset(34, 34)
	meFace.BackgroundColor3 = UiKit.SHELL_DEEP
	meFace.ZIndex = Z + 3
	meFace.Parent = me
	UiKit.Corner(meFace, 17)
	face(player.UserId, meFace)
	local meTitle = text(me, "YOU", 16, Color3.new(1, 1, 1), Z + 3, 1.8)
	meTitle.Position = UDim2.fromOffset(54, 4)
	meTitle.Size = UDim2.new(1, -160, 0, 22)
	meTitle.TextXAlignment = Enum.TextXAlignment.Left
	local meHint = text(me, "", 12, UiKit.INK, Z + 3)
	meHint.Font = Enum.Font.GothamBold
	meHint.Position = UDim2.fromOffset(54, 26)
	meHint.Size = UDim2.new(1, -160, 0, 18)
	meHint.TextXAlignment = Enum.TextXAlignment.Left
	local meValue = text(me, "0", 26, ACCENT, Z + 3, 2)
	meValue.AnchorPoint = Vector2.new(1, 0.5)
	meValue.Position = UDim2.new(1, -12, 0.5, 0)
	meValue.Size = UDim2.fromOffset(100, 30)
	meValue.TextXAlignment = Enum.TextXAlignment.Right

	-- ─── Sağ: ödüller ────────────────────────────────────────────────────
	local rewards = Instance.new("Frame")
	rewards.AnchorPoint = Vector2.new(1, 0)
	rewards.Position = UDim2.new(1, -16, 0, listTop)
	rewards.Size = UDim2.new(0, 240, 1, -listTop - 16)
	rewards.BackgroundColor3 = UiKit.SHELL_DEEP
	rewards.ZIndex = Z + 1
	rewards.Parent = root
	UiKit.Corner(rewards, 12)
	local rTitle = text(rewards, "REWARDS", 20, Color3.new(1, 1, 1), Z + 3, 2)
	rTitle.Position = UDim2.fromOffset(0, 8)
	rTitle.Size = UDim2.new(1, 0, 0, 24)
	local rList = Instance.new("Frame")
	rList.Position = UDim2.fromOffset(10, 40)
	rList.Size = UDim2.new(1, -20, 1, -50)
	rList.BackgroundTransparency = 1
	rList.ZIndex = Z + 2
	rList.Parent = rewards
	local rLayout = Instance.new("UIListLayout")
	rLayout.Padding = UDim.new(0, 8)
	rLayout.Parent = rList
	for i, reward in Config.Weekly.Rewards do
		local card = Instance.new("Frame")
		card.LayoutOrder = i
		card.Size = UDim2.new(1, 0, 0, if reward.flame then 118 else 92)
		card.BackgroundColor3 = (PODIUM[math.min(i, 3)] or ACCENT):Lerp(UiKit.ROW, 0.72)
		card.ZIndex = Z + 3
		card.Parent = rList
		UiKit.Corner(card, 10)
		UiKit.Stroke(card, PODIUM[math.min(i, 3)] or ACCENT, 2, 0.2)
		local head = text(card, reward.label, 20, PODIUM[math.min(i, 3)] or ACCENT, Z + 4, 2)
		head.Position = UDim2.fromOffset(10, 4)
		head.Size = UDim2.new(1, -20, 0, 24)
		head.TextXAlignment = Enum.TextXAlignment.Left
		local titleDef = Config.GetTitle(if reward.best == 3 then "WeeklyChampion" elseif reward.best == 2 then "WeeklyTop3" else "WeeklyTop10")
		local lines = {
			string.format("💰 %s min of your income", Config.FormatCash(reward.seconds // 60)),
			string.format("🏷 Title: %s", if titleDef then titleDef.name else "?"),
		}
		if reward.flame then
			local flame = Config.GetJetFlame(reward.flame)
			table.insert(lines, string.format("🔥 %s jetpack flame", if flame then flame.name else reward.flame))
		end
		local body = text(card, table.concat(lines, "\n"), 13, UiKit.INK, Z + 4)
		body.Font = Enum.Font.GothamBold
		body.Position = UDim2.fromOffset(10, 30)
		body.Size = UDim2.new(1, -20, 1, -34)
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextWrapped = true
		body.LineHeight = 1.15
	end

	-- ─── Veri ────────────────────────────────────────────────────────────
	local function read(): { Row }
		local raw = workspace:GetAttribute("WeeklyTop")
		if typeof(raw) ~= "string" then
			return {}
		end
		local ok, rows = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		return if ok and typeof(rows) == "table" then rows else {}
	end

	local function refresh()
		local rows = read()
		local mine = player:GetAttribute("WeeklyHeists")
		local myValue = if typeof(mine) == "number" then mine else 0
		local myRank: number? = nil
		for i, ui in rowUis do
			local row = rows[i]
			ui.frame.Visible = row ~= nil
			if row then
				local isMe = row.u == player.UserId
				if isMe then
					myRank = i
				end
				ui.name.Text = row.n .. (if isMe then "  (you)" else "")
				ui.value.Text = string.format("%d heists", row.v)
				ui.frame.BackgroundColor3 = if isMe then ACCENT:Lerp(UiKit.ROW, 0.65) else UiKit.ROW
				face(row.u, ui.face)
			end
		end
		empty.Visible = #rows == 0
		meValue.Text = tostring(myValue)
		if myRank then
			meTitle.Text = string.format("YOU  ·  #%d", myRank)
			meHint.Text = if myRank == 1 then "You're #1! Hold the lead until Monday." else "You're in the Top 10 - keep climbing!"
		else
			meTitle.Text = "YOU"
			local tenth = rows[Config.Weekly.Rows]
			meHint.Text = if tenth then string.format("%d more heists to reach the Top 10", math.max(1, tenth.v - myValue + 1))
				else "Steal crewmates in space to climb the ranks"
		end
		scope.Text = if workspace:GetAttribute("WeeklyGlobal") == true then "ALL SERVERS · updates every minute" else "THIS SERVER (global list loading)"
	end

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, workspace:GetAttributeChangedSignal("WeeklyTop"):Connect(function()
		if root.Visible then
			refresh()
		end
	end))
	table.insert(conns, player:GetAttributeChangedSignal("WeeklyHeists"):Connect(function()
		if root.Visible then
			refresh()
		end
	end))
	local lastTick = 0
	table.insert(conns, RunService.Heartbeat:Connect(function()
		if not root.Visible then
			return
		end
		local t = os.clock()
		if t - lastTick < 0.5 then
			return
		end
		lastTick = t
		local ends = workspace:GetAttribute("WeeklyEndsAt")
		timer.Text = if typeof(ends) == "number" then "Resets in " .. countdown(ends - workspace:GetServerTimeNow()) else ""
	end))

	local function open()
		refresh()
		root.Visible = true
	end
	close.Activated:Connect(function()
		root.Visible = false
	end)
	table.insert(conns, ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "WeeklyPrompt" then
			open()
		end
	end))
	-- Geçen haftanın ödülü: pencere açılıp kutluyor
	local function showResult()
		local raw = player:GetAttribute("WeeklyResult")
		if typeof(raw) ~= "string" then
			return
		end
		local rank, what = string.match(raw, "^(%d+)|(.*)$")
		if not rank then
			return
		end
		bannerText.Text = string.format("🎉 Last week you finished #%s!  %s", rank, what or "")
		banner.Visible = true
		list.Position = UDim2.fromOffset(16, 112)
		list.Size = UDim2.new(0, 410, 1, -112 - 76)
		open()
	end
	table.insert(conns, player:GetAttributeChangedSignal("WeeklyResult"):Connect(showResult))
	task.defer(showResult)

	return {
		Open = open,
		Toggle = function()
			if root.Visible then
				root.Visible = false
			else
				open()
			end
		end,
		Destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			root:Destroy()
		end,
	}
end

return WeeklyPanel
