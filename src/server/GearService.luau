--!strict
--[[
	Ekipman: lobideki Gear Shop'tan (Weapons) oyun içi parayla alınan
	kalıcı aletler. Liste ve sayılar Config.Gear'da.

	  Slap Glove       — öndeki en yakın oyuncuya tokat: savrulup sersemliyor.
	                     Hırsızsa taşıdığını düşürüyor (kurbanın üssüne dönüyor).
	                     Üssünü soyan impostoru (RogueService) da durduruyor.
	  Speed Coil       — elde tutarken koşudan hızlı; Shift'le daha da hızlı.
	                     TAŞIRKEN işlemiyor.
	  Stun Gun         — baktığı yöndeki oyuncuyu uzaktan donduruyor; hırsız
	                     ganimeti düşürüyor.
	  Ghost Serum      — birkaç saniye görünmezlik. Bir şey taşımaya
	                     başlayınca, saldırınca ya da vurulunca bozuluyor.
	  Emergency Button — çevredeki herkes savruluyor, sersemliyor, taşıdığını
	                     düşürüyor.

	═══ GÜVENLİK ══════════════════════════════════════════════════════════

	GearBuy oyuncunun KENDİ parasını harcıyor; fiyat, sahiplik ve kimlik
	sunucuda. Aletlerin etkisi de sunucuda: Tool.Activated sunucuda da
	tetikleniyor. İstemci "şu oyuncuya vurdum" DİYEMİYOR — hedefi sunucu,
	karakterlerin konumundan seçiyor; bekleme süresi de sunucuda.

	═══ SAVRULMA NEDEN İSTEMCİDE ══════════════════════════════════════════

	Karakterin fiziği kendi istemcisinde. Sunucudan hız vermek güvenilir
	çalışmıyor (istemci bir sonraki karede eziyor). Sunucu "GearFX" ile
	HERKESE "şu karakter vuruldu" diyor; vurulanın istemcisi kendini
	savuruyor/donduruyor (GearFX.luau), diğerleri yalnızca efekti çiziyor.
	Kendini savurmamayı seçen istemci ancak kendine iyilik yapar — hile
	olarak zaten karakterini istediği yere taşıyabiliyor. Ganimetin
	düşmesi ise tamamen sunucuda (StealService.KnockDrop).

	Hız nitelik üzerinden: hızı StealService hesaplıyor (taşıma ile
	yarıştığı için tek yerde), burası "GearSpeed"/"GearSprint" yazıp
	yeniden hesaplatıyor.
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

-- Görünmezlik aşağıda; vuruş onu bitirebilsin diye önden bildiriliyor
local endCloak: (player: Player) -> ()

--[[
	Vuruş: ganimet düşüyor (sunucu), savrulma/sersemleme vurulanın
	istemcisinde. `from` savrulmanın merkezi.
]]
local function hit(attacker: Player, target: Player, def: Config.GearDef, from: Vector3)
	local character = target.Character
	if not character then
		return
	end
	-- Görünmezken vurulan görünür oluyor
	endCloak(target)
	fx("hit", character, def.id, from, def.knock or 0, def.stun or 1)
	if StealService.KnockDrop(target) then
		notify(attacker, string.format("You hit %s - they dropped the loot!", target.DisplayName), false)
		notify(target, string.format("%s hit you - you dropped the loot!", attacker.DisplayName), true)
	end
end

--[[
	Üssünü soyan impostor menzildeyse vuran üssün sahibiyse impostor
	durduruluyor (prompttaki "Stop" ile aynı sonuç). Başkası vurursa
	RogueService nedenini bildiriyor.
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

--[[
	Önündeki en yakın oyuncu: menzilde ve bakış yönüyle arasındaki açının
	kosinüsü `minDot`'tan büyük. Arkadakine vurulmuyor.
]]
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

-- ─── Görünmezlik ────────────────────────────────────────────────────────────

--[[
	Karakterin bütün görünen parçaları saydam, isim etiketi ve efektleri
	(iz, parıltı, başındaki tabelalar) kapalı; eski değerler saklanıyor ve
	aynen geri yazılıyor. Sunucuda yapılıyor ki herkeste görünmez olsun;
	oyuncunun kendi istemcisi kendini soluk görüyor (GearFX).
]]
type Cloak = { character: Model, saved: { [Instance]: any }, token: number }
local cloaks: { [Player]: Cloak } = {}
local cloakToken = 0

function endCloak(player: Player)
	local c = cloaks[player]
	if not c then
		return
	end
	cloaks[player] = nil
	for inst, value in c.saved do
		if inst.Parent then
			if inst:IsA("BasePart") or inst:IsA("Decal") then
				(inst :: any).Transparency = value
			elseif inst:IsA("Humanoid") then
				inst.DisplayDistanceType = value
			else
				(inst :: any).Enabled = value
			end
		end
	end
	player:SetAttribute("Cloaked", nil)
	fx("cloak", c.character, false)
end

--[[ Görünmezliği bitirir (süre doldu, taşımaya başladı, saldırdı, vuruldu). ]]
function GearService.EndCloak(player: Player)
	endCloak(player)
end

local function startCloak(player: Player, def: Config.GearDef)
	local character = player.Character
	if not character then
		return
	end
	endCloak(player)
	local saved: { [Instance]: any } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			saved[d] = d.Transparency
			d.Transparency = 1
		elseif d:IsA("BillboardGui") or d:IsA("Trail") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") then
			saved[d] = (d :: any).Enabled;
			(d :: any).Enabled = false
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		saved[humanoid] = humanoid.DisplayDistanceType
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	cloakToken += 1
	local token = cloakToken
	cloaks[player] = { character = character, saved = saved, token = token }
	player:SetAttribute("Cloaked", true)
	fx("cloak", character, true)

	-- Süre doluncaya ya da bir şey taşıyana kadar
	task.spawn(function()
		local ends = os.clock() + (def.duration or 8)
		while os.clock() < ends do
			task.wait(0.2)
			local c = cloaks[player]
			if not c or c.token ~= token then
				return
			end
			if StealService.IsCarrying(player) or player.Character ~= character then
				break
			end
		end
		local c = cloaks[player]
		if c and c.token == token then
			endCloak(player)
		end
	end)
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
	if def.kind == "cloak" and StealService.IsCarrying(player) then
		notify(player, "You can't turn invisible while carrying", true)
		return false
	end
	if not ready(player, def) then
		return false
	end
	local character = player.Character :: Model
	local range = def.range or 10

	-- Görünmezken saldıran görünür oluyor
	if def.kind ~= "cloak" then
		endCloak(player)
	end

	if def.kind == "slap" then
		fx("use", character, id)
		local target = targetInFront(player, root, range, 0.2)
		if target then
			hit(player, target, def, root.Position)
		else
			hitRogue(player, root.Position, range)
		end
	elseif def.kind == "stun" then
		-- Dar koni (~25°): nişan alınıyor. Işın efekti hedefe gitsin diye hedef de gidiyor
		local target = targetInFront(player, root, range, 0.9)
		fx("use", character, id, if target then target.Character else nil)
		if target then
			hit(player, target, def, root.Position)
		else
			hitRogue(player, root.Position + root.CFrame.LookVector * (range / 2), range / 2)
		end
	elseif def.kind == "cloak" then
		fx("use", character, id)
		startCloak(player, def)
	elseif def.kind == "blast" then
		fx("use", character, id)
		local count = 0
		for _, other in Players:GetPlayers() do
			local otherRoot = rootOf(other)
			if other ~= player and otherRoot and (otherRoot.Position - root.Position).Magnitude <= range then
				hit(player, other, def, root.Position)
				count += 1
			end
		end
		if not hitRogue(player, root.Position, range) and count == 0 then
			notify(player, "Nobody was close enough", false)
		end
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
		StealService.RefreshSpeed(player)
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
			player:SetAttribute("Cloaked", nil)
			cloaks[player] = nil
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
		cloaks[player] = nil
	end)

	local ok, err = pcall(GearService.WireShop)
	if not ok then
		warn("[GearService] Dukkan baglanamadi: " .. tostring(err))
	end
end

return GearService
