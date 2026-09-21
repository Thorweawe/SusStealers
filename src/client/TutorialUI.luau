--!strict
--[[
	Öğretici paneli: sıradaki adımı ve hedefi gösterir.

	Sunucu (TutorialService) hangi adımda olduğumuzu "Tutorial" remote'uyla
	gönderiyor; burada sadece çiziliyor. Karar sunucuda, görüntü burada —
	istemci ilerlemeyi değiştiremiyor.

	Remote iki şey yolluyor:
		payload : { active, index, total, id, title, text, hint, reward,
		            value, goal }
		target  : ilerlenecek nesne (Instance?) — bulunamadıysa nil

	Hedef nesne Highlight ile çevreleniyor. Oyuncu "nereye gideceğim"
	sorusunu metinden değil, dünyadan okuyor; bu türde en sık kaybedilen
	yer orası.

	Kullanım (init.client.luau içinde, screen kurulduktan sonra):
		local TutorialUI = require(script.TutorialUI)
		local tutorial = TutorialUI.Create(screen)

	Döngüde güncellenmesi gerekmiyor, olay güdümlü.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local TutorialUI = {}

local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local ACCENT = Color3.fromRGB(255, 190, 90)
local GOOD = Color3.fromRGB(120, 255, 150)
local PANEL = Color3.fromRGB(18, 20, 28)

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

function TutorialUI.Create(screen: ScreenGui): Panel
	-- Sol alt: sol üstte nakit, sağ üstte üs paneli, alt ortada bildirimler
	-- var. Kalan tek boş köşe burası.
	local frame = Instance.new("Frame")
	frame.Name = "Tutorial"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 24, 1, -24)
	frame.Size = UDim2.new(0, 330, 0, 126)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	-- Sol kenarda renkli şerit: panelin bildirim değil, kalıcı bir görev
	-- olduğunu ayırt ettiriyor
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, 0)
	stripe.BackgroundColor3 = ACCENT
	stripe.BorderSizePixel = 0
	stripe.Parent = frame

	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(0, 10)
	stripeCorner.Parent = stripe

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = frame

	local function newLabel(name: string, y: number, height: number, size: number, font: Enum.Font): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Position = UDim2.new(0, 0, 0, y)
		label.Size = UDim2.new(1, 0, 0, height)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextSize = size
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.TextColor3 = INK
		label.Parent = frame
		return label
	end

	local counter = newLabel("Counter", 0, 16, 13, Enum.Font.GothamMedium)
	counter.TextColor3 = MUTED

	local title = newLabel("Title", 17, 24, 21, Enum.Font.GothamBold)
	title.TextColor3 = ACCENT

	local body = newLabel("Body", 43, 40, 15, Enum.Font.GothamMedium)
	body.TextColor3 = INK
	body.TextWrapped = true

	-- İlerleme çubuğu: hedefi iki adet olan adımda (ikinci kaide) oyuncu
	-- birini aldığında bir şeyin ilerlediğini görmeli
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.new(0, 0, 0, 88)
	track.Size = UDim2.new(1, -14, 0, 6)
	track.BackgroundColor3 = Color3.fromRGB(44, 50, 62)
	track.BorderSizePixel = 0
	track.Parent = frame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = GOOD
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local reward = newLabel("Reward", 100, 18, 14, Enum.Font.GothamBold)
	reward.TextColor3 = GOOD

	-- Atlama: oyunu bilen oyuncu paneli kapatabilmeli. Kalan ödüller yanıyor,
	-- o yüzden yazıda "skip" değil ne kaybedileceği de var.
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, 0, 1, -10)
	skip.Size = UDim2.new(0, 64, 0, 20)
	skip.BackgroundTransparency = 1
	skip.Font = Enum.Font.GothamMedium
	skip.TextSize = 13
	skip.TextColor3 = MUTED
	skip.TextXAlignment = Enum.TextXAlignment.Right
	skip.Text = "Skip →"
	skip.AutoButtonColor = false
	skip.Parent = frame

	skip.MouseEnter:Connect(function()
		skip.TextColor3 = INK
	end)
	skip.MouseLeave:Connect(function()
		skip.TextColor3 = MUTED
	end)

	local skipRemote = Net.Get("TutorialSkip")
	skip.Activated:Connect(function()
		skip.Text = "..."
		skipRemote:FireServer()
	end)

	-- ─── Dünyadaki hedef ────────────────────────────────────────────────────

	local highlight = Instance.new("Highlight")
	highlight.Name = "TutorialTarget"
	highlight.FillColor = ACCENT
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = ACCENT
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = screen

	local function setTarget(target: Instance?)
		if target and (target:IsA("Model") or target:IsA("BasePart")) then
			highlight.Adornee = target
			highlight.Enabled = true
		else
			highlight.Adornee = nil
			highlight.Enabled = false
		end
	end

	--[[
		Hedef dikkat çeksin diye nefes alıyor. Sabit bir çerçeve dünyanın
		geri kalanına karışıyor; yanıp sönen karışmıyor.
	]]
	task.spawn(function()
		local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(highlight, info, { FillTransparency = 0.92 }):Play()
	end)

	-- ─── Güncelleme ─────────────────────────────────────────────────────────

	local function hide()
		setTarget(nil)
		if not frame.Visible then
			return
		end

		local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		for _, child in frame:GetDescendants() do
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				TweenService:Create(child, info, { TextTransparency = 1 }):Play()
			elseif child:IsA("Frame") then
				TweenService:Create(child, info, { BackgroundTransparency = 1 }):Play()
			end
		end

		task.delay(0.5, function()
			frame.Visible = false
		end)
	end

	-- hide() saydamlık tween'i çalıştırıyor. Bitirmek terminal bir durum,
	-- yani pratikte geri dönüş yok; yine de yeniden gösterilirse panel
	-- görünmez kalmasın diye saydamlıkları sıfırlıyoruz.
	local function resetTransparency()
		frame.BackgroundTransparency = 0.15
		for _, child in frame:GetDescendants() do
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				child.TextTransparency = 0
			elseif child:IsA("Frame") then
				child.BackgroundTransparency = 0
			end
		end
	end

	local function show(payload: Payload, target: Instance?)
		local index = payload.index or 1
		local total = payload.total or #Config.Tutorial
		local value = payload.value or 0
		local goal = math.max(1, payload.goal or 1)

		counter.Text = string.format("TUTORIAL  ·  STEP %d OF %d", index, total)
		title.Text = payload.title or ""
		body.Text = payload.text or ""

		if goal > 1 then
			track.Visible = true
			TweenService:Create(
				fill,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.new(math.clamp(value / goal, 0, 1), 0, 1, 0) }
			):Play()
		else
			-- Tek adımlık hedefte çubuk hep boş duracaktı; bilgi vermiyor
			track.Visible = false
		end

		local amount = payload.reward or 0
		reward.Text = if amount > 0 then "Reward  $" .. Config.FormatCash(amount) else ""

		setTarget(target)
		if not frame.Visible then
			resetTransparency()
		end
		frame.Visible = true
	end

	local connection = Net.Get("Tutorial").OnClientEvent:Connect(function(payload: Payload, target: Instance?)
		if typeof(payload) ~= "table" or not payload.active then
			hide()
			return
		end
		show(payload, target)
	end)

	--[[
		Karakter yeniden doğduğunda ScreenGui kalıyor (ResetOnSpawn false)
		ama vurgulanan hedef üs devri gibi durumlarda yok olabiliyor.
		Adornee silinirse Highlight sessizce boşa düşüyor, hata vermiyor;
		yine de kapatmak temiz.
	]]
	highlight:GetPropertyChangedSignal("Adornee"):Connect(function()
		if highlight.Adornee == nil then
			highlight.Enabled = false
		end
	end)

	return {
		Destroy = function()
			connection:Disconnect()
			highlight:Destroy()
			frame:Destroy()
		end,
	}
end

return TutorialUI
