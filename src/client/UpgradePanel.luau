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

	2026-09-28: yükseltmeler yeni döngüye göre (Config.Upgrades): yedi kart
	üç bölümde (SPACE TRAINING / HEIST GEAR / BASE), kaydırılabilir liste.
	Kapsül ve Training Console kapsülün yanındaki istasyonlardan da alınıyor.
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
	SpaceCapsule = Color3.fromRGB(40, 150, 220),
	TrainingConsole = Color3.fromRGB(60, 175, 90),
	QuickHands = Color3.fromRGB(230, 110, 40),
	JetBoost = Color3.fromRGB(235, 70, 60),
	StealthSuit = Color3.fromRGB(120, 80, 210),
	LuckyScanner = Color3.fromRGB(215, 160, 20),
	CrewMorale = Color3.fromRGB(40, 165, 150),
}
local ICON: { [string]: string } = {
	SpaceCapsule = "bolt",
	TrainingConsole = "clipboard",
	QuickHands = "crewmate",
	JetBoost = "boot",
	StealthSuit = "lock",
	LuckyScanner = "gift",
	CrewMorale = "coin",
}

-- Bölümler: kategori -> başlık ve renk
local SECTIONS = {
	{ id = "training", title = "SPACE TRAINING", color = Color3.fromRGB(120, 210, 255) },
	{ id = "heist", title = "HEIST GEAR", color = Color3.fromRGB(255, 150, 90) },
	{ id = "base", title = "BASE", color = Color3.fromRGB(130, 240, 190) },
}

--[[
	Etki metni: şimdiki değer → sonraki seviyedeki değer. Config'teki
	formüller sunucunun kullandıklarıyla aynı, yani yazan sayı gerçek.
]]
type Effect = { label: string, value: (level: number) -> string }

local function pct(x: number): string
	return string.format("%d%%", math.floor(x * 100 + 0.5))
end

