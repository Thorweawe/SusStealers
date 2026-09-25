--!strict
--[[
	Oyuncu ayarları: müzik ve efekt sesi, kamera sarsıntısı (başlangıç
	ekranındaki SETTINGS) ve yumurtadan çıkınca silinecek pet kademeleri
	(yumurta panelindeki AUTO-DELETE, uygulaması PetService.TryHatch).

	Ayarlar profilde duruyor ki oyuncu her girişte yeniden kurmasın. Sunucu
	onları oyuncuya nitelik olarak yazıyor (SettingMusic, SettingSfx,
	SettingShake); istemci niteliği okuyup sesi ve sarsıntıyı ayarlıyor.
	Oyuna hiçbir etkisi yok, yalnızca oyuncunun kendi ekranı ve kulağı.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local SettingsService = {}

-- Kaydırıcı sürüklenirken art arda istek geliyor; sonuncusu yeter
local MIN_INTERVAL = 0.25
local lastAt: { [Player]: number } = {}

type Settings = { music: number, sfx: number, shake: boolean, autoDelete: { [string]: boolean }? }

local function publish(player: Player, settings: Settings)
	player:SetAttribute("SettingMusic", settings.music)
	player:SetAttribute("SettingSfx", settings.sfx)
	player:SetAttribute("SettingShake", settings.shake)
	-- Otomatik silinen kademeler virgüllü liste (nitelik tablo tutamıyor), kademe sırasıyla
	local list = {}
	for rarity, on in settings.autoDelete or {} do
		if on then
			table.insert(list, rarity)
		end
	end
	table.sort(list, function(a, b)
		return Config.Rarities[a].order < Config.Rarities[b].order
	end)
	player:SetAttribute("SettingAutoDelete", table.concat(list, ","))
end

--[[
	İstemciden gelen tabloyu doğrular ve profile yazar. Tanınmayan alan ve
	yanlış tür yok sayılıyor; sayı 0..1'e sıkıştırılıyor. Yazılan tabloyu
	döndürür, reddedilirse nil.
]]
function SettingsService.Apply(player: Player, payload: any, now: number?): Settings?
	local profile = DataService.Get(player)
	if not profile or typeof(payload) ~= "table" then
		return nil
	end
	local t = now or os.clock()
	local last = lastAt[player]
	if last and t - last < MIN_INTERVAL then
		return nil
	end
	lastAt[player] = t

	local settings = profile.settings
	for _, key in { "music", "sfx" } do
		local v = payload[key]
		if typeof(v) == "number" and v == v then
			(settings :: any)[key] = math.clamp(v, 0, 1)
		end
	end
	if typeof(payload.shake) == "boolean" then
		settings.shake = payload.shake
	end
	--[[
		Otomatik silme (yumurta panelindeki Auto-Delete): kademe -> açık mı.
		Yalnızca tanınan kademeler; tablo verilmişse tamamı yeniden yazılıyor
		(kapatılan kademe listeden çıksın).
	]]
	if typeof(payload.autoDelete) == "table" then
		local fresh: { [string]: boolean } = {}
		for rarity, on in payload.autoDelete do
			if typeof(rarity) == "string" and Config.Rarities[rarity] and on == true then
				fresh[rarity] = true
			end
		end
		settings.autoDelete = fresh
	end
	publish(player, settings)
	return settings
end

--[[ Bekleme sınırını sıfırlar (yalnızca testler). ]]
function SettingsService._Reset(player: Player)
	lastAt[player] = nil
end

local function onPlayerAdded(player: Player)
	-- Profil gelene kadar varsayılanlar: istemci boş nitelikte beklemesin
	publish(player, Config.DefaultSettings)
	local profile = DataService.WaitForProfile(player)
	if profile and player.Parent == Players then
		publish(player, profile.settings)
	end
end

function SettingsService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		lastAt[player] = nil
	end)

	Net.Get("SettingsSave").OnServerEvent:Connect(function(player, payload)
		SettingsService.Apply(player, payload)
	end)
end

return SettingsService
