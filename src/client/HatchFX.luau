--!strict
--[[
	Yumurta açılışı ve birleştirme animasyonu.

	NEDEN VAR: yumurtayı açınca yalnızca köşede bir bildirim çıkıyordu.
	Bu türün en önemli anı o — oyuncunun parasını şansa yatırdığı an.
	Bildirim satırı onu bir fatura gibi gösteriyordu.

	Akış: yumurta ekranın ortasında sallanıyor (üç kez, giderek hızlı),
	beyaz bir parlama ile çatlıyor, arkasında kademe renginde ışınlar
	dönerken pet beliriyor. Tıklayınca ya da birkaç saniye sonra kapanıyor.

	Sonucu sunucu belirliyor (PetHatched remote'u anahtarı gönderiyor);
	burası sadece gösteriyor. Animasyon sonucu değiştiremiyor, geciktirmiyor
	— pet zaten envanterde.

	Üst üste gelen açılışlar SIRAYA giriyor: hızlı hızlı basan oyuncu her
	sonucu ayrı görüyor, birbirinin üstüne binmiyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PetModel = require(Shared.PetModel)

local UiKit = require(script.Parent.UiKit)

local HatchFX = {}

export type Handle = {
	Destroy: () -> (),
}

local Z = 80

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = TweenService:Create(object, info, goal)
	t:Play()
	return t
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

	-- Tıklanınca kapanması için görünmez düğme; animasyon sırasında kapalı
	local dismiss = Instance.new("TextButton")
	dismiss.Size = UDim2.fromScale(1, 1)
	dismiss.BackgroundTransparency = 1
	dismiss.Text = ""
	dismiss.AutoButtonColor = false
	dismiss.Active = false
	dismiss.ZIndex = Z + 20
	dismiss.Parent = layer

	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.45)
	center.Size = UDim2.fromOffset(220, 220)
	center.BackgroundTransparency = 1
	center.ZIndex = Z + 1
	center.Parent = layer

	-- Işınlar: sonucu açarken arkada dönen kademe renginde çubuklar
	local rays = Instance.new("Frame")
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromOffset(420, 420)
	rays.BackgroundTransparency = 1
	rays.ZIndex = Z + 1
	rays.Parent = center

	local rayBars: { Frame } = {}
	for i = 0, 5 do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(1, 0, 0, 26)
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
		table.insert(rayBars, bar)
	end

	local figure = Instance.new("Frame")
	figure.AnchorPoint = Vector2.new(0.5, 0.5)
	figure.Position = UDim2.fromScale(0.5, 0.5)
	figure.Size = UDim2.fromOffset(160, 160)
	figure.BackgroundTransparency = 1
	figure.ZIndex = Z + 3
	figure.Parent = center

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = Z + 10
	flash.Parent = layer

	local function label(y: number, size: number, font: Enum.Font): TextLabel
		local text = Instance.new("TextLabel")
		text.AnchorPoint = Vector2.new(0.5, 0)
		text.Position = UDim2.new(0.5, 0, 0.45, y)
		text.Size = UDim2.fromOffset(600, size + 6)
		text.BackgroundTransparency = 1
		text.Font = font
		text.TextSize = size
		text.TextColor3 = UiKit.INK
		text.TextTransparency = 1
		text.TextStrokeTransparency = 1
		text.Text = ""
		text.ZIndex = Z + 4
		text.Parent = layer
		return text
	end

	local headline = label(-170, 20, Enum.Font.GothamBlack)
	local nameLabel = label(120, 30, Enum.Font.GothamBlack)
	local tierLabel = label(156, 16, Enum.Font.GothamBold)
	local statLabel = label(180, 14, Enum.Font.GothamMedium)

	local function setText(text: TextLabel, value: string, color: Color3?)
		text.Text = value
		text.TextColor3 = color or UiKit.INK
	end

	local function fadeText(text: TextLabel, visible: boolean, seconds: number)
		tween(text, seconds, {
			TextTransparency = if visible then 0 else 1,
			TextStrokeTransparency = if visible then 0.4 else 1,
		})
	end

	-- ─── Tek bir gösterim ───────────────────────────────────────────────────

	local queue: { { key: string, source: string } } = {}
	local playing = false
	local closeRequested = false

	local function play(key: string, source: string)
		local def, mutation = Config.ParsePetKey(key)
		if not def then
			return
		end
		local rarity = Config.Rarities[def.rarity]
		local tone = rarity.color
		local bodyColor = if mutation then mutation.tint else def.color

		closeRequested = false
		dismiss.Active = false
		layer.Visible = true
		UiKit.ClearSlot(figure)
		for _, bar in rayBars do
			bar.BackgroundTransparency = 1
		end
		for _, text in { headline, nameLabel, tierLabel, statLabel } do
			text.TextTransparency = 1
			text.TextStrokeTransparency = 1
		end

		tween(layer, 0.25, { BackgroundTransparency = 0.4 })
		setText(headline, if source == "fuse" then "FUSING..." else "HATCHING...", UiKit.INK)
		fadeText(headline, true, 0.25)

		--[[
			Sallanan yumurta. Birleştirmede de yumurta: üç kopya "içine
			giriyor" ve bir tanesi çıkıyor — ayrı bir animasyon yazmaya
			değmeyecek kadar aynı his.
		]]
		local egg = UiKit.Egg(figure, 150, Color3.fromRGB(236, 228, 210))
		egg.Rotation = 0

		local wobbles = { 0.22, 0.16, 0.11 }
		for _, seconds in wobbles do
			tween(egg, seconds, { Rotation = -14 }, Enum.EasingStyle.Sine).Completed:Wait()
			tween(egg, seconds, { Rotation = 14 }, Enum.EasingStyle.Sine).Completed:Wait()
		end
		tween(egg, 0.08, { Rotation = 0 }).Completed:Wait()

		-- Çatlama: beyaz parlama, yumurta gidiyor, pet geliyor
		flash.BackgroundTransparency = 0.05
		tween(flash, 0.45, { BackgroundTransparency = 1 })
		UiKit.ClearSlot(figure)

		--[[
			Pet küçükten büyüyor. Gövdenin Size'ını değil ölçeği tweenliyoruz:
			vizör ve çanta piksel ölçüsüyle kurulu, gövde tek başına
			büyüseydi ilk karelerde vizör gövdeden taşardı.
		]]
		UiKit.PetFigure(figure, 130, PetModel.FormOf(def.id), bodyColor)
		local grow = Instance.new("UIScale")
		grow.Scale = 0.15
		grow.Parent = figure
		tween(grow, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

		for _, bar in rayBars do
			bar.BackgroundColor3 = tone
			tween(bar, 0.4, { BackgroundTransparency = 0.1 })
		end

		setText(headline, if source == "fuse" then "FUSED!" else "HATCHED!", tone)
		setText(nameLabel, (if mutation then mutation.name .. " " else "") .. def.name, bodyColor)
		setText(tierLabel, string.upper(def.rarity), tone)

		local income, speed = Config.GetPetKeyBonus(key)
		setText(statLabel, string.format("+%d%% cash   ·   +%.2f steal speed", math.floor(income * 100 + 0.5), speed), UiKit.MUTED)
		for _, text in { nameLabel, tierLabel, statLabel } do
			fadeText(text, true, 0.3)
		end

		-- Işınlar dönüyor; kapanana kadar ya da 3 saniye
		dismiss.Active = true
		local started = os.clock()
		while not closeRequested and os.clock() - started < 3 do
			rays.Rotation += 0.6
			task.wait()
		end

		for _, text in { headline, nameLabel, tierLabel, statLabel } do
			fadeText(text, false, 0.2)
		end
		for _, bar in rayBars do
			tween(bar, 0.2, { BackgroundTransparency = 1 })
		end
		tween(layer, 0.25, { BackgroundTransparency = 1 }).Completed:Wait()
		UiKit.ClearSlot(figure)
		layer.Visible = false
	end

	local function drain()
		if playing then
			return
		end
		playing = true
		while #queue > 0 do
			local item = table.remove(queue, 1)
			local ok, err = pcall(play, item.key, item.source)
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

	local connection = Net.Get("PetHatched").OnClientEvent:Connect(function(key, source)
		if typeof(key) ~= "string" then
			return
		end
		table.insert(queue, { key = key, source = if typeof(source) == "string" then source else "egg" })
		task.spawn(drain)
	end)

	return {
		Destroy = function()
			connection:Disconnect()
			layer:Destroy()
		end,
	}
end

return HatchFX
