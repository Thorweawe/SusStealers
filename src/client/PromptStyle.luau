--!strict
--[[
	Etkileşim pencereleri (ProximityPrompt) oyunun kendi tasarımıyla.

	Roblox'un varsayılan kutusu (gri yarı saydam kutu, düz yazı, köşede
	"E") oyunun geri kalanıyla uyumsuzdu. Burada bütün promptlar Custom
	stile alınıyor ve ProximityPromptService'in olaylarıyla kendi
	kartımızı çiziyoruz:

	  - Koyu yuvarlak kart, işin türüne göre renkli çerçeve ve şerit
	    (Steal kırmızı, Buy yeşil, Sell altın, Lock mavi, Upgrade/Rebirth
	    turuncu, Vent yeşil, diğerleri camgöbeği)
	  - Solda tuş rozeti: klavyede tuşun harfi, gamepad'de düğmesi,
	    dokunmatikte parmak simgesi
	  - Üstte küçük nesne yazısı (ObjectText), altında büyük eylem yazısı
	  - Basılı tutulan işlerde alt kenarda dolan ilerleme çubuğu
	  - Açılırken küçük bir "pop", tetiklenince beyaz parlama

	GİRİŞ: klavye/gamepad girişini ProximityPromptService yine kendisi
	işliyor (Custom stil yalnızca görünüşü değiştirir). Dokunmatik ve fare
	tıklaması için kartın üstünde görünmez bir düğme InputHoldBegin/End
	çağırıyor — varsayılan kutunun yaptığının aynısı.

	Yumurta promptları HARİÇ: onları EggPanel kendi panelinde gösteriyor
	(yumurtanın ekranı, E/R/T). Enabled süzmesi PromptFilter'da; burası
	yalnızca çizim.

	YAPIŞKAN KART (bant, "BuyPrompt"): bantta birkaç karakter kayarken en
	yakın olan sürekli değişiyor; Roblox her değişimde eskisini gizleyip
	yenisini gösteriyor. Her seferinde kart küçülüp yok oluyor, yenisi
	"pop" ile çıkıyordu — saniyede birkaç kez, satın alma tuşu titreyip
	takılıyor gibi görünüyordu. Artık aynı kart yeni karaktere kayıyor,
	yalnızca yazısı (fiyat) değişiyor; son karakter de uzaklaşınca kısa
	bir gecikmeyle kapanıyor.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PromptStyle = {}

export type Handle = {
	Destroy: () -> (),
}

local player = Players.LocalPlayer

local WHITE = Color3.new(1, 1, 1)
local OUTLINE = Color3.fromRGB(16, 18, 28)
local CARD = Color3.fromRGB(28, 32, 46)
local FONT = Enum.Font.FredokaOne

-- Prompt adı -> vurgu rengi
local TONES: { [string]: Color3 } = {
	StealPrompt = Color3.fromRGB(240, 60, 70),
	CatchPrompt = Color3.fromRGB(240, 60, 70),
	RoguePrompt = Color3.fromRGB(240, 60, 70),
	BuyPrompt = Color3.fromRGB(80, 220, 70),
	SellPrompt = Color3.fromRGB(255, 196, 40),
	LockPrompt = Color3.fromRGB(70, 150, 255),
	UpgradePrompt = Color3.fromRGB(255, 140, 40),
	RebirthPrompt = Color3.fromRGB(255, 140, 40),
	VentPrompt = Color3.fromRGB(90, 200, 90),
	SpinPrompt = Color3.fromRGB(230, 80, 190),
	FusePrompt = Color3.fromRGB(170, 110, 255),
	GearPrompt = Color3.fromRGB(255, 150, 50),
}
local DEFAULT_TONE = Color3.fromRGB(80, 210, 230)

-- Aynı kartı paylaşan (yeniden çizilmeyen) prompt adları
local STICKY: { [string]: boolean } = {
	BuyPrompt = true,
}
local STICKY_LINGER = 0.2

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, contextual: boolean?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

--[[ Yumurta kabuğunun promptu mu (EggPanel çiziyor). ]]
local function isEggPrompt(prompt: ProximityPrompt): boolean
	local parent = prompt.Parent
	return parent ~= nil and parent:GetAttribute("EggId") ~= nil
end

--[[ Tuş rozetinin yazısı: giriş türüne göre. ]]
local function keyLabel(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "👆"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		local name = prompt.GamepadKeyCode.Name
		return (string.gsub(name, "^Button", ""))
	end
	local key = prompt.KeyboardKeyCode
	local mapped = UserInputService:GetStringForKeyCode(key)
	if mapped and mapped ~= "" then
		return string.upper(mapped)
	end
	return key.Name
end

type Shown = {
	gui: BillboardGui,
	fill: Frame,
	bar: Frame,
	card: Frame,
	action: TextLabel,
	object: TextLabel?,
	key: TextLabel,
	target: { prompt: ProximityPrompt },  -- tıklama düğmesinin hedefi (kart başka prompta kayabilir)
	holdTween: Tween?,
	watch: { RBXScriptConnection },
}

function PromptStyle.Start(): Handle
	local connections: { RBXScriptConnection } = {}
	local shown: { [ProximityPrompt]: Shown } = {}

	-- Bütün promptlar Custom stile (yumurtalar EggPanel'de zaten Custom)
	local function adopt(d: Instance)
		if d:IsA("ProximityPrompt") and not isEggPrompt(d) and d.Style ~= Enum.ProximityPromptStyle.Custom then
			d.Style = Enum.ProximityPromptStyle.Custom
		end
	end
	for _, d in workspace:GetDescendants() do
		adopt(d)
	end
	table.insert(connections, workspace.DescendantAdded:Connect(adopt))

	-- Küçük ekranda kart da küçük (dokunmatik telefon)
	local function cardScale(): number
		local camera = workspace.CurrentCamera
		local short = if camera then math.min(camera.ViewportSize.X, camera.ViewportSize.Y) else 800
		return math.clamp(short / 800, 0.72, 1)
	end

	-- Yapışkan kart: gizlendikten sonra kısa süre bekliyor, başka bir
	-- bant promptu gösterilirse ona kayıyor
	local lingering: { s: Shown, name: string, token: number }? = nil
	local lingerToken = 0

	local function destroyCard(s: Shown)
		local gui = s.gui
		local scale = gui:FindFirstChildWhichIsA("UIScale", true)
		if scale then
			local t = TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 0.4 })
			t:Play()
			t.Completed:Once(function()
				gui:Destroy()
			end)
		else
			gui:Destroy()
		end
	end

	local function hide(prompt: ProximityPrompt)
		local s = shown[prompt]
		if not s then
			return
		end
		shown[prompt] = nil
		for _, c in s.watch do
			c:Disconnect()
		end
		if s.holdTween then
			s.holdTween:Cancel()
			s.holdTween = nil
		end
		if STICKY[prompt.Name] then
			if lingering then
				destroyCard(lingering.s)
			end
			lingerToken += 1
			local token = lingerToken
			lingering = { s = s, name = prompt.Name, token = token }
			task.delay(STICKY_LINGER, function()
				local l = lingering
				if l and l.token == token then
					lingering = nil
					destroyCard(l.s)
				end
			end)
			return
		end
		destroyCard(s)
	end

	-- Yazı değişirse (ör. çalma süresi ObjectText'te) kart da güncellensin
	local function watchPrompt(prompt: ProximityPrompt, s: Shown): { RBXScriptConnection }
		local watch = {
			prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
				s.action.Text = prompt.ActionText
			end),
		}
		local objectLabel = s.object
		if objectLabel then
			table.insert(watch, prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
				objectLabel.Text = prompt.ObjectText
			end))
		end
		return watch
	end

	--[[
		Yapışkan kartı yeni prompta kaydırır: yeniden çizim yok, yalnızca
		hedef ve yazılar. Yeni karakter olduğunu hafif bir tık belli ediyor.
	]]
	local function retarget(s: Shown, prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
		local adornee = prompt.Parent
		if adornee and (adornee:IsA("BasePart") or adornee:IsA("Attachment") or adornee:IsA("Model")) then
			s.gui.Adornee = adornee :: any
		end
		s.target.prompt = prompt
		s.action.Text = prompt.ActionText
		if s.object then
			s.object.Text = prompt.ObjectText
		end
		s.key.Text = keyLabel(prompt, inputType)
		s.fill.Size = UDim2.fromScale(0, 1)
		s.watch = watchPrompt(prompt, s)
		shown[prompt] = s
		local scale = s.gui:FindFirstChildWhichIsA("UIScale", true)
		if scale then
			local full = cardScale()
			scale.Scale = full * 1.06
			TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = full }):Play()
		end
	end

	local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
		if isEggPrompt(prompt) then
			return
		end
		if STICKY[prompt.Name] and not shown[prompt] then
			-- Aynı türden ekranda duran ya da yeni gizlenen kart varsa ona kay
			for other, s in shown do
				if other ~= prompt and other.Name == prompt.Name then
					shown[other] = nil
					for _, c in s.watch do
						c:Disconnect()
					end
					retarget(s, prompt, inputType)
					return
				end
			end
			local l = lingering
			if l and l.name == prompt.Name then
				lingering = nil
				retarget(l.s, prompt, inputType)
				return
			end
		end
		hide(prompt)
		local tone = TONES[prompt.Name] or DEFAULT_TONE
		local adornee = prompt.Parent
		if not (adornee and (adornee:IsA("BasePart") or adornee:IsA("Attachment") or adornee:IsA("Model"))) then
			return
		end

		local hasObject = prompt.ObjectText ~= ""
		local W, H = 270, if hasObject then 78 else 64

		local gui = Instance.new("BillboardGui")
		gui.Name = "Prompt_" .. prompt.Name
		gui.Adornee = adornee :: any
		-- Kart UIOffset kadar kayabiliyor (Lock/Rebirth üst üste binmesin): pay bırak
		gui.Size = UDim2.fromOffset(W + 20 + math.abs(prompt.UIOffset.X) * 2, H + 20 + math.abs(prompt.UIOffset.Y) * 2)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		gui.Active = true
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.StudsOffset = Vector3.new(0, 1.5, 0)
		gui.Parent = player:WaitForChild("PlayerGui")

		local root = Instance.new("Frame")
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.new(0.5, prompt.UIOffset.X, 0.5, prompt.UIOffset.Y)
		root.Size = UDim2.fromOffset(W, H)
		root.BackgroundTransparency = 1
		root.Parent = gui
		local scale = Instance.new("UIScale")
		scale.Scale = cardScale() * 0.5
		scale.Parent = root

		local card = Instance.new("Frame")
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = CARD
		card.BackgroundTransparency = 0.05
		card.ClipsDescendants = true
		card.Parent = root
		corner(card, 14)
		stroke(card, OUTLINE, 3)
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(CARD:Lerp(tone, 0.22), CARD)
		grad.Parent = card

		-- Sol kenarda renk şeridi
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 6, 1, 0)
		stripe.BackgroundColor3 = tone
		stripe.BorderSizePixel = 0
		stripe.Parent = card

		-- İnce iç çerçeve (vurgu renginde)
		local inner = Instance.new("Frame")
		inner.Position = UDim2.fromOffset(2, 2)
		inner.Size = UDim2.new(1, -4, 1, -4)
		inner.BackgroundTransparency = 1
		inner.Parent = card
		corner(inner, 12)
		local innerStroke = Instance.new("UIStroke")
		innerStroke.Color = tone
		innerStroke.Thickness = 1.5
		innerStroke.Transparency = 0.35
		innerStroke.Parent = inner

		-- Tuş rozeti
		local badge = Instance.new("Frame")
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 16, 0.5, 0)
		badge.Size = UDim2.fromOffset(46, 46)
		badge.BackgroundColor3 = WHITE
		badge.Parent = card
		corner(badge, if inputType == Enum.ProximityPromptInputType.Touch then 23 else 10)
		stroke(badge, OUTLINE, 3)
		local badgeShade = Instance.new("UIGradient")
		badgeShade.Rotation = 90
		badgeShade.Color = ColorSequence.new(WHITE, Color3.fromRGB(205, 212, 226))
		badgeShade.Parent = badge
		local key = Instance.new("TextLabel")
		key.Size = UDim2.fromScale(1, 1)
		key.BackgroundTransparency = 1
		key.Font = FONT
		key.TextScaled = true
		key.TextColor3 = OUTLINE
		key.Text = keyLabel(prompt, inputType)
		key.Parent = badge
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 7)
		pad.PaddingBottom = UDim.new(0, 7)
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.Parent = key

		-- Yazılar
		if hasObject then
			local object = Instance.new("TextLabel")
			object.Name = "Object"
			object.Position = UDim2.fromOffset(74, 9)
			object.Size = UDim2.new(1, -84, 0, 20)
			object.BackgroundTransparency = 1
			object.Font = Enum.Font.GothamBold
			object.TextSize = 16
			object.TextXAlignment = Enum.TextXAlignment.Left
			object.TextTruncate = Enum.TextTruncate.AtEnd
			object.TextColor3 = tone:Lerp(WHITE, 0.45)
			object.Text = prompt.ObjectText
			object.Parent = card
		end
		local action = Instance.new("TextLabel")
		action.Position = UDim2.fromOffset(74, if hasObject then 30 else 12)
		action.Size = UDim2.new(1, -84, 0, 34)
		action.BackgroundTransparency = 1
		action.Font = FONT
		action.TextSize = 30
		action.TextXAlignment = Enum.TextXAlignment.Left
		action.TextColor3 = WHITE
		action.Text = prompt.ActionText
		action.Parent = card
		local actionFit = Instance.new("UITextSizeConstraint")
		actionFit.MaxTextSize = 30
		actionFit.MinTextSize = 16
		actionFit.Parent = action
		action.TextScaled = true
		stroke(action, OUTLINE, 3, true)

		-- Basılı tutma çubuğu (yalnızca süresi olan işlerde)
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new(0, 6, 1, 0)
		bar.Size = UDim2.new(1, -6, 0, 6)
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BackgroundTransparency = 0.4
		bar.BorderSizePixel = 0
		bar.Visible = prompt.HoldDuration > 0
		bar.Parent = card
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = tone:Lerp(WHITE, 0.2)
		fill.BorderSizePixel = 0
		fill.Parent = bar

		-- Dokunma / tıklama: basılı tutma varsayılan kutudaki gibi. Hedef
		-- tablodan okunuyor: yapışkan kart başka prompta kayabiliyor.
		local target = { prompt = prompt }
		if prompt.ClickablePrompt then
			local hit = Instance.new("TextButton")
			hit.Size = UDim2.fromScale(1, 1)
			hit.BackgroundTransparency = 1
			hit.Text = ""
			hit.ZIndex = 10
			hit.Parent = root
			hit.InputBegan:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1)
					and input.UserInputState ~= Enum.UserInputState.Change then
					target.prompt:InputHoldBegin()
				end
			end)
			hit.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					target.prompt:InputHoldEnd()
				end
			end)
		end

		local record: Shown = {
			gui = gui,
			fill = fill,
			bar = bar,
			card = card,
			action = action,
			object = card:FindFirstChild("Object") :: TextLabel?,
			key = key,
			target = target,
			holdTween = nil,
			watch = {},
		}
		record.watch = watchPrompt(prompt, record)
		shown[prompt] = record
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = cardScale() }):Play()
	end

	table.insert(connections, ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, inputType)
		end
	end))
	table.insert(connections, ProximityPromptService.PromptHidden:Connect(hide))

	table.insert(connections, ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local s = shown[prompt]
		if not s then
			return
		end
		s.fill.Size = UDim2.fromScale(0, 1)
		local t = TweenService:Create(s.fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		s.holdTween = t
		t:Play()
	end))
	table.insert(connections, ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local s = shown[prompt]
		if not s then
			return
		end
		if s.holdTween then
			s.holdTween:Cancel()
			s.holdTween = nil
		end
		TweenService:Create(s.fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(0, 1) }):Play()
	end))
	table.insert(connections, ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local s = shown[prompt]
		if not s then
			return
		end
		-- Beyaz parlama: iş yapıldı
		local flash = Instance.new("Frame")
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = WHITE
		flash.BackgroundTransparency = 0.35
		flash.BorderSizePixel = 0
		flash.ZIndex = 5
		flash.Parent = s.card
		TweenService:Create(flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.delay(0.32, function()
			flash:Destroy()
		end)
	end))

	return {
		Destroy = function()
			for _, c in connections do
				c:Disconnect()
			end
			for prompt in shown do
				hide(prompt)
			end
			if lingering then
				destroyCard(lingering.s)
				lingering = nil
			end
		end,
	}
end

return PromptStyle
