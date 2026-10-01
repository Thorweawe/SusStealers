--!strict
-- Sunucu açılışı. Servis sırası önemli:
-- Net remote'ları yaratır, PlotService dünyayı kurar, diğerleri ona bağlanır.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
require(Shared.Net)

local DataService = require(script.DataService)
local BadgeService = require(script.BadgeService)
local MonetizationService = require(script.MonetizationService)
local AnnounceService = require(script.AnnounceService)
local PlotService = require(script.PlotService)
local EconomyService = require(script.EconomyService)
local MovementService = require(script.MovementService)
local SellService = require(script.SellService)
local RebirthService = require(script.RebirthService)
local UpgradeService = require(script.UpgradeService)
local SpinService = require(script.SpinService)
local TitleService = require(script.TitleService)
local TutorialService = require(script.TutorialService)
local FloorService = require(script.FloorService)
local PotionService = require(script.PotionService)
local QuestService = require(script.QuestService)
local PetService = require(script.PetService)
local RewardService = require(script.RewardService)
local GearService = require(script.GearService)
local GlobalBoardService = require(script.GlobalBoardService)
local MinigameService = require(script.MinigameService)
local TaskService = require(script.TaskService)
local CosmeticService = require(script.CosmeticService)
local FriendService = require(script.FriendService)
local VentService = require(script.VentService)
local EventService = require(script.EventService)
local RogueService = require(script.RogueService)
local AdminMapService = require(script.AdminMapService)
local SettingsService = require(script.SettingsService)
local SpaceService = require(script.SpaceService)
local SpaceBonusService = require(script.SpaceBonusService)
local CapsuleService = require(script.CapsuleService)
local JetpackService = require(script.JetpackService)
local WeeklyService = require(script.WeeklyService)
local SeasonService = require(script.SeasonService)
local ServerBoostService = require(script.ServerBoostService)
local FunnelService = require(script.FunnelService)
local ReferralService = require(script.ReferralService)
local NotifyService = require(script.NotifyService)
local LobbyBoardService = require(script.LobbyBoardService)
local AdminService = require(script.AdminService)
local SoftShutdown = require(script.SoftShutdown)
local LimitedEventService = require(script.LimitedEventService)
local DefenseService = require(script.DefenseService)

--[[
	Yeniden başlatmanın geçici durağı (SoftShutdown): oyunun hiçbir servisi
	başlamıyor — profil yüklenmiyor, üs verilmiyor; oyuncu birkaç saniye
	sonra yeni sürümün sunucusuna geri ışınlanıyor.
]]
if SoftShutdown.IsTemporary() then
	SoftShutdown.RunTemporary()
	return
end

local started = os.clock()

-- DataService önce: PlayerRemoving'e ilk o bağlanmalı ki oyuncu çıkarken
-- kayıt, üs boşaltılmadan önce alınsın.
DataService.Start()
BadgeService.Start()
MonetizationService.Start()
AnnounceService.Start()
PlotService.Start()
EconomyService.Start()
MovementService.Start()
SellService.Start()
RebirthService.Start()
-- RebirthService'ten sonra: ped rebirth sayısına bakıyor
FloorService.Start()
UpgradeService.Start()
SpinService.Start()
TitleService.Start()
-- En sonda: okudukları her sayaç (üs, gelir, yükseltme, çark) o ana kadar
-- kurulmuş oluyor, ilk yayın da doğru durumu gösteriyor.
TutorialService.Start()
-- PotionService, QuestService'ten önce: günlük bonus envantere iksir koyuyor
PotionService.Start()
QuestService.Start()
PetService.Start()
RewardService.Start()
GearService.Start()
GlobalBoardService.Start()
MinigameService.Start()
TaskService.Start()
CosmeticService.Start()
FriendService.Start()
VentService.Start()
-- En sonda: Economy, Steal ve Announce hazır olmalı
EventService.Start()
-- Olay ve vent servislerine bakıyor: onlardan sonra
RogueService.Start()
AdminMapService.Start()
SettingsService.Start()
-- Uzay soygunu: Launch Bay, gezegenler, canavarlar (konveyörün yerine; "conveyor"/"lucky" ürünleri de burada)
SpaceService.Start()
-- Gezegen yolundaki halkalar, yıldız tozu, sandıklar, asteroitler, pano (SpaceService'ten sonra)
SpaceBonusService.Start()
-- Üslerdeki uzay kapsülleri: antrenman ve yükseltme konsolu
CapsuleService.Start()
-- Launch Bay'deki jetpack standı (SpaceService güverteyi kurduktan sonra)
JetpackService.Start()
-- Gezegen savunması: Navigasyon'daki PILOT istemi, gezegen yüzeyleri, dalgalar
DefenseService.Start()
WeeklyService.Start()
SeasonService.Start()
-- Robux: sunucu şansı ve troller (MonetizationService granter'ları)
ServerBoostService.Start()
-- Yeni oyuncunun ilk dakikaları (AnalyticsService hunisi)
FunnelService.Start()
-- Geri getirme: davet ödülü, oyun dışı bildirim, lobi tabelası (2026-09-29)
ReferralService.Start()
NotifyService.Start()
LobbyBoardService.Start()
-- Sınırlı etkinlik: şeker, dükkân, süs (Config.LimitedEvent; SpaceService'ten sonra)
LimitedEventService.Start()
-- Geliştirici konsolu komutları (ServerStorage.AdminCommand)
AdminService.Start()
-- "Restart servers": 10 sn geri sayım, sonra oyuncular yeni sürüme otomatik taşınıyor
SoftShutdown.Start()

print(string.format("[SusStealers] Server ready (%.0f ms)", (os.clock() - started) * 1000))
