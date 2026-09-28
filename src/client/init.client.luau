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

local CapsuleFX = require(script.CapsuleFX)
local CosmeticPanel = require(script.CosmeticPanel)
local AlertBanner = require(script.AlertBanner)
local DeviceLayout = require(script.DeviceLayout)
local DecorFX = require(script.DecorFX)
local PetFollow = require(script.PetFollow)
local SecurityCams = require(script.SecurityCams)
local AdminView = require(script.AdminView)
local EggPanel = require(script.EggPanel)
local EggStyle = require(script.EggStyle)
local EventFX = require(script.EventFX)
local FloorStyle = require(script.FloorStyle)
local Index = require(script.Index)
local Inventory = require(script.Inventory)
local Leaderboard = require(script.Leaderboard)
local Lobby = require(script.Lobby)
local MapLife = require(script.MapLife)
local OwnerColors = require(script.OwnerColors)
local PromptFilter = require(script.PromptFilter)
local RarityFX = require(script.RarityFX)
local ScreenFX = require(script.ScreenFX)
local GearFX = require(script.GearFX)
local PromptStyle = require(script.PromptStyle)
local SoundFX = require(script.SoundFX)
local Toasts = require(script.Toasts)
local SpaceFX = require(script.SpaceFX)
local TitleTags = require(script.TitleTags)
local TaskGames = require(script.TaskGames)
local UiKit = require(script.UiKit)

-- Sunucu tarafi hazir olan paneller. Bunlari sunucu sehridi yazdi ama
-- gorunumleri bu sehride: yerlesim, renk ve animasyonu degistirmek
-- serbest, sunucu yalnizca veri gonderiyor.
local ChatTitles = require(script.ChatTitles)
local TutorialUI = require(script.TutorialUI)
local Menus = require(script.Menus)
local Topbar = require(script.Topbar)
local RewardsPanel = require(script.RewardsPanel)
local Music = require(script.Music)
local OwnPlot = require(script.OwnPlot)
local Sprint = require(script.Sprint)
local UpgradePanel = require(script.UpgradePanel)
local ShopPanel = require(script.ShopPanel)
local SideRail = require(script.SideRail)
local PetPanel = require(script.PetPanel)
local HatchFX = require(script.HatchFX)
local FuseFX = require(script.FuseFX)
local AutoHatch = require(script.AutoHatch)
local GearPanel = require(script.GearPanel)
local JetpackPanel = require(script.JetpackPanel)
local SettingsPanel = require(script.SettingsPanel)
local SpinPanel = require(script.SpinPanel)
local CrewAura = require(script.CrewAura)
local WeeklyPanel = require(script.WeeklyPanel)
local SeasonPanel = require(script.SeasonPanel)
local SpaceEventsFX = require(script.SpaceEventsFX)
local Objective = require(script.Objective)
local Intro = require(script.Intro)
local Summons = require(script.Summons)
local Hotbar = require(script.Hotbar)
local AsteroidGame = require(script.AsteroidGame)
local TitleScreen = require(script.TitleScreen)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--[[
	Telefon ve tablet yalnızca YATAY: arayüz (sol sütun, sağ dok, olay
	paneli, mağaza) yatay ekrana göre dizildi; dikeyde üst üste biniyordu.
	LandscapeSensor = iki yatay yöne de döner, dikeye dönmez. Masaüstünde
	etkisi yok. (StarterGui.ScreenOrientation da aynı değerde, ilk kare için.)
]]
playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

--[[
	Başlangıç ekranı: her girişte, HUD kurulmadan ÖNCE açılıyor ki oyuncu
	yarım kurulmuş arayüzü hiç görmesin. HUD arkasında kurulmaya devam
	ediyor; PLAY'e basınca perde açılıyor.
]]
TitleScreen.Show({
	-- Yeni oyuncuya hikâye girişi (Intro kendisi karar veriyor: öğretici başlamamışsa)
	onPlay = function()
		Intro.PlayIfNew()
	end,
})

local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local GOOD = Color3.fromRGB(120, 255, 150)
local WARN = Color3.fromRGB(255, 190, 90)
local BAD = Color3.fromRGB(255, 90, 90)

