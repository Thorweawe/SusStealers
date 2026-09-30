--!strict
--[[
	Sınırlı etkinlik penceresi (2026-09-30, Config.LimitedEvent; sunucusu
	LimitedEventService).

	  Üst: etkinlik adı, geri sayım (başlamadıysa "STARTS IN", sürüyorsa
	       "ENDS IN" — kıtlık hissi), şeker bakiyesi
	  Orta: etkinlik parası nasıl kazanılır + etkinlik mutasyonu ihtimali (şeffaflık)
	  Metinler, renkler, simge Config.LimitedEvent'ten (temadan bağımsız).
	  Liste: YILDIZ YAĞMURU kartı (sıradakine geri sayım, miktarlar ve
	       SUPERNOVA ihtimali — şeffaflık), YILDIZ YOLU (bedava ödül basamakları,
	       ilerleme çubuğu, "N kaldı" — yakın kaçış), 7 GÜNLÜK GİRİŞ (yarın ne
	       geleceği — geri dönüş), sonra dükkân — beş ürün, ucuzdan pahalıya
	       (hedef merdiveni); fiyat, alınan / en fazla, BUY düğmesi. Kozmetiklerde
	       dönen 3B önizleme. En altta sıralama.

	Sol raydaki EVENT düğmesi (init.client) açıyor; düğme etkinlikten
	3 gün önce görünmeye başlıyor (merak), bitince kayboluyor.
	Satın alma "EventShop" remote'u; hak kontrolü sunucuda.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local CosmeticModel = require(Shared.CosmeticModel)

local CardKit = require(script.Parent.CardKit)
local FancyKit = require(script.Parent.FancyKit)
local UiKit = require(script.Parent.UiKit)

local EventPanel = {}

local player = Players.LocalPlayer

local Z = 50
local W, H = 620, 600
local HEADER = 70
local ROW_H = 84
local TEASER_SECONDS = 3 * 86400

export type Panel = {
	Toggle: () -> (),
	Open: () -> (),
	Destroy: () -> (),
}

--[[ Raydaki düğme görünsün mü: etkinlikten 3 gün önce ve etkinlik boyunca. ]]
function EventPanel.ShouldShow(): boolean
	local now = workspace:GetServerTimeNow()
	local e = Config.LimitedEvent
	return now >= e.startsAt - TEASER_SECONDS and now < e.endsAt
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local d = s // 86400
	local h = (s % 86400) // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if d > 0 then
		return string.format("%dd %02d:%02d:%02d", d, h, m, sec)
	end
	return string.format("%02d:%02d:%02d", h, m, sec)
end

local function boughtMap(): { [string]: number }
	local out = {}
	local raw = player:GetAttribute("EventBought")
	if typeof(raw) == "string" then
		for id, n in string.gmatch(raw, "([^:,]+):(%d+)") do
			out[id] = tonumber(n) or 0
		end
	end
	return out
end

--[[ Raydaki düğmenin simgesi: dönen balkabağı (kozmetik modeli). ]]
function EventPanel.DecorateIcon(slot: Frame)
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 190, 180)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.ZIndex = slot.ZIndex + 1
	vp.Parent = slot
	local model = CosmeticModel.BuildHat(Config.LimitedEvent.railHat, true)
	if not model then
		return
	end
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	local dist = math.max(size.X, size.Y, size.Z) * 1.7
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, dist * 0.2, -dist), cf.Position)
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
end

