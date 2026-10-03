--!strict
--[[
	Oyuncu üslerinin (workspace.Plots) görünüşü — 2026-10-03, "bu base'ler de
	değişsin". Tamamen İSTEMCİ ve tamamen görsel: sunucu (PlotService) üssü
	düz parçalardan kuruyor; burada üstlerine giydiriyoruz, çarpışmaya ve
	oyun mantığına dokunmuyoruz.

	  • Kaideler ("Podium" kutuları): yerel olarak gizlenip yerine 3D kürsü
	    (ReplicatedStorage.StationMeshes.Podium, ChatGPT → TRELLIS) geliyor.
	    Sunucunun kaide saydamlığı (kilitli kat 1, kilitli bonus 0.6) kürsüye
	    aynen yansıyor.
	  • Yürünen düz yüzeyler (zemin, güverte, plakalar, basamaklar) istasyonla
	    aynı sci-fi panel dokusunu (MaterialService.StationFloor), dik
	    duvarlar gövde panelini (StationWall) alıyor. Parça rengiyle boyanıyor,
	    yani odanın rengi korunuyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialService = game:GetService("MaterialService")

local BaseStyle = {}

export type Handle = {
	Update: () -> (),
}

local FLOOR_VARIANT = "StationFloor"
local WALL_VARIANT = "StationWall"

-- Neon/cam/metal parçalar (lambalar, şeritler) kendi malzemesinde kalıyor
local function texture(p: BasePart)
	if not p:IsA("Part") or p.Material ~= Enum.Material.SmoothPlastic or p.Shape ~= Enum.PartType.Block then
		return
	end
	if p.Name == "Podium" or p.Transparency >= 1 then
		return
	end
	local s = p.Size
	if s.Y <= 1.5 and s.X * s.Z >= 16 then
		p.MaterialVariant = FLOOR_VARIANT
	elseif s.Y >= 4 and math.min(s.X, s.Z) <= 2.5 and math.max(s.X, s.Z) >= 4 then
		p.MaterialVariant = WALL_VARIANT
	end
end

function BaseStyle.Start(): Handle
	local _ = Players.LocalPlayer
	local hasVariants = MaterialService:FindFirstChild(FLOOR_VARIANT) ~= nil
	local template: BasePart? = nil
	local meshes = ReplicatedStorage:FindFirstChild("StationMeshes")
	local t = meshes and meshes:FindFirstChild("Podium")
	if t and t:IsA("BasePart") then
		template = t
	end

	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "BaseStyleFX"
	fxFolder.Parent = workspace

	local styled: { [Instance]: boolean } = {}
	local podiumMesh: { [BasePart]: BasePart } = {}

	local function dress(podium: BasePart)
		if not template or podiumMesh[podium] then
			return
		end
		local m = template:Clone()
		local d = math.max(podium.Size.X, podium.Size.Z) + 1.2
		local h = podium.Size.Y + 0.2
		m.Size = Vector3.new(d, h, d)
		-- Üst yüzü kaidenin üstüyle aynı hizada (karakter yerinden oynamasın)
		m.CFrame = CFrame.new(podium.Position + Vector3.new(0, podium.Size.Y / 2 - h / 2 + 0.02, 0))
		m.Name = "PodiumMesh"
		m.Parent = fxFolder
		podiumMesh[podium] = m
		podium.LocalTransparencyModifier = 1
	end

	local function update()
		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			return
		end
		for _, plot in plots:GetChildren() do
			if not plot:IsA("Model") then
				continue
			end
			if not styled[plot] then
				styled[plot] = true
				if hasVariants then
					for _, d in plot:GetDescendants() do
						if d:IsA("BasePart") then
							texture(d)
						end
					end
					plot.DescendantAdded:Connect(function(d)
						if d:IsA("BasePart") then
							task.defer(texture, d)
						end
					end)
				end
			end
			local podiums = plot:FindFirstChild("Podiums")
			if podiums then
				for _, p in podiums:GetChildren() do
					if p:IsA("BasePart") and p.Name == "Podium" then
						dress(p)
					end
				end
			end
		end
		-- Kaide saydamlığı (kilitli kat / bonus) kürsüye; silinen kaidenin kürsüsü gider
		for podium, m in podiumMesh do
			if not podium.Parent then
				m:Destroy()
				podiumMesh[podium] = nil
			else
				m.Transparency = podium.Transparency
				podium.LocalTransparencyModifier = 1
			end
		end
	end

	return { Update = update }
end

return BaseStyle
