--!strict
--[[
	Admin haritasını ekranın ortasında büyük açar (Among Us'ta admin
	masasına dokununca açılan harita gibi).

	Haritayı sunucu zaten çiziyor: ADMIN odasındaki masanın ekranında bir
	SurfaceGui (AdminMapService). Burası o SurfaceGui'nin içeriğini saniyede
	bir kopyalayıp pencereye koyuyor — aynı harita, aynı noktalar, ikinci
	bir çizim kodu yok. Masadaki "AdminPrompt" açıyor.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")

local UiKit = require(script.Parent.UiKit)

local AdminView = {}

local ACCENT = Color3.fromRGB(90, 240, 150)
-- Masanın ekran oranı (AdminScreen 12.4 x 10.4 stud)
local MAP_W, MAP_H = 620, 520

local function findSource(): Frame?
	local decor = workspace:FindFirstChild("Decor")
	local tableModel = decor and decor:FindFirstChild("AdminTable")
	local screen = tableModel and tableModel:FindFirstChild("AdminScreen")
	local gui = screen and screen:FindFirstChild("AdminMap")
	local bg = gui and gui:FindFirstChild("Background")
	return if bg and bg:IsA("Frame") then bg else nil
end

function AdminView.Create(screen: Instance)
	local player = Players.LocalPlayer

	local window = UiKit.Window(screen, "AdminView", ACCENT)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(MAP_W + 36, MAP_H + 110)
	window.Visible = false
	window.ZIndex = 40

	local title, sub = UiKit.Heading(window, "ADMIN MAP", ACCENT)
	title.ZIndex = 41
	sub.ZIndex = 41
	sub.Text = "Live crew locations. A red base has an intruder!"
	local close = UiKit.CloseButton(window)
	close.ZIndex = 46

	local holder = Instance.new("Frame")
	holder.Name = "Map"
	holder.Position = UDim2.fromOffset(18, 62)
	holder.Size = UDim2.fromOffset(MAP_W, MAP_H)
	holder.BackgroundColor3 = Color3.fromRGB(10, 20, 30)
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.ZIndex = 41
	holder.Parent = window
	UiKit.Corner(holder, 10)

	local missing = Instance.new("TextLabel")
	missing.Size = UDim2.fromScale(1, 1)
	missing.BackgroundTransparency = 1
	missing.Font = Enum.Font.GothamBold
	missing.TextSize = 16
	missing.TextColor3 = UiKit.MUTED
	missing.Text = "Admin map is offline."
	missing.ZIndex = 42
	missing.Parent = holder

	-- Açıklama: nokta = oyuncu, kırmızı nokta = impostor
	local legend = Instance.new("TextLabel")
	legend.Position = UDim2.new(0, 18, 1, -40)
	legend.Size = UDim2.new(1, -36, 0, 30)
	legend.BackgroundTransparency = 1
	legend.RichText = true
	legend.Font = Enum.Font.GothamBold
	legend.TextSize = 14
	legend.TextColor3 = UiKit.INK
	legend.Text = '<font color="#F5FAFF">●</font> crewmate     <font color="#FF3232">●</font> impostor     <font color="#C8323C">■</font> intruder in base     <font color="#F0A028">■</font> tunnels'
	legend.ZIndex = 41
	legend.Parent = window

	local copy: Instance? = nil
	local function refresh()
		local source = findSource()
		if copy then
			copy:Destroy()
			copy = nil
		end
		missing.Visible = source == nil
		if not source then
			return
		end
		local c = source:Clone()
		c.Size = UDim2.fromScale(1, 1)
		c.Position = UDim2.new()
		-- Kopyanın katmanları pencerenin üstünde kalsın
		for _, d in c:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex += 41
			end
		end
		c.ZIndex = 42
		c.Parent = holder
		copy = c
	end

	local open = false
	close.Activated:Connect(function()
		window.Visible = false
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		open = window.Visible
		if open then
			task.spawn(function()
				while open do
					refresh()
					task.wait(1)
				end
			end)
		elseif copy then
			copy:Destroy()
			copy = nil
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "AdminPrompt" then
			window.Visible = true
		end
	end)
end

return AdminView
