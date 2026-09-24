--!strict
--[[
	Ödül penceresi: üst şeritteki hediye kutusu açıyor. İki sekme:

	  DAILY STREAK   — yedi günlük seri. Bugünün kutusu parlıyor, geçmiş
	                   günler işaretli, gelecekler sönük. Bir gün kaçınca
	                   seri başa dönüyor (sunucu hesaplıyor).
	  PLAYTIME GIFTS — oyunda kalınan süreye göre altı kutu (5..60 dk).
	                   Her kutunun üstünde geri sayım; hazır olan parlıyor.

	Durum sunucudan "Rewards" remote'uyla geliyor; oynama süresi arada
	istemcide ilerletiliyor (saniyede bir paket gitmesin). Toplama isteği
	RewardClaim ile gidiyor, hak kontrolü sunucuda (RewardService).

	`onBadge` toplanabilir ödül sayısını üst şeritteki hediye düğmesine
	bildiriyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)
local EggStyle = require(script.Parent.EggStyle)

local RewardsPanel = {}

local player = Players.LocalPlayer

local ACCENT = UiKit.CREW.PINK
local GOLD = Color3.fromRGB(255, 200, 70)
local Z = 45

export type Panel = {
	Toggle: () -> (),
	Destroy: () -> (),
}

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

local function income(): number
	local value = player:GetAttribute("Income")
	return if typeof(value) == "number" then value else 0
end

--[[ Ödülün kısa metni ve ikonu. Nakit tutarı oyuncunun gelirine göre. ]]
local function describe(reward: Config.RewardDef): string
	if reward.kind == "cash" then
		return "$" .. Config.FormatCash(Config.GetRewardCash(reward, income()))
	elseif reward.kind == "potion" then
		return if (reward.count or 1) > 1 then (reward.count :: number) .. " Potions" else "Potion"
	elseif reward.kind == "egg" and reward.egg then
		local egg = Config.GetEgg(reward.egg)
		return if egg then egg.name else "Egg"
	end
	return "?"
end

local function drawIcon(slot: Frame, reward: Config.RewardDef, dim: boolean)
	UiKit.ClearSlot(slot)
	local tone = function(c: Color3): Color3
		return if dim then c:Lerp(UiKit.DIM, 0.7) else c
	end
	if reward.kind == "cash" then
		UiKit.Coin(slot, 30, tone(UiKit.CREW.LIME))
	elseif reward.kind == "potion" then
		UiKit.Vial(slot, 32, tone(Color3.fromRGB(150, 226, 160)), 0.8, true)
	elseif dim then
		UiKit.Egg(slot, 34, tone(Color3.fromRGB(255, 190, 220)))
	else
		EggStyle.Draw(slot, 34, reward.egg)
	end
end

function RewardsPanel.Create(screen: ScreenGui, onBadge: ((number) -> ())?): Panel
	local root = UiKit.Window(screen, "RewardsPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(560, 440)
	root.Visible = false
	root.ZIndex = Z

	-- ─── Başlık ─────────────────────────────────────────────────────────────

	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 54)
	band.BackgroundColor3 = ACCENT:Lerp(Color3.new(0, 0, 0), 0.55)
	band.BorderSizePixel = 0
	band.ZIndex = Z + 1
	band.Parent = root
	UiKit.Corner(band, 14)
	local bandFoot = Instance.new("Frame")
	bandFoot.Position = UDim2.new(0, 0, 1, -14)
	bandFoot.Size = UDim2.new(1, 0, 0, 14)
	bandFoot.BackgroundColor3 = band.BackgroundColor3
	bandFoot.BorderSizePixel = 0
	bandFoot.ZIndex = Z + 1
	bandFoot.Parent = band

	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(0.5, -96, 0.5, 0)
	badge.Size = UDim2.fromOffset(34, 34)
	badge.BackgroundTransparency = 1
	badge.ZIndex = Z + 2
	badge.Parent = band
	UiKit.Gift(badge, 32, Color3.fromRGB(255, 120, 170))

	local heading = Instance.new("TextLabel")
	heading.AnchorPoint = Vector2.new(0.5, 0.5)
	heading.Position = UDim2.fromScale(0.5, 0.5)
	heading.Size = UDim2.fromOffset(220, 30)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBlack
	heading.TextSize = 24
	heading.TextColor3 = Color3.new(1, 1, 1)
	heading.TextStrokeTransparency = 0.5
	heading.Text = "• REWARDS •"
	heading.ZIndex = Z + 2
	heading.Parent = band

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 3

	-- ─── Sekmeler ───────────────────────────────────────────────────────────

	local tabs = Instance.new("Frame")
	tabs.Position = UDim2.fromOffset(16, 64)
	tabs.Size = UDim2.new(1, -32, 0, 40)
	tabs.BackgroundTransparency = 1
	tabs.ZIndex = Z + 1
	tabs.Parent = root

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 10)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs

	type Tab = { button: TextButton, stroke: UIStroke, dot: TextLabel }
	local tabButtons: { [string]: Tab } = {}
	local current = "daily"

	local pages: { [string]: Frame } = {}

	local function makePage(id: string): Frame
		local page = Instance.new("Frame")
		page.Name = id
		page.Position = UDim2.fromOffset(16, 114)
		page.Size = UDim2.new(1, -32, 1, -128)
		page.BackgroundTransparency = 1
		page.ZIndex = Z + 1
		page.Visible = false
		page.Parent = root
		pages[id] = page
		return page
	end

	local redraw: () -> ()

	local function makeTab(id: string, text: string, order: number)
		local button = Instance.new("TextButton")
		button.LayoutOrder = order
		button.Size = UDim2.new(0.5, -5, 1, 0)
		button.BackgroundColor3 = UiKit.ROW
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 14
		button.TextColor3 = UiKit.INK
		button.Text = text
		button.ZIndex = Z + 2
		button.Parent = tabs
		UiKit.Corner(button, 10)
		local stroke = UiKit.Stroke(button, ACCENT, 1.6, 1)
		local dot = UiKit.Badge(button)
		tabButtons[id] = { button = button, stroke = stroke, dot = dot }
		button.MouseButton1Click:Connect(function()
			current = id
			redraw()
		end)
	end

	makeTab("daily", "DAILY STREAK", 1)
	makeTab("playtime", "PLAYTIME GIFTS", 2)

	-- ─── Günlük seri sayfası ────────────────────────────────────────────────

	local dailyPage = makePage("daily")

	local streakLabel = Instance.new("TextLabel")
	streakLabel.Size = UDim2.new(1, 0, 0, 22)
	streakLabel.BackgroundTransparency = 1
	streakLabel.Font = Enum.Font.GothamBlack
	streakLabel.TextSize = 16
	streakLabel.TextColor3 = GOLD
	streakLabel.ZIndex = Z + 2
	streakLabel.Parent = dailyPage

	local dayGrid = Instance.new("Frame")
	dayGrid.Position = UDim2.fromOffset(0, 30)
	dayGrid.Size = UDim2.new(1, 0, 0, 212)
	dayGrid.BackgroundTransparency = 1
	dayGrid.ZIndex = Z + 1
	dayGrid.Parent = dailyPage
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(118, 100)
	grid.CellPadding = UDim2.fromOffset(8, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = dayGrid

	type Tile = { frame: Frame, stroke: UIStroke, title: TextLabel, icon: Frame, amount: TextLabel, mark: TextLabel }

	local function makeTile(parent: Instance, order: number): Tile
		local frame = Instance.new("Frame")
		frame.LayoutOrder = order
		frame.BackgroundColor3 = UiKit.ROW
		frame.BorderSizePixel = 0
		frame.ZIndex = Z + 2
		frame.Parent = parent
		UiKit.Corner(frame, 12)
		local stroke = UiKit.Stroke(frame, ACCENT, 1.4, 0.7)

		local title = Instance.new("TextLabel")
		title.Position = UDim2.fromOffset(0, 6)
		title.Size = UDim2.new(1, 0, 0, 16)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextSize = 12
		title.TextColor3 = UiKit.INK
		title.ZIndex = Z + 3
		title.Parent = frame

		local icon = Instance.new("Frame")
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 26)
		icon.Size = UDim2.fromOffset(38, 38)
		icon.BackgroundTransparency = 1
		icon.ZIndex = Z + 3
		icon.Parent = frame

		local amount = Instance.new("TextLabel")
		amount.Position = UDim2.new(0, 4, 1, -30)
		amount.Size = UDim2.new(1, -8, 0, 24)
		amount.BackgroundTransparency = 1
		amount.Font = Enum.Font.GothamBold
		amount.TextSize = 12
		amount.TextWrapped = true
		amount.TextColor3 = UiKit.MUTED
		amount.ZIndex = Z + 3
		amount.Parent = frame

		-- Toplandı işareti: kutunun üstüne yarı saydam tik
		local mark = Instance.new("TextLabel")
		mark.Size = UDim2.fromScale(1, 1)
		mark.BackgroundColor3 = Color3.new(0, 0, 0)
		mark.BackgroundTransparency = 0.45
		mark.Font = Enum.Font.GothamBlack
		mark.TextSize = 34
		mark.TextColor3 = UiKit.GOOD
		mark.Text = "✓"
		mark.Visible = false
		mark.ZIndex = Z + 5
		mark.Parent = frame
		UiKit.Corner(mark, 12)

		return { frame = frame, stroke = stroke, title = title, icon = icon, amount = amount, mark = mark }
	end

	local dayTiles: { Tile } = {}
	for i = 1, #Config.DailyRewards do
		local tile = makeTile(dayGrid, i)
		tile.title.Text = "DAY " .. i
		table.insert(dayTiles, tile)
	end

	local claimRemote = Net.Get("RewardClaim")

	local dailyHolder, dailyClaim = UiKit.Raised(dailyPage, "ClaimDaily", UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35), UDim2.fromOffset(220, 46), 12)
	dailyHolder.AnchorPoint = Vector2.new(0.5, 1)
	dailyHolder.Position = UDim2.new(0.5, 0, 1, 0)
	dailyHolder.ZIndex = Z + 2
	local dailyClaimText = Instance.new("TextLabel")
	dailyClaimText.Size = UDim2.fromScale(1, 1)
	dailyClaimText.BackgroundTransparency = 1
	dailyClaimText.Font = Enum.Font.GothamBlack
	dailyClaimText.TextSize = 16
	dailyClaimText.TextColor3 = Color3.new(1, 1, 1)
	dailyClaimText.TextStrokeTransparency = 0.5
	dailyClaimText.ZIndex = Z + 6
	dailyClaimText.Parent = dailyClaim
	dailyClaim.MouseButton1Click:Connect(function()
		if dailyClaim.Active then
			claimRemote:FireServer("daily")
		end
	end)

	-- ─── Oynama süresi sayfası ──────────────────────────────────────────────

	local playPage = makePage("playtime")

	local playLabel = Instance.new("TextLabel")
	playLabel.Size = UDim2.new(1, 0, 0, 22)
	playLabel.BackgroundTransparency = 1
	playLabel.Font = Enum.Font.GothamBlack
	playLabel.TextSize = 16
	playLabel.TextColor3 = UiKit.VISOR
	playLabel.ZIndex = Z + 2
	playLabel.Parent = playPage

	local playGrid = Instance.new("Frame")
	playGrid.Position = UDim2.fromOffset(0, 30)
	playGrid.Size = UDim2.new(1, 0, 1, -30)
	playGrid.BackgroundTransparency = 1
	playGrid.ZIndex = Z + 1
	playGrid.Parent = playPage
	local grid2 = Instance.new("UIGridLayout")
	grid2.CellSize = UDim2.fromOffset(160, 124)
	grid2.CellPadding = UDim2.fromOffset(10, 10)
	grid2.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid2.SortOrder = Enum.SortOrder.LayoutOrder
	grid2.Parent = playGrid

	type PlayTile = { tile: Tile, holder: Frame, button: TextButton, buttonText: TextLabel }
	local playTiles: { PlayTile } = {}
	for i, reward in Config.PlaytimeRewards do
		local tile = makeTile(playGrid, i)
		tile.title.Text = string.format("%d MIN", reward.minutes or 0)
		tile.amount.Position = UDim2.new(0, 4, 0, 66)
		tile.amount.Size = UDim2.new(1, -8, 0, 16)

		local holder, button = UiKit.Raised(tile.frame, "Claim", UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35), UDim2.new(1, -16, 0, 30), 8)
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 1, -6)
		holder.ZIndex = Z + 3
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextSize = 13
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.5
		text.ZIndex = Z + 7
		text.Parent = button
		local index = i
		button.MouseButton1Click:Connect(function()
			if button.Active then
				claimRemote:FireServer("playtime", index)
			end
		end)
		table.insert(playTiles, { tile = tile, holder = holder, button = button, buttonText = text })
	end

	-- ─── Durum ──────────────────────────────────────────────────────────────

	local state = {
		streak = 0, canClaim = false, nextStreak = 1, resetAt = 0,
		seconds = 0, receivedAt = os.clock(), claimed = {} :: { [number]: boolean },
	}

	local function playSeconds(): number
		return state.seconds + (os.clock() - state.receivedAt)
	end

	local function setButton(button: TextButton, text: TextLabel, label: string, tint: Color3?)
		text.Text = label
		button.Active = tint ~= nil
		local base = tint or UiKit.DIM
		button.BackgroundColor3 = base
		local grad = button:FindFirstChildOfClass("UIGradient")
		if grad then
			grad.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), 0.22), base:Lerp(Color3.new(0, 0, 0), 0.18))
		end
	end

	local function slotOf(streak: number): number
		return ((math.max(1, streak) - 1) % #Config.DailyRewards) + 1
	end

	local claimTint = UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35)

	local function readyCount(): number
		local n = if state.canClaim then 1 else 0
		local played = playSeconds()
		for i, reward in Config.PlaytimeRewards do
			if not state.claimed[i] and played >= (reward.minutes or 0) * 60 then
				n += 1
			end
		end
		return n
	end

	redraw = function()
		for id, page in pages do
			page.Visible = id == current
		end
		for id, tab in tabButtons do
			local on = id == current
			tab.button.BackgroundColor3 = if on then ACCENT:Lerp(UiKit.ROW, 0.6) else UiKit.ROW
			tab.stroke.Transparency = if on then 0.1 else 1
		end

		-- Günlük: bu döngüde bugün hangi kutu
		local today = if state.canClaim then slotOf(state.nextStreak) else slotOf(state.streak)
		local claimedUpTo = if state.canClaim then today - 1 else (if state.streak > 0 then today else 0)
		for i, tile in dayTiles do
			local reward = Config.DailyRewards[i]
			local isToday = state.canClaim and i == today
			local done = i <= claimedUpTo
			drawIcon(tile.icon, reward, not (isToday or done))
			tile.amount.Text = describe(reward)
			tile.mark.Visible = done
			tile.stroke.Color = if isToday then GOLD else ACCENT
			tile.stroke.Transparency = if isToday then 0 else 0.7
			tile.stroke.Thickness = if isToday then 2.6 else 1.4
			tile.frame.BackgroundColor3 = if isToday then GOLD:Lerp(UiKit.ROW, 0.75) else UiKit.ROW
		end

		local left = state.resetAt - workspace:GetServerTimeNow()
		if state.canClaim then
			streakLabel.Text = if state.nextStreak > 1
				then string.format("STREAK %d  ·  claim day %d!", state.nextStreak - 1, state.nextStreak)
				else "Claim your daily reward!"
			setButton(dailyClaim, dailyClaimText, "CLAIM DAY " .. state.nextStreak, claimTint)
		else
			streakLabel.Text = string.format("STREAK %d  ·  next reward in %s", state.streak, clock(left))
			setButton(dailyClaim, dailyClaimText, "COME BACK IN " .. clock(left), nil)
		end

		-- Oynama süresi
		local played = playSeconds()
		playLabel.Text = string.format("Played today: %s", clock(played))
		for i, entry in playTiles do
			local reward = Config.PlaytimeRewards[i]
			local need = (reward.minutes or 0) * 60
			local done = state.claimed[i] == true
			local ready = not done and played >= need
			drawIcon(entry.tile.icon, reward, not (ready or done))
			entry.tile.amount.Text = describe(reward)
			entry.tile.mark.Visible = done
			entry.holder.Visible = not done
			entry.tile.stroke.Color = if ready then GOLD else ACCENT
			entry.tile.stroke.Transparency = if ready then 0 else 0.7
			entry.tile.stroke.Thickness = if ready then 2.6 else 1.4
			if ready then
				setButton(entry.button, entry.buttonText, "CLAIM", claimTint)
			else
				setButton(entry.button, entry.buttonText, clock(need - played), nil)
			end
		end

		local ready = readyCount()
		tabButtons.daily.dot.Visible = state.canClaim
		tabButtons.daily.dot.Text = "1"
		local playReady = ready - (if state.canClaim then 1 else 0)
		tabButtons.playtime.dot.Visible = playReady > 0
		tabButtons.playtime.dot.Text = tostring(playReady)
	end

	local connection = Net.Get("Rewards").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		local daily = payload.daily
		if typeof(daily) == "table" then
			state.streak = tonumber(daily.streak) or 0
			state.canClaim = daily.canClaim == true
			state.nextStreak = tonumber(daily.nextStreak) or 1
			state.resetAt = tonumber(daily.resetAt) or 0
		end
		local play = payload.playtime
		if typeof(play) == "table" then
			state.seconds = tonumber(play.seconds) or 0
			state.receivedAt = os.clock()
			state.claimed = {}
			if typeof(play.claimed) == "table" then
				for _, i in play.claimed do
					if typeof(i) == "number" then
						state.claimed[i] = true
					end
				end
			end
		end
		redraw()
	end)

	-- Saniyede bir: geri sayımlar ve üst şeritteki rozet
	local elapsed = 0
	local lastBadge = -1
	local tick = RunService.Heartbeat:Connect(function(delta)
		elapsed += delta
		if elapsed < 1 then
			return
		end
		elapsed = 0
		if root.Visible then
			redraw()
		end
		local ready = readyCount()
		if ready ~= lastBadge then
			lastBadge = ready
			if onBadge then
				onBadge(ready)
			end
		end
	end)

	close.Activated:Connect(function()
		root.Visible = false
	end)

	return {
		Toggle = function()
			root.Visible = not root.Visible
			if root.Visible then
				-- Toplanacak bir şey varsa önce onun sekmesi
				if state.canClaim then
					current = "daily"
				elseif readyCount() > 0 then
					current = "playtime"
				end
				redraw()
			end
		end,
		Destroy = function()
			connection:Disconnect()
			tick:Disconnect()
			root:Destroy()
		end,
	}
end

return RewardsPanel