-- ─── Arayüz ─────────────────────────────────────────────────────────────────

local hudGui = Instance.new("ScreenGui")
hudGui.Name = "SusStealersHud"
hudGui.ResetOnSpawn = false
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.Parent = playerGui

--[[
	Bütün paneller `screen`e kuruluyor ve `screen` artık ScreenGui'nin
	kendisi değil, içindeki ölçek katmanı (DeviceLayout). Telefonda ve
	tablette arayüz tek yerden küçülüyor; panellerin kodu değişmedi.
	Paneller `screen`i yalnızca ebeveyn ve ad araması için kullanıyor,
	ikisi de Frame'de aynı çalışıyor.
]]
local deviceLayout = DeviceLayout.Wrap(hudGui)
local screen: ScreenGui = deviceLayout.Root :: any

--[[
	Sol alttaki sayaçlar: nakit ve çalma hızı.

	NEDEN SOL ALT: eskiden sol ÜSTTEydiler ve sıralama tablosunu aşağı
	itiyorlardı; ekranın üst yarısı üç ayrı şeyle doluyken alt yarısı
	bomboştu. Tür standardı da burası — oyuncu parasını ekranın altında
	arıyor.

	İkisi aynı hap kalıbında (UiKit.StatPill) çünkü ikisi de "şu an neyim
	var" bilgisi; farklı kutularda dursalar göz ikisini ayrı ayrı arardı.
]]
local statBar = Instance.new("Frame")
statBar.Name = "StatBar"
statBar.AnchorPoint = Vector2.new(0, 1)
statBar.Position = UDim2.new(0, 22, 1, -22)
statBar.Size = UDim2.fromOffset(232, 108)
statBar.BackgroundTransparency = 1
statBar.Parent = screen

local statLayout = Instance.new("UIListLayout")
statLayout.SortOrder = Enum.SortOrder.LayoutOrder
statLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
statLayout.Padding = UDim.new(0, 8)
statLayout.Parent = statBar

local speedPill, speedDisc, speedValue, speedSub = UiKit.StatPill(statBar, "SpeedPill", UiKit.CREW.CYAN)
speedPill.LayoutOrder = 1
UiKit.Boot(speedDisc, 26, UiKit.CREW.CYAN)
speedSub.Text = "SPACE SPEED"

local cashPill, cashDisc, cashValue, cashSub = UiKit.StatPill(statBar, "CashPill", UiKit.CREW.LIME)
cashPill.LayoutOrder = 2
UiKit.Coin(cashDisc, 26, UiKit.CREW.LIME)

--[[
	Eskiden burada sağ üstte "Podiums / Lock / Carrying" paneli vardı.
	Kaldırıldı: kilit artık üssün içindeki fiziksel düğmede, taşınan
	karakteri sırtındaki model ve yön oku zaten gösteriyor, kaide sayısı
	da üsse bakınca okunuyor. Panel bilgiyi ikinci kez yazıyordu ve
	oyuncular ne işe yaradığını anlamıyordu. Yeri sıralama tablosuna
	kaldı.
]]
-- ─── Bildirimler ────────────────────────────────────────────────────────────

-- Kısa bildirimler ekipman çubuğunun üstünde, mağaza dilinde (Toasts)
local toasts = Toasts.Create(screen)

local function showToast(text: string, color: Color3)
	toasts.Show(text, color == BAD, if color == GOOD or color == BAD then nil else color)
end

-- ─── Efektler ───────────────────────────────────────────────────────────────
-- Ses ve ekran geri bildirimi bildirimlere bağlanıyor: sunucu zaten ne olduğunu
-- söylüyor, ayrı bir olay akışına gerek yok.

local effects = ScreenFX.Create(screen)
-- Üsse tehdit uyarıları (çalınma, gezen impostor, sabotaj) alttaki bildirim
-- yığınında kayboluyordu; üst-ortada büyük bant
local alertBanner = AlertBanner.Create(screen)
local BANNER_TITLES: { [string]: string } = {
	rogue = "Rogue impostor!",
}
SoundFX.Preload()
SoundFX.StartAmbient()

