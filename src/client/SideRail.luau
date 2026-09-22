--!strict
--[[
	Sol kenardaki büyük düğmeler: SHOP, INDEX, QUESTS.

	NEDEN VAR: mağaza hiç görünmüyordu, indeks yalnızca C tuşuyla
	açılıyordu, görevler de ekranın solunu sürekli kaplıyordu. Türün
	oyuncusu bu şeyleri ekranın solunda, büyük ve renkli bir düğmede
	arıyor.

	Düğmeler UiKit.WideButton'dan: gövde, gölge ve basma davranışı her
	yerde aynı olsun diye. Buradaki iş sadece hangi düğme, hangi renk,
	hangi ikon ve tıklanınca ne olacağı.

	Yeni bir düğme eklemek tek kayıt: RAIL listesine bir satır. Rozet
	(kırmızı sayı) her düğmede hazır, SetBadge ile açılıyor.
]]

local UiKit = require(script.Parent.UiKit)

local SideRail = {}

export type Spec = {
	name: string,
	label: string,
	tint: Color3,
	icon: string,      -- crate | crewmate | coin | vial | boot | flame | clipboard
	onClick: () -> (),
}

export type Rail = {
	SetBadge: (name: string, count: number) -> (),
	Destroy: () -> (),
}

local BUTTON_H = 60
local GAP = 8

--[[ Yuvaya ikonu çizer. ]]
local function drawIcon(slot: Frame, icon: string, tint: Color3)
	UiKit.ClearSlot(slot)
	if icon == "crate" then
		UiKit.Crate(slot, 26, tint)
	elseif icon == "crewmate" then
		UiKit.Crewmate(slot, 26, tint)
	elseif icon == "coin" then
		UiKit.Coin(slot, 26, tint)
	elseif icon == "vial" then
		UiKit.Vial(slot, 28, tint, 0.7, true)
	elseif icon == "boot" then
		UiKit.Boot(slot, 26, tint)
	elseif icon == "clipboard" then
		UiKit.Clipboard(slot, 28, tint)
	else
		UiKit.Flame(slot, 28, tint)
	end
end

--[[
	Rayı kurar.

	`name` HudToggle'ın gizleme listesindeki adla aynı olmalı; öyle olmazsa
	arayüzü gizleme düğmesi bu rayı bulamaz.
]]
function SideRail.Create(screen: ScreenGui, name: string, specs: { Spec }): Rail
	--[[
		Alt sola, nakit haplarının hemen üstüne yaslı: 22 kenar + 108 hap +
		12 ara = 142. Görevler artık pencere olduğu için solda başka bir şey
		yok; ray sıralama tablosuyla da çakışmıyor (tablo sağ üstte).
	]]
	local rail = Instance.new("Frame")
	rail.Name = name
	rail.AnchorPoint = Vector2.new(0, 1)
	rail.Position = UDim2.new(0, 22, 1, -142)
	rail.Size = UDim2.fromOffset(196, #specs * BUTTON_H + (#specs - 1) * GAP)
	rail.BackgroundTransparency = 1
	rail.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = rail

	local badges: { [string]: TextLabel } = {}

	for index, spec in specs do
		local holder, button, slot = UiKit.WideButton(rail, spec.name, spec.tint, spec.label)
		holder.LayoutOrder = index

		--[[
			İkon yuvası düğmenin kendi renginin koyusu; ikon ise açık tonu.
			Aynı renkte olsalardı ikon dolgunun içinde kaybolurdu.
		]]
		drawIcon(slot, spec.icon, spec.tint:Lerp(Color3.new(1, 1, 1), 0.55))

		badges[spec.name] = UiKit.Badge(button)

		button.MouseButton1Click:Connect(spec.onClick)
	end

	return {
		SetBadge = function(buttonName: string, count: number)
			local badge = badges[buttonName]
			if badge then
				badge.Visible = count > 0
				badge.Text = if count > 9 then "9+" else tostring(count)
			end
		end,
		Destroy = function()
			rail:Destroy()
		end,
	}
end

return SideRail
