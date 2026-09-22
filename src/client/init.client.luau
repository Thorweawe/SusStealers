--!strict
-- HUD: nakit, saniyelik gelir, üs durumu ve bildirim şeridi.
-- Kod içi yorumlar Türkçe, oyuncunun gördüğü metinler İngilizce.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CarryGuide = require(script.CarryGuide)
local DecorFX = require(script.DecorFX)
local FloorStyle = require(script.FloorStyle)
local Index = require(script.Index)
local Leaderboard = require(script.Leaderboard)
local Lobby = require(script.Lobby)
local Minimap = require(script.Minimap)
local OwnerColors = require(script.OwnerColors)
local PromptFilter = require(script.PromptFilter)
local RarityFX = require(script.RarityFX)
local ScreenFX = require(script.ScreenFX)
local SoundFX = require(script.SoundFX)
local ThiefTrail = require(script.ThiefTrail)

-- Sunucu tarafi hazir olan paneller. Bunlari sunucu sehridi yazdi ama
-- gorunumleri bu sehride: yerlesim, renk ve animasyonu degistirmek
-- serbest, sunucu yalnizca veri gonderiyor.
local ChatTitles = require(script.ChatTitles)
local TutorialUI = require(script.TutorialUI)
local QuestPanel = require(script.QuestPanel)
local Menus = require(script.Menus)
local HudToggle = require(script.HudToggle)
local Music = require(script.Music)
local OwnPlot = require(script.OwnPlot)
local Sprint = require(script.Sprint)
local UpgradePanel = require(script.UpgradePanel)
local RebirthPanel = require(script.RebirthPanel)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local GOOD = Color3.fromRGB(120, 255, 150)
local WARN = Color3.fromRGB(255, 190, 90)
local BAD = Color3.fromRGB(255, 90, 90)
local PANEL = Color3.fromRGB(18, 20, 28)

-- ─── Arayüz ─────────────────────────────────────────────────────────────────

local screen = Instance.new("ScreenGui")
screen.Name = "SusStealersHud"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local function newLabel(name: string, position: UDim2, size: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = INK
	label.TextStrokeTransparency = 0.4
	label.Parent = screen
	return label
end

local cashLabel = newLabel("Cash", UDim2.new(0, 24, 0, 20), UDim2.new(0, 360, 0, 44), 34)
cashLabel.TextColor3 = GOOD

local incomeLabel = newLabel("Income", UDim2.new(0, 24, 0, 62), UDim2.new(0, 360, 0, 28), 20)
incomeLabel.TextColor3 = MUTED

-- ─── Üs paneli ──────────────────────────────────────────────────────────────
-- Sağ üstte: kaide doluluğu, kilit durumu ve taşınan karakter.

local panel = Instance.new("Frame")
panel.Name = "PlotPanel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -24, 0, 20)
panel.Size = UDim2.new(0, 260, 0, 104)
panel.BackgroundColor3 = PANEL
-- Saydamlik kaldirildi: arkadaki dunya panelin icinden gorunuyordu ve
-- "Podiums / Lock / Carrying" satirlari okunmuyordu.
panel.BackgroundTransparency = 0
panel.BorderSizePixel = 0
panel.Parent = screen

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(86, 96, 120)
panelStroke.Thickness = 1
panelStroke.Transparency = 0.35
panelStroke.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 10)
panelPadding.PaddingLeft = UDim.new(0, 14)
panelPadding.PaddingRight = UDim.new(0, 14)
panelPadding.Parent = panel

local panelLayout = Instance.new("UIListLayout")
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Padding = UDim.new(0, 4)
panelLayout.Parent = panel

--[[ Panelde "başlık  değer" biçiminde tek satır üretir. ]]
local function newRow(order: number, caption: string): TextLabel
	local row = Instance.new("Frame")
	row.Name = caption
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.45, 0, 1, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = MUTED
	title.Text = caption
	title.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Position = UDim2.new(0.45, 0, 0, 0)
	value.Size = UDim2.new(0.55, 0, 1, 0)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.TextSize = 15
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextColor3 = INK
	value.Text = "—"
	value.Parent = row

	return value
end

local podiumValue = newRow(1, "Podiums")
local lockValue = newRow(2, "Lock")
local carryValue = newRow(3, "Carrying")

