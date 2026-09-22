--!strict
--[[
	Sol kenardaki büyük düğmeler: SHOP ve INDEX.

	NEDEN VAR: mağaza hiç görünmüyordu (panel bile yoktu), indeks yalnızca
	C tuşuyla açılıyordu — yani ikisi de pratikte yoktu. Türün oyuncusu bu
	iki şeyi ekranın solunda, büyük ve renkli bir düğmede arıyor.

	Düğmeler UiKit.WideButton'dan: gövde, gölge ve basma davranışı her
	yerde aynı olsun diye. Buradaki iş sadece hangi düğme, hangi renk,
	hangi ikon ve tıklanınca ne olacağı.

	Yeni bir düğme (pet, envanter, günlük ödül) eklemek tek satır: RAIL
	listesine bir kayıt. Sıra LayoutOrder'dan geliyor.
]]

local UiKit = require(script.Parent.UiKit)

local SideRail = {}

export type Spec = {
	name: string,
	label: string,
	tint: Color3,
	icon: string,      -- crate | crewmate | coin | vial | boot | flame
	onClick: () -> (),
}

export type Rail = {
	Destroy: () -> (),
}

--[[ Yuvaya ikonu çizer. ShopPanel'deki eşi ile aynı kalıp. ]]
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
	local rail = Instance.new("Frame")
	rail.Name = name
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.new(0, 22, 0.5, -30)
	rail.Size = UDim2.fromOffset(196, #specs * 68)
	rail.BackgroundTransparency = 1
	rail.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = rail

	for index, spec in specs do
		local holder, button, slot = UiKit.WideButton(rail, spec.name, spec.tint, spec.label)
		holder.LayoutOrder = index

		--[[
			İkon yuvası düğmenin kendi renginin koyusu; ikon ise açık tonu.
			Aynı renkte olsalardı ikon dolgunun içinde kaybolurdu.
		]]
		drawIcon(slot, spec.icon, spec.tint:Lerp(Color3.new(1, 1, 1), 0.55))

		button.MouseButton1Click:Connect(spec.onClick)
	end

	return {
		Destroy = function()
			rail:Destroy()
		end,
	}
end

return SideRail
