--!strict
--[[
	Sezon Kartı penceresi (sunucusu SeasonService). Sol raydaki PASS düğmesi
	açıyor.

	  Üst:   sezon adı, bitişe kalan süre, kademe + XP çubuğu, PREMIUM düğmesi
	  Orta:  30 kademe yana kayan sütunlar. Her sütunda üstte BEDAVA, altta
	         PREMIUM (altın) ödül kartı; kart hâli: CLAIM (hak edildi),
	         ✓ (alındı), kilit (kademe ya da pass yok)
	  Alt:   XP nereden gelir (soygun, mini oyun, görev, günlük giriş...)

	Ödül toplama "SeasonClaim"(kademe, iz) — hak sunucuda. Durum nitelikleri:
	SeasonXp, SeasonClaimed ("f3,p3,..."), SeasonPass.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local EggStyle = require(script.Parent.EggStyle)
local UiKit = require(script.Parent.UiKit)

local SeasonPanel = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(170, 100, 255)
local GOLD = Color3.fromRGB(255, 200, 60)
local OUTLINE = Color3.fromRGB(14, 16, 28)
local Z = 50
local COLUMN = 112

export type Panel = {
	Open: () -> (),
	Toggle: () -> (),
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
	if stroke then
		local s = Instance.new("UIStroke")
		s.Thickness = stroke
		s.Color = OUTLINE
		s.Parent = l
	end
	return l
end

local function income(): number
	local v = player:GetAttribute("Income")
	return if typeof(v) == "number" then v else 0
end

local function describe(reward: Config.SeasonReward): string
	if reward.kind == "cash" then
		return "$" .. Config.FormatCash(Config.GetRewardCash(reward :: any, income()))
	elseif reward.kind == "potion" then
		return if (reward.count or 1) > 1 then (reward.count :: number) .. " Potions" else "Potion"
	elseif reward.kind == "egg" then
		local egg = Config.GetEgg(reward.egg or "")
		return if egg then egg.name else "Egg"
	elseif reward.kind == "superspin" then
		return if (reward.count or 1) > 1 then (reward.count :: number) .. " Super Spins" else "Super Spin"
	elseif reward.kind == "spins" then
		return if (reward.count or 1) > 1 then (reward.count :: number) .. " Spins" else "Spin"
	elseif reward.kind == "flame" then
		local flame = Config.GetJetFlame(reward.flame)
		return if flame then flame.name .. " Flame" else "Flame"
	end
	return "?"
end

local function drawIcon(slot: Frame, reward: Config.SeasonReward, size: number)
	if reward.kind == "cash" then
		UiKit.Coin(slot, size, Color3.fromRGB(255, 210, 60))
	elseif reward.kind == "potion" then
		UiKit.Vial(slot, size, Color3.fromRGB(150, 236, 160), 0.8, true)
	elseif reward.kind == "egg" then
		EggStyle.Draw(slot, size, reward.egg)
	elseif reward.kind == "superspin" then
		UiKit.Wheel(slot, size, GOLD)
	elseif reward.kind == "spins" then
		UiKit.Wheel(slot, size, Color3.fromRGB(120, 200, 255))
	elseif reward.kind == "flame" then
		local flame = Config.GetJetFlame(reward.flame)
		UiKit.Flame(slot, size, if flame then flame.flame else Color3.fromRGB(255, 140, 60))
	end
end

--[[ Toplanmayı bekleyen ödül sayısı (sol raydaki PASS düğmesinin rozeti). ]]
function SeasonPanel.Claimable(): number
	local xpRaw = player:GetAttribute("SeasonXp")
	local tier = Config.SeasonProgress(if typeof(xpRaw) == "number" then xpRaw else 0)
	local hasPass = player:GetAttribute("SeasonPass") == true
	local claimed: { [string]: boolean } = {}
	local raw = player:GetAttribute("SeasonClaimed")
	if typeof(raw) == "string" then
		for key in string.gmatch(raw, "[^,]+") do
			claimed[key] = true
		end
	end
	local count = 0
	for t = 1, tier do
		if not claimed["f" .. t] then
			count += 1
		end
		if hasPass and not claimed["p" .. t] then
			count += 1
		end
	end
	return count
end

function SeasonPanel.Create(screen: ScreenGui): Panel
	local claimRemote = Net.Get("SeasonClaim")

	local root = UiKit.Window(screen, "SeasonPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(780, 500)
	root.Visible = false
	root.ZIndex = Z

	local title = text(root, "SEASON PASS", 32, Color3.new(1, 1, 1), Z + 3, 3)
	title.Position = UDim2.fromOffset(20, 8)
	title.Size = UDim2.new(0.5, 0, 0, 38)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 170, 240), Color3.fromRGB(150, 130, 255))
	grad.Parent = title
	local season = text(root, Config.Season.name, 15, UiKit.MUTED, Z + 3)
	season.Font = Enum.Font.GothamBold
	season.Position = UDim2.fromOffset(22, 44)
	season.Size = UDim2.new(0.5, 0, 0, 18)
	season.TextXAlignment = Enum.TextXAlignment.Left
	local ends = text(root, "", 14, Color3.new(1, 1, 1), Z + 3, 1.6)
	ends.AnchorPoint = Vector2.new(1, 0)
	ends.Position = UDim2.new(1, -60, 0, 14)
	ends.Size = UDim2.fromOffset(240, 20)
	ends.TextXAlignment = Enum.TextXAlignment.Right

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 5

	-- Kademe ve XP çubuğu
	local tierBadge = Instance.new("Frame")
	tierBadge.Position = UDim2.fromOffset(20, 72)
	tierBadge.Size = UDim2.fromOffset(86, 44)
	tierBadge.BackgroundColor3 = ACCENT
	tierBadge.ZIndex = Z + 3
	tierBadge.Parent = root
	UiKit.Corner(tierBadge, 12)
	UiKit.Stroke(tierBadge, OUTLINE, 2.5, 0)
	local tierText = text(tierBadge, "TIER 0", 18, Color3.new(1, 1, 1), Z + 4, 2)
	tierText.Size = UDim2.fromScale(1, 1)
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(116, 82)
	track.Size = UDim2.new(1, -330, 0, 24)
	track.BackgroundColor3 = UiKit.SHELL_DEEP
	track.ZIndex = Z + 3
	track.Parent = root
	UiKit.Corner(track, 12)
	UiKit.Stroke(track, OUTLINE, 2, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = ACCENT
	fill.ZIndex = Z + 4
	fill.Parent = track
	UiKit.Corner(fill, 12)
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new(Color3.fromRGB(255, 150, 240), Color3.fromRGB(140, 110, 255))
	fillGrad.Parent = fill
	local xpText = text(track, "", 14, Color3.new(1, 1, 1), Z + 5, 1.6)
	xpText.Size = UDim2.fromScale(1, 1)

	local premiumHolder, premiumButton = UiKit.Raised(root, "Premium", GOLD, UDim2.fromOffset(190, 46), 12)
	premiumHolder.AnchorPoint = Vector2.new(1, 0)
	premiumHolder.Position = UDim2.new(1, -20, 0, 70)
	premiumHolder.ZIndex = Z + 3
	local premiumText = text(premiumButton, "", 16, Color3.new(1, 1, 1), Z + 8, 2)
	premiumText.Size = UDim2.fromScale(1, 1)

	-- Sütunlar
	local scroller = Instance.new("ScrollingFrame")
	scroller.Position = UDim2.fromOffset(16, 128)
	scroller.Size = UDim2.new(1, -32, 1, -178)
	scroller.BackgroundColor3 = UiKit.SHELL_DEEP
	scroller.BackgroundTransparency = 0.3
	scroller.BorderSizePixel = 0
	scroller.ScrollingDirection = Enum.ScrollingDirection.X
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = ACCENT
	scroller.CanvasSize = UDim2.fromOffset(Config.Season.tiers * (COLUMN + 8) + 70, 0)
	scroller.ZIndex = Z + 2
	scroller.Parent = root
	UiKit.Corner(scroller, 12)
	-- İz adları (sol kenarda sabit değil, ilk sütunun önünde)
	local freeTag = text(scroller, "FREE", 16, Color3.fromRGB(150, 230, 255), Z + 4, 2)
	freeTag.Position = UDim2.fromOffset(6, 40)
	freeTag.Size = UDim2.fromOffset(56, 110)
	freeTag.Rotation = 0
	local premTag = text(scroller, "PRE-\nMIUM", 15, GOLD, Z + 4, 2)
	premTag.Position = UDim2.fromOffset(6, 162)
	premTag.Size = UDim2.fromOffset(56, 110)

	type Card = { frame: Frame, button: TextButton, label: TextLabel, lock: TextLabel, stroke: UIStroke }
	type Column = { tier: number, head: TextLabel, free: Card, premium: Card }
	local columns: { Column } = {}

	local function makeCard(parent: Frame, y: number, reward: Config.SeasonReward, premium: boolean, tier: number): Card
		local tint = if premium then GOLD else Color3.fromRGB(110, 180, 255)
		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromOffset(4, y)
		frame.Size = UDim2.new(1, -8, 0, 116)
		frame.BackgroundColor3 = tint:Lerp(UiKit.ROW, 0.78)
		frame.ZIndex = Z + 3
		frame.Parent = parent
		UiKit.Corner(frame, 10)
		local stroke = UiKit.Stroke(frame, tint, 1.6, 0.4)
		local slot = Instance.new("Frame")
		slot.AnchorPoint = Vector2.new(0.5, 0)
		slot.Position = UDim2.new(0.5, 0, 0, 6)
		slot.Size = UDim2.fromOffset(46, 46)
		slot.BackgroundTransparency = 1
		slot.ZIndex = Z + 4
		slot.Parent = frame
		drawIcon(slot, reward, 44)
		local name = text(frame, describe(reward), 12, UiKit.INK, Z + 4, 1.2)
		name.Position = UDim2.fromOffset(4, 54)
		name.Size = UDim2.new(1, -8, 0, 26)
		name.TextWrapped = true
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.new(0.5, 0, 1, -6)
		button.Size = UDim2.new(1, -14, 0, 26)
		button.AutoButtonColor = true
		button.Text = ""
		button.ZIndex = Z + 5
		button.Parent = frame
		UiKit.Corner(button, 8)
		UiKit.Stroke(button, OUTLINE, 1.6, 0)
		local label = text(button, "", 13, Color3.new(1, 1, 1), Z + 6, 1.4)
		label.Size = UDim2.fromScale(1, 1)
		local lock = text(frame, "🔒", 22, Color3.new(1, 1, 1), Z + 7)
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, -2, 0, 0)
		lock.Size = UDim2.fromOffset(26, 26)
		button.Activated:Connect(function()
			if button.Active then
				claimRemote:FireServer(tier, if premium then "premium" else "free")
			end
		end)
		return { frame = frame, button = button, label = label, lock = lock, stroke = stroke }
	end

	for tier = 1, Config.Season.tiers do
		local col = Instance.new("Frame")
		col.Position = UDim2.fromOffset(64 + (tier - 1) * (COLUMN + 8), 6)
		col.Size = UDim2.new(0, COLUMN, 1, -18)
		col.BackgroundTransparency = 1
		col.ZIndex = Z + 3
		col.Parent = scroller
		local milestone = tier % 5 == 0
		local head = text(col, tostring(tier), if milestone then 22 else 18, if milestone then GOLD else Color3.new(1, 1, 1), Z + 4, 2)
		head.Size = UDim2.new(1, 0, 0, 26)
		local free, premium = Config.GetSeasonRewards(tier)
		table.insert(columns, {
			tier = tier,
			head = head,
			free = makeCard(col, 30, free, false, tier),
			premium = makeCard(col, 154, premium, true, tier),
		})
	end

	local info = text(root, string.format("Earn XP: heist +%d  ·  capsule game +%d  ·  quest +%d  ·  daily login +%d  ·  spin +%d  ·  room task +%d",
		Config.Season.xp.salvaged, Config.Season.xp.trainings, Config.Season.xp.questsClaimed, Config.Season.xp.dailyClaims,
		Config.Season.xp.spins, Config.Season.xp.tasksDone), 13, UiKit.MUTED, Z + 3)
	info.Font = Enum.Font.GothamBold
	info.AnchorPoint = Vector2.new(0.5, 1)
	info.Position = UDim2.new(0.5, 0, 1, -16)
	info.Size = UDim2.new(1, -40, 0, 20)

	-- ─── Durum ───────────────────────────────────────────────────────────
	local function paint(card: Card, state: string)
		card.lock.Visible = state == "locked" or state == "pass"
		card.button.Active = state == "ready"
		local color = if state == "ready" then UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.3)
			elseif state == "done" then UiKit.DIM
			else Color3.fromRGB(70, 74, 90)
		card.button.BackgroundColor3 = color
		card.label.Text = if state == "ready" then "CLAIM" elseif state == "done" then "✓" elseif state == "pass" then "PREMIUM" else "LOCKED"
		card.stroke.Transparency = if state == "ready" then 0 else 0.4
		card.stroke.Thickness = if state == "ready" then 2.6 else 1.6
		card.frame.BackgroundTransparency = if state == "done" then 0.45 else 0
	end

	local function refresh()
		local xpRaw = player:GetAttribute("SeasonXp")
		local xp = if typeof(xpRaw) == "number" then xpRaw else 0
		local tier, into, need = Config.SeasonProgress(xp)
		local hasPass = player:GetAttribute("SeasonPass") == true
		local claimed: { [string]: boolean } = {}
		local raw = player:GetAttribute("SeasonClaimed")
		if typeof(raw) == "string" then
			for key in string.gmatch(raw, "[^,]+") do
				claimed[key] = true
			end
		end
		tierText.Text = "TIER " .. tier
		if need > 0 then
			fill.Size = UDim2.fromScale(math.clamp(into / need, 0, 1), 1)
			xpText.Text = string.format("%d / %d XP to tier %d", into, need, tier + 1)
		else
			fill.Size = UDim2.fromScale(1, 1)
			xpText.Text = "MAX TIER!"
		end
		if hasPass then
			premiumText.Text = "✓ PREMIUM"
			premiumButton.Active = false
		elseif Config.Season.pass.id > 0 then
			premiumText.Text = string.format("👑 PREMIUM  R$ %d", Config.Season.pass.robux)
			premiumButton.Active = true
		else
			premiumText.Text = "👑 PREMIUM (SOON)"
			premiumButton.Active = false
		end
		for _, col in columns do
			local reached = col.tier <= tier
			col.head.TextTransparency = if reached then 0 else 0.4
			paint(col.free, if claimed["f" .. col.tier] then "done" elseif reached then "ready" else "locked")
			paint(col.premium, if claimed["p" .. col.tier] then "done" elseif not hasPass then "pass" elseif reached then "ready" else "locked")
		end
	end

	local conns: { RBXScriptConnection } = {}
	for _, attr in { "SeasonXp", "SeasonClaimed", "SeasonPass" } do
		table.insert(conns, player:GetAttributeChangedSignal(attr):Connect(function()
			if root.Visible then
				refresh()
			end
		end))
	end
	premiumButton.Activated:Connect(function()
		if premiumButton.Active and Config.Season.pass.id > 0 then
			MarketplaceService:PromptGamePassPurchase(player, Config.Season.pass.id)
		end
	end)
	local last = 0
	table.insert(conns, RunService.Heartbeat:Connect(function()
		if not root.Visible or os.clock() - last < 1 then
			return
		end
		last = os.clock()
		local left = Config.SeasonEndsAt() - workspace:GetServerTimeNow()
		if left <= 0 then
			ends.Text = "Season over - new season soon!"
		else
			local t = math.floor(left)
			ends.Text = string.format("Ends in %dd %02dh %02dm", t // 86400, (t % 86400) // 3600, (t % 3600) // 60)
		end
	end))

	local function open()
		refresh()
		root.Visible = true
		-- Açılışta şu anki kademeye kaydır
		local xpRaw = player:GetAttribute("SeasonXp")
		local tier = Config.SeasonProgress(if typeof(xpRaw) == "number" then xpRaw else 0)
		scroller.CanvasPosition = Vector2.new(math.max(0, (tier - 2) * (COLUMN + 8)), 0)
	end
	close.Activated:Connect(function()
		root.Visible = false
	end)

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

return SeasonPanel
