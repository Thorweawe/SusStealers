--!strict
-- Kilitli katları holografik plan gibi gösterir.
--
-- Sunucu kilitli katları %75 saydam yapıyor ve üstüne basılmasın diye
-- çarpışmasını kapatıyor. Mantık doğru ama sonuç bozuk bir render gibi
-- duruyordu: yarı görünür gri bloklar.
--
-- Burada aynı katları camgöbeği bir projeksiyona çeviriyoruz. Mesaj aynı
-- ("burası henüz yok") ama artık kasıtlı görünüyor — üstelik bir hedef
-- gibi duruyor, oyuncu oraya ulaşmak istiyor.
--
-- Tamamen görsel ve tamamen istemci tarafı. Çarpışmaya dokunmuyoruz:
-- kilitli kat yine geçirgen kalmalı.

local Players = game:GetService("Players")

local FloorStyle = {}

local player = Players.LocalPlayer

local PLAN = Color3.fromRGB(60, 150, 190)       -- plan çizgisi
local PLAN_DIM = Color3.fromRGB(28, 74, 96)
local LOCKED_TEXT = Color3.fromRGB(120, 200, 235)

export type Style = {
	Update: () -> (),
}

function FloorStyle.Create(): Style
	-- Hangi kata ne uyguladığımızı tutuyoruz: her turda bütün parçalara
	-- yazmak yerine sadece durum değişince dokunuyoruz.
	local applied: { [Model]: number } = {}

	local function styleLocked(floorModel: Model)
		for _, part in floorModel:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end

			--[[
				Neon + yüksek saydamlık = ışık projeksiyonu. Düz gri yarı
				saydamdan farkı: gölge almıyor, kendi rengiyle parlıyor,
				bu yüzden "katı bir nesnenin hayaleti" değil "bir plan"
				gibi okunuyor.
			]]
			part.Material = Enum.Material.Neon
			part.Color = if part.Name == "Podium" then PLAN else PLAN_DIM
			part.Transparency = 0.86
			part.CastShadow = false
		end
	end

	local function styleOpen(floorModel: Model)
		for _, part in floorModel:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = 0
			part.CastShadow = true
		end
	end

	--[[ Kilitli katın ortasında "FLOOR 2 · LOCKED" yazısı. ]]
	local function ensureLabel(floorModel: Model, index: number, locked: boolean)
		local anchor = floorModel:FindFirstChild("FloorTag")

		if not locked then
			if anchor then
				anchor:Destroy()
			end
			return
		end

		if not anchor then
			local deck = floorModel:FindFirstChild("Deck") or floorModel:FindFirstChildWhichIsA("BasePart")
			if not (deck and deck:IsA("BasePart")) then
				return
			end

			local tag = Instance.new("Part")
			tag.Name = "FloorTag"
			tag.Size = Vector3.new(1, 1, 1)
			tag.CFrame = deck.CFrame * CFrame.new(0, 8, 0)
			tag.Anchored = true
			tag.CanCollide = false
			tag.CanQuery = false
			tag.CanTouch = false
			tag.Transparency = 1
			tag.Parent = floorModel

			local gui = Instance.new("BillboardGui")
			gui.Name = "Label"
			gui.Size = UDim2.fromScale(14, 3)
			gui.AlwaysOnTop = false
			gui.MaxDistance = 200
			gui.Parent = tag

			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.GothamBold
			text.TextScaled = true
			text.TextColor3 = LOCKED_TEXT
			text.TextTransparency = 0.15
			text.TextStrokeTransparency = 0.5
			text.Text = string.format("FLOOR %d  ·  LOCKED", index)
			text.Parent = gui
		end
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

			local unlocked = plot:GetAttribute("UnlockedFloors")
			if typeof(unlocked) ~= "number" then
				continue
			end

			local floors = plot:FindFirstChild("Floors")
			if not floors then
				continue
			end

			for _, floorModel in floors:GetChildren() do
				if not floorModel:IsA("Model") then
					continue
				end

				local index = tonumber(string.match(floorModel.Name, "%d+")) or 1
				local locked = index > unlocked

				-- Durum değişmediyse dokunma
				local state = if locked then 0 else 1
				if applied[floorModel] == state then
					continue
				end
				applied[floorModel] = state

				if locked then
					styleLocked(floorModel)
				else
					styleOpen(floorModel)
				end
				ensureLabel(floorModel, index, locked)
			end
		end
	end

	return { Update = update }
end

return FloorStyle
