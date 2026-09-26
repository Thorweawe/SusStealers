--!strict
--[[
	Görev penceresi: 30 dakikalık, 3 saatlik ve günlük hedefler.

	Sunucu (QuestService) "Quests" remote'uyla vade listesini gönderiyor;
	burada sadece çiziliyor. İlerleme sunucuda hesaplanıyor, istemci onu
	değiştiremiyor. Toplama isteği (QuestClaim) de sunucuda doğrulanıyor.

	═══ NEDEN PENCERE ══════════════════════════════════════════════════════

	Eskiden sol kenarda sürekli açık duran bir kutuydu ve iki sorunu vardı:
	ekranın sol yarısını kaplıyordu (SHOP/INDEX ile üst üste biniyordu) ve
	oyuncu onu "arka plan" olarak okuyup hiç bakmıyordu.

	Artık SHOP ve INDEX gibi sol raydaki bir düğme. Hazır ödül varsa
	düğmenin köşesinde kırmızı sayı çıkıyor — görevleri görünür kılan şey
	sürekli ekranda durmaları değil, o sayı.

	═══ DÜZEN ══════════════════════════════════════════════════════════════

	Üstte vade sekmeleri (her birinde kendi sayacı ve hazır sayısı),
	altında o vadenin görevleri kart olarak. Kartın üç hâli var ve üçü de
	farklı görünüyor:

	    devam ediyor → ilerleme çubuğu + "3 / 5", sağda ödül önizlemesi
	    hazır        → yeşil CLAIM düğmesi, ödül üstünde yazıyor
	    toplandı     → yeşil tik, kart sönük

	"Hazır" ile "toplandı" ayrı olmasaydı oyuncu ödülünü alıp almadığını
	bilemezdi.

	═══ GÖRÜNÜŞ ════════════════════════════════════════════════════════════

	Mağazanın dili (CardKit): mavi başlık şeridi, her vadenin kendi rengi
	(30 dk camgöbeği, 3 saat mor, günlük altın), ışınlı kartlar, kalın
	ilerleme çubuğu, tıknaz CLAIM düğmesi. Eski düz gri satırlar oyuncuya
	"burada ödül var" demiyordu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CardKit = require(script.Parent.CardKit)
local UiKit = require(script.Parent.UiKit)

local QuestPanel = {}

local WHITE = CardKit.WHITE
local HEADER_COLOR = Color3.fromRGB(50, 140, 240)
local DONE_TINT = Color3.fromRGB(70, 78, 96)
local READY_TINT = Color3.fromRGB(60, 180, 70)

-- Vade -> kart ve sekme rengi (bilinmeyen vade camgöbeği)
local TIER_TINT: { [string]: Color3 } = {
	short = Color3.fromRGB(30, 160, 200),
	medium = Color3.fromRGB(140, 80, 220),
	daily = Color3.fromRGB(230, 160, 20),
}
local DEFAULT_TINT = Color3.fromRGB(30, 160, 200)

local function tintOf(id: string, order: number): Color3
	return TIER_TINT[id] or ({ DEFAULT_TINT, Color3.fromRGB(140, 80, 220), Color3.fromRGB(230, 160, 20) })[order] or DEFAULT_TINT
end

export type Panel = {
	Toggle: () -> (),
	Destroy: () -> (),
}

type Entry = {
	id: string,
	text: string,
	value: number,
	goal: number,
	done: boolean,
	claimed: boolean,
	cash: boolean,
}

type Tier = {
	id: string,
	name: string,
	secondsLeft: number,
	reward: number,
	entries: { Entry },
}

local Z = 40
local W, H = 660, 560
local HEADER = 64

--[[
	`onReady` hazır (toplanmamış) ödül sayısı değişince çağrılıyor; sol
	raydaki QUESTS düğmesinin rozeti buna bağlı.
]]
function QuestPanel.Create(screen: ScreenGui, onReady: ((number) -> ())?): Panel
	local root = UiKit.Window(screen, "QuestPanel", HEADER_COLOR)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(W, H)
	root.Visible = false
	root.ZIndex = Z

	local skin = CardKit.skin(root, HEADER_COLOR, "Quests", HEADER, Z)
	local close = skin.close

	-- ─── Vade sekmeleri ─────────────────────────────────────────────────────

	local tabs = Instance.new("Frame")
	tabs.Position = UDim2.fromOffset(16, 12)
	tabs.Size = UDim2.new(1, -32, 0, 70)
	tabs.BackgroundTransparency = 1
	tabs.ZIndex = Z + 1
	tabs.Parent = skin.body

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 10)
	tabLayout.Parent = tabs

	type Tab = { holder: Frame, card: Frame, name: TextLabel, timer: TextLabel, dot: TextLabel, tint: Color3, scale: UIScale }
	local tabButtons: { [string]: Tab } = {}

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(16, 94)
	list.Size = UDim2.new(1, -24, 1, -134)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(200, 210, 230)
	list.ScrollBarImageTransparency = 0.3
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ZIndex = Z + 1
	list.Parent = skin.body

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = list
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 2)
	listPad.PaddingBottom = UDim.new(0, 8)
	listPad.PaddingRight = UDim.new(0, 10)
	listPad.Parent = list

	local CARD_W = W - 24 - 16 - 10 - 8

	local footer = CardKit.bold(skin.body, "", 18, Color3.fromRGB(200, 210, 230), Z + 2, 2)
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -8)
	footer.Size = UDim2.new(1, -32, 0, 24)

	-- ─── Veri ───────────────────────────────────────────────────────────────

	local claimRemote = Net.Get("QuestClaim")

	local payload: { Tier } = {}
	local selected: string? = nil
	local endsAt: { [string]: number } = {}

	-- Sekme tıklaması yeniden çizmeli ama çizim aşağıda tanımlı; önden bildir
	local redraw: () -> ()

	local function readyIn(tier: Tier): number
		local n = 0
		for _, entry in tier.entries do
			if entry.done and not entry.claimed then
				n += 1
			end
		end
		return n
	end

	local function makeTab(tier: Tier, order: number): Tab
		local tint = tintOf(tier.id, order)
		local holder = Instance.new("Frame")
		holder.LayoutOrder = order
		holder.Size = UDim2.new(1 / 3, -7, 1, 0)
		holder.BackgroundTransparency = 1
		holder.ZIndex = Z + 2
		holder.Parent = tabs
		local scale = Instance.new("UIScale")
		scale.Parent = holder

		local card = CardKit.card(holder, tint, UDim2.fromScale(1, 1), Z + 2, UDim2.fromScale(0.5, 0.5), 260)
		local name = CardKit.bold(card, string.upper(tier.name), 24, WHITE, Z + 4, 3)
		name.Position = UDim2.fromOffset(10, 6)
		name.Size = UDim2.new(1, -20, 0, 30)
		CardKit.fit(name, 24, 12)
		local timer = CardKit.bold(card, "", 15, CardKit.YELLOW, Z + 4, 2)
		timer.Position = UDim2.fromOffset(10, 38)
		timer.Size = UDim2.new(1, -20, 0, 20)

		-- Hazır ödül sayısı: kırmızı daire, sekmenin sağ üstünde
		local dot = CardKit.bold(holder, "", 16, WHITE, Z + 6, 2)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.new(1, -4, 0, 4)
		dot.Size = UDim2.fromOffset(28, 28)
		dot.BackgroundTransparency = 0
		dot.BackgroundColor3 = Color3.fromRGB(226, 30, 40)
		dot.Visible = false
		CardKit.corner(dot, 14)
		CardKit.border(dot, CardKit.OUTLINE, 2.5)

		local hit = Instance.new("TextButton")
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = Z + 7
		hit.Parent = holder
		local id = tier.id
		hit.MouseButton1Click:Connect(function()
			selected = id
			redraw()
		end)

		return { holder = holder, card = card, name = name, timer = timer, dot = dot, tint = tint, scale = scale }
	end

	local cards: { Instance } = {}

	local function makeCard(tier: Tier, tierTint: Color3, entry: Entry, order: number)
		local ready = entry.done and not entry.claimed
		local tint = if entry.claimed then DONE_TINT elseif ready then READY_TINT else tierTint

		local card = CardKit.card(list, tint, UDim2.fromOffset(CARD_W, 104), Z + 2, UDim2.fromScale(0.08, 0.5), 280)
		card.LayoutOrder = order
		table.insert(cards, card)

		--[[
			Sol rozet: durumu tek bakışta söylüyor. Toplanan görevde tik,
			hazırda parlayan yıldız, devam edende vade rengindeki mürettebat.
		]]
		local badge = CardKit.badge(card, 76, tint, Z + 4)
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 12, 0.5, 0)
		local slot = badge:FindFirstChild("Slot") :: Frame
		if entry.claimed or ready then
			local mark = CardKit.bold(slot, if entry.claimed then "✓" else "★", 44,
				if entry.claimed then Color3.fromRGB(140, 230, 140) else CardKit.YELLOW, Z + 6, 3)
			mark.Size = UDim2.fromScale(1, 1)
		else
			UiKit.Crewmate(slot, 46, tint:Lerp(WHITE, 0.5))
		end

		local text = CardKit.bold(card, entry.text, 24, if entry.claimed then Color3.fromRGB(190, 196, 210) else WHITE, Z + 5, 3)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.Position = UDim2.fromOffset(100, 10)
		text.Size = UDim2.new(1, -278, 0, 30)
		CardKit.fit(text, 24, 12)

		local shown = if entry.cash then "$" .. Config.FormatCash(entry.value) else tostring(entry.value)
		local goal = if entry.cash then "$" .. Config.FormatCash(entry.goal) else tostring(entry.goal)
		local bar = CardKit.bar(card, UDim2.new(1, -278, 0, 26), if entry.done then Color3.fromRGB(110, 230, 80) else CardKit.YELLOW, Z + 5, 16)
		bar.frame.Position = UDim2.fromOffset(100, 52)
		local ratio = if entry.done then 1 else math.clamp(entry.value / math.max(1, entry.goal), 0, 1)
		bar.set(0, if entry.done then goal .. " / " .. goal else shown .. " / " .. goal)
		TweenService:Create(bar.fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(ratio, 1) }):Play()
		bar.fill.Visible = ratio > 0.001

		-- ─── Sağ taraf: ödül / CLAIM / DONE ──────────────────────────────
		local reward = "+$" .. Config.FormatCash(tier.reward)
		if ready then
			local claim = CardKit.button(card, UDim2.fromOffset(160, 70), Z + 5, 30)
			claim.holder.AnchorPoint = Vector2.new(1, 0.5)
			claim.holder.Position = UDim2.new(1, -12, 0.5, 2)
			claim.set("CLAIM", CardKit.GREEN)
			claim.label.Size = UDim2.new(1, -10, 0.62, 0)
			local sub = CardKit.bold(claim.button, reward, 16, Color3.fromRGB(240, 255, 210), Z + 8, 2)
			sub.Position = UDim2.new(0, 5, 0.55, 0)
			sub.Size = UDim2.new(1, -10, 0.4, 0)
			CardKit.fit(sub, 16, 10)
			-- Hazır kart hafifçe nabız atıyor: "buraya bas"
			local pulse = Instance.new("UIScale")
			pulse.Parent = claim.holder
			TweenService:Create(pulse, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.06 }):Play()

			local tierId, questId = tier.id, entry.id
			claim.button.MouseButton1Click:Connect(function()
				-- Basılır basılmaz kapanıyor: yanıt gelene kadar ikinci istek gitmesin
				claim.holder.Visible = false
				claimRemote:FireServer(tierId, questId)
			end)
		else
			local tag = CardKit.bold(card, if entry.claimed then "DONE" else reward, 28,
				if entry.claimed then Color3.fromRGB(170, 176, 190) else Color3.fromRGB(124, 255, 91), Z + 5, 3.5)
			tag.AnchorPoint = Vector2.new(1, 0.5)
			tag.Position = UDim2.new(1, -16, 0.5, 0)
			tag.Size = UDim2.fromOffset(150, 40)
			tag.TextXAlignment = Enum.TextXAlignment.Right
			CardKit.fit(tag, 28, 12)
		end
	end

	redraw = function()
		for _, card in cards do
			card:Destroy()
		end
		table.clear(cards)

		local totalReady = 0
		for order, tier in payload do
			local tab = tabButtons[tier.id]
			if not tab then
				tab = makeTab(tier, order)
				tabButtons[tier.id] = tab
			end
			local ready = readyIn(tier)
			totalReady += ready
			tab.dot.Visible = ready > 0
			tab.dot.Text = tostring(ready)
		end

		if onReady then
			onReady(totalReady)
		end

		-- Seçili vade yoksa: önce hazır ödülü olan, yoksa ilki
		local current: Tier? = nil
		for _, tier in payload do
			if tier.id == selected then
				current = tier
			end
		end
		if not current then
			for _, tier in payload do
				if readyIn(tier) > 0 then
					current = tier
					break
				end
			end
			current = current or payload[1]
			selected = if current then current.id else nil
		end

		-- Seçili sekme parlak ve büyük, diğerleri sönük
		for id, tab in tabButtons do
			local on = id == selected
			CardKit.tintCard(tab.card, if on then tab.tint else tab.tint:Lerp(DONE_TINT, 0.6))
			tab.scale.Scale = if on then 1 else 0.94
		end

		if not current then
			footer.Text = "Quests are loading..."
			return
		end

		local tint = tabButtons[current.id] and tabButtons[current.id].tint or DEFAULT_TINT
		for order, entry in current.entries do
			makeCard(current, tint, entry, order)
		end

		local claimed = 0
		for _, entry in current.entries do
			if entry.claimed then
				claimed += 1
			end
		end

		--[[
			Alt satır vadenin tamamını söylüyor. Günlükte ekstra ödül var
			(QuestService: hepsi bitince iksir), onu burada hatırlatıyoruz —
			yoksa oyuncu üçüncü görevi neden bitirmesi gerektiğini bilmiyor.
		]]
		local bonus = if current.id == "daily" then '  ·  <font color="#7CFF5B">finish all for a free potion!</font>' else ""
		footer.Text = string.format("%d / %d claimed%s", claimed, #current.entries, bonus)
	end

	local connection = Net.Get("Quests").OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" then
			return
		end
		payload = data
		for _, tier in payload do
			endsAt[tier.id] = os.time() + tier.secondsLeft
		end
		redraw()
	end)

	--[[
		Sekme sayaçları saniyede bir. Pencere kapalıyken de dönüyor ama
		yalnızca üç metin; rozet sayısı bundan etkilenmiyor.
	]]
	local elapsed = 0
	local tick = RunService.Heartbeat:Connect(function(delta)
		elapsed += delta
		if elapsed < 1 then
			return
		end
		elapsed = 0
		if not root.Visible then
			return
		end

		local now = os.time()
		for id, tab in tabButtons do
			local ends = endsAt[id]
			if ends then
				local left = math.max(0, ends - now)
				tab.timer.Text = "resets in " .. Config.FormatDuration(left)
				tab.timer.TextColor3 = if left < 300 then Color3.fromRGB(255, 120, 100) else CardKit.YELLOW
			end
		end
	end)

	close.MouseButton1Click:Connect(function()
		root.Visible = false
	end)

	return {
		Toggle = function()
			root.Visible = not root.Visible
			if root.Visible then
				redraw()
			end
		end,
		Destroy = function()
			connection:Disconnect()
			tick:Disconnect()
			root:Destroy()
		end,
	}
end

return QuestPanel
