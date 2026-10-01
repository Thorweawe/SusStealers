--!strict
--[[
	Yeni oyuncunun sessiz dönemi (2026-10-01, "oyun başında çok pop-up
	çıkıyor: bu geliyor, bu var, buna tıkla — yeni oyuncu için ilk 8 dk
	kapatalım").

	Öğreticiyi henüz bitirmemiş oyuncu, oyuna girdikten (başlık ekranından
	PLAY) sonraki QUIET_SECONDS boyunca KENDİLİĞİNDEN gelen duyuruları
	görmüyor:
	  - kendi yaptığı bir işin cevabı olmayan bildirimler (unvan açıldı,
	    görev bitti, sezon kademesi, arkadaş bonusu, etkinlik duyurusu)
	  - başkalarının sunucu şansı / trol bantları
	  - nadir spawn alarmı kartı
	  - favori / bildirim izni istemleri (sonraya kalıyor)

	Görmeye devam ettikleri: hatalar, kendi tıklamasının cevabı (son birkaç
	saniyede tıkladıysa), öğretici, soygun kutlaması, kendi aldığı ürün.
	Oyun mekanikleri (olaylar, nadir doğuş) değişmiyor; yalnızca ekran sakin.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Quiet = {}

local QUIET_SECONDS = 8 * 60
-- Bu kadar saniye içinde tıklayan oyuncunun bildirimi kendi işinin cevabı sayılıyor
local RESPONSE_WINDOW = 3

-- Kendiliğinden gelen bildirim türleri (sunucunun Notify dördüncü argümanı)
local UNSOLICITED: { [string]: boolean } = {
	title = true,
	quest = true,
	reward = true,
	friend = true,
	event = true,
}

local player = Players.LocalPlayer
local startedAt: number? = nil
-- Yeni mi: TutorialStep niteliği ilk kez görülünce karar veriliyor ve sabitleniyor
local newPlayer: boolean? = nil
local lastInput = -math.huge

UserInputService.InputBegan:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Keyboard
		or t == Enum.UserInputType.Gamepad1 then
		lastInput = os.clock()
	end
end)

--[[ Başlık ekranından oyuna girildi (TitleScreen onPlay). ]]
function Quiet.Start()
	if startedAt then
		return
	end
	startedAt = os.clock()
end

local function isNew(): boolean?
	if newPlayer == nil then
		-- Öğretici bitmemiş oyuncu yeni; -1 = atlanmış (yeni sayılmıyor)
		local step = player:GetAttribute("TutorialStep")
		if typeof(step) == "number" then
			newPlayer = step >= 0 and step < #Config.Tutorial
		end
	end
	return newPlayer
end

--[[ Sessiz dönem sürüyor mu. ]]
function Quiet.Active(): boolean
	local fresh = isNew()
	if fresh == false then
		return false
	end
	-- Profil henüz gelmediyse (nil) de sessiz: yeni oyuncuya ilk saniyelerde yağmasın
	local t0 = startedAt
	if not t0 then
		-- Başlık ekranındayken de sessiz
		return true
	end
	return os.clock() - t0 < QUIET_SECONDS
end

--[[ Sessiz dönem bitene kadar kalan saniye (bitmişse 0). ]]
function Quiet.Remaining(): number
	if not Quiet.Active() then
		return 0
	end
	return QUIET_SECONDS - (os.clock() - (startedAt or os.clock()))
end

--[[ Bu bildirim gösterilsin mi. Hata ve oyuncunun kendi tıklamasının cevabı hep geçiyor. ]]
function Quiet.AllowNotify(kind: string?, isError: boolean): boolean
	if isError or not Quiet.Active() then
		return true
	end
	if os.clock() - lastInput < RESPONSE_WINDOW then
		return true
	end
	return not (kind ~= nil and UNSOLICITED[kind] == true)
end

return Quiet
