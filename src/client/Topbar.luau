--!strict
--[[
	Roblox'un üst şeridine, sohbet düğmesinin hemen sağına iki düğme:

	    [Roblox] [≡ 💬]  [HEDİYE] [GÖZ]

	  HEDİYE — ödül penceresi (günlük seri + oynama süresi). Toplanacak
	           ödül varsa köşesinde kırmızı sayı.
	  GÖZ    — arayüzü gizle/göster (H tuşu da). Eskiden tek başına
	           duruyordu ve Roblox'un düğmelerinden küçüktü.

	═══ YER VE BOYUT ═══════════════════════════════════════════════════════

	Roblox'un kendi düğmeleriyle AYNI boy (44) ve aynı hizada. Konum
	GuiService.TopbarInset'ten: Roblox'un sol düğmelerinin bittiği yeri
	o söylüyor; sohbet kapalıyken ya da sesli sohbet açıkken değişiyor, o
	yüzden değişime bağlı. Eski şeritte (TopbarInset yoksa) 228'e düşüyor.

	Düğmeler KENDİ ScreenGui'lerinde: üst şeridin hizasına inmek için
	IgnoreGuiInset gerekiyor, onu ana HUD'a açmak bütün panelleri kaydırırdı.

	═══ GİZLEME ════════════════════════════════════════════════════════════

	Arayüz öğelerini ADIYLA buluyor, kendi kodlarına dokunmuyor. Nakit,
	bildirimler, öğretici ve taşıma oku gizlenmiyor — oyuncunun o an ne
	yaptığını söyleyen şeyler onlar.
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.UiKit)

local Topbar = {}

local CLUTTER = {
	"Leaderboard",
	"SideRail",
	"MenuDock",
	"MenuOverlay",
	"UnitIndex",
	"ShopPanel",
	"QuestPanel",
	"PetPanel",
	"RewardsPanel",
	"GearPanel",
	"TransitPanel",
	"Hotbar",
}

local BUTTON = 44
local GAP = 12

export type Bar = {
	SetGiftBadge: (count: number) -> (),
	SetHidden: (hidden: boolean) -> (),
	Destroy: () -> (),
}

function Topbar.Create(screen: ScreenGui, onGift: () -> ()): Bar
	local layer = Instance.new("ScreenGui")
	layer.Name = "SusStealersTopbar"
	layer.ResetOnSpawn = false
	layer.IgnoreGuiInset = true
	-- Gizlediği panellerin üstünde kalmalı; yoksa kendini gizleyen bir
	-- düğme geri gelemezdi
	layer.DisplayOrder = 20
	layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	layer.Parent = screen.Parent

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.Size = UDim2.fromOffset(BUTTON * 2 + GAP, BUTTON + 4)
	row.BackgroundTransparency = 1
	row.Parent = layer

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = row

	-- ─── Hediye ─────────────────────────────────────────────────────────────

	local giftHolder, giftButton = UiKit.Raised(row, "Gift", UiKit.CREW.PINK, UDim2.fromOffset(BUTTON, BUTTON + 4), 12)
	giftHolder.LayoutOrder = 1
	local giftSlot = Instance.new("Frame")
	giftSlot.Size = UDim2.fromScale(1, 1)
	giftSlot.BackgroundTransparency = 1
	giftSlot.ZIndex = 5
	giftSlot.Parent = giftButton
	UiKit.Gift(giftSlot, 30, Color3.fromRGB(255, 120, 170))
	local giftBadge = UiKit.Badge(giftButton)
	giftButton.MouseButton1Click:Connect(onGift)

	-- ─── Göz ────────────────────────────────────────────────────────────────

	local eyeHolder, eyeButton = UiKit.Raised(row, "HideUi", Color3.fromRGB(70, 82, 98), UDim2.fromOffset(BUTTON, BUTTON + 4), 12)
	eyeHolder.LayoutOrder = 2
	local eyeSlot = Instance.new("Frame")
	eyeSlot.Size = UDim2.fromScale(1, 1)
	eyeSlot.BackgroundTransparency = 1
	eyeSlot.ZIndex = 5
	eyeSlot.Parent = eyeButton

	-- İpucu düğmelerin ALTINDA: sağında şeridin devamı var
	local tip = Instance.new("TextLabel")
	tip.AnchorPoint = Vector2.new(0.5, 0)
	tip.Position = UDim2.new(0.5, 0, 1, 6)
	tip.Size = UDim2.fromOffset(120, 18)
	tip.BackgroundTransparency = 1
	tip.Font = Enum.Font.GothamBold
	tip.TextSize = 12
	tip.TextColor3 = UiKit.MUTED
	tip.TextStrokeTransparency = 0.5
	tip.TextTransparency = 1
	tip.ZIndex = 6
	tip.Parent = eyeHolder

	local hidden = false
	--[[
		Gizlenmeden önceki görünürlüğü hatırlıyoruz: geri açınca o sırada
		zaten kapalı olan bir pencere zorla açılmasın.
	]]
	local restore: { [Instance]: boolean } = {}

	local function apply()
		if hidden then
			table.clear(restore)
			for _, name in CLUTTER do
				local element = screen:FindFirstChild(name)
				if element and element:IsA("GuiObject") then
					restore[element] = element.Visible
					element.Visible = false
				end
			end
		else
			for element, wasVisible in restore do
				if element.Parent then
					(element :: GuiObject).Visible = wasVisible
				end
			end
			table.clear(restore)
		end
		-- Kendini yeniden çizen parçalar (ekipman çubuğu) gizliyken görünmesin
		screen:SetAttribute("UiHidden", hidden)
		UiKit.ClearSlot(eyeSlot)
		UiKit.EyeIcon(eyeSlot, 28, hidden)
		tip.Text = if hidden then "Show UI  (H)" else "Hide UI  (H)"
	end
	apply()

	eyeButton.MouseButton1Click:Connect(function()
		hidden = not hidden
		apply()
	end)
	eyeButton.MouseEnter:Connect(function()
		tip.TextTransparency = 0
	end)
	eyeButton.MouseLeave:Connect(function()
		tip.TextTransparency = 1
	end)

	--[[
		Roblox'un şeridine hizalama. Yeni şeritte (yükseklik 58) Roblox'un
		düğmeleri 44 ve alt kenara yakın; eski şeritte (36) daha küçük.
		Düğmeler Roblox'unkiyle aynı boyda: kabartma (Raised) 4 piksel gölge
		ekliyor, düğmenin kendisi `size` x `size`.
	]]
	local function place()
		local ok, inset = pcall(function()
			return GuiService.TopbarInset
		end)
		local height, x
		if ok and inset and inset.Height > 0 then
			height, x = inset.Height, inset.Min.X
		else
			local topInset = GuiService:GetGuiInset()
			height, x = if topInset.Y > 0 then topInset.Y else 36, 228
		end
		local size = if height >= 50 then BUTTON else math.max(28, height - 6)
		for _, holder in { giftHolder, eyeHolder } do
			holder.Size = UDim2.fromOffset(size, size + 4)
		end
		row.Size = UDim2.fromOffset(size * 2 + GAP, size + 4)
		row.Position = UDim2.fromOffset(x, math.max(2, height - size - 2))
	end
	place()
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
	end)

	-- H kısayolu; sohbete "h" yazarken tetiklenmesin (processed)
	local input = UserInputService.InputBegan:Connect(function(io, processed)
		if processed or io.KeyCode ~= Enum.KeyCode.H then
			return
		end
		hidden = not hidden
		apply()
	end)

	return {
		SetGiftBadge = function(count: number)
			giftBadge.Visible = count > 0
			giftBadge.Text = if count > 9 then "9+" else tostring(count)
		end,
		SetHidden = function(value: boolean)
			hidden = value
			apply()
		end,
		Destroy = function()
			input:Disconnect()
			layer:Destroy()
		end,
	}
end

return Topbar
