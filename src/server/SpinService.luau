--!strict
-- Şans çarkı: günde bir bedava çevirme, fazlası Robux ile.
--
-- Çarkın geometrisi dekorda hazır (workspace.Decor.Wheel). Dilimlerin
-- ödül renkleri ve yazıları burada, açılışta ekleniyor (decorateWheel).
--
-- Dönüş istemcide (DecorFX) ama açı SUNUCU SAATİNDEN (shared/WheelSpin):
-- herkes çarkı aynı yerde görüyor. Çevirmede sunucu Wheel modeline
-- SpinFrom/SpinTo/SpinStart/SpinEnd yazıyor; çark kazanılan ödülün
-- diliminde yavaşlayarak duruyor, ödül mesajı da o anda geliyor.
--
-- Ödüller oyuncunun kendi gelirinin katı. Sabit tutar olsaydı geç oyunda
-- anlamsızlaşır, erken oyunda dengeyi bozardı.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local WheelSpin = require(Shared.WheelSpin)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)
local ConveyorService = require(script.Parent.ConveyorService)
local MonetizationService = require(script.Parent.MonetizationService)
local BadgeService = require(script.Parent.BadgeService)

local SpinService = {}

local rng = Random.new()
local notifyRemote: RemoteEvent

-- Çark dönerken ikinci çevirme kabul edilmiyor; ödül animasyonu bitsin
local spinning = false
local spinPrompt: ProximityPrompt? = nil

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "spin"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
SpinService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
	end
end

-- ─── Bedava hak ─────────────────────────────────────────────────────────────