--[[
	Harita ve üs bilgisi aşağıda kuruluyor ama bildirim işleyicileri burada
	tanımlanıyor. Önden bildirip sonra dolduruyoruz; işleyici tetiklendiğinde
	ikisi de hazır olmuş oluyor.
]]
--[[
	Müzik. Bölgeye göre değişiyor. Burada tanımlı çünkü yukarıdaki
	işleyiciler ona ulaşabilsin; kurulumu panellerle birlikte, en sonda.
]]
local music: Music.Handle? = nil

local currentPlot: Model? = nil

-- Yukseltme arayuzu en sonda kuruluyor (asagidaki mountPanel); ana dongu
-- ona buradan ulasiyor. Kurulmadiysa nil kaliyor ve dongu atliyor.
local upgradePanel: UpgradePanel.Panel? = nil

--[[
	Sunucu bildirimin TÜRÜNÜ de gönderiyor (dördüncü argüman) ve ses ona
	göre seçiliyor. Eskiden bütün başarılı işlemler aynı tınıydı: satın
	alma, satma, yükseltme, görev hepsi tek sesti.

	Tür gelmezse SoundFX taban sese düşüyor, yani eski çağrılar da çalışıyor.
]]
Net.Get("Notify").OnClientEvent:Connect(function(text: string, isError: boolean, kind: string?)
	-- Üssüne yönelik tehditler (sunucu isError ile gönderiyor) bantta
	local bannerTitle = if kind and isError then BANNER_TITLES[kind] else nil
	if bannerTitle then
		alertBanner.Show(bannerTitle, text, nil, 5)
	else
		showToast(text, if isError then BAD else GOOD)
	end
	SoundFX.Event(kind, isError)
end)

--[[
	TEŞHİS TUŞU (K): çalınma efektlerini yerel olarak tetikler.

	Yalnızca Studio'da: canlı oyunda K'ye basan oyuncunun ekranında "TEST"
	bildirimi çıkıyor ve alarm çalıyordu — oyuncuya sızmış bir geliştirici
	aracıydı.
]]
game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.K or not RunService:IsStudio() then
		return
	end

	showToast("TEST: efekt denemesi", Color3.fromRGB(255, 70, 110))
	SoundFX.Alarm()
	effects.Flash(Color3.fromRGB(255, 40, 60), 0.45, 0.7)
	effects.Shake(1.6, 0.6)
	print("[SusStealers] K: efektler yerel olarak tetiklendi")
end)

-- ─── Nakit / gelir ──────────────────────────────────────────────────────────

local function refreshCash()
	local cash = player:GetAttribute("Cash") :: number?
	local income = player:GetAttribute("Income") :: number?

	cashValue.Text = "$" .. Config.FormatCash(cash or 0)
	--[[
		Arkadaş bonusu gelirin yanında: oyuncu bonusun nereden geldiğini
		görsün, arkadaşı çağırmanın karşılığı da burada okunuyor.
	]]
	local friendBonus = player:GetAttribute("FriendBonus") :: number?
	cashSub.Text = if (friendBonus or 0) > 0
		then string.format("+$%s/s · friends +%d%%", Config.FormatCash(income or 0), math.floor((friendBonus or 0) * 100 + 0.5))
		else string.format("+$%s/s", Config.FormatCash(income or 0))
end

player:GetAttributeChangedSignal("Cash"):Connect(refreshCash)
player:GetAttributeChangedSignal("Income"):Connect(refreshCash)
player:GetAttributeChangedSignal("FriendBonus"):Connect(refreshCash)
refreshCash()

--[[
	Uzay hızı: kapsülde kazanılan hız (canavarlara erişimi belirleyen sayı).
	2026-09-28 (Yusuf): alt satırda yalnızca "SPACE SPEED" — kapsül seviyesi
	ve pet katkısı kalabalık yapıyordu (ikisi de kendi pencerelerinde yazıyor).
]]
local function refreshSpeed()
	local speed = player:GetAttribute("SpaceSpeed") :: number?
	speedValue.Text = string.format("%.1f", speed or Config.Space.BaseSpeed)
	speedSub.Text = "SPACE SPEED"
