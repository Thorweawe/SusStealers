--!strict
-- Karakter taşıyan oyuncunun arkasında sönen parlak iz.
--
-- Kovalamacayı görünür kılıyor: köşeyi döndüğünde hırsızı kaybetsen bile
-- izi hangi yöne gittiğini söylüyor. Alarm "birisi çaldı" diyor, harita
-- "şurada" diyor, iz "oradan gitti" diyor — üçü birlikte takip edilebilir
-- bir kaçış yaratıyor.
--
-- Tamamen istemci tarafı ve tamamen görsel. İzler her oyuncunun kendi
-- makinesinde üretiliyor, ağda hiçbir şey taşınmıyor.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ThiefTrail = {}

local player = Players.LocalPlayer

local DROP_INTERVAL = 0.14   -- iki iz arası süre
local FADE_TIME = 2.2        -- izin sönme süresi
local MAX_DISTANCE = 260     -- bu mesafeden uzaktaki hırsız için iz üretme

local HOT = Color3.fromRGB(255, 150, 50)    -- başkasının izi: dikkat çeksin
local MINE = Color3.fromRGB(120, 255, 150)  -- kendi izin: sakin

export type Trail = {
	Stop: () -> (),
}

local function carrying(p: Player): boolean
	local char = p.Character
	return char ~= nil and char:FindFirstChild("CarriedUnit") ~= nil
end

function ThiefTrail.Start(): Trail
	--[[
		İzler ayrı bir klasörde: dekorun içine karışırlarsa OwnerColors gibi
		dekoru tarayan modüller onları da boyamaya çalışır.
	]]
	local folder = workspace:FindFirstChild("TrailFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TrailFX"
		folder.Parent = workspace
	end

	local lastDrop: { [Player]: number } = {}

	local function drop(p: Player, position: Vector3, mine: boolean)
		local mark = Instance.new("Part")
		mark.Name = "Step"
		mark.Size = Vector3.new(2.6, 0.12, 2.6)
		mark.CFrame = CFrame.new(position.X, position.Y - 2.6, position.Z)
			* CFrame.Angles(0, math.random() * math.pi, 0)
		mark.Color = if mine then MINE else HOT
		mark.Material = Enum.Material.Neon
		mark.Anchored = true
		mark.CanCollide = false
		mark.CanQuery = false
		mark.CanTouch = false
		mark.Transparency = 0.25
		mark.Parent = folder

		--[[
			Sönerken hem saydamlaşıyor hem küçülüyor. Sadece saydamlaşsa
			son anına kadar aynı boyutta durup birden kayboluyor; küçülme
			"soğuyor" hissini veriyor ve iz yaşını okunur kılıyor.
		]]
		local info = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(mark, info, {
			Transparency = 1,
			Size = Vector3.new(0.6, 0.12, 0.6),
		}):Play()

		task.delay(FADE_TIME + 0.15, function()
			mark:Destroy()
		end)
	end

	local connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()

		local myRoot: BasePart? = nil
		local myChar = player.Character
		local r = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") then
			myRoot = r
		end

		for _, p in Players:GetPlayers() do
			if not carrying(p) then
				lastDrop[p] = nil
				continue
			end

			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart")) then
				continue
			end

			-- Uzaktaki hırsız için iz üretmenin anlamı yok, görünmüyor
			if myRoot and (root.Position - myRoot.Position).Magnitude > MAX_DISTANCE then
				continue
			end

			local last = lastDrop[p] or 0
			if now - last < DROP_INTERVAL then
				continue
			end
			lastDrop[p] = now

			drop(p, root.Position, p == player)
		end
	end)

	return {
		Stop = function()
			connection:Disconnect()
		end,
	}
end

return ThiefTrail
