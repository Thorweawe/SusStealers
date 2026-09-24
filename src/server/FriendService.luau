--!strict
--[[
	Arkadaş bonusu: aynı sunucudaki her Roblox arkadaşı için küçük gelir
	bonusu (Config.GetFriendBonus). Amaç oyuncunun arkadaşını çağırması;
	davet düğmesi istemcide (Topbar), bonus burada.

	═══ NEDEN NİTELİK ══════════════════════════════════════════════════════

	Bonus oyuncuya "FriendBonus" niteliği olarak yazılıyor, EconomyService
	onu okuyor — pet ve indeks bonusuyla aynı yol. EconomyService bu
	servisi require etmiyor, bağımlılık tek yönlü. İstemci de aynı niteliği
	okuyup nakit hapında gösteriyor.

	═══ ARKADAŞLIK SORGUSU ═════════════════════════════════════════════════

	Player:IsFriendsWith ağ çağrısı yapıyor (yield). Her çift yalnızca BİR
	kez, oyuncu girdiğinde soruluyor ve sonuç önbellekte; arkadaşlık
	simetrik olduğu için iki yön tek sorgu. Sorgu başarısız olursa çift
	arkadaş sayılmıyor — bonus kaçırmak, yanlış bonus vermekten iyi.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local FriendService = {}

local NOTIFY_KIND = "friend"

-- Dışa açık: test her servisin türünün Config.NotifyCues'ta sesi olduğuna bakıyor
FriendService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent

-- friends[a][b] = true: a ile b arkadaş ve ikisi de sunucuda
local friends: { [Player]: { [Player]: boolean } } = {}

local function notify(player: Player, text: string)
	if notifyRemote then
		notifyRemote:FireClient(player, text, false, NOTIFY_KIND)
	end
end

local function countFriends(player: Player): number
	local count = 0
	for other in friends[player] or {} do
		if other.Parent == Players then
			count += 1
		end
	end
	return count
end

--[[ Oyuncunun niteliklerini sunucudaki arkadaş sayısına göre yazar. ]]
local function publish(player: Player)
	local count = countFriends(player)
	player:SetAttribute("FriendsHere", count)
	player:SetAttribute("FriendBonus", Config.GetFriendBonus(count))
end

local function link(a: Player, b: Player)
	friends[a] = friends[a] or {}
	friends[b] = friends[b] or {}
	friends[a][b] = true
	friends[b][a] = true
end

local function bonusText(player: Player): string
	return string.format("+%d%% income", math.floor(Config.GetFriendBonus(countFriends(player)) * 100 + 0.5))
end

local function onPlayerAdded(player: Player)
	friends[player] = friends[player] or {}
	publish(player)

	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local ok, isFriend = pcall(function()
			return player:IsFriendsWith(other.UserId)
		end)
		-- Sorgu sürerken biri çıktıysa bağlama
		if ok and isFriend and player.Parent == Players and other.Parent == Players then
			link(player, other)
			publish(player)
			publish(other)
			notify(other, string.format("Your friend %s joined! Friend bonus: %s", player.DisplayName, bonusText(other)))
		end
	end

	if countFriends(player) > 0 then
		notify(player, string.format("Playing with friends! Friend bonus: %s", bonusText(player)))
	end
end

local function onPlayerRemoving(player: Player)
	local list = friends[player]
	friends[player] = nil
	if not list then
		return
	end
	for other in list do
		local theirs = friends[other]
		if theirs then
			theirs[player] = nil
			publish(other)
		end
	end
end

--[[ TEST: oyuncunun bonus niteliğini gerçek arkadaş sayısından yeniden yazar. ]]
function FriendService._Publish(player: Player)
	publish(player)
end

function FriendService.GetFriendCount(player: Player): number
	return countFriends(player)
end

function FriendService.Start()
	notifyRemote = Net.Get("Notify")

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return FriendService
