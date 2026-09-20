--!strict
-- Sunucu açılışı. Servis sırası önemli:
-- Net remote'ları yaratır, PlotService dünyayı kurar, diğerleri ona bağlanır.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
require(Shared.Net)

local PlotService = require(script.PlotService)
local EconomyService = require(script.EconomyService)
local ConveyorService = require(script.ConveyorService)
local StealService = require(script.StealService)

local started = os.clock()

PlotService.Start()
EconomyService.Start()
ConveyorService.Start()
StealService.Start()

print(string.format("[SusStealers] Sunucu hazır (%.0f ms)", (os.clock() - started) * 1000))
