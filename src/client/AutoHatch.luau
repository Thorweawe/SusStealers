--!strict
--[[
	Otomatik yumurta açma — istemci döngüsü.

	Oyuncu bir yumurtada AUTO'yu açınca her açılış bittiğinde bir sonrakini
	istiyor, ta ki oyuncu durdurana ya da parası bitene kadar.

	Döngü İSTEMCİDE ama hız sunucuda: PetService her açılıştan sonra
	Config.HatchDuration kadar yeni isteği kabul etmiyor. Yani otomatik
	açma elle basmaktan hızlı olamıyor; tek farkı oyuncunun basmak zorunda
	kalmaması. Grup şartı da sunucuda (PetService.CanAutoHatch).

	Ekranın üstünde küçük bir şerit: hangi yumurta, kaçlı, STOP düğmesi.
	Açık olduğu unutulmasın — yoksa oyuncu parasının nereye gittiğini
	anlamazdı.

	Durma sebepleri:
	  - oyuncu STOP'a basıyor ya da aynı yumurtada AUTO'ya tekrar basıyor
	  - parası bir açılışa yetmiyor (istemci Cash niteliğinden görüyor)
	  - arka arkaya iki istek sonuçsuz kalıyor (sunucu reddetti: grup yok,
	    pass yok, envanter dolu) — sunucunun gönderdiği bildirim sebebi
	    zaten söylüyor
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local AutoHatch = {}

local player = Players.LocalPlayer

export type Handle = {
	Toggle: (eggId: string, count: number) -> (),
	Stop: () -> (),
	Current: () -> (string?, number),
	Changed: BindableEvent,
	Destroy: () -> (),
}

function AutoHatch.Create(screen: ScreenGui, isPlaying: () -> boolean): Handle
	local hatchRemote = Net.Get("PetHatch")
	local changed = Instance.new("BindableEvent")

	local eggId: string? = nil
	local count = 1
	local nextFire = 0
	local waitingSince: number? = nil
	local failures = 0

	-- ─── Şerit ──────────────────────────────────────────────────────────────

	local bar = Instance.new("Frame")
	bar.Name = "AutoHatchBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 10)
	bar.Size = UDim2.fromOffset(330, 44)
	bar.BackgroundColor3 = UiKit.SHELL_DEEP
	bar.BackgroundTransparency = 0.08
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.ZIndex = 60
	bar.Parent = screen
	UiKit.Corner(bar, 22)
	UiKit.Stroke(bar, UiKit.CREW.PINK, 1.6, 0.2)

	local slot = Instance.new("Frame")
	slot.Position = UDim2.fromOffset(8, 6)
	slot.Size = UDim2.fromOffset(32, 32)
	slot.BackgroundTransparency = 1
	slot.ZIndex = 61
	slot.Parent = bar
	UiKit.Egg(slot, 28, UiKit.CREW.PINK:Lerp(Color3.new(1, 1, 1), 0.4))

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(46, 0)
	label.Size = UDim2.new(1, -140, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = UiKit.INK
	label.ZIndex = 61
	label.Parent = bar

	local holder, stop = UiKit.Raised(bar, "Stop", UiKit.CREW.RED, UDim2.fromOffset(80, 32), 10)
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -8, 0.5, 0)
	holder.ZIndex = 61
	local stopText = Instance.new("TextLabel")
	stopText.Size = UDim2.fromScale(1, 1)
	stopText.BackgroundTransparency = 1
	stopText.Font = Enum.Font.GothamBlack
	stopText.TextSize = 13
	stopText.TextColor3 = Color3.new(1, 1, 1)
	stopText.TextStrokeTransparency = 0.5
	stopText.Text = "STOP"
	stopText.ZIndex = 64
	stopText.Parent = stop

	local function stopAuto()
		if eggId == nil then
			return
		end
		eggId = nil
		waitingSince = nil
		failures = 0
		bar.Visible = false
		changed:Fire()
	end

	local function start(id: string, amount: number)
		local egg = Config.GetEgg(id)
		if not egg then
			return
		end
		eggId = id
		count = amount
		failures = 0
		waitingSince = nil
		nextFire = 0
		label.Text = string.format("AUTO HATCH  ·  %s%s", egg.name, if amount > 1 then " x" .. amount else "")
		bar.Visible = true
		changed:Fire()
	end

	stop.MouseButton1Click:Connect(stopAuto)

	-- Başarılı açılış: sayaç sıfırlanıyor, bir sonraki istek süre dolunca
	local hatched = Net.Get("PetHatched").OnClientEvent:Connect(function(_, source)
		if source == "egg" then
			waitingSince = nil
			failures = 0
		end
	end)

	local elapsed = 0
	local tick = RunService.Heartbeat:Connect(function(delta)
		elapsed += delta
		if elapsed < 0.2 or eggId == nil then
			return
		end
		elapsed = 0
		local now = os.clock()

		-- Cevapsız kalan istek: sunucu reddetti
		if waitingSince and now - waitingSince > 2 then
			waitingSince = nil
			failures += 1
			if failures >= 2 then
				stopAuto()
				return
			end
		end

		if waitingSince or isPlaying() or now < nextFire then
			return
		end

		local egg = Config.GetEgg(eggId :: string)
		local cash = player:GetAttribute("Cash")
		if not egg or typeof(cash) ~= "number" or cash < egg.price * count then
			stopAuto()
			return
		end

		hatchRemote:FireServer(eggId, count, true)
		waitingSince = now
		nextFire = now + Config.HatchDuration + 0.2
	end)

	return {
		Toggle = function(id: string, amount: number)
			if eggId == id and count == amount then
				stopAuto()
			else
				start(id, amount)
			end
		end,
		Stop = stopAuto,
		Current = function(): (string?, number)
			return eggId, count
		end,
		Changed = changed,
		Destroy = function()
			hatched:Disconnect()
			tick:Disconnect()
			bar:Destroy()
			changed:Destroy()
		end,
	}
end

return AutoHatch
