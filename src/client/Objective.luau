--!strict
--[[
	TEK HEDEF kartı — oyuncuya her an "şimdi ne yapmalıyım" diyen şey.

	═══ GÖRSEL HİYERARŞİ (2026-09-28) ═════════════════════════════════════

	Ekran üç seviyeye ayrıldı; göz önce 1'e, sonra 2'ye gidiyor:

	  1. BİRİNCİL  — ÜST ORTA sütun: [süren olay şeridi] + [HEDEF kartı]
	                 ve SOL ALT: nakit + uzay hızı. Tam renk yalnızca burada.
	  2. İKİNCİL   — SOL: menü ızgarası (SHOP, INVENTORY, QUESTS, INDEX,
	                 PASS, REBIRTH); lacivert, ikonlar renkli.
	  3. ÜÇÜNCÜL   — sağ üst CREW tablosu, üst şerit düğmeleri, sıradaki olay
	                 satırı: küçük, sönük.

	Uzayda üst ortayı uzay kartı (SpaceFX), kapsülde kapsül kartı (CapsuleFX)
	alıyor; hedef kartı aynı yerde olduğu için oyuncu "hedef hep orada"
	öğreniyor. Öğretici sürerken hedef = öğretici kartı (TutorialUI); bu kart
	öğretici bitince devralıyor.

	═══ HEDEFİN SEÇİMİ (öncelik sırası) ════════════════════════════════════

	  kaideler dolu      → "Podiums full: sell one or unlock a floor"
	  rebirth parası var → "REBIRTH is ready"          (tıklayınca pencere)
	  sıradaki canavar   → "Train to N Space Speed to rob X" + ilerleme
	  hepsi açık         → "Hunt Secret crew on the last planet"

	Altında küçük satır: sıradaki olay 10 dakikadan yakınsa "⏱ Meteor
	Shower in 4:12" (eski sağ alt çizelgenin yerine; saatte iki olay var).

	═══ ARA ARA (2026-09-28) ══════════════════════════════════════════════

	"Sürekli açık kalınca rahatsız ediyor": kart SHOW_SECONDS görünüp
	sönerek kayboluyor; hedef değişince ya da REPEAT_SECONDS geçince
	yeniden geliyor. (Pencere / uzay / sinema sırasında yine gizli.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local CardKit = require(script.Parent.CardKit)
local OwnPlot = require(script.Parent.OwnPlot)

local Objective = {}

export type Handle = { Destroy: () -> () }

local player = Players.LocalPlayer
local Z = 20
local SHOW_SECONDS = 5
local REPEAT_SECONDS = 90
local W, H = 420, 64

type Goal = { key: string, icon: string, title: string, sub: string, progress: number?, tint: Color3, onClick: (() -> ())? }

local function num(attr: string, default: number): number
	local v = player:GetAttribute(attr)
	return if typeof(v) == "number" then v else default
end

--[[ Açık katlardaki boş kaide var mı. ]]
local function podiumsFull(): boolean
	local plot = OwnPlot.Get()
	if not plot then
		return false
	end
	local unlocked = (plot:GetAttribute("UnlockedFloors") :: number?) or 1
	local total = 0
	for _, d in plot:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Podium" then
			local floor = (d:GetAttribute("Floor") :: number?) or 1
			if floor <= unlocked and not d:GetAttribute("Bonus") then
				total += 1
				local unitId = d:GetAttribute("UnitId")
				if typeof(unitId) ~= "string" or unitId == "" then
					return false
				end
			end
		end
	end
	return total > 0
end

function Objective.Start(screen: Instance, actions: { [string]: () -> () }): Handle
	-- CanvasGroup: kartın bütün yazıları birlikte sönebilsin
	local holder = Instance.new("CanvasGroup")
	holder.Name = "Objective"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 78)
	holder.Size = UDim2.fromOffset(W, H + 26)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = screen

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(W, H)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = Z
	button.Parent = holder
	local card = CardKit.hero(button, Color3.fromRGB(46, 110, 220), UDim2.fromScale(1, 1), Z, UDim2.fromScale(0.1, 0.5), 300)
	card.Active = false

	local tag = CardKit.bold(card, "GOAL", 12, Color3.fromRGB(200, 235, 255), Z + 3, 1.6)
	tag.AnchorPoint = Vector2.new(0, 0)
	tag.Position = UDim2.fromOffset(64, 5)
	tag.Size = UDim2.fromOffset(60, 14)
	tag.TextXAlignment = Enum.TextXAlignment.Left
	local icon = CardKit.bold(card, "🎯", 30, Color3.new(1, 1, 1), Z + 3, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0, 32, 0.5, 0)
	icon.Size = UDim2.fromOffset(44, 44)
	local title = CardKit.bold(card, "", 20, Color3.new(1, 1, 1), Z + 3, 2.4)
	title.Position = UDim2.fromOffset(64, 17)
	title.Size = UDim2.new(1, -76, 0, 24)
	title.TextXAlignment = Enum.TextXAlignment.Left
	CardKit.fit(title, 20, 12)
	local sub = CardKit.bold(card, "", 14, Color3.fromRGB(230, 240, 255), Z + 3, 1.6)
	sub.Position = UDim2.fromOffset(64, 40)
	sub.Size = UDim2.new(1, -76, 0, 18)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	CardKit.fit(sub, 14, 10)
	-- İlerleme: kartın altında ince çizgi
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -4)
	track.Size = UDim2.new(1, -24, 0, 5)
	track.BackgroundColor3 = Color3.fromRGB(10, 14, 30)
	track.BackgroundTransparency = 0.3
	track.BorderSizePixel = 0
	track.ZIndex = Z + 3
	track.Parent = card
	CardKit.corner(track, 3)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 255, 150)
	fill.BorderSizePixel = 0
	fill.ZIndex = Z + 4
	fill.Parent = track
	CardKit.corner(fill, 3)

	-- Sıradaki olay: küçük, sönük satır (üçüncül)
	local nextEvent = CardKit.bold(holder, "", 14, Color3.fromRGB(200, 210, 230), Z, 1.6)
	nextEvent.AnchorPoint = Vector2.new(0.5, 0)
	nextEvent.Position = UDim2.new(0.5, 0, 0, H + 4)
	nextEvent.Size = UDim2.fromOffset(W, 18)
	nextEvent.TextTransparency = 0.15

	local current: Goal? = nil
	local shownKey = ""

	local function pick(): Goal
		if podiumsFull() then
			return { key = "full", icon = "🧑‍🚀", title = "Your podiums are full!", sub = "Sell a crewmate or unlock a new floor",
				tint = Color3.fromRGB(220, 120, 40), onClick = actions.Inventory }
		end
		local rebirths = num("Rebirths", 0)
		local cash = num("Cash", 0)
		local cost = Config.GetRebirthCost(rebirths)
		if cash >= cost then
			return { key = "rebirth", icon = "♻️", title = "REBIRTH is ready!", sub = "Reset for a permanent income boost - tap to open",
				tint = Color3.fromRGB(230, 130, 40), onClick = actions.Rebirth }
		end
		local speed = num("SpaceSpeed", Config.Space.BaseSpeed)
		local prev = Config.Space.BaseSpeed
		for _, def in Config.SpaceMonsters do
			-- Rebirth canavarı kilitliyse hedef rebirth (2026-09-29)
			if not Config.MonsterUnlocked(def, rebirths) then
				return {
					key = "rebirthgate:" .. def.id,
					icon = "♻️",
					title = string.format("Rebirth %d unlocks %s", def.rebirths or 0, def.name),
					sub = string.format("A new monster with CELESTIAL crew · %d/%d rebirths", rebirths, def.rebirths or 0),
					progress = rebirths / math.max(1, def.rebirths or 1),
					tint = Color3.fromRGB(230, 130, 40),
					onClick = actions.Rebirth,
				}
			end
			if speed < def.need then
				return {
					key = "train:" .. def.id,
					icon = "🚀",
					title = string.format("Train to %d Space Speed", def.need),
					sub = string.format("Train in your Space Capsule to unlock %s", def.name),
					progress = (speed - prev) / math.max(0.001, def.need - prev),
					tint = Color3.fromRGB(46, 110, 220),
				}
			end
			prev = def.need
		end
		local last = Config.SpaceMonsters[#Config.SpaceMonsters]
		return { key = "hunt", icon = "👑", title = "Every planet is open!", sub = string.format("Hunt Celestial crew from %s", last.name),
			tint = Color3.fromRGB(150, 80, 230) }
	end

	local function show(goal: Goal)
		current = goal
		title.Text = goal.title
		sub.Text = goal.sub
		icon.Text = goal.icon
		track.Visible = goal.progress ~= nil
		if goal.progress then
			fill.Size = UDim2.fromScale(math.clamp(goal.progress, 0, 1), 1)
		end
		if goal.key ~= shownKey then
			-- Yeni hedef: renk değişip kart hafifçe zıplıyor
			shownKey = goal.key
			CardKit.tintCard(card, goal.tint)
			button.Size = UDim2.fromOffset(W * 0.9, H * 0.9)
			TweenService:Create(button, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(W, H) }):Play()
		end
	end

	button.Activated:Connect(function()
		local goal = current
		if goal and goal.onClick then
			goal.onClick()
		end
	end)

	local conns: { RBXScriptConnection } = {}
	local last = 0
	local showUntil = 0
	local nextShowAt = 0
	local lastKey = ""
	local fading = false
	local fadeTween: Tween? = nil
	local function fadeTo(target: number, seconds: number)
		if fadeTween then
			fadeTween:Cancel()
		end
		fadeTween = TweenService:Create(holder, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { GroupTransparency = target })
		fadeTween:Play()
	end
	table.insert(conns, RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < 0.5 then
			return
		end
		last = now
		-- Öğretici bitmeden hedef öğretici kartında; uzayda / kapsülde onların kartı
		local step = num("TutorialStep", 0)
		local tutorialDone = step >= #Config.Tutorial or step < 0
		local busy = player:GetAttribute("InSpace") == true or player:GetAttribute("InCapsule") == true
			or player:GetAttribute("SpaceGrabbed") ~= nil
		-- Ortada bir pencere açıkken (mağaza, envanter...) kart gizli: üstüne biniyordu
		local windowOpen = false
		for _, child in screen:GetChildren() do
			if child:IsA("GuiObject") and child.Visible and child.AbsoluteSize.X > 300 and child.AnchorPoint == Vector2.new(0.5, 0.5)
				and child.Position.X.Scale == 0.5 and child.Position.Y.Scale == 0.5 then
				windowOpen = true
				break
			end
		end
		local allowed = tutorialDone and not busy and not windowOpen and player:GetAttribute("Cinematic") ~= true
		if not allowed then
			holder.Visible = false
			fading = false
			return
		end
		local goal = pick()
		-- Yeni hedef ya da uzun süre görünmedi: SHOW_SECONDS göster
		if goal.key ~= lastKey or now >= nextShowAt then
			lastKey = goal.key
			showUntil = now + SHOW_SECONDS
			nextShowAt = now + REPEAT_SECONDS
			if not holder.Visible then
				holder.GroupTransparency = 1
				holder.Visible = true
			end
			fading = false
			fadeTo(0, 0.35)
		end
		if now >= showUntil then
			-- Süre doldu: sönerek kaybol
			if holder.Visible and not fading then
				fading = true
				fadeTo(1, 0.9)
				task.delay(0.95, function()
					if fading then
						holder.Visible = false
					end
				end)
			end
			return
		end
		show(goal)
		-- Olay şeridi açıkken hedef onun altında
		local eventOn = typeof(workspace:GetAttribute("EventId")) == "string" and workspace:GetAttribute("EventId") ~= ""
		holder.Position = UDim2.new(0.5, 0, 0, if eventOn then 82 else 10)
		-- Sıradaki olay (10 dk'dan yakınsa)
		local at = workspace:GetAttribute("NextEventAt")
		local name = workspace:GetAttribute("NextEventName")
		local left = if typeof(at) == "number" then at - Config.ServerNow() else math.huge
		if not eventOn and typeof(name) == "string" and left > 0 and left <= 600 then
			local t = math.floor(left)
			nextEvent.Text = string.format("⏱ %s in %d:%02d", name, t // 60, t % 60)
			nextEvent.Visible = true
		else
			nextEvent.Visible = false
		end
	end))

	return {
		Destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			holder:Destroy()
		end,
	}
end

return Objective
