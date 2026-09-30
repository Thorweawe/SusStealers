--!strict
--[[
	Jetpack'ler (Config.Jetpacks): Launch Bay'deki JETPACK standından
	alınıyor ve kuşanılıyor. Kuşanılan jetpack uzayda GİDERKEN uçuş hızını
	çarpıyor (boost); mürettebat taşırken kendi hızınla dönüyorsun
	(Config.GetJetpackBoost). Uçuş istemcide (SpaceFX) — sunucu yalnızca
	sahipliği ve kuşanılanı tutuyor.

	  Oyun içi para — `price` (0 = herkeste var: Starter Pack)
	  Robux         — `pass` gamepass kimliği; 0 iken satılmıyor ("SOON")

	Oyuncu nitelikleri:
	  Jetpack        — kuşanılan jetpack kimliği (herkes görsün diye)
	  JetpacksOwned  — sahip olunanlar, virgülle (arayüz için)

	Remote "JetpackAction" (client -> server): ("buy" | "equip", id) ya da
	alevler için ("flamebuy" | "flameequip", id).

	ALEVLER (2026-09-28, Config.JetFlames): jetpack'ten bağımsız kozmetik.
	Parayla, Robux pass'iyle ya da ödülle (Sezon Kartı, haftalık birinci —
	`source`) açılıyor. Nitelikler: JetFlame (takılı), FlamesOwned.
	Bedava bir şey VERMİYOR: satın alma oyuncunun KENDİ parasını
	harcıyor (fiyat Config'te, sunucuda), kuşanma yalnızca sahip olunanı.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local JetpackModel = require(Shared.JetpackModel)
local Net = require(Shared.Net)
local SpaceField = require(Shared.SpaceField)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local JetpackService = {}

JetpackService.NotifyKind = "buy"

local notifyRemote: RemoteEvent? = nil
local passCache: { [Player]: { [number]: boolean } } = {}
local lastAction: { [Player]: number } = {}

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, JetpackService.NotifyKind)
	end
end

--[[ Robux jetpack'inin pass'i var mı (oturum boyunca önbellekli). ]]
local function ownsPass(player: Player, passId: number): boolean
	if passId <= 0 then
		return false
	end
	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	if cache[passId] ~= nil then
		return cache[passId]
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if not ok then
		return false
	end
	cache[passId] = owns
	return owns
end

function JetpackService.Owns(player: Player, id: string): boolean
	local def = Config.GetJetpack(id)
	if not def then
		return false
	end
	if def.pass ~= nil then
		return ownsPass(player, def.pass)
	end
	if def.price <= 0 then
		return true
	end
	local profile = DataService.Get(player)
	return profile ~= nil and profile.jetpacks[id] == true
end

function JetpackService.OwnsFlame(player: Player, id: string): boolean
	local def = Config.GetJetFlame(id)
	if not def then
		return false
	end
	local profile = DataService.Get(player)
	if profile and profile.flames[id] == true then
		return true
	end
	if def.pass ~= nil then
		return ownsPass(player, def.pass)
	end
	return def.price <= 0 and def.source == nil
end

function JetpackService.Publish(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if not JetpackService.OwnsFlame(player, profile.flame) then
		profile.flame = "Classic"
	end
	local flames = {}
	for _, def in Config.JetFlames do
		if JetpackService.OwnsFlame(player, def.id) then
			table.insert(flames, def.id)
		end
	end
	player:SetAttribute("JetFlame", profile.flame)
	player:SetAttribute("FlamesOwned", table.concat(flames, ","))
	-- Kuşanılan artık sahip olunmuyorsa (pass iadesi vb.) başlangıca dön
	if not JetpackService.Owns(player, profile.jetpack) then
		profile.jetpack = "Starter"
	end
	local owned = {}
	for _, def in Config.Jetpacks do
		if JetpackService.Owns(player, def.id) then
			table.insert(owned, def.id)
		end
	end
	player:SetAttribute("Jetpack", profile.jetpack)
	player:SetAttribute("JetpacksOwned", table.concat(owned, ","))
end

function JetpackService.Buy(player: Player, id: string): boolean
	local def = Config.GetJetpack(id)
	local profile = DataService.Get(player)
	if not (def and profile) then
		return false
	end
	if JetpackService.Owns(player, id) then
		return JetpackService.Equip(player, id)
	end
	if def.pass ~= nil then
		-- Robux: satın alma penceresi istemcide açılıyor (PromptGamePassPurchase)
		return false
	end
	-- Geç oyun jetpackleri rebirth'le açılıyor
	if def.rebirths and profile.rebirths < def.rebirths then
		notify(player, string.format("%s unlocks at REBIRTH %d!", def.name, def.rebirths), true)
		return false
	end
	if not EconomyService.TrySpend(player, def.price) then
		notify(player, string.format("%s costs $%s", def.name, Config.FormatCash(def.price)), true)
		return false
	end
	profile.jetpacks[id] = true
	profile.jetpack = id
	JetpackService.Publish(player)
	notify(player, string.format("%s equipped! +%d%% flight speed on the way out", def.name, math.floor((def.boost - 1) * 100 + 0.5)), false)
	return true
end

function JetpackService.Equip(player: Player, id: string): boolean
	local profile = DataService.Get(player)
	if not profile or not JetpackService.Owns(player, id) then
		return false
	end
	profile.jetpack = id
	JetpackService.Publish(player)
	return true
end

function JetpackService.BuyFlame(player: Player, id: string): boolean
	local def = Config.GetJetFlame(id)
	local profile = DataService.Get(player)
	if not (def and profile) then
		return false
	end
	if JetpackService.OwnsFlame(player, id) then
		return JetpackService.EquipFlame(player, id)
	end
	if def.pass ~= nil or def.source ~= nil then
		-- Robux (istemci pencereyi açıyor) ya da ödülle açılan
		return false
	end
	if not EconomyService.TrySpend(player, def.price) then
		notify(player, string.format("%s costs $%s", def.name, Config.FormatCash(def.price)), true)
		return false
	end
	profile.flames[id] = true
	profile.flame = id
	JetpackService.Publish(player)
	notify(player, string.format("%s flame equipped!", def.name), false)
	return true
end

function JetpackService.EquipFlame(player: Player, id: string): boolean
	local profile = DataService.Get(player)
	if not profile or not JetpackService.OwnsFlame(player, id) then
		return false
	end
	profile.flame = id
	JetpackService.Publish(player)
	return true
end

-- ─── Stand (Launch Bay) ─────────────────────────────────────────────────────

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

--[[
	Güvertenin sol ön köşesinde, içeri (güverte ortasına) bakan dükkân:
	tezgâh, arkasında üç vitrin (Scout, Comet, Nova) ve parlak "JETPACKS"
	tabelası. Prompt yalnızca pencereyi açıyor (istemci, JetpackPanel).
]]
local function buildStand(): BasePart?
	local zone = workspace:FindFirstChild("SpaceZone")
	local bay = zone and zone:FindFirstChild("LaunchBay")
	if not bay then
		return nil
	end
	local old = bay:FindFirstChild("JetpackStand")
	if old then
		old:Destroy()
	end
	local s = Config.Space
	local top = s.DeckTop
	local x = s.GateX - s.DeckHalfWidth + 12
	local z = SpaceField.WallOuterZ() - s.DeckDepth + 20
	-- Güverte ortasına bakıyor (+X)
	local base = CFrame.lookAt(Vector3.new(x, top, z), Vector3.new(x + 10, top, z))

	local model = Instance.new("Model")
	model.Name = "JetpackStand"
	local METAL = Color3.fromRGB(58, 64, 82)
	local TRIM = Color3.fromRGB(255, 176, 40)
	local GLOW = Color3.fromRGB(90, 210, 255)

	part(model, "StandFloor", Vector3.new(14, 0.3, 10), base * CFrame.new(0, 0.15, 1.5), Color3.fromRGB(34, 38, 52))
	part(model, "StandStripe", Vector3.new(14.2, 0.32, 0.5), base * CFrame.new(0, 0.16, -3.3), TRIM, { Material = Enum.Material.Neon })
	-- Tezgâh
	local counter = part(model, "Counter", Vector3.new(10, 3.2, 2.2), base * CFrame.new(0, 1.9, -1.8), METAL)
	part(model, "CounterTop", Vector3.new(10.4, 0.3, 2.6), base * CFrame.new(0, 3.6, -1.8), Color3.fromRGB(220, 226, 238))
	part(model, "CounterGlow", Vector3.new(10.1, 0.25, 0.1), base * CFrame.new(0, 2.9, -2.95), GLOW, { Material = Enum.Material.Neon })
	-- Arka duvar ve tabela
	part(model, "BackWall", Vector3.new(14, 11, 0.6), base * CFrame.new(0, 5.5, 5.6), Color3.fromRGB(28, 32, 48))
	for _, side in { -1, 1 } do
		part(model, "Pillar", Vector3.new(0.8, 12, 0.8), base * CFrame.new(side * 6.8, 6, 5.2), TRIM)
	end
	local sign = part(model, "StandSign", Vector3.new(12, 2.4, 0.4), base * CFrame.new(0, 11.4, 5.0), Color3.fromRGB(20, 24, 40))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "🚀 JETPACKS"
	label.TextColor3 = Color3.fromRGB(255, 214, 90)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(40, 20, 0)
	stroke.Parent = label

	-- Vitrinler: arka duvarın önünde üç kaide, üstlerinde jetpack
	local showcase = { "Scout", "Comet", "Nova" }
	for i, id in showcase do
		local def = Config.GetJetpack(id)
		if def then
			local px = (i - 2) * 4.2
			part(model, "Plinth", Vector3.new(2.6, 1.4, 2.6), base * CFrame.new(px, 0.9, 3.4), METAL)
			part(model, "PlinthGlow", Vector3.new(2.7, 0.2, 2.7), base * CFrame.new(px, 1.65, 3.4), def.flame, { Material = Enum.Material.Neon })
			local display = JetpackModel.Build(def, base * CFrame.new(px, 4.1, 3.4) * CFrame.Angles(0, math.rad(180 - 25 * (i - 2)), 0), 1)
			display.Parent = model
			JetpackModel.AddFlames(display, def)
		end
	end

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = sign

	-- Prompt: tezgâhın önünde, pencereyi açıyor
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JetpackPrompt"
	prompt.ActionText = "Browse"
	prompt.ObjectText = "Jetpacks"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	model.PrimaryPart = counter
	model.Parent = bay
	return counter
end

function JetpackService.Start()
	notifyRemote = Net.Get("Notify")
	buildStand()

	Net.Get("JetpackAction").OnServerEvent:Connect(function(player, action, id)
		if typeof(action) ~= "string" or typeof(id) ~= "string" then
			return
		end
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.3 then
			return
		end
		lastAction[player] = now
		if action == "buy" then
			JetpackService.Buy(player, id)
		elseif action == "equip" then
			JetpackService.Equip(player, id)
		elseif action == "flamebuy" then
			JetpackService.BuyFlame(player, id)
		elseif action == "flameequip" then
			JetpackService.EquipFlame(player, id)
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, def in Config.Jetpacks do
			if def.pass == passId and passId > 0 then
				local cache = passCache[player] or {}
				passCache[player] = cache
				cache[passId] = true
				local profile = DataService.Get(player)
				if profile then
					profile.jetpack = def.id
				end
				JetpackService.Publish(player)
				notify(player, string.format("%s unlocked and equipped!", def.name), false)
			end
		end
		for _, def in Config.JetFlames do
			if def.pass == passId and passId > 0 then
				local cache = passCache[player] or {}
				passCache[player] = cache
				cache[passId] = true
				local profile = DataService.Get(player)
				if profile then
					profile.flame = def.id
				end
				JetpackService.Publish(player)
				notify(player, string.format("%s flame unlocked and equipped!", def.name), false)
			end
		end
	end)

	local function onPlayer(player: Player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player, 30)
			if profile and player.Parent then
				JetpackService.Publish(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
		lastAction[player] = nil
	end)
end

return JetpackService
