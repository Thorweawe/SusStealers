--!strict
--[[
	Gemideki yürüme hızı: normal / koşma (Shift, mobilde RUN) / Speed Coil.

	2026-09-28: oyuncudan çalma kalktı (StealService silindi). Ondan geriye
	yalnızca hız kaldı; burada tek yerde. Uzaydaki uçuş hızı ayrı
	(SpaceFX, "SpaceSpeed" niteliği), orada WalkSpeed kullanılmıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local MovementService = {}

local sprinting: { [Player]: boolean } = {}

local function applyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	--[[
		Ekipman hızı (Speed Coil) nitelikten okunuyor: GearService yazıyor.
		Bobin elindeyken Shift'e basınca bobinin koşu hızı ("GearSprint")
		geçerli; her durumda büyüğü. Uzayda (uçuşta ya da canavardan
		çalınanı taşırken) bobin işlemiyor: orada uzay hızı sayılıyor.
	]]
	local gearSpeed = player:GetAttribute("GearSpeed")
	local boost = if typeof(gearSpeed) == "number" then gearSpeed else 0
	local gearSprint = player:GetAttribute("GearSprint")
	local sprintBoost = if typeof(gearSprint) == "number" then gearSprint else boost
	if player:GetAttribute("InSpace") == true or player:GetAttribute("SpaceCarry") == true then
		boost, sprintBoost = 0, 0
	end

	--[[
		Sprint Boots yükseltmesi (UpgradeService "Upg_SprintBoots" yazıyor):
		gemideki bütün yürüyüş hızları, bobinli olanlar da, çarpılıyor.
		Uzayda (yukarıda boost sıfırlanan durum) yürüyüş zaten kullanılmıyor.
	]]
	local bootsLevel = player:GetAttribute("Upg_SprintBoots")
	local mul = Config.GetSprintMul(if typeof(bootsLevel) == "number" then bootsLevel else 0)

	if sprinting[player] then
		humanoid.WalkSpeed = math.max(Config.SprintWalkSpeed, sprintBoost) * mul
	else
		humanoid.WalkSpeed = math.max(Config.NormalWalkSpeed, boost) * mul
	end
end

--[[ Koşma bayrağını ayarlar (istemciden "Sprint"). ]]
function MovementService.SetSprinting(player: Player, active: boolean)
	sprinting[player] = active or nil
	applyWalkSpeed(player)
end

--[[ Hızı yeniden hesaplar (ekipman takılıp çıkarılınca, uzaya girip çıkınca). ]]
function MovementService.RefreshSpeed(player: Player)
	applyWalkSpeed(player)
end

function MovementService.Start()
	-- İstemciden gelen tek şey bir bayrak; hızı sunucu belirliyor
	Net.Get("Sprint").OnServerEvent:Connect(function(player, active)
		if typeof(active) ~= "boolean" then
			return
		end
		MovementService.SetSprinting(player, active)
	end)

	local function watchCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid")
			-- Yeniden doğan karakterde koşma bayrağı düşsün: tuşu bırakmış
			-- olabilir ve haberimiz olmaz
			sprinting[player] = nil
			applyWalkSpeed(player)
		end)
		-- Sprint Boots seviyesi değişince (satın alma, rebirth sıfırlaması)
		player:GetAttributeChangedSignal("Upg_SprintBoots"):Connect(function()
			applyWalkSpeed(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	Players.PlayerRemoving:Connect(function(player)
		sprinting[player] = nil
	end)
end

return MovementService
