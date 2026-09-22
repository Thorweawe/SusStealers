--!strict
-- Rozetler. Oyuncuya hedef veriyor ve Roblox'un keşfet sıralamasında
-- rozet kazanma oranı da sayılıyor.
--
-- Tasarım: bu modül rozeti ne zaman vereceğini bilmiyor, sadece nasıl
-- vereceğini. Tetikleyen olaylar servislerinde kalıyor — StealService
-- çalmayı bilir, RebirthService rebirth'ü. Böylece yeni rozet eklemek
-- için tek satır yetiyor ve bu modül hiçbir servise bağımlı olmuyor.

local BadgeService_ = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local BadgeService = {}

local notifyRemote: RemoteEvent

-- oyuncu -> rozet anahtarı -> sahip mi
-- Roblox'a her seferinde sormak yavaş ve kotalı; oyun içi tetikleyiciler
-- sık çalıştığı için önbellek şart.
local owned: { [Player]: { [string]: boolean } } = {}

-- Aynı rozet için üst üste ödül isteği gitmesin
local granting: { [Player]: { [string]: boolean } } = {}

--[[ Rozet kazanma sesi diğerlerinden ayrı; nadir ve kutlama gerektiriyor. ]]
local function notify(player: Player, text: string)
	if notifyRemote then
		notifyRemote:FireClient(player, text, false, "badge")
	end
end

local function cacheOf(player: Player): { [string]: boolean }
	local cache = owned[player]
	if not cache then
		cache = {}
		owned[player] = cache
	end
	return cache
end

--[[
	Oyuncunun rozeti var mı. Sorgu başarısız olursa false önbelleklemiyoruz:
	geçici bir ağ hatası yüzünden rozeti ikinci kez vermeye çalışmak, hiç
	vermemekten iyi (Roblox zaten ikinciyi yok sayıyor).
]]
local function hasBadge(player: Player, key: string, id: number): boolean
	local cache = cacheOf(player)
	if cache[key] ~= nil then
		return cache[key]
	end

	local ok, result = pcall(function()
		return BadgeService_:UserHasBadgeAsync(player.UserId, id)
	end)

	if not ok then
		warn(string.format("[Badge] %s icin %s sorgulanamadi", player.Name, key))
		return false
	end

	cache[key] = result
	return result
end

--[[
	Rozeti verir. Zaten varsa veya id tanımlı değilse sessizce çıkar.
	Ağ çağrısı yaptığı için çağıranı bekletmiyor.
]]
function BadgeService.Award(player: Player, key: string)
	local def = Config.Badges[key]
	if not def or def.id == 0 or not player.Parent then
		return
	end

	local pending = granting[player]
	if not pending then
		pending = {}
		granting[player] = pending
	end
	if pending[key] then
		return
	end
	pending[key] = true

	task.spawn(function()
		if not hasBadge(player, key, def.id) then
			local ok, err = pcall(function()
				BadgeService_:AwardBadge(player.UserId, def.id)
			end)

			if ok then
				cacheOf(player)[key] = true
				notify(player, string.format("Badge unlocked: %s", def.name))
			else
				warn(string.format("[Badge] %s verilemedi: %s", key, tostring(err)))
			end
		end

		local stillPending = granting[player]
		if stillPending then
			stillPending[key] = nil
		end
	end)
end

--[[ Eşik rozetleri: nakit miktarına bakarak uygun olanları verir. ]]
function BadgeService.CheckCash(player: Player, cash: number)
	if cash >= Config.BadgeMillionaire then
		BadgeService.Award(player, "Millionaire")
	end
	if cash >= Config.BadgeBillionaire then
		BadgeService.Award(player, "Billionaire")
	end
end

function BadgeService.Start()
	notifyRemote = Net.Get("Notify")

	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		granting[player] = nil
	end)
end

return BadgeService
