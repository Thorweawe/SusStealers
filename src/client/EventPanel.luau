--!strict
--[[
	Sınırlı etkinlik penceresi (2026-09-30, Config.LimitedEvent; sunucusu
	LimitedEventService).

	  Üst: etkinlik adı, geri sayım (başlamadıysa "STARTS IN", sürüyorsa
	       "ENDS IN" — kıtlık hissi), şeker bakiyesi
	  Orta: şeker nasıl kazanılır + HAUNTED ihtimali (şeffaflık)
	  Alt: dükkân — beş ürün, ucuzdan pahalıya (hedef merdiveni); fiyat,
	       alınan / en fazla, BUY düğmesi. Kozmetiklerde dönen 3B önizleme.

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
	local model = CosmeticModel.BuildHat("PumpkinHead", true)
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
	local shell = FancyKit.shell(root, "🎃 " .. e.name, { e.color, e.color2, Color3.fromRGB(255, 90, 60) }, HEADER, Z, driver, 44)
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
	local candyTitle = CardKit.bold(top, "YOUR CANDY", 18, Color3.fromRGB(255, 225, 180), Z + 4, 2)
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
		"Steal crewmates to earn %s (rarer = more)  ·  HAUNTED crewmates give %dx  ·  +%d every day",
		e.icon, e.hauntedCandyMul, e.dailyBonus), 15, Color3.fromRGB(220, 226, 245), Z + 2, 2)
	how.Position = UDim2.fromOffset(12, 108)
	how.Size = UDim2.new(1, -24, 0, 20)
	CardKit.fit(how, 15, 10)
	local odds = CardKit.bold(body, string.format("During the event %d%% of planet crewmates spawn HAUNTED (x%d income)",
		math.floor(e.hauntedChance * 100 + 0.5), (Config.GetMutation("Haunted") :: any).incomeMul), 14,
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
			local emoji = if item.kind == "unit" then "👻" elseif item.kind == "superspin" then "🎡" else "✨"
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

	local function redraw()
		local now = workspace:GetServerTimeNow()
		local active = Config.IsLimitedEventActive(now)
		if now < e.startsAt then
			countTitle.Text = "EVENT STARTS IN"
			countText.Text = clock(e.startsAt - now)
		elseif active then
			countTitle.Text = "LIMITED! ENDS IN"
			countText.Text = clock(e.endsAt - now)
		else
			countTitle.Text = "EVENT OVER"
			countText.Text = "SEE YOU NEXT TIME"
		end
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
	for _, attr in { "EventCandy", "EventBought" } do
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
