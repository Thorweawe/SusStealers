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

	--[[
		Kilitli kat tamamen gizleniyor.

		Önce %75 saydam gri (sunucunun varsayılanı), sonra camgöbeği plan
		denendi. İkisi de rahatsız ediciydi: havada asılı yarı görünür
		bloklar gözü sürekli meşgul ediyor ve sahnenin okunurluğunu bozuyor.
		Olmayan bir katı göstermenin oyuncuya faydası yok — hedefi arayüz
		zaten anlatıyor.

		Çarpışmaya dokunmuyoruz; sunucu onu zaten kapatmış.
	]]
	local function styleLocked(floorModel: Model)
		for _, part in floorModel:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end
			part.Transparency = 1
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

	--[[
		Eski "FLOOR 2 · LOCKED" etiketini temizler. Etiket fikri iyiydi ama
		havada asılı yazı da görüntü kirliliği yapıyordu; kat tamamen
		gizlendiğine göre anlatacak bir şey de kalmadı.
	]]
	local function clearLabel(floorModel: Model)
		local tag = floorModel:FindFirstChild("FloorTag")
		if tag then
			tag:Destroy()
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
				clearLabel(floorModel)
			end
		end
	end

	return { Update = update }
end

return FloorStyle