end

player:GetAttributeChangedSignal("SpaceSpeed"):Connect(refreshSpeed)
refreshSpeed()

-- ─── Üs durumu ──────────────────────────────────────────────────────────────

--[[
	Kendi üssümüz. Arama OwnPlot modülünde: aynı arama Lobby'de de gerekiyor
	ve iki kopya birbirinden ayrışıp bir hataya yol açmıştı.
]]
local function findOwnPlot(): Model?
	return OwnPlot.Get()
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
-- Petleri istemci yürütüyor (sunucu yalnızca kuruyor): akıcı takip
PetFollow.Start()

local board = Leaderboard.Create(screen)
local prompts = PromptFilter.Create()
local colors = OwnerColors.Create()
local lobby = Lobby.Create(screen)
local floorStyle = FloorStyle.Create()
local rarityFX = RarityFX.Create()
local catalog = Index.Create(screen)


--[[
	Üslerin uzay kapsüllerine konumlu makine uğultusu (eskiden konveyör
	kapaklarındaydı). Üsler oyun başlayınca kuruluyor, o yüzden bir kez
	değil kurulana kadar deneniyor. Ses parçaya bağlı: yaklaştıkça yükseliyor.
]]
task.spawn(function()
	for _ = 1, 40 do
		local plots = workspace:FindFirstChild("Plots")
		if plots then
			local attached = 0
			for _, plot in plots:GetChildren() do
				local capsule = plot:FindFirstChild("Capsule")
				local dome = capsule and capsule:FindFirstChild("Dome")
				if dome and dome:IsA("BasePart") then
					SoundFX.AttachMachineHum(dome)
					attached += 1
				end
			end
			if attached > 0 then
				return
			end
		end
		task.wait(0.5)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.2)

		local plot = findOwnPlot()
		currentPlot = plot

		colors.Update()
		-- Tablo her oyuncuyu kendi üs renginde gösteriyor
		board.Update(colors.ColorOf)
		prompts.Update(plot)
		lobby.Update()
		floorStyle.Update()
		rarityFX.Update()
		catalog.Update()
		if upgradePanel then
			upgradePanel.Update()
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

	Sıra önemsiz: Topbar gizleyeceği panelleri tıklama anında adıyla
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

-- Yeraltı odaları: Security'de kamera ekranı, Admin'de büyük harita
mountPanel("SecurityCams", SecurityCams.Start)
mountPanel("AdminView", function()
	AdminView.Create(screen)
end)

