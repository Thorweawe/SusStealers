--!strict
--[[
	Ekipman çubuğu: Roblox'un hazır sırt çantası çubuğunun yerine.

	NEDEN: hazır çubuk düz gri kutulardı ("Slap Glove / Gravity Coil /
	Speed Coil" yazıları) ve ekranın tam ortasında her pencerenin ÜSTÜNE
	biniyordu — Rebirth penceresinin satın alma düğmesi bile altında
	kalıyordu. Bu çubuk arayüzün geri kalanıyla aynı kabartma dilinde,
	ekipmanın resmini gösteriyor ve pencerelerin ALTINDA kalıyor.

	Davranış hazır çubukla aynı: tıkla ya da 1-9'a bas → kuşan; kuşanılıysa
	bırak. Araçlar sunucudan geliyor (GearService); burası yalnızca gösterip
	kuşandırıyor.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.UiKit)

local Hotbar = {}

export type Bar = {
	Destroy: () -> (),
}

local SLOT = 62
local GAP = 8
local ACCENT = Color3.fromRGB(80, 96, 116)

local KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

function Hotbar.Create(screen: ScreenGui): Bar
	local player = Players.LocalPlayer

	-- Hazır çubuğu kapat: oturumun ilk anında çağrı başarısız olabiliyor
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)

	local bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromOffset(SLOT, SLOT + 4)
	bar.BackgroundTransparency = 1
	bar.ZIndex = 2
	bar.Visible = false
	bar.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = bar

	local tools: { Tool } = {}
	local connections: { RBXScriptConnection } = {}

	local function humanoid(): Humanoid?
		local char = player.Character
		return char and char:FindFirstChildOfClass("Humanoid")
	end

	local function toggle(tool: Tool)
		local hum = humanoid()
		if not hum then
			return
		end
		if tool.Parent == player.Character then
			hum:UnequipTools()
		else
			hum:EquipTool(tool)
		end
	end

	local function collect(): { Tool }
		local list: { Tool } = {}
		local backpack = player:FindFirstChildOfClass("Backpack")
		for _, container in { backpack, player.Character } do
			if container then
				for _, child in container:GetChildren() do
					if child:IsA("Tool") then
						table.insert(list, child)
					end
				end
			end
		end
		-- Sıra kalıcı: ekipman kimliğine göre (kuşanınca yer değiştirmesin)
		table.sort(list, function(a, b)
			local ka = tostring(a:GetAttribute("GearId") or a.Name)
			local kb = tostring(b:GetAttribute("GearId") or b.Name)
			return ka < kb
		end)
		return list
	end

	local function redraw()
		for _, child in bar:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		tools = collect()
		-- Arayüz gizliyken (Topbar gözü) yeniden çizim çubuğu geri açmasın
		bar.Visible = #tools > 0 and screen:GetAttribute("UiHidden") ~= true
		bar.Size = UDim2.fromOffset(math.max(SLOT, #tools * SLOT + (#tools - 1) * GAP), SLOT + 4)

		for i, tool in tools do
			local equipped = tool.Parent == player.Character
			local tint = if equipped then UiKit.CREW.CYAN:Lerp(Color3.new(0, 0, 0), 0.25) else ACCENT
			local holder, button = UiKit.Raised(bar, "Slot" .. i, tint, UDim2.fromOffset(SLOT, SLOT + 4), 14)
			holder.LayoutOrder = i
			if equipped then
				-- Kuşanılı yuva bir tık yukarıda ve beyaz çerçeveli
				local stroke = button:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = Color3.new(1, 1, 1)
					stroke.Thickness = 2.5
				end
			end

			local icon = Instance.new("Frame")
			icon.Size = UDim2.fromScale(1, 1)
			icon.BackgroundTransparency = 1
			icon.ZIndex = button.ZIndex + 1
			icon.Parent = button
			local gearId = tool:GetAttribute("GearId")
			if typeof(gearId) == "string" then
				UiKit.GearIcon(icon, 40, gearId)
			else
				local name = Instance.new("TextLabel")
				name.Size = UDim2.new(1, -8, 1, -8)
				name.Position = UDim2.fromOffset(4, 4)
				name.BackgroundTransparency = 1
				name.Font = Enum.Font.GothamBold
				name.TextScaled = true
				name.TextColor3 = Color3.new(1, 1, 1)
				name.Text = tool.Name
				name.ZIndex = icon.ZIndex + 1
				name.Parent = icon
			end

			local key = Instance.new("TextLabel")
			key.Position = UDim2.fromOffset(6, 3)
			key.Size = UDim2.fromOffset(14, 14)
			key.BackgroundTransparency = 1
			key.Font = Enum.Font.FredokaOne
			key.TextSize = 14
			key.TextColor3 = Color3.new(1, 1, 1)
			key.TextStrokeTransparency = 0.4
			key.Text = tostring(i)
			key.ZIndex = icon.ZIndex + 3
			key.Parent = button

			button.MouseButton1Click:Connect(function()
				toggle(tool)
			end)
		end
	end

	local watched: { [Instance]: { RBXScriptConnection } } = {}
	local function watch(container: Instance?)
		if not container or watched[container] then
			return
		end
		watched[container] = {
			container.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					redraw()
				end
			end),
			container.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") then
					redraw()
				end
			end),
		}
		container.Destroying:Connect(function()
			local list = watched[container]
			if list then
				for _, c in list do
					c:Disconnect()
				end
				watched[container] = nil
			end
		end)
	end

	local function hookCharacter(char: Model?)
		watch(char)
		watch(player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10))
		redraw()
	end

	table.insert(connections, player.CharacterAdded:Connect(hookCharacter))
	table.insert(connections, player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watch(child)
			redraw()
		end
	end))
	hookCharacter(player.Character)

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local index = table.find(KEYS, input.KeyCode)
		local tool = index and tools[index]
		if tool then
			toggle(tool)
		end
	end))

	return {
		Destroy = function()
			for _, c in connections do
				c:Disconnect()
			end
			bar:Destroy()
		end,
	}
end

return Hotbar
