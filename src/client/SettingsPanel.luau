--!strict
--[[
	Oyun içi SETTINGS penceresi (üst şeritteki ⚙ düğmesi).

	Görünüş referansı (Yusuf'un attığı görsel): başlıklı bölümler, her satırda
	renkli ikon rozeti + ad + sağda yeşil/kırmızı kayar anahtar. Bizim
	temaya uyarlandı (UiKit penceresi, uzay mavisi vurgu, tıknaz yazı).

	  AUDIO     Music ve Sound Effects — kaydırıcı (0..100)
	  GAMEPLAY  Camera Shake, Other Players' Pets, My Pets
	  GRAPHICS  Low Graphics — gölgeler, parçacıklar, ışık efektleri kapalı

	Kaydetme sunucuda (SettingsService, "SettingsSave"): oyuncu değiştirmeyi
	bitirince tek istek. Değerler "Setting*" niteliklerinden okunuyor; ses ve
	sarsıntı modülleri de aynı niteliklere bakıyor, anında etkili. Düşük
	grafiği bu modül uyguluyor (LowGfx aşağıda).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local SettingsPanel = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(70, 190, 255)
local ON = Color3.fromRGB(70, 210, 100)
local OFF = Color3.fromRGB(220, 70, 80)
local Z = 60

export type Panel = {
	Open: () -> (),
	Toggle: () -> (),
	Destroy: () -> (),
}

-- ─── Düşük grafik ───────────────────────────────────────────────────────────

--[[
	Açıkken: gölgeler kapalı, Lighting'deki son işlem efektleri (Bloom,
	SunRays, DepthOfField, Blur hariç) kapalı, dünyadaki iz/ışın/duman
	yayıcıları kapalı (sonradan eklenenler de). Kapatınca yalnızca BİZİM
	kapattıklarımız geri açılıyor.
	2026-10-03: parçacıklar artık KAPANMIYOR, yoğunlukları %30'a iniyor —
	tamamen kapanınca boss ve crewmate'ler efektsiz, "bozuk" görünüyordu.
]]
local LOW_RATE = 0.3
local lowOn = false
local touched: { [Instance]: boolean } = {}
local savedRate: { [ParticleEmitter]: number } = {}
local addedConn: RBXScriptConnection? = nil
local oldShadows: boolean? = nil

local function dim(d: Instance)
	if d:IsA("ParticleEmitter") then
		if not savedRate[d] then
			savedRate[d] = d.Rate
			d.Rate *= LOW_RATE
		end
		return
	end
	if (d:IsA("Trail") or d:IsA("Beam") or d:IsA("Sparkles") or d:IsA("Smoke") or d:IsA("Fire"))
		and (d :: any).Enabled then
		(d :: any).Enabled = false
		touched[d] = true
	end
end

local function setLowGraphics(on: boolean)
	if on == lowOn then
		return
	end
	lowOn = on
	if on then
		oldShadows = Lighting.GlobalShadows
		Lighting.GlobalShadows = false
		for _, e in Lighting:GetChildren() do
			if e:IsA("BloomEffect") or e:IsA("SunRaysEffect") or e:IsA("DepthOfFieldEffect") then
				if e.Enabled then
					e.Enabled = false
					touched[e] = true
				end
			end
		end
		for _, d in workspace:GetDescendants() do
			dim(d)
		end
		addedConn = workspace.DescendantAdded:Connect(function(d)
			task.defer(dim, d)
		end)
	else
		if addedConn then
			addedConn:Disconnect()
			addedConn = nil
		end
		if oldShadows ~= nil then
			Lighting.GlobalShadows = oldShadows
		end
		for d in touched do
			if d.Parent then
				(d :: any).Enabled = true
			end
		end
		table.clear(touched)
		for e, rate in savedRate do
			if e.Parent then
				e.Rate = rate
			end
		end
		table.clear(savedRate)
	end
end

-- ─── Pencere ────────────────────────────────────────────────────────────────

local function text(parent: Instance, value: string, font: Enum.Font, size: number, color: Color3, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = value
	l.ZIndex = z
	l.Parent = parent
	return l
end

function SettingsPanel.Create(screen: ScreenGui): Panel
	local root = UiKit.Window(screen, "SettingsPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(420, 530)
	root.Visible = false
	root.ZIndex = Z

	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 56)
	band.BackgroundColor3 = ACCENT:Lerp(Color3.new(0, 0, 0), 0.62)
	band.BorderSizePixel = 0
	band.ZIndex = Z + 1
	band.Parent = root
	UiKit.Corner(band, 14)
	local foot = Instance.new("Frame")
	foot.Position = UDim2.new(0, 0, 1, -14)
	foot.Size = UDim2.new(1, 0, 0, 14)
	foot.BackgroundColor3 = band.BackgroundColor3
	foot.BorderSizePixel = 0
	foot.ZIndex = Z + 1
	foot.Parent = band
	local title = text(band, "⚙  SETTINGS", Enum.Font.FredokaOne, 28, Color3.new(1, 1, 1), Z + 2)
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.fromOffset(18, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(10, 20, 40)
	stroke.Parent = title

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 3

	local list = Instance.new("Frame")
	list.Position = UDim2.fromOffset(16, 66)
	list.Size = UDim2.new(1, -32, 1, -100)
	list.BackgroundTransparency = 1
	list.ZIndex = Z + 1
	list.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 7)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local saved = text(root, "Saved to your account.", Enum.Font.GothamMedium, 12, UiKit.MUTED, Z + 2)
	saved.AnchorPoint = Vector2.new(0.5, 1)
	saved.Position = UDim2.new(0.5, 0, 1, -10)
	saved.Size = UDim2.new(1, -20, 0, 16)

	-- Mevcut değerler (nitelikler)
	local current = { music = 1, sfx = 1, shake = true, pets = true, myPets = true, lowGfx = false }
	local function read()
		for key, attr in { music = "SettingMusic", sfx = "SettingSfx" } do
			local v = player:GetAttribute(attr)
			if typeof(v) == "number" then
				(current :: any)[key] = math.clamp(v, 0, 1)
			end
		end
		for key, attr in { shake = "SettingShake", pets = "SettingPets", myPets = "SettingMyPets", lowGfx = "SettingLowGfx" } do
			local v = player:GetAttribute(attr)
			if typeof(v) == "boolean" then
				(current :: any)[key] = v
			end
		end
	end
	read()

	local saveRemote = Net.Get("SettingsSave")
	local saveToken = 0
	local function queueSave()
		saveToken += 1
		local token = saveToken
		task.delay(0.5, function()
			if token == saveToken then
				saveRemote:FireServer(table.clone(current))
			end
		end)
	end
	-- Ses modülleri niteliği dinliyor: sürüklerken anında duyulsun diye yerelde de yaz
	local function preview(key: string)
		local attr = ({ music = "SettingMusic", sfx = "SettingSfx", shake = "SettingShake", pets = "SettingPets", myPets = "SettingMyPets", lowGfx = "SettingLowGfx" } :: any)[key]
		player:SetAttribute(attr, (current :: any)[key])
		if key == "lowGfx" then
			setLowGraphics(current.lowGfx)
		end
	end

	local order = 0
	local function section(name: string)
		order += 1
		local h = text(list, name, Enum.Font.GothamBlack, 14, ACCENT:Lerp(Color3.new(1, 1, 1), 0.35), Z + 2)
		h.LayoutOrder = order
		h.Size = UDim2.new(1, 0, 0, 22)
		h.TextXAlignment = Enum.TextXAlignment.Left
	end

	local function row(icon: string, tint: Color3, name: string): Frame
		order += 1
		local r = Instance.new("Frame")
		r.LayoutOrder = order
		r.Size = UDim2.new(1, 0, 0, 50)
		r.BackgroundColor3 = tint:Lerp(UiKit.ROW, 0.82)
		r.BorderSizePixel = 0
		r.ZIndex = Z + 2
		r.Parent = list
		UiKit.Corner(r, 12)
		UiKit.Stroke(r, tint, 1.5, 0.45)
		local badge = Instance.new("Frame")
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 8, 0.5, 0)
		badge.Size = UDim2.fromOffset(36, 36)
		badge.BackgroundColor3 = tint
		badge.BorderSizePixel = 0
		badge.ZIndex = Z + 3
		badge.Parent = r
		UiKit.Corner(badge, 10)
		UiKit.Stroke(badge, Color3.fromRGB(12, 16, 28), 2, 0)
		local glyph = text(badge, icon, Enum.Font.GothamBlack, 20, Color3.new(1, 1, 1), Z + 4)
		glyph.Size = UDim2.fromScale(1, 1)
		local label = text(r, name, Enum.Font.GothamBlack, 16, UiKit.INK, Z + 3)
		label.Position = UDim2.fromOffset(54, 0)
		label.Size = UDim2.new(0.5, 0, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		return r
	end

	type Toggle = { key: string, knob: Frame, pill: TextButton, word: TextLabel }
	local toggles: { Toggle } = {}
	local function paintToggle(t: Toggle)
		local on = (current :: any)[t.key] == true
		t.pill.BackgroundColor3 = if on then ON else OFF
		t.knob.Position = if on then UDim2.new(1, -25, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		t.word.Text = if on then "ON" else "OFF"
		t.word.Position = if on then UDim2.fromOffset(8, 0) else UDim2.new(1, -34, 0, 0)
	end
	local function toggle(icon: string, tint: Color3, name: string, key: string)
		local r = row(icon, tint, name)
		local pill = Instance.new("TextButton")
		pill.AnchorPoint = Vector2.new(1, 0.5)
		pill.Position = UDim2.new(1, -10, 0.5, 0)
		pill.Size = UDim2.fromOffset(64, 28)
		pill.AutoButtonColor = false
		pill.Text = ""
		pill.ZIndex = Z + 3
		pill.Parent = r
		UiKit.Corner(pill, 14)
		UiKit.Stroke(pill, Color3.fromRGB(12, 16, 28), 2, 0)
		local word = text(pill, "", Enum.Font.GothamBlack, 11, Color3.new(1, 1, 1), Z + 4)
		word.Size = UDim2.fromOffset(26, 28)
		local knob = Instance.new("Frame")
		knob.AnchorPoint = Vector2.new(0, 0.5)
		knob.Size = UDim2.fromOffset(22, 22)
		knob.BackgroundColor3 = Color3.new(1, 1, 1)
		knob.BorderSizePixel = 0
		knob.ZIndex = Z + 5
		knob.Parent = pill
		UiKit.Corner(knob, 11)
		local t = { key = key, knob = knob, pill = pill, word = word }
		pill.Activated:Connect(function()
			(current :: any)[key] = not (current :: any)[key]
			paintToggle(t)
			preview(key)
			queueSave()
		end)
		table.insert(toggles, t)
		paintToggle(t)
	end

	type Slider = { key: string, fill: Frame, knob: Frame, value: TextLabel }
	local sliders: { Slider } = {}
	local dragging: { track: Frame, s: Slider }? = nil
	local function paintSlider(s: Slider)
		local v = (current :: any)[s.key] :: number
		s.fill.Size = UDim2.fromScale(v, 1)
		s.knob.Position = UDim2.fromScale(v, 0.5)
		s.value.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
	end
	local function slider(icon: string, tint: Color3, name: string, key: string)
		local r = row(icon, tint, name)
		local track = Instance.new("Frame")
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.Position = UDim2.new(1, -62, 0.5, 0)
		track.Size = UDim2.new(0.42, 0, 0, 12)
		track.BackgroundColor3 = UiKit.SHELL_DEEP
		track.BorderSizePixel = 0
		track.ZIndex = Z + 3
		track.Parent = r
		UiKit.Corner(track, 6)
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = ACCENT
		fill.BorderSizePixel = 0
		fill.ZIndex = Z + 4
		fill.Parent = track
		UiKit.Corner(fill, 6)
		local knob = Instance.new("Frame")
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Size = UDim2.fromOffset(20, 20)
		knob.BackgroundColor3 = Color3.new(1, 1, 1)
		knob.BorderSizePixel = 0
		knob.ZIndex = Z + 5
		knob.Parent = track
		UiKit.Corner(knob, 10)
		UiKit.Stroke(knob, Color3.fromRGB(12, 16, 28), 2, 0)
		local value = text(r, "", Enum.Font.GothamBlack, 14, UiKit.INK, Z + 3)
		value.AnchorPoint = Vector2.new(1, 0.5)
		value.Position = UDim2.new(1, -10, 0.5, 0)
		value.Size = UDim2.fromOffset(46, 20)
		value.TextXAlignment = Enum.TextXAlignment.Right
		local s = { key = key, fill = fill, knob = knob, value = value }
		-- Tıklama alanı: iz + düğme (dokunmatikte ince çubuğu tutturmak zor)
		local hit = Instance.new("TextButton")
		hit.AnchorPoint = Vector2.new(0, 0.5)
		hit.Position = UDim2.new(0, -10, 0.5, 0)
		hit.Size = UDim2.new(1, 20, 0, 36)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = Z + 6
		hit.Parent = track
		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = { track = track, s = s }
				local x = (input.Position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
				;(current :: any)[key] = math.clamp(x, 0, 1)
				paintSlider(s)
				preview(key)
			end
		end)
		table.insert(sliders, s)
		paintSlider(s)
	end

	section("AUDIO")
	slider("♪", Color3.fromRGB(150, 90, 255), "Music", "music")
	slider("🔊", Color3.fromRGB(60, 160, 255), "Sound Effects", "sfx")
	section("GAMEPLAY")
	toggle("≈", Color3.fromRGB(255, 150, 40), "Camera Shake", "shake")
	toggle("🐾", Color3.fromRGB(255, 100, 170), "Other Players' Pets", "pets")
	toggle("🐶", Color3.fromRGB(255, 170, 90), "My Pets", "myPets")
	section("GRAPHICS")
	toggle("⚡", Color3.fromRGB(80, 200, 120), "Low Graphics", "lowGfx")

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		local d = dragging
		if d and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local x = (input.Position.X - d.track.AbsolutePosition.X) / math.max(1, d.track.AbsoluteSize.X)
			;(current :: any)[d.s.key] = math.clamp(x, 0, 1)
			paintSlider(d.s)
			preview(d.s.key)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = nil
			queueSave()
		end
	end))

	-- Profil sonradan gelince (ya da başlangıç ekranında değişince) güncelle
	local function syncFromAttributes()
		if dragging then
			return
		end
		read()
		for _, s in sliders do
			paintSlider(s)
		end
		for _, t in toggles do
			paintToggle(t)
		end
		setLowGraphics(current.lowGfx)
	end
	for _, attr in { "SettingMusic", "SettingSfx", "SettingShake", "SettingPets", "SettingMyPets", "SettingLowGfx" } do
		table.insert(conns, player:GetAttributeChangedSignal(attr):Connect(syncFromAttributes))
	end
	setLowGraphics(current.lowGfx)

	close.Activated:Connect(function()
		root.Visible = false
	end)

	local function open()
		syncFromAttributes()
		root.Visible = true
	end
	return {
		Open = open,
		Toggle = function()
			if root.Visible then
				root.Visible = false
			else
				open()
			end
		end,
		Destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			setLowGraphics(false)
			root:Destroy()
		end,
	}
end

return SettingsPanel
