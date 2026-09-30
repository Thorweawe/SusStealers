--!strict
--[[
	Sezon Kartı penceresi (sunucusu SeasonService). Sol raydaki PASS düğmesi
	açıyor.

	  Üst:   sezon adı, bitişe kalan süre, kademe + XP çubuğu, PREMIUM düğmesi
	  Orta:  30 kademe yana kayan sütunlar. Her sütunda üstte BEDAVA, altta
	         PREMIUM (altın) ödül kartı; kart hâli: CLAIM (hak edildi),
	         ✓ (alındı), kilit (kademe ya da pass yok)
	  Alt:   XP nereden gelir (soygun, mini oyun, görev, günlük giriş...)

	2026-09-28: mağazanın dilinde (FancyKit kabuğu, renkli kartlar, 3B
	ödül ikonları, tıknaz düğmeler).

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
local FancyKit = require(script.Parent.FancyKit)
local UiArt = require(script.Parent.UiArt)
local UiKit = require(script.Parent.UiKit)

local SeasonPanel = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(170, 100, 255)
local GOLD = Color3.fromRGB(255, 200, 60)
local OUTLINE = Color3.fromRGB(22, 20, 34)
local GREEN = Color3.fromRGB(70, 200, 70)
local Z = 50
local COLUMN = 118

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

-- Sunucunun ödül tabanı (EconomyService.GetRewardIncome): anlık ya da en yüksek gelir
local function income(): number
	local v = player:GetAttribute("Income")
	local peak = player:GetAttribute("RewardIncome")
	return math.max(if typeof(v) == "number" then v else 0, if typeof(peak) == "number" then peak else 0)
end

-- "best" yumurta: sunucuyla aynı seçim (Config.ResolveRewardEgg)
local function resolveEgg(eggId: string?): string
	local rb = player:GetAttribute("Rebirths")
	return Config.ResolveRewardEgg(eggId or "", if typeof(rb) == "number" then rb else 0, income())
end

local function describe(reward: Config.SeasonReward): string
	if reward.kind == "cash" then
		return "$" .. Config.FormatCash(Config.GetRewardCash(reward :: any, income()))
	elseif reward.kind == "potion" then
		return if (reward.count or 1) > 1 then (reward.count :: number) .. " Potions" else "Potion"
	elseif reward.kind == "egg" then
		local egg = Config.GetEgg(resolveEgg(reward.egg))
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

-- Ödülün 3B ikonu (UiArt); yoksa çizim
local ART: { [string]: string } = {
	cash = "Cash100K",
	potion = "Potion_Income2x",
	spins = "ExtraSpin",
	superspin = "Jackpot",
}

local function drawIcon(slot: Frame, reward: Config.SeasonReward, size: number)
	local art = UiArt.Image("Icon", ART[reward.kind] or "")
	if art ~= "" then
		local img = Instance.new("ImageLabel")
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromOffset(size * 1.3, size * 1.3)
		img.BackgroundTransparency = 1
		img.Image = art
		img.ZIndex = slot.ZIndex + 1
		img.Parent = slot
		return
	end
	if reward.kind == "cash" then
		UiKit.Coin(slot, size, Color3.fromRGB(255, 210, 60))
	elseif reward.kind == "potion" then
		UiKit.Vial(slot, size, Color3.fromRGB(150, 236, 160), 0.8, true)
	elseif reward.kind == "egg" then
		EggStyle.Draw(slot, size, resolveEgg(reward.egg))
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

	local W, H, HEADER = 820, 560, 66
	local root = UiKit.Window(screen, "SeasonPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(W, H)
	root.Visible = false
	root.ZIndex = Z
	local driver = FancyKit.driver(root)
	local shell = FancyKit.shell(root, "SEASON PASS", {
		Color3.fromRGB(190, 80, 255), Color3.fromRGB(255, 90, 190), Color3.fromRGB(80, 140, 255),
	}, HEADER, Z, driver, 46)
	local close = shell.close

	local ends = text(root, "", 16, Color3.new(1, 1, 1), Z + 6, 2)
	ends.AnchorPoint = Vector2.new(1, 0.5)
	ends.Position = UDim2.new(1, -74, 0, HEADER / 2)
	ends.Size = UDim2.fromOffset(240, 22)
	ends.TextXAlignment = Enum.TextXAlignment.Right
	local season = text(root, Config.Season.name, 15, Color3.fromRGB(230, 220, 255), Z + 3, 1.8)
	season.Position = UDim2.fromOffset(22, HEADER + 8)
	season.Size = UDim2.new(0.5, 0, 0, 20)
	season.TextXAlignment = Enum.TextXAlignment.Left

	-- Kademe rozeti, XP çubuğu, PREMIUM düğmesi
	local tierBadge = Instance.new("Frame")
	tierBadge.Position = UDim2.fromOffset(20, HEADER + 32)
	tierBadge.Size = UDim2.fromOffset(104, 50)
	tierBadge.BackgroundColor3 = Color3.new(1, 1, 1)
	tierBadge.ZIndex = Z + 3
	tierBadge.Parent = root
	FancyKit.corner(tierBadge, 12)
	FancyKit.border(tierBadge, OUTLINE, 3)
	FancyKit.gradient(tierBadge, { Color3.fromRGB(200, 120, 255), Color3.fromRGB(120, 60, 220) }, 90)
	FancyKit.gleam(tierBadge, driver, 4.5, 0.5, 0.4)
	local tierText = text(tierBadge, "TIER 0", 22, Color3.new(1, 1, 1), Z + 5, 2.5)
	tierText.Size = UDim2.fromScale(1, 1)

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(136, HEADER + 42)
	track.Size = UDim2.new(1, -370, 0, 30)
	track.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
	track.ZIndex = Z + 3
	track.Parent = root
	FancyKit.corner(track, 15)
	FancyKit.border(track, OUTLINE, 3)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.ZIndex = Z + 4
	fill.Parent = track
	FancyKit.corner(fill, 15)
	FancyKit.gradient(fill, { Color3.fromRGB(255, 150, 240), Color3.fromRGB(160, 110, 255), Color3.fromRGB(90, 170, 255) }, 0)
	FancyKit.gleam(fill, driver, 3, 0, 0.5)
	local xpText = text(track, "", 16, Color3.new(1, 1, 1), Z + 6, 2)
	xpText.Size = UDim2.fromScale(1, 1)

	local premium = FancyKit.button(root, UDim2.fromOffset(210, 56), GOLD, 20, Z + 3, driver, 0.3)
	premium.holder.AnchorPoint = Vector2.new(1, 0)
	premium.holder.Position = UDim2.new(1, -20, 0, HEADER + 28)
	local premiumButton = premium.button

	-- Sütunlar
	local scroller = Instance.new("ScrollingFrame")
	scroller.Position = UDim2.fromOffset(16, HEADER + 96)
	scroller.Size = UDim2.new(1, -32, 1, -(HEADER + 136))
	scroller.BackgroundColor3 = Color3.fromRGB(12, 14, 26)
	scroller.BackgroundTransparency = 0.35
	scroller.BorderSizePixel = 0
	scroller.ScrollingDirection = Enum.ScrollingDirection.X
	scroller.ScrollBarThickness = 8
	scroller.ScrollBarImageColor3 = Color3.fromRGB(200, 140, 255)
	scroller.CanvasSize = UDim2.fromOffset(Config.Season.tiers * (COLUMN + 10) + 80, 0)
	scroller.ZIndex = Z + 2
	scroller.Parent = root
	FancyKit.corner(scroller, 14)
	FancyKit.border(scroller, OUTLINE, 3)
	-- İz adları (ilk sütunun önünde)
	local freeTag = text(scroller, "FREE", 18, Color3.fromRGB(150, 230, 255), Z + 4, 2.5)
	freeTag.Position = UDim2.fromOffset(8, 40)
	freeTag.Size = UDim2.fromOffset(60, 130)
	local premTag = text(scroller, "PRE-\nMIUM", 17, GOLD, Z + 4, 2.5)
	premTag.Position = UDim2.fromOffset(8, 180)
	premTag.Size = UDim2.fromOffset(60, 130)

	type Card = { frame: Frame, claim: FancyKit.Button, lock: Frame, done: TextLabel }
	type Column = { tier: number, head: Frame, free: Card, premium: Card }
	local columns: { Column } = {}

	local function makeCard(parent: Frame, y: number, reward: Config.SeasonReward, isPremium: boolean, tier: number): Card
		local tint = if isPremium then GOLD else Color3.fromRGB(80, 160, 255)
		local frame = FancyKit.card(parent, tint, UDim2.new(1, -6, 0, 134), Z + 3, nil, UDim2.new(0.5, 0, 0, 36))
		frame.Position = UDim2.fromOffset(3, y)
		local slot = Instance.new("Frame")
		slot.AnchorPoint = Vector2.new(0.5, 0)
		slot.Position = UDim2.new(0.5, 0, 0, 8)
		slot.Size = UDim2.fromOffset(52, 52)
		slot.BackgroundTransparency = 1
		slot.ZIndex = Z + 5
		slot.Parent = frame
		drawIcon(slot, reward, 50)
		local name = text(frame, describe(reward), 15, Color3.new(1, 1, 1), Z + 6, 2)
		name.Position = UDim2.fromOffset(4, 64)
		name.Size = UDim2.new(1, -8, 0, 26)
		name.TextWrapped = true
		local claim = FancyKit.button(frame, UDim2.new(1, -14, 0, 36), GREEN, 16, Z + 6, nil)
		claim.holder.AnchorPoint = Vector2.new(0.5, 1)
		claim.holder.Position = UDim2.new(0.5, 0, 1, -6)
		-- Kilit: kartı karartan perde + asma kilit
		local lock = Instance.new("Frame")
		lock.Size = UDim2.fromScale(1, 1)
		lock.BackgroundColor3 = Color3.fromRGB(8, 10, 20)
		lock.BackgroundTransparency = 0.45
		lock.ZIndex = Z + 9
		lock.Parent = frame
		FancyKit.corner(lock, 14)
		local lockIcon = text(lock, "🔒", 28, Color3.new(1, 1, 1), Z + 10)
		lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		lockIcon.Position = UDim2.fromScale(0.5, 0.4)
		lockIcon.Size = UDim2.fromOffset(40, 40)
		local done = text(frame, "✓", 44, Color3.fromRGB(120, 255, 120), Z + 10, 3)
		done.AnchorPoint = Vector2.new(0.5, 0.5)
		done.Position = UDim2.fromScale(0.5, 0.42)
		done.Size = UDim2.fromOffset(60, 60)
		claim.button.Activated:Connect(function()
			if claim.button.Active then
				claimRemote:FireServer(tier, if isPremium then "premium" else "free")
			end
		end)
		return { frame = frame, claim = claim, lock = lock, done = done }
	end

	for tier = 1, Config.Season.tiers do
		local col = Instance.new("Frame")
		col.Position = UDim2.fromOffset(72 + (tier - 1) * (COLUMN + 10), 6)
		col.Size = UDim2.new(0, COLUMN, 1, -18)
		col.BackgroundTransparency = 1
		col.ZIndex = Z + 3
		col.Parent = scroller
		local milestone = tier % 5 == 0
		local head = Instance.new("Frame")
		head.AnchorPoint = Vector2.new(0.5, 0)
		head.Position = UDim2.fromScale(0.5, 0)
		head.Size = UDim2.fromOffset(if milestone then 52 else 40, 26)
		head.BackgroundColor3 = Color3.new(1, 1, 1)
		head.ZIndex = Z + 4
		head.Parent = col
		FancyKit.corner(head, 13)
		FancyKit.border(head, OUTLINE, 2.5)
		FancyKit.gradient(head, if milestone then { Color3.fromRGB(255, 230, 120), Color3.fromRGB(230, 150, 20) } else { Color3.fromRGB(120, 130, 170), Color3.fromRGB(60, 66, 96) }, 90)
		local headText = text(head, tostring(tier), 18, Color3.new(1, 1, 1), Z + 5, 2)
		headText.Size = UDim2.fromScale(1, 1)
		local free, prem = Config.GetSeasonRewards(tier)
		table.insert(columns, {
			tier = tier,
			head = head,
			free = makeCard(col, 32, free, false, tier),
			premium = makeCard(col, 174, prem, true, tier),
		})
	end

	local info = text(root, string.format("Earn XP: heist +%d  ·  capsule game +%d  ·  quest +%d  ·  daily login +%d  ·  spin +%d  ·  room task +%d",
		Config.Season.xp.salvaged, Config.Season.xp.trainings, Config.Season.xp.questsClaimed, Config.Season.xp.dailyClaims,
		Config.Season.xp.spins, Config.Season.xp.tasksDone), 15, Color3.fromRGB(210, 216, 240), Z + 3, 1.8)
	info.AnchorPoint = Vector2.new(0.5, 1)
	info.Position = UDim2.new(0.5, 0, 1, -12)
	info.Size = UDim2.new(1, -40, 0, 20)

	-- ─── Durum ───────────────────────────────────────────────────────────
	local function paint(card: Card, state: string)
		card.lock.Visible = state == "locked" or state == "pass"
		card.done.Visible = state == "done"
		card.claim.set(if state == "ready" then "CLAIM" elseif state == "done" then "CLAIMED" elseif state == "pass" then "PREMIUM" else "LOCKED",
			if state == "ready" then GREEN else nil)
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
			premium.set("PREMIUM ✓", nil)
		elseif Config.Season.pass.id > 0 then
			premium.set("PREMIUM " .. Config.Season.pass.robux, GOLD, true)
		else
			premium.set("PREMIUM SOON", GOLD:Lerp(Color3.fromRGB(110, 110, 120), 0.5))
		end
		for _, col in columns do
			local reached = col.tier <= tier
			col.head.BackgroundTransparency = if reached then 0 else 0.35
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
		scroller.CanvasPosition = Vector2.new(math.max(0, (tier - 2) * (COLUMN + 10)), 0)
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
			driver.destroy()
			root:Destroy()
		end,
	}
end

return SeasonPanel
