--!strict
-- HUD: nakit, saniyelik gelir, üs durumu ve bildirim şeridi.
-- Kod içi yorumlar Türkçe, oyuncunun gördüğü metinler İngilizce.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local GOOD = Color3.fromRGB(120, 255, 150)
local WARN = Color3.fromRGB(255, 190, 90)
local BAD = Color3.fromRGB(255, 90, 90)
local PANEL = Color3.fromRGB(18, 20, 28)

-- ─── Arayüz ─────────────────────────────────────────────────────────────────

local screen = Instance.new("ScreenGui")
screen.Name = "SusStealersHud"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local function newLabel(name: string, position: UDim2, size: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = INK
	label.TextStrokeTransparency = 0.4
	label.Parent = screen
	return label
end

local cashLabel = newLabel("Cash", UDim2.new(0, 24, 0, 20), UDim2.new(0, 360, 0, 44), 34)
cashLabel.TextColor3 = GOOD

local incomeLabel = newLabel("Income", UDim2.new(0, 24, 0, 62), UDim2.new(0, 360, 0, 28), 20)
incomeLabel.TextColor3 = MUTED

-- ─── Üs paneli ──────────────────────────────────────────────────────────────
-- Sağ üstte: kaide doluluğu, kilit durumu ve taşınan karakter.

local panel = Instance.new("Frame")
panel.Name = "PlotPanel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -24, 0, 20)
panel.Size = UDim2.new(0, 260, 0, 104)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Parent = screen

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 10)
panelPadding.PaddingLeft = UDim.new(0, 14)
panelPadding.PaddingRight = UDim.new(0, 14)
panelPadding.Parent = panel

local panelLayout = Instance.new("UIListLayout")
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Padding = UDim.new(0, 4)
panelLayout.Parent = panel

--[[ Panelde "başlık  değer" biçiminde tek satır üretir. ]]
local function newRow(order: number, caption: string): TextLabel
	local row = Instance.new("Frame")
	row.Name = caption
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.45, 0, 1, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = MUTED
	title.Text = caption
	title.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Position = UDim2.new(0.45, 0, 0, 0)
	value.Size = UDim2.new(0.55, 0, 1, 0)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.TextSize = 15
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextColor3 = INK
	value.Text = "—"
	value.Parent = row

	return value
end

local podiumValue = newRow(1, "Podiums")
local lockValue = newRow(2, "Lock")
local carryValue = newRow(3, "Carrying")

-- ─── Bildirimler ────────────────────────────────────────────────────────────

local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.AnchorPoint = Vector2.new(0.5, 1)
toastHolder.Position = UDim2.new(0.5, 0, 1, -40)
toastHolder.Size = UDim2.new(0, 520, 0, 200)
toastHolder.BackgroundTransparency = 1
toastHolder.Parent = screen

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 6)
layout.Parent = toastHolder

local toastOrder = 0

