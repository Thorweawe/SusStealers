--!strict
--[[
	Ödüller: günlük giriş serisi, oynama süresi hediyeleri, indeks ödülleri.

	Tanımlar Config'te (DailyRewards, PlaytimeRewards, IndexRewards);
	burası sayaçları tutuyor, hakkı doğruluyor ve ödülü veriyor.

	═══ GÜVENLİK ══════════════════════════════════════════════════════════

	İstemciden tek remote dinleniyor: RewardClaim(tür, sıra). Hiçbir şeyi
	istemci belirlemiyor — hangi ödülün hak edildiği sunucudaki sayaçlardan
	hesaplanıyor (gün numarası, oynanan saniye, keşif listesi). İstemci
	yalnızca "şunu topluyorum" diyor; hak yoksa istek reddediliyor. Aynı
	ödül iki kez alınamıyor: toplandı bilgisi profile yazılıyor.

	═══ ZAMAN ═════════════════════════════════════════════════════════════

	Gün UTC gün numarası (Config.DayIndex). Oynama süresi sunucuda
	saniye saniye sayılıyor; istemci gösterirken kendi saatiyle ilerletiyor
	(saniyede bir paket gitmesin diye), ama hak hesabı sunucunun sayacından.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PotionService = require(script.Parent.PotionService)
local PetService = require(script.Parent.PetService)

local RewardService = {}

local NOTIFY_KIND = "reward"
RewardService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent
local stateRemote: RemoteEvent

local rng = Random.new()

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, NOTIFY_KIND)
	end
end

-- ─── Durum ──────────────────────────────────────────────────────────────────

--[[
	Gün değiştiyse oynama süresi sayacını sıfırlar. Her okuma/yazmadan
	önce çağrılıyor: gece yarısında oyunda olan oyuncunun sayacı da doğru
	güne geçsin.
]]
local function rollPlaytimeDay(profile: any)
	local today = Config.DayIndex(os.time())
	if profile.playtimeDay ~= today then
		profile.playtimeDay = today
		profile.playtimeSeconds = 0
		profile.playtimeClaimed = {}
	end
end

--[[ Bugünün günlük ödülü toplanabilir mi, toplanırsa seri kaç olur. ]]
local function dailyStatus(profile: any): (boolean, number)
	local today = Config.DayIndex(os.time())
	if profile.lastDailyDay == today then
		return false, profile.dailyStreak
	end
	-- Dün toplanmışsa seri devam, değilse baştan
	local nextStreak = if profile.lastDailyDay == today - 1 then profile.dailyStreak + 1 else 1
	return true, nextStreak
end

--[[ Seri numarasından ödül sırası: 1..7, sonra başa dönüyor. ]]
local function dailySlot(streak: number): number
	return ((math.max(1, streak) - 1) % #Config.DailyRewards) + 1
end

--[[ Nadirliğin bütün karakterleri keşfedilmiş mi. ]]
local function rarityComplete(profile: any, rarity: string): (boolean, number, number)
	local found, total = 0, 0
	for _, unit in Config.Units do
		if unit.rarity == rarity then
			total += 1
			if profile.discovered[unit.id] then
				found += 1
			end
		end
	end
	return total > 0 and found == total, found, total
end

--[[
	İndeks bonusunu ve toplanan satırları niteliklere yazar. EconomyService
	"IndexBonus"u gelir çarpanına katıyor; istemci "IndexClaimed"den hangi
	satırın toplandığını okuyor.
]]
local function publishIndex(player: Player, profile: any)
	local bonus = 0
	local claimed = {}
	for rarity, flag in profile.indexClaimed do
		if flag and Config.IndexRewards[rarity] then
			bonus += Config.IndexRewards[rarity]
			table.insert(claimed, rarity)
		end
	end
	table.sort(claimed)
	player:SetAttribute("IndexBonus", bonus)
	player:SetAttribute("IndexClaimed", table.concat(claimed, ","))
end

--[[ İstemciye durum: pencere ve hediye düğmesinin rozeti buna bakıyor. ]]
function RewardService.Push(player: Player)
	local profile = DataService.Get(player)
	if not (profile and stateRemote) then
		return
	end
	rollPlaytimeDay(profile)
	local canDaily, nextStreak = dailyStatus(profile)
	local claimed = {}
	for index in profile.playtimeClaimed do
		table.insert(claimed, tonumber(index))
	end
	stateRemote:FireClient(player, {
		daily = {
			streak = profile.dailyStreak,
			canClaim = canDaily,
			nextStreak = nextStreak,
			-- Bir sonraki UTC gün başı; istemci geri sayımı buradan
			resetAt = (Config.DayIndex(os.time()) + 1) * 86400,
		},
		playtime = {
			seconds = profile.playtimeSeconds,
			claimed = claimed,
		},
	})
end

-- ─── Ödül verme ─────────────────────────────────────────────────────────────

--[[
	Tek bir ödül tanımını oyuncuya verir. Başarılıysa okunur açıklamasını
	döndürür. İksir envanteri doluysa (PotionService reddediyorsa) ödül
	verilmemiş sayılıyor ve toplama işaretlenmiyor — oyuncu yer açıp
	tekrar alabilsin.
]]
local function give(player: Player, reward: Config.RewardDef): string?
	if reward.kind == "cash" then
		local amount = Config.GetRewardCash(reward, EconomyService.GetIncome(player))
		EconomyService.AddCash(player, amount)
		return "$" .. Config.FormatCash(amount)
	elseif reward.kind == "potion" then
		local given = 0
		for _ = 1, reward.count or 1 do
			local def = Config.RollPotion(rng)
			if PotionService.Grant(player, def.id) then
				given += 1
			end
		end
		if given == 0 then
			notify(player, "Your potion stack is full - drink one to make room", true)
			return nil
		end
		return if given == 1 then "a potion" else given .. " potions"
	elseif reward.kind == "egg" and reward.egg then
		local key = PetService.GiveEggRoll(player, reward.egg)
		if not key then
			notify(player, "Could not hatch the reward egg (pet stack full?)", true)
			return nil
		end
		local egg = Config.GetEgg(reward.egg)
		return if egg then "a free " .. egg.name else "a free egg"
	end
	return nil
end

-- ─── Kodlar ─────────────────────────────────────────────────────────────────

-- Kod denemeleri arası bekleme: kaba kuvvetle kod aramasın
local CODE_COOLDOWN = 1.5
local lastCode: { [Player]: number } = {}
local codeRemote: RemoteEvent? = nil

local function codeReply(player: Player, ok: boolean, message: string)
	if codeRemote then
		codeRemote:FireClient(player, ok, message)
	end
end

--[[
	Kod kullanır. Sonucu (başarı, mesaj) döndürür ve istemcideki kutuya da
	yollar. Ödüllerden en az biri verilirse kod kullanılmış sayılıyor;
	hiçbiri verilemezse (ör. iksir envanteri dolu) kod harcanmıyor.
]]
function RewardService.RedeemCode(player: Player, text: string, now: number?): (boolean, string)
	local t = now or os.clock()
	if t - (lastCode[player] or -math.huge) < CODE_COOLDOWN then
		codeReply(player, false, "Slow down - try again in a second")
		return false, "Slow down - try again in a second"
	end
	lastCode[player] = t

	local profile = DataService.Get(player)
	if not profile then
		return false, "Still loading, try again"
	end
	local def = Config.GetCode(text)
	if not def then
		codeReply(player, false, "Invalid code")
		return false, "Invalid code"
	end
	if def.expires and os.time() > def.expires then
		codeReply(player, false, "This code has expired")
		return false, "This code has expired"
	end
	if profile.codes[def.code] then
		codeReply(player, false, "You already used this code")
		return false, "You already used this code"
	end

	local got: { string } = {}
	for _, reward in def.rewards do
		local what = give(player, reward)
		if what then
			table.insert(got, what)
		end
	end
	if #got == 0 then
		codeReply(player, false, "Could not give the reward - make some room and try again")
		return false, "Could not give the reward"
	end
	profile.codes[def.code] = true
	DataService.RequestSave(player)
	local message = "Code redeemed: " .. table.concat(got, " + ") .. "!"
	notify(player, message, false)
	codeReply(player, true, message)
	return true, message
end

--[[ Testler için: kod bekleme süresini sıfırlar. ]]
function RewardService._ResetCodeCooldown(player: Player)
	lastCode[player] = nil
end

-- ─── Toplama ────────────────────────────────────────────────────────────────

function RewardService.ClaimDaily(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local can, nextStreak = dailyStatus(profile)
	if not can then
		notify(player, "Come back tomorrow for the next daily reward", true)
		return false
	end
	local reward = Config.DailyRewards[dailySlot(nextStreak)]
	local what = give(player, reward)
	if not what then
		return false
	end
	profile.dailyStreak = nextStreak
	profile.lastDailyDay = Config.DayIndex(os.time())
	notify(player, string.format("Day %d reward: %s!", nextStreak, what), false)
	RewardService.Push(player)
	return true
end

function RewardService.ClaimPlaytime(player: Player, index: number): boolean
	local profile = DataService.Get(player)
	local reward = Config.PlaytimeRewards[index]
	if not (profile and reward) then
		return false
	end
	rollPlaytimeDay(profile)
	local key = tostring(index)
	if profile.playtimeClaimed[key] then
		return false
	end
	if profile.playtimeSeconds < (reward.minutes or 0) * 60 then
		notify(player, "That gift is not ready yet", true)
		return false
	end
	local what = give(player, reward)
	if not what then
		return false
	end
	profile.playtimeClaimed[key] = true
	notify(player, string.format("Playtime gift: %s!", what), false)
	RewardService.Push(player)
	return true
end

function RewardService.ClaimIndex(player: Player, rarity: string): boolean
	local profile = DataService.Get(player)
	local bonus = Config.IndexRewards[rarity]
	if not (profile and bonus) then
		return false
	end
	if profile.indexClaimed[rarity] then
		return false
	end
	local complete = rarityComplete(profile, rarity)
	if not complete then
		notify(player, string.format("Discover every %s crewmate first", rarity), true)
		return false
	end
	profile.indexClaimed[rarity] = true
	publishIndex(player, profile)
	notify(player, string.format("%s index complete! +%d%% income forever", rarity, math.floor(bonus * 100 + 0.5)), false)
	return true
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function RewardService.Start()
	notifyRemote = Net.Get("Notify")
	stateRemote = Net.Get("Rewards")
	codeRemote = Net.Get("CodeResult")

	-- Kısa bir hız sınırı: düğmeye art arda basmak aynı kontrolleri
	-- saniyede onlarca kez çalıştırmasın
	local last: { [Player]: number } = {}

	Net.Get("RewardClaim").OnServerEvent:Connect(function(player, kind, arg)
		local now = os.clock()
		if now - (last[player] or 0) < 0.3 then
			return
		end
		last[player] = now

		if kind == "daily" then
			RewardService.ClaimDaily(player)
		elseif kind == "playtime" and typeof(arg) == "number" then
			RewardService.ClaimPlaytime(player, math.floor(arg))
		elseif kind == "index" and typeof(arg) == "string" then
			RewardService.ClaimIndex(player, arg)
		elseif kind == "code" and typeof(arg) == "string" and #arg <= 32 then
			RewardService.RedeemCode(player, arg)
		end
	end)

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player)
			if profile then
				rollPlaytimeDay(profile)
				publishIndex(player, profile)
				RewardService.Push(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
		lastCode[player] = nil
	end)

	--[[
		Oynama süresi sayacı. Saniyede bir herkese +1; bir hediye tam o
		saniyede hazır olduysa istemciye haber veriliyor (rozet yansın).
		Arada paket gitmiyor — istemci süreyi kendisi ilerletiyor.
	]]
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if profile then
					rollPlaytimeDay(profile)
					profile.playtimeSeconds += 1
					for _, reward in Config.PlaytimeRewards do
						if profile.playtimeSeconds == (reward.minutes or 0) * 60 then
							RewardService.Push(player)
						end
					end
				end
			end
		end
	end)
end

return RewardService
