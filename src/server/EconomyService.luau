--!strict
-- Nakit, leaderstats ve saniyelik gelir üretimi.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local BadgeService = require(script.Parent.BadgeService)

local EconomyService = {}

local cash: { [Player]: number } = {}
local notifyRemote: RemoteEvent

-- ─── Nakit ──────────────────────────────────────────────────────────────────

local function refreshStats(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash")
	if value and value:IsA("StringValue") then
		value.Value = "$" .. Config.FormatCash(cash[player] or 0)
	end
	player:SetAttribute("Cash", cash[player] or 0)
end

--[[
	Nakdi hem arayüze hem profile yazar. Profil DataService'in kaydettiği
	tablonun ta kendisi, dolayısıyla ayrıca "kaydet" demeye gerek yok.
]]
local function commitCash(player: Player)
	local profile = DataService.Get(player)
	if profile then
		profile.cash = cash[player] or 0
	end
	refreshStats(player)
	BadgeService.CheckCash(player, cash[player] or 0)
end

function EconomyService.GetCash(player: Player): number
	return cash[player] or 0
end

function EconomyService.AddCash(player: Player, amount: number)
	cash[player] = (cash[player] or 0) + amount
	commitCash(player)

	-- Görevler "şu kadar kazan" diyebiliyor. Harcama bu sayacı düşürmüyor;
	-- düşürseydi para biriktirmek görev ilerlemesi sayılırdı, oysa istenen
	-- kazanmak. Negatif çağrı (ceza) da sayaca yazılmıyor.
	if amount > 0 then
		DataService.Bump(player, "earned", amount)
	end
end

--[[ Parası yeterliyse düşer ve true döner. ]]
function EconomyService.TrySpend(player: Player, amount: number): boolean
	local current = cash[player] or 0
	if current < amount then
		return false
	end

	cash[player] = current - amount
	commitCash(player)
	return true
end

-- ─── Gelir ──────────────────────────────────────────────────────────────────

--[[ Oyuncunun kaidelerindeki karakterlerin toplam saniyelik geliri. ]]
function EconomyService.GetIncome(player: Player): number
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		return 0
	end

	local total = 0
	for _, podium in PlotService.GetPodiums(plot) do
		local unitId = podium:GetAttribute("UnitId") :: string
		if unitId ~= "" then
			local def = Config.GetUnit(unitId)
			if def then
				local mutationId = podium:GetAttribute("MutationId") :: string
				local mutation = Config.GetMutation(if mutationId == "" then nil else mutationId)
				total += def.income * (if mutation then mutation.incomeMul else 1)
			end
		end
	end

	-- Rebirth ve gamepass çarpanları en sonda, birbirleriyle çarpılarak
	local profile = DataService.Get(player)
	local rebirths = if profile then profile.rebirths else 0
	local multiplier = Config.GetIncomeMultiplier(rebirths)
		* MonetizationService.GetIncomeMultiplier(player)

	--[[
		Pet bonusu. PetService'i require ETMİYORUZ: yumurta açmak bu
		servisin TrySpend'ine muhtaç, yani karşılıklı require döngü olurdu.
		PetService bonusu niteliğe yazıyor, burası okuyor — tek yönlü.

		Çarpan olarak giriyor, toplama değil: petin değeri oyuncunun
		gelirinin büyüklüğünden bağımsız aynı oranda kalsın.
	]]
	local petBonus = player:GetAttribute("PetIncomeBonus") :: number?
	multiplier *= 1 + math.max(0, petBonus or 0)

	-- İndeks ödülleri: tamamlanan nadirlik satırlarının kalıcı bonusu.
	-- Aynı gerekçeyle nitelikten (RewardService yazıyor)
	local indexBonus = player:GetAttribute("IndexBonus") :: number?
	multiplier *= 1 + math.max(0, indexBonus or 0)

	return math.floor(total * multiplier)
end

-- ─── Yaşam döngüsü ──────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	-- leaderstats hemen kurulsun ki profil gelene kadar tablo boş görünmesin
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"

	local cashValue = Instance.new("StringValue")
	cashValue.Name = "Cash"
	cashValue.Value = "$0"
	cashValue.Parent = stats

	local stolenValue = Instance.new("IntValue")
	stolenValue.Name = "Stolen"
	stolenValue.Value = 0
	stolenValue.Parent = stats

	stats.Parent = player

	-- Kayıtlı veri gelene kadar bekle; gelmezse oyuncu zaten atılmış olur
	local profile = DataService.WaitForProfile(player)
	if not profile or player.Parent == nil then
		return
	end

	cash[player] = profile.cash
	stolenValue.Value = profile.stolen
	refreshStats(player)

	-- Çevrimdışı kazanç profile zaten eklendi; oyuncuya haber ver
	local earned, seconds = DataService.ConsumeOfflineEarnings(player)
	if earned > 0 and notifyRemote then
		-- Çevrimdışı kazanç: girişte bir kez, kendi sesiyle
		notifyRemote:FireClient(player, string.format(
			"Welcome back! You earned $%s while away (%d min)",
			Config.FormatCash(earned),
			math.floor(seconds / 60)
		), false, "welcome")
	end
end

function EconomyService.AddStealCount(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Stolen")
	if value and value:IsA("IntValue") then
		value.Value += 1

		local profile = DataService.Get(player)
		if profile then
			profile.stolen = value.Value
		end
	end
end

function EconomyService.Start()
	notifyRemote = Net.Get("Notify")

	-- Nakit paketleri: satın alınca doğrudan bakiyeye ekleniyor
	MonetizationService.RegisterGranter("cash", function(player, product)
		local amount = product.amount
		if not amount or amount <= 0 then
			return false
		end
		EconomyService.AddCash(player, amount)
		return true
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		cash[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.IncomeInterval)
			for _, player in Players:GetPlayers() do
				local income = EconomyService.GetIncome(player)
				if income > 0 then
					EconomyService.AddCash(player, income * Config.IncomeInterval)
				end
				player:SetAttribute("Income", income)

				-- Kilitlenme koruması: geliri sıfır ve en ucuz karakteri
				-- bile alamıyorsa oyuncu hiçbir şey yapamaz. Satmak artık
				-- engelli ama karakteri çalınan oyuncu da bu duruma
				-- düşebiliyor, o yüzden kontrol satıştan bağımsız.
				if income <= 0 and PlotService.GetPlotOf(player) then
					local floor = Config.GetCheapestUnitPrice()
					if EconomyService.GetCash(player) < floor then
						EconomyService.AddCash(player, floor - EconomyService.GetCash(player))
					end
				end

				-- Çevrimdışı kazanç bu değerden hesaplanıyor
				local profile = DataService.Get(player)
				if profile then
					profile.incomePerSecond = income
				end
			end
		end
	end)
end

return EconomyService