--[[
	STUDIO ÖNİZLEMESİ: pencereleri koddan açmak için. Studio testinde sunucu
	oyuncuya "UiPreview" niteliği yazıyor, burası adı geçen pencereyi
	açıyor — arayüz elle tıklanmadan tek tek incelenebiliyor. Canlı oyunda
	hiç bağlanmıyor.
]]
local previews: { [string]: () -> () } = {}
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("UiPreview"):Connect(function()
		local name = player:GetAttribute("UiPreview")
		local open = if typeof(name) == "string" then previews[name] else nil
		if open then
			local ok, err = pcall(open)
			if not ok then
				warn("[UiPreview] " .. tostring(err))
			end
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



--[[
	Yükseltme arayüzü. Kendi üssündeki kulübenin önüne basınca açılıyor,
	çıkınca kapanıyor; o yüzden her karede değil, HUD'un kendi döngüsünde
	güncelleniyor (aşağıda). Panel kurulamazsa Update çağrısı sessizce
	atlanıyor — çekirdek HUD'u indirmemeli.
]]
mountPanel("UpgradePanel", function()
	local panel = UpgradePanel.Create(screen)
	upgradePanel = panel
	-- Rebirth artık bu pencerenin sekmesi (2026-09-28): hedef kartı buradan açıyor
	previews.Rebirth = panel.OpenRebirth
end)

mountPanel("Music", function()
	music = Music.Start()
end)

mountPanel("Sprint", function()
	Sprint.Create(screen)
end)

-- Etkileşim pencereleri (E / dokun): oyunun kendi kart tasarımı (PromptStyle)
mountPanel("PromptStyle", function()
	PromptStyle.Start()
end)

-- Ekipman: kol animasyonları, vuruş efektleri, savrulma (GearFX)
mountPanel("GearFX", function()
	GearFX.Start(effects)
end)

-- Başın üstünde unvan etiketi (nadirlik renginde)
mountPanel("TitleTags", function()
	TitleTags.Start()
end)

-- Uzay soygunu: uçuş, canavarlar, yakalanıp fırlatılma, görev kartı (SpaceFX)
mountPanel("SpaceFX", function()
	SpaceFX.Start(screen, effects)
end)

-- Üssün uzay kapsülünde antrenman göstergesi (CapsuleFX)
mountPanel("CapsuleFX", function()
	CapsuleFX.Start(screen)
end)


--[[
	ENVANTER: petler, iksirler, stil ve unvanlar tek pencerede (Inventory.luau).
	Sağ ortadaki düğme dizisini (MenuDock) de o kuruyor; REBIRTH düğmesi
	yukarıda ona takılıyor.

	Sayfalar panellerin kendisi — her biri ayrı pcall'da: biri kurulamazsa
	diğer sekmeler çalışmaya devam etsin.
]]
mountPanel("Inventory", function()
	local inventory = Inventory.Create(screen)
	local content = inventory.Content

	local function page(name: string, build: () -> ())
		local ok, err = pcall(build)
		if not ok then
			warn(string.format("[SusStealers] Envanter sayfasi kurulamadi (%s): %s", name, tostring(err)))
		end
	end

	-- 1) PETS — yumurtalar, koleksiyon, birleştirme makinesi
	page("Pets", function()
		--[[
			Açılış animasyonu, otomatik açma döngüsü ve pet sayfası birbirine
			bağlı: otomatik açma animasyon bitmeden bir sonrakini istemiyor,
			sayfa da hangi yumurtada otomatiğin açık olduğunu gösteriyor.
		]]
		local hatchFX = HatchFX.Create(screen)
		local auto = AutoHatch.Create(screen, hatchFX.IsPlaying)
		-- Kuluçkadaki yumurtanın üstünde: petler, şanslar, AUTO-DELETE, E/R/T
		EggPanel.Create(auto, hatchFX.IsPlaying)
		local panel = PetPanel.Create(screen, auto, content, function(text)
			inventory.SetCount("pets", text)
		end)
		previews.Pets = panel.Toggle
		previews.Fuse = panel.OpenFuse

		inventory.AddTab({
			id = "pets",
			label = "PETS",
			tint = UiKit.CREW.PINK,
			order = 1,
			icon = function(slot, size, tint)
				UiKit.Paw(slot, size, tint)
			end,
		}, content:WaitForChild("PetPanel") :: GuiObject, panel.Toggle)

		-- Birleştirme makinede oynuyor: pencere kapanıyor, bitince makine ekranı geri geliyor
		local fuseWasOpen = false
		FuseFX.Create({
			onStart = function()
				fuseWasOpen = panel.IsFuseOpen()
				panel.Hide()
			end,
			onEnd = function()
				if fuseWasOpen then
					panel.OpenFuse()
				end
			end,
		})

		--[[
			Kuluçkahanedeki birleştirme makinesi. Promptu sunucu kuruyor ama
			pencere istemcinin işi: oyuncunun kendi tetiklemesi burada da
			görünüyor ve birleştirme modunu açıyor. Asıl işlem (PetFuse)
			sunucuda, makineye yakınlık orada doğrulanıyor.
		]]
		game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, who)
			if who ~= player then
				return
			end
			if prompt.Name == "FusePrompt" then
				panel.OpenFuse()
			elseif prompt.Name == "AutoPrompt" then
				-- Kuluçkadaki yumurtanın T tuşu: o yumurtada otomatik açmayı aç/kapa
				local eggId = prompt:GetAttribute("EggId")
				if typeof(eggId) == "string" then
					auto.Toggle(eggId, 1)
				end
			end
		end)
	end)

	-- 2) POTIONS ve 4) TITLES — aynı sayfa (Menus), sekmesi niteliğinde
	page("Menus", function()
		local menu = Menus.Create(screen, content, function(tab, text, badge)
			inventory.SetCount(tab, text)
			if tab == "potions" then
				inventory.SetBadge("potions", badge)
			end
		end)
		local root = content:WaitForChild("MenuOverlay") :: GuiObject
		inventory.AddTab({
			id = "potions",
			label = "POTIONS",
			tint = Color3.fromRGB(110, 206, 120),
			order = 2,
			icon = function(slot, size, tint)
				UiKit.Vial(slot, size, Color3.fromRGB(170, 255, 120), 0.8, true)
			end,
		}, root, function()
			menu.Open("potions")
		end)
		inventory.AddTab({
			id = "titles",
			label = "TITLES",
			tint = Color3.fromRGB(214, 164, 40),
			order = 4,
			icon = function(slot, size, tint)
				UiKit.Crown(slot, size, Color3.fromRGB(255, 214, 90))
			end,
		}, root, function()
			menu.Open("titles")
		end)
		previews.Titles = function()
			inventory.Open("titles")
		end
		previews.Potions = function()
			inventory.Open("potions")
		end
	end)

	-- 3) STYLE — şapkalar ve izler
	page("Style", function()
		local panel = CosmeticPanel.Create(screen, content)
		inventory.AddTab({
			id = "style",
			label = "STYLE",
			tint = UiKit.CREW.PURPLE:Lerp(UiKit.CREW.PINK, 0.4),
			order = 3,
			icon = function(slot, size, tint)
				-- Şapkalı mürettebat: kozmetiğin ne olduğu ikondan okunsun
				local body = UiKit.Crewmate(slot, size * 0.74, UiKit.CREW.PINK:Lerp(Color3.new(1, 1, 1), 0.3))
				local hat = Instance.new("Frame")
				hat.AnchorPoint = Vector2.new(0.5, 1)
				hat.Position = UDim2.fromScale(0.45, 0.12)
				hat.Size = UDim2.fromScale(0.62, 0.3)
				hat.BackgroundColor3 = UiKit.CREW.YELLOW
				hat.BorderSizePixel = 0
				hat.ZIndex = body.ZIndex + 2
				hat.Parent = body
				UiKit.Corner(hat, 4)
			end,
		}, content:WaitForChild("CosmeticPanel") :: GuiObject, panel.Toggle)
		previews.Style = function()
			inventory.Open("style")
		end

		-- Sayaç oyuncu niteliğinden: sahip olunan kozmetik / toplam
		local function refreshStyle()
			local raw = player:GetAttribute("CosmeticsOwned")
			local count = 0
			if typeof(raw) == "string" then
				for _ in string.gmatch(raw, "[^,]+") do
					count += 1
				end
			end
			inventory.SetCount("style", string.format("%d / %d owned", count, #Config.Cosmetics))
		end
		player:GetAttributeChangedSignal("CosmeticsOwned"):Connect(refreshStyle)
		refreshStyle()
	end)

	previews.Inventory = function()
		inventory.Open(nil)
	end
	previews.InventoryToggle = inventory.Toggle
end)

--[[
	Sol kenar: SHOP, INDEX, QUESTS.

	Mağaza ve görev pencereleri burada kuruluyor çünkü onları açan tek şey
	bu ray. İndeks paneli yukarıda zaten var (catalog), ray sadece onu
	açıp kapatıyor — C tuşu duruyor ama artık tek yol değil.

	Görev penceresi hazır ödül sayısını bildiriyor; QUESTS düğmesinin
	köşesindeki kırmızı rozet ona bağlı.

	Ayrı bir görevde çünkü mağaza açılışta Roblox'a fiyat soruyor; o ağ
	çağrısı çekirdek HUD'u bekletmemeli.
]]
mountPanel("SideRail", function()
	local shop = ShopPanel.Create(screen)

	-- Sezon Kartı: sol rayda PASS (rozet = toplanacak ödül)
	local seasonPass = SeasonPanel.Create(screen)
	previews.Season = seasonPass.Open
	--[[
		Sol menü: 2×2 dört düğme (SideRail). `unlockAt` = kaç öğretici adımı
		bitince görünüyor (kademeli açılma): ilk soygundan sonra SHOP ve
		INDEX, pet adımında ITEMS, öğretici bitince PASS.
		2026-09-28: QUESTS ödül penceresinin sekmesi (üst şeritteki hediye,
		yine 2. adımdan sonra), REBIRTH yükseltme penceresinin sekmesi
		(öğretici bitince).
	]]
	local function call(key: string)
		return function()
			local f = previews[key]
			if f then
				f()
			end
		end
	end
	local rail = SideRail.Create(screen, "SideRail", {
		{
			name = "Shop",
			label = "SHOP",
			tint = UiKit.CREW.LIME,
			icon = "bag",
			onClick = shop.Toggle,
			unlockAt = 1,
		},
		{
			name = "Inventory",
			label = "ITEMS",
			tint = Color3.fromRGB(64, 150, 214),
			icon = "backpack",
			onClick = call("InventoryToggle"),
			unlockAt = 8,
		},
		{
			name = "Index",
			label = "INDEX",
			tint = UiKit.CREW.CYAN,
			icon = "book",
			onClick = catalog.Toggle,
			unlockAt = 1,
		},
		{
			name = "Pass",
			label = "PASS",
			tint = Color3.fromRGB(170, 100, 255),
			icon = "crown",
			onClick = seasonPass.Toggle,
			unlockAt = #Config.Tutorial,
		},
	})
	Inventory.BadgeChanged.Event:Connect(function(total: number)
		rail.SetBadge("Inventory", total)
	end)
	local function passBadge()
		rail.SetBadge("Pass", SeasonPanel.Claimable())
	end
	for _, attr in { "SeasonXp", "SeasonClaimed", "SeasonPass" } do
		player:GetAttributeChangedSignal(attr):Connect(passBadge)
	end
	passBadge()

	previews.Shop = shop.Toggle
	previews.Index = catalog.Toggle

	--[[
		Kafeteryadaki otomat (Decor, "Vending"): tıklayınca ya da E'ye
		basınca mağaza İKSİRLER bölümünde açılıyor (Robux iksirleri).
		Prompt ve tıklama algılayıcı istemcide kuruluyor: yalnızca bu
		oyuncunun penceresini açıyorlar, sunucuya bir şey gitmiyor.
	]]
	task.spawn(function()
		local decor = workspace:WaitForChild("Decor", 60)
		if not decor then
			return
		end
		local wired: { [Instance]: boolean } = {}
		local function openPotions()
			shop.Open("potions")
		end
		local function wire(part: Instance)
			if wired[part] or not part:IsA("BasePart") then
				return
			end
			local name = part.Name
			if not (name == "Vending" or name == "VendGlass" or name == "Snack" or name == "VendPad") then
				return
			end
			wired[part] = true
			local click = Instance.new("ClickDetector")
			click.MaxActivationDistance = 40
			click.Parent = part
			click.MouseClick:Connect(openPotions)
			if name == "Vending" then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "VendingPrompt"
				prompt.ActionText = "Potions"
				prompt.ObjectText = "Vending Machine"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Parent = part
				prompt.Triggered:Connect(openPotions)
			end
		end
		for _, d in decor:GetDescendants() do
			wire(d)
		end
		decor.DescendantAdded:Connect(wire)
	end)
	previews.PetIndex = function()
		catalog.ShowPets()
	end
end)

--[[
	Lobideki ekipman dukkani. Tezgahtaki promptu sunucu kuruyor; pencere
	istemcinin isi, oyuncunun kendi tetiklemesi burada gorunuyor.
]]
mountPanel("GearPanel", function()
	local gear = GearPanel.Create(screen)
	previews.Gear = gear.Open
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "GearPrompt" then
			gear.Open()
		end
	end)
end)