--[[ Bedava çevirmeye kaç saniye kaldı. 0 ise hak hazır. ]]
function SpinService.GetCooldown(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return math.huge
	end

	local elapsed = os.time() - profile.lastSpinAt
	local total = Config.SpinCooldownHours * 3600
	return math.max(0, total - elapsed)
end

-- ─── Ödül ───────────────────────────────────────────────────────────────────

--[[
	Ödülü uygular ve oyuncuya gösterilecek metni döner.
	Uygulanamazsa nil döner; çağıran hakkı harcamamalı.
]]
local function grantReward(player: Player, reward: Config.SpinReward): string?
	if reward.kind == "cash" then
		local amount = Config.GetSpinCash(reward, EconomyService.GetIncome(player))
		EconomyService.AddCash(player, amount)
		return string.format("$%s", Config.FormatCash(amount))

	elseif reward.kind == "spawn" then
		if not ConveyorService.SpawnFor(player) then
			return nil
		end
		return "a unit on your conveyor"

	elseif reward.kind == "mutation" then
		if not ConveyorService.GrantLuckyRoll(player) then
			return nil
		end
		return "a guaranteed mutation"

	elseif reward.kind == "unit" then
		--[[
			Doğrudan kaideye konan bedava karakter. Boş kaide yoksa
			ödülü kaybetmesin diye nakde çevriliyor.
		]]
		local plot = PlotService.GetPlotOf(player)
		local podium = plot and PlotService.FindEmptyPodium(plot)
		local def = Config.RollUnit(rng, 0)

		if podium and PlotService.PlaceUnit(podium, def.id, nil) then
			if def.rarity == "Secret" then
				BadgeService.Award(player, "SecretFind")
			end
			return def.name
		end

		local amount = Config.GetPrice(def.id, nil)
		EconomyService.AddCash(player, amount)
		return string.format("$%s (no free podium)", Config.FormatCash(amount))
	end

	return nil
end

-- ─── Çevirme ────────────────────────────────────────────────────────────────

local function getWheel(): Model?
	local decor = workspace:FindFirstChild("Decor")
	local wheel = decor and decor:FindFirstChild("Wheel")
	return if wheel and wheel:IsA("Model") then wheel else nil
end

-- Boşta dönüş hızı (derece/sn): dilimlerin SpinSpeed niteliği
local function idleSpeed(wheel: Model): number
	local disc = wheel:FindFirstChild("WheelDisc")
	local speed = disc and disc:GetAttribute("SpinSpeed")
	return if typeof(speed) == "number" then speed else 26
end

--[[
	Çarkı `rewardId`nin dilimlerinden birinde durdurur. Kaç saniye sonra
	durduğunu döner (ödül mesajı o zaman).
]]
local function animate(rewardId: string): number
	local wheel = getWheel()
	if not wheel then
		spinning = false
		return 0
	end
	local slots = {}
	for i, id in Config.SpinWheelSlices do
		if id == rewardId then
			table.insert(slots, i)
		end
	end
	local index = if #slots > 0 then slots[rng:NextInteger(1, #slots)] else 1
	local jitter = rng:NextNumber(-WheelSpin.SLICE_JITTER, WheelSpin.SLICE_JITTER)

	local now = workspace:GetServerTimeNow()
	local start = now + 0.25 -- istemcilere niteliklerin ulaşması için pay
	local from = WheelSpin.Angle(wheel, start, idleSpeed(wheel))
	local to = WheelSpin.SpinTo(from, WheelSpin.TargetFor(index, #Config.SpinWheelSlices, jitter))
	wheel:SetAttribute("SpinFrom", from)
	wheel:SetAttribute("SpinTo", to)
	wheel:SetAttribute("SpinStart", start)
	wheel:SetAttribute("SpinEnd", start + Config.SpinDuration)
	wheel:SetAttribute("SpinSlice", index)

	local stopsIn = (start - now) + Config.SpinDuration
	task.delay(stopsIn + WheelSpin.HOLD, function()
		spinning = false
	end)
	return stopsIn
end

-- ─── Dilimler ───────────────────────────────────────────────────────────────

-- Ödül -> dilim rengi ve yazısı
local SLICE_LOOK: { [string]: { color: Color3, text: string } } = {
	SmallCash = { color = Color3.fromRGB(88, 200, 74), text = "CASH" },
	MedCash = { color = Color3.fromRGB(40, 150, 230), text = "BIG CASH" },
	HugeCash = { color = Color3.fromRGB(255, 190, 30), text = "HUGE CASH" },
	Spawn = { color = Color3.fromRGB(245, 120, 30), text = "SPAWN" },
	Mutation = { color = Color3.fromRGB(160, 80, 235), text = "MUTATION" },
	FreeUnit = { color = Color3.fromRGB(230, 45, 70), text = "FREE UNIT" },
}

--[[
	Harita çarkı düz renkli, boş dilimlerle kuruyor (lobby.luau). Burada
	her dilim ödülünün rengine boyanıyor ve üstüne ödülün yazısı geliyor.
	Yazı parçaları dilimlerle aynı dönüş niteliklerini taşıyor; DecorFX
	onları da çarkla birlikte döndürüyor.

	Dilimin sırası parçanın göbeğe göre açısından bulunuyor: sunucuda
	parçalar hiç dönmüyor (dönüş istemcide), yani kuruldukları yerdeler.
]]
local function decorateWheel(wheel: Model)
	local disc = wheel:FindFirstChild("WheelDisc")
	if not (disc and disc:IsA("BasePart")) then
		return
	end
	local center = disc:GetAttribute("SpinCenter")
	if typeof(center) ~= "Vector3" then
		return
	end
	local count = #Config.SpinWheelSlices
	local width = 2 * math.pi / count
	local frame = disc.CFrame.Rotation
	local radius = (disc.Size.X + 1) / 2

	local function sliceOf(pos: Vector3): (number, number)
		local l = frame:PointToObjectSpace(pos - center)
		local ang = math.atan2(l.Y, l.X)
		local index = math.floor(ang / width + 0.5) % count + 1
		return index, Vector2.new(l.X, l.Y).Magnitude
	end

	for _, part in wheel:GetChildren() do
		if part:IsA("BasePart") and part.Name == "WheelSlice" then
			local index, r = sliceOf(part.Position)
			local look = SLICE_LOOK[Config.SpinWheelSlices[index]]
			if look then
				-- Göbekten dışa doğru hafif açılan ton (haritadaki gibi)
				part.Color = look.color:Lerp(Color3.new(1, 1, 1), math.clamp(r / radius, 0, 1) * 0.2)
			end
		end
	end

	local old = wheel:FindFirstChild("SliceLabels")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SliceLabels"

	-- Dilimlerin ön yüzü diskin önünde; yazı onun hemen önünde
	local slice = wheel:FindFirstChild("WheelSlice") :: BasePart?
	local front = if slice then frame:PointToObjectSpace(slice.Position - center).Z - slice.Size.Z / 2 - 0.06 else -1
	for index, id in Config.SpinWheelSlices do
		local look = SLICE_LOOK[id]
		if not look then
			continue
		end
		local ang = (index - 1) * width
		local part = Instance.new("Part")
		part.Name = "WheelLabel"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(radius * 0.62, radius * 0.24, 0.05)
		-- Yazı göbekten dışa okunsun: parçanın -X'i dışa bakıyor (ön yüzün sağı -X)
		part.CFrame = CFrame.new(center) * frame * CFrame.Angles(0, 0, ang)
			* CFrame.new(radius * 0.56, 0, front) * CFrame.Angles(0, 0, math.pi)
		for _, key in { "SpinSpeed", "SpinAxis", "SpinCenter", "SpinAxisVec" } do
			part:SetAttribute(key, disc:GetAttribute(key))
		end
		part:SetAttribute("Slice", index)

		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		gui.LightInfluence = 0
		gui.Parent = part
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.Text = look.text
		text.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(22, 20, 34)
		stroke.Thickness = 5
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = text
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.14, 0)
		pad.PaddingBottom = UDim.new(0.14, 0)
		pad.PaddingLeft = UDim.new(0.04, 0)
		pad.PaddingRight = UDim.new(0.04, 0)
		pad.Parent = text

		part.Parent = folder
	end
	folder.Parent = wheel
end

--[[
	Çarkı çevirir. free true ise günlük hak harcanıyor, false ise
	Robux ürününden geliyor ve hak kontrolü yapılmıyor.
]]
function SpinService.Spin(player: Player, free: boolean): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	if not PlotService.GetPlotOf(player) then
		notify(player, "You need a base first", true)
		return false
	end

	if spinning then
		notify(player, "The wheel is already spinning", true)
		return false
	end

	if free then
		local remaining = SpinService.GetCooldown(player)
		if remaining > 0 then
			local hours = math.floor(remaining / 3600)
			local minutes = math.ceil((remaining % 3600) / 60)
			notify(player, string.format("Next free spin in %dh %dm", hours, minutes), true)
			return false
		end
	end

	local reward = Config.RollSpinReward(rng)
	local description = grantReward(player, reward)
	if not description then
		notify(player, "Could not grant the prize - try again", true)
		return false
	end

	-- Ödül verildikten sonra hakkı harca: veremezsek hak da gitmesin
	DataService.Bump(player, "spins")
	if free then
		profile.lastSpinAt = os.time()
		DataService.Save(player)
	end

	spinning = true
	local stopsIn = animate(reward.id)

	-- Ödül verildi; mesaj çark ödülün diliminde durunca
	task.delay(stopsIn, function()
		if player.Parent then
			notify(player, string.format("%s! You won %s", reward.name, description), false)
		end
	end)
	BadgeService.Award(player, "FirstSpin")
	return true
end

-- ─── Prompt ─────────────────────────────────────────────────────────────────

local function setupPrompt()
	local decor = workspace:FindFirstChild("Decor")
	local wheel = decor and decor:FindFirstChild("Wheel")
	if not wheel then
		warn("[Spin] workspace.Decor.Wheel bulunamadi, cark promptu kurulmadi")
		return
	end

	--[[
		Prompt kaidenin ön yüzünde, göz hizasında. Eskiden yüksekteki
		göbekteydi: yaklaşınca göbek ekranın üstünde kalıyor, Roblox da
		ekran dışındaki promptu göstermiyor — yazı ancak yukarı bakınca
		çıkıyordu.
	]]
	local plinth = wheel:FindFirstChild("WheelPlinth")
	if not (plinth and plinth:IsA("BasePart")) then
		warn("[Spin] Cark kaidesi bulunamadi")
		return
	end
	-- Ön yüz, çarkın (göbeğin) olduğu taraf; kaidenin yönüne güvenmiyoruz
	local hub = wheel:FindFirstChild("WheelHub")
	local side = if hub and hub:IsA("BasePart") and plinth.CFrame:PointToObjectSpace(hub.Position).Z < 0 then -1 else 1
	local anchor = Instance.new("Attachment")
	anchor.Name = "SpinPromptPoint"
	anchor.Position = Vector3.new(0, plinth.Size.Y / 2 - 1, side * (plinth.Size.Z / 2 + 0.5))
	anchor.Parent = plinth

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SpinPrompt"
	prompt.ActionText = "Lucky Spin"
	prompt.ObjectText = "Free"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	spinPrompt = prompt

	PromptGuard.Connect(prompt, function(player)
		SpinService.Spin(player, true)
	end)

	--[[
		Prompt herkese ortak, bekleme süresi kişisel. En yakın oyuncunun
		durumunu yazmak yanıltıcı olurdu; onun yerine genel bir metin
		duruyor ve kişisel süre tetiklendiğinde bildirimle söyleniyor.
	]]
	task.spawn(function()
		while true do
			task.wait(5)
			local ready = 0
			for _, player in Players:GetPlayers() do
				if SpinService.GetCooldown(player) <= 0 then
					ready += 1
				end
			end
			prompt.ObjectText = if ready > 0 then "Free spin ready" else "Daily"
		end
	end)
end

function SpinService.Start()
	notifyRemote = Net.Get("Notify")

	MonetizationService.RegisterGranter("spin", function(player)
		return SpinService.Spin(player, false)
	end)

	setupPrompt()
	local wheel = getWheel()
	if wheel then
		decorateWheel(wheel)
	end
end

return SpinService
