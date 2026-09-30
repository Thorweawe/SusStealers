--!strict
--[[
	Soygunun ANI (2026-09-29, "Steal a Brainrot gibi hype").

	Eskiden güverteye varınca ortada tek satır "STOLE X!" yazıyordu: oyunun
	en çok tekrarlanan başarısı en sönük andı. Artık kısa bir kutlama kartı:

	  ESCAPED! / CLOSE CALL!   — canavar dibindeyken vardıysan ikincisi
	  dönen 3B karakter        — nadirlik renginde kart, ışınlar
	  nadirlik + ad + mutasyon — "×30 INCOME" gibi
	  bonus satırı             — yarım saniye sonra (beklenti): close call
	                             bonusu ve şans bonusu (Config.Hype.LuckySteal)

	Kart 3 sn duruyor, bonus varsa biraz daha. Öğreticinin orta afişi
	(TutorialStage) açıksa kart onun altına iniyor.

	RareSpawn: gezegende çok nadir biri doğunca (SpaceService, Config.
	IsHypeSpawn) üst ortada birkaç saniyelik uyarı şeridi — üste, hedef
	kartının altına; oyun alanını kapatmıyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local UnitModel = require(Shared.UnitModel)

local CardKit = require(script.Parent.CardKit)
local SoundFX = require(script.Parent.SoundFX)

local StealReveal = {}

local Z = 70
local W, H = 440, 214
local SECRET_TINT = Color3.fromRGB(70, 44, 110)
local GOLD = Color3.fromRGB(255, 210, 60)

local current: Frame? = nil
local currentToken = 0

local function tintOf(rarity: string): Color3
	if rarity == "Secret" then
		return SECRET_TINT
	end
	local def = Config.Rarities[rarity]
	return if def then def.color else Color3.fromRGB(80, 140, 230)
end

--[[ Dönen 3B karakter. Model kurulamazsa nil (kart yine çıkıyor). ]]
local function preview(parent: GuiObject, unitId: string, mutationId: string?, z: number): (() -> ())?
	local ok, model = pcall(UnitModel.Build, unitId, mutationId)
	if not (ok and model) then
		return nil
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("BillboardGui") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Preview"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(170, 172, 182)
	vp.LightColor = Color3.fromRGB(255, 252, 245)
	vp.LightDirection = Vector3.new(-0.6, -1, 0.5)
	vp.ZIndex = z
	vp.Parent = parent
	local world = Instance.new("WorldModel")
	world.Parent = vp
	model:PivotTo(CFrame.new())
	model.Parent = world
	local cf, extent = model:GetBoundingBox()
	local reach = math.max(extent.X, extent.Y, extent.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local center = cf.Position
	camera.CFrame = CFrame.lookAt(center + Vector3.new(reach * 0.35, reach * 0.2, -reach * 2.3), center)
	camera.Parent = vp
	vp.CurrentCamera = camera
	local angle = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		angle += dt * 1.4
		model:PivotTo(CFrame.new(center) * CFrame.Angles(0, math.sin(angle) * 0.6, 0) * CFrame.new(-center))
	end)
	return function()
		conn:Disconnect()
	end
end

local function label(parent: Instance, text: string, size: number, color: Color3, z: number, outline: number?): TextLabel
	local l = CardKit.bold(parent, text, size, color, z, outline or 2.5)
	l.TextXAlignment = Enum.TextXAlignment.Left
	return l
end

export type Info = {
	unitId: string?,
	mutationId: string?,
	closeCall: number?,
	bonusId: string?,
	bonusName: string?,
	bonusCash: number?,
	candy: number?,
}

--[[ Güverteye varınca (SpaceFX "delivered"). `name` sunucunun yazdığı ad. ]]
function StealReveal.Show(screen: Instance, name: string, info: Info?)
	info = info or {}
	local data = info :: Info
	local unit = if data.unitId then Config.GetUnit(data.unitId) else nil
	local mutation = Config.GetMutation(data.mutationId)
	local rarity = if unit then unit.rarity else "Common"
	local tint = tintOf(rarity)
	local order = (Config.Rarities[rarity] and Config.Rarities[rarity].order) or 1
	local closeCall = data.closeCall or 0
	local bonusCash = data.bonusCash or 0

	currentToken += 1
	local token = currentToken
	if current then
		current:Destroy()
		current = nil
	end

	-- Öğreticinin orta afişi açıksa altına
	local stage = screen:FindFirstChild("TutorialStage", true)
	local lower = stage ~= nil and stage:IsA("GuiObject") and stage.Visible

	local holder = Instance.new("Frame")
	holder.Name = "StealReveal"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = if lower then UDim2.fromScale(0.5, 0.7) else UDim2.fromScale(0.5, 0.44)
	holder.Size = UDim2.fromOffset(W, H)
	holder.BackgroundTransparency = 1
	holder.ZIndex = Z
	holder.Parent = screen
	current = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder

	-- Başlık kartın üstünde, kenarından taşıyor
	local header = CardKit.bold(holder, if closeCall > 0 then "CLOSE CALL!" else "ESCAPED!", 40,
		if closeCall > 0 then Color3.fromRGB(255, 120, 90) else GOLD, Z + 6, 5)
	header.AnchorPoint = Vector2.new(0.5, 0.5)
	header.Position = UDim2.new(0.5, 0, 0, 4)
	header.Size = UDim2.new(1, 0, 0, 48)
	header.Rotation = -3

	local card = CardKit.hero(holder, tint, UDim2.new(1, 0, 1, -18), Z, UDim2.fromScale(0.2, 0.5), 520)
	card.Position = UDim2.fromOffset(0, 18)

	local stage3d = Instance.new("Frame")
	stage3d.BackgroundTransparency = 1
	stage3d.Position = UDim2.fromOffset(6, 14)
	stage3d.Size = UDim2.fromOffset(150, 150)
	stage3d.ZIndex = Z + 3
	stage3d.Parent = card
	local stopPreview = if data.unitId then preview(stage3d, data.unitId, data.mutationId, Z + 3) else nil

	local tag = label(card, string.upper(rarity), 20, if rarity == "Secret" then Color3.fromRGB(230, 200, 255) else tint:Lerp(Color3.new(1, 1, 1), 0.55), Z + 4)
	tag.Position = UDim2.fromOffset(166, 30)
	tag.Size = UDim2.new(1, -180, 0, 24)
	local title = label(card, name, 30, Color3.new(1, 1, 1), Z + 4, 3)
	title.Position = UDim2.fromOffset(166, 54)
	title.Size = UDim2.new(1, -180, 0, 40)
	CardKit.fit(title, 30, 16)
	local sub = label(card, if mutation then string.format("%s MUTATION  ·  ×%d INCOME", string.upper(mutation.name), mutation.incomeMul) else "is on your podium!", 16,
		if mutation then GOLD else Color3.fromRGB(230, 236, 250), Z + 4, 2)
	sub.Position = UDim2.fromOffset(166, 96)
	sub.Size = UDim2.new(1, -180, 0, 22)
	CardKit.fit(sub, 16, 11)

	-- Bonus satırı: yarım saniye sonra (beklenti), yoksa hiç çıkmıyor
	local lines: { string } = {}
	if closeCall > 0 then
		table.insert(lines, string.format("CLOSE CALL +$%s", Config.FormatCash(closeCall)))
	end
	if bonusCash > 0 then
		table.insert(lines, string.format("%s +$%s", data.bonusName or "BONUS!", Config.FormatCash(bonusCash)))
	end
	-- Sınırlı etkinlik şekeri (Config.LimitedEvent; sunucu aynı miktarı ekledi)
	local candy = data.candy or 0
	if candy > 0 then
		table.insert(lines, string.format("+%d %s CANDY", candy, Config.LimitedEvent.icon))
	end
	local bonus = label(card, "", 22, Color3.fromRGB(120, 255, 140), Z + 5, 3)
	bonus.AnchorPoint = Vector2.new(0, 1)
	bonus.Position = UDim2.new(0, 166, 1, -14)
	bonus.Size = UDim2.new(1, -180, 0, 52)
	bonus.TextWrapped = true
	bonus.TextYAlignment = Enum.TextYAlignment.Bottom
	CardKit.fit(bonus, 22, 12)
	bonus.Visible = false

	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	SoundFX.HatchReveal(order)

	local seconds = 3.2
	if #lines > 0 then
		seconds += 1.2
		task.delay(0.55, function()
			if token ~= currentToken then
				return
			end
			bonus.Text = table.concat(lines, "\n")
			bonus.Visible = true
			local pop = Instance.new("UIScale")
			pop.Scale = 1.6
			pop.Parent = bonus
			TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			if data.bonusId == "Jackpot" then
				SoundFX.HatchReveal(6)
			else
				SoundFX.Event("reward", false)
			end
		end)
	end

	task.delay(seconds, function()
		if token ~= currentToken then
			if stopPreview then
				stopPreview()
			end
			return
		end
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.wait(0.26)
		if stopPreview then
			stopPreview()
		end
		holder:Destroy()
		if current == holder then
			current = nil
		end
	end)
end

--[[ Gezegende çok nadir biri doğdu (bütün sunucu). ]]
local bannerToken = 0
local banner: Frame? = nil
function StealReveal.RareSpawn(screen: Instance, unitId: string, mutationId: string?, planetIndex: number)
	local unit = Config.GetUnit(unitId)
	local planet = Config.SpaceMonsters[planetIndex]
	if not (unit and planet) then
		return
	end
	local mutation = Config.GetMutation(mutationId)
	bannerToken += 1
	local token = bannerToken
	if banner then
		banner:Destroy()
	end
	local holder = Instance.new("Frame")
	holder.Name = "RareSpawnBanner"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 170)
	holder.Size = UDim2.fromOffset(470, 70)
	holder.BackgroundTransparency = 1
	holder.ZIndex = Z - 10
	holder.Parent = screen
	banner = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = holder
	local tint = tintOf(unit.rarity)
	local card = CardKit.hero(holder, tint, UDim2.fromScale(1, 1), Z - 10, UDim2.fromScale(0.5, 0.5), 400)
	local top = CardKit.bold(card, string.format("%s SPOTTED!", if unit.rarity == "Secret" or unit.rarity == "Celestial" then string.upper(unit.rarity) else "IMPOSTOR MUTATION"),
		22, GOLD, Z - 6, 3)
	top.Position = UDim2.fromOffset(0, 6)
	top.Size = UDim2.new(1, 0, 0, 26)
	local body = CardKit.bold(card, string.format("%s%s on %s  ·  needs %d Space Speed",
		if mutation then mutation.name .. " " else "", unit.name, planet.planet, planet.need), 17, Color3.new(1, 1, 1), Z - 6, 2)
	body.Position = UDim2.fromOffset(10, 36)
	body.Size = UDim2.new(1, -20, 0, 24)
	CardKit.fit(body, 17, 11)
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	SoundFX.Alarm()
	task.delay(6, function()
		if token ~= bannerToken then
			return
		end
		TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 0 }):Play()
		task.wait(0.26)
		holder:Destroy()
		if banner == holder then
			banner = nil
		end
	end)
end

return StealReveal
