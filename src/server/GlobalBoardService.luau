--!strict
--[[
	Lobideki üç sıralama panosu — KÜRESEL (bütün sunucular, bütün zamanlar).

	Eskiden panoları istemci dolduruyordu ve yalnızca o sunucudaki oyuncuları
	gösteriyordu: sekiz kişilik bir sunucuda "RICHEST" panosu en fazla sekiz
	isimdi ve oyuncu gerçekten ne kadar iyi olduğunu göremiyordu.

	Artık sunucu OrderedDataStore'a yazıyor ve oradan okuyor:

	    TOP EARNERS  — hayat boyu kazanılan para (profile.earned). Nakit
	                   harcandıkça düştüğü için "en zengin" yerine bu.
	    MOST STOLEN  — hayat boyu çalma sayısı (profile.stolen)
	    TOP INCOME   — saniyelik gelir (profile.incomePerSecond)

	Panolar Decor'daki SurfaceGui'ler; sunucu yazınca herkese replike
	oluyor, istemcinin bir şey yapmasına gerek yok.

	═══ KOTA ═══════════════════════════════════════════════════════════════

	OrderedDataStore kotası dar. Yazma oyuncu başına dakikada bir (ve
	çıkarken), okuma üç pano için dakikada bir. İsimler UserId'den bir kez
	çözülüp önbelleğe alınıyor.

	Studio'da API erişimi kapalıysa ya da istek başarısızsa pano o
	sunucudaki oyunculara düşüyor — boş kalmıyor.

	═══ TOP CREW KÜRSÜSÜ ═══════════════════════════════════════════════════

	Lobinin güneydoğusundaki 1-2-3 kürsüsünde TOP EARNERS panosunun ilk
	üçünün GERÇEK Roblox karakterleri duruyor (Players:
	CreateHumanoidModelFromUserId — oyunda olmasalar da). Eskiden haritayla
	konmuş sabit Among Us karakterleriydi, sıralamayla ilgisi yoktu. Kimse
	değişmedikçe karakter yeniden kurulmuyor; yalnızca isim plakası.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local DataService = require(script.Parent.DataService)

local GlobalBoardService = {}

local INTERVAL = 60
local ROWS = 8

type Board = {
	index: number,
	title: string,
	store: string,
	value: (profile: any) -> number,
	format: (number) -> string,
}

local BOARDS: { Board } = {
	{ index = 1, title = "TOP EARNERS", store = "Global_Earned_v1",
		value = function(p) return p.earned or 0 end,
		format = function(v) return "$" .. Config.FormatCash(v) end },
	{ index = 2, title = "MOST STOLEN", store = "Global_Stolen_v1",
		value = function(p) return p.stolen or 0 end,
		format = function(v) return tostring(math.floor(v)) end },
	{ index = 3, title = "TOP INCOME", store = "Global_Income_v1",
		value = function(p) return p.incomePerSecond or 0 end,
		format = function(v) return "+$" .. Config.FormatCash(v) .. "/s" end },
}

-- İlk üçün renkleri: altın, gümüş, bronz
local PODIUM = { "#FFC83C", "#C8D2DE", "#D68C50" }

local stores: { [string]: OrderedDataStore? } = {}
local names: { [number]: string } = {}

local function storeFor(board: Board): OrderedDataStore?
	if stores[board.store] == nil then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.store)
		end)
		stores[board.store] = if ok then store else nil
	end
	return stores[board.store]
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		names[userId] = online.DisplayName
		return online.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and typeof(name) == "string" then name else "Crewmate"
	names[userId] = result
	return result
end

local function screenBody(index: number): (TextLabel?, TextLabel?)
	local decor = workspace:FindFirstChild("Decor")
	local boards = decor and decor:FindFirstChild("Boards")
	local screen = boards and boards:FindFirstChild("BoardScreen" .. index)
	local surface = screen and screen:FindFirstChild("Display")
	local body = surface and surface:FindFirstChild("Body")
	local header = surface and surface:FindFirstChild("Header")
	return (if body and body:IsA("TextLabel") then body else nil),
		(if header and header:IsA("TextLabel") then header else nil)
end

type Row = { name: string, value: number, userId: number? }

