--!strict
--[[
	Üsse tehdit uyarısı: ekranın üst-ortasında büyük, kısa bant.

	Neden: "karakterin çalındı", "impostor üssüne geliyor", "sabotaj"
	gibi oyuncunun HEMEN tepki vermesi gereken şeyler alttaki bildirim
	yığınında kayboluyordu — küçük, uzun cümle, ekranın en dibinde.
	Burada tek büyük başlık + tek satır açıklama, bıçaklı mürettebat
	ikonu, sarsılarak açılıyor ve kenarı nabız gibi atıyor.

	Olay şeridinin (EventFX, en üstte) altında duruyor ki üst üste
	binmesin. Yeni uyarı eskisinin yerini alıyor, yığılmıyor.
]]

local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent.UiKit)

local AlertBanner = {}

export type Handle = {
	Show: (title: string, detail: string, color: Color3?, seconds: number?) -> (),
	Destroy: () -> (),
}

local Z = 60
local DEFAULT_COLOR = Color3.fromRGB(255, 60, 70)

function AlertBanner.Create(screen: Instance): Handle
	local root = Instance.new("Frame")
	root.Name = "AlertBanner"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 118)
	root.Size = UDim2.fromOffset(500, 84)
	root.BackgroundColor3 = UiKit.SHELL_DEEP
	root.BackgroundTransparency = 0.05
	root.BorderSizePixel = 0
	root.Visible = false
	root.ZIndex = Z
	root.Parent = screen
	UiKit.Corner(root, 16)
	local stroke = UiKit.Stroke(root, DEFAULT_COLOR, 3, 0)
	local scale = Instance.new("UIScale")
	scale.Parent = root

	-- Sol: kırmızı disk içinde bıçaklı mürettebat
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0, 0.5)
	disc.Position = UDim2.new(0, 12, 0.5, 0)
	disc.Size = UDim2.fromOffset(60, 60)
	disc.BackgroundColor3 = DEFAULT_COLOR
	disc.BorderSizePixel = 0
	disc.ZIndex = Z + 1
	disc.Parent = root
	UiKit.Corner(disc, 30)
	local crew = UiKit.Crewmate(disc, 42, Color3.fromRGB(40, 12, 16))
	crew.AnchorPoint = Vector2.new(0.5, 0.5)
	crew.Position = UDim2.fromScale(0.5, 0.52)
	for _, d in crew:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += Z
		end
	end
	crew.ZIndex += Z

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(86, 10)
	title.Size = UDim2.new(1, -100, 0, 36)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = DEFAULT_COLOR
	title.TextStrokeTransparency = 0.4
	title.ZIndex = Z + 1
	title.Parent = root
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = 30
	titleLimit.Parent = title

	local detail = Instance.new("TextLabel")
	detail.Position = UDim2.fromOffset(86, 48)
	detail.Size = UDim2.new(1, -100, 0, 24)
	detail.BackgroundTransparency = 1
	detail.Font = Enum.Font.GothamBold
	detail.TextScaled = true
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextColor3 = UiKit.INK
	detail.ZIndex = Z + 1
	detail.Parent = root
	local detailLimit = Instance.new("UITextSizeConstraint")
	detailLimit.MaxTextSize = 18
	detailLimit.Parent = detail

	local serial = 0
	local pulse: Tween? = nil

	local function hide(mySerial: number)
		if serial ~= mySerial then
			return
		end
		local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(scale, info, { Scale = 0.85 }):Play()
		TweenService:Create(root, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(title, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(detail, info, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		task.delay(0.26, function()
			if serial == mySerial then
				root.Visible = false
				if pulse then
					pulse:Cancel()
					pulse = nil
				end
			end
		end)
	end

	local function show(titleText: string, detailText: string, color: Color3?, seconds: number?)
		serial += 1
		local mySerial = serial
		local c = color or DEFAULT_COLOR

		title.Text = string.upper(titleText)
		detail.Text = detailText
		title.TextColor3 = c
		stroke.Color = c
		disc.BackgroundColor3 = c
		root.BackgroundTransparency = 0.05
		title.TextTransparency = 0
		title.TextStrokeTransparency = 0.4
		detail.TextTransparency = 0
		stroke.Transparency = 0
		root.Visible = true

		-- Açılış: büyüyerek ve hafif sarsılarak
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		root.Rotation = -3
		TweenService:Create(root, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()

		-- Kenar nabız gibi atıyor
		if pulse then
			pulse:Cancel()
		end
		stroke.Thickness = 3
		pulse = TweenService:Create(stroke, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6 })
		;(pulse :: Tween):Play()

		task.delay(seconds or 5, hide, mySerial)
	end

	return {
		Show = show,
		Destroy = function()
			if pulse then
				pulse:Cancel()
			end
			root:Destroy()
		end,
	}
end

return AlertBanner
