--!strict
--[[
	Arka planda önden yükleme (2026-10-03, Batur: "birçok şey geç yükleniyor").

	Oyuncu ana ekrandayken (TitleScreen) arayüz görselleri (UiArt), parçacık
	dokuları (Config.Vfx) ve ReplicatedStorage'daki 3B şablonlar (crewmate,
	canavar, pet, savunma ağları...) ContentProvider'a küçük partiler hâlinde
	veriliyor. Eskiden ilk açılan pencere boş kart, ilk görülen canavar
	parça modeli olarak geliyordu; yükleme o an başlıyordu.

	Partiler arasında kısa bekleme var: ağı ve ana iş parçacığını boğmasın.
	Önceliği yüksek olanlar (pencere kiti, ikonlar) önce.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local UiArt = require(script.Parent.UiArt)

local AssetPreload = {}

local BATCH = 40

-- Kimlik (sayı ya da "rbxassetid://...") -> içerik dizesi
local function asContent(v: any): string?
	if typeof(v) == "number" and v > 0 then
		return "rbxassetid://" .. tostring(math.floor(v))
	elseif typeof(v) == "string" and string.find(v, "^rbxasset") then
		return v
	end
	return nil
end

local function collect(t: any, out: { string }, seen: { [string]: boolean }, depth: number)
	if depth > 4 or typeof(t) ~= "table" then
		return
	end
	for _, v in t do
		local c = asContent(v)
		if c then
			if not seen[c] then
				seen[c] = true
				table.insert(out, c)
			end
		elseif typeof(v) == "table" then
			collect(v, out, seen, depth + 1)
		end
	end
end

-- 3B şablon klasörleri (yoksa atlanıyor)
local MESH_FOLDERS = {
	"UnitMeshes", "MonsterMeshes", "PetMeshes", "DefenseMeshes", "StationMeshes",
	"HatMeshes", "CosmeticMeshes", "JetpackMeshes", "EventMeshes",
}

local started = false

function AssetPreload.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local list: { any } = {}
		local seen: { [string]: boolean } = {}
		-- Önce arayüz: pencere kiti, ana ekran, ikonlar, dokular
		collect(UiArt, list, seen, 0)
		collect((Config :: any).Vfx, list, seen, 0)
		-- Sonra 3B şablonlar: MeshPart'lar ağını ve dokusunu birlikte yüklüyor
		for _, name in MESH_FOLDERS do
			local folder = ReplicatedStorage:FindFirstChild(name)
			if folder then
				for _, d in folder:GetDescendants() do
					if d:IsA("MeshPart") or d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
						table.insert(list, d)
					end
				end
			end
		end
		for i = 1, #list, BATCH do
			local batch = table.move(list, i, math.min(i + BATCH - 1, #list), 1, {})
			pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)
			task.wait(0.05)
		end
	end)
end

return AssetPreload
