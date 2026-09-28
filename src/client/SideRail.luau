--!strict
--[[
	Sol menü: oyunun bütün pencereleri TEK yerde, aynı düğme tipinde.

	2026-09-28 (Yusuf: "ekranda aynı anda çok şey var", "arayüz tutarlı olsun"):
	  - Eskiden solda dört geniş renkli düğme, sağ ortada ayrıca Envanter ve
	    Rebirth vardı (iki farklı düğme tipi, iki ayrı yer). Şimdi hepsi
	    burada, 2 sütunlu kare ızgara (UiKit.IconButton).
	  - İKİNCİL seviye: düğme gövdeleri koyu/sönük, yalnızca ikonlar renkli.
	    Ekranda tam renk yalnızca hedef kartında ve süren olayda (birincil).
	  - KADEMELİ AÇILMA: yeni oyuncu ilk dakikada her şeyi görmüyor. Her
	    düğmenin `unlockAt`'i var (tamamlanan öğretici adımı, "TutorialStep"
	    niteliği). Açılan düğme büyüyerek geliyor ve üstünde "NEW" yazıyor,
	    ilk basışta kayboluyor. Öğreticiyi atlayan / bitiren her şeyi görüyor.

	Ray alt sola, nakit haplarının üstüne yaslı; yukarı doğru büyüyor.

	2026-09-28 (mağaza dili): düğmeler renkli gradyan + kalın koyu kenar,
	ikonlar 3B render (UiArt "Nav_*"), düğmenin üstünden taşıyor ve hafifçe
	süzülüyor; ara ara üstlerinden parıltı geçiyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local FancyKit = require(script.Parent.FancyKit)
local UiArt = require(script.Parent.UiArt)
local UiKit = require(script.Parent.UiKit)

-- Düğme adı → 3B ikon (UiArt.Icon)
local ART: { [string]: string } = {
	Shop = "Nav_Shop",
	Inventory = "Nav_Items",
	Pass = "Nav_Pass",
	Index = "Nav_Index",
}
local OUTLINE = Color3.fromRGB(22, 20, 34)

local SideRail = {}

export type Spec = {
	name: string,
	label: string,
	tint: Color3,
	icon: string,      -- UiKit.Icon adı: bag | book | clipboard | coin | ...
	onClick: () -> (),
	unlockAt: number?, -- bu kadar öğretici adımı bitince görünüyor (yoksa hep)
}

export type Rail = {
	SetBadge: (name: string, count: number) -> (),
	Destroy: () -> (),
}

-- 2026-09-28: tek sütun, yukarıdan aşağı (SHOP, ITEMS, PASS, INDEX). Düğmeler
-- biraz küçük: telefonda (joystick bandı kaldırması dahil) üst şeride değmesin
local BUTTON = Vector2.new(64, 66)
local GAP = 6
local COLUMNS = 1
local BODY = Color3.fromRGB(40, 46, 68)

local player = Players.LocalPlayer

local function step(): number
	local v = player:GetAttribute("TutorialStep")
	if typeof(v) ~= "number" then
		return 0
	end
	-- Atlanan öğretici (-1) ya da bitmiş: hepsi açık
	return if v < 0 then #Config.Tutorial else v
end

function SideRail.Create(screen: ScreenGui, name: string, specs: { Spec }): Rail
	local rail = Instance.new("Frame")
	rail.Name = name
	rail.AnchorPoint = Vector2.new(0, 1)
	rail.Position = UDim2.new(0, 22, 1, -142)
	local rows = math.ceil(#specs / COLUMNS)
	rail.Size = UDim2.fromOffset(COLUMNS * BUTTON.X + (COLUMNS - 1) * GAP, rows * BUTTON.Y + (rows - 1) * GAP)
	rail.BackgroundTransparency = 1
	rail.Parent = screen
	local driver = FancyKit.driver(rail)

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(BUTTON.X, BUTTON.Y)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = COLUMNS
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	-- Alttan dolsun: az düğme varken haplara yakın dursun
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = rail

	type Entry = { spec: Spec, holder: Frame, button: TextButton, badge: TextLabel, newTag: TextLabel, shown: boolean }
	local entries: { [string]: Entry } = {}

	for index, spec in specs do
		-- İkincil seviye: gövde koyu (rengin izi), ikon parlak
		local body = BODY:Lerp(spec.tint, 0.28)
		local holder, button, slot = UiKit.IconButton(rail, spec.name, body, spec.label, BUTTON)
		holder.LayoutOrder = index
		UiKit.ClearSlot(slot)
		slot.Size = UDim2.fromOffset(34, 34)
		local art = UiArt.Image("Icon", ART[spec.name] or "")
		if art ~= "" then
			-- Mağaza dili: renkli gövde, kalın kenar, taşan 3B ikon, parıltı
			button.BackgroundColor3 = Color3.new(1, 1, 1)
			local grad = button:FindFirstChildOfClass("UIGradient")
			if grad then
				grad.Color = ColorSequence.new(spec.tint:Lerp(Color3.new(1, 1, 1), 0.2), spec.tint:Lerp(Color3.new(0, 0, 0), 0.35))
			end
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = OUTLINE
				stroke.Thickness = 3
			end
			FancyKit.halftone(button, Color3.new(1, 1, 1), 0.85, button.ZIndex, true)
			FancyKit.gleam(button, driver, 5, index * 0.7, 0.45)
			local img = Instance.new("ImageLabel")
			img.Name = "Art"
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.new(0.5, 0, 0.5, -3)
			img.Size = UDim2.fromOffset(50, 50)
			img.BackgroundTransparency = 1
			img.Image = art
			img.ZIndex = slot.ZIndex + 2
			img.Parent = slot
			FancyKit.bob(img, driver, 2, 2.6, index * 1.3, 4)
			local label = button:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				label.Font = Enum.Font.FredokaOne
				label.ZIndex = slot.ZIndex + 3
				label.TextStrokeTransparency = 1
				local ls = Instance.new("UIStroke")
				ls.Color = OUTLINE
				ls.Thickness = 2
				ls.Parent = label
			end
		else
			UiKit.Icon(slot, spec.icon, 32, spec.tint:Lerp(Color3.new(1, 1, 1), 0.25))
		end
		local badge = UiKit.Badge(button)

		local newTag = Instance.new("TextLabel")
		newTag.Name = "New"
		newTag.AnchorPoint = Vector2.new(0.5, 0.5)
		newTag.Position = UDim2.new(0.5, 0, 0, 0)
		newTag.Size = UDim2.fromOffset(42, 18)
		newTag.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
		newTag.Font = Enum.Font.FredokaOne
		newTag.TextSize = 13
		newTag.TextColor3 = Color3.fromRGB(40, 24, 0)
		newTag.Text = "NEW"
		newTag.Visible = false
		newTag.ZIndex = 12
		newTag.Parent = holder
		UiKit.Corner(newTag, 9)

		local entry = { spec = spec, holder = holder, button = button, badge = badge, newTag = newTag, shown = true }
		entries[spec.name] = entry
		button.MouseButton1Click:Connect(function()
			newTag.Visible = false
			spec.onClick()
		end)
	end

	--[[ Kademeli açılma: gizli düğme ızgarada yer kaplamıyor. "NEW" yalnızca
	     oyun SIRASINDA açılanlara: nitelik ilk geldiğinde (giriş) açık olanlar
	     sessizce görünüyor. ]]
	local first = true
	local function apply()
		if player:GetAttribute("TutorialStep") == nil then
			-- Profil daha gelmedi: yalnızca hep açık olanlar
			for _, entry in entries do
				local want = (entry.spec.unlockAt or 0) <= 0
				entry.shown = want
				entry.holder.Visible = want
			end
			return
		end
		local done = step()
		for _, entry in entries do
			local want = done >= (entry.spec.unlockAt or 0)
			if want ~= entry.shown then
				entry.shown = want
				entry.holder.Visible = want
				if want and not first then
					-- Yeni açıldı: büyüyerek gel, "NEW" yazısı
					-- 2026-09-28: "NEW yazıları kalksın" — büyüme animasyonu yeterli
					entry.newTag.Visible = false
					local scale = entry.holder:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
					scale.Parent = entry.holder
					scale.Scale = 0.3
					TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				end
			end
		end
		first = false
	end
	for _, entry in entries do
		entry.shown = true
	end
	apply()
	local conn = player:GetAttributeChangedSignal("TutorialStep"):Connect(apply)

	return {
		SetBadge = function(buttonName: string, count: number)
			local entry = entries[buttonName]
			if entry then
				entry.badge.Visible = count > 0
				entry.badge.Text = if count > 9 then "9+" else tostring(count)
			end
		end,
		Destroy = function()
			conn:Disconnect()
			driver.destroy()
			rail:Destroy()
		end,
	}
end

return SideRail
