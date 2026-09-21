--!strict
--[[
	Arayüzü gizleme düğmesi.

	Neden var: ekranda aynı anda harita, görev paneli, üs paneli, sıralama
	tablosu ve karakter kataloğu duruyor. Oynarken hepsi lazım değil ve
	çalmaya giderken görüşü kapatıyorlar.

	Yer: sağ üst, üs panelinin hemen solunda. Sohbet düğmesiyle aynı hizada
	duruyor ki oyuncu "arayüz düğmeleri burada" diye öğrensin.

	Ne gizliyor: kalabalık yapanlar (harita, görevler, üs paneli, sıralama,
	katalog, menü düğmeleri). Ne gizlemiyor: nakit, bildirimler, öğretici
	ve taşıma oku — bunlar oyuncunun o an ne yaptığını söyleyen şeyler,
	gizlenirse oyun anlaşılmaz oluyor.

	Nasıl çalışıyor: arayüz öğelerini ADIYLA buluyor, kendi kodlarına
	dokunmuyor. Listedeki bir öğe yoksa sessizce atlıyor, yani arkadaş
	tarafındaki bir yeniden adlandırma bunu kırmıyor, sadece o öğe
	gizlenmez olur.

	Kullanım (init.client.luau içinde, screen kurulduktan sonra, DİĞER
	panellerden SONRA çağır ki hepsini bulabilsin):
		local HudToggle = require(script.HudToggle)
		local hud = HudToggle.Create(screen)
]]

local UserInputService = game:GetService("UserInputService")

local HudToggle = {}

local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local PANEL = Color3.fromRGB(18, 20, 28)

--[[
	Gizlenecek arayüz öğelerinin adları.

	Sıralama önemsiz; bulunan gizleniyor, bulunmayan atlanıyor. Yeni bir
	panel eklerken adını buraya yazmak yeterli.
]]
local CLUTTER = {
	"Minimap",
	"Quests",
	"PlotPanel",
	"Leaderboard",
	"UnitIndex",
	"MenuDock",
	"MenuOverlay",
	"TransitPanel",
}

export type Toggle = {
	SetHidden: (hidden: boolean) -> (),
	IsHidden: () -> boolean,
	Destroy: () -> (),
}

function HudToggle.Create(screen: ScreenGui): Toggle
	local button = Instance.new("TextButton")
	button.Name = "HudToggle"
	button.AnchorPoint = Vector2.new(1, 0)
	-- Üs paneli sağda 260 geniş ve 24 boşluklu; düğme onun soluna düşüyor
	button.Position = UDim2.new(1, -292, 0, 20)
	button.Size = UDim2.new(0, 36, 0, 36)
	button.BackgroundColor3 = PANEL
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = INK
	button.Text = "👁"
	button.AutoButtonColor = false
	-- Gizlenenlerin üstünde kalsın; kendini gizleyen bir düğme geri
	-- gelemezdi
	button.ZIndex = 20
	button.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local tip = Instance.new("TextLabel")
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(1, 0)
	tip.Position = UDim2.new(1, -42, 0, 20)
	tip.Size = UDim2.new(0, 120, 0, 36)
	tip.BackgroundTransparency = 1
	tip.Font = Enum.Font.GothamMedium
	tip.TextSize = 12
	tip.TextXAlignment = Enum.TextXAlignment.Right
	tip.TextColor3 = MUTED
	tip.TextTransparency = 1
	tip.Text = "Hide UI  (H)"
	tip.ZIndex = 20
	tip.Parent = screen

	local hidden = false

	--[[
		Gizlenmeden önceki görünürlüğü hatırlıyoruz.

		Aksi halde geri açınca, o sırada zaten kapalı olan bir panel
		(örneğin oyuncunun katladığı görev paneli ya da hiç açılmamış menü)
		zorla açılırdı.
	]]
	local restore: { [Instance]: boolean } = {}

	local function apply()
		if hidden then
			table.clear(restore)
			for _, name in CLUTTER do
				local element = screen:FindFirstChild(name)
				if element and element:IsA("GuiObject") then
					restore[element] = element.Visible
					element.Visible = false
				end
			end
		else
			for element, wasVisible in restore do
				if element.Parent then
					(element :: GuiObject).Visible = wasVisible
				end
			end
			table.clear(restore)
		end

		button.Text = if hidden then "🚫" else "👁"
		button.TextColor3 = if hidden then MUTED else INK
		tip.Text = if hidden then "Show UI  (H)" else "Hide UI  (H)"
	end

	button.Activated:Connect(function()
		hidden = not hidden
		apply()
	end)

	button.MouseEnter:Connect(function()
		tip.TextTransparency = 0
	end)
	button.MouseLeave:Connect(function()
		tip.TextTransparency = 1
	end)

	--[[
		H kısayolu. processed kontrolü şart: oyuncu sohbete "h" yazarken
		arayüz kaybolmamalı.
	]]
	local input = UserInputService.InputBegan:Connect(function(io, processed)
		if processed or io.KeyCode ~= Enum.KeyCode.H then
			return
		end
		hidden = not hidden
		apply()
	end)

	return {
		SetHidden = function(value: boolean)
			hidden = value
			apply()
		end,
		IsHidden = function(): boolean
			return hidden
		end,
		Destroy = function()
			input:Disconnect()
			button:Destroy()
			tip:Destroy()
		end,
	}
end

return HudToggle
