--!strict
-- Üst katların oyun içi parayla satın alınması.
--
-- Neden var: kat eskiden doğrudan rebirth ödülüydü. Rebirth zaten kalıcı
-- gelir çarpanı veriyordu, kat da bedava gelince rebirth tek başına her
-- şeydi ve biriken paranın rebirth dışında harcanacak büyük bir yeri
-- yoktu.
--
-- Şimdi ikisi ayrı: rebirth katın KİLİDİNİ açıyor, kat parayla alınıyor.
-- "5 milyarı 2. kata mı yatırayım yoksa 8 milyarlık rebirth'e mi
-- saklayayım" gerçek bir karar.
--
-- Pedin yeri rampadan türetiliyor, elle koordinat girilmiyor: rampanın
-- alçak ucu neredeyse ped oraya çıkıyor. FloorHeight ya da rampa ölçüsü
-- değişirse ped kendiliğinden uyuyor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local FloorService = {}

local REFRESH_INTERVAL = 2

local notifyRemote: RemoteEvent

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError)
	end
end

-- ─── Ped ────────────────────────────────────────────────────────────────────

--[[
	Merdivenin en alt basamağının dünya konumu.

	Üs yerleşimi rampadan merdivene geçti (Step / StairSide / Landing).
	En alçak basamağı seçiyoruz: oyuncunun yukarı çıkmak için bastığı ilk
	yer orası, yani parayı vereceği yerin de orası olması gerekiyor.

	Basamağı isimle arıyoruz, sayıyla değil: basamak sayısı kat
	yüksekliğine göre değişiyor ve sabit bir indeks kırılgan olurdu.
]]
local function stairFoot(floorModel: Model): Vector3?
	local lowest: BasePart? = nil

	for _, part in floorModel:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Step" then
			if not lowest or part.Position.Y < lowest.Position.Y then
				lowest = part
			end
		end
	end

	return if lowest then lowest.Position else nil
end

--[[
	Pedin duracağı yer: merdivenin dibinden üssün MERKEZİNE doğru birkaç
	stud içeride.

	Önce körlemesine +Z yönüne ittiriyordum ve ped üssün dışına taşıyordu.
	Yönü merkezden türetmek, merdiven hangi kenarda olursa olsun pedi
	içeride tutuyor — alt sıradaki dört üs 180° dönük, sabit bir yön
	hiçbir zaman ikisinde birden doğru olmuyor.
]]
local PAD_INSET = 5

local function padPosition(plot: Model, foot: Vector3): Vector3
	local base = plot:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return foot + Vector3.new(0, 0.3, 0)
	end

	local flat = Vector3.new(base.Position.X - foot.X, 0, base.Position.Z - foot.Z)
	local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1)

	-- Yükseklik üssün zemininden: basamağın kendi yüksekliği pedi havada
	-- bırakıyordu
	local groundY = base.Position.Y + base.Size.Y / 2 + 0.3
	local spot = foot + direction * PAD_INSET
	return Vector3.new(spot.X, groundY, spot.Z)
end

--[[ Katın merdiven dibi. Kat ya da merdiven yoksa nil. ]]
local function floorFoot(plot: Model, floor: number): Vector3?
	local floors = plot:FindFirstChild("Floors")
	local floorModel = floors and floors:FindFirstChild(string.format("Floor%d", floor))
	if not (floorModel and floorModel:IsA("Model")) then
		return nil
	end
	return stairFoot(floorModel)
end

--[[
	Satın alma pedi. Her üsse bir tane; hangi katı sattığı duruma göre
	değişiyor, o yüzden tek ped yeniden konumlanıyor — kat başına ayrı
	ped koysaydık alınmış katın pedi ortada dururdu.
]]
local function buildPad(plot: Model): BasePart?
	local foot = floorFoot(plot, 2)
	if not foot then
		warn("[FloorService] " .. plot.Name .. ": merdiven bulunamadi, satin alma pedi kurulamadi")
		return nil
	end

	local pad = Instance.new("Part")
	pad.Name = "FloorPad"
	pad.Size = Vector3.new(8, 0.4, 6)
	pad.CFrame = CFrame.new(padPosition(plot, foot))
	pad.Anchored = true
	pad.CanCollide = false
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(255, 190, 90)
	pad.Transparency = 0.35
	pad.Parent = plot

	--[[
		Pedin üstünde duran ışık sütunu. Ped tek başına yere yapışık
		duruyordu ve "üst kat alma yeri nerede" sorusu cevapsız kalıyordu;
		sütun merdivenin dibini uzaktan görünür yapıyor.
	]]
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Size = Vector3.new(1.2, 14, 1.2)
	beacon.CFrame = pad.CFrame * CFrame.new(0, 7, 0)
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = pad.Color
	beacon.Transparency = 0.75
	beacon.Parent = pad

	local gui = Instance.new("BillboardGui")
	gui.Name = "FloorLabel"
	gui.Size = UDim2.fromScale(12, 3)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.Parent = pad

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 205, 120)
	label.TextStrokeTransparency = 0.3
	label.Text = ""
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FloorPrompt"
	prompt.ActionText = "Buy Floor"
	prompt.ObjectText = "Upper Floor"
	-- Geri alınamaz ve çok pahalı: yanlışlıkla basılmasın
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	PromptGuard.Connect(prompt, function(player)
		FloorService.TryBuy(player)
	end)

	return pad
