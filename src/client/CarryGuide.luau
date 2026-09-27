--!strict
--[[
	Taşıma rehberi: çalınan karakteri taşırken üssüne doğru ok gösterir.
	Harita boş olduğu için çaldıktan sonra yön bulmak zor; bu onu çözüyor.

	Eskiden okun altında "123 studs" yazıyordu (oyuncu stud'ın ne
	olduğunu bilmiyor, "garip yazı") ve gri Gotham kutusu öbür arayüzden
	kopuktu. Artık mağaza dilinde (CardKit): konturlu ok, renkli kart,
	yaklaşınca yeşile dönüyor ve "ALMOST THERE!" diyor.
]]

local Players = game:GetService("Players")

local CardKit = require(script.Parent.CardKit)

local CarryGuide = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(255, 176, 50)
local NEAR = Color3.fromRGB(70, 210, 90)
local Z = 20

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
	holder.Size = UDim2.new(0, 280, 0, 150)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = screen

	local arrow = CardKit.bold(holder, "▲", 76, ACCENT, Z, 5)
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0.5, 0, 0, 46)
	arrow.Size = UDim2.new(0, 92, 0, 92)

	local card = CardKit.card(holder, ACCENT, UDim2.new(1, 0, 0, 46), Z, UDim2.fromScale(0.5, 0.5), 380)
	card.Name = "Caption"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 98)

	local caption = CardKit.bold(card, "RETURN TO YOUR BASE!", 22, CardKit.WHITE, Z + 3, 2.5)
	caption.Position = UDim2.fromOffset(10, 0)
	caption.Size = UDim2.new(1, -20, 1, 0)
	CardKit.fit(caption, 22, 12)

	local lastArrived: boolean? = nil

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
		local arrived = Vector3.new(flat.X, 0, flat.Z).Magnitude <= ARRIVED_STUDS

		-- Ok hafifçe nabız gibi atıyor: gözden kaçmasın
		arrow.Rotation = bearingTo(base.Position, root.Position)
		arrow.TextSize = 76 + math.sin(os.clock() * 6) * 4

		if arrived ~= lastArrived then
			lastArrived = arrived
			local color = if arrived then NEAR else ACCENT
			arrow.TextColor3 = color
			CardKit.tintCard(card, color)
			caption.Text = if arrived then "ALMOST THERE!" else "RETURN TO YOUR BASE!"
		end
	end

	return { Update = update }
end

return CarryGuide
