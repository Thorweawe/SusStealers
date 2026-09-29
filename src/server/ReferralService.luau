--!strict
--[[
	Davet ödülü (2026-09-29, Config.Referral).

	Akış:
	  1. Davet düğmesi (istemci, Topbar) daveti LaunchData "ref:<userId>" ile
	     gönderiyor. Roblox ayrıca davet/paylaşım bağlantısıyla gelene
	     GetJoinData().ReferredByPlayerId veriyor; ikisinden biri yeter.
	  2. Davetle İLK KEZ gelen (DataService.IsFirstVisit) oyuncu hoş geldin
	     hediyesini alıyor (Config.Referral.Invitee); profile referredBy yazılıyor.
	  3. Davet eden bu sunucudaysa ödülü hemen alıyor; değilse ödül
	     "Referrals_v1" DataStore'unda davet edenin anahtarına yazılıyor ve
	     bir sonraki girişinde veriliyor.

	Sınır: davet eden en fazla MaxRewards kez ödüllenir. Kendini davet
	etmek, eski oyuncuyu "davetli" saymak (ilk ziyaret değil) sayılmıyor.

	Sunucudan istemciye yalnızca Notify; istemciden gelen bir şey yok (davet
	eden kimliği Roblox'un katılma verisinden okunuyor ve yalnızca ÖDÜL
	yönünü belirliyor, kimseye bir şey aldırmıyor).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

local ReferralService = {}

ReferralService.NotifyKind = "reward"
-- Testler: gerçek DataStore'a sahte davet yazılmasın
ReferralService._NoStore = false

local notifyRemote: RemoteEvent? = nil
local store: DataStore? = nil

local function notify(player: Player, text: string)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, false, ReferralService.NotifyKind)
	end
end

local function giveAll(player: Player, list: { any }): { string }
	local got = {}
	for _, reward in list do
		local what = RewardService.Give(player, reward)
		if what then
			table.insert(got, what)
		end
	end
	return got
end

--[[ Davet edene bir davetin ödülü. Sınırdaysa false. ]]
function ReferralService.RewardInviter(inviter: Player, friendName: string): boolean
	local profile = DataService.Get(inviter)
	if not profile or profile.referrals >= Config.Referral.MaxRewards then
		return false
	end
	profile.referrals += 1
	local got = giveAll(inviter, Config.Referral.Inviter)
	DataService.RequestSave(inviter)
	notify(inviter, string.format("%s joined from your invite! %s", friendName, table.concat(got, " + ")))
	inviter:SetAttribute("Referrals", profile.referrals)
	return true
end

--[[ Katılma verisinden davet edenin kimliği (yoksa nil). Testler `data` verebilir. ]]
function ReferralService.InviterOf(player: Player, data: any?): number?
	local join = data
	if join == nil then
		local ok, result = pcall(function()
			return player:GetJoinData()
		end)
		join = if ok then result else nil
	end
	if typeof(join) ~= "table" then
		return nil
	end
	local id: number? = nil
	if typeof(join.LaunchData) == "string" then
		local text = string.match(join.LaunchData, "^ref:(%d+)$")
		id = if text then tonumber(text) else nil
	end
	if not id and typeof(join.ReferredByPlayerId) == "number" and join.ReferredByPlayerId > 0 then
		id = join.ReferredByPlayerId
	end
	if id == nil or id == player.UserId then
		return nil
	end
	return id
end

--[[
	Davetle gelen yeni oyuncuyu işler. `data` testler için (GetJoinData yerine).
	Döner: davet edenin kimliği (işlendiyse).
]]
function ReferralService.HandleJoin(player: Player, data: any?, firstVisit: boolean?): number?
	local profile = DataService.Get(player)
	if not profile or profile.referredBy ~= 0 then
		return nil
	end
	local isFirst = if firstVisit ~= nil then firstVisit else DataService.IsFirstVisit(player)
	if not isFirst then
		return nil
	end
	local inviterId = ReferralService.InviterOf(player, data)
	if not inviterId then
		return nil
	end
	profile.referredBy = inviterId
	local got = giveAll(player, Config.Referral.Invitee)
	DataService.RequestSave(player)
	notify(player, string.format("Welcome, crewmate! Your friend's invite gave you %s", table.concat(got, " + ")))

	local inviter = Players:GetPlayerByUserId(inviterId)
	if inviter and DataService.Get(inviter) then
		ReferralService.RewardInviter(inviter, player.DisplayName)
	elseif store and DataService.IsAvailable() and not ReferralService._NoStore then
		-- Davet eden oyunda değil: bir sonraki girişinde (ClaimPending)
		local name = player.DisplayName
		task.spawn(function()
			pcall(function()
				(store :: DataStore):UpdateAsync(tostring(inviterId), function(old)
					local list = if typeof(old) == "table" then old else {}
					if #list < Config.Referral.MaxRewards * 2 then
						table.insert(list, name)
					end
					return list
				end)
			end)
		end)
	end
	return inviterId
end

--[[ Oyuncu yokken gelen davetlerin ödülü (DataStore'dan, bir kez). ]]
local function claimPending(player: Player)
	if not (store and DataService.IsAvailable()) then
		return
	end
	local names: { string } = {}
	local ok = pcall(function()
		(store :: DataStore):UpdateAsync(tostring(player.UserId), function(old)
			if typeof(old) == "table" then
				for _, n in old do
					if typeof(n) == "string" then
						table.insert(names, n)
					end
				end
			end
			-- Boş liste yaz (nil dönmek güncellemeyi İPTAL ediyor, liste kalırdı)
			return {}
		end)
	end)
	if not ok then
		return
	end
	for _, n in names do
		if not ReferralService.RewardInviter(player, n) then
			break
		end
	end
end

function ReferralService.Start()
	notifyRemote = Net.Get("Notify")
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("Referrals_v1")
	end)
	store = if ok then result else nil

	local function onPlayer(player: Player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player, 30)
			if not (profile and player.Parent) then
				return
			end
			player:SetAttribute("Referrals", profile.referrals)
			ReferralService.HandleJoin(player)
			claimPending(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

return ReferralService
