--!strict
-- Taşıma rehberi: çalınan karakteri taşırken üssüne doğru ok ve mesafe gösterir.
-- Harita boş olduğu için çaldıktan sonra yön bulmak zor; bu onu çözüyor.

local Players = game:GetService("Players")

local CarryGuide = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(255, 190, 90)
local NEAR = Color3.fromRGB(120, 255, 150)
local PANEL = Color3.fromRGB(18, 20, 28)

-- Bu mesafenin altında "vardın" sayıp rengi yeşile çeviriyoruz.
local ARRIVED_STUDS = 30

export type Guide = {
	Update: (plot: Model?) -> (),
}

--[[
	Kameranın baktığı yön ile hedefin yönü arasındaki işaretli açıyı verir.
	0 = tam karşıda, +90 = sağda, -90 = solda.
]]
local function bearingTo(target: Vector3, from: Vector3): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end

	local delta = target - from
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 0.01 then
		return 0
	end

	local look = camera.CFrame.LookVector
	local camFlat = Vector3.new(look.X, 0, look.Z)
	if camFlat.Magnitude < 0.001 then
		camFlat = Vector3.new(0, 0, -1)
	end

	local dir = flat.Unit
	camFlat = camFlat.Unit

	-- GUI'de pozitif dönüş saat yönünde, o yüzden sonucu ters çeviriyoruz.
	return -math.deg(math.atan2(camFlat:Cross(dir).Y, camFlat:Dot(dir)))
end

function CarryGuide.Create(screen: ScreenGui): Guide
	local holder = Instance.new("Frame")
	holder.Name = "CarryGuide"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0.32, 0)
	holder.Size = UDim2.new(0, 220, 0, 150)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = screen

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0)
	arrow.Position = UDim2.new(0.5, 0, 0, 0)
	arrow.Size = UDim2.new(0, 90, 0, 90)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBold
	arrow.Text = "▲"
	arrow.TextSize = 72
	arrow.TextColor3 = ACCENT
	arrow.TextStrokeTransparency = 0.3
	arrow.Parent = holder

	local distance = Instance.new("TextLabel")
	distance.Name = "Distance"
	distance.AnchorPoint = Vector2.new(0.5, 0)
	distance.Position = UDim2.new(0.5, 0, 0, 88)
	distance.Size = UDim2.new(1, 0, 0, 28)
	distance.BackgroundTransparency = 1
	distance.Font = Enum.Font.GothamBold
	distance.TextSize = 24
	distance.TextColor3 = ACCENT
	distance.TextStrokeTransparency = 0.3
	distance.Text = ""
	distance.Parent = holder

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.new(0.5, 0, 0, 116)
	caption.Size = UDim2.new(1, 0, 0, 22)
	caption.BackgroundColor3 = PANEL
	caption.BackgroundTransparency = 0.25
	caption.Font = Enum.Font.GothamMedium
	caption.TextSize = 14
	caption.TextColor3 = Color3.fromRGB(235, 240, 250)
	caption.Text = "RETURN TO YOUR BASE"
	caption.Parent = holder

	local captionCorner = Instance.new("UICorner")
	captionCorner.CornerRadius = UDim.new(0, 6)
	captionCorner.Parent = caption

	local function update(plot: Model?)
		local character = player.Character
		local carried = character and character:FindFirstChild("CarriedUnit")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not (carried and plot and root and root:IsA("BasePart")) then
			holder.Visible = false
			return
		end

		local base = plot:FindFirstChild("Base")
		if not (base and base:IsA("BasePart")) then
			holder.Visible = false
			return
		end

		holder.Visible = true

		local flat = base.Position - root.Position
		local studs = Vector3.new(flat.X, 0, flat.Z).Magnitude
		local arrived = studs <= ARRIVED_STUDS
		local color = if arrived then NEAR else ACCENT

		arrow.Rotation = bearingTo(base.Position, root.Position)
		arrow.TextColor3 = color
		distance.TextColor3 = color
		distance.Text = string.format("%d studs", math.floor(studs + 0.5))
		caption.Text = if arrived then "ALMOST THERE" else "RETURN TO YOUR BASE"
	end

	return { Update = update }
end

return CarryGuide
