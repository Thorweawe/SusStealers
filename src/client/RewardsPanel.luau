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

	GÖRÜNÜŞ mağaza dilinde (CardKit): pembe başlık şeridi, renkli sekme
	kartları, ışınlı kutular (bugün altın ve nabız atıyor, alınan yeşil ve
	büyük tik, gelecek gri-mavi), tıknaz CLAIM düğmeleri.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CardKit = require(script.Parent.CardKit)
local UiKit = require(script.Parent.UiKit)
local EggStyle = require(script.Parent.EggStyle)

local RewardsPanel = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(236, 80, 160)
local TODAY_TINT = Color3.fromRGB(230, 160, 20)
local DONE_TINT = Color3.fromRGB(50, 150, 60)
local LATER_TINT = Color3.fromRGB(60, 90, 150)
local TAB_TINT = { daily = Color3.fromRGB(230, 150, 30), playtime = Color3.fromRGB(40, 150, 220) }
local W, H, HEADER = 700, 540, 64
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
		UiKit.Coin(slot, 44, tone(Color3.fromRGB(255, 210, 60)))
	elseif reward.kind == "potion" then
		UiKit.Vial(slot, 46, tone(Color3.fromRGB(150, 236, 160)), 0.8, true)
	elseif dim then
		UiKit.Egg(slot, 48, tone(Color3.fromRGB(255, 190, 220)))
	else
		EggStyle.Draw(slot, 48, reward.egg)
	end
end

