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
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local UiKit = require(script.Parent.UiKit)

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

local BUTTON = Vector2.new(78, 80)
local GAP = 8
local COLUMNS = 2
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
		slot.Size = UDim2.fromOffset(40, 40)
		UiKit.Icon(slot, spec.icon, 38, spec.tint:Lerp(Color3.new(1, 1, 1), 0.25))
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
					entry.newTag.Visible = true
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
			rail:Destroy()
		end,
	}
end

return SideRail
