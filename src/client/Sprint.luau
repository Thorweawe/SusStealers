--!strict
--[[
	Shift ile koşma.

	Burada yalnızca TUŞ dinleniyor; hızı sunucu belirliyor
	(StealService.SetSprinting) ve karakter taşırken yok sayıyor. Çalmanın
	riski taşırken yavaş kalmak; koşmaya izin vermek o riski silerdi.

	Telefonda Shift yok, o yüzden ekranda bir düğme de var. Roblox'un
	kendi zıplama düğmesinin yanında duruyor.

	Kullanım (init.client.luau içinde):
		mountPanel("Sprint", function() Sprint.Create(screen) end)
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Sprint = {}

local ACTION = "SusStealersSprint"

export type Handle = {
	Destroy: () -> (),
}

function Sprint.Create(screen: ScreenGui): Handle
	local remote = Net.Get("Sprint")
	local active = false

	--[[
		Sunucuya yalnızca DEĞİŞİMDE haber veriyoruz. Tuş basılı dururken
		her karede paket yollamak ağı boşuna dolduruyordu.
	]]
	local function setActive(value: boolean)
		if active == value then
			return
		end
		active = value
		remote:FireServer(value)
	end

	--[[
		ContextActionService kullanıyoruz çünkü hem tuşu hem de telefon
		düğmesini tek yerden veriyor; ayrıca sohbete yazarken tetiklenmiyor.
	]]
	local function onAction(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			setActive(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setActive(false)
		end
		return Enum.ContextActionResult.Pass
	end

	ContextActionService:BindAction(
		ACTION, onAction, true,
		Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3
	)

	--[[
		Dokunmatikte düğme; masaüstünde görünmüyor. Yeri Roblox'un ZIPLAMA
		düğmesinin SOL ALTI: sabit bir konumdayken ekran boyuna göre zıplama
		düğmesinin üstüne biniyordu ("iç içe geçmiş"). Zıplama düğmesinin
		gerçek yerinden hesaplanıyor; ekran dönünce / boyut değişince yeniden.
	]]
	local placeConnection: RBXScriptConnection? = nil
	if UserInputService.TouchEnabled then
		ContextActionService:SetTitle(ACTION, "RUN")
		ContextActionService:SetPosition(ACTION, UDim2.new(1, -140, 1, -180))

		local function placeRun(): boolean
			local button = ContextActionService:GetButton(ACTION)
			local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
			local touch = pg and pg:FindFirstChild("TouchGui")
			local jump = touch and touch:FindFirstChild("JumpButton", true)
			if not (button and jump and jump:IsA("GuiObject") and button.Parent and button.Parent:IsA("GuiObject")) then
				return false
			end
			local frame = button.Parent :: GuiObject
			local size = button.AbsoluteSize
			local jp, js = jump.AbsolutePosition, jump.AbsoluteSize
			local viewport = workspace.CurrentCamera.ViewportSize
			-- Sol-alt: sağ kenarı zıplamanın solunda, alt kenarı zıplamanın altından biraz aşağıda
			local x = jp.X - 10 - size.X
			local y = math.min(jp.Y + js.Y - size.Y * 0.55, viewport.Y - size.Y - 6)
			local rel = Vector2.new(x, y) - frame.AbsolutePosition
			ContextActionService:SetPosition(ACTION, UDim2.fromOffset(rel.X, rel.Y))
			return true
		end
		task.spawn(function()
			for _ = 1, 20 do
				if placeRun() then
					break
				end
				task.wait(0.5)
			end
		end)
		placeConnection = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.delay(0.3, placeRun)
		end)
	end

	--[[
		Pencere odağı giderken bayrağı düşürüyoruz. Alt+Tab yapan oyuncu
		Shift'i bıraktığında olay gelmiyor ve sunucuda sonsuza kadar
		koşuyor kalıyordu.
	]]
	local focusLost = UserInputService.WindowFocusReleased:Connect(function()
		setActive(false)
	end)

	return {
		Destroy = function()
			focusLost:Disconnect()
			if placeConnection then
				placeConnection:Disconnect()
			end
			ContextActionService:UnbindAction(ACTION)
			setActive(false)
		end,
	}
end

return Sprint