end

-- ─── Satın alma ─────────────────────────────────────────────────────────────

--[[
	Sıradaki katı satın alır.

	Sıralı: 3. kat 2. kat alınmadan satın alınamıyor, yoksa arada boş kat
	kalırdı. Rebirth koşulu burada aranıyor ve sonradan geri alınmıyor —
	oyuncu parasını ödedi.
]]
function FloorService.TryBuy(player: Player): boolean
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		notify(player, "You need a base first", true)
		return false
	end

	if PlotService.GetOwner(plot) ~= player then
		notify(player, "Not your base", true)
		return false
	end

	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local def = Config.GetNextFloor(profile.floorsBought)
	if not def then
		notify(player, "You already own every floor", true)
		return false
	end

	if profile.rebirths < def.rebirths then
		notify(player, string.format(
			"Floor %d needs %d rebirth%s - you have %d",
			def.floor, def.rebirths,
			if def.rebirths == 1 then "" else "s",
			profile.rebirths
		), true)
		return false
	end

	if not EconomyService.TrySpend(player, def.cost) then
		notify(player, string.format(
			"Floor %d costs $%s - you have $%s",
			def.floor,
			Config.FormatCash(def.cost),
			Config.FormatCash(EconomyService.GetCash(player))
		), true)
		return false
	end

	profile.floorsBought += 1
	PlotService.SetUnlockedFloors(plot, Config.GetUnlockedFloors(profile.floorsBought))

	notify(player, string.format("Floor %d unlocked!", def.floor), false)

	-- Pahalı ve geri alınamaz; bir sonraki autosave'i beklemeyelim
	DataService.Save(player)
	FloorService.Refresh(plot)
	return true
end

-- ─── Görünüm ────────────────────────────────────────────────────────────────

--[[
	Pedin yazısını ve yerini sahibin durumuna göre tazeler.

	Hepsi alınmışsa ped gizleniyor: alacak bir şey kalmadığında ortada
	duran parlak bir ped oyuncuyu boşuna oraya çekiyor.
]]
function FloorService.Refresh(plot: Model)
	local pad = plot:FindFirstChild("FloorPad")
	if not (pad and pad:IsA("BasePart")) then
		return
	end

	local gui = pad:FindFirstChild("FloorLabel")
	local label = gui and gui:FindFirstChild("Text")
	local prompt = pad:FindFirstChild("FloorPrompt")
	if not (label and label:IsA("TextLabel") and prompt and prompt:IsA("ProximityPrompt")) then
		return
	end

	local owner = PlotService.GetOwner(plot)
	local profile = if owner then DataService.Get(owner) else nil

	if not profile then
		pad.Transparency = 1
		prompt.Enabled = false
		label.Text = ""
		return
	end

	local def = Config.GetNextFloor(profile.floorsBought)
	if not def then
		pad.Transparency = 1
		prompt.Enabled = false
		label.Text = ""
		return
	end

	-- Pedi satılan katın rampasının dibine taşı
	local foot = floorFoot(plot, def.floor)
	if foot then
		pad.CFrame = CFrame.new(padPosition(plot, foot))
	end

	pad.Transparency = 0.5
	prompt.Enabled = true

	local beacon = pad:FindFirstChild("Beacon")

	if profile.rebirths < def.rebirths then
		-- Kilitli: fiyatı da gösteriyoruz ki oyuncu neye hazırlanacağını bilsin
		pad.Color = Color3.fromRGB(120, 128, 145)
		prompt.ActionText = "Locked"
		prompt.ObjectText = string.format("Floor %d", def.floor)
		label.TextColor3 = Color3.fromRGB(150, 163, 184)
		label.Text = string.format(
			"FLOOR %d\nNeeds %d rebirth  ·  $%s",
			def.floor, def.rebirths, Config.FormatCash(def.cost)
		)
	else
		pad.Color = Color3.fromRGB(255, 190, 90)
		prompt.ActionText = "Buy Floor"
		prompt.ObjectText = string.format("$%s", Config.FormatCash(def.cost))
		label.TextColor3 = Color3.fromRGB(255, 205, 120)
		label.Text = string.format("FLOOR %d\n$%s", def.floor, Config.FormatCash(def.cost))
	end

	if beacon and beacon:IsA("BasePart") then
		beacon.Color = pad.Color
		beacon.Transparency = if pad.Transparency >= 1 then 1 else 0.75
		beacon.CFrame = pad.CFrame * CFrame.new(0, 7, 0)
	end
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function FloorService.Start()
	notifyRemote = Net.Get("Notify")

	for _, plot in PlotService.GetAllPlots() do
		buildPad(plot)
		FloorService.Refresh(plot)
	end

	--[[
		Rebirth ve üs sahipliği başka servislerde değişiyor ve olay yayını
		yok. Sekiz ped için iki saniyede bir tarama, ayrı bir olay akışı
		kurmaktan ucuz ve gecikmesi fark edilmiyor.
	]]
	task.spawn(function()
		while true do
			task.wait(REFRESH_INTERVAL)
			for _, plot in PlotService.GetAllPlots() do
				FloorService.Refresh(plot)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			if DataService.WaitForProfile(player) then
				local plot = PlotService.GetPlotOf(player)
				if plot then
					FloorService.Refresh(plot)
				end
			end
		end)
	end)
end

return FloorService
