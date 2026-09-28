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
--
-- 2026-09-28 (Yusuf): çevirme artık PENCEREDEN (istemci SpinPanel). Prompt
-- yalnızca pencereyi açıyor; SPIN düğmesi "SpinRequest" gönderiyor. Sunucu
-- ödülü seçip "SpinResult" ile dilimi söylüyor, pencerede çark o dilimde
-- duruyor ve ödül ANCAK O ZAMAN veriliyor (Config.SpinDuration sonra).
-- Salondaki büyük çark da (boştaysa) aynı dilime dönüyor. Oyuncu başına
-- kilit: iki oyuncu aynı anda çevirebiliyor. "SpinReadyAt" niteliği bedava
-- hakkın geleceği an (os.time), pencere geri sayımı ondan.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local WheelSpin = require(Shared.WheelSpin)

local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)
local SpaceService = require(script.Parent.SpaceService)
local MonetizationService = require(script.Parent.MonetizationService)
local BadgeService = require(script.Parent.BadgeService)

local SpinService = {}

local rng = Random.new()
local notifyRemote: RemoteEvent

-- Salondaki çark dönerken yeni çevirme onu yeniden başlatmıyor (pencere yine dönüyor)
local spinning = false
-- Oyuncunun kendi çevirmesi bitmeden (ödül verilmeden) ikincisi yok
local busy: { [Player]: boolean } = {}
-- Bekleyen ödülün jetonu: iptal edilince (testler) ödül verilmiyor
local pending: { [Player]: number } = {}
local pendingToken = 0
local lastRequest: { [Player]: number } = {}
local resultRemote: RemoteEvent? = nil
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

--[[ Pencereye jeton ve süper çark sayıları. ]]
local function publishTokens(player: Player)
	local profile = DataService.Get(player)
	if profile then
		player:SetAttribute("SpinTokens", profile.spinTokens)
		player:SetAttribute("SuperSpins", profile.superSpins)
	end
end

--[[ Pencerenin geri sayımı: bedava hakkın geleceği an (os.time). ]]
local function publishReady(player: Player)
	local profile = DataService.Get(player)
	if profile then
		player:SetAttribute("SpinReadyAt", profile.lastSpinAt + Config.SpinCooldownHours * 3600)
	end
end

-- ─── Ödül ───────────────────────────────────────────────────────────────────

--[[
	Ödülü uygular ve oyuncuya gösterilecek metni döner.
	Uygulanamazsa nil döner; çağıran hakkı harcamamalı.
]]
local function grantReward(player: Player, reward: Config.SpinReward, super: boolean?): string?
	if reward.kind == "cash" then
		local amount = Config.GetSpinCash(reward, EconomyService.GetIncome(player), EconomyService.GetCash(player))
		if super then
			amount = math.floor(amount * Config.SuperSpin.cashMul)
		end
		EconomyService.AddCash(player, amount)
		return string.format("$%s", Config.FormatCash(amount))

	elseif reward.kind == "spawn" or reward.kind == "mutation" or reward.kind == "unit" then
		--[[
			Konveyör kalktı: karakter doğrudan kaideye (SpaceService). Havuz
			oyuncunun hızının yettiği en iyi canavar; "unit" (Jackpot) bir
			üst canavarın havuzundan. Boş kaide yoksa ödül kaybolmasın diye
			o havuzdan bir karakterin satış değeri kadar nakit.
		]]
		local mutated = reward.kind == "mutation"
		local bonusTier = (if reward.kind == "unit" then 1 else 0) + (if super then Config.SuperSpin.bonusTier else 0)
		local name = SpaceService.GrantUnit(player, mutated, bonusTier)
		if name then
			return name
		end
		local def = Config.RollSpaceUnit(rng, SpaceService.PoolFor(player, bonusTier))
		local amount = Config.GetSellPrice(def.id, nil)
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
local function pickSlice(rewardId: string): (number, number)
	local slots = {}
	for i, id in Config.SpinWheelSlices do
		if id == rewardId then
			table.insert(slots, i)
		end
	end
	local index = if #slots > 0 then slots[rng:NextInteger(1, #slots)] else 1
	return index, rng:NextNumber(-WheelSpin.SLICE_JITTER, WheelSpin.SLICE_JITTER)
end

local function animate(index: number, jitter: number): number
	local wheel = getWheel()
	if not wheel or spinning then
		return Config.SpinDuration
	end
	spinning = true

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

