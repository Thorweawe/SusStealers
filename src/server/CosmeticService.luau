--!strict
--[[
	Kozmetikler: şapka ve iz (Config.Cosmetics). Oyun içi parayla alınıyor,
	kalıcı; güç vermiyor, gösteriş veriyor.

	═══ GÜVENLİK ══════════════════════════════════════════════════════════

	Tek remote: "CosmeticAction"(action, id). action "buy" | "equip" |
	"unequip". Hiçbiri bedava bir şey VERMİYOR: satın alma oyuncunun KENDİ
	parasını harcıyor (fiyat sunucuda), takmak yalnızca sahip olunanı
	takıyor. Kimlik Config'te aranıyor, tanınmayan reddediliyor.

	═══ GÖRÜNÜŞ ═══════════════════════════════════════════════════════════

	Şapka ve iz SUNUCUDA karaktere takılıyor ki herkes görsün. Model
	CosmeticModel'den (mağazadaki önizlemeyle aynı kod). Şapka takılıyken
	oyuncunun kendi Roblox şapkaları (Accessory, tür Hat) gizleniyor; iki
	şapka üst üste binmesin.

	İstemciye nitelikler: "CosmeticsOwned" (virgüllü liste), "HatId",
	"TrailId" — mağaza penceresi bunlardan çiziliyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local CosmeticModel = require(Shared.CosmeticModel)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local CosmeticService = {}

local NOTIFY_KIND = "cosmetic"
CosmeticService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent
local lastAction: { [Player]: number } = {}
local ACTION_DEBOUNCE = 0.25

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, NOTIFY_KIND)
	end
end

-- ─── Görünüş ────────────────────────────────────────────────────────────────

local function setAvatarHatsHidden(character: Model, hidden: boolean)
	for _, acc in character:GetChildren() do
		if acc:IsA("Accessory") and acc.AccessoryType == Enum.AccessoryType.Hat then
			local handle = acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				if hidden then
					if handle:GetAttribute("CosmeticHidden") == nil then
						handle:SetAttribute("CosmeticHidden", handle.Transparency)
					end
					handle.Transparency = 1
				else
					local original = handle:GetAttribute("CosmeticHidden")
					if typeof(original) == "number" then
						handle.Transparency = original
					end
					handle:SetAttribute("CosmeticHidden", nil)
				end
			end
		end
	end
end

--[[ Profildeki şapka ve izi karaktere uygular (öncekileri kaldırarak). ]]
function CosmeticService.Apply(player: Player)
	local profile = DataService.Get(player)
	local character = player.Character
	if not (profile and character) then
		return
	end

	local old = character:FindFirstChild("CosmeticHat")
	if old then
		old:Destroy()
	end
	local head = character:FindFirstChild("Head")
	if profile.hat ~= "" and head and head:IsA("BasePart") then
		local hat = CosmeticModel.BuildHat(profile.hat)
		local base = hat and hat.PrimaryPart
		if hat and base then
			--[[
				Modelin y=0'ı kafanın üst yüzüne. Model tasarım koordinatında
				kuruldu (orijin = kafa tepesi); pivot Base'in kendisi, o yüzden
				Base'in tasarımdaki yeri de hesaba katılıyor — yoksa şapka Base'in
				yüksekliği kadar kafaya gömülüyordu.
			]]
			-- +0.15: avatar saçı kafanın üstüne taşıyor, şapka saçın içinde kalmasın
			local top = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.15, 0)
			hat:PivotTo(top * base.CFrame)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = base
			weld.Parent = base
			hat.Parent = character
		end
	end
	setAvatarHatsHidden(character, profile.hat ~= "")

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		CosmeticModel.RemoveTrail(root)
		if profile.trail ~= "" then
			CosmeticModel.ApplyTrail(root, profile.trail)
		end
	end
end

--[[ İstemcinin mağaza penceresi için nitelikleri yazar. ]]
function CosmeticService.Publish(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local owned = {}
	for id in profile.cosmetics do
		table.insert(owned, id)
	end
	table.sort(owned)
	player:SetAttribute("CosmeticsOwned", table.concat(owned, ","))
	player:SetAttribute("HatId", profile.hat)
	player:SetAttribute("TrailId", profile.trail)
end

-- ─── İşlemler ───────────────────────────────────────────────────────────────

--[[ Satın alır. Parası yoksa, zaten sahipse ya da kimlik bilinmiyorsa false. ]]
function CosmeticService.TryBuy(player: Player, id: string): boolean
	local def = Config.GetCosmetic(id)
	local profile = DataService.Get(player)
	if not (def and profile) then
		return false
	end
	if profile.cosmetics[id] then
		return false
	end
	if not EconomyService.TrySpend(player, def.price) then
		notify(player, string.format("You need $%s for %s", Config.FormatCash(def.price), def.name), true)
		return false
	end
	profile.cosmetics[id] = true
	-- Alınan hemen takılıyor: oyuncu parasını verdiği şeyi görmek istiyor
	;(profile :: any)[def.kind] = id
	CosmeticService.Apply(player)
	CosmeticService.Publish(player)
	DataService.RequestSave(player)
	notify(player, string.format("%s unlocked!", def.name), false)
	return true
end

--[[ Takar (sahip olunanı) ya da `id` boşsa o türdeki takılıyı çıkarır. ]]
function CosmeticService.Equip(player: Player, kind: string, id: string): boolean
	local profile = DataService.Get(player)
	if not profile or (kind ~= "hat" and kind ~= "trail") then
		return false
	end
	if id ~= "" then
		local def = Config.GetCosmetic(id)
		if not def or def.kind ~= kind or not profile.cosmetics[id] then
			return false
		end
	end
	;(profile :: any)[kind] = id
	CosmeticService.Apply(player)
	CosmeticService.Publish(player)
	return true
end

local function onAction(player: Player, action: any, id: any)
	if typeof(action) ~= "string" or typeof(id) ~= "string" or #id > 40 then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < ACTION_DEBOUNCE then
		return
	end
	lastAction[player] = now

	if action == "buy" then
		CosmeticService.TryBuy(player, id)
	elseif action == "equip" then
		local def = Config.GetCosmetic(id)
		if def then
			CosmeticService.Equip(player, def.kind, id)
		end
	elseif action == "unequip" then
		-- Burada id türün adı: "hat" | "trail"
		CosmeticService.Equip(player, id, "")
	end
end

function CosmeticService.Start()
	notifyRemote = Net.Get("Notify")
	Net.Get("CosmeticAction").OnServerEvent:Connect(onAction)

	local function onPlayer(player: Player)
		task.spawn(function()
			if not DataService.WaitForProfile(player) then
				return
			end
			CosmeticService.Publish(player)
			if player.Character then
				CosmeticService.Apply(player)
			end
		end)
		player.CharacterAdded:Connect(function(character)
			-- Aksesuarlar karakterle birlikte yükleniyor; bir an bekle ki
			-- gizlenecek şapkalar yerinde olsun
			character:WaitForChild("Head", 10)
			task.wait(0.5)
			CosmeticService.Apply(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return CosmeticService
