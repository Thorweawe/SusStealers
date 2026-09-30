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

	2026-09-28: REBIRTH bu pencerenin ikinci sekmesi (eski ayrı RebirthPanel
	ve sol raydaki REBIRTH düğmesi kalktı). Sekme öğretici bitince görünüyor
	(kademeli açılma). Hedef kartındaki "REBIRTH is ready" pencereyi
	kulübeden uzakta da bu sekmede açıyor (OpenRebirth).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CardKit = require(script.Parent.CardKit)
local UiArt = require(script.Parent.UiArt)
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
	SprintBoots = Color3.fromRGB(70, 200, 230),
	SlapPower = Color3.fromRGB(230, 70, 110),
	StunCharge = Color3.fromRGB(250, 190, 40),
	GearRecharge = Color3.fromRGB(150, 110, 240),
}
-- Ekipman kartlarında aletin 3B ikonu (UiArt), diğerlerinde çizim
local ART: { [string]: string } = {
	SprintBoots = "Gear_SpeedCoil",
	SlapPower = "Gear_SlapGlove",
	StunCharge = "Gear_StunGun",
	GearRecharge = "Gear_EmergencyButton",
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
	{ id = "gear", title = "GEAR", color = Color3.fromRGB(255, 120, 160) },
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
			local rb = Players.LocalPlayer:GetAttribute("Rebirths")
			return string.format("+%.3f", Config.GetCapsuleGain(level, if typeof(speed) == "number" then speed else Config.Space.BaseSpeed)
				* Config.GetRebirthTrainingMul(if typeof(rb) == "number" then rb else 0))
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
	SprintBoots = {
		label = "Ship run speed",
		value = function(level)
			return "+" .. pct(Config.GetSprintMul(level) - 1)
		end,
	},
	SlapPower = {
		label = "Slap power",
		value = function(level)
			return "+" .. pct(Config.GetSlapPower(level) - 1)
		end,
	},
	StunCharge = {
		label = "Stun power",
		value = function(level)
			return "+" .. pct(Config.GetStunCharge(level) - 1)
		end,
	},
	GearRecharge = {
		label = "Gear cooldown",
		value = function(level)
			return "-" .. pct(1 - Config.GetGearRecharge(level))
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
	OpenRebirth: () -> (),
	Destroy: () -> (),
}

local REBIRTH_TINT = Color3.fromRGB(235, 120, 30)

--[[ Öğretici bitti mi (atlanmış = bitti). SideRail ile aynı kural. ]]
local function tutorialFinished(): boolean
	local v = Players.LocalPlayer:GetAttribute("TutorialStep")
	return typeof(v) == "number" and (v < 0 or v >= #Config.Tutorial)
end

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

	-- ─── Sekmeler: UPGRADES / REBIRTH ───────────────────────────────────────

	local TAB_H = 46
	local tabs = Instance.new("Frame")
	tabs.Position = UDim2.fromOffset(14, 10)
	tabs.Size = UDim2.new(1, -28, 0, TAB_H)
	tabs.BackgroundTransparency = 1
	tabs.ZIndex = Z + 1
	tabs.Parent = skin.body
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 12)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs

	local current = "upgrades"
	local pages: { [string]: Frame } = {}
	type TabRef = { holder: Frame, card: Frame, scale: UIScale, tint: Color3 }
	local tabRefs: { [string]: TabRef } = {}
	local paintTabs: () -> ()

	local function makePage(id: string): Frame
		local page = Instance.new("Frame")
		page.Name = id
		page.Position = UDim2.fromOffset(0, TAB_H + 14)
		page.Size = UDim2.new(1, 0, 1, -(TAB_H + 14))
		page.BackgroundTransparency = 1
		page.ZIndex = Z + 1
		page.Visible = id == current
		page.Parent = skin.body
		pages[id] = page
		return page
	end

	local function makeTab(id: string, text: string, tint: Color3, order: number)
		local holder = Instance.new("Frame")
		holder.LayoutOrder = order
		holder.Size = UDim2.new(0.5, -6, 1, 0)
		holder.BackgroundTransparency = 1
		holder.ZIndex = Z + 2
		holder.Parent = tabs
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		local card = CardKit.card(holder, tint, UDim2.fromScale(1, 1), Z + 2, UDim2.fromScale(0.5, 0.5), 260)
		local label = CardKit.bold(card, text, 22, CardKit.WHITE, Z + 4, 3)
		label.Size = UDim2.fromScale(1, 1)
		local hit = Instance.new("TextButton")
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = Z + 6
		hit.Parent = holder
		tabRefs[id] = { holder = holder, card = card, scale = scale, tint = tint }
		hit.MouseButton1Click:Connect(function()
			current = id
			paintTabs()
		end)
	end
	makeTab("upgrades", "UPGRADES", HEADER_COLOR, 1)
	makeTab("rebirth", "REBIRTH", REBIRTH_TINT, 2)

	paintTabs = function()
		local rebirthOpen = tutorialFinished()
		tabRefs.rebirth.holder.Visible = rebirthOpen
		if current == "rebirth" and not rebirthOpen then
			current = "upgrades"
		end
		for id, page in pages do
			page.Visible = id == current
		end
		for id, ref in tabRefs do
			local on = id == current
			CardKit.tintCard(ref.card, if on then ref.tint else ref.tint:Lerp(Color3.fromRGB(70, 78, 96), 0.6))
			ref.scale.Scale = if on then 1 else 0.95
		end
	end

	local upgradePage = makePage("upgrades")
	local rebirthPage = makePage("rebirth")

	-- ─── Kartlar ────────────────────────────────────────────────────────────

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(14, 0)
	list.Size = UDim2.new(1, -20, 1, -30)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(255, 200, 120)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ZIndex = Z + 1
	list.Parent = upgradePage

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
			local art = if ART[def.id] then UiArt.Image("Icon", ART[def.id]) else ""
			if art ~= "" then
				local img = Instance.new("ImageLabel")
				img.AnchorPoint = Vector2.new(0.5, 0.5)
				img.Position = UDim2.fromScale(0.5, 0.5)
				img.Size = UDim2.fromOffset(58, 58)
				img.BackgroundTransparency = 1
				img.Image = art
				img.ZIndex = slot.ZIndex + 1
				img.Parent = slot
			else
				UiKit.Icon(slot, ICON[def.id] or "bolt", 50, tint:Lerp(CardKit.WHITE, 0.55))
			end
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
	--[[
		2026-09-30 (oyuncu: "there's no upgrade button"): her şey tavandayken
		bütün düğmeler gri "MAX" oluyordu ve panel sıradaki adımı söylemiyordu.
		Artık sıradaki adım rebirth ise kat kartının düğmesi yeşil "REBIRTH →"
		oluyor ve REBIRTH sekmesini açıyor; alt yazı da durumu söylüyor.
	]]
	local floorGoesRebirth = false
	floorBuy.button.MouseButton1Click:Connect(function()
		if not floorBuy.button.Active then
			return
		end
		if floorGoesRebirth then
			current = "rebirth"
			paintTabs()
		else
			floorRemote:FireServer()
		end
	end)

	local foot = CardKit.bold(upgradePage, "Upgrades reset on rebirth  ·  floors and rebirths raise every cap  ·  scroll for more",
		15, Color3.fromRGB(190, 200, 220), Z + 2, 2)
	foot.AnchorPoint = Vector2.new(0.5, 1)
	foot.Position = UDim2.new(0.5, 0, 1, -6)
	foot.Size = UDim2.new(1, -30, 0, 20)

	-- ─── Rebirth sayfası ────────────────────────────────────────────────────
	--[[
		Mağaza dilinde: üstte büyük kahraman kart (kaçıncı rebirth, kalıcı
		gelir çarpanı şimdi → sonra), altında iki kart yan yana: KAYBEDİLEN
		(kırmızı) ve KAZANILAN (yeşil), en altta tıknaz REBIRTH düğmesi.
		Doğrulama sunucuda (RebirthBuy → RebirthService.TryRebirth).
	]]
	local RB_W = CARD_W
	local hero = CardKit.hero(rebirthPage, REBIRTH_TINT, UDim2.fromOffset(RB_W, 150), Z + 2, UDim2.fromScale(0.12, 0.5), 320)
	hero.Position = UDim2.fromOffset(14, 0)
	local heroBadge = CardKit.badge(hero, 104, REBIRTH_TINT, Z + 4)
	heroBadge.AnchorPoint = Vector2.new(0, 0.5)
	heroBadge.Position = UDim2.new(0, 16, 0.5, 0)
	UiKit.Icon(heroBadge:FindFirstChild("Slot") :: Frame, "rebirth", 76, CardKit.WHITE)
	local rbTitle = CardKit.bold(hero, "", 34, CardKit.WHITE, Z + 5, 4)
	rbTitle.TextXAlignment = Enum.TextXAlignment.Left
	rbTitle.Position = UDim2.fromOffset(136, 18)
	rbTitle.Size = UDim2.new(1, -150, 0, 40)
	CardKit.fit(rbTitle, 34, 18)
	local rbMult = CardKit.bold(hero, "", 22, CardKit.YELLOW, Z + 5, 2.6)
	rbMult.TextXAlignment = Enum.TextXAlignment.Left
	rbMult.Position = UDim2.fromOffset(136, 64)
	rbMult.Size = UDim2.new(1, -150, 0, 28)
	CardKit.fit(rbMult, 22, 12)
	local rbSub = CardKit.bold(hero, "Reset your base for a PERMANENT income boost", 16, Color3.fromRGB(255, 235, 215), Z + 5, 2)
	rbSub.TextXAlignment = Enum.TextXAlignment.Left
	rbSub.Position = UDim2.fromOffset(136, 100)
	rbSub.Size = UDim2.new(1, -150, 0, 22)
	CardKit.fit(rbSub, 16, 10)

	local function ledger(x: number, tint: Color3, head: string, lines: { string }): { TextLabel }
		local w = (RB_W - 12) / 2
		local c = CardKit.card(rebirthPage, tint, UDim2.fromOffset(w, 176), Z + 2, UDim2.fromScale(0.5, 0.2), 220)
		c.Position = UDim2.fromOffset(14 + x * (w + 12), 162)
		local h = CardKit.bold(c, head, 22, CardKit.WHITE, Z + 5, 3)
		h.Position = UDim2.fromOffset(0, 8)
		h.Size = UDim2.new(1, 0, 0, 28)
		local out = {}
		for i, text in lines do
			local l = CardKit.bold(c, text, 16, CardKit.WHITE, Z + 5, 2)
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Position = UDim2.fromOffset(18, 42 + (i - 1) * 30)
			l.Size = UDim2.new(1, -30, 0, 24)
			l.RichText = true
			CardKit.fit(l, 16, 10)
			table.insert(out, l)
		end
		return out
	end
	ledger(0, Color3.fromRGB(200, 60, 70), "YOU LOSE", {
		'<font color="#FF9A9A">-</font>  Crewmates on your podiums',
		'<font color="#FF9A9A">-</font>  Every upgrade level',
		'<font color="#FF9A9A">-</font>  Your cash',
	})
	local gains = ledger(1, Color3.fromRGB(50, 160, 80), "YOU GET", {
		"",
		'<font color="#9CFFA0">+</font>  Unlocks the next floor to buy',
		'<font color="#9CFFA0">+</font>  Titles and rebirth badges',
	})

	local rbBuy = CardKit.button(rebirthPage, UDim2.fromOffset(RB_W, 66), Z + 3, 30)
	rbBuy.holder.Position = UDim2.fromOffset(14, 352)
	local rbNote = CardKit.bold(rebirthPage, "This cannot be undone.", 15, Color3.fromRGB(200, 205, 225), Z + 2, 2)
	rbNote.Position = UDim2.fromOffset(14, 424)
	rbNote.Size = UDim2.fromOffset(RB_W, 20)
	local rebirthRemote = Net.Get("RebirthBuy")
	rbBuy.button.MouseButton1Click:Connect(function()
		if rbBuy.button.Active then
			rebirthRemote:FireServer()
		end
	end)

	local function refreshRebirth(cash: number)
		local rebirths = player:GetAttribute("Rebirths")
		rebirths = if typeof(rebirths) == "number" then rebirths else 0
		rbTitle.Text = if rebirths > 0 then string.format("REBIRTH %d", rebirths) else "REBIRTH"
		local now = Config.GetIncomeMultiplier(rebirths)
		-- Tavan (sunucuyla aynı kural, Config.MaxRebirths)
		if rebirths >= Config.MaxRebirths then
			rbMult.Text = string.format("Income x%.2f  ·  every rebirth done", now)
			gains[1].Text = '<font color="#9CFFA0">+</font>  Nothing left to unlock'
			gains[2].Text = '<font color="#9CFFA0">+</font>  Every monster and egg is open'
			rbBuy.set("MAXED", nil)
			rbNote.Text = "You have every rebirth."
			return
		end
		local nextMul = Config.GetIncomeMultiplier(rebirths + 1)
		rbMult.Text = string.format('Income x%.2f  <font color="#7CFF5B">→ x%.2f</font>', now, nextMul)
		rbMult.RichText = true
		gains[1].Text = string.format('<font color="#9CFFA0">+</font>  <font color="#FFE13C">+%d%% income</font> forever', math.floor(Config.GetRebirthBonus(rebirths + 1) * 100 + 0.5))
		--[[
			İkinci satır: bir sonraki rebirth neyi açıyor. Önce rebirth
			canavarı / yumurtası / jetpack'i, yoksa satın alınacak kat, o da
			yoksa bir sonraki kilide kaç rebirth kaldığı.
		]]
		local unlocks = Config.RebirthUnlocks(rebirths + 1)
		local floor = Config.GetNextFloor(player:GetAttribute("FloorsBought") :: any or 0)
		if #unlocks > 0 then
			gains[2].Text = '<font color="#9CFFA0">+</font>  Unlocks <font color="#78FFEB">' .. table.concat(unlocks, ", ") .. "</font>"
		elseif floor and floor.rebirths == rebirths + 1 then
			gains[2].Text = '<font color="#9CFFA0">+</font>  Unlocks the next floor to buy'
		elseif Config.GetRebirthUpgradeBonus(rebirths + 1) > 0 then
			gains[2].Text = string.format('<font color="#9CFFA0">+</font>  Every upgrade cap <font color="#78FFEB">+%d levels</font>',
				Config.GetRebirthUpgradeBonus(rebirths + 1) - Config.GetRebirthUpgradeBonus(rebirths))
		else
			local ahead = ""
			for r = rebirths + 2, Config.MaxRebirths do
				local list = Config.RebirthUnlocks(r)
				if #list > 0 then
					ahead = string.format("%s at Rebirth %d", list[1], r)
					break
				end
			end
			gains[2].Text = '<font color="#9CFFA0">+</font>  ' .. (if ahead ~= "" then "Closer to " .. ahead else "Faster capsule training")
		end
		local cost = player:GetAttribute("RebirthCost")
		cost = if typeof(cost) == "number" then cost else Config.GetRebirthCost(rebirths)
		if cash >= cost then
			rbBuy.set("REBIRTH  ·  $" .. Config.FormatCash(cost), CardKit.GREEN)
		else
			-- Yetmiyor: gri ama tıklanabilir (sunucu fiyatı söylüyor)
			rbBuy.set(string.format("$%s / $%s", Config.FormatCash(cash), Config.FormatCash(cost)), CardKit.GREY)
		end
		rbNote.Text = "This cannot be undone."
	end

	-- ─── Güncelleme ─────────────────────────────────────────────────────────

	local function number(name: string, default: number): number
		local value = player:GetAttribute(name)
		return if typeof(value) == "number" then value else default
	end

	local function refresh()
		local floors = number("UpgradeFloors", 1)
		local cash = number("Cash", 0)
		local rebirthsNow = number("Rebirths", 0)
		paintTabs()
		refreshRebirth(cash)

		-- Hâlâ alınabilen yükseltme sayısı (0 = hepsi tavanda)
		local buyable = 0
		for _, row in rows do
			local lvl = number("Upg_" .. row.def.id, 0)
			local maxLevel = Config.GetUpgradeMaxLevel(row.def, floors, rebirthsNow)
			row.bar.set(lvl / math.max(1, maxLevel), string.format("LV %d / %d", lvl, maxLevel))

			local effect = EFFECT[row.def.id]
			local price = Config.GetUpgradeCost(row.def.id, lvl, floors, rebirthsNow)
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
				buyable += 1
				-- Parası yetmiyorsa düğme sönük ama tıklanabilir: sunucu fiyatı söylüyor
				row.buy.set("$" .. Config.FormatCash(price), if cash >= price then CardKit.GREEN else CardKit.GREEN:Lerp(CardKit.GREY, 0.55))
			elseif floors < Config.MaxFloors then
				row.buy.set("NEXT FLOOR", nil)
			elseif rebirthsNow < Config.MaxRebirths then
				-- Rebirth tavanı yükseltiyor (3. rebirth'ten itibaren)
				row.buy.set("REBIRTH", nil)
			else
				row.buy.set("MAX", nil)
			end
		end

		-- Kat kartı: rebirth yetmiyor / alınabilir / hepsi alınmış
		local bought = number("FloorsBought", 0)
		local rebirths = number("Rebirths", 0)
		local nextFloor = Config.GetNextFloor(bought)
		local canRebirth = rebirths < Config.MaxRebirths and tutorialFinished()
		floorGoesRebirth = false
		if not nextFloor then
			--[[
				Katlar bitti: kart rebirth tavan bonusunu anlatıyor
				(Config.GetRebirthUpgradeBonus, 3. rebirth'ten itibaren her
				yükseltmeye rebirth × 3 seviye). Düğme REBIRTH sekmesine götürüyor.
			]]
			local nowBonus = Config.GetRebirthUpgradeBonus(rebirths)
			local nextBonus = Config.GetRebirthUpgradeBonus(rebirths + 1)
			floorName.Text = "REBIRTH CAP BONUS"
			if canRebirth then
				floorNote.Text = string.format('Every upgrade: <font color="#7CFF5B">+%d levels</font>  ·  Rebirth %d → <font color="#FFE13C">+%d</font>',
					nowBonus, rebirths + 1, nextBonus)
				floorBuy.set("REBIRTH →", CardKit.GREEN)
				floorGoesRebirth = true
			else
				floorNote.Text = string.format('Every upgrade: <font color="#7CFF5B">+%d levels</font>', nowBonus)
				floorBuy.set("MAX", nil)
			end
		elseif rebirths < nextFloor.rebirths then
			floorName.Text = string.format("NEW FLOOR %d", nextFloor.floor)
			floorNote.Text = string.format('Needs <font color="#FFE13C">%d rebirth%s</font> (you have %d)',
				nextFloor.rebirths, if nextFloor.rebirths == 1 then "" else "s", rebirths)
			if canRebirth then
				floorBuy.set("REBIRTH →", CardKit.GREEN)
				floorGoesRebirth = true
			else
				floorBuy.set("LOCKED", nil)
			end
		else
			floorName.Text = string.format("NEW FLOOR %d", nextFloor.floor)
			floorNote.Text = '<font color="#7CFF5B">More podiums</font> + doubles every upgrade cap'
			floorBuy.set("$" .. Config.FormatCash(nextFloor.cost), if cash >= nextFloor.cost then CardKit.GREEN else CardKit.GREEN:Lerp(CardKit.GREY, 0.55))
		end

		-- Alt yazı: alınacak yükseltme kalmadıysa sıradaki adımı söyle
		if buyable > 0 then
			foot.Text = "Upgrades reset on rebirth  ·  floors and rebirths raise every cap  ·  scroll for more"
			foot.TextColor3 = Color3.fromRGB(190, 200, 220)
		elseif nextFloor and rebirths >= nextFloor.rebirths then
			foot.Text = "ALL CAPS REACHED!  Scroll down and buy the NEW FLOOR to double every cap"
			foot.TextColor3 = CardKit.YELLOW
		elseif canRebirth then
			foot.Text = "ALL UPGRADES MAXED!  Next step: open the REBIRTH tab"
			foot.TextColor3 = CardKit.YELLOW
		else
			foot.Text = "Everything is maxed. You finished the upgrades!"
			foot.TextColor3 = CardKit.YELLOW
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
	-- Kulübeden uzakta açıldı (hedef kartı → REBIRTH): X'e basılana kadar açık
	local forced = false
	skin.close.MouseButton1Click:Connect(function()
		dismissed = true
		forced = false
	end)

	local function update()
		local inside = nearOwnBooth()
		if not inside then
			dismissed = false
		end
		local near = (inside and not dismissed) or forced
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
		OpenRebirth = function()
			forced = true
			dismissed = false
			current = if tutorialFinished() then "rebirth" else "upgrades"
			update()
			paintTabs()
		end,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return UpgradePanel
