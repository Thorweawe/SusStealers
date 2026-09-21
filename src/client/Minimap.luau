--!strict
-- Sağ alt köşede üstten görünüm harita.
--
-- Harita 4x2 ızgaraya büyüyünce yön bulmak zorlaştı: çaldığın karakteri
-- taşırken kendi üssünün hangi yönde olduğunu bilmen gerek. Ok zaten yönü
-- gösteriyor ama harita bütün sahayı bir bakışta veriyor — kimin üssü dolu,
-- nerede boşluk var, hangi yoldan gitsen daha kısa.

local Players = game:GetService("Players")

local Minimap = {}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(18, 20, 28)
local MUTED = Color3.fromRGB(150, 163, 184)
local INK = Color3.fromRGB(235, 240, 250)

local SIZE = 176          -- panelin piksel boyutu
local PAD = 12            -- kenar payı

export type Map = {
	Update: (ownerColor: (Player) -> Color3) -> (),
}

type Cell = {
	frame: Frame,
	fill: Frame,
	label: TextLabel,
	lock: Frame,
	index: number,
}

function Minimap.Create(screen: ScreenGui): Map
	local holder = Instance.new("Frame")
	holder.Name = "Minimap"
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -24, 1, -24)
	holder.Size = UDim2.fromOffset(SIZE, SIZE + 22)
	holder.BackgroundColor3 = PANEL
	holder.BackgroundTransparency = 0.2
	holder.BorderSizePixel = 0
	holder.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = holder

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(12, 5)
	title.Size = UDim2.new(1, -24, 0, 14)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 10
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = MUTED
	title.TextTransparency = 0.25
	title.Text = "STATION MAP"
	title.Parent = holder

	-- Haritanın çizildiği alan
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.Position = UDim2.fromOffset(PAD, 22)
	canvas.Size = UDim2.fromOffset(SIZE - PAD * 2, SIZE - PAD * 2)
	canvas.BackgroundTransparency = 1
	canvas.Parent = holder

	local cells: { [number]: Cell } = {}

	--[[
		Oyuncu işareti: nokta konumu, ondan çıkan ince çubuk baktığın yönü
		gösteriyor. Sadece nokta olunca haritada nereye döndüğünü anlamak
		için ekranı kontrol etmen gerekiyordu.
	]]
	local you = Instance.new("Frame")
	you.Name = "You"
	you.AnchorPoint = Vector2.new(0.5, 0.5)
	you.Size = UDim2.fromOffset(14, 14)
	you.BackgroundTransparency = 1
	you.ZIndex = 6
	you.Parent = canvas

	local heading = Instance.new("Frame")
	heading.Name = "Heading"
	heading.AnchorPoint = Vector2.new(0.5, 1)
	heading.Position = UDim2.fromScale(0.5, 0.5)
	heading.Size = UDim2.fromOffset(2, 9)
	heading.BackgroundColor3 = INK
	heading.BorderSizePixel = 0
	heading.ZIndex = 6
	heading.Parent = you

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(7, 7)
	dot.BackgroundColor3 = INK
	dot.BorderSizePixel = 0
	dot.ZIndex = 7
	dot.Parent = you

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	-- Diğer oyuncular: gerektikçe yaratılıyor
	local others: { [Player]: Frame } = {}

	local function otherDot(p: Player): Frame
		local existing = others[p]
		if existing then
			return existing
		end

		local d = Instance.new("Frame")
		d.Name = "P_" .. p.Name
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(6, 6)
		d.BorderSizePixel = 0
		d.ZIndex = 5
		d.Parent = canvas

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = d

		others[p] = d
		return d
	end

	--[[
		Sahanın dünya sınırlarını üslerden hesaplıyoruz. Config'e bağlanmak
		yerine gerçekte ne kurulduysa ona bakıyor; yerleşim değişirse harita
		kendiliğinden uyuyor.
	]]
	local function bounds(plots: Instance): (Vector2?, Vector2?)
		local minX, maxX = math.huge, -math.huge
		local minZ, maxZ = math.huge, -math.huge
		local any = false

		for _, plot in plots:GetChildren() do
			local base = plot:FindFirstChild("Base")
			if base and base:IsA("BasePart") then
				any = true
				local p, s = base.Position, base.Size
				minX = math.min(minX, p.X - s.X / 2)
				maxX = math.max(maxX, p.X + s.X / 2)
				minZ = math.min(minZ, p.Z - s.Z / 2)
				maxZ = math.max(maxZ, p.Z + s.Z / 2)
			end
		end

		if not any then
			return nil, nil
		end
		-- Kenarlarda biraz pay bırak
		local pad = 18
		return Vector2.new(minX - pad, minZ - pad), Vector2.new(maxX + pad, maxZ + pad)
	end

	local function update(ownerColor: (Player) -> Color3)
		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			holder.Visible = false
			return
		end
		holder.Visible = true

		local lo, hi = bounds(plots)
		if not lo or not hi then
			return
		end

		local span = hi - lo
		local w = canvas.AbsoluteSize.X
		local h = canvas.AbsoluteSize.Y
		if w <= 0 or h <= 0 or span.X <= 0 or span.Y <= 0 then
			return
		end

		--[[ Dünya oranını koruyarak sığdır: harita geniş ama alçaksa
		     kareye yayıp bozmak yerine üstte altta boşluk bırak. ]]
		local scale = math.min(w / span.X, h / span.Y)
		local offX = (w - span.X * scale) / 2
		local offY = (h - span.Y * scale) / 2

		local function toCanvas(worldX: number, worldZ: number): (number, number)
			return offX + (worldX - lo.X) * scale, offY + (worldZ - lo.Y) * scale
		end

		for _, plot in plots:GetChildren() do
			local base = plot:FindFirstChild("Base")
			if not (base and base:IsA("BasePart")) then
				continue
			end
			local index = tonumber(string.match(plot.Name, "%d+"))
			if not index then
				continue
			end

			local cell = cells[index]
			if not cell then
				local frame = Instance.new("Frame")
				frame.Name = "Bay" .. index
				frame.AnchorPoint = Vector2.new(0.5, 0.5)
				frame.BackgroundColor3 = MUTED
				frame.BackgroundTransparency = 0.55
				frame.BorderSizePixel = 0
				frame.Parent = canvas

				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0, 2)
				c.Parent = frame

				-- Doluluk göstergesi: kaidesi dolan üs parlar
				local fill = Instance.new("Frame")
				fill.AnchorPoint = Vector2.new(0.5, 1)
				fill.Position = UDim2.fromScale(0.5, 1)
				fill.Size = UDim2.fromScale(1, 0)
				fill.BackgroundColor3 = INK
				fill.BackgroundTransparency = 0.3
				fill.BorderSizePixel = 0
				fill.Parent = frame

				-- Üs numarası: haritadaki kutuyla sahadaki BAY yazısı eşleşsin
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.GothamBold
				label.TextSize = 9
				label.TextColor3 = Color3.new(1, 1, 1)
				label.TextStrokeTransparency = 0.5
				label.ZIndex = 3
				label.Text = tostring(index)
				label.Parent = frame

				--[[ Kilit göstergesi: kilitli üsten çalamazsın, haritada
				     görmek boşuna koşmanı engelliyor. ]]
				local lock = Instance.new("Frame")
				lock.AnchorPoint = Vector2.new(1, 0)
				lock.Position = UDim2.fromScale(1, 0)
				lock.Size = UDim2.fromOffset(5, 5)
				lock.BackgroundColor3 = Color3.fromRGB(255, 176, 40)
				lock.BorderSizePixel = 0
				lock.ZIndex = 4
				lock.Visible = false
				lock.Parent = frame

				cell = { frame = frame, fill = fill, label = label, lock = lock, index = index }
				cells[index] = cell
			end

			local cx, cy = toCanvas(base.Position.X, base.Position.Z)
			cell.frame.Position = UDim2.fromOffset(cx, cy)
			cell.frame.Size = UDim2.fromOffset(
				math.max(6, base.Size.X * scale),
				math.max(6, base.Size.Z * scale)
			)

			-- Sahip rengi
			local sign = plot:FindFirstChild("Sign")
			local gui = sign and sign:FindFirstChild("OwnerLabel")
			local label = gui and gui:FindFirstChild("Text")
			local ownerName = if label and label:IsA("TextLabel") then label.Text else ""

			local owner: Player? = nil
			for _, p in Players:GetPlayers() do
				if string.upper(p.DisplayName) == ownerName then
					owner = p
					break
				end
			end

			if owner then
				cell.frame.BackgroundColor3 = ownerColor(owner)
				cell.frame.BackgroundTransparency = if owner == player then 0.1 else 0.35
			else
				cell.frame.BackgroundColor3 = MUTED
				cell.frame.BackgroundTransparency = 0.7
			end

			-- Kaç kaide dolu
			local podiums = plot:FindFirstChild("Podiums")
			if podiums then
				local total, filled = 0, 0
				for _, podium in podiums:GetChildren() do
					if podium:IsA("BasePart") then
						total += 1
						local unitId = podium:GetAttribute("UnitId")
						if typeof(unitId) == "string" and unitId ~= "" then
							filled += 1
						end
					end
				end
				cell.fill.Size = UDim2.fromScale(1, if total > 0 then filled / total else 0)
			end

			cell.lock.Visible = plot:GetAttribute("Locked") == true
		end

		-- Oyuncu işareti ve bakış yönü
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local px, py = toCanvas(root.Position.X, root.Position.Z)
			you.Visible = true
			you.Position = UDim2.fromOffset(math.clamp(px, 0, w), math.clamp(py, 0, h))

			--[[
				Harita üstten bakıyor: dünya +X sağa, +Z aşağı. Karakterin
				baktığı yön de aynı düzleme indirilip açıya çevriliyor.
			]]
			local look = root.CFrame.LookVector
			you.Rotation = math.deg(math.atan2(look.X, -look.Z))
		else
			you.Visible = false
		end

		-- Diğer oyuncular
		local seen: { [Player]: boolean } = {}
		for _, p in Players:GetPlayers() do
			if p == player then
				continue
			end

			local char = p.Character
			local r = char and char:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") then
				seen[p] = true
				local d = otherDot(p)
				local ox, oy = toCanvas(r.Position.X, r.Position.Z)
				d.Visible = true
				d.BackgroundColor3 = ownerColor(p)
				d.Position = UDim2.fromOffset(math.clamp(ox, 0, w), math.clamp(oy, 0, h))
			end
		end

		-- Ayrılan oyuncuların noktalarını temizle
		for p, d in others do
			if not seen[p] then
				d:Destroy()
				others[p] = nil
			end
		end
	end

	return { Update = update }
end

return Minimap
