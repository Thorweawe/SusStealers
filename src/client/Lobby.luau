--!strict
-- Lobi işlevleri: ışınlanma arayüzü. (Sıralama panolarını sunucu dolduruyor.)
--
-- Ped yerine arayüz: üstüne basınca ışınlanan bir ped, yanından geçerken
-- kazara tetikleniyor ve sinir bozucu oluyor. Kürsüye yaklaşınca açılan
-- panelde ne olduğunu okuyup karar veriyorsun.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local OwnPlot = require(script.Parent.OwnPlot)

local Lobby = {}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(18, 20, 28)
local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local NEON = Color3.fromRGB(80, 220, 255)
local WARN = Color3.fromRGB(255, 190, 90)

--[[
	Kürsüye kaç stud yaklaşınca panel açılsın.

	22'ydi ve lobi büyüyünce (230x156) çok geniş kalıyordu: oyuncu kapıdan
	girer girmez "RETURN TO MY BASE" beliriyor, kürsünün yanına gitmesine
	gerek kalmıyordu. Kürsünün kaidesi 16 stud; 11 onun hemen çevresi
	demek, yani gerçekten yanına gelmek gerekiyor.
]]
local REACH = 11

export type Hub = {
	Update: () -> (),
}

function Lobby.Create(screen: ScreenGui): Hub
	-- ─── Işınlanma paneli ───────────────────────────────────────────────────

	local panel = Instance.new("Frame")
	panel.Name = "TransitPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -150)
	panel.Size = UDim2.fromOffset(300, 108)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -32, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 12
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = MUTED
	title.Text = "TRANSIT"
	title.Parent = panel

	local button = Instance.new("TextButton")
	button.Name = "Teleport"
	button.Position = UDim2.fromOffset(16, 32)
	button.Size = UDim2.new(1, -32, 0, 40)
	button.BackgroundColor3 = NEON
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = Color3.fromRGB(10, 18, 24)
	button.Text = "RETURN TO MY BASE"
	button.AutoButtonColor = true
	button.Parent = panel

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	local note = Instance.new("TextLabel")
	note.Position = UDim2.fromOffset(16, 76)
	note.Size = UDim2.new(1, -32, 0, 22)
	note.BackgroundTransparency = 1
	note.Font = Enum.Font.GothamMedium
	note.TextSize = 12
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = MUTED
	note.Text = ""
	note.Parent = panel


	local function carrying(): boolean
		local char = player.Character
		return char ~= nil and char:FindFirstChild("CarriedUnit") ~= nil
	end

	--[[
		Masanın bankında oturan oyuncuyu ışınlanmadan önce kaldırır.

		ESKİ HATA: acil durum masasının bankına oturup "RETURN TO MY BASE"
		deyince oturduğun koltuk da seninle geliyordu. Oturmak karakteri
		koltuğa kaynakla (SeatWeld) bağlıyor; PivotTo kaynaklı her şeyi,
		koltuk dahil, birlikte taşıyor.

		Sit = false kalkışı başlatıyor, kaynağı sunucu siliyor; silinmesi
		bir ağ turu sürüyor. En fazla bir saniye bekleniyor, kaynak hâlâ
		duruyorsa yerelde koparılıyor ki koltuk hiçbir koşulda gelmesin.
	]]
	local function standUp(char: Model)
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		if not (humanoid and seat) then
			return
		end
		-- Zıplamak koltuktan kalkmanın motorun tanıdığı yolu; Sit tek başına her zaman yetmiyor
		humanoid.Sit = false
		humanoid.Jump = true

		local deadline = os.clock() + 1
		while os.clock() < deadline do
			if humanoid.SeatPart == nil and not seat:FindFirstChild("SeatWeld") then
				return
			end
			task.wait()
		end

		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end

	local teleporting = false

	button.Activated:Connect(function()
		--[[
			Taşırken ışınlanma YOK. Çalmanın bütün riski üsse kadar yürümekte;
			ışınlanmak o riski sıfırlar ve çalmayı bedavaya çevirir. Config'de
			CarryTravelTolerance da tam bu yüzden var — sunucu zaten yürüme
			süresini denetliyor, burada da kapıyı kapatıyoruz.
		]]
		if carrying() then
			note.Text = "Can't teleport while carrying"
			note.TextColor3 = WARN
			return
		end

		local plot = OwnPlot.Get()
		local base = plot and plot:FindFirstChild("Base")
		local char = player.Character
		if not (base and base:IsA("BasePart") and char) then
			note.Text = "You don't own a base yet"
			note.TextColor3 = WARN
			return
		end

		-- Koltuktan kalkış bekleyebilir: art arda tıklama iki kez ışınlamasın
		if teleporting then
			return
		end
		teleporting = true
		standUp(char)
		teleporting = false
		if player.Character ~= char then
			return
		end

		char:PivotTo(CFrame.new(base.Position + Vector3.new(0, 5, 0)))
		note.Text = ""
	end)

	-- ─── Döngü ──────────────────────────────────────────────────────────────

	local function update()
		-- Kürsüye yakın mıyız
		local decor = workspace:FindFirstChild("Decor")
		local pad = decor and decor:FindFirstChild("TeleportPad")
		local column = pad and pad:FindFirstChild("PadColumn")
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")

		if column and column:IsA("BasePart") and root and root:IsA("BasePart") then
			local near = (root.Position - column.Position).Magnitude <= REACH
			panel.Visible = near
			if near and carrying() then
				note.Text = "Can't teleport while carrying"
				note.TextColor3 = WARN
			elseif near and note.TextColor3 == WARN then
				note.Text = ""
			end
		else
			panel.Visible = false
		end
		-- Panoları artık sunucu dolduruyor (GlobalBoardService, küresel)
	end

	return { Update = update }
end

return Lobby