-- Ödül -> dilim rengi ve yazısı (pencere de kullanıyor)
local SLICE_LOOK = Config.SpinSliceLook

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
	Robux ürününden geliyor ve hak kontrolü yapılmıyor. Ödül seçiliyor,
	dilim oyuncuya gidiyor ("SpinResult"), ödül çark durunca veriliyor.
	`instant` (testler) beklemeden verir.

	`kind` (free false iken): "token" bir çark jetonu harcar (bekleme yok),
	"super" bir SÜPER ÇARK hakkı harcar (Config.SuperSpin: ağırlıklar büyük
	ödüllere kayık, nakit ×3, karakter bir kademe üstten).
]]
function SpinService.Spin(player: Player, free: boolean, instant: boolean?, kind: string?): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	if not PlotService.GetPlotOf(player) then
		notify(player, "You need a base first", true)
		return false
	end

	if busy[player] then
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

	local super = not free and kind == "super"
	local useToken = not free and kind == "token"
	if super and profile.superSpins <= 0 then
		notify(player, "No super spins - finish a 7 day streak!", true)
		return false
	end
	if useToken and profile.spinTokens <= 0 then
		notify(player, "No spins left", true)
		return false
	end

	local reward = Config.RollSpinReward(rng, if super then Config.SuperSpin.weights else nil)
	local index, jitter = pickSlice(reward.id)
	if super then
		profile.superSpins -= 1
	elseif useToken then
		profile.spinTokens -= 1
	end
	publishTokens(player)

	-- Hak şimdi harcanıyor (pencere kapatılıp yeniden açılınca tekrar çevrilmesin)
	local previousSpinAt = profile.lastSpinAt
	if free then
		profile.lastSpinAt = os.time()
		publishReady(player)
	end
	busy[player] = true
	pendingToken += 1
	local token = pendingToken
	pending[player] = token

	local function finish()
		if pending[player] ~= token then
			return
		end
		pending[player] = nil
		busy[player] = nil
		if not player.Parent then
			return
		end
		local description = grantReward(player, reward, super)
		if not description then
			if free then
				profile.lastSpinAt = previousSpinAt
				publishReady(player)
			elseif super then
				profile.superSpins += 1
			elseif useToken then
				profile.spinTokens += 1
			end
			publishTokens(player)
			notify(player, "Could not grant the prize - try again", true)
			return
		end
		DataService.Bump(player, "spins")
		if free then
			DataService.Save(player)
		end
		notify(player, string.format("%s%s! You won %s", if super then "SUPER " else "", reward.name, description), false)
		BadgeService.Award(player, "FirstSpin")
	end

	if instant then
		finish()
		return true
	end
	local stopsIn = animate(index, jitter)
	if resultRemote then
		resultRemote:FireClient(player, reward.id, reward.name, stopsIn, index, jitter, super)
	end
	task.delay(stopsIn, finish)
	return true
end

--[[ Bekleyen ödülü iptal eder (yalnızca testler). ]]
function SpinService._CancelPending(player: Player)
	pending[player] = nil
	busy[player] = nil
end

--[[ Penceredeki SPIN düğmesi: çarkın yanında olmalı, art arda istek yok.
     `mode`: nil (günlük bedava), "token", "super". ]]
function SpinService.TrySpin(player: Player, mode: string?): boolean
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 1 then
		return false
	end
	lastRequest[player] = now
	local wheel = getWheel()
	local plinth = wheel and wheel:FindFirstChild("WheelPlinth")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if plinth and plinth:IsA("BasePart") and root and root:IsA("BasePart")
		and (root.Position - plinth.Position).Magnitude > 40 then
		return false
	end
	if mode == "token" or mode == "super" then
		return SpinService.Spin(player, false, nil, mode)
	end
	return SpinService.Spin(player, true)
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
	prompt.ActionText = "Open"
	prompt.ObjectText = "Lucky Spin"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	spinPrompt = prompt
	-- Tetikleme istemcide: pencereyi açıyor (SpinPanel); çevirme SpinRequest'le

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
			prompt.ObjectText = if ready > 0 then "Lucky Spin · FREE" else "Lucky Spin"
		end
	end)
end

function SpinService.Start()
	notifyRemote = Net.Get("Notify")
	resultRemote = Net.Get("SpinResult")
	Net.Get("SpinRequest").OnServerEvent:Connect(function(player, mode)
		SpinService.TrySpin(player, if typeof(mode) == "string" then mode else nil)
	end)
	-- 5'li çark paketi (Config.SpinPack, kimlik girilince): jeton
	MonetizationService.RegisterGranter("spinpack", function(player)
		local profile = DataService.Get(player)
		if not profile then
			return false
		end
		profile.spinTokens += Config.SpinPack.count
		publishTokens(player)
		return true
	end)
	local function onPlayer(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player, 30) and player.Parent then
				publishReady(player)
				publishTokens(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		pending[player] = nil
		lastRequest[player] = nil
	end)

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
