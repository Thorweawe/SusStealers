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
	2026-10-03: her unvanın kendi amblemi (UiArt.TitleIcon, ChatGPT) yazının
	solunda; kademeye göre efekt:
	  Rare       — amblem hafifçe nefes alıyor
	  Epic+      — yazının üstünden geçen ışık şeridi
	  Legendary+ — amblemin arkasında dönen ışık + etrafta yanıp sönen yıldızlar

	Unvanı sunucu yazıyor ("Title", "TitleRarity" nitelikleri; TitleService).
	Varsayılan "Crewmate" gösterilmiyor: herkesin başında aynı yazı kalabalık.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local UiArt = require(script.Parent.UiArt)

local TitleTags = {}

export type Handle = {
	Destroy: () -> (),
}

local OUTLINE = Color3.fromRGB(18, 14, 28)
local DEVELOPER = "Developer"
local TIER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7 }

-- Unvan adından kimliğe (nitelikte ad duruyor)
local ID_BY_NAME: { [string]: string } = {}
for _, t in Config.Titles do
	ID_BY_NAME[t.name] = t.id
end

type Fx = { kind: string, inst: GuiObject, phase: number }

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
	local fx: { Fx } = {}

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

		local tier = TIER[rarity] or 0
		local icon = UiArt.TitleIcon[ID_BY_NAME[title] or ""]

		local gui = Instance.new("BillboardGui")
		gui.Name = "TitleTag"
		gui.Size = UDim2.fromOffset(300, 40)
		gui.StudsOffset = Vector3.new(0, 2.7, 0)
		gui.MaxDistance = 95
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		-- Amblem + yazı yan yana, ortalı
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(1, 1)
		row.Parent = gui
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = row
		if icon then
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.fromOffset(38, 38)
			holder.LayoutOrder = 1
			holder.Parent = row
			if tier >= 5 then
				local rays = Instance.new("ImageLabel")
				rays.BackgroundTransparency = 1
				rays.AnchorPoint = Vector2.new(0.5, 0.5)
				rays.Position = UDim2.fromScale(0.5, 0.5)
				rays.Size = UDim2.fromScale(1.9, 1.9)
				rays.Image = Config.Vfx.Star
				rays.ImageColor3 = Config.GetTitleColor(rarity)
				rays.ImageTransparency = 0.25
				rays.Parent = holder
				table.insert(fx, { kind = "spin", inst = rays, phase = math.random() * 6 })
			end
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromScale(1, 1)
			img.Image = icon
			img.ZIndex = 2
			img.Parent = holder
			if tier >= 3 then
				table.insert(fx, { kind = "pulse", inst = img, phase = math.random() * 6 })
			end
			if tier >= 5 then
				for i, at in { Vector2.new(0.12, 0.1), Vector2.new(0.88, 0.2), Vector2.new(0.6, 0.95) } do
					local star = Instance.new("ImageLabel")
					star.BackgroundTransparency = 1
					star.AnchorPoint = Vector2.new(0.5, 0.5)
					star.Size = UDim2.fromOffset(14, 14)
					star.Position = UDim2.fromScale(at.X, at.Y)
					star.Image = Config.Vfx.Star
					star.ZIndex = 3
					star.Parent = gui
					table.insert(fx, { kind = "twinkle", inst = star, phase = i * 2.1 })
				end
			end
		end

		local label = Instance.new("TextLabel")
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.LayoutOrder = 2
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextSize = if rarity == "Mythic" or rarity == "Secret" or rarity == DEVELOPER then 24 else 21
		label.Text = if rarity == DEVELOPER then "[" .. title .. "]" else tagText(title, rarity)
		label.TextColor3 = if rarity == DEVELOPER then Color3.fromRGB(255, 210, 60) else Config.GetTitleColor(rarity)
		label.Parent = row
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
		elseif tier == 4 or tier == 5 then
			-- Epic/Legendary: yazının üstünden geçen beyaz ışık şeridi
			local tone = Config.GetTitleColor(rarity)
			label.TextColor3 = Color3.new(1, 1, 1)
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, tone),
				ColorSequenceKeypoint.new(0.42, tone),
				ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.58, tone),
				ColorSequenceKeypoint.new(1, tone),
			})
			gradient.Parent = label
			table.insert(fx, { kind = "sweep", inst = gradient :: any, phase = math.random() * 3 })
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
		local now = os.clock()
		for i = #fx, 1, -1 do
			local f = fx[i]
			local inst: any = f.inst
			if not inst.Parent then
				table.remove(fx, i)
			elseif f.kind == "spin" then
				inst.Rotation = (now * 40 + f.phase * 60) % 360
			elseif f.kind == "pulse" then
				local k = 1 + math.sin(now * 2.4 + f.phase) * 0.07
				inst.Size = UDim2.fromScale(k, k)
			elseif f.kind == "twinkle" then
				local k = math.max(0, math.sin(now * 3 + f.phase))
				inst.ImageTransparency = 1 - k
				inst.Rotation = now * 90 % 360
			elseif f.kind == "sweep" then
				-- 2,6 sn'de bir soldan sağa geçiyor, arada bekliyor
				local t = ((now + f.phase) % 2.6) / 1.3
				inst.Offset = Vector2.new(math.clamp(t, 0, 1) * 2 - 1, 0)
			end
		end
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
