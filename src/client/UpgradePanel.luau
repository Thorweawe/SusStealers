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

	Görünüş mağazanın dilinde (CardKit): turuncu başlık şeridi, ışınlı renkli
	kartlar, kalın konturlu yazılar, seviye çubuğu, tıknaz fiyat düğmesi.
	Her kart yükseltmenin NE YAPTIĞINI sayıyla söylüyor ("8.8 → 9.0").
	Kırmızı X pencereyi kulübeden uzaklaşana kadar kapatıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CardKit = require(script.Parent.CardKit)
local UiKit = require(script.Parent.UiKit)

local UpgradePanel = {}

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(240, 170, 30)
local HEADER_COLOR = Color3.fromRGB(245, 140, 30)
local Z = 30

-- Her yükseltmenin kart rengi ve ikonu: kartlar birbirinden ayrılsın
local TINT: { [string]: Color3 } = {
	ConveyorSpeed = Color3.fromRGB(40, 150, 200),
	UnitGuard = Color3.fromRGB(60, 170, 80),
	CarrySpeed = Color3.fromRGB(230, 110, 40),
	LockPower = Color3.fromRGB(140, 80, 220),
}
local ICON: { [string]: string } = {
	ConveyorSpeed = "crate",
	UnitGuard = "crewmate",
	CarrySpeed = "boot",
	LockPower = "lock",
}

--[[
	Etki metni: şimdiki değer → sonraki seviyedeki değer. Config'teki
	formüller sunucunun kullandıklarıyla aynı, yani yazan sayı gerçek.
]]
type Effect = { label: string, value: (level: number) -> string }

