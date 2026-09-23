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
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local QuestPanel = {}

local INK = UiKit.INK
local MUTED = UiKit.MUTED
local ACCENT = UiKit.VISOR
local GOOD = UiKit.GOOD
local WARN = UiKit.WARN
local DIM = UiKit.DIM

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

--[[
	`onReady` hazır (toplanmamış) ödül sayısı değişince çağrılıyor; sol
	raydaki QUESTS düğmesinin rozeti buna bağlı.
]]
function QuestPanel.Create(screen: ScreenGui, onReady: ((number) -> ())?): Panel
	local root = UiKit.Window(screen, "QuestPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(520, 470)
	root.Visible = false
	root.ZIndex = Z

	--[[
		Üst şerit: vizör renginde bant, ortasında "• QUESTS •". Referanstaki
		kurdele başlığın karşılığı; panelin ne olduğunu uzaktan söylüyor.
	]]
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 52)
	band.BackgroundColor3 = ACCENT:Lerp(Color3.new(0, 0, 0), 0.55)
	band.BorderSizePixel = 0
	band.ZIndex = Z + 1
	band.Parent = root
	UiKit.Corner(band, 14)

	-- Bandın alt köşeleri düz: altına yapışık ikinci bir şerit
	local bandFoot = Instance.new("Frame")
	bandFoot.Position = UDim2.new(0, 0, 1, -14)
	bandFoot.Size = UDim2.new(1, 0, 0, 14)
	bandFoot.BackgroundColor3 = band.BackgroundColor3
	bandFoot.BorderSizePixel = 0
	bandFoot.ZIndex = Z + 1
	bandFoot.Parent = band

	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(0.5, -78, 0.5, 0)
	badge.Size = UDim2.fromOffset(26, 26)
	badge.BackgroundTransparency = 1
	badge.ZIndex = Z + 2
	badge.Parent = band
	UiKit.Clipboard(badge, 26, ACCENT)

	local heading = Instance.new("TextLabel")
	heading.AnchorPoint = Vector2.new(0.5, 0.5)
	heading.Position = UDim2.fromScale(0.5, 0.5)
	heading.Size = UDim2.fromOffset(200, 30)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBlack
	heading.TextSize = 24
	heading.TextColor3 = Color3.new(1, 1, 1)
	heading.TextStrokeTransparency = 0.5
	heading.Text = "• QUESTS •"
	heading.ZIndex = Z + 2
	heading.Parent = band

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 3

	-- ─── Vade sekmeleri ─────────────────────────────────────────────────────

	local tabs = Instance.new("Frame")
	tabs.Position = UDim2.fromOffset(14, 62)
	tabs.Size = UDim2.new(1, -28, 0, 46)
	tabs.BackgroundTransparency = 1
	tabs.ZIndex = Z + 1
	tabs.Parent = root

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabs

	type Tab = { button: TextButton, name: TextLabel, timer: TextLabel, dot: TextLabel, stroke: UIStroke }
	local tabButtons: { [string]: Tab } = {}

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(14, 118)
	list.Size = UDim2.new(1, -28, 1, -160)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = MUTED
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = Z + 1
	list.Parent = root

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = list

	local footer = Instance.new("TextLabel")
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 18, 1, -12)
	footer.Size = UDim2.new(1, -36, 0, 18)
	footer.BackgroundTransparency = 1
	footer.Font = Enum.Font.GothamBold
	footer.TextSize = 12
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextColor3 = MUTED
	footer.Text = ""
	footer.ZIndex = Z + 1
	footer.Parent = root

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
		local button = Instance.new("TextButton")
		button.Name = tier.id
		button.LayoutOrder = order
		button.Size = UDim2.new(1 / 3, -6, 1, 0)
		button.BackgroundColor3 = UiKit.ROW
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Text = ""
		button.ZIndex = Z + 2
		button.Parent = tabs
		UiKit.Corner(button, 10)
		local stroke = UiKit.Stroke(button, ACCENT, 1.6, 1)

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(12, 5)
		name.Size = UDim2.new(1, -40, 0, 18)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBlack
		name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = INK
		name.Text = string.upper(tier.name)
		name.ZIndex = Z + 3
		name.Parent = button

		local timer = Instance.new("TextLabel")
		timer.Position = UDim2.fromOffset(12, 23)
		timer.Size = UDim2.new(1, -24, 0, 16)
		timer.BackgroundTransparency = 1
		timer.Font = Enum.Font.GothamMedium
		timer.TextSize = 11
		timer.TextXAlignment = Enum.TextXAlignment.Left
		timer.TextColor3 = MUTED
		timer.ZIndex = Z + 3
		timer.Parent = button

		-- Hazır ödül sayısı: kırmızı daire, sekmenin sağ üstünde
		local dot = Instance.new("TextLabel")
		dot.AnchorPoint = Vector2.new(1, 0)
		dot.Position = UDim2.new(1, -8, 0, 8)
		dot.Size = UDim2.fromOffset(20, 20)
		dot.BackgroundColor3 = UiKit.CREW.RED
		dot.BorderSizePixel = 0
		dot.Font = Enum.Font.GothamBlack
		dot.TextSize = 11
		dot.TextColor3 = Color3.new(1, 1, 1)
		dot.Visible = false
		dot.ZIndex = Z + 4
		dot.Parent = button
		UiKit.Corner(dot, 10)

		local id = tier.id
		button.MouseButton1Click:Connect(function()
			selected = id
			redraw()
		end)

		return { button = button, name = name, timer = timer, dot = dot, stroke = stroke }
	end

	local cards: { Instance } = {}

	local function makeCard(tier: Tier, entry: Entry, order: number)
		local ready = entry.done and not entry.claimed

		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.Size = UDim2.new(1, -8, 0, 66)
		card.BackgroundColor3 = UiKit.ROW
		card.BackgroundTransparency = if entry.claimed then 0.45 else 0
		card.BorderSizePixel = 0
		card.ZIndex = Z + 2
		card.Parent = list
		UiKit.Corner(card, 12)
		UiKit.Stroke(card,
			if ready then GOOD elseif entry.claimed then DIM else ACCENT,
			if ready then 2 else 1.2,
			if ready then 0.1 else 0.7)
		table.insert(cards, card)

		--[[
			Sol kutu: durumu tek bakışta söyleyen ikon. Toplanan görevde
			yeşil tik, hazırda parlayan yıldız, devam edende vade rengindeki
			mürettebat.
		]]
		local icon = Instance.new("Frame")
		icon.Position = UDim2.fromOffset(10, 11)
		icon.Size = UDim2.fromOffset(44, 44)
		icon.BackgroundColor3 = if entry.claimed then GOOD:Lerp(Color3.new(0, 0, 0), 0.55)
			elseif ready then WARN:Lerp(Color3.new(0, 0, 0), 0.5)
			else UiKit.SHELL_DEEP
		icon.BorderSizePixel = 0
		icon.ZIndex = Z + 3
		icon.Parent = card
		UiKit.Corner(icon, 10)

		if entry.claimed or ready then
			local mark = Instance.new("TextLabel")
			mark.Size = UDim2.fromScale(1, 1)
			mark.BackgroundTransparency = 1
			mark.Font = Enum.Font.GothamBlack
			mark.TextSize = 24
			mark.TextColor3 = if entry.claimed then GOOD else WARN
			mark.Text = if entry.claimed then "✓" else "★"
			mark.ZIndex = Z + 4
			mark.Parent = icon
		else
			UiKit.Crewmate(icon, 28, ACCENT)
		end

		local text = Instance.new("TextLabel")
		text.Position = UDim2.fromOffset(66, 10)
		text.Size = UDim2.new(1, -206, 0, 20)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextSize = 14
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.TextColor3 = if entry.claimed then MUTED else INK
		text.Text = entry.text
		text.ZIndex = Z + 3
		text.Parent = card

		local shown = if entry.cash then "$" .. Config.FormatCash(entry.value) else tostring(entry.value)
		local goal = if entry.cash then "$" .. Config.FormatCash(entry.goal) else tostring(entry.goal)

		local progress = Instance.new("TextLabel")
		progress.AnchorPoint = Vector2.new(1, 0)
		progress.Position = UDim2.new(1, -140, 0, 32)
		progress.Size = UDim2.fromOffset(90, 14)
		progress.BackgroundTransparency = 1
		progress.Font = Enum.Font.GothamBold
		progress.TextSize = 11
		progress.TextXAlignment = Enum.TextXAlignment.Right
		progress.TextColor3 = MUTED
		progress.Text = if entry.done then goal .. " / " .. goal else shown .. " / " .. goal
		progress.ZIndex = Z + 3
		progress.Parent = card

		local barHolder = Instance.new("Frame")
		barHolder.Position = UDim2.fromOffset(66, 48)
		barHolder.Size = UDim2.new(1, -206, 0, 8)
		barHolder.BackgroundTransparency = 1
		barHolder.ZIndex = Z + 3
		barHolder.Parent = card
		local track, fill = UiKit.Bar(barHolder, 8, if entry.done then GOOD else ACCENT)
		track.ZIndex = Z + 3
		fill.ZIndex = Z + 4
		local ratio = if entry.done then 1 else math.clamp(entry.value / math.max(1, entry.goal), 0, 1)
		TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(ratio, 0, 1, 0) }):Play()

		-- ─── Sağ taraf: ödül / CLAIM / DONE ──────────────────────────────
		local reward = "+$" .. Config.FormatCash(tier.reward)

		if ready then
			local holder, claim = UiKit.Raised(card, "Claim", UiKit.CREW.GREEN:Lerp(GOOD, 0.35), UDim2.fromOffset(118, 46), 10)
			holder.AnchorPoint = Vector2.new(1, 0.5)
			holder.Position = UDim2.new(1, -10, 0.5, 0)
			holder.ZIndex = Z + 3

			local claimText = Instance.new("TextLabel")
			claimText.Position = UDim2.fromOffset(0, 4)
			claimText.Size = UDim2.new(1, 0, 0, 18)
			claimText.BackgroundTransparency = 1
			claimText.Font = Enum.Font.GothamBlack
			claimText.TextSize = 14
			claimText.TextColor3 = Color3.new(1, 1, 1)
			claimText.TextStrokeTransparency = 0.5
			claimText.Text = "CLAIM"
			claimText.ZIndex = Z + 6
			claimText.Parent = claim

			local claimReward = Instance.new("TextLabel")
			claimReward.Position = UDim2.fromOffset(0, 21)
			claimReward.Size = UDim2.new(1, 0, 0, 16)
			claimReward.BackgroundTransparency = 1
			claimReward.Font = Enum.Font.GothamBold
			claimReward.TextSize = 12
			claimReward.TextColor3 = Color3.fromRGB(230, 255, 200)
			claimReward.TextStrokeTransparency = 0.6
			claimReward.Text = reward
			claimReward.ZIndex = Z + 6
			claimReward.Parent = claim

			local tierId, questId = tier.id, entry.id
			claim.MouseButton1Click:Connect(function()
				-- Basılır basılmaz kapanıyor: yanıt gelene kadar ikinci istek gitmesin
				holder.Visible = false
				claimRemote:FireServer(tierId, questId)
			end)
		else
			local tag = Instance.new("TextLabel")
			tag.AnchorPoint = Vector2.new(1, 0.5)
			tag.Position = UDim2.new(1, -16, 0.5, 0)
			tag.Size = UDim2.fromOffset(110, 30)
			tag.BackgroundTransparency = 1
			tag.Font = Enum.Font.GothamBlack
			tag.TextSize = 14
			tag.TextXAlignment = Enum.TextXAlignment.Right
			tag.TextColor3 = if entry.claimed then DIM else UiKit.CREW.LIME
			tag.Text = if entry.claimed then "DONE" else reward
			tag.ZIndex = Z + 3
			tag.Parent = card
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

		for id, tab in tabButtons do
			local on = id == selected
			tab.button.BackgroundColor3 = if on then ACCENT:Lerp(UiKit.ROW, 0.72) else UiKit.ROW
			tab.stroke.Transparency = if on then 0.1 else 1
			tab.name.TextColor3 = if on then ACCENT else INK
		end

		if not current then
			footer.Text = "Quests are loading…"
			return
		end

		for order, entry in current.entries do
			makeCard(current, entry, order)
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
		local bonus = if current.id == "daily" then "  ·  finish all for a free potion" else ""
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
				tab.timer.TextColor3 = if left < 300 then WARN else MUTED
			end
		end
	end)

	close.Activated:Connect(function()
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