-- Şans çarkı penceresi (prompt sunucuda, SpinService; pencere SpinResult'u da dinliyor)
mountPanel("SpinPanel", function()
	local spin = SpinPanel.Create(screen)
	previews.Spin = spin.Open
end)

-- Launch Bay'deki jetpack standı (prompt sunucuda, JetpackService)
mountPanel("JetpackPanel", function()
	local jetpacks = JetpackPanel.Create(screen)
	previews.Jetpack = jetpacks.Open
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "JetpackPrompt" then
			jetpacks.Open()
		end
	end)
end)

-- Ek odalardaki görevler (Storage, Laboratory): pencere ve sarı "!" işaretleri
mountPanel("TaskGames", function()
	local tasks = TaskGames.Create(screen)
	previews.Fuel = function()
		tasks.Open("Fuel")
	end
	previews.Wiring = function()
		tasks.Open("Wiring")
	end
	previews.Card = function()
		tasks.Open("Card")
	end
end)

-- Sunucu olayları: üstteki şerit ve Lights Sabotage karanlığı
mountPanel("EventFX", function()
	EventFX.Create(screen)
end)

-- Kuluçka yumurtaları: her birinin kendi görünüşü ve boşta animasyonu
mountPanel("EggStyle", function()
	EggStyle.Start()
end)

