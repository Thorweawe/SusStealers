--!strict
-- Oyuncu verisinin kalıcılığı: nakit, kaidedeki karakterler, çalma sayısı.
--
-- Tasarım: bu modül veriyi yorumlamaz. Diğer servisler kendilerine ait
-- alanları profil tablosunda doğrudan günceller (EconomyService profile.cash,
-- PlotService profile.units). DataService yalnızca yükler, kaydeder ve
-- oturum kilidini yönetir. Böylece kayıt anında başka servise çağrı yok,
-- bağımlılık tek yönlü kalıyor.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local DataService = {}

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 120
local LOCK_TIMEOUT = 180      -- kilit bu kadar saniye tazelenmezse ölü sayılır
local LOAD_RETRIES = 4

export type StoredUnit = {
	slot: number,
	unitId: string,
	mutationId: string?,
}

export type Profile = {
	version: number,
	cash: number,
	stolen: number,
	units: { StoredUnit },
}

type Lock = { owner: string, at: number }
type Record = { profile: Profile, lock: Lock? }

local store: DataStore? = nil
local storeAvailable = false

-- Studio'da her oturum ayrı sayılsın diye JobId bos ise kendimiz uretiyoruz
local SESSION_ID = if game.JobId ~= "" then game.JobId else "studio-" .. tostring(os.time())

local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}

-- ─── Varsayılan ─────────────────────────────────────────────────────────────

local function newProfile(): Profile
	return {
		version = 1,
		cash = Config.StartingCash,
		stolen = 0,
		units = {},
	}
end

--[[
	Diskten gelen tabloyu güvenli hale getirir. Eski sürüm, eksik alan veya
	bozuk veri gelirse oyuncuyu patlatmak yerine varsayılana düşer.
]]
local function sanitize(raw: any): Profile
	if typeof(raw) ~= "table" then
		return newProfile()
	end

	local profile = newProfile()

	if typeof(raw.cash) == "number" and raw.cash == raw.cash and raw.cash >= 0 then
		profile.cash = math.floor(raw.cash)
	end

	if typeof(raw.stolen) == "number" and raw.stolen >= 0 then
		profile.stolen = math.floor(raw.stolen)
	end

	if typeof(raw.units) == "table" then
		for _, entry in raw.units do
			if typeof(entry) == "table"
				and typeof(entry.slot) == "number"
				and typeof(entry.unitId) == "string"
				-- Config'ten silinmiş bir karakter kayıtta kalmış olabilir
				and Config.GetUnit(entry.unitId) ~= nil
			then
				local mutationId: string? = nil
				if typeof(entry.mutationId) == "string" and Config.GetMutation(entry.mutationId) then
					mutationId = entry.mutationId
				end

				table.insert(profile.units, {
					slot = math.floor(entry.slot),
					unitId = entry.unitId,
					mutationId = mutationId,
				})
			end
		end
	end

	return profile
end

-- ─── Kilit ──────────────────────────────────────────────────────────────────

local function lockIsForeign(lock: Lock?): boolean
	if not lock then
		return false
	end
	if lock.owner == SESSION_ID then
		return false
	end
	return (os.time() - lock.at) < LOCK_TIMEOUT
end

-- ─── Yükleme ────────────────────────────────────────────────────────────────

local function keyFor(player: Player): string
	return "player_" .. tostring(player.UserId)
end