function RewardsPanel.Create(screen: ScreenGui, onBadge: ((number) -> ())?): Panel
	local root = UiKit.Window(screen, "RewardsPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(W, H)
	root.Visible = false
	root.ZIndex = Z

	local skin = CardKit.skin(root, ACCENT, "Rewards", HEADER, Z)
	local close = skin.close
	skin.title.Position = UDim2.fromOffset(78, 4)
	local crest = CardKit.badge(skin.header, 50, ACCENT, Z + 4)
	crest.AnchorPoint = Vector2.new(0, 0.5)
	crest.Position = UDim2.new(0, 18, 0.5, 0)
	UiKit.Gift(crest:FindFirstChild("Slot") :: Frame, 34, Color3.fromRGB(255, 140, 190))

	-- ─── Sekmeler ───────────────────────────────────────────────────────────

	local tabs = Instance.new("Frame")
	tabs.Position = UDim2.fromOffset(16, 12)
	tabs.Size = UDim2.new(1, -32, 0, 54)
	tabs.BackgroundTransparency = 1
	tabs.ZIndex = Z + 1
	tabs.Parent = skin.body

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 12)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs

	type Tab = { card: Frame, scale: UIScale, dot: TextLabel, tint: Color3 }
	local tabButtons: { [string]: Tab } = {}
	local current = "daily"

	local pages: { [string]: Frame } = {}

	local function makePage(id: string): Frame
		local page = Instance.new("Frame")
		page.Name = id
		page.Position = UDim2.fromOffset(16, 78)
		page.Size = UDim2.new(1, -32, 1, -90)
		page.BackgroundTransparency = 1
		page.ZIndex = Z + 1
		page.Visible = false
		page.Parent = skin.body
		pages[id] = page
		return page
	end

	local redraw: () -> ()

	local function makeTab(id: string, text: string, order: number)
		local tint = TAB_TINT[id]
		local holder = Instance.new("Frame")
		holder.LayoutOrder = order
		holder.Size = UDim2.new(0.5, -6, 1, 0)
		holder.BackgroundTransparency = 1
		holder.ZIndex = Z + 2
		holder.Parent = tabs
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		local card = CardKit.card(holder, tint, UDim2.fromScale(1, 1), Z + 2, UDim2.fromScale(0.5, 0.5), 300)
		local label = CardKit.bold(card, text, 24, CardKit.WHITE, Z + 4, 3)
		label.Size = UDim2.fromScale(1, 1)
		CardKit.fit(label, 24, 12)
		local dot = CardKit.bold(holder, "", 16, CardKit.WHITE, Z + 6, 2)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.new(1, -4, 0, 4)
		dot.Size = UDim2.fromOffset(28, 28)
		dot.BackgroundTransparency = 0
		dot.BackgroundColor3 = Color3.fromRGB(226, 30, 40)
		dot.Visible = false
		CardKit.corner(dot, 14)
		CardKit.border(dot, CardKit.OUTLINE, 2.5)
		local hit = Instance.new("TextButton")
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = Z + 7
		hit.Parent = holder
		tabButtons[id] = { card = card, scale = scale, dot = dot, tint = tint }
		hit.MouseButton1Click:Connect(function()
			current = id
			redraw()
		end)
	end

	makeTab("daily", "DAILY STREAK", 1)
	makeTab("playtime", "PLAYTIME GIFTS", 2)

	-- ─── Kutu kalıbı ────────────────────────────────────────────────────────

	type Tile = { frame: Frame, card: Frame, title: TextLabel, icon: Frame, amount: TextLabel, mark: TextLabel, scale: UIScale }

	local function makeTile(parent: Instance, order: number): Tile
		local frame = Instance.new("Frame")
		frame.LayoutOrder = order
		frame.BackgroundTransparency = 1
		frame.ZIndex = Z + 2
		frame.Parent = parent
		local scale = Instance.new("UIScale")
		scale.Parent = frame
		local card = CardKit.card(frame, LATER_TINT, UDim2.fromScale(1, 1), Z + 2, UDim2.fromScale(0.5, 0.42), 240)

		local title = CardKit.bold(card, "", 20, CardKit.WHITE, Z + 5, 2.5)
		title.Position = UDim2.fromOffset(0, 4)
		title.Size = UDim2.new(1, 0, 0, 24)

		local icon = Instance.new("Frame")
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 30)
		icon.Size = UDim2.fromOffset(52, 52)
		icon.BackgroundTransparency = 1
		icon.ZIndex = Z + 5
		icon.Parent = card

		local amount = CardKit.bold(card, "", 16, CardKit.YELLOW, Z + 5, 2)
		amount.Position = UDim2.new(0, 4, 0, 84)
		amount.Size = UDim2.new(1, -8, 0, 20)
		CardKit.fit(amount, 16, 9)

		-- Toplandı işareti: kutunun üstüne yarı saydam büyük tik
		local mark = CardKit.bold(card, "✓", 52, Color3.fromRGB(140, 255, 120), Z + 8, 4)
		mark.Size = UDim2.fromScale(1, 1)
		mark.BackgroundColor3 = Color3.new(0, 0, 0)
		mark.BackgroundTransparency = 0.5
		mark.Visible = false
		CardKit.corner(mark, 14)

		return { frame = frame, card = card, title = title, icon = icon, amount = amount, mark = mark, scale = scale }
	end

	-- ─── Günlük seri sayfası ────────────────────────────────────────────────

	local dailyPage = makePage("daily")

	local streakLabel = CardKit.bold(dailyPage, "", 22, CardKit.YELLOW, Z + 2, 2.5)
	streakLabel.Size = UDim2.new(1, 0, 0, 26)

	local dayGrid = Instance.new("Frame")
	dayGrid.Position = UDim2.fromOffset(0, 34)
	dayGrid.Size = UDim2.new(1, 0, 0, 250)
	dayGrid.BackgroundTransparency = 1
	dayGrid.ZIndex = Z + 1
	dayGrid.Parent = dailyPage
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(146, 114)
	grid.CellPadding = UDim2.fromOffset(12, 12)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = dayGrid

	local dayTiles: { Tile } = {}
	for i = 1, #Config.DailyRewards do
		local tile = makeTile(dayGrid, i)
		tile.title.Text = "DAY " .. i
		table.insert(dayTiles, tile)
	end

	local claimRemote = Net.Get("RewardClaim")

	local dailyButton = CardKit.button(dailyPage, UDim2.fromOffset(300, 62), Z + 3, 28)
	dailyButton.holder.AnchorPoint = Vector2.new(0.5, 1)
	dailyButton.holder.Position = UDim2.new(0.5, 0, 1, -2)
	local dailyPulse = Instance.new("UIScale")
	dailyPulse.Parent = dailyButton.holder
	dailyButton.button.MouseButton1Click:Connect(function()
		if dailyButton.button.Active then
			claimRemote:FireServer("daily")
		end
	end)

	-- ─── Oynama süresi sayfası ──────────────────────────────────────────────

	local playPage = makePage("playtime")

	local playLabel = CardKit.bold(playPage, "", 22, Color3.fromRGB(120, 210, 255), Z + 2, 2.5)
	playLabel.Size = UDim2.new(1, 0, 0, 26)

	local playGrid = Instance.new("Frame")
	playGrid.Position = UDim2.fromOffset(0, 34)
	playGrid.Size = UDim2.new(1, 0, 1, -34)
	playGrid.BackgroundTransparency = 1
	playGrid.ZIndex = Z + 1
	playGrid.Parent = playPage
	local grid2 = Instance.new("UIGridLayout")
	grid2.CellSize = UDim2.fromOffset(200, 160)
	grid2.CellPadding = UDim2.fromOffset(12, 12)
	grid2.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid2.SortOrder = Enum.SortOrder.LayoutOrder
	grid2.Parent = playGrid

	type PlayTile = { tile: Tile, buy: CardKit.Button }
	local playTiles: { PlayTile } = {}
	for i, reward in Config.PlaytimeRewards do
		local tile = makeTile(playGrid, i)
		tile.title.Text = string.format("%d MIN", reward.minutes or 0)

		local buy = CardKit.button(tile.card, UDim2.new(1, -20, 0, 44), Z + 6, 22)
		buy.holder.AnchorPoint = Vector2.new(0.5, 1)
		buy.holder.Position = UDim2.new(0.5, 0, 1, -8)
		local index = i
		buy.button.MouseButton1Click:Connect(function()
			if buy.button.Active then
				claimRemote:FireServer("playtime", index)
			end
		end)
		table.insert(playTiles, { tile = tile, buy = buy })
	end

	-- ─── Durum ──────────────────────────────────────────────────────────────

	local state = {
		streak = 0, canClaim = false, nextStreak = 1, resetAt = 0,
		seconds = 0, receivedAt = os.clock(), claimed = {} :: { [number]: boolean },
	}

	local function playSeconds(): number
		return state.seconds + (os.clock() - state.receivedAt)
	end


	local function slotOf(streak: number): number
		return ((math.max(1, streak) - 1) % #Config.DailyRewards) + 1
	end

	local clockPulse = 0

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
		clockPulse += 1
		for id, page in pages do
			page.Visible = id == current
		end
		for id, tab in tabButtons do
			local on = id == current
			CardKit.tintCard(tab.card, if on then tab.tint else tab.tint:Lerp(Color3.fromRGB(70, 78, 96), 0.6))
			tab.scale.Scale = if on then 1 else 0.95
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
			CardKit.tintCard(tile.card, if isToday then TODAY_TINT elseif done then DONE_TINT else LATER_TINT)
			-- Bugünün kutusu nabız atıyor (saniyede bir çizim, iki adımda)
			tile.scale.Scale = if isToday then (if clockPulse % 2 == 0 then 1.06 else 1) else 1
		end

		local left = state.resetAt - workspace:GetServerTimeNow()
		if state.canClaim then
			streakLabel.Text = if state.nextStreak > 1
				then string.format("STREAK %d  ·  claim day %d!", state.nextStreak - 1, state.nextStreak)
				else "Claim your daily reward!"
			dailyButton.set("CLAIM DAY " .. state.nextStreak, CardKit.GREEN)
			dailyPulse.Scale = if clockPulse % 2 == 0 then 1.05 else 1
		else
			streakLabel.Text = string.format("STREAK %d  ·  next reward in %s", state.streak, clock(left))
			dailyButton.set("COME BACK IN " .. clock(left), nil)
			dailyPulse.Scale = 1
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
			entry.buy.holder.Visible = not done
			CardKit.tintCard(entry.tile.card, if ready then TODAY_TINT elseif done then DONE_TINT else LATER_TINT)
			if ready then
				entry.buy.set("CLAIM", CardKit.GREEN)
			else
				entry.buy.set(clock(need - played), nil)
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

	close.MouseButton1Click:Connect(function()
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
