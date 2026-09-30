--!strict
--[[
	Sunucuya yönelik Robux ürünleri (Config.ServerProducts): SUNUCU ŞANSI ve
	TROLLER. MonetizationService makbuzu işliyor, ödülü buradaki granter
	veriyor ("serverluck", "troll").

	Sunucu şansı workspace niteliklerinde: ServerLuck (çarpan),
	ServerLuckEndsAt (sunucu saati), ServerLuckBy (alanın adı). Zarlar
	Config.GetServerLuck() ile okuyor (SpaceService doğuşları, Lucky
	Scanner, PetService yumurtaları). İstemci aynı niteliklerden HUD'daki
	sayacı çiziyor.

	Troller kısa ve zararsız; herkese "ServerFX" ile duyuruluyor (istemci
	afiş, siren, sarsıntı çiziyor):
	  Tiny  — alan hariç herkes küçülüyor (uzaydakiler hariç: uçuş kısıtları
	          boyutla bozuluyor). Süre bitince eski boy.
	  Moon  — workspace.Gravity düşüyor (herkes); süre bitince eski değer.
	  Alarm — siren ve kırmızı ekran (istemci) + 2026-09-30: gerçekten bir
	          gezen impostor çıkıyor (RogueService.Spawn; zaten biri varsa
	          yenisi yok). Eskiden yalnızca efektti ve alana hiç görünmüyordu:
	          tek başına alan oyuncu "hiçbir şey olmadı" diyordu.
	Aynı trol tekrar alınırsa süre uzuyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local AnnounceService = require(script.Parent.AnnounceService)
local MonetizationService = require(script.Parent.MonetizationService)
local RogueService = require(script.Parent.RogueService)

local ServerBoostService = {}

local fxRemote: RemoteEvent? = nil
local baseGravity = workspace.Gravity

-- Trolün bitiş zamanı (os.clock) ve küçültülen karakterler
local trollUntil: { [string]: number } = {}
local shrunk: { [Model]: boolean } = {}

local LUCK_COLOR = Color3.fromRGB(110, 240, 110)
local TROLL_COLOR = Color3.fromRGB(255, 120, 200)

local function now(): number
	return workspace:GetServerTimeNow()
end

--[[ Sunucu şansını başlatır / uzatır. Makbuz için true döner. ]]
function ServerBoostService.GrantLuck(player: Player): boolean
	local cfg = Config.ServerLuck
	local t = now()
	local current = workspace:GetAttribute("ServerLuckEndsAt")
	local from = if typeof(current) == "number" and current > t then current else t
	local ends = math.min(t + cfg.maxSeconds, from + cfg.seconds)
	workspace:SetAttribute("ServerLuck", cfg.multiplier)
	workspace:SetAttribute("ServerLuckEndsAt", ends)
	workspace:SetAttribute("ServerLuckBy", player.DisplayName)
	workspace:SetAttribute("ServerLuckById", player.UserId)
	if fxRemote then
		fxRemote:FireAllClients("luck", player.DisplayName, ends, player.UserId)
	end
	AnnounceService.Summon(string.format("%s activated %s for the whole server!",
		AnnounceService.Paint(player.DisplayName, LUCK_COLOR),
		AnnounceService.Paint(string.format("SERVER LUCK x%d", cfg.multiplier), LUCK_COLOR)))
	return true
end

local function shrinkAll(buyer: Player, scale: number)
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if p ~= buyer and character and not shrunk[character] and p:GetAttribute("InSpace") ~= true then
			local ok = pcall(function()
				character:ScaleTo(scale)
			end)
			if ok then
				shrunk[character] = true
			end
		end
	end
end

local function unshrinkAll()
	for character in shrunk do
		if character.Parent then
			pcall(function()
				character:ScaleTo(1)
			end)
		end
	end
	table.clear(shrunk)
end

--[[ Trol uygular. Bilinmeyen tür false (makbuz işlenmez). ]]
function ServerBoostService.Troll(player: Player, kind: string): boolean
	local cfg = Config.Trolls[kind]
	if not cfg then
		return false
	end
	trollUntil[kind] = math.max(trollUntil[kind] or 0, os.clock()) + cfg.seconds
	if kind == "Tiny" then
		shrinkAll(player, cfg.scale or 0.5)
	elseif kind == "Moon" then
		workspace.Gravity = cfg.gravity or 50
	elseif kind == "Alarm" then
		-- Alarmın sebebi: bir impostor gerçekten çıkıyor (yol arama bekletebilir)
		-- Çıkış vent'i rastgele; oradan yol bulunamazsa Spawn false dönüyor: birkaç kez dene
		task.spawn(function()
			for _ = 1, 6 do
				if RogueService.GetCurrent() then
					return
				end
				local ok, spawned = pcall(RogueService.Spawn)
				if ok and spawned then
					return
				end
				task.wait(1)
			end
			warn("[ServerBoost] Impostor Alarm: impostor çıkarılamadı (dolu kaide / yol yok)")
		end)
	end
	if fxRemote then
		fxRemote:FireAllClients("troll", kind, player.DisplayName, cfg.seconds, player.UserId)
	end
	AnnounceService.Summon(string.format("%s used %s!",
		AnnounceService.Paint(player.DisplayName, TROLL_COLOR),
		AnnounceService.Paint(string.upper(cfg.name), TROLL_COLOR)))
	return true
end

--[[ Süresi dolanları geri alır (döngü ve testler çağırıyor). ]]
function ServerBoostService.Expire(force: boolean?)
	local t = os.clock()
	for kind, untilAt in trollUntil do
		if force or t >= untilAt then
			trollUntil[kind] = nil
			if kind == "Tiny" then
				unshrinkAll()
			elseif kind == "Moon" then
				workspace.Gravity = baseGravity
			end
		end
	end
	local ends = workspace:GetAttribute("ServerLuckEndsAt")
	if typeof(ends) == "number" and (force or ends <= now()) then
		workspace:SetAttribute("ServerLuck", nil)
		workspace:SetAttribute("ServerLuckEndsAt", nil)
		workspace:SetAttribute("ServerLuckBy", nil)
		workspace:SetAttribute("ServerLuckById", nil)
	end
end

function ServerBoostService.Start()
	fxRemote = Net.Get("ServerFX")
	MonetizationService.RegisterGranter("serverluck", function(player)
		return ServerBoostService.GrantLuck(player)
	end)
	MonetizationService.RegisterGranter("troll", function(player, def)
		return ServerBoostService.Troll(player, (def :: any).troll or "")
	end)
	-- Küçükken ölen / yeniden doğan oyuncunun eski karakteri listeden düşsün
	Players.PlayerRemoving:Connect(function(p)
		if p.Character then
			shrunk[p.Character] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			ServerBoostService.Expire(false)
		end
	end)
end

return ServerBoostService
