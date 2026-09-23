--!strict
--[[
	Mağaza: gamepass'ler ve tek seferlik ürünler.

	NEDEN VAR: ikisi de Config'de tanımlıydı, sunucu ikisini de işliyordu
	ama oyunun içinde onları GÖREBİLECEĞİN hiçbir yer yoktu. Satın alma
	istemi yalnızca kod çağırınca açılıyordu, yani pratikte hiç açılmıyordu.

	═══ SUNUCUYA REMOTE YOK ═══════════════════════════════════════════════

	Satın alma istemini MarketplaceService istemciden açabiliyor ve parayı
	Roblox tahsil ediyor; ödülü de sunucu ProcessReceipt / pass önbelleği
	üzerinden veriyor. Yani buradan giden bir "bana şunu ver" isteği YOK —
	yeni bir saldırı yüzeyi açılmıyor. Net.luau'ya dokunulmamasının sebebi
	bu.

	═══ ID'SİZ ÜRÜN ═══════════════════════════════════════════════════════

	Config'deki id = 0 olan ürünler henüz Creator Dashboard'da
	oluşturulmadı. Onları gizlemiyoruz, SOON olarak gösteriyoruz: oyuncu
	neyin geleceğini görüyor, tıklayınca da boş bir istem açılmıyor.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local UiKit = require(script.Parent.UiKit)

local ShopPanel = {}

local player = Players.LocalPlayer

local INK = UiKit.INK
local MUTED = UiKit.MUTED
local ACCENT = UiKit.CREW.LIME
local GOOD = UiKit.GOOD

export type Panel = {
	Toggle: () -> (),
	Close: () -> (),
	Destroy: () -> (),
}

type Entry = {
	key: string,
	kind: string,       -- pass | product
	blurb: string,
	tint: Color3,
	icon: string,       -- crewmate | crate | coin | vial | flame | boot
}

--[[
	Gösterim sırası burada, Config'de değil.

	Config.GamePasses ve Config.Products sözlük — Lua'da sırasız. Sırayı
	orada aramak her oturumda farklı dizilen bir mağaza demekti.

	Açıklamalar da burada çünkü Config'deki ad ("2x Income") ne yaptığını
	söylüyor ama neye değdiğini söylemiyor.
]]
local PASSES: { Entry } = {
	{ key = "DoubleIncome", kind = "pass", tint = UiKit.CREW.LIME,
		icon = "coin",     blurb = "Every crewmate on your podiums earns double, forever." },
	{ key = "ExtraPodiums", kind = "pass", tint = UiKit.CREW.CYAN,
		icon = "crewmate", blurb = "Two extra podium slots on every floor you own." },
	{ key = "FastSteal",    kind = "pass", tint = UiKit.CREW.RED,
		icon = "boot",     blurb = "Rip a crewmate off a podium in a lot less time." },
	{ key = "StrongLock",   kind = "pass", tint = UiKit.CREW.BLUE,
		icon = "crate",    blurb = "Your base lock holds longer and recharges faster." },
	{ key = "TripleHatch",  kind = "pass", tint = UiKit.CREW.PINK,
		icon = "egg",      blurb = "Hatch 3 eggs at once, same wait as one." },
}

local SUPPLIES: { Entry } = {
	{ key = "Cash100K",       kind = "product", tint = UiKit.CREW.LIME,
		icon = "coin",  blurb = "Instant cash drop." },
	{ key = "Cash1M",         kind = "product", tint = UiKit.CREW.LIME,
		icon = "coin",  blurb = "Instant cash drop." },
	{ key = "Cash10M",        kind = "product", tint = UiKit.CREW.LIME,
		icon = "coin",  blurb = "Instant cash drop." },
	{ key = "SkipConveyor",   kind = "product", tint = UiKit.CREW.CYAN,
		icon = "crate", blurb = "Skip the conveyor wait — next crewmate lands now." },
	{ key = "LuckyRoll",      kind = "product", tint = UiKit.CREW.PURPLE,
		icon = "vial",  blurb = "Your next crewmate spawns mutated, guaranteed." },
	{ key = "ExtraSpin",      kind = "product", tint = UiKit.CREW.YELLOW,
		icon = "vial",  blurb = "One more spin on the wheel." },
	{ key = "InstantRebirth", kind = "product", tint = UiKit.CREW.ORANGE,
		icon = "flame", blurb = "Rebirth now without meeting the cash requirement." },
}

local function defOf(entry: Entry): { id: number, name: string }?
	if entry.kind == "pass" then
		return Config.GamePasses[entry.key]
	end
	return Config.Products[entry.key]
end

--[[ Yuvaya ikonu çizer. Hepsi UiKit'ten; hazır görsel yok. ]]
local function drawIcon(slot: Frame, entry: Entry)
	UiKit.ClearSlot(slot)
	if entry.icon == "crewmate" then
		UiKit.Crewmate(slot, 30, entry.tint)
	elseif entry.icon == "crate" then
		UiKit.Crate(slot, 30, entry.tint)
	elseif entry.icon == "coin" then
		UiKit.Coin(slot, 30, entry.tint)
	elseif entry.icon == "vial" then
		UiKit.Vial(slot, 32, entry.tint, 0.7, true)
	elseif entry.icon == "boot" then
		UiKit.Boot(slot, 30, entry.tint)
	elseif entry.icon == "egg" then
		UiKit.Egg(slot, 32, entry.tint)
	else
		UiKit.Flame(slot, 32, entry.tint)
	end
end

function ShopPanel.Create(screen: ScreenGui): Panel
	local overlay = UiKit.Window(screen, "ShopPanel", ACCENT)
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromOffset(560, 470)
	overlay.Visible = false
	overlay.ZIndex = 40

	local badge = Instance.new("Frame")
	badge.Position = UDim2.fromOffset(18, 14)
	badge.Size = UDim2.fromOffset(30, 30)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 41
	badge.Parent = overlay
	UiKit.Crate(badge, 26, ACCENT)

	local heading = Instance.new("TextLabel")
	heading.Position = UDim2.fromOffset(56, 12)
	heading.Size = UDim2.new(1, -100, 0, 24)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBlack
	heading.TextSize = 20
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextColor3 = ACCENT
	heading.Text = "SUPPLY SHOP"
	heading.ZIndex = 41
	heading.Parent = overlay

	local hint = Instance.new("TextLabel")
	hint.Position = UDim2.fromOffset(56, 34)
	hint.Size = UDim2.new(1, -100, 0, 16)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = MUTED
	hint.Text = "Passes stay with you forever. Supplies are one-time drops."
	hint.ZIndex = 41
	hint.Parent = overlay

	local close = UiKit.CloseButton(overlay)
	close.ZIndex = 41

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(14, 60)
	list.Size = UDim2.new(1, -28, 1, -74)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = MUTED
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = 41
	list.Parent = overlay

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local order = 0

	local function section(text: string, tone: Color3)
		order += 1
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.new(1, -6, 0, 26)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = tone
		label.Text = text
		label.ZIndex = 42
		label.Parent = list
	end

	-- ─── Kart ───────────────────────────────────────────────────────────────

	type Card = { entry: Entry, holder: Frame, price: TextLabel, buy: TextButton, state: TextLabel }
	local cards: { Card } = {}

	local function makeCard(entry: Entry)
		local def = defOf(entry)
		if not def then
			return
		end

		order += 1

		local card = Instance.new("Frame")
		card.Name = entry.key
		card.LayoutOrder = order
		card.Size = UDim2.new(1, -6, 0, 64)
		card.BackgroundColor3 = UiKit.ROW
		card.BorderSizePixel = 0
		card.ZIndex = 42
		card.Parent = list
		UiKit.Corner(card, 10)

		-- Sol kenarda ürünün rengi: kartları okumadan türü ayırt ediliyor
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 4, 1, 0)
		stripe.BackgroundColor3 = entry.tint
		stripe.BorderSizePixel = 0
		stripe.ZIndex = 43
		stripe.Parent = card
		UiKit.Corner(stripe, 2)

		local slot = Instance.new("Frame")
		slot.Position = UDim2.fromOffset(16, 16)
		slot.Size = UDim2.fromOffset(32, 32)
		slot.BackgroundTransparency = 1
		slot.ZIndex = 43
		slot.Parent = card
		drawIcon(slot, entry)

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(60, 10)
		name.Size = UDim2.new(1, -190, 0, 20)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 15
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = INK
		name.Text = def.name
		name.ZIndex = 43
		name.Parent = card

		local blurb = Instance.new("TextLabel")
		blurb.Position = UDim2.fromOffset(60, 30)
		blurb.Size = UDim2.new(1, -190, 0, 26)
		blurb.BackgroundTransparency = 1
		blurb.Font = Enum.Font.GothamMedium
		blurb.TextSize = 12
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		blurb.TextYAlignment = Enum.TextYAlignment.Top
		blurb.TextWrapped = true
		blurb.TextColor3 = MUTED
		blurb.Text = entry.blurb
		blurb.ZIndex = 43
		blurb.Parent = card

		--[[
			Satın alma düğmesi kartın sağında ve HUD'un kabartma dilinde:
			listedeki tek TIKLANABİLİR şey o, gövdesi de öyle görünmeli.
		]]
		local holder, buy = UiKit.Raised(card, "Buy", entry.tint, UDim2.fromOffset(112, 40), 10)
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -12, 0.5, 0)
		holder.ZIndex = 43

		local price = Instance.new("TextLabel")
		price.Size = UDim2.fromScale(1, 1)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.GothamBlack
		price.TextSize = 14
		price.TextColor3 = Color3.new(1, 1, 1)
		price.TextStrokeTransparency = 0.5
		price.Text = "..."
		price.ZIndex = 45
		price.Parent = buy

		-- Sahiplik rozeti: satın alınmış pass'in düğmesi kapanıyor
		local state = Instance.new("TextLabel")
		state.AnchorPoint = Vector2.new(1, 0.5)
		state.Position = UDim2.new(1, -12, 0.5, 0)
		state.Size = UDim2.fromOffset(112, 40)
		state.BackgroundTransparency = 1
		state.Font = Enum.Font.GothamBlack
		state.TextSize = 14
		state.TextColor3 = GOOD
		state.Text = ""
		state.Visible = false
		state.ZIndex = 45
		state.Parent = card

		buy.MouseButton1Click:Connect(function()
			if def.id == 0 then
				return
			end
			if entry.kind == "pass" then
				MarketplaceService:PromptGamePassPurchase(player, def.id)
			else
				MarketplaceService:PromptProductPurchase(player, def.id)
			end
		end)

		table.insert(cards, { entry = entry, holder = holder, price = price, buy = buy, state = state })
	end

	section("CREW PASSES", ACCENT)
	for _, entry in PASSES do
		makeCard(entry)
	end

	section("SUPPLY DROPS", UiKit.CREW.CYAN)
	for _, entry in SUPPLIES do
		makeCard(entry)
	end

	-- ─── Fiyat ve sahiplik ──────────────────────────────────────────────────

	--[[
		Fiyatlar Roblox'tan geliyor ve ağ çağrısı: panel her açıldığında
		sorulsa kota yenirdi. Bir kez çekilip saklanıyor, fiyat oyun
		ortasında değişmiyor.
	]]
	local priceCache: { [string]: string } = {}
	local ownedCache: { [string]: boolean } = {}

	local function infoType(kind: string): Enum.InfoType
		return if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	end

	local function refreshCard(card: Card)
		local def = defOf(card.entry)
		if not def then
			return
		end

		if def.id == 0 then
			card.price.Text = "SOON"
			card.buy.BackgroundColor3 = UiKit.DIM
			return
		end

		if ownedCache[card.entry.key] then
			card.holder.Visible = false
			card.state.Visible = true
			card.state.Text = "OWNED"
			return
		end

		card.price.Text = priceCache[card.entry.key] or "..."
	end

	--[[
		Hepsi tek bir görevde, sırayla. Paralel çağırmak aynı anda on ağ
		isteği demek ve Roblox onları kuyruğa alıp yavaşlatıyor.
	]]
	task.spawn(function()
		for _, card in cards do
			local def = defOf(card.entry)
			if def and def.id ~= 0 then
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(def.id, infoType(card.entry.kind))
				end)
				if ok and typeof(info) == "table" and info.PriceInRobux then
					priceCache[card.entry.key] = "R$ " .. tostring(info.PriceInRobux)
				else
					priceCache[card.entry.key] = "BUY"
				end

				if card.entry.kind == "pass" then
					local owns = false
					pcall(function()
						owns = MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
					end)
					ownedCache[card.entry.key] = owns
				end
			end
			refreshCard(card)
		end
	end)

	--[[
		Oyun içinde pass alınırsa kart hemen OWNED'a dönsün; oyuncunun
		yeniden girmesi gerekmemeli. Sunucu da aynı olayda önbelleğini
		tazeliyor (MonetizationService).
	]]
	local finished = MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(who: Player, passId: number, purchased: boolean)
			if who ~= player or not purchased then
				return
			end
			for _, card in cards do
				local def = defOf(card.entry)
				if def and def.id == passId then
					ownedCache[card.entry.key] = true
					refreshCard(card)
				end
			end
		end
	)

	-- ─── Aç / kapa ──────────────────────────────────────────────────────────

	close.Activated:Connect(function()
		overlay.Visible = false
	end)

	return {
		Toggle = function()
			overlay.Visible = not overlay.Visible
		end,
		Close = function()
			overlay.Visible = false
		end,
		Destroy = function()
			finished:Disconnect()
			overlay:Destroy()
		end,
	}
end

return ShopPanel