-- Harita canlılığı: uyarı lambaları ve koridorda gezen mürettebat
mountPanel("MapLife", function()
	MapLife.Start()
end)

-- Gezegenlerdeki mürettebatın nadirlik aurası (ışıltı, küre, ışık sütunu)
mountPanel("CrewAura", function()
	CrewAura.Start()
end)

-- Tek hedef kartı (üst orta): öğretici bitince "şimdi ne yapmalıyım"
mountPanel("Objective", function()
	Objective.Start(screen, {
		Inventory = function()
			local f = previews.Inventory
			if f then
				f()
			end
		end,
		Rebirth = function()
			local f = previews.Rebirth
			if f then
				f()
			end
		end,
	})
end)

-- Uzay istasyonu olaylarının görünüşü (göktaşları, karartma, güneş rüzgârı)
mountPanel("SpaceEventsFX", function()
	SpaceEventsFX.Start()
end)

-- Haftalık sıralama: CREW tablosundaki 🏆 düğmesi ve lobideki panonun promptu
mountPanel("WeeklyPanel", function()
	local weekly = WeeklyPanel.Create(screen)
	previews.Weekly = weekly.Open
	Leaderboard.OpenWeekly.Event:Connect(weekly.Toggle)
end)

-- Summons sohbet sekmesi (nadir cikislar)
mountPanel("Summons", function()
	Summons.Create(screen)
end)

