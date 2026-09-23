--!strict
--[[
	Ekipman: lobideki Gear Shop'tan oyun içi parayla alınan kalıcı aletler.

	  Slap Glove   — yakındaki oyuncuya tokat. Çalınmış karakter taşıyorsa
	                 düşürüyor (karakter kurbanın üssüne dönüyor). Taşımıyorsa
	                 kısa bir sersemletme (oturma). Beklemesi var.
	  Gravity Coil — elde tutarken zıplama iki katı.
	  Speed Coil   — elde tutarken koşudan hızlı; TAŞIRKEN işlemiyor.

	═══ GÜVENLİK ══════════════════════════════════════════════════════════

	GearBuy oyuncunun KENDİ parasını harcıyor; fiyat, sahiplik ve kimlik
	sunucuda. Aletlerin etkisi de sunucuda: Tool.Equipped/Activated sunucuda
	da tetikleniyor. İstemci "tokat attım, şu oyuncuya" DİYEMİYOR — hedefi
	sunucu, karakterlerin konumundan seçiyor.

	Hız ve zıplama nitelik/insan özelliği üzerinden: hızı StealService
	hesaplıyor (taşıma ile yarıştığı için tek yerde), burası yalnızca
	"GearSpeed" niteliğini yazıp yeniden hesaplatıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GearModel = require(Shared.GearModel)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StealService = require(script.Parent.StealService)

local GearService = {}

local NOTIFY_KIND = "gear"
GearService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent

local DEFAULT_JUMP = 7.2

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, NOTIFY_KIND)
	end
end

-- Son tokat zamanı: oyuncu -> os.clock
local lastSlap: { [Player]: number } = {}

-- ─── Etkiler ────────────────────────────────────────────────────────────────

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--[[
	Tokat: menzildeki EN YAKIN oyuncu, önünde olmak şartıyla. Hedefi sunucu
	seçiyor; istemci yalnızca "tıkladım" diyor (Tool.Activated).
]]
local function slap(player: Player, def: Config.GearDef)
	local now = os.clock()
	if now - (lastSlap[player] or 0) < (def.cooldown or 5) then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end

	local best: Player? = nil
	local bestDistance = def.range or 8
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = rootOf(other)
			if otherRoot then
				local offset = otherRoot.Position - root.Position
				local distance = offset.Magnitude
				-- Önünde mi: arkasındakine tokat atılmıyor
				local facing = distance < 0.01 or root.CFrame.LookVector:Dot(offset.Unit) > 0.2
				if distance <= bestDistance and facing then
					best, bestDistance = other, distance
				end
			end
		end
	end
	if not best then
		return
	end
	lastSlap[player] = now

	local target = best :: Player
	if StealService.KnockDrop(target) then
		notify(player, string.format("You slapped %s - they dropped the loot!", target.DisplayName), false)
		notify(target, string.format("%s slapped you - you dropped the loot!", player.DisplayName), true)
	end

	-- Kısa sersemletme: oturtuyor. Yere düşürüp itmek istemci sahipli
	-- karakterde sunucudan güvenilir çalışmıyor; oturma replike oluyor.
	local character = target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = true
	end
end

--[[
	Alet ele alınınca/bırakılınca etkisini uygular. Etkiler ELDEYKEN
	geçerli: çantada duran bobin bir şey yapmıyor, oyuncu seçim yapıyor
	(tokat mı, hız mı).
]]
local function onEquipChanged(player: Player, def: Config.GearDef, equipped: boolean)
	if def.walkSpeed then
		player:SetAttribute("GearSpeed", if equipped then def.walkSpeed else nil)
		StealService.RefreshSpeed(player)
	end
	if def.jumpHeight then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.UseJumpPower = false
			humanoid.JumpHeight = if equipped then def.jumpHeight else DEFAULT_JUMP
		end
	end
end

-- ─── Aletleri verme ─────────────────────────────────────────────────────────

local function giveTool(player: Player, id: string)
	local def = Config.GetGear(id)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not (def and backpack) then
		return
	end
	-- Zaten varsa (çantada ya da elde) ikinci kopya verme
	for _, container in { backpack, player.Character } do
		if container then
			for _, item in container:GetChildren() do
				if item:IsA("Tool") and item:GetAttribute("GearId") == id then
					return
				end
			end
		end
	end

	local tool = GearModel.BuildTool(id)
	if not tool then
		return
	end
	tool.Equipped:Connect(function()
		onEquipChanged(player, def, true)
	end)
	tool.Unequipped:Connect(function()
		onEquipChanged(player, def, false)
	end)
	if id == "SlapGlove" then
		tool.Activated:Connect(function()
			slap(player, def)
		end)
	end
	tool.Parent = backpack
end

local function giveAll(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	for _, def in Config.Gear do
		if profile.gear[def.id] then
			giveTool(player, def.id)
		end
	end
end

-- ─── Satın alma ─────────────────────────────────────────────────────────────

function GearService.TryBuy(player: Player, id: string): boolean
	local def = Config.GetGear(id)
	local profile = DataService.Get(player)
	if not (def and profile) then
		return false
	end
	if profile.gear[id] then
		notify(player, "You already own the " .. def.name, true)
		return false
	end
	if not EconomyService.TrySpend(player, def.price) then
		notify(player, string.format("The %s costs $%s", def.name, Config.FormatCash(def.price)), true)
		return false
	end
	profile.gear[id] = true
	GearService.Publish(player)
	giveTool(player, id)
	notify(player, def.name .. " bought! Check your backpack", false)
	return true
end

--[[ Sahip olunanları istemciye nitelik olarak yayınlar (dükkân "OWNED" yazsın). ]]
function GearService.Publish(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local owned = {}
	for id, flag in profile.gear do
		if flag then
			table.insert(owned, id)
		end
	end
	table.sort(owned)
	player:SetAttribute("GearOwned", table.concat(owned, ","))
end

-- ─── Dükkân ─────────────────────────────────────────────────────────────────

--[[
	Lobideki dükkâna vitrin modellerini ve promptu bağlar. Mimari haritada
	(build_decor, "GearShop"); burada adı belli parçalara iş bağlanıyor —
	kuluçkahaneyle aynı düzen. Prompt sunucuda bir şey yapmıyor: istemci
	kendi tetiklemesini görüp dükkân penceresini açıyor.
]]
function GearService.WireShop(): boolean
	local decor = workspace:FindFirstChild("Decor")
	local shop = decor and decor:FindFirstChild("GearShop", true)
	if not shop then
		warn("[GearService] Decor.GearShop yok; dukkan penceresi acilamaz")
		return false
	end

	for index, def in Config.Gear do
		local plinth = shop:FindFirstChild("GearPlinth" .. index)
		if plinth and plinth:IsA("BasePart") then
			local old = shop:FindFirstChild("Display_" .. def.id)
			if old then
				old:Destroy()
			end
			local top = plinth.CFrame * CFrame.new(0, plinth.Size.Y / 2 + 0.6, 0)
			local display = GearModel.BuildDisplay(def.id, top)
			if display then
				display.Parent = shop
			end
		end
	end

	local counter = shop:FindFirstChild("GearCounter")
	if counter and counter:IsA("BasePart") then
		counter.CanQuery = true
		local old = counter:FindFirstChild("GearPrompt")
		if old then
			old:Destroy()
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GearPrompt"
		prompt.ActionText = "Open Shop"
		prompt.ObjectText = "Gear Shop"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = counter
	end
	return true
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function GearService.Start()
	notifyRemote = Net.Get("Notify")

	local lastBuy: { [Player]: number } = {}
	Net.Get("GearBuy").OnServerEvent:Connect(function(player, id)
		local now = os.clock()
		if typeof(id) ~= "string" or now - (lastBuy[player] or 0) < 0.4 then
			return
		end
		lastBuy[player] = now
		GearService.TryBuy(player, id)
	end)

	local function onPlayerAdded(player: Player)
		-- Her doğuşta çanta boşalıyor; aletler yeniden veriliyor
		player.CharacterAdded:Connect(function()
			task.defer(function()
				if DataService.Get(player) then
					giveAll(player)
				end
			end)
			player:SetAttribute("GearSpeed", nil)
		end)
		task.spawn(function()
			if DataService.WaitForProfile(player) then
				GearService.Publish(player)
				giveAll(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		lastSlap[player] = nil
		lastBuy[player] = nil
	end)

	local ok, err = pcall(GearService.WireShop)
	if not ok then
		warn("[GearService] Dukkan baglanamadi: " .. tostring(err))
	end
end

return GearService