local EFFECT: { [string]: Effect } = {
	-- Yükseltme hem aralığı kısaltıyor hem bandı hızlandırıyor (ConveyorService)
	ConveyorSpeed = {
		label = "Crewmate every / belt",
		value = function(level)
			return string.format("%.1fs / %.1fx", Config.GetConveyorInterval(level),
				Config.GetConveyorBeltSpeed(level) / Config.GetConveyorBeltSpeed(0))
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
	effect: TextLabel,
	bar: CardKit.Bar,
	buy: CardKit.Button,
	tint: Color3,
}

local HEADER = 64
local ROW_H = 100
local WIDTH = 600

function UpgradePanel.Create(screen: ScreenGui): Panel
	local rowCount = #Config.Upgrades + 1
	local height = HEADER + 12 + rowCount * (ROW_H + 10) + 30

	local root = UiKit.Window(screen, "UpgradePanel", HEADER_COLOR)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.55, 0)
	root.Size = UDim2.fromOffset(WIDTH, height)
	root.Visible = false
	root.ZIndex = Z

	-- Açılış animasyonu ölçeği; boyuta dokunmuyor, içerik hep aynı düzende
	local pop = Instance.new("UIScale")
	pop.Parent = root

	local skin = CardKit.skin(root, HEADER_COLOR, "Upgrades", HEADER, Z)

	-- ─── Kartlar ────────────────────────────────────────────────────────────

	local list = Instance.new("Frame")
	list.Position = UDim2.fromOffset(14, 12)
	list.Size = UDim2.new(1, -28, 1, -12)
	list.BackgroundTransparency = 1
	list.ZIndex = Z + 1
	list.Parent = skin.body

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = list

	local buyRemote = Net.Get("UpgradeBuy")
	local rows: { Row } = {}
	local CARD_W = WIDTH - 28

	local function makeCard(order: number, tint: Color3, icon: (slot: Frame) -> ()): Frame
		local card = CardKit.card(list, tint, UDim2.fromOffset(CARD_W, ROW_H), Z + 2, UDim2.fromScale(0.09, 0.5), 300)
		card.LayoutOrder = order
		local badge = CardKit.badge(card, 76, tint, Z + 4)
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 12, 0.5, 0)
		icon(badge:FindFirstChild("Slot") :: Frame)
		return card
	end

	local function title(card: Frame, text: string): TextLabel
		local name = CardKit.bold(card, text, 28, CardKit.WHITE, Z + 5, 3.5)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(100, 8)
		name.Size = UDim2.new(1, -278, 0, 32)
		CardKit.fit(name, 28, 16)
		return name
	end

	local function line(card: Frame, y: number, size: number): TextLabel
		local l = CardKit.bold(card, "", size, CardKit.WHITE, Z + 5, 2.2)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Position = UDim2.fromOffset(100, y)
		l.Size = UDim2.new(1, -278, 0, size + 4)
		CardKit.fit(l, size, 10)
		return l
	end

	local function makeBuy(card: Frame): CardKit.Button
		local buy = CardKit.button(card, UDim2.fromOffset(160, 62), Z + 5, 28)
		buy.holder.AnchorPoint = Vector2.new(1, 0.5)
		buy.holder.Position = UDim2.new(1, -12, 0.5, 2)
		return buy
	end

	for index, def in Config.Upgrades do
		local tint = TINT[def.id] or GOLD
		local card = makeCard(index, tint, function(slot)
			UiKit.Icon(slot, ICON[def.id] or "bolt", 50, tint:Lerp(CardKit.WHITE, 0.55))
		end)
		title(card, def.name)
		local effect = line(card, 42, 18)

		-- Seviye çubuğu: "12 seviyeden 4'ü" saymadan okunuyor
		local bar = CardKit.bar(card, UDim2.new(1, -278, 0, 22), CardKit.YELLOW, Z + 5, 15)
		bar.frame.Position = UDim2.fromOffset(100, 68)

		local buy = makeBuy(card)
		--[[
			Tıklama doğrudan remote'a gidiyor. Parası yetmeyen oyuncuda da
			düğme kapanmıyor: sunucu reddedip fiyatı söyleyen bir bildirim
			basıyor, istemcide susmak oyuncuya hiçbir şey anlatmaz.
		]]
		local id = def.id
		buy.button.MouseButton1Click:Connect(function()
			if buy.button.Active then
				buyRemote:FireServer(id)
			end
		end)

		table.insert(rows, { def = def, effect = effect, bar = bar, buy = buy, tint = tint })
	end

	-- ─── Yeni kat kartı ─────────────────────────────────────────────────────
	--[[
		Kat artık YALNIZCA burada alınıyor. Üslerdeki satın alma pedi
		kaldırıldı ("FLOOR 3 · Needs 2 rebirth" tabelası her üste bir ışık
		sütunu ve yazı koyuyordu).
	]]
	local floorCard = makeCard(#Config.Upgrades + 1, GOLD, function(slot)
		UiKit.Icon(slot, "podium", 50, GOLD:Lerp(CardKit.WHITE, 0.5))
	end)
	local floorName = title(floorCard, "")
	floorName.TextColor3 = CardKit.YELLOW
	local floorNote = line(floorCard, 44, 18)
	local floorBuy = makeBuy(floorCard)
	local floorRemote = Net.Get("FloorBuy")
	floorBuy.button.MouseButton1Click:Connect(function()
		if floorBuy.button.Active then
			floorRemote:FireServer()
		end
	end)

	local foot = CardKit.bold(skin.body, "Upgrades reset on rebirth  ·  every new floor doubles each cap",
		15, Color3.fromRGB(190, 200, 220), Z + 2, 2)
	foot.AnchorPoint = Vector2.new(0.5, 1)
	foot.Position = UDim2.new(0.5, 0, 1, -6)
	foot.Size = UDim2.new(1, -30, 0, 20)

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
			row.bar.set(lvl / math.max(1, maxLevel), string.format("LV %d / %d", lvl, maxLevel))

			local effect = EFFECT[row.def.id]
			local price = Config.GetUpgradeCost(row.def.id, lvl, floors)
			if effect then
				if price then
					-- Şimdi → sonraki: yeşil ok ve sonraki değer
					row.effect.Text = string.format('%s %s <font color="#7CFF5B">→ %s</font>',
						effect.label, effect.value(lvl), effect.value(lvl + 1))
				else
					row.effect.Text = effect.label .. " " .. effect.value(lvl)
				end
			end

			if price then
				-- Parası yetmiyorsa düğme sönük ama tıklanabilir: sunucu fiyatı söylüyor
				row.buy.set("$" .. Config.FormatCash(price), if cash >= price then CardKit.GREEN else CardKit.GREEN:Lerp(CardKit.GREY, 0.55))
			elseif floors < Config.MaxFloors then
				row.buy.set("NEXT FLOOR", nil)
			else
				row.buy.set("MAX", nil)
			end
		end

		-- Kat kartı: rebirth yetmiyor / alınabilir / hepsi alınmış
		local bought = number("FloorsBought", 0)
		local rebirths = number("Rebirths", 0)
		local nextFloor = Config.GetNextFloor(bought)
		if not nextFloor then
			floorName.Text = "ALL FLOORS OPEN"
			floorNote.Text = "Every upgrade cap is at its highest"
			floorBuy.set("MAX", nil)
		elseif rebirths < nextFloor.rebirths then
			floorName.Text = string.format("NEW FLOOR %d", nextFloor.floor)
			floorNote.Text = string.format('Needs <font color="#FFE13C">%d rebirth%s</font> (you have %d)',
				nextFloor.rebirths, if nextFloor.rebirths == 1 then "" else "s", rebirths)
			floorBuy.set("LOCKED", nil)
		else
			floorName.Text = string.format("NEW FLOOR %d", nextFloor.floor)
			floorNote.Text = '<font color="#7CFF5B">More podiums</font> + doubles every upgrade cap'
			floorBuy.set("$" .. Config.FormatCash(nextFloor.cost), if cash >= nextFloor.cost then CardKit.GREEN else CardKit.GREEN:Lerp(CardKit.GREY, 0.55))
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
	-- X'e basıldı: kulübeden uzaklaşıp dönene kadar açılmasın
	local dismissed = false
	skin.close.MouseButton1Click:Connect(function()
		dismissed = true
	end)

	local function update()
		local inside = nearOwnBooth()
		if not inside then
			dismissed = false
		end
		local near = inside and not dismissed
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
