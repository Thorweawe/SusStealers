--!strict
--[[
	Kısa bildirimler ("Stole X!", "Base locked", "Wait 3 s" ...).

	Eskiden ekranın en dibinde (alttan 40 piksel) ince, gri, Gotham yazılı
	kutulardı: ekipman çubuğu (Hotbar) açılınca tam onun üstüne biniyor ve
	okunmuyordu, görünüşü de mağaza diline geçen öbür pencerelerden
	kopuktu.

	Artık ekipman çubuğunun ÜSTÜNDE, CardKit kartı: renkli gradyan zemin,
	kalın koyu konturlu çizgi roman yazısı, zıplayarak açılıyor. Başarılı
	yeşil, hata kırmızı. Aynı anda en fazla MAX tane; fazlası en eskiyi
	atıyor, yığın ekipmanın üstüne taşmıyor.
]]

local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local CardKit = require(script.Parent.CardKit)

local Toasts = {}

export type Handle = {
	Show: (text: string, isError: boolean?, tint: Color3?) -> (),
}

local Z = 40
local MAX = 3
local HEIGHT = 44
local TEXT_SIZE = 21
local LIFETIME = 3.2

local GOOD_TINT = Color3.fromRGB(46, 170, 74)
local BAD_TINT = Color3.fromRGB(214, 52, 64)

--[[ Ekipman çubuğu alttan 14 + 66 piksel, üstünde kuşanılı ekipmanın adı (Hotbar GearHint, 26 piksel); onun da üstü. ]]
local BOTTOM = 14 + 66 + 44

function Toasts.Create(screen: Instance): Handle
	local holder = Instance.new("Frame")
	holder.Name = "Toasts"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -BOTTOM)
	holder.Size = UDim2.fromOffset(600, (HEIGHT + 30) * MAX)
	holder.BackgroundTransparency = 1
	holder.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = holder

	local order = 0
	local live: { Frame } = {}

	--[[
		Öğretici kartı (sol altta, 172 yüksek, alttan 22) açıkken bildirimler
		onun arkasında kalıyordu: kartın üstüne çıkıyorlar.
	]]
	local TUTORIAL_TOP = 22 + 172 + 10
	task.spawn(function()
		while holder.Parent do
			local tut = screen:FindFirstChild("Tutorial")
			local bottom = if tut and tut:IsA("GuiObject") and tut.Visible then math.max(BOTTOM, TUTORIAL_TOP) else BOTTOM
			if holder.Position.Y.Offset ~= -bottom then
				holder.Position = UDim2.new(0.5, 0, 1, -bottom)
			end
			task.wait(0.5)
		end
	end)

	local function remove(slot: Frame)
		local i = table.find(live, slot)
		if i then
			table.remove(live, i)
		end
		slot:Destroy()
	end

	local function show(text: string, isError: boolean?, tint: Color3?)
		order += 1
		local color = tint or (if isError then BAD_TINT else GOOD_TINT)

		-- Genişlik yazıya göre (kalın yazı Gotham'dan geniş; pay bırakıyoruz)
		local plain = text:gsub("<[^>]->", "")
		local measured = TextService:GetTextSize(plain, TEXT_SIZE, CardKit.FONT, Vector2.new(2000, HEIGHT))
		-- Uzun metin iki satıra iniyor (tek satırda küçülüp okunmaz oluyordu)
		local twoLines = measured.X + 48 > 580
		local width = math.clamp(measured.X + 48, 180, 580)
		local height = if twoLines then HEIGHT + 22 else HEIGHT

		-- Yuva düzende yer tutuyor; kart içinde ölçeklenip zıplıyor
		local slot = Instance.new("Frame")
		slot.Name = "Toast"
		slot.Size = UDim2.fromOffset(width, height)
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = order
		slot.Parent = holder

		local card = CardKit.card(slot, color, UDim2.fromScale(1, 1), Z, UDim2.fromScale(0.5, 0.5), width * 1.4)
		local scale = Instance.new("UIScale")
		scale.Scale = 0.6
		scale.Parent = card

		local label = CardKit.bold(card, text, TEXT_SIZE, CardKit.WHITE, Z + 3, 2.5)
		label.Position = UDim2.fromOffset(12, 0)
		label.Size = UDim2.new(1, -24, 1, 0)
		if twoLines then
			label.TextSize = TEXT_SIZE - 3
			label.TextWrapped = true
		else
			CardKit.fit(label, TEXT_SIZE, 12)
		end

		table.insert(live, slot)
		while #live > MAX do
			remove(live[1])
		end

		TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

		task.delay(LIFETIME, function()
			if not slot.Parent then
				return
			end
			local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(scale, info, { Scale = 0.001 }):Play()
			task.wait(0.32)
			if slot.Parent then
				remove(slot)
			end
		end)
	end

	return { Show = show }
end

return Toasts
