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
local ConveyorService = require(script.ConveyorService)
local StealService = require(script.StealService)
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

local started = os.clock()

-- DataService önce: PlayerRemoving'e ilk o bağlanmalı ki oyuncu çıkarken
-- kayıt, üs boşaltılmadan önce alınsın.
DataService.Start()
BadgeService.Start()
MonetizationService.Start()
AnnounceService.Start()
PlotService.Start()
EconomyService.Start()
ConveyorService.Start()
StealService.Start()
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

print(string.format("[SusStealers] Server ready (%.0f ms)", (os.clock() - started) * 1000))
