--!strict
--[[
	Sınırlı etkinliğin karşılama kartı (2026-09-30, Config.LimitedEvent).

	Oyuncu oyuna girince (başlık ekranı kapanıp "WELCOME BACK" kartı da
	geçtikten sonra) oturumda bir kez, büyük bir kart:

	  ÖNCESİ (3 gün kala)  — "STARTS IN ..." + ne geleceği: para, yağmur,
	                         sınırlı şapkalar, ilk 10 ödülü (merak, randevu)
	  SÜRERKEN             — bitişe geri sayım (son gün: 2X), bugünkü giriş
	                         ödülü ve yarınki, sıradaki yıldız yağmuru, yıldız
	                         yolunda sıradaki ödül ("N kaldı"), ortak hedef

	Hedef açık olsun: oyuncu "bugün ne yapmalıyım" sorusunun cevabını tek
	bakışta görsün. Öğreticideki yeni oyuncuya çıkmıyor (kafası karışmasın;
	EVENT düğmesi zaten rayda). "OPEN EVENT" pencereyi açıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local CardKit = require(script.Parent.CardKit)
local SoundFX = require(script.Parent.SoundFX)

local EventIntro = {}

local player = Players.LocalPlayer

local Z = 82
local W, H = 500, 300
local TEASER_SECONDS = 3 * 86400

local screenRef: Instance? = nil
local openPanel: (() -> ())? = nil
local shown = false

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local d = s // 86400
	local h = (s % 86400) // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if d > 0 then
		return string.format("%dd %02d:%02d:%02d", d, h, m, sec)
	end
	return string.format("%02d:%02d:%02d", h, m, sec)
end

local function commas(n: number): string
	local out = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function numberAttr(name: string): number
	local v = player:GetAttribute(name)
	return if typeof(v) == "number" then v else 0
end

local function tutorialDone(): boolean
	local v = player:GetAttribute("TutorialStep")
	return typeof(v) == "number" and (v < 0 or v >= #Config.Tutorial)
end

--[[ Kartın satırları (her saniye yeniden): { emoji, metin }. ]]
local function rows(now: number): { { string } }
	local e = Config.LimitedEvent
	if now < e.startsAt then
		local reward = Config.GetCosmetic(e.leaderboard.reward)
		return {
			{ e.icon, string.format("Steal crewmates to earn %s - rarer crew, more %s", e.currency, e.currency) },
			{ e.emoji, string.format("%s twice an hour: catch falling stars!", e.shower.name) },
			{ "🎩", "LIMITED hats & trail in the event shop - never sold again" },
			{ "🏆", string.format("Top %d collectors win the %s", e.leaderboard.rewardTop, if reward then reward.name else "top prize") },
		}
	end
	local out = {}
	local days = numberAttr("EventDays")
	if days > 0 then
		local tomorrow = if (Config.DayIndex(now) + 1) * 86400 < e.endsAt
			then string.format("  ·  tomorrow +%d", Config.EventDailyAmount(days + 1)) else ""
		table.insert(out, { "📅", string.format("Day %d: +%d %s collected!%s", days, Config.EventDailyAmount(days), e.icon, tomorrow) })
	end
	for _, def in Config.Events do
		if def.id == "EventShower" then
			if workspace:GetAttribute("EventId") == "EventShower" then
				table.insert(out, { e.emoji, string.format("%s is ON! Fly into space now!", e.shower.name) })
			else
				table.insert(out, { e.emoji, string.format("%s in %s - catch falling stars", e.shower.name,
					clock(Config.GetNextEventStart(def, now) - now)) })
			end
		end
	end
	local step = Config.EventNextMilestone(numberAttr("EventMs"))
	if step then
		local left = step.at - numberAttr("EventEarned")
		table.insert(out, { "⭐", if left > 0
			then string.format("Next: %s in %d %s", step.label, left, e.icon)
			else string.format("%s waiting - free a podium!", step.label) })
	end
	local total = numberAttr("EventGlobal")
	local raw = workspace:GetAttribute("EventGlobal")
	total = if typeof(raw) == "number" then raw else total
	local tier = e.community.tiers[Config.EventCommunityReached(total) + 1]
	if tier then
		table.insert(out, { "🌌", string.format("All servers: %s / %s %s = %s for everyone", commas(total), commas(tier.at), e.icon, tier.label) })
	end
	while #out > 4 do
		table.remove(out)
	end
	return out
end

local function show()
	local screen = screenRef
	local e = Config.LimitedEvent
	if shown or not screen then
		return
	end
	shown = true

	local holder = Instance.new("Frame")
	holder.Name = "EventIntro"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(W, H)
	holder.BackgroundTransparency = 1
	holder.ZIndex = Z
	holder.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder
	-- Telefonda (yatay, kısa ekran) sığsın
	local camera = workspace.CurrentCamera
	local fit = if camera then math.min(1, (camera.ViewportSize.Y - 40) / H, (camera.ViewportSize.X - 40) / W) else 1

	local card = CardKit.hero(holder, e.color2, UDim2.fromScale(1, 1), Z, UDim2.fromScale(0.5, 0.2), 620)
	local title = CardKit.bold(card, e.emoji .. " " .. e.name, 36, CardKit.YELLOW, Z + 4, 5)
	title.Position = UDim2.fromOffset(0, 10)
	title.Size = UDim2.new(1, 0, 0, 42)
	CardKit.fit(title, 36, 20)
	local timer = CardKit.bold(card, "", 20, Color3.new(1, 1, 1), Z + 4, 3)
	timer.Position = UDim2.fromOffset(0, 52)
	timer.Size = UDim2.new(1, 0, 0, 24)

	local lines: { { icon: TextLabel, text: TextLabel } } = {}
	for i = 1, 4 do
		local y = 84 + (i - 1) * 32
		local icon = CardKit.bold(card, "", 22, Color3.new(1, 1, 1), Z + 4, 0)
		icon.Position = UDim2.fromOffset(18, y)
		icon.Size = UDim2.fromOffset(30, 28)
		local text = CardKit.bold(card, "", 16, Color3.fromRGB(235, 240, 255), Z + 4, 2)
		text.Position = UDim2.fromOffset(54, y + 2)
		text.Size = UDim2.new(1, -72, 0, 24)
		text.TextXAlignment = Enum.TextXAlignment.Left
		CardKit.fit(text, 16, 10)
		table.insert(lines, { icon = icon, text = text })
	end

	local running = true
	local function redraw()
		local now = Config.ServerNow()
		if now < e.startsAt then
			timer.Text = "STARTS IN " .. clock(e.startsAt - now) .. "  ·  DON'T MISS IT!"
		elseif Config.IsEventFinalDay(now) then
			timer.Text = string.format("FINAL DAY! %dX %s  ·  ENDS IN %s", e.finalDayMul, e.icon, clock(e.endsAt - now))
			timer.TextColor3 = Color3.fromRGB(255, 150, 120)
		else
			timer.Text = "LIMITED EVENT  ·  ENDS IN " .. clock(e.endsAt - now)
		end
		local list = rows(now)
		for i, line in lines do
			local row = list[i]
			line.icon.Text = if row then row[1] else ""
			line.text.Text = if row then row[2] else ""
		end
	end
	redraw()
	task.spawn(function()
		while running and holder.Parent do
			task.wait(1)
			if running then
				redraw()
			end
		end
	end)

	local function close()
		running = false
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.delay(0.21, function()
			holder:Destroy()
		end)
	end
	local teaser = Config.ServerNow() < e.startsAt
	local open = CardKit.button(card, UDim2.fromOffset(220, 58), Z + 5, 22, CardKit.GREEN)
	open.holder.AnchorPoint = Vector2.new(0.5, 1)
	open.holder.Position = UDim2.new(0.5, -84, 1, -14)
	open.set(if teaser then "SEE REWARDS" else "OPEN EVENT", CardKit.GREEN)
	open.button.Activated:Connect(function()
		SoundFX.Event("reward", false)
		close()
		if openPanel then
			openPanel()
		end
	end)
	local later = CardKit.button(card, UDim2.fromOffset(140, 58), Z + 5, 20, CardKit.GREY)
	later.holder.AnchorPoint = Vector2.new(0.5, 1)
	later.holder.Position = UDim2.new(0.5, 110, 1, -14)
	later.set(if teaser then "OK!" else "LET'S GO", CardKit.GREY)
	later.button.Activated:Connect(close)

	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	SoundFX.Event("welcome", false)
end

function EventIntro.Start(screen: Instance, open: () -> ())
	screenRef = screen
	openPanel = open
end

--[[ Başlık ekranı kapandı: uygun zamansa kartı göster (oturumda bir kez). ]]
function EventIntro.Ready()
	task.spawn(function()
		local e = Config.LimitedEvent
		local now = Config.ServerNow()
		if now < e.startsAt - TEASER_SECONDS or now >= e.endsAt then
			return
		end
		-- Profil gelsin (öğretici durumu, giriş günü)
		local waited = 0
		while (player:GetAttribute("TutorialStep") == nil or screenRef == nil) and waited < 20 do
			task.wait(0.5)
			waited += 0.5
		end
		if not tutorialDone() then
			return
		end
		task.wait(1.5)
		-- "WELCOME BACK" kartı açıksa önce o kapansın
		local screen = screenRef
		waited = 0
		while screen and screen:FindFirstChild("WelcomeBack") and waited < 60 do
			task.wait(0.5)
			waited += 0.5
		end
		task.wait(0.4)
		show()
	end)
end

return EventIntro
