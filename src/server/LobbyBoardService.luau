--!strict
--[[
	Lobi tabelası (2026-09-29, Config.LiveOps): kafeteryanın güney duvarında,
	üç sıralama panosunun ÜSTÜNDE geniş bir şerit. Üç bölüm:

	  NEXT UPDATE  — sıradaki güncellemeye geri sayım + ne geleceği
	                 ("randevu": oyuncu o gün geri gelsin)
	  LIKE GOAL    — beğeni hedefi ve ödülü (topluluk hedefi; sayı elle,
	                 Roblox beğeni sayısını oyun sunucusuna vermiyor)
	  FAVORITE     — favoriye ekle, güncellemede haberin olsun

	Dünyaya çalışma anında kuruluyor (yer Team Create'te elle kurulan
	haritaya dokunmuyor). Geri sayım saniyede bir sunucuda yazılıyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local LobbyBoardService = {}

-- Güney duvarı: panolar x 135..273, üstleri y≈29.8; duvar yüzü z≈408.8
local CENTER = Vector3.new(204, 36.4, 408.25)
local SIZE = Vector3.new(130, 8, 0.3)
local PPS = 24

local DARK = Color3.fromRGB(14, 16, 32)
local OUTLINE = Color3.fromRGB(10, 12, 24)

local countdown: TextLabel? = nil
local countdownTitle: TextLabel? = nil
local countdownSub: TextLabel? = nil

local function label(parent: Instance, text: string, size: number, color: Color3, order: number): TextLabel
	local t = Instance.new("TextLabel")
	t.LayoutOrder = order
	t.Size = UDim2.new(1, -20, 0, size * 1.15)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextSize = size
	t.TextColor3 = color
	t.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = OUTLINE
	stroke.Parent = t
	t.Parent = parent
	return t
end

local function column(gui: SurfaceGui, index: number, accent: Color3): Frame
	local col = Instance.new("Frame")
	col.Size = UDim2.new(1 / 3, 0, 1, 0)
	col.Position = UDim2.fromScale((index - 1) / 3, 0)
	col.BackgroundTransparency = 1
	col.Parent = gui
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 2)
	list.Parent = col
	if index > 1 then
		local rule = Instance.new("Frame")
		rule.Size = UDim2.new(0, 4, 0.7, 0)
		rule.Position = UDim2.new((index - 1) / 3, -2, 0.15, 0)
		rule.BackgroundColor3 = accent
		rule.BorderSizePixel = 0
		rule.Parent = gui
	end
	return col
end

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

--[[ Geri sayım metni (testler de çağırıyor). ]]
function LobbyBoardService.CountdownText(now: number): string
	local at = Config.LiveOps.nextUpdate.at
	if at <= 0 then
		return "SOON!"
	end
	if now >= at then
		return "OUT NOW!"
	end
	return clock(at - now)
end

local function build()
	local old = workspace:FindFirstChild("LobbyUpdateBoard")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "LobbyUpdateBoard"

	local cf = CFrame.lookAt(CENTER, CENTER + Vector3.new(0, 0, -1))
	local frame = Instance.new("Part")
	frame.Name = "BoardGlow"
	frame.Size = SIZE + Vector3.new(1.2, 1.2, 0)
	frame.CFrame = cf * CFrame.new(0, 0, 0.2)
	frame.Color = Color3.fromRGB(255, 200, 60)
	frame.Material = Enum.Material.Neon
	frame.Anchored = true
	frame.CanCollide = false
	frame.CanQuery = false
	frame.CanTouch = false
	frame.CastShadow = false
	frame.Parent = model

	local board = Instance.new("Part")
	board.Name = "Board"
	board.Size = SIZE
	board.CFrame = cf
	board.Color = DARK
	board.Material = Enum.Material.SmoothPlastic
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.CastShadow = false
	board.Parent = model

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Parent = board

	local live = Config.LiveOps
	local c1 = column(gui, 1, Color3.fromRGB(80, 200, 255))
	countdownTitle = label(c1, "NEXT UPDATE", 40, Color3.fromRGB(120, 220, 255), 1)
	countdown = label(c1, LobbyBoardService.CountdownText(os.time()), 64, Color3.fromRGB(255, 225, 70), 2)
	countdownSub = label(c1, live.nextUpdate.title, 32, Color3.new(1, 1, 1), 3)

	local c2 = column(gui, 2, Color3.fromRGB(80, 200, 255))
	label(c2, "👍 LIKE GOAL", 40, Color3.fromRGB(130, 255, 140), 1)
	label(c2, string.format("%d LIKES", live.likeGoal.goal), 64, Color3.fromRGB(255, 225, 70), 2)
	label(c2, "= " .. live.likeGoal.reward, 32, Color3.new(1, 1, 1), 3)

	local c3 = column(gui, 3, Color3.fromRGB(80, 200, 255))
	label(c3, "⭐ FAVORITE", 40, Color3.fromRGB(255, 190, 90), 1)
	label(c3, "THE GAME", 64, Color3.fromRGB(255, 225, 70), 2)
	label(c3, "to get update alerts!", 32, Color3.new(1, 1, 1), 3)

	model.Parent = workspace
end

--[[
	İlk sütun: sınırlı etkinlik bir haftadan yakınsa ya da sürüyorsa onun geri
	sayımı (başlık, süre, alt satır), yoksa sıradaki güncelleme. nil = güncelleme.
]]
function LobbyBoardService.EventHeadline(now: number): (string?, string?, string?)
	local e = Config.LimitedEvent
	if now < e.startsAt and e.startsAt - now <= 7 * 86400 then
		return "🎃 " .. e.name, "IN " .. clock(e.startsAt - now), "LIMITED EVENT · CANDY SHOP"
	elseif Config.IsLimitedEventActive(now) then
		return "🎃 " .. e.name, "ENDS " .. clock(e.endsAt - now), "HAUNTED CREW · LIMITED HATS"
	end
	return nil, nil, nil
end

function LobbyBoardService.Start()
	build()
	task.spawn(function()
		while true do
			task.wait(1)
			local label = countdown
			if label and label.Parent then
				local now = os.time()
				local title, time, sub = LobbyBoardService.EventHeadline(now)
				local text = time or LobbyBoardService.CountdownText(now)
				if label.Text ~= text then
					label.Text = text
				end
				local wantTitle = title or "NEXT UPDATE"
				local wantSub = sub or Config.LiveOps.nextUpdate.title
				if countdownTitle and countdownTitle.Text ~= wantTitle then
					countdownTitle.Text = wantTitle
					countdownTitle.TextColor3 = if title then Config.LimitedEvent.color else Color3.fromRGB(120, 220, 255)
				end
				if countdownSub and countdownSub.Text ~= wantSub then
					countdownSub.Text = wantSub
				end
			end
		end
	end)
end

return LobbyBoardService
