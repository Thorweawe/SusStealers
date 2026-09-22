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

	-- Dokunmatikte düğme; masaüstünde görünmüyor
	if UserInputService.TouchEnabled then
		ContextActionService:SetTitle(ACTION, "RUN")
		ContextActionService:SetPosition(ACTION, UDim2.new(1, -140, 1, -180))
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
			ContextActionService:UnbindAction(ACTION)
			setActive(false)
		end,
	}
end

return Sprint
