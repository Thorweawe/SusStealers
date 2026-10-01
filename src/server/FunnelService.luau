--!strict
--[[
	Yeni oyuncunun ilk dakikalarını ölçer (AnalyticsService → Creator
	Dashboard > Analytics). 2026-09-28: "oyuncu nerede bırakıyor, tahmin
	yerine veriyle düzeltelim".

	Yalnızca YENİ oyuncular (öğreticinin ilk adımında giren) sayılıyor;
	eski oyuncunun her girişi huniyi bozardı.

	  Onboarding hunisi (Dashboard > Funnels > Onboarding):
	    1 "Joined"                 — profil yüklendi
	    k+1 "Tutorial <adım>"      — öğreticinin k. adımı bitti (Config.Tutorial)
	  Özel olaylar (Dashboard > Custom Events):
	    NewPlayerMinute  değer = dakika (1,2,3,5,7,10), alan 1 = o anki adım
	    NewPlayerLeft    değer = kaç dakika kaldı,       alan 1 = bıraktığı adım
	    TutorialSkipped  değer = kaçıncı adımda atladı

	Hunide adımların sırayla ve bir kez gönderilmesi gerekiyor; oturum
	içinde en son gönderilen adım tutuluyor, geri giden adım gönderilmiyor.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local FunnelService = {}

local CHECKPOINTS = { 1, 2, 3, 5, 7, 10 }

type Session = { joinedAt: number, logged: number, isNew: boolean, noted: { [string]: number } }
local sessions: { [Player]: Session } = {}

local function stepName(done: number): string
	if done < 0 then
		return "Skipped"
	end
	local step = Config.Tutorial[done + 1]
	return if step then step.id else "Done"
end

local function field(value: string): { [string]: any }
	return { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = value }
end

local function funnel(player: Player, step: number, name: string)
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

local function custom(player: Player, event: string, value: number, fieldValue: string?)
	pcall(function()
		if fieldValue then
			AnalyticsService:LogCustomEvent(player, event, value, field(fieldValue))
		else
			AnalyticsService:LogCustomEvent(player, event, value)
		end
	end)
end

local function currentStep(player: Player): number
	local v = player:GetAttribute("TutorialStep")
	return if typeof(v) == "number" then v else 0
end

local function onStep(player: Player)
	local s = sessions[player]
	if not s or not s.isNew then
		return
	end
	local done = currentStep(player)
	if done < 0 then
		custom(player, "TutorialSkipped", s.logged)
		s.isNew = false
		return
	end
	-- Biten her adım (atlanan varsa sırayla hepsi) bir huni adımı
	while s.logged < done and s.logged < #Config.Tutorial do
		s.logged += 1
		local step = Config.Tutorial[s.logged]
		funnel(player, s.logged + 1, "Tutorial " .. (if step then step.id else tostring(s.logged)))
	end
end

local function track(player: Player)
	-- Öğretici niteliği gelene kadar bekle (TutorialService yayınlıyor)
	local waited = 0
	while player.Parent and player:GetAttribute("TutorialStep") == nil and waited < 60 do
		task.wait(0.5)
		waited += 0.5
	end
	if not player.Parent then
		return
	end
	local isNew = currentStep(player) == 0
	local s: Session = { joinedAt = os.clock(), logged = 0, isNew = isNew, noted = {} }
	sessions[player] = s
	if not isNew then
		return
	end
	funnel(player, 1, "Joined")
	-- İlk soygunun alt adımları: uzaya çıktı mı (SpaceService diğerlerini Note ile)
	player:GetAttributeChangedSignal("InSpace"):Connect(function()
		if player:GetAttribute("InSpace") == true then
			FunnelService.Note(player, "NewPlayerSpace")
		end
	end)
	player:GetAttributeChangedSignal("TutorialStep"):Connect(function()
		onStep(player)
	end)
	onStep(player)
	for _, minute in CHECKPOINTS do
		task.delay(minute * 60, function()
			if player.Parent and sessions[player] == s then
				custom(player, "NewPlayerMinute", minute, stepName(currentStep(player)))
			end
		end)
	end
end

--[[
	Yeni oyuncunun ilk soygununun alt adımları (Custom Events), oturumda her
	olay ilk kez gerçekleştiği DAKİKAyla bir kez: NewPlayerSpace (uzaya çıktı),
	NewPlayerGrab (mürettebat kaptı), NewPlayerCaught (yakalandı). Funnel'da
	"Heist"e ulaşamayanların nerede takıldığını gösteriyor.
]]
function FunnelService.Note(player: Player, event: string)
	local s = sessions[player]
	if not s or not s.isNew or s.noted[event] then
		return
	end
	local minutes = math.floor((os.clock() - s.joinedAt) / 60 * 10 + 0.5) / 10
	s.noted[event] = minutes
	custom(player, event, minutes, stepName(currentStep(player)))
end

function FunnelService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(track, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(track, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local s = sessions[player]
		sessions[player] = nil
		if s and s.isNew then
			local minutes = math.floor((os.clock() - s.joinedAt) / 60 * 10 + 0.5) / 10
			custom(player, "NewPlayerLeft", minutes, stepName(currentStep(player)))
		end
	end)
end

return FunnelService