-- Ekipman çubuğu: Roblox'un gri hazır çubuğunun yerine (pencerelerin altında kalıyor)
mountPanel("Hotbar", function()
	Hotbar.Create(screen)
end)

--[[
	Weapons odasındaki "Clear Asteroids" oyunu. Konsolun promptunu sunucu
	kuruyor ve başlangıç zamanını orada yazıyor; burası oyuncunun kendi
	tetiklemesini görüp oyunu açıyor. Ödülü sunucu veriyor.
]]
mountPanel("AsteroidGame", function()
	local asteroids = AsteroidGame.Create(screen)
	previews.Asteroids = asteroids.Open
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "AsteroidPrompt" then
			asteroids.Open()
		end
	end)
end)

--[[
	Üst şerit: Roblox sohbet düğmesinin yanında önce hediye kutusu (ödül
	penceresi), sonra arayüzü gizleme gözü. Hediyenin rozeti ödül
	penceresinin saydığı toplanabilir ödül sayısı.
]]
mountPanel("Topbar", function()
	local rewards: RewardsPanel.Panel? = nil
	local settings = SettingsPanel.Create(screen)
	previews.Settings = settings.Open
	local bar = Topbar.Create(screen, function()
		if rewards then
			rewards.Toggle()
		end
	end, settings.Toggle)
	rewards = RewardsPanel.Create(screen, bar.SetGiftBadge)
	previews.Rewards = function()
		if rewards then
			rewards.Toggle()
		end
	end
	-- Görevler ödül penceresinin sekmesi (2026-09-28)
	previews.Quests = function()
		if rewards then
			rewards.OpenQuests()
		end
	end
end)
