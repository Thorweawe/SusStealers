--!strict
--[[
	Konveyör bandı: gri çıtalar ve bandın üstündeki karakterler AYNI saatle
	çiziliyor.

	ESKİ HATA: çıtalar DecorFX'te sabit 5 stud/sn'de kayıyordu, karakterler
	sunucuda ~2.7 stud/sn'de ilerliyordu. Çıtalar karakterlerin altından
	kayıp gidiyor, karakterler bandın üstünde "kayıyormuş" gibi duruyordu.
	Conveyor Speed yükseltmesi de ikisini ayrı ayrı etkilemiyordu.

	Şimdi tek bir sayaç var (ConveyorService, "BANT SAATİ"): üssün Conveyor
	parçasının BeltSpeed / BeltDistance / BeltStamp nitelikleri.

	    D(t) = BeltDistance + BeltSpeed × (t − BeltStamp)

	  - Çıta k: (SlidePhase + D) mod SlideRange — bandın başından itibaren.
	  - Karakter: D − SpawnDistance. Sunucu karakteri D'nin çıta aralığının
	    tam katında ağza getiriyor, yani karakter hep bir çıtanın üstünde.

	Karakterler sunucuda da taşınıyor (prompt mesafesi orada doğrulanıyor;
	saniyede 5 kez) ama ekranda burada, her karede yeniden konumlanıyor. Sunucudan gelen
	konum ağ gecikmesi kadar geride kalıyordu; çıtalar ise istemcinin
	saatinde. Aynı formülden çizilince aradaki kayma sıfırlanıyor.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ConveyorFX = {}

type Slat = {
	part: BasePart,
	base: CFrame,
	phase: number,
	range: number,
	sign: number,
	plotName: string,
}

export type FX = {
	Stop: () -> (),
}

local function conveyorOf(plotName: string): BasePart?
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(plotName)
	local conveyor = plot and plot:FindFirstChild("Conveyor")
	if conveyor and conveyor:IsA("BasePart") then
		return conveyor
	end
	return nil
end

--[[
	Bandın kat ettiği yol. Nitelikler henüz gelmediyse (üs kurulmadı, akış
	gecikti) taban hızla sürüyor ki çıtalar donmasın.
]]
local function beltDistance(conveyor: BasePart?, now: number): number
	if conveyor then
		local speed = conveyor:GetAttribute("BeltSpeed")
		local distance = conveyor:GetAttribute("BeltDistance")
		local stamp = conveyor:GetAttribute("BeltStamp")
		if typeof(speed) == "number" and typeof(distance) == "number" and typeof(stamp) == "number" then
			return distance + speed * (now - stamp)
		end
	end
	return Config.GetConveyorBeltSpeed(0) * now
end

function ConveyorFX.Start(): FX
	local slats: { Slat } = {}
	local registered: { [Instance]: boolean } = {}

	--[[
		Çıtalar haritada (Decor.Plots.PlotN.BeltSlat). Hangi üsse ait
		oldukları klasörün adından okunuyor: harita ve sunucu üsleri aynı
		numarayla kuruluyor (tools/map/bays.luau, PlotService).
	]]
	local function register(obj: Instance)
		if registered[obj] or obj.Name ~= "BeltSlat" or not obj:IsA("BasePart") then
			return
		end
		local range = obj:GetAttribute("SlideRange")
		if typeof(range) ~= "number" or range <= 0 then
			return
		end
		local folder = obj.Parent
		if not folder then
			return
		end
		registered[obj] = true

		local speed = obj:GetAttribute("SlideSpeed")
		local phase = obj:GetAttribute("SlidePhase")
		table.insert(slats, {
			part = obj,
			base = obj.CFrame,
			phase = if typeof(phase) == "number" then phase else 0,
			range = range,
			-- Yön haritadan (üst sıra üsler 180° dönük), hız bant saatinden
			sign = if typeof(speed) == "number" and speed < 0 then -1 else 1,
			plotName = folder.Name,
		})
	end

	local added: RBXScriptConnection? = nil
	task.spawn(function()
		local decor = workspace:FindFirstChild("Decor") or workspace:WaitForChild("Decor", 30)
		if not decor then
			return
		end
		added = decor.DescendantAdded:Connect(register)
		for _, obj in decor:GetDescendants() do
			register(obj)
		end
	end)

	--[[
		PERFORMANS: sekiz üssün bandı ve bantlardaki karakterler eskiden her
		karede, oyuncu nerede olursa olsun taşınıyordu. Artık üssün bandı
		kameraya yakınsa her karede, orta uzaklıkta 3 karede bir, uzaktaysa
		12 karede bir çiziliyor (konum saatten hesaplanıyor, sıçrama yok).
		Çıtalar tek BulkMoveTo çağrısıyla yazılıyor.
	]]
	local NEAR, MID = 140, 380
	local frameNo = 0
	local moveParts: { BasePart } = {}
	local moveCFrames: { CFrame } = {}

	local connection = RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		frameNo += 1
		local cam = workspace.CurrentCamera.CFrame.Position

		-- Aynı karede her üssün saatini ve "bu kare çizilsin mi" kararını bir kez hesapla
		local distances: { [string]: number } = {}
		local due: { [string]: boolean } = {}
		local function distanceFor(plotName: string): number
			local d = distances[plotName]
			if not d then
				d = beltDistance(conveyorOf(plotName), now)
				distances[plotName] = d
			end
			return d
		end
		local function dueFor(plotName: string): boolean
			local v = due[plotName]
			if v == nil then
				local conveyor = conveyorOf(plotName)
				local d = if conveyor then (conveyor.Position - cam).Magnitude else 0
				v = d <= NEAR or (d <= MID and frameNo % 3 == 0) or frameNo % 12 == 0
				due[plotName] = v
			end
			return v :: boolean
		end

		table.clear(moveParts)
		table.clear(moveCFrames)
		for _, s in slats do
			if not dueFor(s.plotName) then
				continue
			end
			local travelled = (s.phase + distanceFor(s.plotName)) % s.range
			local n = #moveParts + 1
			moveParts[n] = s.part
			moveCFrames[n] = s.base * CFrame.new(travelled * s.sign, 0, 0)
		end
		if #moveParts > 0 then
			workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end

		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			return
		end
		for _, plot in plots:GetChildren() do
			local items = plot:FindFirstChild("Items")
			if not items or not dueFor(plot.Name) then
				continue
			end
			for _, model in items:GetChildren() do
				if not (model:IsA("Model") and model.PrimaryPart) then
					continue
				end
				local start = model:GetAttribute("BeltStart")
				local spawnDistance = model:GetAttribute("SpawnDistance")
				local travel = model:GetAttribute("Travel")
				if typeof(start) ~= "CFrame" or typeof(spawnDistance) ~= "number" or typeof(travel) ~= "number" then
					continue
				end
				-- Sunucu bu sınıra gelince siliyor; silme gecikirse girişte beklesin
				local position = math.min(distanceFor(plot.Name) - spawnDistance, travel)
				model:PivotTo(start * CFrame.new(position, 0, 0))
			end
		end
	end)

	return {
		Stop = function()
			connection:Disconnect()
			if added then
				added:Disconnect()
			end
		end,
	}
end

return ConveyorFX
