--!strict
--[[
	Oyuncuyu GERİ GETİREN anlar (2026-09-29). Üç iş, hepsi istemcide:

	  WELCOME BACK  — geri dönen oyuncuya büyük kart: yokken kazandığı para
	                  (sunucu "OfflineEarned"/"OfflineSeconds" niteliği yazıyor,
	                  EconomyService), çevrimdışı kazancın TAVANI ("3 saatten
	                  sonra durur — daha sık gel") ve günlük ödül hazırsa ona
	                  giden düğme. Başlık ekranı kapanınca (Ready) çıkıyor.

	  FAVORİ        — oturumda 3. soygundan sonra, oyun favorilerde değilse
	                  Roblox'un favori istemi (oturum başına en fazla bir kez).
	                  Favori, oyuncunun ana sayfasında oyunu gösteriyor ve
	                  Roblox'un öneri sıralamasında sayılıyor.

	  BİLDİRİM İZNİ — günlük ödülü alınca "yarınki ödül hazır olunca haber
	                  verelim mi?" — Roblox'un deneyim bildirimi istemi.
	                  Ne kadar sık sorulabileceğini Roblox kendisi sınırlıyor
	                  (CanPromptOptInAsync). Bildirimi GÖNDERMEK için Creator
	                  Hub'da bildirim şablonu ve Open Cloud anahtarı gerekiyor
	                  (kodda değil, panelde).
]]

local AvatarEditorService = game:GetService("AvatarEditorService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local CardKit = require(script.Parent.CardKit)
local SoundFX = require(script.Parent.SoundFX)

local Engagement = {}

local player = Players.LocalPlayer

local Z = 80
local GOLD = Color3.fromRGB(255, 210, 60)
local FAVORITE_AFTER_STEALS = 3

export type Hooks = {
	openRewards: () -> (),
	dailyReady: () -> boolean,
}

local screenRef: Instance? = nil
local hooks: Hooks? = nil
local ready = false
local welcomeShown = false

local function duration(seconds: number): string
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then
		return string.format("%d min", math.max(1, minutes))
	end
	return string.format("%dh %02dm", minutes // 60, minutes % 60)
end

local function showWelcome()
	local screen = screenRef
	local earned = player:GetAttribute("OfflineEarned")
	local seconds = player:GetAttribute("OfflineSeconds")
	if welcomeShown or not (ready and screen) or typeof(earned) ~= "number" or earned <= 0 then
		return
	end
	welcomeShown = true
	local away = if typeof(seconds) == "number" then seconds else 0
	local capped = away >= Config.OfflineIncomeCapHours * 3600

	local holder = Instance.new("Frame")
	holder.Name = "WelcomeBack"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(460, 290)
	holder.BackgroundTransparency = 1
	holder.ZIndex = Z
	holder.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder

	local card = CardKit.hero(holder, Color3.fromRGB(60, 120, 230), UDim2.fromScale(1, 1), Z, UDim2.fromScale(0.5, 0.42), 560)
	local title = CardKit.bold(card, "WELCOME BACK!", 38, GOLD, Z + 4, 5)
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 44)
	local sub = CardKit.bold(card, "Your crew kept working while you were away", 18, Color3.new(1, 1, 1), Z + 4, 2)
	sub.Position = UDim2.fromOffset(16, 62)
	sub.Size = UDim2.new(1, -32, 0, 22)
	CardKit.fit(sub, 18, 12)
	local amount = CardKit.bold(card, "+$" .. Config.FormatCash(earned), 52, Color3.fromRGB(130, 255, 140), Z + 4, 5)
	amount.Position = UDim2.fromOffset(0, 88)
	amount.Size = UDim2.new(1, 0, 0, 58)
	local note = CardKit.bold(card, if capped
		then string.format("Offline earnings stop after %dh — come back sooner!", Config.OfflineIncomeCapHours)
		else string.format("Away %s  ·  offline earnings grow for up to %dh", duration(away), Config.OfflineIncomeCapHours),
		16, if capped then Color3.fromRGB(255, 190, 120) else Color3.fromRGB(220, 230, 250), Z + 4, 2)
	note.Position = UDim2.fromOffset(16, 150)
	note.Size = UDim2.new(1, -32, 0, 20)
	CardKit.fit(note, 16, 11)

	local h = hooks
	local daily = h ~= nil and h.dailyReady()
	local collect = CardKit.button(card, UDim2.fromOffset(if daily then 190 else 240, 62), Z + 5, 24, CardKit.GREEN)
	collect.holder.AnchorPoint = Vector2.new(0.5, 1)
	collect.holder.Position = if daily then UDim2.new(0.5, -102, 1, -18) else UDim2.new(0.5, 0, 1, -18)
	collect.set("COLLECT", CardKit.GREEN)

	local function close()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.delay(0.21, function()
			holder:Destroy()
		end)
	end
	collect.button.Activated:Connect(function()
		SoundFX.Event("reward", false)
		close()
	end)
	if daily and h then
		local go = CardKit.button(card, UDim2.fromOffset(190, 62), Z + 5, 20, Color3.fromRGB(240, 150, 30))
		go.holder.AnchorPoint = Vector2.new(0.5, 1)
		go.holder.Position = UDim2.new(0.5, 102, 1, -18)
		go.set("DAILY REWARD!", Color3.fromRGB(240, 150, 30))
		go.button.Activated:Connect(function()
			close()
			h.openRewards()
		end)
	end

	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	SoundFX.Event("welcome", false)
end

--[[ Başlık ekranı kapandı: bekleyen kartlar artık çıkabilir. ]]
function Engagement.Ready()
	ready = true
	task.delay(0.8, showWelcome)
end

--[[ Roblox'un bildirim izni istemi (günlük ödül alınınca). Sessizce başarısız olabilir. ]]
function Engagement.PromptNotifications()
	task.spawn(function()
		local ok, can = pcall(function()
			return ExperienceNotificationService:CanPromptOptInAsync()
		end)
		if ok and can then
			task.wait(1.2)
			pcall(function()
				ExperienceNotificationService:PromptOptIn()
			end)
		end
	end)
end

local favoriteAsked = false
local function maybeFavorite()
	if favoriteAsked then
		return
	end
	favoriteAsked = true
	task.spawn(function()
		-- Favorideyse sorma (öğrenemezsek oturumda bir kez soruluyor)
		local ok, favorited = pcall(function()
			return AvatarEditorService:GetFavorite(game.PlaceId, Enum.AvatarItemType.Asset)
		end)
		if ok and favorited then
			return
		end
		-- Kutlama kartı geçsin
		task.wait(4.5)
		pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
	end)
end

function Engagement.Start(screen: Instance, h: Hooks)
	screenRef = screen
	hooks = h
	player:GetAttributeChangedSignal("OfflineEarned"):Connect(showWelcome)

	-- Oturumdaki soygunlar (leaderstats.Stolen artışı)
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats", 60)
		local stolen = stats and stats:WaitForChild("Stolen", 60)
		if not (stolen and stolen:IsA("IntValue")) then
			return
		end
		-- Kayıt yüklenince sayaç kayıttaki değere atlıyor: önce onu bekle
		-- (TutorialStep niteliği profil yüklenince geliyor, SideRail de ona bakıyor)
		while player:GetAttribute("TutorialStep") == nil do
			player:GetAttributeChangedSignal("TutorialStep"):Wait()
		end
		task.wait(2)
		local start = stolen.Value
		stolen.Changed:Connect(function(value)
			if value - start >= FAVORITE_AFTER_STEALS then
				maybeFavorite()
			end
		end)
	end)
end

return Engagement
