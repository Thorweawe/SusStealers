--!strict
--[[
	Yükseltme penceresi. Üssündeki kulübenin önüne basınca açılıyor,
	uzaklaşınca kapanıyor.

	Seviyeler oyuncunun niteliklerinden okunuyor (UpgradeService yazıyor),
	maliyet ve etki Config'ten hesaplanıyor. Satın alma UpgradeBuy
	remote'una gidiyor; doğrulamanın tamamı sunucuda.

	═══ NEDEN YENİDEN YAZILDI ══════════════════════════════════════════════

	Görsel hatalar vardı:
	  - "NEXT LEVEL / NEXT FLOOR" yazısı düğmeyle AYNI yere konmuştu; fiyatın
	    arkasında soluk bir yazı, "LOCKED"ın üstünde "NEXT FLOOR" okunuyordu.
	  - Düğme her tıklamada ilk boyutundan büyük bir boyuta tweenleniyordu
	    ve bir daha küçülmüyordu.
	  - Panel açılış animasyonu içeriğin tasarlandığı genişlikten farklı
	    bir genişliğe gidiyordu.

	Artık diğer pencerelerle aynı dilde (UiKit): başlık bandı, kart
	satırlar, kabartma düğmeler. Her satır yükseltmenin NE YAPTIĞINI
	sayıyla söylüyor ("8.8 → 9.0"); eskiden yalnızca adı vardı ve oyuncu
	neye para verdiğini bilmiyordu.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local UpgradePanel = {}

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(236, 196, 92)
local PIP_SLOTS = 12
local Z = 30

-- Her yükseltmenin kendi mürettebat rengi: satırlar birbirinden ayrılsın
local TINT: { [string]: Color3 } = {
	ConveyorSpeed = UiKit.CREW.CYAN:Lerp(Color3.fromRGB(40, 60, 70), 0.25),
	UnitGuard = UiKit.CREW.GREEN:Lerp(UiKit.CREW.LIME, 0.35),
	CarrySpeed = UiKit.CREW.ORANGE,
	LockPower = UiKit.CREW.PURPLE:Lerp(UiKit.CREW.PINK, 0.3),
}

--[[
	Etki metni: şimdiki değer → sonraki seviyedeki değer. Config'teki
	formüller sunucunun kullandıklarıyla aynı, yani yazan sayı gerçek.
]]
type Effect = { label: string, value: (level: number) -> string }

local EFFECT: { [string]: Effect } = {
	ConveyorSpeed = {
		label = "New crewmate every",
		value = function(level)
			return string.format("%.1fs", Config.GetConveyorInterval(level))
		end,
	},
	UnitGuard = {
		label = "New crewmates safe for",
		value = function(level)
			return string.format("%ds", Config.GetSafeSeconds(level))
		end,
	},
	CarrySpeed = {
		label = "Carry speed",
		value = function(level)
			return string.format("%.1f", Config.GetCarryWalkSpeed(level))
		end,
	},
	LockPower = {
		label = "Lock / cooldown",
		value = function(level)
			local duration, cooldown = Config.GetLockValues(level)
			return string.format("%ds / %ds", math.floor(duration), math.floor(cooldown))
		end,
	},
}

--[[
	Tetik alanının yarıçapı. 11 studda panel kulübenin epey uzağından
	açılıyordu; 6'da kulübenin önüne GELMEK gerekiyor — açılması bir
	niyet, kaza değil.
]]
local REACH = 6

export type Panel = {
	Update: () -> (),
	Destroy: () -> (),
}

type Row = {
	def: Config.UpgradeDef,
	level: TextLabel,
	effect: TextLabel,
	pips: { Frame },
	holder: Frame,
	button: TextButton,
	price: TextLabel,
	tint: Color3,
}

local ROW_H = 64
local WIDTH = 460

function UpgradePanel.Create(screen: ScreenGui): Panel
	local rowCount = #Config.Upgrades + 1
	local height = 64 + rowCount * (ROW_H + 8) + 8

	local root = UiKit.Window(screen, "UpgradePanel", GOLD)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.55, 0)
	root.Size = UDim2.fromOffset(WIDTH, height)
	root.Visible = false
	root.ZIndex = Z

	-- Açılış animasyonu ölçeği; boyuta dokunmuyor, içerik hep aynı düzende
	local pop = Instance.new("UIScale")
	pop.Parent = root

	-- ─── Başlık bandı ───────────────────────────────────────────────────────

	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 52)
	band.BackgroundColor3 = GOLD:Lerp(Color3.new(0, 0, 0), 0.62)
	band.BorderSizePixel = 0
	band.ZIndex = Z + 1
	band.Parent = root
	UiKit.Corner(band, 14)
	local bandFoot = Instance.new("Frame")
	bandFoot.Position = UDim2.new(0, 0, 1, -14)
	bandFoot.Size = UDim2.new(1, 0, 0, 14)
	bandFoot.BackgroundColor3 = band.BackgroundColor3
	bandFoot.BorderSizePixel = 0
	bandFoot.ZIndex = Z + 1
	bandFoot.Parent = band

	--[[ Başlıktaki mürettebat: tezgâhın arkasındaki satıcıyla aynı renk,
	     "o adamdan alıyorum" bilgisini veriyor. ]]
	local badge = Instance.new("Frame")
	badge.Position = UDim2.fromOffset(14, 10)
	badge.Size = UDim2.fromOffset(32, 32)
	badge.BackgroundTransparency = 1
	badge.ZIndex = Z + 2
	badge.Parent = band
	UiKit.Crewmate(badge, 30, Color3.fromRGB(122, 112, 148))

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(56, 6)
	title.Size = UDim2.new(1, -100, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = GOLD
	title.TextStrokeTransparency = 0.6
	title.Text = "UPGRADES"
	title.ZIndex = Z + 2
	title.Parent = band

	local hint = Instance.new("TextLabel")
	hint.Position = UDim2.fromOffset(56, 30)
	hint.Size = UDim2.new(1, -100, 0, 16)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = UiKit.MUTED
	hint.Text = "Reset on rebirth · each new floor doubles every cap"
	hint.ZIndex = Z + 2
	hint.Parent = band

	-- ─── Satırlar ───────────────────────────────────────────────────────────

	local list = Instance.new("Frame")
	list.Position = UDim2.fromOffset(12, 62)
	list.Size = UDim2.new(1, -24, 1, -70)
	list.BackgroundTransparency = 1
	list.ZIndex = Z + 1
	list.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local buyRemote = Net.Get("UpgradeBuy")
	local rows: { Row } = {}

	local function makeCard(order: number, accent: Color3): Frame
		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.Size = UDim2.new(1, 0, 0, ROW_H)
		card.BackgroundColor3 = accent:Lerp(UiKit.ROW, 0.86)
		card.BorderSizePixel = 0
		card.ZIndex = Z + 2
		card.Parent = list
		UiKit.Corner(card, 12)
		UiKit.Stroke(card, accent, 1.2, 0.6)
		return card
	end

	local function makeButton(card: Frame, tint: Color3): (Frame, TextButton, TextLabel)
		local holder, button = UiKit.Raised(card, "Buy", tint, UDim2.fromOffset(112, 42), 10)
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -10, 0.5, 0)
		holder.ZIndex = Z + 3

		local price = Instance.new("TextLabel")
		price.Size = UDim2.fromScale(1, 1)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.GothamBlack
		price.TextSize = 15
		price.TextColor3 = Color3.new(1, 1, 1)
		price.TextStrokeTransparency = 0.5
		price.Text = "—"
		price.ZIndex = Z + 6
		price.Parent = button
		return holder, button, price
	end

	for index, def in Config.Upgrades do
		local tint = TINT[def.id] or GOLD
		local card = makeCard(index, tint)

		local icon = Instance.new("Frame")
		icon.Position = UDim2.fromOffset(10, 10)
		icon.Size = UDim2.fromOffset(44, 44)
		icon.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.55)
		icon.BorderSizePixel = 0
		icon.ZIndex = Z + 3
		icon.Parent = card
		UiKit.Corner(icon, 10)
		if def.id == "CarrySpeed" then
			UiKit.Boot(icon, 30, tint:Lerp(Color3.new(1, 1, 1), 0.4))
		elseif def.id == "ConveyorSpeed" then
			UiKit.Crate(icon, 28, tint:Lerp(Color3.new(1, 1, 1), 0.4))
		else
			UiKit.Crewmate(icon, 30, tint:Lerp(Color3.new(1, 1, 1), 0.4))
		end

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(64, 7)
		name.Size = UDim2.new(1, -200, 0, 18)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBlack
		name.TextSize = 15
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = UiKit.INK
		name.Text = def.name
		name.ZIndex = Z + 3
		name.Parent = card

		-- Seviye adın sağında, kendi renginde; adla aynı etikette değil ki
		-- uzun adda kesilmesin
		local level = Instance.new("TextLabel")
		level.AnchorPoint = Vector2.new(1, 0)
		level.Position = UDim2.new(1, -132, 0, 7)
		level.Size = UDim2.fromOffset(60, 18)
		level.BackgroundTransparency = 1
		level.Font = Enum.Font.GothamBlack
		level.TextSize = 13
		level.TextXAlignment = Enum.TextXAlignment.Right
		level.TextColor3 = tint
		level.ZIndex = Z + 3
		level.Parent = card

		local effect = Instance.new("TextLabel")
		effect.Position = UDim2.fromOffset(64, 25)
		effect.Size = UDim2.new(1, -200, 0, 15)
		effect.BackgroundTransparency = 1
		effect.Font = Enum.Font.GothamMedium
		effect.TextSize = 11
		effect.TextXAlignment = Enum.TextXAlignment.Left
		effect.TextTruncate = Enum.TextTruncate.AtEnd
		effect.TextColor3 = UiKit.MUTED
		effect.RichText = true
		effect.ZIndex = Z + 3
		effect.Parent = card

		--[[
			Seviye kutucukları: "12 seviyeden 4'ü" bilgisi saymadan okunuyor.
			Tavan kat açtıkça iki katına çıkıyor (6/12/24); yirmi dört kutucuk
			sığmaz, o yüzden sabit sayıda kutucuk ve her biri oransal.
		]]
		local pipArea = Instance.new("Frame")
		pipArea.Position = UDim2.fromOffset(64, 44)
		pipArea.Size = UDim2.new(1, -200, 0, 9)
		pipArea.BackgroundTransparency = 1
		pipArea.ZIndex = Z + 3
		pipArea.Parent = card
		local pipLayout = Instance.new("UIListLayout")
		pipLayout.FillDirection = Enum.FillDirection.Horizontal
		pipLayout.Padding = UDim.new(0, 3)
		pipLayout.Parent = pipArea

		local pips: { Frame } = {}
		local pipCount = math.min(PIP_SLOTS, Config.GetUpgradeCeiling(def))
		for slot = 1, pipCount do
			local pip = Instance.new("Frame")
			pip.LayoutOrder = slot
			pip.Size = UDim2.new(1 / pipCount, -3, 1, 0)
			pip.BackgroundColor3 = UiKit.DIM
			pip.BorderSizePixel = 0
			pip.ZIndex = Z + 4
			pip.Parent = pipArea
			UiKit.Corner(pip, 3)
			table.insert(pips, pip)
		end

		local holder, button, price = makeButton(card, tint)

		--[[
			Tıklama doğrudan remote'a gidiyor. Parası yetmeyen oyuncuda da
			düğme kapanmıyor: sunucu reddedip fiyatı söyleyen bir bildirim
			basıyor, istemcide susmak oyuncuya hiçbir şey anlatmaz.
		]]
		local id = def.id
		button.MouseButton1Click:Connect(function()
			if button.Active then
				buyRemote:FireServer(id)
			end
		end)

		table.insert(rows, {
			def = def, level = level, effect = effect, pips = pips,
			holder = holder, button = button, price = price, tint = tint,
		})
	end

	-- ─── Yeni kat satırı ────────────────────────────────────────────────────
	--[[
		Kat artık YALNIZCA burada alınıyor. Üslerdeki satın alma pedi
		kaldırıldı ("FLOOR 3 · Needs 2 rebirth" tabelası her üste bir ışık
		sütunu ve yazı koyuyordu).
	]]
	local floorCard = makeCard(#Config.Upgrades + 1, GOLD)
	local floorIcon = Instance.new("Frame")
	floorIcon.Position = UDim2.fromOffset(10, 10)
	floorIcon.Size = UDim2.fromOffset(44, 44)
	floorIcon.BackgroundColor3 = GOLD:Lerp(Color3.new(0, 0, 0), 0.55)
	floorIcon.BorderSizePixel = 0
	floorIcon.ZIndex = Z + 3
	floorIcon.Parent = floorCard
	UiKit.Corner(floorIcon, 10)
	-- Kat ikonu: üst üste üç levha
	for i = 0, 2 do
		local slab = Instance.new("Frame")
		slab.AnchorPoint = Vector2.new(0.5, 0.5)
		slab.Position = UDim2.new(0.5, 0, 0.5, 10 - i * 9)
		slab.Size = UDim2.fromOffset(28 - i * 4, 6)
		slab.BackgroundColor3 = GOLD:Lerp(Color3.new(1, 1, 1), 0.2 + i * 0.15)
		slab.BorderSizePixel = 0
		slab.ZIndex = Z + 4
		slab.Parent = floorIcon
		UiKit.Corner(slab, 2)
	end

	local floorName = Instance.new("TextLabel")
	floorName.Position = UDim2.fromOffset(64, 10)
	floorName.Size = UDim2.new(1, -200, 0, 20)
	floorName.BackgroundTransparency = 1
	floorName.Font = Enum.Font.GothamBlack
	floorName.TextSize = 15
	floorName.TextXAlignment = Enum.TextXAlignment.Left
	floorName.TextColor3 = GOLD
	floorName.ZIndex = Z + 3
	floorName.Parent = floorCard

	local floorNote = Instance.new("TextLabel")
	floorNote.Position = UDim2.fromOffset(64, 32)
	floorNote.Size = UDim2.new(1, -200, 0, 16)
	floorNote.BackgroundTransparency = 1
	floorNote.Font = Enum.Font.GothamMedium
	floorNote.TextSize = 11
	floorNote.TextXAlignment = Enum.TextXAlignment.Left
	floorNote.TextColor3 = UiKit.MUTED
	floorNote.ZIndex = Z + 3
	floorNote.Parent = floorCard

	local _, floorButton, floorPrice = makeButton(floorCard, GOLD)
	local floorRemote = Net.Get("FloorBuy")
	floorButton.MouseButton1Click:Connect(function()
		if floorButton.Active then
			floorRemote:FireServer()
		end
	end)

	-- Düğmenin hâli: renk + yazı + tıklanabilirlik tek yerde
	local function setButton(button: TextButton, price: TextLabel, text: string, tint: Color3?)
		price.Text = text
		button.BackgroundColor3 = tint or UiKit.DIM
		button.Active = tint ~= nil
		-- Kabartmanın degradesi ve kenarı da aynı renge dönsün (UiKit.Raised)
		local base = tint or UiKit.DIM
		local grad = button:FindFirstChildOfClass("UIGradient")
		if grad then
			grad.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), 0.22), base:Lerp(Color3.new(0, 0, 0), 0.18))
		end
		local edge = button:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = base:Lerp(Color3.new(0, 0, 0), 0.55)
		end
	end

	-- ─── Güncelleme ─────────────────────────────────────────────────────────

	local function number(name: string, default: number): number
		local value = player:GetAttribute(name)
		return if typeof(value) == "number" then value else default
	end

	local function refresh()
		local floors = number("UpgradeFloors", 1)
		local cash = number("Cash", 0)

		for _, row in rows do
			local lvl = number("Upg_" .. row.def.id, 0)
			local maxLevel = Config.GetUpgradeMaxLevel(row.def, floors)

			row.level.Text = string.format("Lv %d/%d", lvl, maxLevel)

			local filled = math.floor(#row.pips * (lvl / math.max(1, maxLevel)) + 0.0001)
			for i, pip in row.pips do
				pip.BackgroundColor3 = if i <= filled then row.tint else UiKit.DIM
			end

			local effect = EFFECT[row.def.id]
			local price = Config.GetUpgradeCost(row.def.id, lvl, floors)
			if effect then
				if price then
					-- Şimdi → sonraki: yeşil ok ve sonraki değer
					row.effect.Text = string.format('%s %s  <font color="#80E096">→ %s</font>',
						effect.label, effect.value(lvl), effect.value(lvl + 1))
				else
					row.effect.Text = effect.label .. " " .. effect.value(lvl)
				end
			end

			if price then
				-- Parası yetmiyorsa düğme sönük ama tıklanabilir: sunucu fiyatı söylüyor
				setButton(row.button, row.price, "$" .. Config.FormatCash(price), row.tint)
				row.button.BackgroundTransparency = if cash >= price then 0 else 0.35
			elseif floors < Config.MaxFloors then
				setButton(row.button, row.price, "NEXT FLOOR", nil)
				row.button.BackgroundTransparency = 0
			else
				setButton(row.button, row.price, "MAX", nil)
				row.button.BackgroundTransparency = 0
			end
		end

		-- Kat satırı: rebirth yetmiyor / alınabilir / hepsi alınmış
		local bought = number("FloorsBought", 0)
		local rebirths = number("Rebirths", 0)
		local nextFloor = Config.GetNextFloor(bought)
		if not nextFloor then
			floorName.Text = "ALL FLOORS OPEN"
			floorNote.Text = "Every upgrade cap is at its highest"
			setButton(floorButton, floorPrice, "MAX", nil)
		elseif rebirths < nextFloor.rebirths then
			floorName.Text = string.format("NEW FLOOR %d", nextFloor.floor)
			floorNote.Text = string.format("Needs %d rebirth%s (you have %d)",
				nextFloor.rebirths, if nextFloor.rebirths == 1 then "" else "s", rebirths)
			setButton(floorButton, floorPrice, "LOCKED", nil)
		else
			floorName.Text = string.format("NEW FLOOR %d", nextFloor.floor)
			floorNote.Text = "More podiums + doubles every upgrade cap"
			setButton(floorButton, floorPrice, "$" .. Config.FormatCash(nextFloor.cost), GOLD)
		end
	end

	--[[
		Kendi üssümüzün tetik alanına yakın mıyız? Yalnızca KENDİ üssümüzdeki
		alan sayılıyor: rakibin kulübesinde açılsa arayüz yalan söylerdi
		(sunucu zaten reddediyor).
	]]
	local function nearOwnBooth(): boolean
		local char = player.Character
		local rootPart = char and char:FindFirstChild("HumanoidRootPart")
		if not (rootPart and rootPart:IsA("BasePart")) then
			return false
		end
		local plots = workspace:FindFirstChild("Plots")
		local assigned = player:GetAttribute("Plot")
		if not (plots and typeof(assigned) == "string") then
			return false
		end
		local plot = plots:FindFirstChild(assigned)
		local booth = plot and plot:FindFirstChild("UpgradeBooth")
		local zone = booth and booth:FindFirstChild("UpgradeZone")
		if not (zone and zone:IsA("BasePart")) then
			return false
		end
		-- Yükseklik farkı büyükse (üst kattan bakıyor) açılmasın
		local delta = rootPart.Position - zone.Position
		if math.abs(delta.Y) > 12 then
			return false
		end
		return Vector2.new(delta.X, delta.Z).Magnitude <= REACH
	end

	local shown = false

	local function update()
		local near = nearOwnBooth()
		if near ~= shown then
			shown = near
			root.Visible = near
			if near then
				-- Küçükten büyüyor; boyut değil ölçek, düzen bozulmuyor
				pop.Scale = 0.9
				TweenService:Create(pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }):Play()
			end
		end
		if near and root.Visible then
			refresh()
		end
	end

	return {
		Update = update,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return UpgradePanel
