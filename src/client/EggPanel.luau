--!strict
--[[
	Yumurta paneli: MedBay kuluçkahanesinde bir yumurtaya yaklaşınca
	açılıyor (pet simülatörlerinin yumurta panosu gibi).

	  Sol kart   — yumurtanın adı ve fiyatı, içinden çıkabilecek HER pet:
	               figürü, kademesi ve çıkma şansı. Secret, indekste
	               bulunana kadar "?" siluet.
	  Sağ sütun  — AUTO-DELETE: kademe başına aç/kapa. Açık kademeden çıkan
	               pet envantere girmiyor (mutasyonlular hariç), ama indekse
	               işleniyor. Tercih hesaba kaydediliyor (SettingsService),
	               uygulaması sunucuda (PetService.TryHatch).
	  Alt düğmeler — E x1, R x3, T Auto. Klavyede aynı tuşlar yumurtanın
	               promptları; promptların varsayılan kutuları gizleniyor
	               (bu panel onların yerini alıyor).

	Panel ekranın üst ortasında, yalnızca bir yumurtanın yanındayken
	açık; boyutu ekrana göre ölçekli.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PetModel = require(Shared.PetModel)

local UiKit = require(script.Parent.UiKit)

local EggPanel = {}

local SHOW_DISTANCE = 13
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(16, 18, 28)
local PANEL_W, PANEL_H = 560, 340

type AutoHandle = {
	Toggle: (eggId: string, count: number) -> (),
	Current: () -> (string?, number),
}

local function tierColor(rarity: string): Color3
	if rarity == "Secret" then
		return Color3.fromRGB(190, 150, 255)
	end
	return Config.Rarities[rarity].color
end

local function eggTint(egg: Config.EggDef): Color3
	local t = egg.tint
	if t.R + t.G + t.B < 0.5 then
		return Color3.fromRGB(170, 120, 255)
	end
	return t
end

local function chanceText(pct: number): string
	if pct >= 10 then
		return string.format("%d%%", math.floor(pct + 0.5))
	elseif pct >= 1 then
		return string.format("%.1f%%", pct)
	end
	return string.format("%.2f%%", pct)
end

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

local function text(parent: Instance, value: string, size: number, color: Color3, z: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextSize = size
	t.TextColor3 = color
	t.Text = value
	t.ZIndex = z
	t.Parent = parent
	return t
end

--[[
	`isHatching`: açılış animasyonu oynarken panel gizleniyor — ekranın
	üstünde durup açılan yumurtayı örtüyordu.
]]
function EggPanel.Create(auto: AutoHandle?, isHatching: (() -> boolean)?)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local hatchRemote = Net.Get("PetHatch")
	local saveRemote = Net.Get("SettingsSave")

	-- Bulunan petler (Pets remote'u) ve otomatik silme tercihi
	local found: { [string]: boolean } = {}
	local function readAutoDelete(): { [string]: boolean }
		local out = {}
		local raw = player:GetAttribute("SettingAutoDelete")
		if typeof(raw) == "string" then
			for id in string.gmatch(raw, "[^,]+") do
				out[id] = true
			end
		end
		return out
	end

	--[[
		Ekranın üst ortasında (dünyada değil). İlk hâli yumurtanın tepesinde
		bir BillboardGui'ydi; kamera yumurtaya yakınken pano ekranın üstünden
		taşıyor, yalnızca E/R/T düğmeleri görünüyordu.
	]]
	local board = Instance.new("ScreenGui")
	board.Name = "EggPanel"
	board.ResetOnSpawn = false
	board.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	board.DisplayOrder = 5
	board.Enabled = false
	board.Parent = playerGui

	-- Ekrana göre ölçek (DeviceLayout ile aynı referans); UIScale sol üstten
	-- küçülttüğü için konum elle ortalanıyor
	local root = Instance.new("Frame")
	root.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	root.BackgroundTransparency = 1
	root.Parent = board
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		local s = math.clamp(math.min(vp.X / 1280, vp.Y / 660), 0.5, 1)
		uiScale.Scale = s
		root.Position = UDim2.new(0.5, -PANEL_W * s / 2, 0, 8)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()
	--[[
		CanvasGroup DEĞİL, düz Frame. CanvasGroup içeriği düşük çözünürlüklü
		bir dokuya çizip ekrana koyuyor: 3B pet simgeleri (ViewportFrame) ve
		yazılar bulanıklaşıyordu. Ayrıca kendi boyutunun dışını kesiyordu —
		15 petli yumurtada son satır ve E/R/T düğmeleri görünmüyordu.
		Açılış solma yerine hafif büyüme (UIScale).
	]]
	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundTransparency = 1
	fade.Parent = root
	local pop = Instance.new("UIScale")
	pop.Parent = fade

	local currentEgg: Config.EggDef? = nil
	local content: Frame? = nil
	local autoButton: TextButton? = nil
	local autoLabel: TextLabel? = nil

	local saveToken = 0
	local function saveAutoDelete(set: { [string]: boolean })
		-- Yerelde hemen yaz (panel anında güncellensin), sunucuya durunca
		local list = {}
		for rarity, on in set do
			if on then
				table.insert(list, rarity)
			end
		end
		table.sort(list, function(a, b)
			return Config.Rarities[a].order < Config.Rarities[b].order
		end)
		player:SetAttribute("SettingAutoDelete", table.concat(list, ","))
		saveToken += 1
		local token = saveToken
		task.delay(0.4, function()
			if token == saveToken then
				saveRemote:FireServer({ autoDelete = set })
			end
		end)
	end

	local function refreshAuto()
		if not (autoButton and autoLabel and currentEgg) then
			return
		end
		local id = if auto then (auto.Current()) else nil
		local on = id == currentEgg.id
		autoLabel.Text = if on then "ON" else "Auto"
		autoButton.BackgroundColor3 = if on then Color3.fromRGB(255, 120, 60) else Color3.fromRGB(230, 60, 70)
	end

	--[[ Paneli bir yumurta için baştan kurar. ]]
	local function build(egg: Config.EggDef)
		if content then
			content:Destroy()
		end
		local c = Instance.new("Frame")
		c.Size = UDim2.fromScale(1, 1)
		c.BackgroundTransparency = 1
		c.Parent = fade
		content = c
		local tint = eggTint(egg)
		local pets = Config.GetEggPets(egg.id)
		--[[
			Kart yüksekliği sıra sayısına göre: tek sıralı yumurtada alt yarı
			boş kalmasın. Çok petli yumurtada (her kademede 2-3 pet) hücreler
			küçülüp beşli diziliyor ki kart panele sığsın.
		]]
		local compact = #pets > 8
		local cols = if compact then 5 else 4
		local cellW, cellH = if compact then 66 else 84, if compact then 84 else 96
		local gap = if compact then 6 else 8
		local rowH = cellH + gap
		local rowsNeeded = math.max(1, math.ceil(#pets / cols))
		local cardH = 64 + rowsNeeded * rowH
		-- Otomatik silme satırları kademe başına bir tane (pet başına değil)
		local rarities: { string } = {}
		for _, def in pets do
			if not table.find(rarities, def.rarity) then
				table.insert(rarities, def.rarity)
			end
		end

		--[[
			UIGradient kullanılmıyor: gradyan nesnenin UIStroke'unu da
			boyuyor ve beyaz çerçeve koyulaşıp kayboluyordu. Zemin düz,
			yumurtanın rengine hafif çalan koyu ton.
		]]
		local card = Instance.new("Frame")
		card.Position = UDim2.fromOffset(0, 26)
		card.Size = UDim2.fromOffset(384, cardH)
		card.BackgroundColor3 = UiKit.SHELL:Lerp(tint, 0.16)
		card.ZIndex = 2
		card.Parent = c
		corner(card, 16)
		stroke(card, WHITE, 3)

		-- Başlık hapı kartın üst kenarına oturuyor (tek UIStroke: çerçeve; yazının konturu TextStroke)
		local title = text(c, string.upper(egg.name), 26, WHITE, 6)
		title.AnchorPoint = Vector2.new(0.5, 0)
		title.Position = UDim2.fromOffset(192, 2)
		title.Size = UDim2.fromOffset(250, 44)
		title.BackgroundTransparency = 0
		title.BackgroundColor3 = tint:Lerp(INK, 0.35)
		title.TextStrokeColor3 = INK
		title.TextStrokeTransparency = 0
		corner(title, 12)
		stroke(title, WHITE, 3)

		local price = text(c, "$" .. Config.FormatCash(egg.price), 16, UiKit.CREW.LIME, 7)
		price.AnchorPoint = Vector2.new(1, 0)
		price.Position = UDim2.fromOffset(378, 34)
		price.Size = UDim2.fromOffset(100, 22)
		price.TextXAlignment = Enum.TextXAlignment.Right
		local ps = Instance.new("UIStroke")
		ps.Color = INK
		ps.Thickness = 2
		ps.Parent = price

		local grid = Instance.new("Frame")
		grid.Position = UDim2.fromOffset(12, 56)
		grid.Size = UDim2.fromOffset(360, rowsNeeded * rowH)
		grid.BackgroundTransparency = 1
		grid.ZIndex = 3
		grid.Parent = card
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromOffset(cellW, cellH)
		layout.CellPadding = UDim2.fromOffset(gap, gap)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid

		for i, def in pets do
			local tone = tierColor(def.rarity)
			local hidden = def.rarity == "Secret" and not found[def.id]
			local cell = Instance.new("Frame")
			cell.LayoutOrder = i
			cell.BackgroundColor3 = tone:Lerp(UiKit.SHELL_DEEP, 0.7)
			cell.ZIndex = 4
			cell.Parent = grid
			corner(cell, 10)
			stroke(cell, tone, 2)

			local fig = Instance.new("Frame")
			fig.AnchorPoint = Vector2.new(0.5, 0)
			fig.Position = UDim2.new(0.5, 0, 0, 2)
			-- Büyük: 3B simge küçükte bulanık duruyor
			local figSize = if compact then 44 else 52
			fig.Size = UDim2.fromOffset(figSize, figSize)
			fig.BackgroundTransparency = 1
			fig.ZIndex = 6
			fig.Parent = cell
			if hidden then
				UiKit.PetIcon(fig, figSize, def.id, Color3.fromRGB(20, 20, 30))
				local q = text(fig, "?", 28, WHITE, 12)
				q.Size = UDim2.fromScale(1, 1)
			else
				UiKit.PetIcon(fig, figSize, def.id)
			end

			-- Petin KENDİ şansı (kademe şansı kademedeki pet sayısına bölünmüş)
			local pct = Config.GetPetChance(egg.id, def.id)
			local chance = text(cell, chanceText(pct), if compact then 12 else 16, WHITE, 6)
			chance.AnchorPoint = Vector2.new(0.5, 1)
			chance.Position = UDim2.new(0.5, 0, 1, -1)
			chance.Size = UDim2.new(1, 0, 0, if compact then 15 else 18)
			local cs = Instance.new("UIStroke")
			cs.Color = INK
			cs.Thickness = 1.6
			cs.Parent = chance

			--[[
				Petin ADI fotoğrafın altında (kademe yazısı değil: kademe zaten
				hücrenin çerçeve rengi). Bulunmamış Secret "???" kalıyor.
				İki satıra sığmayan uzun adlar küçülüyor.
			]]
			local name = text(cell, if hidden then "???" else def.name, 11, WHITE, 6)
			name.AnchorPoint = Vector2.new(0.5, 0)
			name.Position = UDim2.new(0.5, 0, 0, figSize + 2)
			name.Size = UDim2.new(1, -6, 0, if compact then 20 else 24)
			name.TextWrapped = true
			name.TextScaled = true
			name.TextStrokeColor3 = INK
			name.TextStrokeTransparency = 0.2
			-- Küçük hücrede iki satır sığsın ("Moon Rock" yalnızca "Moon" kalıyordu)
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = if compact then 9 else 11
			limit.MinTextSize = if compact then 6 else 8
			limit.Parent = name
		end

		-- ── Sağ sütun: AUTO-DELETE ───────────────────────────────────────
		local delH = math.max(cardH, 38 + #rarities * 25)
		local del = Instance.new("Frame")
		del.Position = UDim2.fromOffset(396, 26)
		del.Size = UDim2.fromOffset(164, delH)
		del.BackgroundColor3 = UiKit.SHELL:Lerp(UiKit.CREW.RED, 0.14)
		del.ZIndex = 2
		del.Parent = c
		corner(del, 16)
		stroke(del, WHITE, 3)

		local delTitle = text(del, "AUTO-DELETE", 17, WHITE, 5)
		delTitle.Position = UDim2.fromOffset(0, 6)
		delTitle.Size = UDim2.new(1, 0, 0, 22)
		delTitle.TextStrokeColor3 = INK
		delTitle.TextStrokeTransparency = 0

		local rows = Instance.new("Frame")
		rows.Position = UDim2.fromOffset(8, 32)
		rows.Size = UDim2.new(1, -16, 1, -38)
		rows.BackgroundTransparency = 1
		rows.ZIndex = 3
		rows.Parent = del
		local rl = Instance.new("UIListLayout")
		rl.Padding = UDim.new(0, 3)
		rl.SortOrder = Enum.SortOrder.LayoutOrder
		rl.Parent = rows

		local rowHeight = math.floor((delH - 38 - (#rarities - 1) * 3) / math.max(#rarities, 1))
		rowHeight = math.clamp(rowHeight, 20, 30)
		for i, rarity in rarities do
			local tone = tierColor(rarity)
			local row = Instance.new("TextButton")
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, rowHeight)
			row.BackgroundColor3 = tone:Lerp(UiKit.SHELL_DEEP, 0.78)
			row.AutoButtonColor = false
			row.Text = ""
			row.ZIndex = 4
			row.Parent = rows
			corner(row, 8)
			local name = text(row, rarity, 14, tone, 5)
			name.Position = UDim2.fromOffset(8, 0)
			name.Size = UDim2.new(1, -60, 1, 0)
			name.TextXAlignment = Enum.TextXAlignment.Left
			local ns = Instance.new("UIStroke")
			ns.Color = INK
			ns.Thickness = 1.4
			ns.Parent = name

			local pill = Instance.new("Frame")
			pill.AnchorPoint = Vector2.new(1, 0.5)
			pill.Position = UDim2.new(1, -6, 0.5, 0)
			pill.Size = UDim2.fromOffset(46, rowHeight - 8)
			pill.ZIndex = 5
			pill.Parent = row
			corner(pill, 10)
			local knob = Instance.new("Frame")
			knob.AnchorPoint = Vector2.new(0.5, 0.5)
			knob.Size = UDim2.fromOffset(rowHeight - 12, rowHeight - 12)
			knob.BackgroundColor3 = WHITE
			knob.ZIndex = 6
			knob.Parent = pill
			corner(knob, 10)
			local state = text(pill, "", 10, WHITE, 7)
			state.Font = Enum.Font.GothamBlack
			state.Size = UDim2.fromScale(1, 1)

			local function draw()
				local on = readAutoDelete()[rarity] == true
				pill.BackgroundColor3 = if on then Color3.fromRGB(220, 60, 70) else Color3.fromRGB(70, 76, 96)
				knob.Position = UDim2.new(if on then 1 else 0, if on then -(rowHeight - 12) / 2 - 3 else (rowHeight - 12) / 2 + 3, 0.5, 0)
				state.Text = if on then "ON   " else "   OFF"
			end
			draw()
			row.Activated:Connect(function()
				local set = readAutoDelete()
				set[rarity] = not set[rarity] or nil
				saveAutoDelete(set)
				draw()
			end)
			player:GetAttributeChangedSignal("SettingAutoDelete"):Connect(draw)
		end

		-- ── Alt: E / R / T ───────────────────────────────────────────────
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0)
		bar.Position = UDim2.fromOffset(192, 26 + math.max(cardH, delH) + 10)
		bar.Size = UDim2.fromOffset(330, 74)
		bar.BackgroundTransparency = 1
		bar.ZIndex = 3
		bar.Parent = c
		local bl = Instance.new("UIListLayout")
		bl.FillDirection = Enum.FillDirection.Horizontal
		bl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		bl.Padding = UDim.new(0, 16)
		bl.Parent = bar

		local function roundButton(key: string, sub: string, color: Color3, order: number): (TextButton, TextLabel)
			local b = Instance.new("TextButton")
			b.LayoutOrder = order
			b.Size = UDim2.fromOffset(68, 68)
			b.BackgroundColor3 = color
			b.AutoButtonColor = true
			b.Font = Enum.Font.FredokaOne
			b.TextSize = 34
			b.TextColor3 = WHITE
			b.Text = key
			b.ZIndex = 4
			b.Parent = bar
			corner(b, 34)
			stroke(b, WHITE, 3)
			local ks = Instance.new("UIStroke")
			ks.Color = INK
			ks.Thickness = 2.4
			ks.Parent = b
			local s = text(b, sub, 15, WHITE, 6)
			s.AnchorPoint = Vector2.new(0.5, 1)
			s.Position = UDim2.new(0.5, 0, 1, 8)
			s.Size = UDim2.fromOffset(70, 18)
			local ss = Instance.new("UIStroke")
			ss.Color = INK
			ss.Thickness = 2
			ss.Parent = s
			return b, s
		end

		local eggId = egg.id
		local one = roundButton("E", "x1", Color3.fromRGB(60, 200, 90), 1)
		one.Activated:Connect(function()
			hatchRemote:FireServer(eggId, 1, false)
		end)
		local three = roundButton("R", "x3", Color3.fromRGB(150, 70, 230), 2)
		three.Activated:Connect(function()
			hatchRemote:FireServer(eggId, Config.TripleHatchCount, false)
		end)
		local autoB, autoS = roundButton("T", "Auto", Color3.fromRGB(230, 60, 70), 3)
		autoButton, autoLabel = autoB, autoS
		autoB.Activated:Connect(function()
			if auto then
				auto.Toggle(eggId, 1)
				task.defer(refreshAuto)
			end
		end)
		refreshAuto()
	end

	-- ── Yakındaki yumurta ────────────────────────────────────────────────
	type Shell = { part: BasePart, egg: Config.EggDef }
	local shells: { Shell } = {}
	local function collect()
		table.clear(shells)
		local decor = workspace:FindFirstChild("Decor")
		local hatchery = decor and decor:FindFirstChild("Hatchery", true)
		if not hatchery then
			return
		end
		for _, d in hatchery:GetChildren() do
			local id = d:GetAttribute("EggId")
			local egg = typeof(id) == "string" and Config.GetEgg(id) or nil
			if d:IsA("BasePart") and egg then
				table.insert(shells, { part = d, egg = egg })
				-- Promptların varsayılan kutusu gizli: bu panel onların yerine
				for _, p in d:GetChildren() do
					if p:IsA("ProximityPrompt") and p.Style ~= Enum.ProximityPromptStyle.Custom then
						p.Style = Enum.ProximityPromptStyle.Custom
					end
				end
			end
		end
	end

	Net.Get("Pets").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.found) ~= "table" then
			return
		end
		table.clear(found)
		for _, id in payload.found do
			if typeof(id) == "string" then
				found[id] = true
			end
		end
		-- Secret bulunduysa siluet açılsın
		if currentEgg and board.Enabled then
			build(currentEgg)
		end
	end)

	local visible = false
	local function setVisible(on: boolean)
		if visible == on then
			return
		end
		visible = on
		if on then
			board.Enabled = true
			pop.Scale = 0.94
			TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		else
			board.Enabled = false
		end
	end

	task.spawn(function()
		local lastCollect = 0
		while true do
			task.wait(0.2)
			if os.clock() - lastCollect > 5 or #shells == 0 then
				lastCollect = os.clock()
				collect()
			end
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local best: Shell? = nil
			local bestDist = SHOW_DISTANCE
			if rootPart and rootPart:IsA("BasePart") then
				for _, s in shells do
					local d = (s.part.Position - rootPart.Position).Magnitude
					if d < bestDist then
						best, bestDist = s, d
					end
				end
			end
			if best and isHatching and isHatching() then
				setVisible(false)
			elseif best then
				if currentEgg ~= best.egg then
					currentEgg = best.egg
					build(best.egg)
				end
				refreshAuto()
				setVisible(true)
			else
				setVisible(false)
			end
		end
	end)
end

return EggPanel
