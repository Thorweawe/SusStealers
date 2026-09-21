--!strict
-- Lobi işlevleri: ışınlanma arayüzü ve sıralama panoları.
--
-- Ped yerine arayüz: üstüne basınca ışınlanan bir ped, yanından geçerken
-- kazara tetikleniyor ve sinir bozucu oluyor. Kürsüye yaklaşınca açılan
-- panelde ne olduğunu okuyup karar veriyorsun.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Lobby = {}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(18, 20, 28)
local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local NEON = Color3.fromRGB(80, 220, 255)
local WARN = Color3.fromRGB(255, 190, 90)

--[[
	Kürsüye kaç stud yaklaşınca panel açılsın.

	22'ydi ve lobi büyüyünce (230x156) çok geniş kalıyordu: oyuncu kapıdan
	girer girmez "RETURN TO MY BASE" beliriyor, kürsünün yanına gitmesine
	gerek kalmıyordu. Kürsünün kaidesi 16 stud; 11 onun hemen çevresi
	demek, yani gerçekten yanına gelmek gerekiyor.
]]
local REACH = 11
local BOARD_ROWS = 6

export type Hub = {
	Update: () -> (),
}

local function cashOf(p: Player): number
	local v = p:GetAttribute("Cash")
	return if typeof(v) == "number" then v else 0
end

local function incomeOf(p: Player): number
	local v = p:GetAttribute("Income")
	return if typeof(v) == "number" then v else 0
end

local function stolenOf(p: Player): number
	local stats = p:FindFirstChild("leaderstats")
	local v = stats and stats:FindFirstChild("Stolen")
	if v and v:IsA("IntValue") then
		return v.Value
	end
	return 0
end

--[[ Panoyu dolduran metni üretir: sıra, isim, değer. ]]
local function boardText(score: (Player) -> number, format: (number) -> string): string
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		return score(a) > score(b)
	end)

	local lines = {}
	for i = 1, math.min(#list, BOARD_ROWS) do
		local p = list[i]
		local mark = if p == player then " <" else ""
		table.insert(lines, string.format("%d.  %-14s %s%s", i, string.sub(p.DisplayName, 1, 14), format(score(p)), mark))
	end

	if #lines == 0 then
		return "no players"
	end
	return table.concat(lines, "\n")
end

function Lobby.Create(screen: ScreenGui): Hub
	-- ─── Işınlanma paneli ───────────────────────────────────────────────────

	local panel = Instance.new("Frame")
	panel.Name = "TransitPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -150)
	panel.Size = UDim2.fromOffset(300, 108)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -32, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 12
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = MUTED
	title.Text = "TRANSIT"
	title.Parent = panel

	local button = Instance.new("TextButton")
	button.Name = "Teleport"
	button.Position = UDim2.fromOffset(16, 32)
	button.Size = UDim2.new(1, -32, 0, 40)
	button.BackgroundColor3 = NEON
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = Color3.fromRGB(10, 18, 24)
	button.Text = "RETURN TO MY BASE"
	button.AutoButtonColor = true
	button.Parent = panel

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	local note = Instance.new("TextLabel")
	note.Position = UDim2.fromOffset(16, 76)
	note.Size = UDim2.new(1, -32, 0, 22)
	note.BackgroundTransparency = 1
	note.Font = Enum.Font.GothamMedium
	note.TextSize = 12
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = MUTED
	note.Text = ""
	note.Parent = panel

	--[[
		Kendi üssünü tabeladaki isimden buluyoruz; sunucu sahiplik bilgisini
		ayrıca yayınlamıyor ama tabela zaten replike oluyor.
	]]
	local function myPlot(): Model?
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

	local function carrying(): boolean
		local char = player.Character
		return char ~= nil and char:FindFirstChild("CarriedUnit") ~= nil
	end

	button.Activated:Connect(function()
		--[[
			Taşırken ışınlanma YOK. Çalmanın bütün riski üsse kadar yürümekte;
			ışınlanmak o riski sıfırlar ve çalmayı bedavaya çevirir. Config'de
			CarryTravelTolerance da tam bu yüzden var — sunucu zaten yürüme
			süresini denetliyor, burada da kapıyı kapatıyoruz.
		]]
		if carrying() then
			note.Text = "Can't teleport while carrying"
			note.TextColor3 = WARN
			return
		end

		local plot = myPlot()
		local base = plot and plot:FindFirstChild("Base")
		local char = player.Character
		if not (base and base:IsA("BasePart") and char) then
			note.Text = "You don't own a base yet"
			note.TextColor3 = WARN
			return
		end

		char:PivotTo(CFrame.new(base.Position + Vector3.new(0, 5, 0)))
		note.Text = ""
	end)

	-- ─── Panolar ────────────────────────────────────────────────────────────

	local function fillBoard(index: number, text: string)
		local decor = workspace:FindFirstChild("Decor")
		local boards = decor and decor:FindFirstChild("Boards")
		local screenPart = boards and boards:FindFirstChild("BoardScreen" .. index)
		local surface = screenPart and screenPart:FindFirstChild("Display")
		local body = surface and surface:FindFirstChild("Body")
		if body and body:IsA("TextLabel") then
			body.Text = text
		end
	end

	-- ─── Döngü ──────────────────────────────────────────────────────────────

	local function update()
		-- Kürsüye yakın mıyız
		local decor = workspace:FindFirstChild("Decor")
		local pad = decor and decor:FindFirstChild("TeleportPad")
		local column = pad and pad:FindFirstChild("PadColumn")
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")

		if column and column:IsA("BasePart") and root and root:IsA("BasePart") then
			local near = (root.Position - column.Position).Magnitude <= REACH
			panel.Visible = near
			if near and carrying() then
				note.Text = "Can't teleport while carrying"
				note.TextColor3 = WARN
			elseif near and note.TextColor3 == WARN then
				note.Text = ""
			end
		else
			panel.Visible = false
		end

		fillBoard(1, boardText(cashOf, function(v)
			return "$" .. Config.FormatCash(v)
		end))
		fillBoard(2, boardText(stolenOf, function(v)
			return tostring(math.floor(v))
		end))
		fillBoard(3, boardText(incomeOf, function(v)
			return "+$" .. Config.FormatCash(v) .. "/s"
		end))
	end

	return { Update = update }
end

return Lobby