--[[
	Profili yükler ve oturum kilidini alır. Başka bir sunucu kilidi
	tutuyorsa birkaç kez dener. Çalınabilir eşya olan bir oyunda iki
	sunucunun aynı profili yazması kopyalamaya yol açar, o yüzden
	kilit alınamazsa nil döner.
]]
local function loadProfile(player: Player): Profile?
	if not storeAvailable then
		return newProfile()
	end

	local key = keyFor(player)

	for attempt = 1, LOAD_RETRIES do
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, function(old: Record?): Record?
				local record: Record = old or { profile = newProfile() }

				if lockIsForeign(record.lock) then
					return nil -- iptal: kilit baskasinda
				end

				record.profile = sanitize(record.profile)
				record.lock = { owner = SESSION_ID, at = os.time() }
				return record
			end)
		end)

		if ok and result then
			return sanitize((result :: Record).profile)
		end

		if not ok then
			warn(string.format("[Data] %s yuklenemedi (deneme %d): %s", player.Name, attempt, tostring(result)))
		end

		if attempt < LOAD_RETRIES then
			task.wait(2 * attempt)
		end
	end

	return nil
end

-- ─── Kaydetme ───────────────────────────────────────────────────────────────

--[[ Profili diske yazar. releaseLock true ise oturum kilidini de bırakır. ]]
local function saveProfile(player: Player, releaseLock: boolean): boolean
	local profile = profiles[player]
	if not profile or not storeAvailable then
		return false
	end

	-- Yazarken profil değişebilir; anlık kopya al
	local snapshot: Profile = {
		version = profile.version,
		cash = profile.cash,
		stolen = profile.stolen,
		units = table.clone(profile.units),
	}

	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old: Record?): Record?
			local record: Record = old or {} :: any

			if lockIsForeign(record.lock) then
				return nil -- baskasinin oturumunun ustune yazma
			end

			record.profile = snapshot
			record.lock = if releaseLock then nil else { owner = SESSION_ID, at = os.time() }
			return record
		end)
	end)

	if not ok then
		warn(string.format("[Data] %s kaydedilemedi: %s", player.Name, tostring(err)))
	end
	return ok
end

-- ─── Dışa açık API ──────────────────────────────────────────────────────────

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

--[[ Profil yüklenene kadar bekler. Yükleme başarısızsa nil döner. ]]
function DataService.WaitForProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 20)

	while os.clock() < deadline do
		if profiles[player] then
			return profiles[player]
		end
		if not loading[player] and player.Parent == nil then
			return nil
		end
		task.wait(0.1)
	end

	return profiles[player]
end

function DataService.Save(player: Player): boolean
	return saveProfile(player, false)
end

--[[ DataStore kullanılabiliyor mu. Studio'da API Services kapalıysa false. ]]
function DataService.IsAvailable(): boolean
	return storeAvailable
end

-- ─── Yaşam döngüsü ──────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	loading[player] = true

	local profile = loadProfile(player)

	if player.Parent == nil then
		loading[player] = nil
		return
	end

	if not profile then
		loading[player] = nil
		player:Kick("Your data is still saving from another server. Please rejoin in a minute.")
		return
	end

	profiles[player] = profile
	loading[player] = nil
end

local function onPlayerRemoving(player: Player)
	saveProfile(player, true)
	profiles[player] = nil
	loading[player] = nil
end

function DataService.Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)

	if ok and result then
		store = result
		-- GetDataStore, API Services kapaliyken de basarili olabiliyor;
		-- gercek erisimi kucuk bir okumayla dogruluyoruz.
		local reachable = pcall(function()
			(result :: DataStore):GetAsync("__probe")
		end)
		storeAvailable = reachable
	end

	if not storeAvailable then
		warn("[Data] DataStore kapali - veriler bu oturumda kaydedilmeyecek. "
			.. "Studio'da: Game Settings > Security > Enable Studio Access to API Services")
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Periyodik kayıt: çökme durumunda kaybı sınırlar, kilidi de tazeler
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				if profiles[player] then
					saveProfile(player, false)
				end
			end
		end
	end)

	-- Sunucu kapanırken herkesi kaydet. Roblox burada 30 saniye tanıyor.
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end

		local pending = 0
		for _, player in Players:GetPlayers() do
			if profiles[player] then
				pending += 1
				task.spawn(function()
					saveProfile(player, true)
					pending -= 1
				end)
			end
		end

		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