local function showToast(text: string, color: Color3)
	toastOrder += 1

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 500, 0, 40)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.LayoutOrder = toastOrder
	frame.Parent = toastHolder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, 0)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Parent = frame

	local label = Instance.new("TextLabel")
	label.Position = UDim2.new(0, 16, 0, 0)
	label.Size = UDim2.new(1, -28, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = INK
	label.Text = text
	label.Parent = frame

	task.delay(3, function()
		if not frame.Parent then
			return
		end
		local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(stripe, info, { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		frame:Destroy()
	end)
end

Net.Get("Notify").OnClientEvent:Connect(function(text: string, isError: boolean)
	showToast(text, if isError then BAD else GOOD)
end)

Net.Get("StealAlert").OnClientEvent:Connect(function(thiefName: string, unitName: string)
	showToast(string.format("%s stole your %s!", thiefName, unitName), Color3.fromRGB(255, 70, 110))
end)

-- ─── Nakit / gelir ──────────────────────────────────────────────────────────

local function refreshCash()
	local cash = player:GetAttribute("Cash") :: number?
	local income = player:GetAttribute("Income") :: number?

	cashLabel.Text = "$" .. Config.FormatCash(cash or 0)
	incomeLabel.Text = string.format("+$%s/s", Config.FormatCash(income or 0))
end

player:GetAttributeChangedSignal("Cash"):Connect(refreshCash)
player:GetAttributeChangedSignal("Income"):Connect(refreshCash)
refreshCash()

-- ─── Üs durumu ──────────────────────────────────────────────────────────────

--[[
	Sunucu hangi üssün bizim olduğunu bildirmiyor (Net.PlotAssigned tanımlı ama
	kullanılmıyor). O yüzden tabeladaki isimden buluyoruz.
]]
local function findOwnPlot(): Model?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end

	local wanted = string.upper(player.DisplayName)
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") then
			local sign = plot:FindFirstChild("Sign")
			local gui = sign and sign:FindFirstChild("OwnerLabel")
			local label = gui and gui:FindFirstChild("Text")
			if label and label:IsA("TextLabel") and label.Text == wanted then
				return plot
			end
		end
	end
	return nil
end

local function countPodiums(plot: Model): (number, number)
	local folder = plot:FindFirstChild("Podiums")
	if not folder then
		return 0, 0
	end

	local filled, total = 0, 0
	for _, podium in folder:GetChildren() do
		if podium:IsA("Part") then
			total += 1
			local unitId = podium:GetAttribute("UnitId")
			if typeof(unitId) == "string" and unitId ~= "" then
				filled += 1
			end
		end
	end
	return filled, total
end

--[[
	Kilit soğuması sunucuda os.clock() ile tutuluyor; o saat istemcide farklı
	çalıştığı için doğrudan okunamaz. Bunun yerine kilidin açılma anını burada
	kendimiz görüp sayıyoruz. Oyuna soğuma ortasında girersen bilinmez kalır.
]]
local lockedSince: number? = nil

local function describeLock(plot: Model): (string, Color3)
	local locked = plot:GetAttribute("Locked") == true

	if locked then
		if lockedSince == nil then
			lockedSince = os.clock()
		end
		local left = Config.LockDuration - (os.clock() - (lockedSince :: number))
		return string.format("LOCKED · %ds", math.max(0, math.ceil(left))), GOOD
	end

	if lockedSince ~= nil then
		local left = Config.LockCooldown - (os.clock() - (lockedSince :: number))
		if left > 0 then
			return string.format("cooldown · %ds", math.ceil(left)), WARN
		end
		lockedSince = nil
	end

	return "ready", INK
end

local function describeCarry(): (string, Color3)
	local character = player.Character
	local carried = character and character:FindFirstChild("CarriedUnit")
	if not carried then
		return "—", MUTED
	end

	local unitTag = carried:FindFirstChild("UnitId")
	local unitId = if unitTag and unitTag:IsA("StringValue") then unitTag.Value else ""

	local def = Config.GetUnit(unitId)
	if not def then
		return "yes", WARN
	end

	local mutationTag = carried:FindFirstChild("MutationId")
	local mutationId = if mutationTag and mutationTag:IsA("StringValue") then mutationTag.Value else ""
	local mutation = Config.GetMutation(if mutationId == "" then nil else mutationId)

	local income = def.income * (if mutation then mutation.incomeMul else 1)
	return string.format("%s +$%s/s", def.name, Config.FormatCash(income)), WARN
end

local function setRow(value: TextLabel, text: string, color: Color3)
	value.Text = text
	value.TextColor3 = color
end

task.spawn(function()
	while true do
		task.wait(0.2)

		local plot = findOwnPlot()
		if plot then
			local filled, total = countPodiums(plot)
			local ratio = if total > 0 then filled / total else 0
			setRow(
				podiumValue,
				string.format("%d / %d", filled, total),
				if ratio >= 1 then WARN else INK
			)
			setRow(lockValue, describeLock(plot))
		else
			setRow(podiumValue, "no base", MUTED)
			setRow(lockValue, "—", MUTED)
		end

		setRow(carryValue, describeCarry())
	end
end)
