--!strict
--[[
	Sınırlı etkinlik (2026-09-30, Config.LimitedEvent): bir haftalık, tarihe
	bağlı etkinlik ("SPOOKY SPACE"). Kurallar Config'teki başlıkta.

	  ŞEKER     — her soygunda (SpaceService.Delivered; miktar
	              Config.GetHeistCandy, istemci kartında da aynısı yazıyor)
	              ve etkinlikte her gün ilk girişte (dailyBonus)
	  HAUNTED   — gezegen doğuşlarında (SpaceService.rollSpot) etkinlik
	              mutasyonu; çalınca 3x şeker
	  DÜKKÂN    — "EventShop" remote'u (itemId): şeker sunucudaki sayaçtan,
	              fiyat/adet Config'ten, yalnızca etkinlik sürerken
	  SÜS       — etkinlikte güvertede ve kafeteryada balkabakları

	Profil: `limited` (id, candy, bought, lastDaily, earned); etkinlik
	kimliği değişince sıfırlanıyor. İstemciye nitelikler: EventCandy,
	EventBought ("id:n,id:n").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SpaceField = require(Shared.SpaceField)

local AnnounceService = require(script.Parent.AnnounceService)
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

local function now(): number
	return nowOverride or os.time()
end

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, LimitedEventService.NotifyKind)
	end
end

--[[ Profilin sayacı bu etkinliğin mi; değilse sıfırla. ]]
local function roll(profile: any)
	if profile.limited.id ~= Config.LimitedEvent.id then
		profile.limited = { id = Config.LimitedEvent.id, candy = 0, bought = {}, lastDaily = 0, earned = 0 }
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
	player:SetAttribute("EventBought", table.concat(parts, ","))
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
	LimitedEventService.Publish(player)
	DataService.RequestSave(player)
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
	LimitedEventService.AddCandy(player, Config.LimitedEvent.dailyBonus)
	notify(player, string.format("%s daily bonus: +%d %s Candy!", Config.LimitedEvent.name,
		Config.LimitedEvent.dailyBonus, Config.LimitedEvent.icon), false)
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
		return false, string.format("You need %d %s Candy", item.price, Config.LimitedEvent.icon)
	end

	local got: string? = nil
	if item.kind == "unit" then
		local name = SpaceService.GrantUnit(player, false, nil, "Haunted")
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

local function buildDecor()
	if workspace:FindFirstChild("SpookyDecor") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SpookyDecor"
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
		pumpkin(folder, ground, if i <= 4 then 4 else 3)
	end
	folder.Parent = workspace
end

local function clearDecor()
	local old = workspace:FindFirstChild("SpookyDecor")
	if old then
		old:Destroy()
	end
end

function LimitedEventService.Start()
	notifyRemote = Net.Get("Notify")

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
		notify(player, message, not ok)
	end)

	local function onPlayer(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player, 30) and player.Parent then
				LimitedEventService.Publish(player)
				LimitedEventService.Daily(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)

	-- Etkinlik başlayınca / bitince süs; gün dönünce oyundakilere bonus
	task.spawn(function()
		local wasActive: boolean? = nil
		while true do
			local active = Config.IsLimitedEventActive(now())
			if active ~= wasActive then
				wasActive = active
				if active then
					buildDecor()
				else
					clearDecor()
				end
			end
			if active then
				for _, player in Players:GetPlayers() do
					LimitedEventService.Daily(player)
				end
			end
			task.wait(30)
		end
	end)
end

return LimitedEventService