function EventPanel.Create(screen: Instance): Panel
	local e = Config.LimitedEvent
	local root = UiKit.Window(screen, "EventPanel", e.color)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(W, H)
	root.Visible = false
	root.ZIndex = Z
	local driver = FancyKit.driver(root)
	local shell = FancyKit.shell(root, e.emoji .. " " .. e.name, { e.color, e.color2, e.color:Lerp(Color3.new(1, 1, 1), 0.3) }, HEADER, Z, driver, 44)
	local body = shell.body

	-- ─── Üst: geri sayım + şeker ────────────────────────────────────────
	local top = CardKit.hero(body, e.color2, UDim2.new(1, -24, 0, 92), Z + 1, UDim2.fromScale(0.2, 0.5), 420)
	top.Position = UDim2.fromOffset(12, 10)
	local countTitle = CardKit.bold(top, "", 18, Color3.fromRGB(255, 225, 180), Z + 4, 2)
	countTitle.Position = UDim2.fromOffset(16, 10)
	countTitle.Size = UDim2.new(0.55, -16, 0, 22)
	countTitle.TextXAlignment = Enum.TextXAlignment.Left
	local countText = CardKit.bold(top, "", 36, CardKit.YELLOW, Z + 4, 4)
	countText.Position = UDim2.fromOffset(16, 34)
	countText.Size = UDim2.new(0.55, -16, 0, 44)
	countText.TextXAlignment = Enum.TextXAlignment.Left
	CardKit.fit(countText, 36, 18)
	local candyTitle = CardKit.bold(top, "YOUR " .. string.upper(e.currency), 18, Color3.fromRGB(255, 225, 180), Z + 4, 2)
	candyTitle.AnchorPoint = Vector2.new(1, 0)
	candyTitle.Position = UDim2.new(1, -16, 0, 10)
	candyTitle.Size = UDim2.new(0.45, -16, 0, 22)
	candyTitle.TextXAlignment = Enum.TextXAlignment.Right
	local candyText = CardKit.bold(top, "", 40, Color3.new(1, 1, 1), Z + 4, 4)
	candyText.AnchorPoint = Vector2.new(1, 0)
	candyText.Position = UDim2.new(1, -16, 0, 32)
	candyText.Size = UDim2.new(0.45, -16, 0, 48)
	candyText.TextXAlignment = Enum.TextXAlignment.Right
	CardKit.fit(candyText, 40, 18)

	-- ─── Nasıl kazanılır ────────────────────────────────────────────────
	local how = CardKit.bold(body, string.format(
		"Steal crewmates for %s %s (rarer = more)  ·  %s crewmates give %dx  ·  catch falling stars  ·  log in daily",
		e.icon, e.currency, string.upper(e.mutation), e.eventMutationMul), 15, Color3.fromRGB(220, 226, 245), Z + 2, 2)
	how.Position = UDim2.fromOffset(12, 108)
	how.Size = UDim2.new(1, -24, 0, 20)
	CardKit.fit(how, 15, 10)
	local eventMutation = Config.GetMutation(e.mutation)
	local odds = CardKit.bold(body, string.format("During the event %d%% of planet crewmates spawn %s (x%d income)",
		math.floor(e.mutationChance * 100 + 0.5), string.upper(e.mutation), if eventMutation then eventMutation.incomeMul else 1), 14,
		Color3.fromRGB(170, 255, 210), Z + 2, 2)
	odds.Position = UDim2.fromOffset(12, 128)
	odds.Size = UDim2.new(1, -24, 0, 18)
	CardKit.fit(odds, 14, 10)

	-- ─── Dükkân ─────────────────────────────────────────────────────────
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 152)
	list.Size = UDim2.new(1, -24, 1, -162)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = Z + 1
	list.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- ─── Yağmur, yıldız yolu, giriş takvimi (listenin başı) ─────────────
	local function section(order: number, height: number, tint: Color3): Frame
		local holder = Instance.new("Frame")
		holder.LayoutOrder = order
		holder.Size = UDim2.new(1, -10, 0, height)
		holder.BackgroundTransparency = 1
		holder.ZIndex = Z + 2
		holder.Parent = list
		return CardKit.card(holder, tint, UDim2.fromScale(1, 1), Z + 2)
	end
	local function line(parent: Instance, text: string, size: number, color: Color3, y: number): TextLabel
		local l = CardKit.bold(parent, text, size, color, Z + 4, 2)
		l.Position = UDim2.fromOffset(14, y)
		l.Size = UDim2.new(1, -28, 0, size + 4)
		l.TextXAlignment = Enum.TextXAlignment.Left
		CardKit.fit(l, size, 9)
		return l
	end

	-- Yıldız yağmuru: ne zaman, ne kadar (ihtimal açık)
	local sh = e.shower
	local showerCard = section(-3, 68, e.color:Lerp(Color3.new(0, 0, 0), 0.25))
	local showerTitle = line(showerCard, "", 20, Color3.new(1, 1, 1), 8)
	line(showerCard, string.format("Stars give %d-%d %s  ·  1 in %d is a %s (%d %s)  ·  first to touch wins!",
		sh.min, sh.max, e.icon, math.floor(1 / sh.superChance + 0.5), sh.superName, sh.superAmount, e.icon),
		14, Color3.fromRGB(255, 235, 170), 38)
	local showerDef: Config.EventDef? = nil
	for _, def in Config.Events do
		if def.id == "EventShower" then
			showerDef = def
		end
	end

	-- Yıldız yolu: bedava ödül basamakları
	local milestones = e.milestones
	local pathCard = section(-2, 124, e.color2)
	line(pathCard, e.text.path .. "  ·  FREE REWARDS", 20, CardKit.YELLOW, 8)
	local pathNext = line(pathCard, "", 15, Color3.new(1, 1, 1), 34)
	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 26, 0, 68)
	track.Size = UDim2.new(1, -52, 0, 12)
	track.BackgroundColor3 = Color3.fromRGB(20, 22, 40)
	track.BorderSizePixel = 0
	track.ZIndex = Z + 4
	track.Parent = pathCard
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = e.color
	fill.BorderSizePixel = 0
	fill.ZIndex = Z + 5
	fill.Parent = track
	trackCorner:Clone().Parent = fill
	local dots: { Frame } = {}
	for i, step in milestones do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(i / #milestones, 0.5)
		dot.Size = UDim2.fromOffset(24, 24)
		dot.BackgroundColor3 = CardKit.GREY
		dot.BorderSizePixel = 0
		dot.ZIndex = Z + 6
		dot.Parent = track
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = dot
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(10, 12, 24)
		stroke.Parent = dot
		local mark = CardKit.bold(dot, tostring(i), 13, Color3.new(1, 1, 1), Z + 7, 1.5)
		mark.Size = UDim2.fromScale(1, 1)
		local at = CardKit.bold(track, tostring(step.at), 12, Color3.fromRGB(220, 226, 245), Z + 6, 1.5)
		at.AnchorPoint = Vector2.new(0.5, 0)
		at.Position = UDim2.new(i / #milestones, 0, 1, 10)
		at.Size = UDim2.fromOffset(60, 14)
		table.insert(dots, dot)
	end

	-- Giriş takvimi: 7 gün, her gün artıyor
	local ladder = e.dailyLadder
	local dayCard = section(-1, 112, e.color:Lerp(e.color2, 0.5):Lerp(Color3.new(0, 0, 0), 0.2))
	local dayTitle = line(dayCard, "", 20, Color3.new(1, 1, 1), 8)
	local dayBoxes: { { box: Frame, top: TextLabel, amount: TextLabel } } = {}
	local boxRow = Instance.new("Frame")
	boxRow.Position = UDim2.fromOffset(12, 36)
	boxRow.Size = UDim2.new(1, -24, 0, 46)
	boxRow.BackgroundTransparency = 1
	boxRow.ZIndex = Z + 4
	boxRow.Parent = dayCard
	for i = 1, #ladder do
		local box = Instance.new("Frame")
		box.Position = UDim2.new((i - 1) / #ladder, 3, 0, 0)
		box.Size = UDim2.new(1 / #ladder, -6, 1, 0)
		box.BackgroundColor3 = Color3.fromRGB(24, 26, 46)
		box.BorderSizePixel = 0
		box.ZIndex = Z + 4
		box.Parent = boxRow
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = box
		local top = CardKit.bold(box, "DAY " .. i, 12, Color3.fromRGB(200, 208, 235), Z + 5, 1.5)
		top.Position = UDim2.fromOffset(0, 3)
		top.Size = UDim2.new(1, 0, 0, 16)
		CardKit.fit(top, 12, 8)
		local amount = CardKit.bold(box, string.format("+%d", ladder[i]), 17, Color3.new(1, 1, 1), Z + 5, 2)
		amount.Position = UDim2.fromOffset(0, 20)
		amount.Size = UDim2.new(1, 0, 0, 22)
		CardKit.fit(amount, 17, 9)
		table.insert(dayBoxes, { box = box, top = top, amount = amount })
	end
	local daySub = line(dayCard, "", 14, Color3.fromRGB(255, 235, 170), 88)

	local function numberAttr(name: string): number
		local v = player:GetAttribute(name)
		return if typeof(v) == "number" then v else 0
	end

	local function redrawExtras(now: number, active: boolean)
		-- Yağmur
		if not active then
			showerTitle.Text = string.format("%s %s: every %d min during the event", e.emoji, sh.name, sh.every // 60)
		elseif workspace:GetAttribute("EventId") == "EventShower" then
			showerTitle.Text = string.format("%s %s IS ON! Fly into space and catch stars!", e.emoji, sh.name)
		elseif showerDef then
			showerTitle.Text = string.format("%s %s every %d min  ·  next in %s", e.emoji, sh.name, sh.every // 60,
				clock(Config.GetNextEventStart(showerDef, now) - now))
		end

		-- Yıldız yolu
		local earned = numberAttr("EventEarned")
		local claimed = numberAttr("EventMs")
		local reached = 0
		for _, step in milestones do
			if earned >= step.at then
				reached += 1
			end
		end
		local seg = 0
		local nextStep = milestones[reached + 1]
		if nextStep then
			local prevAt = if reached > 0 then milestones[reached].at else 0
			seg = math.clamp((earned - prevAt) / math.max(1, nextStep.at - prevAt), 0, 1)
		end
		fill.Size = UDim2.fromScale(math.clamp((reached + seg) / #milestones, 0, 1), 1)
		for i, dot in dots do
			dot.BackgroundColor3 = if i <= claimed then CardKit.YELLOW elseif i <= reached then e.color else CardKit.GREY
		end
		local pending = milestones[claimed + 1]
		if not pending then
			pathNext.Text = "PATH COMPLETE! You got every reward"
		elseif earned >= pending.at then
			pathNext.Text = string.format("Your %s is waiting: free a podium to get it!", pending.label)
		else
			pathNext.Text = string.format("Next: %s at %d %s  ·  only %d to go!", pending.label, pending.at, e.icon, pending.at - earned)
		end

		-- Giriş takvimi
		local days = numberAttr("EventDays")
		local doneToday = player:GetAttribute("EventDayDone") == true
		dayTitle.Text = string.format("📅 DAILY %s  ·  DAY %d / %d", string.upper(e.currency), math.min(days, #ladder), #ladder)
		local nextDay = days + 1
		for i, b in dayBoxes do
			if i <= days then
				b.box.BackgroundColor3 = CardKit.GREEN:Lerp(Color3.new(0, 0, 0), 0.2)
				b.top.Text = "✓ DAY " .. i
			elseif i == nextDay then
				b.box.BackgroundColor3 = e.color:Lerp(Color3.new(0, 0, 0), 0.1)
				b.top.Text = if doneToday then "TOMORROW" else "TODAY"
			else
				b.box.BackgroundColor3 = Color3.fromRGB(24, 26, 46)
				b.top.Text = "DAY " .. i
			end
		end
		if not active then
			daySub.Text = string.format("Log in every day of the event: up to +%d %s on day %d!", ladder[#ladder], e.icon, #ladder)
		elseif doneToday and (Config.DayIndex(now) + 1) * 86400 < e.endsAt then
			-- Yarın (UTC gün başı) etkinlik hâlâ sürüyorsa
			daySub.Text = string.format("Come back tomorrow for +%d %s - don't miss it!", Config.EventDailyAmount(nextDay), e.icon)
		else
			daySub.Text = "Log in every day - the rewards keep growing!"
		end
	end

	local shopRemote = Net.Get("EventShop")
	type Row = { item: any, buy: CardKit.Button, count: TextLabel }
	local rows: { Row } = {}
	local spinners: { Model } = {}

	for i, item in e.shop do
		local holder = Instance.new("Frame")
		holder.LayoutOrder = i
		holder.Size = UDim2.new(1, -10, 0, ROW_H)
		holder.BackgroundTransparency = 1
		holder.ZIndex = Z + 2
		holder.Parent = list
		local card = CardKit.card(holder, if item.kind == "cosmetic" then e.color2 else e.color, UDim2.fromScale(1, 1), Z + 2)

		-- Simge: kozmetikte dönen model, diğerlerinde emoji
		local iconSlot = Instance.new("Frame")
		iconSlot.Position = UDim2.fromOffset(10, 8)
		iconSlot.Size = UDim2.fromOffset(68, 68)
		iconSlot.BackgroundTransparency = 1
		iconSlot.ZIndex = Z + 4
		iconSlot.Parent = card
		local def = if item.cosmetic then Config.GetCosmetic(item.cosmetic) else nil
		if def and def.kind == "hat" then
			local vp = Instance.new("ViewportFrame")
			vp.Size = UDim2.fromScale(1, 1)
			vp.BackgroundTransparency = 1
			vp.Ambient = Color3.fromRGB(190, 185, 190)
			vp.LightColor = Color3.new(1, 1, 1)
			vp.ZIndex = Z + 4
			vp.Parent = iconSlot
			local model = CosmeticModel.BuildHat(def.id, true)
			if model then
				model.Parent = vp
				local cf, size = model:GetBoundingBox()
				local cam = Instance.new("Camera")
				local dist = math.max(size.X, size.Y, size.Z) * 1.8
				cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, dist * 0.3, -dist), cf.Position)
				cam.FieldOfView = 40
				cam.Parent = vp
				vp.CurrentCamera = cam
				table.insert(spinners, model)
			end
		else
			local emoji = if item.kind == "unit" then e.emoji elseif item.kind == "superspin" then "🎡" else e.icon
			local icon = CardKit.bold(iconSlot, emoji, 44, Color3.new(1, 1, 1), Z + 5, 0)
			icon.Size = UDim2.fromScale(1, 1)
		end

		local name = CardKit.bold(card, item.name, 22, Color3.new(1, 1, 1), Z + 4, 3)
		name.Position = UDim2.fromOffset(88, 12)
		name.Size = UDim2.new(1, -250, 0, 26)
		name.TextXAlignment = Enum.TextXAlignment.Left
		CardKit.fit(name, 22, 12)
		local desc = CardKit.bold(card, item.desc, 14, Color3.fromRGB(220, 226, 245), Z + 4, 1.5)
		desc.Position = UDim2.fromOffset(88, 40)
		desc.Size = UDim2.new(1, -250, 0, 18)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		CardKit.fit(desc, 14, 9)
		local count = CardKit.bold(card, "", 13, Color3.fromRGB(190, 200, 225), Z + 4, 1.5)
		count.Position = UDim2.fromOffset(88, 60)
		count.Size = UDim2.new(1, -250, 0, 16)
		count.TextXAlignment = Enum.TextXAlignment.Left

		local buy = CardKit.button(card, UDim2.fromOffset(140, 56), Z + 4, 20, CardKit.GREEN)
		buy.holder.AnchorPoint = Vector2.new(1, 0.5)
		buy.holder.Position = UDim2.new(1, -10, 0.5, 2)
		buy.button.Activated:Connect(function()
			if buy.button.Active then
				shopRemote:FireServer(item.id)
			end
		end)
		table.insert(rows, { item = item, buy = buy, count = count })
	end

	-- ─── Sıralama (listenin sonunda): ilk 10 etkinlik bitince sınırlı taç ──
	local board = Instance.new("Frame")
	board.LayoutOrder = 100
	board.Size = UDim2.new(1, -10, 0, 118 + e.leaderboard.rows * 22)
	board.BackgroundTransparency = 1
	board.ZIndex = Z + 2
	board.Parent = list
	local boardCard = CardKit.hero(board, e.color2, UDim2.fromScale(1, 1), Z + 2, UDim2.fromScale(0.85, 0.2), 360)
	local rewardDef = Config.GetCosmetic(e.leaderboard.reward)
	local boardTitle = CardKit.bold(boardCard, "🏆 " .. e.text.hunters, 24, CardKit.YELLOW, Z + 4, 3)
	boardTitle.Position = UDim2.fromOffset(14, 8)
	boardTitle.Size = UDim2.new(1, -28, 0, 28)
	boardTitle.TextXAlignment = Enum.TextXAlignment.Left
	local boardSub = CardKit.bold(boardCard, string.format("Top %d when the event ends win the LIMITED %s (all servers)",
		e.leaderboard.rewardTop, if rewardDef then rewardDef.name else "reward"), 14, Color3.new(1, 1, 1), Z + 4, 2)
	boardSub.Position = UDim2.fromOffset(14, 38)
	boardSub.Size = UDim2.new(1, -28, 0, 18)
	boardSub.TextXAlignment = Enum.TextXAlignment.Left
	CardKit.fit(boardSub, 14, 9)
	local mine = CardKit.bold(boardCard, "", 15, Color3.fromRGB(170, 255, 210), Z + 4, 2)
	mine.Position = UDim2.fromOffset(14, 58)
	mine.Size = UDim2.new(1, -28, 0, 20)
	mine.TextXAlignment = Enum.TextXAlignment.Left
	local boardRows: { TextLabel } = {}
	for r = 1, e.leaderboard.rows do
		local l = CardKit.bold(boardCard, "", 16, Color3.new(1, 1, 1), Z + 4, 2)
		l.Position = UDim2.fromOffset(14, 82 + (r - 1) * 22)
		l.Size = UDim2.new(1, -28, 0, 22)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.RichText = true
		table.insert(boardRows, l)
	end

	local function redrawBoard()
		local rows = {}
		local raw = workspace:GetAttribute("EventTop")
		if typeof(raw) == "string" then
			local ok, decoded = pcall(function()
				return game:GetService("HttpService"):JSONDecode(raw)
			end)
			if ok and typeof(decoded) == "table" then
				rows = decoded
			end
		end
		local myRank: number? = nil
		for i, label in boardRows do
			local row = rows[i]
			if typeof(row) == "table" then
				local isMe = row.u == player.UserId
				if isMe then
					myRank = i
				end
				local medal = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else tostring(i) .. "."
				label.Text = string.format('%s %s<font color="#FFE13C">  %s %s</font>', medal,
					if isMe then "<b>" .. tostring(row.n) .. " (you)</b>" else tostring(row.n), tostring(row.v), e.icon)
			else
				label.Text = if i == 1 then "No hunters yet. Be the first!" else ""
			end
		end
		local earned = player:GetAttribute("EventEarned")
		earned = if typeof(earned) == "number" then earned else 0
		mine.Text = string.format("You earned %d %s this event%s", earned, e.icon,
			if myRank then string.format("  ·  you are #%d!", myRank) else "")
	end
	workspace:GetAttributeChangedSignal("EventTop"):Connect(function()
		if root.Visible then
			redrawBoard()
		end
	end)

	local function redraw()
		redrawBoard()
		local now = workspace:GetServerTimeNow()
		local active = Config.IsLimitedEventActive(now)
		if now < e.startsAt then
			countTitle.Text = "EVENT STARTS IN"
			countText.Text = clock(e.startsAt - now)
		elseif Config.IsEventFinalDay(now) then
			countTitle.Text = string.format("FINAL DAY! %dX %s · ENDS IN", e.finalDayMul, e.icon)
			countText.Text = clock(e.endsAt - now)
		elseif active then
			countTitle.Text = "LIMITED! ENDS IN"
			countText.Text = clock(e.endsAt - now)
		else
			countTitle.Text = "EVENT OVER"
			countText.Text = "SEE YOU NEXT TIME"
		end
		redrawExtras(now, active)
		local candy = player:GetAttribute("EventCandy")
		candy = if typeof(candy) == "number" then candy else 0
		candyText.Text = string.format("%s %d", e.icon, candy)
		local bought = boughtMap()
		for _, row in rows do
			local have = bought[row.item.id] or 0
			row.count.Text = string.format("%d / %d owned", have, row.item.limit)
			if have >= row.item.limit then
				row.buy.set("OWNED", nil)
			elseif not active then
				row.buy.set(string.format("%s %d", e.icon, row.item.price), nil)
			else
				row.buy.set(string.format("%s %d", e.icon, row.item.price),
					if candy >= row.item.price then CardKit.GREEN else CardKit.GREEN:Lerp(CardKit.GREY, 0.55))
			end
		end
	end

	local elapsed = 0
	local tick = RunService.Heartbeat:Connect(function(dt)
		if not root.Visible then
			return
		end
		for _, model in spinners do
			if model.Parent then
				local cf, _ = model:GetBoundingBox()
				model:PivotTo(CFrame.new(cf.Position) * CFrame.Angles(0, dt * 0.9, 0) * CFrame.new(-cf.Position) * model:GetPivot())
			end
		end
		elapsed += dt
		if elapsed >= 1 then
			elapsed = 0
			redraw()
		end
	end)
	for _, attr in { "EventCandy", "EventBought", "EventEarned", "EventMs", "EventDays", "EventDayDone" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if root.Visible then
				redraw()
			end
		end)
	end

	shell.close.Activated:Connect(function()
		root.Visible = false
	end)

	local function open()
		root.Visible = true
		redraw()
	end
	return {
		Toggle = function()
			if root.Visible then
				root.Visible = false
			else
				open()
			end
		end,
		Open = open,
		Destroy = function()
			tick:Disconnect()
			root:Destroy()
		end,
	}
end

return EventPanel
