--!strict
--[[
	Yumurta açılışı ve birleştirme animasyonu.

	NEDEN VAR: yumurtayı açınca yalnızca köşede bir bildirim çıkıyordu.
	Bu türün en önemli anı o — oyuncunun parasını şansa yatırdığı an.

	Akış: yumurta(lar) ekranın ortasında sallanıyor, beyaz bir parlama ile
	çatlıyor, arkada kademe renginde ışınlar dönerken pet(ler) beliriyor.

	═══ SÜRE ═══════════════════════════════════════════════════════════════

	Toplam süre Config.HatchDuration ile aynı: sunucu bir yumurta açılırken
	ikincisini kabul etmiyor, animasyon da o süre boyunca ekranda. Oyuncu
	tıklayıp sonucu erken kapatabiliyor ama bir sonraki yumurta yine süre
	dolana kadar açılmıyor. Eskiden bekleme yoktu; art arda basınca
	animasyonlar kuyruğa giriyor ve sonuçlar birbirine karışıyordu.

	Üçlü açmada üç yumurta yan yana, aynı anda çatlıyor.

	Sonucu sunucu belirliyor (PetHatched: anahtar listesi); burası sadece
	gösteriyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PetModel = require(Shared.PetModel)

local UiKit = require(script.Parent.UiKit)
local FuseFX = require(script.Parent.FuseFX)

local HatchFX = {}

export type Handle = {
	IsPlaying: () -> boolean,
	Destroy: () -> (),
}

local Z = 80

-- Süre dağılımı (toplam ≈ Config.HatchDuration)
local WOBBLE = { 0.16, 0.12, 0.08 }   -- her sallanma iki yön
local REVEAL = Config.HatchDuration - 0.8 - 0.25

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = TweenService:Create(object, info, goal)
	t:Play()
	return t
end

-- Secret'ın kendi rengi koyu panelde görünmüyor; arayüzde mor vurgu
local function tierColor(rarity: string): Color3
	if rarity == "Secret" then
		return Color3.fromRGB(190, 150, 255)
	end
	return Config.Rarities[rarity].color
end

function HatchFX.Create(screen: ScreenGui): Handle
	local layer = Instance.new("Frame")
	layer.Name = "HatchFX"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundColor3 = Color3.new(0, 0, 0)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Visible = false
	layer.ZIndex = Z
	layer.Parent = screen

	-- Tıklanınca erken kapanıyor; animasyonun ilk yarısında kapalı
	local dismiss = Instance.new("TextButton")
	dismiss.Size = UDim2.fromScale(1, 1)
	dismiss.BackgroundTransparency = 1
	dismiss.Text = ""
	dismiss.AutoButtonColor = false
	dismiss.Active = false
	dismiss.ZIndex = Z + 20
	dismiss.Parent = layer

	local headline = Instance.new("TextLabel")
	headline.AnchorPoint = Vector2.new(0.5, 0)
	headline.Position = UDim2.new(0.5, 0, 0.18, 0)
	headline.Size = UDim2.fromOffset(600, 30)
	headline.BackgroundTransparency = 1
	headline.Font = Enum.Font.GothamBlack
	headline.TextSize = 24
	headline.TextColor3 = UiKit.INK
	headline.TextStrokeTransparency = 0.4
	headline.ZIndex = Z + 4
	headline.Parent = layer

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = Z + 10
	flash.Parent = layer

	-- Yan yana sonuç yuvaları: tek açılışta ortadaki, üçlüde üçü
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.48)
	row.Size = UDim2.fromOffset(720, 360)
	row.BackgroundTransparency = 1
	row.ZIndex = Z + 1
	row.Parent = layer

	type Slot = {
		root: Frame,
		rays: Frame,
		bars: { Frame },
		figure: Frame,
		name: TextLabel,
		tier: TextLabel,
		stat: TextLabel,
	}
	local slots: { Slot } = {}

	local function makeSlot(): Slot
		local root = Instance.new("Frame")
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Size = UDim2.fromOffset(230, 340)
		root.BackgroundTransparency = 1
		root.ZIndex = Z + 1
		root.Parent = row

		local rays = Instance.new("Frame")
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.new(0.5, 0, 0, 110)
		rays.Size = UDim2.fromOffset(300, 300)
		rays.BackgroundTransparency = 1
		rays.ZIndex = Z + 1
		rays.Parent = root

		local bars: { Frame } = {}
		for i = 0, 5 do
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.new(1, 0, 0, 22)
			bar.Rotation = i * 30
			bar.BackgroundColor3 = Color3.new(1, 1, 1)
			bar.BackgroundTransparency = 1
			bar.BorderSizePixel = 0
			bar.ZIndex = Z + 1
			bar.Parent = rays
			local grad = Instance.new("UIGradient")
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			grad.Parent = bar
			table.insert(bars, bar)
		end

		local figure = Instance.new("Frame")
		figure.AnchorPoint = Vector2.new(0.5, 0.5)
		figure.Position = UDim2.new(0.5, 0, 0, 110)
		figure.Size = UDim2.fromOffset(150, 150)
		figure.BackgroundTransparency = 1
		figure.ZIndex = Z + 3
		figure.Parent = root

		local function text(y: number, size: number, font: Enum.Font): TextLabel
			local t = Instance.new("TextLabel")
			t.AnchorPoint = Vector2.new(0.5, 0)
			t.Position = UDim2.new(0.5, 0, 0, y)
			t.Size = UDim2.new(1, 0, 0, size + 6)
			t.BackgroundTransparency = 1
			t.Font = font
			t.TextSize = size
			t.TextWrapped = true
			t.TextColor3 = UiKit.INK
			t.TextTransparency = 1
			t.TextStrokeTransparency = 1
			t.ZIndex = Z + 4
			t.Parent = root
			return t
		end

		return {
			root = root, rays = rays, bars = bars, figure = figure,
			name = text(205, 22, Enum.Font.GothamBlack),
			tier = text(238, 14, Enum.Font.GothamBold),
			stat = text(260, 12, Enum.Font.GothamMedium),
		}
	end

	for _ = 1, Config.TripleHatchCount do
		table.insert(slots, makeSlot())
	end

	local function fadeText(t: TextLabel, visible: boolean, seconds: number)
		tween(t, seconds, {
			TextTransparency = if visible then 0 else 1,
			TextStrokeTransparency = if visible then 0.4 else 1,
		})
	end

	-- ─── Tek bir gösterim ───────────────────────────────────────────────────

	local queue: { { keys: { string }, source: string } } = {}
	local playing = false
	local closeRequested = false

	local function play(keys: { string }, source: string)
		local count = math.min(#keys, #slots)
		closeRequested = false
		dismiss.Active = false
		layer.Visible = true

		-- Yuvaları yerleştir: tekse ortada büyük, üçlüde yan yana
		for i, slot in slots do
			local used = i <= count
			slot.root.Visible = used
			if used then
				local x = if count == 1 then 0.5 else (i - 0.5) / count
				slot.root.Position = UDim2.fromScale(x, 0.5)
				slot.root.Size = if count == 1 then UDim2.fromOffset(300, 360) else UDim2.fromOffset(230, 340)
				UiKit.ClearSlot(slot.figure)
				for _, bar in slot.bars do
					bar.BackgroundTransparency = 1
				end
				for _, t in { slot.name, slot.tier, slot.stat } do
					t.TextTransparency = 1
					t.TextStrokeTransparency = 1
				end
			end
		end

		tween(layer, 0.2, { BackgroundTransparency = 0.4 })
		headline.Text = if source == "fuse" then "FUSING..." else (if count > 1 then "HATCHING x" .. count .. "..." else "HATCHING...")
		headline.TextColor3 = UiKit.INK
		headline.TextTransparency = 0

		--[[
			Sallanan yumurtalar. Birleştirmede de yumurta: üç kopya "içine
			giriyor" ve bir tanesi çıkıyor — ayrı bir animasyona değmeyecek
			kadar aynı his.
		]]
		local eggs: { Frame } = {}
		for i = 1, count do
			local egg = UiKit.Egg(slots[i].figure, if count == 1 then 150 else 120, Color3.fromRGB(236, 228, 210))
			table.insert(eggs, egg)
		end
		for _, seconds in WOBBLE do
			for _, egg in eggs do
				tween(egg, seconds, { Rotation = -14 }, Enum.EasingStyle.Sine)
			end
			task.wait(seconds)
			for _, egg in eggs do
				tween(egg, seconds, { Rotation = 14 }, Enum.EasingStyle.Sine)
			end
			task.wait(seconds)
		end
		for _, egg in eggs do
			tween(egg, 0.08, { Rotation = 0 })
		end
		task.wait(0.08)

		-- Çatlama: beyaz parlama, yumurtalar gidiyor, petler geliyor
		flash.BackgroundTransparency = 0.05
		tween(flash, 0.4, { BackgroundTransparency = 1 })
		headline.Text = if source == "fuse" then "FUSED!" else "HATCHED!"

		local best = 0
		for i = 1, count do
			local slot = slots[i]
			local def, mutation, size = Config.ParsePetKey(keys[i])
			UiKit.ClearSlot(slot.figure)
			if not def then
				continue
			end
			local tone = tierColor(def.rarity)
			local order = Config.Rarities[def.rarity].order
			if order > best then
				best = order
				headline.TextColor3 = tone
			end

			--[[ Pet küçükten büyüyor; ölçekle, çünkü vizör piksel ölçüyle
			     kurulu ve gövde tek başına büyüseydi vizör taşardı. ]]
			local bodyColor = if mutation then mutation.tint else def.color
			UiKit.PetFigure(slot.figure, if count == 1 then 140 else 110, PetModel.FormOf(def.id), bodyColor)
			local grow = Instance.new("UIScale")
			grow.Scale = 0.15
			grow.Parent = slot.figure
			tween(grow, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

			for _, bar in slot.bars do
				bar.BackgroundColor3 = tone
				tween(bar, 0.35, { BackgroundTransparency = 0.1 })
			end

			slot.name.Text = Config.PetDisplayName(keys[i])
			slot.name.TextColor3 = bodyColor:Lerp(Color3.new(1, 1, 1), 0.2)
			slot.tier.Text = string.upper(def.rarity) .. (if size then "  ·  " .. string.upper(size.name) else "")
			slot.tier.TextColor3 = tone
			local income, speed = Config.GetPetKeyBonus(keys[i])
			slot.stat.Text = string.format("+%d%% cash  ·  +%.2f speed", math.floor(income * 100 + 0.5), speed)
			slot.stat.TextColor3 = UiKit.MUTED
			for _, t in { slot.name, slot.tier, slot.stat } do
				fadeText(t, true, 0.25)
			end
		end

		-- Işınlar dönüyor; tıklanana kadar ya da süre dolana kadar
		dismiss.Active = true
		local started = os.clock()
		while not closeRequested and os.clock() - started < REVEAL do
			for i = 1, count do
				slots[i].rays.Rotation += 0.6
			end
			task.wait()
		end

		for i = 1, count do
			local slot = slots[i]
			for _, t in { slot.name, slot.tier, slot.stat } do
				fadeText(t, false, 0.2)
			end
			for _, bar in slot.bars do
				tween(bar, 0.2, { BackgroundTransparency = 1 })
			end
		end
		headline.TextTransparency = 1
		tween(layer, 0.25, { BackgroundTransparency = 1 }).Completed:Wait()
		for i = 1, count do
			UiKit.ClearSlot(slots[i].figure)
		end
		layer.Visible = false
	end

	local function drain()
		if playing then
			return
		end
		playing = true
		while #queue > 0 do
			local item = table.remove(queue, 1)
			local ok, err = pcall(play, item.keys, item.source)
			if not ok then
				warn("[HatchFX] " .. tostring(err))
				layer.Visible = false
			end
		end
		playing = false
	end

	dismiss.MouseButton1Click:Connect(function()
		closeRequested = true
	end)

	local connection = Net.Get("PetHatched").OnClientEvent:Connect(function(keys, source, fromKey)
		-- Birleştirme makinede dünyada oynuyor (FuseFX); kart yalnızca makine yoksa
		if source == "fuse" and typeof(fromKey) == "string" and FuseFX.Available() then
			return
		end
		local list: { string } = {}
		if typeof(keys) == "string" then
			list = { keys }
		elseif typeof(keys) == "table" then
			for _, k in keys do
				if typeof(k) == "string" then
					table.insert(list, k)
				end
			end
		end
		if #list == 0 then
			return
		end
		table.insert(queue, { keys = list, source = if typeof(source) == "string" then source else "egg" })
		task.spawn(drain)
	end)

	return {
		IsPlaying = function(): boolean
			return playing
		end,
		Destroy = function()
			connection:Disconnect()
			layer:Destroy()
		end,
	}
end

return HatchFX