local function render(board: Board, rows: { Row }, global: boolean)
	local body, header = screenBody(board.index)
	if not body then
		return
	end
	if header then
		header.Text = if global then "GLOBAL " .. board.title else board.title .. " · THIS SERVER"
	end
	body.RichText = true
	body.TextSize = 18
	local lines = {}
	for rank, row in rows do
		local color = PODIUM[rank]
		local line = string.format("%d.  %s   %s", rank, string.sub(row.name, 1, 16), board.format(row.value))
		table.insert(lines, if color then string.format('<font color="%s">%s</font>', color, line) else line)
	end
	body.Text = if #lines > 0 then table.concat(lines, "\n") else "no crewmates yet"
end

--[[ Yedek: o sunucudaki oyuncular (API yoksa ya da istek düştüyse). ]]
local function localRows(board: Board): { Row }
	local rows: { Row } = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile then
			table.insert(rows, { name = player.DisplayName, value = board.value(profile), userId = player.UserId })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	while #rows > ROWS do
		table.remove(rows)
	end
	return rows
end

local function write(player: Player)
	local profile = DataService.Get(player)
	if not profile or not DataService.IsAvailable() then
		return
	end
	for _, board in BOARDS do
		local store = storeFor(board)
		if store then
			local value = math.floor(math.max(0, board.value(profile)))
			pcall(function()
				(store :: OrderedDataStore):SetAsync(tostring(player.UserId), value)
			end)
		end
	end
end

-- ─── TOP CREW kürsüsü ───────────────────────────────────────────────────────

-- R15 varsayılan boşta durma (Roblox'un Animate betiğindeki "idle")
local IDLE_ANIMATION = "rbxassetid://507766666"
local AVATAR_SCALE = 1.3
local RANK_COLORS = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(200, 210, 222), Color3.fromRGB(214, 140, 80) }

local podiumUsers: { [number]: number } = {}      -- sıra -> şu an duran UserId
local podiumModels: { [number]: Model } = {}
local podiumPlates: { [number]: { name: TextLabel, value: TextLabel } } = {}
local cleared = false

local function podiumFolder(): Instance?
	local decor = workspace:FindFirstChild("Decor")
	local folder = decor and decor:FindFirstChild("Podium", true)
	return if folder and folder:FindFirstChild("Step1") then folder else nil
end

--[[ Basamağın üst yüzeyinin ortası, odaya bakan yönde. ]]
local function stepTop(folder: Instance, rank: number): CFrame?
	local step = folder:FindFirstChild("Step" .. rank)
	if not (step and step:IsA("BasePart")) then
		return nil
	end
	return step.CFrame * CFrame.new(0, step.Size.Y / 2, 0)
end

local function buildAvatar(userId: number): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not model then
		return nil
	end
	model.Name = "TopCrewAvatar"
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end
	pcall(function()
		model:ScaleTo(AVATAR_SCALE)
	end)
	return model
end

local function plateFor(folder: Instance, rank: number, top: CFrame): { name: TextLabel, value: TextLabel }
	local existing = podiumPlates[rank]
	if existing and existing.name.Parent then
		return existing
	end
	local anchor = Instance.new("Part")
	anchor.Name = "TopCrewPlate" .. rank
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = top * CFrame.new(0, 3.5, 0) -- boşken basamağın hemen üstü; karakter gelince kafasının üstüne
	anchor.Parent = folder

	-- Ölçekli boyut (stud): piksel boyutlu etiketler bu oyunda çizilmiyordu
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(9, 2.6)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Parent = anchor
	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 0.6)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = RANK_COLORS[rank] or Color3.new(1, 1, 1)
	name.Text = ""
	name.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(22, 20, 34)
	stroke.Thickness = 3
	stroke.Parent = name
	local value = Instance.new("TextLabel")
	value.Position = UDim2.fromScale(0, 0.6)
	value.Size = UDim2.fromScale(1, 0.4)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.TextScaled = true
	value.TextColor3 = Color3.new(1, 1, 1)
	value.Text = ""
	value.Parent = gui
	local vstroke = Instance.new("UIStroke")
	vstroke.Color = Color3.fromRGB(22, 20, 34)
	vstroke.Thickness = 2
	vstroke.Parent = value
	local plate = { name = name, value = value }
	podiumPlates[rank] = plate
	return plate
