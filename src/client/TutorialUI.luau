--!strict
--[[
	Öğretici: sıradaki adımı ve hedefi gösterir — oyuncuyu İÇİNE ÇEKEREK.

	Sunucu (TutorialService) hangi adımda olduğumuzu "Tutorial" remote'uyla
	gönderiyor; burada sadece çiziliyor. Karar sunucuda, görüntü burada —
	istemci ilerlemeyi değiştiremiyor.

	Remote iki şey yolluyor:
		payload : { active, index, total, id, title, text, hint, reward,
		            value, goal }
		target  : ilerlenecek nesne (Instance?) — bulunamadıysa nil

	═══ NEDEN YENİDEN ══════════════════════════════════════════════════════

	Eski hâli köşede küçük, sade bir yazı kutusuydu ("çok sade, oyuncuyu
	içine çekmiyor"). Oyuncu okumuyor, adım bittiğinde de hiçbir şey
	olmuyordu. Şimdi:

	  - REHBER: kartın köşesinde Kaptan (gerçek 3B mürettebat) konuşuyor;
	    yazı daktilo gibi akıyor, Kaptan her yeni cümlede zıplıyor.
	  - ADIM AFİŞİ: yeni adım ekranın ortasında büyük bir afişle başlıyor
	    ("STEP 2 · FILL ANOTHER PODIUM", ödülüyle), sonra köşeye iniyor.
	  - KUTLAMA: adım bitince konfeti ve "STEP COMPLETE! +$1.5K".
	    Öğretici bitince büyük final ve toplam ödül.
	  - YOL: oyuncunun ayağından hedefe parlayan bir ışık hattı (Beam),
	    hedefin üstünde zıplayan ok, uzaksa ekranda yön oku ve mesafe.
	  - KART: mağaza dilinde (CardKit) ışınlı, adım noktaları, kalın
	    ilerleme çubuğu, ödül rozeti.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CardKit = require(script.Parent.CardKit)
local UiKit = require(script.Parent.UiKit)

local TutorialUI = {}

local player = Players.LocalPlayer

local WHITE = CardKit.WHITE
local ACCENT = Color3.fromRGB(255, 190, 60)
local CARD_TINT = Color3.fromRGB(60, 110, 220)
local GOOD = Color3.fromRGB(124, 255, 91)
local Z = 20

export type Panel = {
	Destroy: () -> (),
}

type Payload = {
	active: boolean,
	index: number?,
	total: number?,
	id: string?,
	title: string?,
	text: string?,
	hint: string?,
	reward: number?,
	value: number?,
	goal: number?,
}

--[[
	Kameranın baktığı yön ile hedefin yönü arasındaki işaretli açı.
	0 = tam karşıda, +90 = sağda, -90 = solda. CarryGuide ile aynı hesap.
]]
local function bearingTo(target: Vector3, from: Vector3): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end
	local delta = target - from
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 0.01 then
		return 0
	end
	local look = camera.CFrame.LookVector
	local camFlat = Vector3.new(look.X, 0, look.Z)
	if camFlat.Magnitude < 0.001 then
		camFlat = Vector3.new(0, 0, -1)
	end
	local dir = flat.Unit
	camFlat = camFlat.Unit
	-- GUI'de pozitif dönüş saat yönünde, o yüzden sonucu ters çeviriyoruz
	return -math.deg(math.atan2(camFlat:Cross(dir).Y, camFlat:Dot(dir)))
end

--[[ Nesnenin dünya konumu. Model de parça da olabiliyor. ]]
local function positionOf(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	elseif target:IsA("Model") then
		local ok, pivot = pcall(function()
			return target:GetPivot()
		end)
		if ok then
			return pivot.Position
		end
	end
	return nil
end

function TutorialUI.Create(screen: ScreenGui): Panel
	--[[
		Alt sol, nakit haplarının SAĞINDA: 22 kenar + 232 hap + 12 ara.
		Nakitle üst üste binmesin — öğretici tam da oyuncunun parasına
		bakması gereken anda parayı kapatıyordu.
	]]
	local W, H = 400, 172
	local frame = Instance.new("Frame")
	frame.Name = "Tutorial"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 266, 1, -22)
	frame.Size = UDim2.fromOffset(W, H)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.ZIndex = Z
	frame.Parent = screen
	local frameScale = Instance.new("UIScale")
	frameScale.Parent = frame

	local card = CardKit.card(frame, CARD_TINT, UDim2.new(1, 0, 1, -14), Z, UDim2.fromScale(0.15, 0.4), 360)
	card.Position = UDim2.fromOffset(0, 14)

	-- ── Rehber: Kaptan ────────────────────────────────────────────────────
	local guide = CardKit.badge(frame, 92, ACCENT, Z + 4)
	guide.Position = UDim2.fromOffset(-14, -10)
	local guideSlot = guide:FindFirstChild("Slot") :: Frame
	guideSlot.Size = UDim2.fromOffset(92, 92)
	UiKit.UnitIcon(guideSlot, 104, "Sheriff")
	local guideBob = Instance.new("UIScale")
	guideBob.Parent = guide
	local guideName = CardKit.bold(frame, "CAPTAIN", 15, CardKit.YELLOW, Z + 6, 2.5)
	guideName.Position = UDim2.fromOffset(-14, 76)
	guideName.Size = UDim2.fromOffset(92, 18)

	local counter = CardKit.bold(card, "", 15, Color3.fromRGB(220, 230, 255), Z + 5, 2)
	counter.TextXAlignment = Enum.TextXAlignment.Left
	counter.Position = UDim2.fromOffset(92, 8)
	counter.Size = UDim2.new(1, -170, 0, 18)

	-- Adım noktaları: yolun neresindeyiz
	local dots = Instance.new("Frame")
	dots.AnchorPoint = Vector2.new(1, 0)
	dots.Position = UDim2.new(1, -12, 0, 10)
	dots.Size = UDim2.fromOffset(110, 14)
	dots.BackgroundTransparency = 1
	dots.ZIndex = Z + 5
	dots.Parent = card
	local dotLayout = Instance.new("UIListLayout")
	dotLayout.FillDirection = Enum.FillDirection.Horizontal
	dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	dotLayout.Padding = UDim.new(0, 5)
	dotLayout.Parent = dots
	local dotFrames: { Frame } = {}
	for i = 1, #Config.Tutorial do
		local d = Instance.new("Frame")
		d.LayoutOrder = i
		d.Size = UDim2.fromOffset(13, 13)
		d.BorderSizePixel = 0
		d.ZIndex = Z + 5
		d.Parent = dots
		CardKit.corner(d, 7)
		CardKit.border(d, CardKit.OUTLINE, 2)
		table.insert(dotFrames, d)
	end

	local title = CardKit.bold(card, "", 26, CardKit.YELLOW, Z + 5, 3.5)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(92, 26)
	title.Size = UDim2.new(1, -104, 0, 30)
	CardKit.fit(title, 26, 14)

	-- Kaptanın sözü (daktilo)
	local body = CardKit.bold(card, "", 17, WHITE, Z + 5, 2)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Position = UDim2.fromOffset(92, 58)
	body.Size = UDim2.new(1, -104, 0, 46)

	local bar = CardKit.bar(card, UDim2.new(1, -206, 0, 20), GOOD, Z + 5, 13)
	bar.frame.Position = UDim2.new(0, 92, 1, -32)

	local rewardChip = CardKit.bold(card, "", 18, WHITE, Z + 6, 2.5)
	rewardChip.AnchorPoint = Vector2.new(1, 1)
	rewardChip.Position = UDim2.new(1, -12, 1, -10)
	rewardChip.Size = UDim2.fromOffset(104, 26)
	rewardChip.BackgroundTransparency = 0
	rewardChip.BackgroundColor3 = Color3.fromRGB(50, 170, 50)
	CardKit.corner(rewardChip, 8)
	CardKit.border(rewardChip, CardKit.OUTLINE, 2.5)
	CardKit.fit(rewardChip, 18, 10)

	-- Atlama: oyunu bilen oyuncu için; küçük ve kartın dışında (yanlışlıkla basılmasın)
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -6, 0, 12)
	skip.Size = UDim2.fromOffset(110, 18)
	skip.BackgroundTransparency = 1
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 13
	skip.TextColor3 = Color3.fromRGB(190, 198, 214)
	skip.TextStrokeTransparency = 0.4
	skip.TextXAlignment = Enum.TextXAlignment.Right
	skip.Text = "skip tutorial »"
	skip.AutoButtonColor = false
	skip.ZIndex = Z + 6
	skip.Parent = frame
	skip.MouseEnter:Connect(function()
		skip.TextColor3 = WHITE
	end)
	skip.MouseLeave:Connect(function()
		skip.TextColor3 = Color3.fromRGB(190, 198, 214)
	end)

	local skipped = false
	local skipRemote = Net.Get("TutorialSkip")
	skip.Activated:Connect(function()
		skipped = true
		skip.Text = "..."
		skipRemote:FireServer()
	end)

	-- ── Ekranın ortasındaki afiş (adım başı / adım sonu / final) ───────────
	local stage = Instance.new("Frame")
	stage.Name = "TutorialStage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.36)
	stage.Size = UDim2.fromOffset(560, 150)
	stage.BackgroundTransparency = 1
	stage.Visible = false
	stage.ZIndex = Z + 20
	stage.Parent = screen
	local stageScale = Instance.new("UIScale")
	stageScale.Parent = stage
	local stageCard = CardKit.card(stage, CARD_TINT, UDim2.fromScale(1, 1), Z + 20, UDim2.fromScale(0.5, 0.5), 700)
	local stageTop = CardKit.bold(stageCard, "", 24, WHITE, Z + 24, 3)
	stageTop.Position = UDim2.fromOffset(0, 12)
	stageTop.Size = UDim2.new(1, 0, 0, 28)
	local stageMain = CardKit.bold(stageCard, "", 48, CardKit.YELLOW, Z + 24, 5)
	stageMain.Position = UDim2.fromOffset(16, 42)
	stageMain.Size = UDim2.new(1, -32, 0, 56)
	CardKit.fit(stageMain, 48, 20)
	local stageSub = CardKit.bold(stageCard, "", 26, GOOD, Z + 24, 3)
	stageSub.Position = UDim2.fromOffset(0, 102)
	stageSub.Size = UDim2.new(1, 0, 0, 32)

	local confettiLayer = Instance.new("Frame")
	confettiLayer.Name = "TutorialConfetti"
	confettiLayer.Size = UDim2.fromScale(1, 1)
	confettiLayer.BackgroundTransparency = 1
	confettiLayer.ZIndex = Z + 30
	confettiLayer.Parent = screen

	local CONFETTI = {
		Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 210, 60), Color3.fromRGB(90, 220, 90),
		Color3.fromRGB(80, 170, 255), Color3.fromRGB(200, 110, 255), Color3.fromRGB(255, 150, 200),
	}
	local function confetti(count: number)
		for i = 1, count do
			local piece = Instance.new("Frame")
			piece.AnchorPoint = Vector2.new(0.5, 0.5)
			piece.Position = UDim2.fromScale(0.5, 0.36)
			piece.Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20))
			piece.Rotation = math.random(0, 360)
			piece.BackgroundColor3 = CONFETTI[(i % #CONFETTI) + 1]
			piece.BorderSizePixel = 0
			piece.ZIndex = Z + 30
			piece.Parent = confettiLayer
			local a = math.rad(math.random(0, 360))
			local r = math.random(180, 520)
			local out = TweenService:Create(piece, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(a) * r, 0.36, math.sin(a) * r * 0.6 - 60),
				Rotation = piece.Rotation + math.random(-360, 360),
			})
			out:Play()
			out.Completed:Once(function()
				local fall = TweenService:Create(piece, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = piece.Position + UDim2.fromOffset(math.random(-40, 40), 260),
					BackgroundTransparency = 1,
				})
				fall:Play()
				fall.Completed:Once(function()
					piece:Destroy()
				end)
			end)
		end
	end

	local stageToken = 0
	--[[ Afişi gösterir; `hold` saniye sonra küçülüp kaybolur. ]]
	local function banner(top: string, main: string, sub: string, tint: Color3, hold: number, withConfetti: boolean)
		stageToken += 1
		local token = stageToken
		stageTop.Text = top
		stageMain.Text = main
		stageSub.Text = sub
		CardKit.tintCard(stageCard, tint)
		stage.Visible = true
		stageScale.Scale = 0.3
		TweenService:Create(stageScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if withConfetti then
			confetti(46)
		end
		task.delay(hold, function()
			if token ~= stageToken then
				return
			end
			local t = TweenService:Create(stageScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
			t:Play()
			t.Completed:Once(function()
				if token == stageToken then
					stage.Visible = false
				end
			end)
		end)
	end

	-- ── Dünyadaki hedef ───────────────────────────────────────────────────
	--[[
		Highlight ve BillboardGui DÜNYAYA bakan nesneler; ScreenGui'nin
		içine konulduklarında çizilmiyorlar. Adornee hedefi belirliyor,
		ebeveyn yalnızca ömürlerini tutuyor — o yüzden workspace ve
		PlayerGui. İkisi de Destroy'da elle siliniyor.
	]]
	local highlight = Instance.new("Highlight")
	highlight.Name = "TutorialTarget"
	highlight.FillColor = ACCENT
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = ACCENT
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = workspace

	-- Hedefin üstünde zıplayan ok
	local marker = Instance.new("BillboardGui")
	marker.Name = "TutorialMarker"
	marker.Size = UDim2.fromScale(4, 4)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	marker.AlwaysOnTop = true
	marker.MaxDistance = 400
	marker.Enabled = false
	marker.Parent = player:WaitForChild("PlayerGui")
	local markerArrow = Instance.new("TextLabel")
	markerArrow.Size = UDim2.fromScale(1, 1)
	markerArrow.BackgroundTransparency = 1
	markerArrow.Font = Enum.Font.FredokaOne
	markerArrow.Text = "▼"
	markerArrow.TextScaled = true
	markerArrow.TextColor3 = ACCENT
	markerArrow.Parent = marker
	local markerStroke = Instance.new("UIStroke")
	markerStroke.Color = CardKit.OUTLINE
	markerStroke.Thickness = 3
	markerStroke.Parent = markerArrow

	--[[
		Yol: oyuncunun ayağından hedefe parlayan ışık hattı. "Konveyör"
		kelimesini okuyup nereye gideceğini bilmeyen oyuncu çizgiyi izliyor.
		Hat yerde (ayak hizası) — göz hizasında görüşü kapatıyordu.
	]]
	local pathFolder = Instance.new("Folder")
	pathFolder.Name = "TutorialPath"
	pathFolder.Parent = workspace
	local anchorPart = Instance.new("Part")
	anchorPart.Name = "PathAnchor"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(0.2, 0.2, 0.2)
	anchorPart.Parent = pathFolder
	local fromAttachment = Instance.new("Attachment")
	fromAttachment.Parent = anchorPart
	local toPart = anchorPart:Clone()
	toPart.Name = "PathEnd"
	toPart.Parent = pathFolder
	local toAttachment = toPart:FindFirstChildOfClass("Attachment") :: Attachment
	local beam = Instance.new("Beam")
	beam.Attachment0 = fromAttachment
	beam.Attachment1 = toAttachment
	beam.Width0 = 1.6
	beam.Width1 = 1.6
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(ACCENT)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(0.85, 0.35),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	beam.Segments = 20
	beam.Enabled = false
	beam.Parent = anchorPart

	-- Ekran oku: hedef görüş alanının dışındaysa yönü ve mesafeyi söylüyor
	local compass = Instance.new("Frame")
	compass.Name = "TutorialCompass"
	compass.AnchorPoint = Vector2.new(0.5, 0.5)
	compass.Position = UDim2.new(0.5, 0, 0.30, 0)
	compass.Size = UDim2.new(0, 160, 0, 112)
	compass.BackgroundTransparency = 1
	compass.Visible = false
	compass.Parent = screen
	local compassArrow = CardKit.bold(compass, "▲", 64, ACCENT, Z + 2, 4)
	compassArrow.AnchorPoint = Vector2.new(0.5, 0)
	compassArrow.Position = UDim2.new(0.5, 0, 0, 0)
	compassArrow.Size = UDim2.fromOffset(76, 76)
	local compassText = CardKit.bold(compass, "", 22, ACCENT, Z + 2, 3)
	compassText.AnchorPoint = Vector2.new(0.5, 0)
	compassText.Position = UDim2.new(0.5, 0, 0, 74)
	compassText.Size = UDim2.new(1, 0, 0, 26)

	local currentTarget: Instance? = nil

	local function setTarget(target: Instance?)
		currentTarget = target
		if target and (target:IsA("Model") or target:IsA("BasePart")) then
			highlight.Adornee = target
			highlight.Enabled = true
			marker.Adornee = target
			marker.Enabled = true
		else
			highlight.Adornee = nil
			highlight.Enabled = false
			marker.Adornee = nil
			marker.Enabled = false
			compass.Visible = false
			beam.Enabled = false
		end
	end

	local NEAR_STUDS = 24
	local clock = 0
	local renderConnection = RunService.RenderStepped:Connect(function(dt)
		clock += dt
		-- Ok zıplıyor, Kaptan nefes alıyor
		marker.StudsOffsetWorldSpace = Vector3.new(0, 6 + math.abs(math.sin(clock * 3)) * 1.4, 0)
		guideBob.Scale = 1 + math.sin(clock * 2.2) * 0.03

		if not (currentTarget and currentTarget.Parent and frame.Visible) then
			compass.Visible = false
			beam.Enabled = false
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local targetPosition = positionOf(currentTarget)
		if not (root and root:IsA("BasePart") and targetPosition) then
			compass.Visible = false
			beam.Enabled = false
			return
		end

		local delta = targetPosition - root.Position
		local studs = Vector3.new(delta.X, 0, delta.Z).Magnitude

		-- Işık hattı: ayaktan hedefin dibine; hedefe varınca kayboluyor
		-- Zeminin biraz üstünde: tam ayak hizasında zemin plakalarının içinde kalıp görünmüyordu
		local feet = root.Position - Vector3.new(0, 2.2, 0)
		anchorPart.CFrame = CFrame.new(feet)
		toPart.CFrame = CFrame.new(Vector3.new(targetPosition.X, math.min(targetPosition.Y, feet.Y + 2), targetPosition.Z))
		beam.Enabled = studs > 8
		local pulse = 0.3 + math.abs(math.sin(clock * 2.5)) * 0.25
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.95),
			NumberSequenceKeypoint.new(0.12, pulse),
			NumberSequenceKeypoint.new(0.88, pulse),
			NumberSequenceKeypoint.new(1, 0.95),
		})

		if studs <= NEAR_STUDS then
			compass.Visible = false
			return
		end
		compass.Visible = true
		compassArrow.Rotation = bearingTo(targetPosition, root.Position)
		compassText.Text = string.format("%d studs", math.floor(studs + 0.5))
	end)

	task.spawn(function()
		local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(highlight, info, { FillTransparency = 0.92 }):Play()
	end)

	-- ── Daktilo ───────────────────────────────────────────────────────────
	local typeToken = 0
	local function typeOut(text: string)
		typeToken += 1
		local token = typeToken
		body.Text = text
		body.MaxVisibleGraphemes = 0
		-- Kaptan konuşmaya başlarken zıplıyor
		guide.Rotation = -8
		TweenService:Create(guide, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		task.spawn(function()
			local total = utf8.len(text) or #text
			local shown = 0
			while shown < total and token == typeToken do
				shown = math.min(total, shown + 2)
				body.MaxVisibleGraphemes = shown
				task.wait(0.025)
			end
			if token == typeToken then
				body.MaxVisibleGraphemes = -1
			end
		end)
	end

	-- ── Güncelleme ────────────────────────────────────────────────────────
	local lastIndex: number? = nil
	local lastText: string? = nil

	local function hide()
		setTarget(nil)
		if not frame.Visible then
			return
		end
		local t = TweenService:Create(frameScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		t:Play()
		t.Completed:Once(function()
			frame.Visible = false
			frameScale.Scale = 1
		end)
	end

	local function paintDots(index: number)
		for i, d in dotFrames do
			d.BackgroundColor3 = if i < index then GOOD elseif i == index then CardKit.YELLOW else Color3.fromRGB(40, 46, 64)
			d.Size = if i == index then UDim2.fromOffset(16, 16) else UDim2.fromOffset(13, 13)
		end
	end

	local function show(payload: Payload, target: Instance?)
		local index = payload.index or 1
		local total = payload.total or #Config.Tutorial
		local value = payload.value or 0
		local goal = math.max(1, payload.goal or 1)

		-- Önceki adım bitti mi? (sıra ilerledi) — kutla
		local advanced = lastIndex ~= nil and index > (lastIndex :: number)
		if advanced then
			local done = Config.GetTutorialStep(lastIndex :: number)
			local amount = if done then done.reward else 0
			banner("STEP COMPLETE!", done and string.upper(done.title) or "NICE!",
				if amount > 0 then "+$" .. Config.FormatCash(amount) else "", Color3.fromRGB(50, 170, 60), 1.6, true)
		end
		local isNew = lastIndex == nil or index ~= lastIndex
		lastIndex = index

		counter.Text = string.format("STEP %d / %d", index, total)
		title.Text = payload.title or ""
		paintDots(index)
		local text = payload.text or ""
		if text ~= lastText then
			lastText = text
			typeOut(text)
		end

		local ratio = math.clamp(value / goal, 0, 1)
		bar.set(ratio, string.format("%d / %d", math.min(value, goal), goal))
		local amount = payload.reward or 0
		rewardChip.Text = if amount > 0 then "+$" .. Config.FormatCash(amount) else ""
		rewardChip.Visible = amount > 0

		setTarget(target)
		if not frame.Visible then
			frame.Visible = true
			frameScale.Scale = 0
			TweenService:Create(frameScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end

		-- Yeni adımın afişi: kutlamadan sonra
		if isNew then
			task.delay(if advanced then 1.9 else 0.4, function()
				if lastIndex ~= index then
					return
				end
				banner(string.format("STEP %d OF %d", index, total), string.upper(payload.title or ""),
					if amount > 0 then "Reward  +$" .. Config.FormatCash(amount) else "", CARD_TINT, 2.2, false)
			end)
		end
	end

	local connection = Net.Get("Tutorial").OnClientEvent:Connect(function(payload: Payload, target: Instance?)
		if typeof(payload) ~= "table" or not payload.active then
			-- Aktifken bitti ve atlanmadıysa: final
			if lastIndex ~= nil and not skipped then
				local last = Config.GetTutorialStep(lastIndex :: number)
				local lastReward = if last then last.reward else 0
				banner("TUTORIAL COMPLETE!", "YOU'RE A REAL CREWMATE!",
					"+$" .. Config.FormatCash(lastReward + Config.TutorialFinishBonus), Color3.fromRGB(230, 150, 20), 3.2, true)
				task.delay(0.35, function()
					confetti(40)
				end)
			end
			lastIndex = nil
			hide()
			return
		end
		show(payload, target)
	end)

	highlight:GetPropertyChangedSignal("Adornee"):Connect(function()
		if highlight.Adornee == nil then
			highlight.Enabled = false
		end
	end)

	return {
		Destroy = function()
			connection:Disconnect()
			renderConnection:Disconnect()
			highlight:Destroy()
			marker:Destroy()
			pathFolder:Destroy()
			compass:Destroy()
			stage:Destroy()
			confettiLayer:Destroy()
			frame:Destroy()
		end,
	}
end

return TutorialUI
