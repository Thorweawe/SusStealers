--!strict
--[[
	Ekipman: lobideki Gear Shop'tan (Weapons) oyun içi parayla alınan
	kalıcı aletler. Liste ve sayılar Config.Gear'da.

	2026-09-28 (Yusuf): aletler OYUNCULARA ve gezen impostora karşı;
	canavarlara işlemiyor. Uzayda da çalışıyor ama hafif (sabotaj):

	  Slap Glove       — öndeki oyuncuyu savuruyor, kısa sersemletiyor.
	  Speed Coil       — gemide elde tutarken koşudan hızlı (uzayda işlemiyor).
	  Stun Gun         — baktığı yöndeki oyuncuyu uzaktan donduruyor.
	  Emergency Button — çevredeki herkesi savuruyor.

	Uzayda etki ~%60, taşınan mürettebat düşmüyor (canavar yetişebilir).
	Savrulma vurulanın istemcisinde (GearFX "hit"): istasyonda yere, uzayda
	dönerek sürüklenme. Gezen süs mürettebata (MapLife) istemci vuruyor.

	═══ GÜVENLİK ══════════════════════════════════════════════════════════

	GearBuy oyuncunun KENDİ parasını harcıyor; fiyat, sahiplik ve kimlik
	sunucuda. Aletlerin etkisi de sunucuda: Tool.Activated sunucuda da
	tetikleniyor, hedefi sunucu konumlardan seçiyor, bekleme sunucuda.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GearModel = require(Shared.GearModel)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MovementService = require(script.Parent.MovementService)
local RogueService = require(script.Parent.RogueService)

local GearService = {}

local NOTIFY_KIND = "gear"
GearService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent
local fxRemote: RemoteEvent

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, NOTIFY_KIND)
	end
end

local function fx(...: any)
	if fxRemote then
		fxRemote:FireAllClients(...)
	end
end

-- Son kullanım: oyuncu -> alet -> os.clock
local lastUse: { [Player]: { [string]: number } } = {}

-- ─── Yardımcılar ────────────────────────────────────────────────────────────

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

--[[ Bekleme süresi dolduysa kullanımı işaretleyip true döner. ]]
local function ready(player: Player, def: Config.GearDef): boolean
	local now = os.clock()
	local used = lastUse[player]
	if not used then
		used = {}
		lastUse[player] = used
	end
	local last = used[def.id]
	if last and now - last < (def.cooldown or 1) then
		return false
	end
	used[def.id] = now
	return true
end

--[[
	Üssünü soyan impostor menzildeyse ve vuran üssün sahibiyse impostor
	durduruluyor (prompttaki "Stop" ile aynı sonuç).
]]
local function hitRogue(player: Player, origin: Vector3, range: number): boolean
	local r = RogueService.GetCurrent()
	if not (r and r.alive and r.root) then
		return false
	end
	if (r.root.Position - origin).Magnitude > range then
		return false
	end
	local result = RogueService.TryCatch(player)
	return result == "ok"
end

-- ─── Oyuncuya vuruş ─────────────────────────────────────────────────────────

--[[
	2026-09-28 (Yusuf): aletler canavarlara DEĞİL oyunculara (ve gezen
	impostora). Uzayda oyuncular birbirini hafifçe sabote edebiliyor:
	sersemleme ve savrulma istasyondakinin ~%60'ı, taşınan mürettebat
	DÜŞMÜYOR — yalnızca canavar yetişebilir. İstasyonda eskisi gibi savurma.
	Görünüş de farklı (GearFX "hit" son argümanı: uzayda dönerek sürüklenme,
	istasyonda yere savrulma).
]]
local SPACE_HIT_MUL = 0.6
local lastHit: { [Player]: number } = {}

function GearService.IsImmune(target: Player, now: number?): boolean
	local last = lastHit[target]
	return last ~= nil and (now or os.clock()) - last < Config.GearHitImmunity
end

function GearService._MarkHit(target: Player, at: number?)
	lastHit[target] = at or os.clock()
end

local function hitPlayer(attacker: Player, target: Player, def: Config.GearDef, from: Vector3): boolean
	local character = target.Character
	if not character or GearService.IsImmune(target) then
		return false
	end
	-- Canavarın elindeki ya da güvenli güvertedeki oyuncuya olmaz
	if target:GetAttribute("SpaceGrabbed") then
		return false
	end
	lastHit[target] = os.clock()
	local inSpace = target:GetAttribute("InSpace") == true
	local mul = if inSpace then SPACE_HIT_MUL else 1
	fx("hit", character, def.id, from, (def.knock or 30) * mul, (def.stun or 1) * mul, inSpace)
	notify(target, string.format("%s hit you with a %s!", attacker.DisplayName, def.name), true)
	return true
end

--[[ Önündeki en yakın oyuncu (menzilde, bakışla açının kosinüsü > minDot). ]]
local function targetInFront(player: Player, root: BasePart, range: number, minDot: number): Player?
	local best: Player? = nil
	local bestDistance = range
	local look = root.CFrame.LookVector
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = rootOf(other)
			if otherRoot then
				local offset = otherRoot.Position - root.Position
				local distance = offset.Magnitude
				local facing = distance < 0.01 or look:Dot(offset.Unit) > minDot
				if distance <= bestDistance and facing then
					best, bestDistance = other, distance
				end
			end
		end
	end
	return best
end

-- ─── Kullanım ───────────────────────────────────────────────────────────────

--[[
	Aletin kullanımı (Tool.Activated). Bekleme süresi dolmadıysa hiçbir şey
	olmuyor; dolduysa herkese "kullandı" gidiyor (animasyon), sonra etki.
	Testler de buradan çağırıyor; kullanıldıysa true.
]]
function GearService.Use(player: Player, id: string): boolean
	local def = Config.GetGear(id)
	local root = rootOf(player)
	if not (def and root) or def.kind == "speed" then
		return false
	end
	if not ready(player, def) then
		return false
	end
	local character = player.Character :: Model
	local range = def.range or 10
	local look = root.CFrame.LookVector
	local count = 0

	if def.kind == "slap" then
		fx("use", character, id)
		local target = targetInFront(player, root, range, 0.2)
		if target and hitPlayer(player, target, def, root.Position) then
			count = 1
		else
			hitRogue(player, root.Position, range)
		end
	elseif def.kind == "stun" then
		-- Dar koni (~30°): nişan alınıyor. Işın efekti hedefe gitsin diye hedef de gidiyor
		local target = targetInFront(player, root, range, 0.85)
		fx("use", character, id, if target then target.Character else nil)
		if target and hitPlayer(player, target, def, root.Position) then
			count = 1
		else
			hitRogue(player, root.Position + look * (range / 2), range / 2)
		end
	elseif def.kind == "blast" then
		fx("use", character, id)
		for _, other in Players:GetPlayers() do
			local otherRoot = rootOf(other)
			if other ~= player and otherRoot and (otherRoot.Position - root.Position).Magnitude <= range then
				if hitPlayer(player, other, def, root.Position) then
					count += 1
				end
			end
		end
		hitRogue(player, root.Position, range)
	end
	if count > 0 then
		DataService.Bump(player, "stunned", count)
	end
	return true
end

--[[ Testler için: bekleme sürelerini sıfırlar. ]]
function GearService._ResetCooldowns(player: Player)
	lastUse[player] = nil
end

--[[
	Alet ele alınınca/bırakılınca etkisini uygular. Hız ELDEYKEN geçerli:
	çantada duran bobin bir şey yapmıyor, oyuncu seçim yapıyor.
]]
local function onEquipChanged(player: Player, def: Config.GearDef, equipped: boolean)
	if def.walkSpeed then
		player:SetAttribute("GearSpeed", if equipped then def.walkSpeed else nil)
		player:SetAttribute("GearSprint", if equipped then def.sprintSpeed else nil)
		MovementService.RefreshSpeed(player)
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
	if def.kind ~= "speed" then
		tool.Activated:Connect(function()
			GearService.Use(player, id)
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
	notify(player, def.name .. " bought! Equip it from your hotbar", false)
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
	fxRemote = Net.Get("GearFX")

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
			player:SetAttribute("GearSprint", nil)
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
		lastUse[player] = nil
		lastBuy[player] = nil
	end)

	local ok, err = pcall(GearService.WireShop)
	if not ok then
		warn("[GearService] Dukkan baglanamadi: " .. tostring(err))
	end
end

return GearService