end

--[[ Kürsüye `rows`un ilk üçünü koyar (TOP EARNERS). ]]
local function updatePodium(board: Board, rows: { Row })
	local folder = podiumFolder()
	if not folder then
		return
	end
	-- Haritanın koyduğu sabit Among Us karakterleri bir kez kalkıyor
	if not cleared then
		cleared = true
		for _, child in folder:GetChildren() do
			if child:IsA("Model") and child.Name ~= "TopCrewAvatar" then
				child:Destroy()
			end
		end
	end

	for rank = 1, 3 do
		local top = stepTop(folder, rank)
		if not top then
			continue
		end
		local row = rows[rank]
		local plate = plateFor(folder, rank, top)
		plate.name.Text = if row then string.format("#%d %s", rank, string.sub(row.name, 1, 18)) else string.format("#%d", rank)
		plate.value.Text = if row then board.format(row.value) else "empty"

		local userId = row and row.userId
		if userId == podiumUsers[rank] and (userId == nil or (podiumModels[rank] and podiumModels[rank].Parent)) then
			continue
		end
		local old = podiumModels[rank]
		if old then
			old:Destroy()
			podiumModels[rank] = nil
		end
		podiumUsers[rank] = userId
		if not userId or userId <= 0 then
			continue
		end
		local model = buildAvatar(userId)
		if not model then
			continue
		end
		-- Ayaklar basamağın üstünde. Basamağın bakışı (LookVector) odaya
		-- dönük; karakterin yüzü de LookVector'ünde, yani döndürme yok.
		-- Eklemler ancak dünyadayken yerine oturuyor: önce koy, bir kare bekle,
		-- sonra ayakların gerçek yerine göre yükselt (dışarıda ölçülen sınır
		-- kutusu yanlıştı, karakter basamağa 1.8 stud gömülüyordu)
		model:PivotTo(top)
		model.Parent = folder
		podiumModels[rank] = model
		task.wait()
		if not model.Parent then
			continue
		end
		local box, size = model:GetBoundingBox()
		local bottom = box.Position.Y - size.Y / 2
		model:PivotTo(model:GetPivot() + Vector3.new(0, top.Position.Y - bottom, 0))
		-- Plaka kafanın hemen üstünde (sabit yükseklikte 1. basamağın plakası
		-- TOP CREW tabelasına biniyordu)
		local anchor = folder:FindFirstChild("TopCrewPlate" .. rank)
		if anchor and anchor:IsA("BasePart") then
			anchor.CFrame = top * CFrame.new(0, size.Y + 1.6, 0)
		end

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = humanoid
			pcall(function()
				local animation = Instance.new("Animation")
				animation.AnimationId = IDLE_ANIMATION
				local track = animator:LoadAnimation(animation)
				track.Looped = true
				track:Play()
			end)
		end
	end
end

local function refresh()
	for _, board in BOARDS do
		local store = if DataService.IsAvailable() then storeFor(board) else nil
		local rows: { Row }? = nil
		if store then
			local ok, page = pcall(function()
				return (store :: OrderedDataStore):GetSortedAsync(false, ROWS):GetCurrentPage()
			end)
			if ok and typeof(page) == "table" then
				local list: { Row } = {}
				for _, entry in page do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(list, { name = nameOf(userId), value = entry.value, userId = userId })
					end
				end
				rows = list
			end
		end
		local shown = if rows and #rows > 0 then rows else localRows(board)
		render(board, shown, rows ~= nil and #rows > 0)
		if board.index == 1 then
			task.spawn(updatePodium, board, shown)
		end
	end
end

function GlobalBoardService.Start()
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(write, player)
	end)

	task.spawn(function()
		-- İlk çizim hemen (yerel), küresel veri ilk turda gelince yerini alıyor
		task.wait(5)
		refresh()
		while true do
			for _, player in Players:GetPlayers() do
				write(player)
			end
			refresh()
			task.wait(INTERVAL)
		end
	end)
end

-- Testler için
GlobalBoardService._UpdatePodium = function(rows: { Row })
	updatePodium(BOARDS[1], rows)
end

return GlobalBoardService
