--!strict
--[[
	Cihaz uyumu: telefon, tablet, konsol.

	═══ ÖLÇEK ══════════════════════════════════════════════════════════════

	Arayüzün tamamı piksel ölçüsüyle yazıldı ve ~1280x720 ekranda 1:1
	tasarlandı. Telefonda (yatay ~844x390) pencereler ekrandan taşıyor,
	sol ray ile nakit hapı ekranın yarısını kaplıyordu.

	Çözüm tek bir ölçek katmanı: HUD'un bütün içeriği "DeviceRoot" adlı
	tam ekran bir Frame'in içinde, onun UIScale'i ekrana göre küçülüyor.
	Root'un boyu 1/ölçek; ölçekle çarpılınca tekrar tam ekran oluyor. Böylece
	panellerin boyutu da kenar boşlukları da AYNI oranda küçülüyor ve
	yerleşim bozulmuyor. Panellerin koduna dokunmak gerekmedi.

	Ölçek hiçbir zaman 1'i geçmiyor: büyük ekranda arayüz tasarlandığı
	boyda kalıyor. Alt sınır var ki telefonda yazılar okunmaz olmasın.

	═══ DOKUNMATİK ═════════════════════════════════════════════════════════

	Roblox'un joystick'i sol altta, zıplama düğmesi sağ altta. Sol alttaki
	nakit hapı + ray ile sağ alttaki menü dizisi tam onların üstüne
	düşüyordu. Dokunmatikte bu üç öğe yukarı kayıyor; masaüstünde yerleri
	değişmiyor. Konumlar adla bulunuyor (Topbar'ın gizleme listesi gibi).

	═══ GAMEPAD ════════════════════════════════════════════════════════════

	Pencere açılınca seçim ilk düğmeye gidiyor, oyuncu D-pad ile gezip A
	ile basabiliyor. Roblox'un kendi arayüz gezintisi (Select tuşu) zaten
	açık; burası yalnızca pencere açıldığında seçimi içine taşıyor.
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.UiKit)

local DeviceLayout = {}

export type Device = "Desktop" | "Touch" | "Gamepad"

-- Arayüzün 1:1 tasarlandığı ekran (topbar hariç yükseklik)
local REF_WIDTH, REF_HEIGHT = 1280, 660
-- Dokunmatikte biraz daha büyük: parmak fareden kalın
local TOUCH_REF_WIDTH, TOUCH_REF_HEIGHT = 1000, 560
local MIN_SCALE, MAX_SCALE = 0.45, 1

-- En büyük pencere (PetPanel 580x520) kenar payıyla sığmalı
local WINDOW_FIT = Vector2.new(820, 540)

--[[
	Dokunmatikte kaydırılan öğeler: adı -> hangi taraf. Değerler ekran
	pikseli değil, joystick/zıplama düğmesinin kapladığı yükseklik; root
	birimine ölçeğe bölünerek çevriliyor.
]]
local TOUCH_LIFT = {
	StatBar = "left",
	SideRail = "left",
	Tutorial = "left",
	MenuDock = "right",
}

--[[
	Roblox'un dokunmatik kontrollerinin kapladığı alt bant (gerçek piksel).
	Küçük ekran eşiği ve boyutlar Roblox'un TouchGui kurulumuyla aynı:
	kısa kenarı 500'den küçükse küçük düzen.
]]
local function touchClearance(viewport: Vector2): (number, number)
	local small = math.min(viewport.X, viewport.Y) <= 500
	if small then
		return 120, 105
	end
	return 230, 220
end

function DeviceLayout.GetDevice(): Device
	local ok, preferred = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and preferred ~= nil then
		if preferred == (Enum :: any).PreferredInput.Touch then
			return "Touch"
		elseif preferred == (Enum :: any).PreferredInput.Gamepad then
			return "Gamepad"
		end
		return "Desktop"
	end
	-- PreferredInput olmayan istemciler için eski yol
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "Desktop"
end

local function computeScale(area: Vector2, device: Device): number
	local refW, refH = REF_WIDTH, REF_HEIGHT
	if device == "Touch" then
		refW, refH = TOUCH_REF_WIDTH, TOUCH_REF_HEIGHT
	end
	local scale = math.min(area.X / refW, area.Y / refH)
	-- Hangi cihaz olursa olsun en büyük pencere ekrana sığmalı
	scale = math.min(scale, area.X / WINDOW_FIT.X, area.Y / WINDOW_FIT.Y)
	return math.clamp(scale, MIN_SCALE, MAX_SCALE)
end

-- ─── Gamepad: pencere açılınca seçimi içine al ──────────────────────────────

local function firstButton(window: GuiObject): GuiObject?
	local best: GuiObject? = nil
	local bestKey = math.huge
	for _, d in window:GetDescendants() do
		if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Selectable and d.Name ~= "Close" then
			local button = d :: GuiObject
			-- Görünmeyen bir atada duruyorsa seçilemez
			local visible = true
			local node: Instance? = button
			while node and node ~= window do
				if node:IsA("GuiObject") and not node.Visible then
					visible = false
					break
				end
				node = node.Parent
			end
			if visible then
				-- Okuma sırası: önce üstteki satır, sonra soldaki
				local key = math.floor(button.AbsolutePosition.Y / 8) * 10000 + button.AbsolutePosition.X
				if key < bestKey then
					best, bestKey = button, key
				end
			end
		end
	end
	return best
end

local function selectInside(window: GuiObject)
	-- İçerik açılışta yeniden çiziliyor; bir kare bekle
	task.defer(function()
		if not window.Visible or DeviceLayout.GetDevice() ~= "Gamepad" then
			return
		end
		local target = firstButton(window)
		if target then
			GuiService.SelectedObject = target
		end
	end)
end

local watchedWindows: { [GuiObject]: boolean } = {}

local function onWindowOpened(window: GuiObject)
	selectInside(window)
	if watchedWindows[window] then
		return
	end
	watchedWindows[window] = true
	-- Kapanınca seçim pencerede kalmasın, yoksa görünmeyen düğmeye basılır
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		local selected = GuiService.SelectedObject
		if not window.Visible and selected and selected:IsDescendantOf(window) then
			GuiService.SelectedObject = nil
		end
	end)
	window.Destroying:Connect(function()
		watchedWindows[window] = nil
	end)
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

export type Layout = {
	Root: Frame,
	GetScale: () -> number,
	GetDevice: () -> Device,
}

--[[
	Ekrandaki HUD'u ölçek katmanına sarar ve katmanı döndürür. Paneller
	artık bu katmanın içine kuruluyor (init.client `screen` olarak bunu
	veriyor).
]]
function DeviceLayout.Wrap(gui: ScreenGui): Layout
	local root = Instance.new("Frame")
	root.Name = "DeviceRoot"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local scaler = Instance.new("UIScale")
	scaler.Name = "DeviceScale"
	scaler.Parent = root

	local scale = 1
	local device: Device = DeviceLayout.GetDevice()

	-- Öğelerin kendi (masaüstü) konumu; dokunmatikten dönünce geri konuyor
	local original: { [GuiObject]: UDim2 } = {}

	local function place(element: Instance)
		if not element:IsA("GuiObject") then
			return
		end
		local side = TOUCH_LIFT[element.Name]
		if not side then
			return
		end
		local base = original[element]
		if not base then
			base = element.Position
			original[element] = base
		end
		if device ~= "Touch" then
			element.Position = base
			return
		end
		local left, right = touchClearance(workspace.CurrentCamera.ViewportSize)
		local lift = (if side == "left" then left else right) / scale
		-- Öğenin kendi alt payını koruyarak joystick bandının üstüne çık
		element.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset - lift)
	end

	local function refresh()
		local area = gui.AbsoluteSize
		if area.X <= 0 or area.Y <= 0 then
			return
		end
		device = DeviceLayout.GetDevice()
		scale = computeScale(area, device)
		scaler.Scale = scale
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
		for _, child in root:GetChildren() do
			place(child)
		end
		root:SetAttribute("Device", device)
		root:SetAttribute("Scale", scale)
	end

	root.ChildAdded:Connect(function(child)
		-- Modüller konumu çoğunlukla Parent'tan SONRA da yazabiliyor
		task.defer(place, child)
	end)
	root.ChildRemoved:Connect(function(child)
		if child:IsA("GuiObject") then
			original[child] = nil
		end
	end)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	UserInputService.LastInputTypeChanged:Connect(function()
		if DeviceLayout.GetDevice() ~= device then
			refresh()
		end
	end)
	refresh()

	UiKit.OnWindowOpened(onWindowOpened)

	return {
		Root = root,
		GetScale = function()
			return scale
		end,
		GetDevice = function()
			return device
		end,
	}
end

return DeviceLayout
