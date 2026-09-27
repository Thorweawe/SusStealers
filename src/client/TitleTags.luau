--!strict
--[[
	Unvan etiketi: her oyuncunun başının üstünde takılı unvanı, nadirlik
	renginde (2026-09-28, "insanlar heves etsin").

	Unvan yalnızca sohbette görünüyordu; kazanmanın bir statüsü yoktu.
	Artık herkes kimin ne olduğunu haritada görüyor:
	  Common..Epic   — düz renk, kalın konturlu yazı
	  Legendary      — ★ ile, altın parıltılı
	  Mythic, Secret — ✦ ile, renkleri kayan (dönen UIGradient) parlak yazı
	Geliştirici unvanı kırmızı-altın.

	Unvanı sunucu yazıyor ("Title", "TitleRarity" nitelikleri; TitleService).
	Varsayılan "Crewmate" gösterilmiyor: herkesin başında aynı yazı kalabalık.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local TitleTags = {}

export type Handle = {
	Destroy: () -> (),
}

local OUTLINE = Color3.fromRGB(18, 14, 28)
local DEVELOPER = "Developer"

local function tagText(title: string, rarity: string): string
	if rarity == "Legendary" then
		return "★ " .. title .. " ★"
	elseif rarity == "Mythic" or rarity == "Secret" then
		return "✦ " .. title .. " ✦"
	end
	return title
end

function TitleTags.Start(): Handle
	local connections: { RBXScriptConnection } = {}
	local shimmer: { UIGradient } = {}

	local function build(player: Player)
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if not (head and head:IsA("BasePart")) then
			return
		end
		local old = head:FindFirstChild("TitleTag")
		if old then
			old:Destroy()
		end
		local title = player:GetAttribute("Title")
		local rarity = player:GetAttribute("TitleRarity")
		if typeof(title) ~= "string" or title == "" or typeof(rarity) ~= "string" or title == "Crewmate" then
			return
		end

		local gui = Instance.new("BillboardGui")
		gui.Name = "TitleTag"
		gui.Size = UDim2.fromOffset(260, 34)
		gui.StudsOffset = Vector3.new(0, 2.7, 0)
		gui.MaxDistance = 95
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextSize = if rarity == "Mythic" or rarity == "Secret" or rarity == DEVELOPER then 24 else 21
		label.Text = if rarity == DEVELOPER then "[" .. title .. "]" else tagText(title, rarity)
		label.TextColor3 = if rarity == DEVELOPER then Color3.fromRGB(255, 210, 60) else Config.GetTitleColor(rarity)
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = if rarity == DEVELOPER then Color3.fromRGB(150, 20, 40) else OUTLINE
		stroke.Thickness = 2.5
		stroke.Parent = label

		-- Mitik ve Secret: renkleri kayan parlak yazı
		if rarity == "Mythic" or rarity == "Secret" then
			label.TextColor3 = Color3.new(1, 1, 1)
			local gradient = Instance.new("UIGradient")
			gradient.Color = if rarity == "Secret"
				then ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 200)),
					ColorSequenceKeypoint.new(0.33, Color3.fromRGB(120, 220, 255)),
					ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255, 240, 140)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 200)),
				})
				else ColorSequence.new(Color3.fromRGB(255, 70, 130), Color3.fromRGB(255, 190, 220))
			gradient.Parent = label
			table.insert(shimmer, gradient)
		end
		gui.Parent = head
	end

	local function watch(player: Player)
		table.insert(connections, player:GetAttributeChangedSignal("Title"):Connect(function()
			build(player)
		end))
		table.insert(connections, player:GetAttributeChangedSignal("TitleRarity"):Connect(function()
			build(player)
		end))
		table.insert(connections, player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			build(player)
		end))
		build(player)
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watch))

	-- Parıltı: gradyanlar yavaşça dönüyor
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local rot = (os.clock() * 90) % 360
		for i = #shimmer, 1, -1 do
			local g = shimmer[i]
			if g.Parent then
				g.Rotation = rot
				g.Offset = Vector2.new(math.sin(os.clock() * 1.5) * 0.3, 0)
			else
				table.remove(shimmer, i)
			end
		end
	end))

	return {
		Destroy = function()
			for _, c in connections do
				c:Disconnect()
			end
		end,
	}
end

return TitleTags
