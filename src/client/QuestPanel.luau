--!strict
--[[
	Görev paneli: 30 dakikalık, 3 saatlik ve günlük hedefler.

	Sunucu (QuestService) "Quests" remote'uyla vade listesini gönderiyor;
	burada sadece çiziliyor. İlerleme sunucuda hesaplanıyor, istemci onu
	değiştiremiyor.

	Yer: sol kenar, sıralama tablosunun altı. Sol üst şerit sırayla nakit
	(y=20), gelir (y=62) ve TOP PLAYERS (y=104, 172 yüksek) ile dolu, yani
	ilk boş nokta y=288. Sağ üst üs paneline, alt orta bildirimlere,
	sağ alt haritaya ayrılmış.

	Yükseklik ekrana göre sınırlanıyor ve sığmazsa gövde kayıyor: küçük
	ekranda (özellikle telefonda) panel alt soldaki öğretici kutusunun
	üstüne biniyordu. Sağ üst üs paneline, alt orta bildirimlere ayrılmış.

	Geri sayım istemcide dönüyor: sunucu bitiş anını gönderiyor, saniyede
	bir paket yollamıyor.

	Başlığa tıklayınca katlanıyor. Ekran kalabalıksa oyuncu kapatabilmeli;
	kapalıyken bile başlıkta kaç görevin bittiği yazıyor.

	Kullanım (init.client.luau içinde, screen kurulduktan sonra):
		local QuestPanel = require(script.QuestPanel)
		local quests = QuestPanel.Create(screen)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local QuestPanel = {}

--[[
	Renkler ve parçalar UiKit'ten. Her panel kendi kutu tasarımını
	kurduğunda aynı oyunda beş farklı dil oluyordu; rebirth paneli doğru
	dili kurdu, hepsi artık onu konuşuyor.

	Vurgu rengi panele özel: görevler GÖREV panelidir, mürettebat
	tulumunun camgöbeği vizörü burada imza rengi.
]]
local INK = UiKit.INK
local MUTED = UiKit.MUTED
local ACCENT = UiKit.VISOR
local GOOD = UiKit.GOOD
local DIM = UiKit.DIM

local WIDTH = 300
-- Sıralama tablosu y=104'te başlayıp 172 yükseliyor; ilk boş nokta burası
local TOP = 288
-- Bir görev satırı + aralığı. Yükseklik hep bunun katına yuvarlanıyor.
local ROW = 34
-- Vade başlığının yüksekliği
local SECTION_HEAD = 18
-- Öğretici kutusu açıkken alt solda ona ayrılan yer
local TUTORIAL_RESERVE = 170
-- Öğretici yokken sadece kenar boşluğu
local EDGE_RESERVE = 32
local MIN_BODY = 90

export type Panel = {
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

function QuestPanel.Create(screen: ScreenGui): Panel
	local root = UiKit.Shell(screen, "Quests", ACCENT)
	root.Position = UDim2.new(0, 24, 0, TOP)
	root.Size = UDim2.new(0, WIDTH, 0, 40)
	root.ClipsDescendants = true

	-- ─── Başlık ─────────────────────────────────────────────────────────────

	--[[
		Başlıkta küçük bir mürettebat silueti duruyor.

		Panelin ne olduğunu ikonla değil FİGÜRLE söylüyor: oyuncunun
		sahada oynadığı karakterin aynısı. Oyunun her yerinde aynı üç
		parça (kapsül, çanta, vizör), o yüzden bakışta tanınıyor ve
		arayüz oyunun içinden çıkmış gibi duruyor.
	]]
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Position = UDim2.fromOffset(12, 7)
	badge.Size = UDim2.fromOffset(20, 20)
	badge.BackgroundTransparency = 1
	badge.Parent = root
	UiKit.Crewmate(badge, 18, ACCENT)

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.Position = UDim2.fromOffset(36, 0)
	header.Size = UDim2.new(1, -36, 0, 34)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 14
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = ACCENT
	header.Text = "QUESTS"
	header.AutoButtonColor = false
	header.Parent = root

	local headerCount = Instance.new("TextLabel")
	headerCount.Name = "Count"
	headerCount.AnchorPoint = Vector2.new(1, 0)
	headerCount.Position = UDim2.new(1, -14, 0, 0)
	headerCount.Size = UDim2.new(0, 70, 0, 34)
	headerCount.BackgroundTransparency = 1
	headerCount.Font = Enum.Font.GothamMedium
	headerCount.TextSize = 13
	headerCount.TextXAlignment = Enum.TextXAlignment.Right
	headerCount.TextColor3 = MUTED
	headerCount.Text = ""
	headerCount.Parent = root

	-- ─── Gövde ──────────────────────────────────────────────────────────────

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Position = UDim2.new(0, 0, 0, 34)
	body.Size = UDim2.new(1, 0, 0, 0)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 3
	body.ScrollBarImageColor3 = MUTED
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = body

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = body

	--[[
		Vade bölümleri yeniden yaratılmıyor, güncelleniyor. Her pakette
		baştan kurmak, oyuncu tam tıklarken paneli altından çekiyordu.
	]]
	type Row = {
		frame: Frame,
		label: TextLabel,
		fill: Frame,
		track: Frame,
		claim: TextButton,
	}

	type Section = {
		frame: Frame,
		title: TextLabel,
		timer: TextLabel,
		rows: { Row },
	}

	local claimRemote = Net.Get("QuestClaim")

	--[[
		Hangi düğmenin hangi görevi topladığı burada tutuluyor.

		Tıklama olayı satır kurulurken BİR KEZ bağlanıyor; her çizimde
		yeniden bağlansaydı panel her güncellendiğinde bir kat daha olay
		tetiklenirdi ve tek tıklama birden fazla istek gönderirdi.
	]]
	local rowTarget: { [TextButton]: { tier: string, quest: string } } = {}

	local sections: { [string]: Section } = {}
	local expanded = true
	local timers: { [string]: number } = {}

	local function newSection(tier: Tier, order: number): Section
		local frame = Instance.new("Frame")
		frame.Name = tier.id
		frame.LayoutOrder = order
		frame.Size = UDim2.new(1, 0, 0, 30)
		frame.BackgroundTransparency = 1
		frame.Parent = body

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(0.6, 0, 0, 18)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 12
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = MUTED
		title.Text = string.upper(tier.name)
		title.Parent = frame

		local timer = Instance.new("TextLabel")
		timer.Name = "Timer"
		timer.AnchorPoint = Vector2.new(1, 0)
		timer.Position = UDim2.new(1, 0, 0, 0)
		timer.Size = UDim2.new(0.4, 0, 0, 18)
		timer.BackgroundTransparency = 1
		timer.Font = Enum.Font.GothamMedium
		timer.TextSize = 12
		timer.TextXAlignment = Enum.TextXAlignment.Right
		timer.TextColor3 = MUTED
		timer.Text = ""
		timer.Parent = frame

		return { frame = frame, title = title, timer = timer, rows = {} }
	end

	local function newRow(section: Section, index: number)
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. index
		frame.Position = UDim2.new(0, 0, 0, 18 + (index - 1) * 34)
		frame.Size = UDim2.new(1, 0, 0, 32)
		frame.BackgroundTransparency = 1
		frame.Parent = section.frame

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 18)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = INK
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = ""
		label.Parent = frame

		local track, fill = UiKit.Bar(frame, 5, ACCENT)
		track.Position = UDim2.new(0, 0, 0, 21)

		--[[
			Toplama düğmesi.

			Ödül artık kendiliğinden gelmiyor: oyuncu bunu basıyor. Sebep,
			otomatik ödülde görevlerin hiç okunmamasıydı — ekranın
			kenarında bir bildirim geçiyor ve bitiyordu. Toplamak için
			panele bakmak gerekince görevler görünür hale geliyor.

			Satırın sağında ve yalnızca hazır olduğunda görünüyor; boş
			dururken satırı kalabalıklaştırmıyor.
		]]
		local claim = Instance.new("TextButton")
		claim.Name = "Claim"
		claim.AnchorPoint = Vector2.new(1, 0)
		claim.Position = UDim2.new(1, 0, 0, 0)
		claim.Size = UDim2.fromOffset(62, 18)
		claim.BackgroundColor3 = GOOD
		claim.BorderSizePixel = 0
		claim.Font = Enum.Font.GothamBold
		claim.TextSize = 11
		claim.TextColor3 = UiKit.SHELL_DEEP
		claim.Text = "CLAIM"
		claim.AutoButtonColor = false
		claim.Visible = false
		claim.Parent = frame
		UiKit.Corner(claim, 5)

		claim.MouseEnter:Connect(function()
			claim.BackgroundColor3 = GOOD:Lerp(Color3.new(1, 1, 1), 0.35)
		end)
		claim.MouseLeave:Connect(function()
			claim.BackgroundColor3 = GOOD
		end)

		claim.Activated:Connect(function()
			local target = rowTarget[claim]
			if not target then
				return
			end
			-- Basılır basılmaz gizleniyor: sunucu yanıtı gelene kadar
			-- ikinci kez basılmasın
			claim.Visible = false
			claimRemote:FireServer(target.tier, target.quest)
		end)

		table.insert(section.rows, {
			frame = frame, label = label, fill = fill, track = track, claim = claim,
		})
	end

	--[[
		Panelin yüksekliği içeriğe göre ama ekrana sığdığı kadar.

		İki kural:

		1. Alt sınır ekrana göre. Sınırsız büyüseydi üç vade × iki görev,
		   küçük ekranda alt soldaki öğretici kutusunun üstüne binerdi.
		   Öğretici kapalıyken (bitmiş oyuncu) o yer boşuna ayrılmıyor.

		2. Yükseklik satır katına yuvarlanıyor. Ham piksele kırpınca panel
		   bir görevin tam ortasından kesiliyordu ve bozuk görünüyordu;
		   artık ya satırın tamamı görünüyor ya hiç görünmüyor, gerisi
		   kaydırılıyor.
	]]
	local function resize()
		if not expanded then
			root.Size = UDim2.new(0, WIDTH, 0, 34)
			return
		end

		local wanted = 12
		for _, section in sections do
			if section.frame.Visible then
				wanted += section.frame.AbsoluteSize.Y + 8
			end
		end

		local tutorial = screen:FindFirstChild("Tutorial")
		local reserve = if tutorial and tutorial:IsA("GuiObject") and tutorial.Visible
			then TUTORIAL_RESERVE
			else EDGE_RESERVE

		local available = screen.AbsoluteSize.Y - TOP - reserve
		local height = math.min(wanted, available)

		-- Satırın ortasından kesme: sığan tam satır sayısına yuvarla
		if height < wanted then
			local usable = height - SECTION_HEAD - 12
			height = SECTION_HEAD + 12 + math.floor(usable / ROW) * ROW
		end

		height = math.max(MIN_BODY, height)

		body.Size = UDim2.new(1, 0, 0, height)
		root.Size = UDim2.new(0, WIDTH, 0, 34 + height)
	end

	-- Ekran döndüğünde ya da pencere boyutlandığında yeniden ölç
	local resizeConnection = screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)

	--[[
		Öğretici kutusu bitince kapanıyor ve alt solda yer açılıyor; panel
		o yeri kullanabilsin diye yeniden ölçüyoruz. Kutu henüz yoksa
		(paneller ayrı ayrı kuruluyor) beklemeye gerek yok, ilk resize
		zaten öğreticisiz varsayıyor.
	]]
	local tutorialWatch: RBXScriptConnection? = nil
	local existing = screen:FindFirstChild("Tutorial")
	if existing and existing:IsA("GuiObject") then
		tutorialWatch = existing:GetPropertyChangedSignal("Visible"):Connect(resize)
	else
		tutorialWatch = screen.ChildAdded:Connect(function(child)
			if child.Name == "Tutorial" and child:IsA("GuiObject") then
				child:GetPropertyChangedSignal("Visible"):Connect(resize)
				resize()
			end
		end)
	end

	local function apply(payload: { Tier })
		local doneCount, totalCount, readyCount = 0, 0, 0

		for order, tier in payload do
			local section = sections[tier.id]
			if not section then
				section = newSection(tier, order)
				sections[tier.id] = section
			end

			section.frame.Visible = true
			section.title.Text = string.upper(tier.name)
			timers[tier.id] = os.time() + tier.secondsLeft

			-- Eksik satırları yarat; fazlası gizleniyor
			while #section.rows < #tier.entries do
				newRow(section, #section.rows + 1)
			end
			for index = #tier.entries + 1, #section.rows do
				section.rows[index].frame.Visible = false
			end

			for index, entry in tier.entries do
				local row = section.rows[index]
				row.frame.Visible = true

				totalCount += 1
				if entry.claimed then
					doneCount += 1
				end
				if entry.done and not entry.claimed then
					readyCount += 1
				end

				local shown = if entry.cash
					then Config.FormatCash(entry.value)
					else tostring(entry.value)
				local target = if entry.cash
					then Config.FormatCash(entry.goal)
					else tostring(entry.goal)

				--[[
					Üç hâl var ve üçü de farklı görünüyor:

					  devam ediyor  → ilerleme çubuğu, sayaç
					  hazır          → CLAIM düğmesi, çubuk yok
					  toplandı       → yeşil tik, düğme yok

					"Hazır" ile "toplandı" ayrı olmasaydı oyuncu ödülünü
					alıp almadığını bilemezdi.
				]]
				rowTarget[row.claim] = { tier = tier.id, quest = entry.id }

				if entry.done and entry.claimed then
					row.label.Text = "✓  " .. entry.text
					row.label.TextColor3 = GOOD
					row.track.Visible = false
					row.claim.Visible = false

				elseif entry.done then
					-- Hazır: satır dikkat çekmeli, ödül orada duruyor
					row.label.Text = entry.text
					row.label.TextColor3 = UiKit.WARN
					row.track.Visible = false
					row.claim.Visible = true

				else
					row.label.Text = string.format("%s   %s / %s", entry.text, shown, target)
					row.label.TextColor3 = INK
					row.fill.BackgroundColor3 = ACCENT
					row.track.Visible = true
					row.claim.Visible = false
				end

				TweenService:Create(
					row.fill,
					TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.new(math.clamp(entry.value / math.max(1, entry.goal), 0, 1), 0, 1, 0) }
				):Play()
			end

			section.frame.Size = UDim2.new(1, 0, 0, 18 + #tier.entries * 34)
		end

		-- Sunucudan gelmeyen vadeyi gizle
		for id, section in sections do
			local found = false
			for _, tier in payload do
				if tier.id == id then
					found = true
					break
				end
			end
			section.frame.Visible = found
		end

		--[[
			Başlık toplanmayı bekleyen ödül varsa onu söylüyor. Panel
			katlanmışken bile görülüyor; oyuncu ödülünü unutmasın.
		]]
		if readyCount > 0 then
			headerCount.Text = string.format("%d READY", readyCount)
			headerCount.TextColor3 = UiKit.WARN
		else
			headerCount.Text = string.format("%d / %d", doneCount, totalCount)
			headerCount.TextColor3 = if doneCount == totalCount and totalCount > 0 then GOOD else MUTED
		end
		resize()
	end

	header.Activated:Connect(function()
		expanded = not expanded
		body.Visible = expanded
		header.Text = if expanded then "QUESTS" else "QUESTS  ▸"
		resize()
	end)

	local connection = Net.Get("Quests").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			apply(payload)
		end
	end)

	--[[
		Geri sayım. Saniyede bir yeter; her karede güncellemek aynı metni
		altmış kez yazmak olurdu.
	]]
	local elapsed = 0
	local tick = RunService.Heartbeat:Connect(function(delta)
		elapsed += delta
		if elapsed < 1 then
			return
		end
		elapsed = 0

		local now = os.time()
		for id, section in sections do
			local endsAt = timers[id]
			if endsAt then
				local left = math.max(0, endsAt - now)
				section.timer.Text = Config.FormatDuration(left)
				section.timer.TextColor3 = if left < 300 then UiKit.WARN else DIM
			end
		end
	end)

	return {
		Destroy = function()
			connection:Disconnect()
			tick:Disconnect()
			resizeConnection:Disconnect()
			if tutorialWatch then
				tutorialWatch:Disconnect()
			end
			root:Destroy()
		end,
	}
end

return QuestPanel
