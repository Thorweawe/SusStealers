--!strict
--[[
	Arayüzü gizleme düğmesi.

	Neden var: ekranda aynı anda harita, görev paneli, üs paneli, sıralama
	tablosu ve karakter kataloğu duruyor. Oynarken hepsi lazım değil ve
	çalmaya giderken görüşü kapatıyorlar.

	Yer: Roblox'un kendi üst şeridinde, mikrofonun sağında. Oyuncunun
	arayüz düğmelerini aradığı yer orası; oyunun kendi paneli araya
	karışmadan aynı sırada duruyor.

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

local GuiService = game:GetService("GuiService")
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
	--[[
		Düğme KENDİ katmanında duruyor.

		Sebep: normal ScreenGui'ler Roblox'un üst şeridinin altına itiliyor
		(GUI inset). Düğmeyi mikrofonun yanına, yani şeridin kendi hizasına
		koyabilmek için IgnoreGuiInset gerekiyor — ama onu ana HUD'a açmak
		bütün panelleri yukarı kaydırırdı. Ayrı katman ikisini de çözüyor.

		DisplayOrder yüksek: gizlediği panellerin üstünde kalmalı, yoksa
		kendini gizleyen bir düğme geri gelemezdi.
	]]
	local layer = Instance.new("ScreenGui")
	layer.Name = "SusStealersTopbar"
	layer.ResetOnSpawn = false
	layer.IgnoreGuiInset = true
	layer.DisplayOrder = 20
	layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	layer.Parent = screen.Parent

	--[[
		Roblox kendi üst şerit ikonlarının konumunu API ile vermiyor, o
		yüzden sabit. Şerit soldan sağa: Roblox logosu, sonra sohbet /
		balon / mikrofon ikonlarını taşıyan kapsül. Kapsül ~218'de bitiyor,
		düğme onun hemen sağına düşüyor.

		Sesli sohbet kapalıysa mikrofon çıkmıyor ve kapsül kısalıyor; o
		durumda düğmenin solunda biraz boşluk kalıyor, üst üste binmiyor.
	]]
	local SLOT_X = 228

	local topInset = GuiService:GetGuiInset()
	local barHeight = if topInset.Y > 0 then topInset.Y else 36
	local size = math.max(28, barHeight - 8)

	local button = Instance.new("TextButton")
	button.Name = "HudToggle"
	button.Position = UDim2.new(0, SLOT_X, 0, math.floor((barHeight - size) / 2))
	button.Size = UDim2.new(0, size, 0, size)
	button.BackgroundColor3 = PANEL
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = INK
	button.Text = "👁"
	button.AutoButtonColor = false
	button.Parent = layer

	local corner = Instance.new("UICorner")
	-- Roblox'un kendi ikonları yuvarlak; aynı dilde olsun
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	-- İpucu düğmenin ALTINDA: sağında yer yok, şeridin devamı geliyor
	local tip = Instance.new("TextLabel")
	tip.Name = "Tip"
	tip.Position = UDim2.new(0, SLOT_X - 30, 0, barHeight + 4)
	tip.Size = UDim2.new(0, 100, 0, 18)
	tip.BackgroundTransparency = 1
	tip.Font = Enum.Font.GothamMedium
	tip.TextSize = 12
	tip.TextXAlignment = Enum.TextXAlignment.Center
	tip.TextColor3 = MUTED
	tip.TextStrokeTransparency = 0.5
	tip.TextTransparency = 1
	tip.Text = "Hide UI  (H)"
	tip.Parent = layer

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
			layer:Destroy()
		end,
	}
end

return HudToggle