-- ─── Bildirimler ────────────────────────────────────────────────────────────

local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.AnchorPoint = Vector2.new(0.5, 1)
toastHolder.Position = UDim2.new(0.5, 0, 1, -40)
toastHolder.Size = UDim2.new(0, 520, 0, 200)
toastHolder.BackgroundTransparency = 1
toastHolder.Parent = screen

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 6)
layout.Parent = toastHolder

local toastOrder = 0

local function showToast(text: string, color: Color3)
	toastOrder += 1

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 500, 0, 40)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.LayoutOrder = toastOrder
	frame.Parent = toastHolder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, 0)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Parent = frame

	local label = Instance.new("TextLabel")
	label.Position = UDim2.new(0, 16, 0, 0)
	label.Size = UDim2.new(1, -28, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = INK
	label.Text = text
	label.Parent = frame

	task.delay(3, function()
		if not frame.Parent then
			return
		end
		local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(stripe, info, { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		frame:Destroy()
	end)
end

-- ─── Efektler ───────────────────────────────────────────────────────────────
-- Ses ve ekran geri bildirimi bildirimlere bağlanıyor: sunucu zaten ne olduğunu
-- söylüyor, ayrı bir olay akışına gerek yok.

local effects = ScreenFX.Create(screen)
SoundFX.Preload()
SoundFX.StartAmbient()

--[[
	Harita ve üs bilgisi aşağıda kuruluyor ama bildirim işleyicileri burada
	tanımlanıyor. Önden bildirip sonra dolduruyoruz; işleyici tetiklendiğinde
	ikisi de hazır olmuş oluyor.
]]
--[[
	Müzik. Bölgeye göre değişiyor ve çalınma alarmı çalarken kısılıyor —
	alarm oyuncunun duyması GEREKEN şey, müzik onunla yarışmamalı.

	Burada tanımlı çünkü aşağıdaki StealAlert işleyicisi onu kullanıyor;
	dosyanın sonunda tanımlansaydı Lua o satırda yerel değil GLOBAL
	görürdü ve müzik hiç kısılmazdı. Kurulumu panellerle birlikte, en
	sonda yapılıyor.
]]
local music: Music.Handle? = nil

local minimapRef: Minimap.Map? = nil
local currentPlot: Model? = nil

-- Yukseltme arayuzu en sonda kuruluyor (asagidaki mountPanel); ana dongu
-- ona buradan ulasiyor. Kurulmadiysa nil kaliyor ve dongu atliyor.
local upgradePanel: UpgradePanel.Panel? = nil
local rebirthPanel: RebirthPanel.Panel? = nil

--[[
	Sunucu bildirimin TÜRÜNÜ de gönderiyor (dördüncü argüman) ve ses ona
	göre seçiliyor. Eskiden bütün başarılı işlemler aynı tınıydı: satın
	alma, satma, yükseltme, görev hepsi tek sesti.

	Tür gelmezse SoundFX taban sese düşüyor, yani eski çağrılar da çalışıyor.
]]
Net.Get("Notify").OnClientEvent:Connect(function(text: string, isError: boolean, kind: string?)
	showToast(text, if isError then BAD else GOOD)
	SoundFX.Event(kind, isError)
end)

Net.Get("StealAlert").OnClientEvent:Connect(function(thiefName: string, unitName: string)
	showToast(string.format("%s stole your %s!", thiefName, unitName), Color3.fromRGB(255, 70, 110))

	-- Çalınmak bedensel hissedilmeli: köşedeki yazıyı kaçırmak kolay,
	-- kırmızı parlama ve sarsıntı kaçırılmıyor.
	effects.Flash(Color3.fromRGB(255, 40, 60), 0.45, 0.7)
	effects.Shake(1.6, 0.6)

	--[[
		Alarm hırsız karakteri bırakana kadar sürüyor. Karakterin sırtındaki
		CarriedUnit istemciye replike olduğu için bunu sunucuya sormadan
		izleyebiliyoruz: model kaybolduğu an teslim etmiş demektir.
	]]
	-- Alarm boyunca müziği geri çek, bitince aç
	if music then
		music.SetDucked(true)
	end

	--[[
		Aynı koşul hem alarmı hem müziğin kısılmasını yönetiyor: hırsız
		karakteri bıraktığı an ikisi de bitiyor. Ayrı bir zamanlayıcı
		kursaydık biri diğerinden önce biter ve alarm sustuğu halde müzik
		kısık kalırdı.

		Süre sınırı ayrıca: koşul hiç false dönmezse (hırsız çıktı, olay
		kaçtı) müzik sonsuza kadar kısık kalmasın.
	]]
	local function thiefStillCarrying(): boolean
		for _, p in Players:GetPlayers() do
			if p.DisplayName == thiefName then
				local char = p.Character
				return char ~= nil and char:FindFirstChild("CarriedUnit") ~= nil
			end
		end
		return false -- hırsız oyundan çıktı
	end

	SoundFX.AlarmUntil(function()
		local carrying = thiefStillCarrying()
		if not carrying and music then
			music.SetDucked(false)
		end
		return carrying
	end, 45)

	task.delay(46, function()
		if music then
			music.SetDucked(false)
		end
	end)

	-- Haritada soyulan üssü yak ve hırsızı işaretle: peşinden gidebilesin
	if minimapRef then
		local bay = if currentPlot then tonumber(string.match(currentPlot.Name, "%d+")) else nil
		minimapRef.Alert(bay, thiefName)
	end

	print(string.format("[SusStealers] Calinma bildirimi geldi: %s -> %s", thiefName, unitName))
end)

--[[
	TEŞHİS TUŞU (K): çalınma efektlerini yerel olarak tetikler.

	Çalınma efektleri test sırasında hiç görünmedi ve sebebi iki yerden biri
	olabilir: ya sunucu bildirimi ulaşmıyor ya da efektlerin kendisi bozuk.
	Bu tuş efektleri olaydan bağımsız çalıştırıyor, böylece hangisi olduğu
	kesinleşiyor. Sebep bulununca kaldırılacak.
]]
game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.K then
		return
	end

	showToast("TEST: efekt denemesi", Color3.fromRGB(255, 70, 110))
	SoundFX.Alarm()
	effects.Flash(Color3.fromRGB(255, 40, 60), 0.45, 0.7)
	effects.Shake(1.6, 0.6)

	if minimapRef then
		local bay = if currentPlot then tonumber(string.match(currentPlot.Name, "%d+")) else nil
		-- Kendimizi hırsız gösteriyoruz ki nokta işaretlemesi de denensin
		minimapRef.Alert(bay, player.DisplayName)
	end
	print("[SusStealers] K: efektler yerel olarak tetiklendi")
end)

-- ─── Nakit / gelir ──────────────────────────────────────────────────────────

local function refreshCash()
	local cash = player:GetAttribute("Cash") :: number?
	local income = player:GetAttribute("Income") :: number?

	cashLabel.Text = "$" .. Config.FormatCash(cash or 0)
	incomeLabel.Text = string.format("+$%s/s", Config.FormatCash(income or 0))
end

player:GetAttributeChangedSignal("Cash"):Connect(refreshCash)
player:GetAttributeChangedSignal("Income"):Connect(refreshCash)
refreshCash()

-- ─── Üs durumu ──────────────────────────────────────────────────────────────

--[[
	Kendi üssümüz. Arama OwnPlot modülünde: aynı arama Lobby'de de gerekiyor
	ve iki kopya birbirinden ayrışıp bir hataya yol açmıştı.
]]
local function findOwnPlot(): Model?
	return OwnPlot.Get()
end

local function countPodiums(plot: Model): (number, number)
	local folder = plot:FindFirstChild("Podiums")
	if not folder then
		return 0, 0
	end

	local filled, total = 0, 0
	for _, podium in folder:GetChildren() do
		if podium:IsA("Part") then
			total += 1
			local unitId = podium:GetAttribute("UnitId")
			if typeof(unitId) == "string" and unitId ~= "" then
				filled += 1
			end
		end
	end
	return filled, total
end

--[[
	Kilit soğuması sunucuda os.clock() ile tutuluyor; o saat istemcide farklı
	çalıştığı için doğrudan okunamaz. Bunun yerine kilidin açılma anını burada
	kendimiz görüp sayıyoruz. Oyuna soğuma ortasında girersen bilinmez kalır.
]]
local lockedSince: number? = nil

local function describeLock(plot: Model): (string, Color3)
	local locked = plot:GetAttribute("Locked") == true

	if locked then
		if lockedSince == nil then
			lockedSince = os.clock()
		end
		local left = Config.LockDuration - (os.clock() - (lockedSince :: number))
		return string.format("LOCKED · %ds", math.max(0, math.ceil(left))), GOOD
	end

	if lockedSince ~= nil then
		local left = Config.LockCooldown - (os.clock() - (lockedSince :: number))
		if left > 0 then
			return string.format("cooldown · %ds", math.ceil(left)), WARN
		end
		lockedSince = nil
	end

	return "ready", INK
end

local function describeCarry(): (string, Color3)
	local character = player.Character
	local carried = character and character:FindFirstChild("CarriedUnit")
	if not carried then
		return "—", MUTED
	end

	local unitTag = carried:FindFirstChild("UnitId")
	local unitId = if unitTag and unitTag:IsA("StringValue") then unitTag.Value else ""

	local def = Config.GetUnit(unitId)
	if not def then
		return "yes", WARN
	end

	local mutationTag = carried:FindFirstChild("MutationId")
	local mutationId = if mutationTag and mutationTag:IsA("StringValue") then mutationTag.Value else ""
	local mutation = Config.GetMutation(if mutationId == "" then nil else mutationId)

	local income = def.income * (if mutation then mutation.incomeMul else 1)
	return string.format("%s +$%s/s", def.name, Config.FormatCash(income)), WARN
end

local function setRow(value: TextLabel, text: string, color: Color3)
	value.Text = text
	value.TextColor3 = color
end

-- ─── Döngüler ───────────────────────────────────────────────────────────────

--[[
	Roblox'un hazır oyuncu listesi sağ üstte duruyor ve üs paneliyle üst üste
	biniyordu. Yerine kendi tablomuz var (çalma sayısı dahil), o yüzden
	kapatıyoruz. Oturumun ilk anında çağrı başarısız olabiliyor, o yüzden
	tutana kadar deniyoruz.
]]
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end)

DecorFX.Start()
ThiefTrail.Start()

local guide = CarryGuide.Create(screen)
local board = Leaderboard.Create(screen)
local prompts = PromptFilter.Create()
local colors = OwnerColors.Create()
local minimap = Minimap.Create(screen)
local lobby = Lobby.Create(screen)
local floorStyle = FloorStyle.Create()
local rarityFX = RarityFX.Create()
local catalog = Index.Create(screen)
minimapRef = minimap


--[[
	Konveyör dağıtıcılarına konumlu makine uğultusu. Üsler oyun başlayınca
	kuruluyor, o yüzden bir kez değil kurulana kadar deneniyor. Ses parçaya
	bağlı olduğu için yaklaştıkça yükseliyor.
]]
task.spawn(function()
	for _ = 1, 40 do
		local decor = workspace:FindFirstChild("Decor")
		local plots = decor and decor:FindFirstChild("Plots")
		if plots then
			local attached = 0
			for _, pf in plots:GetChildren() do
				for _, part in pf:GetChildren() do
					if part:IsA("BasePart") and part.Name == "HatchHood" then
						SoundFX.AttachMachineHum(part)
						attached += 1
					end
				end
			end
			if attached > 0 then
				return
			end
		end
		task.wait(0.5)
	end
end)

-- Ok kameraya göre döndüğü için her kare güncellenmeli; 0.2 sn'de bir
-- güncellense kamerayı çevirdiğinde takılarak döner.
RunService.RenderStepped:Connect(function()
	guide.Update(currentPlot)
	-- Harita işaretleri de her karede: yavaş döngüde dönerken takılıyordu
	minimap.Markers(colors.ColorOf, currentPlot)
end)

task.spawn(function()
	while true do
		task.wait(0.2)

		local plot = findOwnPlot()
		currentPlot = plot

		if plot then
			local filled, total = countPodiums(plot)
			local ratio = if total > 0 then filled / total else 0
			setRow(
				podiumValue,
				string.format("%d / %d", filled, total),
				if ratio >= 1 then WARN else INK
			)
			setRow(lockValue, describeLock(plot))
		else
			setRow(podiumValue, "no base", MUTED)
			setRow(lockValue, "—", MUTED)
		end

		setRow(carryValue, describeCarry())
		board.Update()
		prompts.Update(plot)
		colors.Update()
		minimap.Update(colors.ColorOf)
		lobby.Update()
		floorStyle.Update()
		rarityFX.Update()
		catalog.Update()
		if upgradePanel then
			upgradePanel.Update()
		end
		if rebirthPanel then
			rebirthPanel.Update()
		end
	end
end)

-- ─── Ek paneller ────────────────────────────────────────────────────────────
--[[
	Paneller EN SONDA ve BİRBİRİNDEN YALITILMIŞ kuruluyor.

	Önce dosyanın ortasındaydılar ve bu bütün oyunu bozdu: biri hata
	verince ya da bir remote'u beklerken takılınca altındaki RenderStepped
	bağlantısı ve ana HUD döngüsü hiç başlamıyordu. Nakit donuyor, harita
	ölüyor, promptlar filtrelenmiyor, kaide sayısı gelmiyordu.

	Kural: bu paneller HUD'un çekirdeği değil. Hiçbiri, tek başına bütün
	arayüzü indirebilecek bir yerde durmamalı.

	task.spawn — biri yield ederse (Net.Get istemcide WaitForChild yapıyor)
	diğerlerini ve çekirdeği bekletmesin.
	pcall — biri hata verirse sessizce kaybolmasın, adıyla konsola düşsün.

	Sıra önemsiz: HudToggle gizleyeceği panelleri tıklama anında adıyla
	arıyor, kurulum anında değil.
]]
local function mountPanel(name: string, mount: () -> ())
	task.spawn(function()
		local ok, err = pcall(mount)
		if not ok then
			warn(string.format("[SusStealers] %s paneli kurulamadi: %s", name, tostring(err)))
		end
	end)
end

-- Sohbet unvanlari: TextChatService.OnIncomingMessage yalnizca istemcide
-- calisiyor, o yuzden burada.
mountPanel("ChatTitles", function()
	ChatTitles.Start()
end)

mountPanel("TutorialUI", function()
	TutorialUI.Create(screen)
end)

mountPanel("QuestPanel", function()
	QuestPanel.Create(screen)
end)

mountPanel("Menus", function()
	Menus.Create(screen)
end)

--[[
	Yükseltme arayüzü. Kendi üssündeki kulübenin önüne basınca açılıyor,
	çıkınca kapanıyor; o yüzden her karede değil, HUD'un kendi döngüsünde
	güncelleniyor (aşağıda). Panel kurulamazsa Update çağrısı sessizce
	atlanıyor — çekirdek HUD'u indirmemeli.
]]
mountPanel("UpgradePanel", function()
	local panel = UpgradePanel.Create(screen)
	upgradePanel = panel
end)

mountPanel("Music", function()
	music = Music.Start()
end)

mountPanel("Sprint", function()
	Sprint.Create(screen)
end)

--[[
	Rebirth arayuzu. Sag alttaki dock'a REBIRTH dugmesi ekliyor; panelin
	kendisi ekranin ortasinda aciliyor. Menus'ten sonra kuruluyor cunku
	dugmeyi onun dock'una takiyor.
]]
mountPanel("RebirthPanel", function()
	local panel = RebirthPanel.Create(screen)
	rebirthPanel = panel

	local dock = screen:WaitForChild("MenuDock", 10)
	if not dock then
		return
	end

	local button = Instance.new("TextButton")
	button.Name = "RebirthButton"
	button.LayoutOrder = 3
	button.Size = UDim2.new(0, 120, 0, 30)
	button.BackgroundColor3 = Color3.fromRGB(58, 34, 26)
	button.BackgroundTransparency = 0.1
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = Color3.fromRGB(252, 214, 96)
	button.Text = "REBIRTH"
	button.AutoButtonColor = false
	button.Parent = dock

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	button.MouseButton1Click:Connect(function()
		panel.Toggle()
	end)
end)

mountPanel("HudToggle", function()
	HudToggle.Create(screen)
end)
