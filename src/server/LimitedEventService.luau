--!strict
--[[
	Sınırlı etkinlik (2026-09-30, Config.LimitedEvent): bir haftalık, tarihe
	bağlı, temadan bağımsız etkinlik (şu an 🌠 STARFALL WEEK; Cadılar
	Bayramı taslağı Config.SpookyEventDraft). Kurallar Config'teki başlıkta.
	İç adlarda "candy" = etkinlik parası (oyuncuya Config'teki `currency`).

	  PARA      — her soygunda (SpaceService.Delivered; miktar
	              Config.GetHeistCandy, istemci kartında da aynısı yazıyor),
	              etkinlikte her gün ilk girişte (7 günlük takvim, dailyLadder)
	              ve YILDIZ YAĞMURUNDA (EventService "EventShower", saat :15/:45:
	              uzaya yıldızlar düşüyor, ilk dokunan alıyor, nadiren SUPERNOVA).
	              Son 24 saat hepsi finalDayMul katı.
	  YOL       — kazanılan toplam (earned) basamaklara varınca bedava ödül
	              (Config.LimitedEvent.milestones), sırayla, kendiliğinden
	  ORTAK     — GALAXY GOAL (community): bütün sunucuların kazandığı toplam
	              DataStore'da (sunucu başına dakikada bir UpdateAsync), her
	              kademe etkinlikte oynamış herkese ödül; workspace.EventGlobal.
	              Lobi tabelasının orta sütunu ve kafeteryadaki dev yıldız
	              (EventStarBeacon, ilerledikçe parlıyor) bunu gösteriyor.
	  MUTASYON  — gezegen doğuşlarında (SpaceService.rollSpot) etkinlik
	              mutasyonu (Config.LimitedEvent.mutation); çalınca 3x para
	  DÜKKÂN    — "EventShop" remote'u (itemId): para sunucudaki sayaçtan,
	              fiyat/adet Config'ten, yalnızca etkinlik sürerken
	  SÜS       — güvertede ve kafeteryada (decor: yıldız kristali / balkabağı)

	Profil: `limited` (id, candy, bought, lastDaily, earned, awarded, days, ms);
	etkinlik kimliği değişince sıfırlanıyor. `gt` = alınan ortak hedef kademesi. İstemciye nitelikler: EventCandy,
	EventEarned, EventBought ("id:n,id:n"), EventDays (giriş yapılan gün),
	EventDayDone (bugünkü alındı mı), EventMs (alınan yol basamağı).
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SpaceField = require(Shared.SpaceField)

local AnnounceService = require(script.Parent.AnnounceService)
local MonetizationService = require(script.Parent.MonetizationService)
local CosmeticService = require(script.Parent.CosmeticService)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local SpaceService = require(script.Parent.SpaceService)

local LimitedEventService = {}

LimitedEventService.NotifyKind = "reward"

local notifyRemote: RemoteEvent? = nil
local lastBuy: { [Player]: number } = {}
-- Testler saati sabitleyebiliyor
local nowOverride: number? = nil
local rng = Random.new()

local function now(): number
	return nowOverride or os.time()
end

-- `kind`: ses türü (Config.NotifyCues); yoksa "reward"
local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, kind or LimitedEventService.NotifyKind)
	end
end

--[[ Profilin sayacı bu etkinliğin mi; değilse sıfırla. ]]
local function roll(profile: any)
	if profile.limited.id ~= Config.LimitedEvent.id then
		profile.limited = { id = Config.LimitedEvent.id, candy = 0, bought = {}, lastDaily = 0, earned = 0, awarded = 0, days = 0, ms = 0, gt = 0 }
	end
end

function LimitedEventService.Publish(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	roll(profile)
	local parts = {}
	for id, n in profile.limited.bought do
		table.insert(parts, id .. ":" .. n)
	end
	table.sort(parts)
	player:SetAttribute("EventCandy", profile.limited.candy)
	player:SetAttribute("EventEarned", profile.limited.earned)
	player:SetAttribute("EventBought", table.concat(parts, ","))
	player:SetAttribute("EventDays", profile.limited.days)
	player:SetAttribute("EventDayDone", profile.limited.lastDaily == Config.DayIndex(now()))
	player:SetAttribute("EventMs", profile.limited.ms)
end

-- ─── Ortak hedef (Config.LimitedEvent.community) ───────────────────────────

local goalStore: DataStore? = nil
local goalFor = ""
local goalTotal = 0      -- DataStore'dan son okunan toplam (bütün sunucular)
local goalPending = 0    -- bu sunucuda kazanılıp henüz yazılmamış
local goalSeen: number? = nil -- bu sunucunun gördüğü kademe (duyuru için)
-- Testler sürerken gerçek DataStore'a (ortak toplam, sıralama) yazılmıyor
local testing = false

--[[ Bu sunucuda kazanılan parayı ortak toplama ekler (dakikada bir yazılıyor). ]]
function LimitedEventService.AddCommunity(amount: number)
	if amount > 0 then
		goalPending += amount
	end
end

--[[ Bilinen ortak toplam (yazılmayı bekleyen dahil). ]]
function LimitedEventService.CommunityTotal(): number
	return goalTotal + goalPending
end

local function communityStore(): DataStore?
	local id = Config.LimitedEvent.id
	if goalFor ~= id then
		goalFor = id
		goalTotal, goalPending, goalSeen = 0, 0, nil
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore("LimitedEventGoal")
		end)
		goalStore = if ok then result else nil
	end
	return goalStore
end

--[[
	Bekleyeni DataStore'a ekler ve güncel toplamı okur. DataStore yoksa
	(Studio) toplam bu sunucuda tutuluyor.
]]
local function flushCommunity()
	local store = communityStore()
	local key = Config.LimitedEvent.id
	if testing or not (store and DataService.IsAvailable()) then
		goalTotal += goalPending
		goalPending = 0
		return
	end
	local sending = goalPending
	local ok, result = pcall(function()
		if sending > 0 then
			return (store :: DataStore):UpdateAsync(key, function(old)
				return (if typeof(old) == "number" then old else 0) + sending
			end)
		end
		return (store :: DataStore):GetAsync(key)
	end)
	if ok then
		goalPending -= sending
		if typeof(result) == "number" then
			goalTotal = math.max(goalTotal, result)
		end
	end
end

local function publishCommunity()
	local total = LimitedEventService.CommunityTotal()
	workspace:SetAttribute("EventGlobal", total)
	-- Kafeteryadaki dev yıldız ilerledikçe parlıyor
	local beacon = workspace:FindFirstChild("EventDecor")
	beacon = beacon and beacon:FindFirstChild("EventStarBeacon")
	local core = beacon and beacon:FindFirstChild("Crystal")
	local light = core and core:FindFirstChildOfClass("PointLight")
	if light then
		local tiers = Config.LimitedEvent.community.tiers
		local progress = math.clamp(total / tiers[#tiers].at, 0, 1)
		light.Brightness = 1 + progress * 3
		light.Range = 20 + progress * 30
	end
end

--[[
	Ortak hedefin ulaşılan kademelerini oyuncuya verir (etkinlikte hiç para
	kazandıysa). Mürettebat ödülü boş kaide yoksa bekliyor. Döner: verilen sayı.
]]
function LimitedEventService.CheckCommunity(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	roll(profile)
	if profile.limited.earned <= 0 then
		return 0
	end
	local e = Config.LimitedEvent
	local reached = Config.EventCommunityReached(LimitedEventService.CommunityTotal())
	local given = 0
	while profile.limited.gt < reached do
		local tier = e.community.tiers[profile.limited.gt + 1]
		local got: string? = nil
		if tier.reward.kind == "unit" then
			got = SpaceService.GrantUnit(player, false, nil, e.mutation)
			if not got then
				notify(player, string.format("%s reward waiting: free a podium to get your %s!", e.community.name, tier.label), true)
				break
			end
		else
			got = RewardService.Give(player, tier.reward)
			if not got then
				break
			end
		end
		profile.limited.gt += 1
		given += 1
		notify(player, string.format("%s reached! Everyone gets %s - you got %s!", e.community.name, tier.label, got :: string), false, "fanfare")
	end
	if given > 0 then
		DataService.RequestSave(player)
	end
	return given
end

--[[ Dakikada bir: yaz/oku, yayınla, yeni kademeyi duyur, oyuncuların payı. ]]
local function communityTick()
	flushCommunity()
	publishCommunity()
	local e = Config.LimitedEvent
	local reached = Config.EventCommunityReached(LimitedEventService.CommunityTotal())
	if goalSeen and reached > goalSeen then
		local tier = e.community.tiers[reached]
		AnnounceService.Summon(string.format("%s REACHED! Everyone who played gets %s!",
			AnnounceService.Paint(e.community.name, e.color), tier.label))
	end
	goalSeen = reached
	for _, player in Players:GetPlayers() do
		LimitedEventService.CheckCommunity(player)
	end
end

--[[ Testler: ortak toplamı sabitler (DataStore'a dokunmadan). ]]
function LimitedEventService._SetCommunity(total: number)
	communityStore()
	goalTotal, goalPending = total, 0
end

--[[ Testler: açıkken DataStore'a yazılmıyor (test paraları gerçek toplama karışmasın). ]]
function LimitedEventService._SetTesting(on: boolean)
	testing = on
end

--[[ Testler: ortak hedef adımı (dakikalık döngünün işi). ]]
function LimitedEventService._CommunityTick()
	communityTick()
end

--[[
	Yıldız yolu: kazanılan toplam sıradaki basamağa vardıysa ödülü verir
	(sırayla; bir seferde birkaç basamak geçilebilir). Mürettebat ödülü boş
	kaide yoksa bekliyor (sonraki paraya ya da girişe kadar), sıra kaymıyor.
	Döner: verilen basamak sayısı.
]]
function LimitedEventService.CheckMilestones(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	roll(profile)
	local e = Config.LimitedEvent
	local given = 0
	while true do
		local step, index = Config.EventNextMilestone(profile.limited.ms)
		if not step or profile.limited.earned < step.at then
			break
		end
		local got: string? = nil
		if step.reward.kind == "unit" then
			got = SpaceService.GrantUnit(player, false, nil, e.mutation)
			if not got then
				notify(player, string.format("%s reward waiting: free a podium to get your %s!", e.text.path, step.label), true)
				break
			end
		else
			got = RewardService.Give(player, step.reward)
			if not got then
				break
			end
		end
		profile.limited.ms = index
		given += 1
		notify(player, string.format("%s %d/%d: you got %s!", e.text.path, index, #e.milestones, got :: string), false,
			if index == #e.milestones then "fanfare" else nil)
		if index == #e.milestones then
			AnnounceService.Summon(string.format("%s finished the %s!", player.DisplayName, AnnounceService.Paint(e.text.path, e.color)))
		end
	end
	if given > 0 then
		LimitedEventService.Publish(player)
		DataService.RequestSave(player)
	end
	return given
end

--[[
	Robux'la alınan etkinlik parası (Config.EventProducts). Yalnızca harcanabilir
	paraya ekleniyor: `earned` (sıralama, yıldız yolu, ortak hedef) değişmiyor.
	Etkinlik bitmiş olsa bile veriliyor (ödeme alındı; dükkân zaten kapalı).
	Döner: verildi mi (MonetizationService makbuzu buna göre işliyor).
]]
function LimitedEventService.GrantPurchased(player: Player, amount: number): boolean
	local profile = DataService.Get(player)
	if not profile or amount <= 0 then
		return false
	end
	roll(profile)
	profile.limited.candy += math.floor(amount)
	LimitedEventService.Publish(player)
	local e = Config.LimitedEvent
	notify(player, string.format("+%d %s %s! Spend it in the EVENT shop", math.floor(amount), e.icon, e.currency), false, "fanfare")
	return true
end

--[[ Şeker ekler (soygun, bonus). Etkinlik dışında ya da 0'da bir şey yapmıyor. ]]
function LimitedEventService.AddCandy(player: Player, amount: number)
	local profile = DataService.Get(player)
	if not profile or amount <= 0 or not Config.IsLimitedEventActive(now()) then
		return
	end
	roll(profile)
	profile.limited.candy += math.floor(amount)
	profile.limited.earned += math.floor(amount)
	LimitedEventService.AddCommunity(math.floor(amount))
	LimitedEventService.Publish(player)
	DataService.RequestSave(player)
	LimitedEventService.CheckMilestones(player)
end

--[[ Etkinlikte günün ilk girişi: bonus şeker. Verildiyse true. ]]
function LimitedEventService.Daily(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile or not Config.IsLimitedEventActive(now()) then
		return false
	end
	roll(profile)
	local day = Config.DayIndex(now())
	if profile.limited.lastDaily == day then
		return false
	end
	profile.limited.lastDaily = day
	profile.limited.days += 1
	local e = Config.LimitedEvent
	local amount = Config.EventDailyAmount(profile.limited.days) * Config.EventCandyMul(now())
	LimitedEventService.AddCandy(player, amount)
	notify(player, string.format("%s DAY %d: +%d %s %s! Come back tomorrow for more", e.name, profile.limited.days, amount, e.icon, e.currency), false)
	return true
end

--[[
	Dükkândan alır. Döner: (başarılı mı, ileti). Şeker yalnızca başarıda düşüyor
	(ör. kaide doluysa karakter verilemez, şeker yerinde kalır).
]]
function LimitedEventService.Buy(player: Player, itemId: string): (boolean, string)
	local item = Config.GetEventShopItem(itemId)
	local profile = DataService.Get(player)
	if not (item and profile) then
		return false, "Unknown item"
	end
	if not Config.IsLimitedEventActive(now()) then
		return false, "The event shop is closed"
	end
	roll(profile)
	local have = profile.limited.bought[item.id] or 0
	if have >= item.limit then
		return false, "You already got the max of " .. item.name
	end
	if profile.limited.candy < item.price then
		return false, string.format("You need %d %s %s", item.price, Config.LimitedEvent.icon, Config.LimitedEvent.currency)
	end

	local got: string? = nil
	if item.kind == "unit" then
		local name = SpaceService.GrantUnit(player, false, nil, Config.LimitedEvent.mutation)
		if not name then
			return false, "No free podium! Sell or rebirth to make room"
		end
		got = name
	elseif item.kind == "superspin" then
		got = RewardService.Give(player, { kind = "superspin", count = 1 } :: any)
	elseif item.kind == "cosmetic" and item.cosmetic then
		if CosmeticService.Grant(player, item.cosmetic) then
			got = item.name
		end
	end
	if not got then
		return false, "Could not give " .. item.name
	end

	profile.limited.candy -= item.price
	profile.limited.bought[item.id] = have + 1
	LimitedEventService.Publish(player)
	DataService.RequestSave(player)
	if item.kind == "cosmetic" then
		-- Sosyal kanıt: sınırlı eşya herkesin önünde
		AnnounceService.Summon(string.format("%s got the LIMITED %s!", player.DisplayName,
			AnnounceService.Paint(item.name, Config.LimitedEvent.color)))
	end
	return true, "You got " .. got .. "!"
end

--[[ Testler için saati sabitler (nil = gerçek saat). ]]
function LimitedEventService._SetNow(t: number?)
	nowOverride = t
end

-- ─── Sıralama ve ilk 10 ödülü (Config.LimitedEvent.leaderboard) ─────────────

type Row = { n: string, v: number, u: number }
local store: OrderedDataStore? = nil
local storeFor = ""
local finalTop: { Row }? = nil

local function boardStore(): OrderedDataStore?
	local id = Config.LimitedEvent.id
	if storeFor ~= id then
		storeFor = id
		finalTop = nil
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore("LimitedEvent_" .. id)
		end)
		store = if ok then result else nil
	end
	return store
end

--[[ Oyuncunun etkinlik toplamını sıralamaya yazar. ]]
local function writeBoard(player: Player)
	local profile = DataService.Get(player)
	if not profile or profile.limited.id ~= Config.LimitedEvent.id or profile.limited.earned <= 0 then
		return
	end
	local s = boardStore()
	if testing or not (s and DataService.IsAvailable()) then
		return
	end
	local value = math.floor(profile.limited.earned)
	pcall(function()
		(s :: OrderedDataStore):SetAsync(tostring(player.UserId), value)
	end)
end

--[[ İlk N (bütün sunucular). DataStore yoksa nil. ]]
local function readBoard(): { Row }?
	local s = boardStore()
	if not (s and DataService.IsAvailable()) then
		return nil
	end
	local rows = Config.LimitedEvent.leaderboard.rows
	local ok, page = pcall(function()
		return (s :: OrderedDataStore):GetSortedAsync(false, rows + 5):GetCurrentPage()
	end)
	if not ok or typeof(page) ~= "table" then
		return nil
	end
	local out: { Row } = {}
	for _, entry in page do
		local userId = tonumber(entry.key)
		if userId and not Config.LeaderboardHidden[userId] and entry.value > 0 and #out < rows then
			local online = Players:GetPlayerByUserId(userId)
			local name = if online then online.DisplayName else nil
			if not name then
				local okName, result = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				name = if okName and typeof(result) == "string" then result else "Crewmate"
			end
			table.insert(out, { n = name :: string, v = entry.value, u = userId })
		end
	end
	return out
end

--[[ Yedek: bu sunucudaki oyuncular (Studio / DataStore kapalı). ]]
local function localBoard(): { Row }
	local out: { Row } = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile and profile.limited.id == Config.LimitedEvent.id and profile.limited.earned > 0
			and not Config.LeaderboardHidden[player.UserId] then
			table.insert(out, { n = player.DisplayName, v = profile.limited.earned, u = player.UserId })
		end
	end
	table.sort(out, function(a, b)
		return a.v > b.v
	end)
	while #out > Config.LimitedEvent.leaderboard.rows do
		table.remove(out)
	end
	return out
end

local function publishBoard()
	local rows = readBoard()
	workspace:SetAttribute("EventTop", HttpService:JSONEncode(rows or localBoard()))
end

--[[
	Etkinlik bitince ödül: ilk `rewardTop` sıradaysa yalnızca ödül olan
	sınırlı kozmetik. Bir kez (profile.limited.awarded). `top` testler için.
	Döner: sıra (yoksa nil). DataStore'a ulaşılamazsa işaretlemiyor (sonra tekrar).
]]
function LimitedEventService.Settle(player: Player, top: { Row }?): number?
	local e = Config.LimitedEvent
	local profile = DataService.Get(player)
	if not profile or now() < e.endsAt or profile.limited.id ~= e.id or (profile.limited.awarded or 0) ~= 0 then
		return nil
	end
	local list = top or finalTop
	if not list then
		list = readBoard()
		if not list then
			return nil
		end
		finalTop = list
	end
	profile.limited.awarded = 1
	DataService.RequestSave(player)
	local rank: number? = nil
	for i, row in list :: { Row } do
		if row.u == player.UserId then
			rank = i
			break
		end
	end
	if rank and rank <= e.leaderboard.rewardTop then
		local def = Config.GetCosmetic(e.leaderboard.reward)
		if def and CosmeticService.Grant(player, def.id) then
			notify(player, string.format("You were #%d in %s! You got the LIMITED %s!", rank, e.name, def.name), false, "fanfare")
			AnnounceService.Summon(string.format("%s was #%d in %s and got the LIMITED %s!", player.DisplayName, rank, e.name,
				AnnounceService.Paint(def.name, e.color)))
		end
	end
	return rank
end

-- ─── Yıldız yağmuru (Config.LimitedEvent.shower) ────────────────────────────

type Star = { part: BasePart, position: Vector3, amount: number, super: boolean }
local stars: { Star } = {}
local SUPER_COLOR = Color3.fromRGB(255, 215, 80)

--[[
	Bir yıldızın miktarı: min..max arası (değişken ödül), `superChance` ile
	SUPERNOVA (superAmount). Son gün çarpanı dahil. `roll`/`pick` testler için.
]]
function LimitedEventService.RollStar(roll: number?, pick: number?): (number, boolean)
	local sh = Config.LimitedEvent.shower
	local mul = Config.EventCandyMul(now())
	if (roll or rng:NextNumber()) < sh.superChance then
		return sh.superAmount * mul, true
	end
	local amount = pick or rng:NextInteger(sh.min, sh.max)
	return math.clamp(amount, sh.min, sh.max) * mul, false
end

local function buildStar(folder: Instance, position: Vector3, amount: number, super: boolean): BasePart
	local e = Config.LimitedEvent
	local color = if super then SUPER_COLOR else e.color
	local star = Instance.new("Part")
	star.Name = if super then "SuperStar" else "EventStar"
	star.Shape = Enum.PartType.Ball
	star.Size = Vector3.one * (if super then 4.5 else 3)
	star.Material = Enum.Material.Neon
	star.Color = color
	star.Anchored = true
	star.CanCollide = false
	star.CanQuery = false
	star.CanTouch = false
	star.CastShadow = false
	star.Position = position
	star:SetAttribute("Amount", amount)
	star:SetAttribute("Super", super)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = if super then 26 else 16
	light.Brightness = 2
	light.Parent = star
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(if super then 0.8 else 0.5, 0)
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(2, 5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = if super then 30 else 12
	sparkle.Parent = star
	-- Uzaktan bulunabilsin (hedef açık): her zaman üstte simge
	local tag = Instance.new("BillboardGui")
	tag.Name = "StarTag"
	tag.Size = UDim2.fromOffset(if super then 64 else 40, if super then 64 else 40)
	tag.StudsOffsetWorldSpace = Vector3.new(0, if super then 4 else 3, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 450
	tag.LightInfluence = 0
	tag.Parent = star
	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Text = if super then "🌟" else e.icon
	icon.TextScaled = true
	icon.Font = Enum.Font.FredokaOne
	icon.Parent = tag
	star.Parent = folder
	return star
end

--[[ Yıldızı `player`a verir (ilk dokunan). Döner: verilen miktar. ]]
local function collectStar(player: Player, index: number): number
	local star = stars[index]
	if not star then
		return 0
	end
	table.remove(stars, index)
	star.part:Destroy()
	local e = Config.LimitedEvent
	LimitedEventService.AddCandy(player, star.amount)
	if star.super then
		notify(player, string.format("%s! +%d %s %s", e.shower.superName, star.amount, e.icon, e.currency), false, "supernova")
		AnnounceService.Summon(string.format("%s caught a %s! +%d %s", player.DisplayName,
			AnnounceService.Paint(e.shower.superName, SUPER_COLOR), star.amount, e.icon))
	else
		notify(player, string.format("+%d %s %s", star.amount, e.icon, e.currency), false, "stardust")
	end
	return star.amount
end

local function stepStars()
	if #stars == 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("SpaceGrabbed") then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and humanoid and humanoid.Health > 0) then
			continue
		end
		for i = #stars, 1, -1 do
			local star = stars[i]
			local reach = if star.super then 9 else 7
			if (star.position - root.Position).Magnitude <= reach then
				collectStar(player, i)
			end
		end
	end
end

--[[
	Yağmuru başlatır (EventService "EventShower" takvimi). Etkinlik yoksa nil.
	Önce bir avuç yıldız, sonra süre boyunca birer birer: yarış bitmesin,
	geç gelen de yakalasın. Döner: temizlik (kalan yıldızlar kayboluyor).
]]
function LimitedEventService.StartShower(): (() -> ())?
	if not Config.IsLimitedEventActive(now()) then
		return nil
	end
	local e = Config.LimitedEvent
	local sh = e.shower
	local old = workspace:FindFirstChild("EventStars")
	if old then
		old:Destroy()
	end
	table.clear(stars)
	local folder = Instance.new("Folder")
	folder.Name = "EventStars"
	folder.Parent = workspace
	local running = true
	local function drop()
		local pos = SpaceService.RandomSpacePoint(rng)
		if pos and running then
			local amount, super = LimitedEventService.RollStar()
			table.insert(stars, { part = buildStar(folder, pos, amount, super), position = pos, amount = amount, super = super })
		end
	end
	local first = math.min(6, sh.stars)
	for _ = 1, first do
		drop()
	end
	task.spawn(function()
		local rest = sh.stars - first
		local gap = if rest > 0 then (sh.duration * 0.75) / rest else 0
		for _ = 1, rest do
			task.wait(gap)
			if not running then
				return
			end
			drop()
		end
	end)
	local acc = 0
	local beat = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			stepStars()
		end
	end)
	if notifyRemote then
		notifyRemote:FireAllClients(string.format("%s %s! %s are falling into space - touch them first for %s %s (1 in %d is a %s!)",
			e.emoji, string.upper(sh.name), e.text.pickup or "Stars", e.icon, e.currency, math.floor(1 / sh.superChance + 0.5), sh.superName), false, "event")
	end
	return function()
		running = false
		beat:Disconnect()
		table.clear(stars)
		folder:Destroy()
	end
end

--[[ Testler: yağmurdaki yıldızlar ve toplama. ]]
function LimitedEventService._Stars(): { Star }
	return stars
end

function LimitedEventService._CollectStar(player: Player, index: number): number
	return collectStar(player, index)
end

-- ─── Süs: balkabakları ──────────────────────────────────────────────────────

local function pumpkin(parent: Instance, at: Vector3, size: number)
	local model = Instance.new("Model")
	model.Name = "Pumpkin"
	local function part(name: string, s: Vector3, cf: CFrame, color: Color3, neon: boolean?, sphere: boolean?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = s
		p.CFrame = cf
		p.Color = color
		p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		if sphere then
			p.Shape = Enum.PartType.Ball
		end
		p.Parent = model
		return p
	end
	local center = at + Vector3.new(0, size * 0.42, 0)
	local body = part("Body", Vector3.one * size, CFrame.new(center), Color3.fromRGB(245, 130, 30), false, true)
	body.Size = Vector3.one * size
	part("Stem", Vector3.new(size * 0.12, size * 0.25, size * 0.12), CFrame.new(center + Vector3.new(0, size * 0.55, 0)), Color3.fromRGB(80, 130, 50))
	local glow = Color3.fromRGB(255, 220, 90)
	for _, x in { -0.18, 0.18 } do
		part("Eye", Vector3.new(size * 0.16, size * 0.16, size * 0.05), CFrame.new(center + Vector3.new(x * size, size * 0.1, -size * 0.47)) * CFrame.Angles(0, 0, math.rad(45)), glow, true)
	end
	part("Mouth", Vector3.new(size * 0.4, size * 0.09, size * 0.05), CFrame.new(center + Vector3.new(0, -size * 0.12, -size * 0.47)), glow, true)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = size * 3
	light.Brightness = 1.2
	light.Parent = body
	model.PrimaryPart = body
	model.Parent = parent
end

--[[ Yıldız kristali (Starfall): kaidenin üstünde süzülen parlak elmas + ışıltı. ]]
local function starCrystal(parent: Instance, at: Vector3, size: number)
	local model = Instance.new("Model")
	model.Name = "StarCrystal"
	local e = Config.LimitedEvent
	local function part(name: string, s: Vector3, cf: CFrame, color: Color3, neon: boolean?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = s
		p.CFrame = cf
		p.Color = color
		p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		return p
	end
	part("Pedestal", Vector3.new(size * 0.9, size * 0.3, size * 0.9), CFrame.new(at + Vector3.new(0, size * 0.15, 0)), Color3.fromRGB(40, 44, 70))
	local center = at + Vector3.new(0, size * 1.3, 0)
	local core = part("Crystal", Vector3.new(size * 0.7, size * 0.7, size * 0.7), CFrame.new(center) * CFrame.Angles(math.rad(45), 0, math.rad(45)), e.color, true)
	part("Crystal2", Vector3.new(size * 0.5, size * 0.5, size * 0.5), CFrame.new(center) * CFrame.Angles(0, math.rad(45), math.rad(45)), e.color2, true)
	local light = Instance.new("PointLight")
	light.Color = e.color
	light.Range = size * 4
	light.Brightness = 1.4
	light.Parent = core
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), e.color)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.4, 0)
	sparkle.Lifetime = NumberRange.new(1, 1.8)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 6
	sparkle.Parent = core
	model.PrimaryPart = core
	model.Parent = parent
end

--[[
	Kafeteryadaki dev yıldız: lobi tabelasının önünde, tavana değmeyecek
	yükseklikte süzülüyor; ortak hedef ilerledikçe ışığı büyüyor.
]]
local function beacon(parent: Instance, params: RaycastParams)
	local base = Vector3.new(204, 42, 403)
	local up = workspace:Raycast(base, Vector3.new(0, 14, 0), params)
	local y = if up then up.Position.Y - 4 else base.Y + 6
	if y < base.Y + 1 then
		return
	end
	local model = Instance.new("Model")
	model.Name = "EventStarBeacon"
	model.Parent = parent
	starCrystal(model, Vector3.new(base.X, y - 3 * 1.3, base.Z), 3)
	local inner = model:FindFirstChild("StarCrystal")
	if inner then
		-- Kaidesi yok: havada süzülsün; parçaları dışarı al
		local pedestal = inner:FindFirstChild("Pedestal")
		if pedestal then
			pedestal:Destroy()
		end
		for _, child in inner:GetChildren() do
			child.Parent = model
		end
		inner:Destroy()
	end
end

local function buildDecor()
	if workspace:FindFirstChild("EventDecor") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "EventDecor"
	local style = Config.LimitedEvent.decor
	local s = Config.Space
	local deck = SpaceField.DeckCenter()
	local spots = {}
	-- Güvertenin dört köşesi
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(spots, deck + Vector3.new(x * (s.DeckHalfWidth - 5), 0, z * (s.DeckDepth / 2 - 5)))
		end
	end
	-- Kafeterya: sıralama panolarının önü
	for _, x in { 150, 204, 258 } do
		table.insert(spots, Vector3.new(x, 20, 398))
	end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { folder }
	for i, p in spots do
		local hit = workspace:Raycast(p + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
		local ground = if hit then hit.Position else p
		local size = if i <= 4 then 4 else 3
		if style == "pumpkins" then
			pumpkin(folder, ground, size)
		else
			starCrystal(folder, ground, size)
		end
	end
	if style == "stars" then
		beacon(folder, params)
	end
	folder.Parent = workspace
	publishCommunity()
end

local function clearDecor()
	local old = workspace:FindFirstChild("EventDecor")
	if old then
		old:Destroy()
	end
end

function LimitedEventService.Start()
	notifyRemote = Net.Get("Notify")

	-- Robux paketleri (makbuz MonetizationService'te; kaydetme orada)
	MonetizationService.RegisterGranter("stardust", function(player, product)
		return LimitedEventService.GrantPurchased(player, (product :: any).amount or 0)
	end)

	SpaceService.Delivered.Event:Connect(function(player: Player, _unitId: string, _mutationId: string?, candy: number)
		if typeof(candy) == "number" and candy > 0 then
			LimitedEventService.AddCandy(player, candy)
		end
	end)

	Net.Get("EventShop").OnServerEvent:Connect(function(player, itemId)
		if typeof(itemId) ~= "string" or #itemId > 40 then
			return
		end
		local t = os.clock()
		if t - (lastBuy[player] or 0) < 0.4 then
			return
		end
		lastBuy[player] = t
		local ok, message = LimitedEventService.Buy(player, itemId)
		-- Sınırlı eşya alındı: fanfar
		local item = Config.GetEventShopItem(itemId)
		notify(player, message, not ok, if ok and item and item.kind == "cosmetic" then "fanfare" else nil)
	end)

	workspace:SetAttribute("EventTop", "[]")
	workspace:SetAttribute("EventGlobal", 0)
	-- Sunucu açılınca ortak toplamı hemen oku (tabela 0 göstermesin)
	task.spawn(function()
		if Config.IsLimitedEventActive(now()) or now() >= Config.LimitedEvent.endsAt then
			communityTick()
		end
	end)
	local function onPlayer(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player, 30) and player.Parent then
				LimitedEventService.Publish(player)
				LimitedEventService.Daily(player)
				-- Bekleyen yol / ortak hedef ödülü (ör. kaide doluydu) girişte tekrar denenir
				LimitedEventService.CheckMilestones(player)
				LimitedEventService.CheckCommunity(player)
				LimitedEventService.Settle(player)
				if Config.IsEventFinalDay(now()) then
					local e = Config.LimitedEvent
					notify(player, string.format("%s FINAL DAY: %dX %s %s from everything!", e.emoji, e.finalDayMul, e.icon, e.currency), false)
				end
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	-- Sunucu kapanırken bekleyen ortak toplam kaybolmasın
	game:BindToClose(function()
		if goalPending > 0 then
			flushCommunity()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
		if Config.IsLimitedEventActive(now()) then
			task.spawn(writeBoard, player)
		end
	end)

	--[[
		Etkinlik başlayınca / bitince süs; gün dönünce oyundakilere bonus;
		etkinlikte dakikada bir sıralamaya yazıp ilk 10'u yayınla; bittikten
		sonra oyundakilerin ödülüne bak (DataStore o an ulaşılamadıysa).
	]]
	task.spawn(function()
		local wasActive: boolean? = nil
		local wasFinal: boolean? = nil
		local saidLastHour = false
		local tickNo = 0
		while true do
			tickNo += 1
			local active = Config.IsLimitedEventActive(now())
			if active ~= wasActive then
				-- Sunucu açıkken başladıysa herkese (açılışta sürüyorsa değil)
				if active and wasActive == false then
					local e = Config.LimitedEvent
					AnnounceService.Summon(string.format("%s %s HAS BEGUN! Steal crewmates for %s %s, open the EVENT shop!",
						e.emoji, AnnounceService.Paint(e.name, e.color), e.icon, e.currency))
				end
				wasActive = active
				if active then
					buildDecor()
				else
					clearDecor()
				end
			end
			-- Kayıp korkusu: son gün başlıyor / son saat (sunucu başına bir kez)
			if active then
				local e = Config.LimitedEvent
				local left = e.endsAt - now()
				local final = Config.IsEventFinalDay(now())
				if final and wasFinal == false then
					AnnounceService.Summon(string.format("%s FINAL DAY! Everything gives %dX %s %s for the last 24 hours!",
						e.emoji, e.finalDayMul, e.icon, e.currency))
				end
				wasFinal = final
				if left <= 3600 and not saidLastHour then
					saidLastHour = true
					AnnounceService.Summon(string.format("⏰ LAST HOUR of %s! Spend your %s %s before the shop closes forever!",
						AnnounceService.Paint(e.name, e.color), e.icon, e.currency))
				end
			end
			if active then
				for _, player in Players:GetPlayers() do
					LimitedEventService.Daily(player)
				end
				if tickNo % 2 == 0 then
					for _, player in Players:GetPlayers() do
						writeBoard(player)
					end
					publishBoard()
					task.spawn(communityTick)
				end
			elseif now() >= Config.LimitedEvent.endsAt and tickNo % 4 == 0 then
				for _, player in Players:GetPlayers() do
					LimitedEventService.Settle(player)
				end
				if tickNo % 10 == 0 then
					publishBoard()
					task.spawn(communityTick)
				end
			end
			task.wait(30)
		end
	end)
end

return LimitedEventService
