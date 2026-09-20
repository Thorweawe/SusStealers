--!strict
-- HUD: nakit, saniyelik gelir ve bildirim şeridi.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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
	label.TextColor3 = Color3.fromRGB(240, 245, 255)
	label.TextStrokeTransparency = 0.4
	label.Parent = screen
	return label
end

local cashLabel = newLabel("Cash", UDim2.new(0, 24, 0, 20), UDim2.new(0, 360, 0, 44), 34)
cashLabel.TextColor3 = Color3.fromRGB(120, 255, 150)

local incomeLabel = newLabel("Income", UDim2.new(0, 24, 0, 62), UDim2.new(0, 360, 0, 28), 20)
incomeLabel.TextColor3 = Color3.fromRGB(180, 195, 215)

local carryLabel = newLabel("Carry", UDim2.new(0, 24, 0, 94), UDim2.new(0, 420, 0, 28), 20)
carryLabel.TextColor3 = Color3.fromRGB(255, 190, 90)
carryLabel.Text = ""

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
	frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
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
	label.TextColor3 = Color3.fromRGB(235, 240, 250)
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
	showToast(text, if isError then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(120, 255, 150))
end)

Net.Get("StealAlert").OnClientEvent:Connect(function(thiefName: string, unitName: string)
	showToast(string.format("%s senden %s çaldı!", thiefName, unitName), Color3.fromRGB(255, 70, 110))
end)

-- ─── Güncelleme ─────────────────────────────────────────────────────────────

local function refresh()
	local cash = player:GetAttribute("Cash") :: number?
	local income = player:GetAttribute("Income") :: number?

	cashLabel.Text = "$" .. Config.FormatCash(cash or 0)
	incomeLabel.Text = string.format("+$%s/sn", Config.FormatCash(income or 0))
end

player:GetAttributeChangedSignal("Cash"):Connect(refresh)
player:GetAttributeChangedSignal("Income"):Connect(refresh)
refresh()

-- Taşıma göstergesi: karakterin altında CarriedUnit varsa göster
task.spawn(function()
	while true do
		task.wait(0.25)
		local character = player.Character
		local carried = character and character:FindFirstChild("CarriedUnit")
		carryLabel.Text = if carried then "TAŞIYORSUN — üssüne dön" else ""
	end
end)
