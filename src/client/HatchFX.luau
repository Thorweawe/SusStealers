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
local EggStyle = require(script.Parent.EggStyle)
local SoundFX = require(script.Parent.SoundFX)

local HatchFX = {}

export type Handle = {
	IsPlaying: () -> boolean,
	Destroy: () -> (),
}

local Z = 80

-- Süre dağılımı (toplam ≈ Config.HatchDuration)
-- Sallanma giderek hızlanıyor: gerilim tırmansın
local WOBBLE = { 0.22, 0.17, 0.13, 0.1, 0.075, 0.06 }   -- her sallanma iki yön
local BUILDUP = 1.55                                     -- çatlamaya kadar (≈ sallanma toplamı)
local REVEAL = Config.HatchDuration - BUILDUP - 0.25

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

	--[[
		Üst şerit (Roblox'un üst çubuğunun hizası) karartmanın dışında
		kalıyordu: arayüz o bandın ALTINDAN başlıyor, katman oraya
		uzanmıyordu. Katmanın üstüne yukarı taşan bir örtü; rengi ve
		saydamlığı katmanla birlikte değişiyor (bütün tween'ler katmana).
	]]
	local topVeil = Instance.new("Frame")
	topVeil.Name = "TopVeil"
	topVeil.AnchorPoint = Vector2.new(0, 1)
	topVeil.Position = UDim2.fromScale(0, 0)
	topVeil.Size = UDim2.new(1, 0, 0, 400)
	topVeil.BackgroundColor3 = layer.BackgroundColor3
	topVeil.BackgroundTransparency = 1
	topVeil.BorderSizePixel = 0
	topVeil.ZIndex = Z
	topVeil.Parent = layer
	layer:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		topVeil.BackgroundTransparency = layer.BackgroundTransparency
	end)
	layer:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		topVeil.BackgroundColor3 = layer.BackgroundColor3
	end)

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
	headline.Position = UDim2.new(0.5, 0, 0.14, 0)
	headline.Size = UDim2.fromOffset(700, 54)
	headline.BackgroundTransparency = 1
	headline.Font = Enum.Font.FredokaOne
	headline.TextSize = 46
	headline.TextColor3 = UiKit.INK
	headline.ZIndex = Z + 4
	headline.Parent = layer
	-- Kalın kontur (TextStroke 1 piksel kalıyordu)
	local headStroke = Instance.new("UIStroke")
	headStroke.Color = Color3.fromRGB(16, 18, 28)
	headStroke.Thickness = 4
	headStroke.LineJoinMode = Enum.LineJoinMode.Round
	headStroke.Parent = headline

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

		local function text(y: number, size: number, font: Enum.Font, outline: number): TextLabel
			local t = Instance.new("TextLabel")
			t.AnchorPoint = Vector2.new(0.5, 0)
			t.Position = UDim2.new(0.5, 0, 0, y)
			t.Size = UDim2.new(1, 0, 0, size + 8)
			t.BackgroundTransparency = 1
			t.Font = font
			t.TextSize = size
			t.TextWrapped = true
			t.TextColor3 = UiKit.INK
			t.TextTransparency = 1
			t.TextStrokeTransparency = 1
			t.ZIndex = Z + 4
			t.Parent = root
			-- Kalın kontur: ışınların ve karanlığın üstünde okunsun
			local s = Instance.new("UIStroke")
			s.Color = Color3.fromRGB(16, 18, 28)
			s.Thickness = outline
			s.LineJoinMode = Enum.LineJoinMode.Round
			s.Transparency = 1
			s.Parent = t
			return t
		end

		local tier = text(248, 18, Enum.Font.FredokaOne, 3)
		tier.Name = "Tier"
		-- Kademe etiketi hap şeklinde: rengi kademenin rengi
		tier.AutomaticSize = Enum.AutomaticSize.X
		tier.Size = UDim2.fromOffset(0, 28)
		tier.BackgroundTransparency = 1
		UiKit.Corner(tier, 14)
		local tierPad = Instance.new("UIPadding")
		tierPad.PaddingLeft = UDim.new(0, 14)
		tierPad.PaddingRight = UDim.new(0, 14)
		tierPad.Parent = tier

		return {
			root = root, rays = rays, bars = bars, figure = figure,
			name = text(206, 34, Enum.Font.FredokaOne, 4),
			tier = tier,
			stat = text(284, 17, Enum.Font.GothamBold, 2.5),
		}
	end

	for _ = 1, Config.TripleHatchCount do
		table.insert(slots, makeSlot())
	end

	local function fadeText(t: TextLabel, visible: boolean, seconds: number)
		tween(t, seconds, { TextTransparency = if visible then 0 else 1 })
		local s = t:FindFirstChildOfClass("UIStroke")
		if s then
			tween(s, seconds, { Transparency = if visible then 0 else 1 })
		end
		-- Kademe hapının zemini de yazıyla birlikte
		if t.Name == "Tier" then
			tween(t, seconds, { BackgroundTransparency = if visible then 0.1 else 1 })
		end
	end

	-- ─── Tek bir gösterim ───────────────────────────────────────────────────

	local queue: { { keys: { string }, source: string, eggId: string?, deleted: { boolean }? } } = {}
	local playing = false
	local closeRequested = false

	--[[
		Açılışta yumurtadan saçılan parçalar: yumurtanın kendi malzemesi
		(karton, cıvata, kar, yıldız). Çatlama anında bir kez.
	]]
	local rng = Random.new()
	local function burst(slot: Slot, style: EggStyle.Style)
		for _ = 1, 14 do
			local bit = Instance.new("Frame")
			bit.AnchorPoint = Vector2.new(0.5, 0.5)
			bit.Position = slot.figure.Position
			bit.BorderSizePixel = 0
			bit.ZIndex = Z + 5
			local kind = style.bits
			if kind == "cardboard" then
				bit.Size = UDim2.fromOffset(rng:NextInteger(10, 18), rng:NextInteger(7, 12))
				bit.BackgroundColor3 = if rng:NextNumber() < 0.3 then style.accent else style.shell
			elseif kind == "bolts" then
				bit.Size = UDim2.fromOffset(8, rng:NextInteger(8, 14))
				bit.BackgroundColor3 = if rng:NextNumber() < 0.4 then style.accent else Color3.fromRGB(150, 164, 176)
				UiKit.Corner(bit, 3)
			elseif kind == "snow" then
				local d = rng:NextInteger(6, 11)
				bit.Size = UDim2.fromOffset(d, d)
				bit.BackgroundColor3 = if rng:NextNumber() < 0.5 then style.accent else style.glow
				UiKit.Corner(bit, d)
			else
				local d = rng:NextInteger(8, 13)
				bit.Size = UDim2.fromOffset(d, d)
				bit.Rotation = 45
				bit.BackgroundColor3 = if rng:NextNumber() < 0.5 then style.accent else style.glow
			end
			bit.Parent = slot.root

			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = rng:NextNumber(90, 160)
			local target = UDim2.new(0.5, math.cos(angle) * dist, 0, 110 + math.sin(angle) * dist)
			tween(bit, 0.7, {
				Position = target,
				Rotation = bit.Rotation + rng:NextNumber(-220, 220),
				BackgroundTransparency = 1,
			})
			task.delay(0.75, function()
				bit:Destroy()
			end)
		end
	end

	--[[
		Çatlama öncesi hareket, yumurtanın stiline göre. Hepsi ~0.72 sn:
		toplam süre Config.HatchDuration'a bağlı (üstteki SÜRE notu).
	]]
	local function crack(eggs: { Frame }, style: EggStyle.Style)
		if style.crack == "spin" then
			-- Giderek hızlanan dönüş: kapsül fırlatılmaya hazırlanıyor
			for _, step in { { 0.3, 360 }, { 0.24, 900 }, { 0.18, 1440 } } do
				for _, egg in eggs do
					tween(egg, step[1], { Rotation = step[2] }, Enum.EasingStyle.Linear)
				end
				task.wait(step[1])
			end
		elseif style.crack == "freeze" then
			-- Buz kaplıyor, yumurta soğuktan titriyor
			for _, egg in eggs do
				local frost = UiKit.Shape(egg, 0.5, 0.53, 0.8, 0.94, style.glow, 6, 0.5)
				frost.BackgroundTransparency = 1
				tween(frost, 0.5, { BackgroundTransparency = 0.35 })
			end
			for k = 1, 8 do
				for _, egg in eggs do
					tween(egg, 0.06, { Rotation = if k % 2 == 0 then 5 else -5 }, Enum.EasingStyle.Linear)
				end
				task.wait(0.06)
			end
			task.wait(0.24)
		elseif style.crack == "implode" then
			-- Nefes alıp içine çöküyor, ekran kararıyor
			tween(layer, 0.6, { BackgroundTransparency = 0.12 })
			local scales: { UIScale } = {}
			for _, egg in eggs do
				local sc = Instance.new("UIScale")
				sc.Parent = egg
				table.insert(scales, sc)
			end
			for _, step in { { 0.2, 1.18 }, { 0.14, 0.9 }, { 0.16, 1.3 }, { 0.2, 0.12 } } do
				for _, sc in scales do
					tween(sc, step[1], { Scale = step[2] }, Enum.EasingStyle.Sine)
				end
				task.wait(step[1])
			end
		else
			-- Sarsıntı: iki yana sallanıp zıplıyor (koli); giderek hızlanıp büyüyor
			local scales: { UIScale } = {}
			for _, egg in eggs do
				local sc = Instance.new("UIScale")
				sc.Parent = egg
				table.insert(scales, sc)
				tween(sc, BUILDUP, { Scale = 1.18 }, Enum.EasingStyle.Quad)
			end
			for k, seconds in WOBBLE do
				local swing = 10 + k * 2.5
				for _, egg in eggs do
					tween(egg, seconds, { Rotation = -swing, Position = UDim2.new(0.5, 0, 0.5, -6 - k) }, Enum.EasingStyle.Sine)
				end
				task.wait(seconds)
				for _, egg in eggs do
					tween(egg, seconds, { Rotation = swing, Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Sine)
				end
				task.wait(seconds)
			end
		end
		for _, egg in eggs do
			-- Tam turları at: 1440°'den 0'a dönerken geri geri dört tur atmasın
			egg.Rotation = ((egg.Rotation + 180) % 360) - 180
			tween(egg, 0.08, { Rotation = 0, Position = UDim2.fromScale(0.5, 0.5) })
		end
		task.wait(0.08)
	end

	local stamps: { GuiObject } = {}

	local function play(keys: { string }, source: string, eggId: string?, deleted: { boolean }?)
		local count = math.min(#keys, #slots)
		-- Birleştirmede yumurta yok; nötr stil
		local style = EggStyle.Get(if source == "fuse" then nil else eggId)
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
					local s = t:FindFirstChildOfClass("UIStroke")
					if s then
						s.Transparency = 1
					end
				end
				slot.tier.BackgroundTransparency = 1
			end
		end

		layer.BackgroundColor3 = style.backdrop
		tween(layer, 0.2, { BackgroundTransparency = 0.4 })
		headline.Text = if source == "fuse" then "FUSING..."
			else style.title .. (if count > 1 then " x" .. count else "") .. "..."
		headline.TextColor3 = UiKit.INK
		headline.TextTransparency = 0

		--[[
			Sallanan yumurtalar. Birleştirmede de yumurta: üç kopya "içine
			giriyor" ve bir tanesi çıkıyor — ayrı bir animasyona değmeyecek
			kadar aynı his.
		]]
		local eggs: { Frame } = {}
		for i = 1, count do
			local egg = EggStyle.Draw(slots[i].figure, if count == 1 then 170 else 130,
				if source == "fuse" then nil else eggId)
			table.insert(eggs, egg)
		end
		SoundFX.HatchShake(BUILDUP)
		local crackStarted = os.clock()
		--[[
			Dönen / donan / çöken stillerin kendi hareketi ~0.72 sn; açılış
			uzayınca önce hafif bir titreme, sonra stilin hareketi — yumurta
			boşta beklemesin.
		]]
		if style.crack == "spin" or style.crack == "freeze" or style.crack == "implode" then
			local pre = os.clock()
			local k = 0
			while os.clock() - pre < BUILDUP - 0.78 do
				k += 1
				for _, egg in eggs do
					tween(egg, 0.07, { Rotation = if k % 2 == 0 then 6 + k * 0.3 else -6 - k * 0.3 }, Enum.EasingStyle.Sine)
				end
				task.wait(0.07)
			end
		end
		crack(eggs, style)
		-- Stil animasyonları farklı sürüyor; çatlama hep aynı anda gelsin
		local left = BUILDUP - (os.clock() - crackStarted)
		if left > 0 then
			task.wait(left)
		end
		SoundFX.HatchCrack()

		-- Çatlama: yumurtanın renginde parlama, parçalar saçılıyor, petler geliyor
		flash.BackgroundColor3 = style.glow:Lerp(Color3.new(1, 1, 1), 0.55)
		flash.BackgroundTransparency = 0.05
		tween(flash, 0.4, { BackgroundTransparency = 1 })
		tween(layer, 0.3, { BackgroundTransparency = 0.4 })
		for i = 1, count do
			burst(slots[i], style)
		end
		headline.Text = if source == "fuse" then "FUSED!" else "YOU HATCHED..."

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
			UiKit.PetIcon(slot.figure, if count == 1 then 140 else 110, keys[i])
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
			slot.tier.TextColor3 = Color3.new(1, 1, 1)
			slot.tier.BackgroundColor3 = tone:Lerp(Color3.new(0, 0, 0), 0.15)
			local income, speed = Config.GetPetKeyBonus(keys[i])
			slot.stat.Text = string.format("+%d%% cash  ·  +%.2f speed", math.floor(income * 100 + 0.5), speed)
			slot.stat.TextColor3 = Color3.fromRGB(200, 255, 190)
			for _, t in { slot.name, slot.tier, slot.stat } do
				fadeText(t, true, 0.25)
			end

			--[[
				Otomatik silindi: pet yine gösteriliyor (ne çıktığını bilmek
				istiyor) ama üstünde kırmızı çapraz damga, ışınlar sönük.
			]]
			if deleted and deleted[i] then
				local stamp = Instance.new("TextLabel")
				stamp.Name = "DeletedStamp"
				stamp.AnchorPoint = Vector2.new(0.5, 0.5)
				stamp.Position = UDim2.new(0.5, 0, 0, 110)
				stamp.Size = UDim2.fromOffset(190, 46)
				stamp.Rotation = -14
				stamp.BackgroundColor3 = Color3.fromRGB(30, 10, 12)
				stamp.BackgroundTransparency = 0.25
				stamp.Font = Enum.Font.FredokaOne
				stamp.TextSize = 30
				stamp.TextColor3 = Color3.fromRGB(255, 80, 80)
				stamp.Text = "DELETED"
				stamp.ZIndex = Z + 6
				stamp.Parent = slot.root
				UiKit.Corner(stamp, 8)
				UiKit.Stroke(stamp, Color3.fromRGB(255, 80, 80), 3, 0)
				table.insert(stamps, stamp)
				slot.stat.Text = "Auto-deleted (still added to your Pet Index)"
				for _, bar in slot.bars do
					bar.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
				end
			end
		end

		if source ~= "fuse" then
			SoundFX.HatchReveal(best)
			-- En iyi çıkışa göre başlık: nadir çıkış kendini belli etsin
			local bestName = ""
			for name, info in Config.Rarities do
				if info.order == best then
					bestName = name
				end
			end
			headline.Text = if best >= 5 then "WOW! " .. string.upper(bestName) .. "!"
				elseif count > 1 then "YOU HATCHED " .. count .. " PETS!"
				else "YOU HATCHED A PET!"
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
		for _, stamp in stamps do
			stamp:Destroy()
		end
		table.clear(stamps)
		layer.Visible = false
	end

	local function drain()
		if playing then
			return
		end
		playing = true
		while #queue > 0 do
			local item = table.remove(queue, 1)
			local ok, err = pcall(play, item.keys, item.source, item.eggId, item.deleted)
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

	local connection = Net.Get("PetHatched").OnClientEvent:Connect(function(keys, source, fromKey, deletedRaw)
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
		-- Yumurta açılışında üçüncü argüman yumurtanın kimliği (stil için)
		-- Dördüncü argüman: otomatik silinen sonuçlar (PetService.TryHatch, AUTO-DELETE)
		local deleted: { boolean } = {}
		if typeof(deletedRaw) == "table" then
			for i = 1, #list do
				deleted[i] = deletedRaw[i] == true
			end
		end
		table.insert(queue, {
			keys = list,
			source = if typeof(source) == "string" then source else "egg",
			eggId = if source ~= "fuse" and typeof(fromKey) == "string" then fromKey else nil,
			deleted = deleted,
		})
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