local EFFECT: { [string]: Effect } = {
	-- Kapsülde saniyede kazanılan uzay hızı (şu anki hızla, CapsuleService)
	SpaceCapsule = {
		label = "Training / sec",
		value = function(level)
			local speed = Players.LocalPlayer:GetAttribute("SpaceSpeed")
			return string.format("+%.3f", Config.GetCapsuleGain(level, if typeof(speed) == "number" then speed else Config.Space.BaseSpeed))
		end,
	},
	TrainingConsole = {
		label = "Mini game ease",
		value = function(level)
			return pct(Config.GetTrainingAssist(level))
		end,
	},
	QuickHands = {
		label = "Grab time",
		value = function(level)
			return string.format("%.2fs", Config.Space.GrabHold * Config.GetGrabHoldMul(level))
		end,
	},
	JetBoost = {
		label = "Boost",
		value = function(level)
			local jet = Config.GetJetBoost(level)
			if not jet then
				return "locked"
			end
			return string.format("x%.2f · %.1fs · every %ds", jet.mul, jet.duration, math.floor(jet.cooldown + 0.5))
		end,
	},
	StealthSuit = {
		label = "Monster wake",
		value = function(level)
			local wake, reach = Config.GetStealth(level)
			return string.format("x%.2f · reach -%s", wake, pct(1 - reach))
		end,
	},
	LuckyScanner = {
		label = "Mutation chance",
		value = function(level)
			return pct(Config.GetLuckyChance(level))
		end,
	},
	CrewMorale = {
		label = "Income",
		value = function(level)
			return "+" .. pct(Config.GetMoraleMultiplier(level) - 1)
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
local ROW_H = 88
local WIDTH = 640

function UpgradePanel.Create(screen: ScreenGui): Panel
	-- Yedi kart + kat kartı + bölüm başlıkları sığmıyor: pencere sabit, liste kayıyor
	local height = 600

	local root = UiKit.Window(screen, "UpgradePanel", HEADER_COLOR)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.5, 0)
	root.Size = UDim2.fromOffset(WIDTH, height)
	root.Visible = false
	root.ZIndex = Z

	-- Açılış animasyonu ölçeği; boyuta dokunmuyor, içerik hep aynı düzende
	local pop = Instance.new("UIScale")
	pop.Parent = root

	local skin = CardKit.skin(root, HEADER_COLOR, "Upgrades", HEADER, Z)

	-- ─── Kartlar ────────────────────────────────────────────────────────────

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(14, 10)
	list.Size = UDim2.new(1, -20, 1, -40)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(255, 200, 120)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ZIndex = Z + 1
	list.Parent = skin.body

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = list

	local buyRemote = Net.Get("UpgradeBuy")
	local rows: { Row } = {}
	local CARD_W = WIDTH - 44

	local function makeCard(order: number, tint: Color3, icon: (slot: Frame) -> ()): Frame
		local card = CardKit.card(list, tint, UDim2.fromOffset(CARD_W, ROW_H), Z + 2, UDim2.fromScale(0.09, 0.5), 300)
		card.LayoutOrder = order
		local badge = CardKit.badge(card, 68, tint, Z + 4)
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 12, 0.5, 0)
		icon(badge:FindFirstChild("Slot") :: Frame)
		return card
	end

	local function title(card: Frame, text: string): TextLabel
		local name = CardKit.bold(card, text, 26, CardKit.WHITE, Z + 5, 3.5)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(92, 6)
		name.Size = UDim2.new(1, -270, 0, 28)
		CardKit.fit(name, 26, 16)
		return name
	end

	local function line(card: Frame, y: number, size: number): TextLabel
		local l = CardKit.bold(card, "", size, CardKit.WHITE, Z + 5, 2.2)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Position = UDim2.fromOffset(92, y)
		l.Size = UDim2.new(1, -270, 0, size + 4)
		CardKit.fit(l, size, 10)
		return l
	end

	local function makeBuy(card: Frame): CardKit.Button
		local buy = CardKit.button(card, UDim2.fromOffset(156, 58), Z + 5, 28)
		buy.holder.AnchorPoint = Vector2.new(1, 0.5)
		buy.holder.Position = UDim2.new(1, -12, 0.5, 2)
		return buy
	end

	-- Bölüm başlıkları ve kartlar sırayla: başlık, o bölümün kartları
	local order = 0
	local cardOrder: { [string]: number } = {}
	for _, section in SECTIONS do
		order += 1
		CardKit.section(list, section.title, section.color, CARD_W, Z + 2, order)
		for _, def in Config.Upgrades do
			if def.category == section.id then
				order += 1
				cardOrder[def.id] = order
			end
		end
	end

	for _, def in Config.Upgrades do
		local tint = TINT[def.id] or GOLD
		local card = makeCard(cardOrder[def.id] or 99, tint, function(slot)
			UiKit.Icon(slot, ICON[def.id] or "bolt", 50, tint:Lerp(CardKit.WHITE, 0.55))
		end)
		local nameLabel = title(card, def.name)
		nameLabel.Size = UDim2.new(1, -270, 0, 24)
		local blurb = line(card, 30, 13)
		blurb.Text = def.blurb
		blurb.TextColor3 = Color3.fromRGB(225, 230, 245)
		local effect = line(card, 46, 16)

		-- Seviye çubuğu: "12 seviyeden 4'ü" saymadan okunuyor
		local bar = CardKit.bar(card, UDim2.new(1, -270, 0, 20), CardKit.YELLOW, Z + 5, 14)
		bar.frame.Position = UDim2.fromOffset(92, 64)
		bar.frame.Size = UDim2.new(1, -270, 0, 16)

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
	local floorCard = makeCard(order + 1, GOLD, function(slot)
		UiKit.Icon(slot, "podium", 50, GOLD:Lerp(CardKit.WHITE, 0.5))
	end)
	local floorName = title(floorCard, "")
	floorName.TextColor3 = CardKit.YELLOW
	local floorNote = line(floorCard, 40, 17)
	local floorBuy = makeBuy(floorCard)
	local floorRemote = Net.Get("FloorBuy")
	floorBuy.button.MouseButton1Click:Connect(function()
		if floorBuy.button.Active then
			floorRemote:FireServer()
		end
	end)

	local foot = CardKit.bold(skin.body, "Upgrades reset on rebirth  ·  every new floor doubles each cap  ·  scroll for more",
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
