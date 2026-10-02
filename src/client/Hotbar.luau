--!strict
--[[
	Ekipman çubuğu: Roblox'un hazır sırt çantası çubuğunun yerine.

	NEDEN: hazır çubuk düz gri kutulardı ("Slap Glove / Speed Coil"
	yazıları) ve ekranın tam ortasında her pencerenin ÜSTÜNE
	biniyordu — Rebirth penceresinin satın alma düğmesi bile altında
	kalıyordu. Bu çubuk arayüzün geri kalanıyla aynı kabartma dilinde,
	ekipmanın resmini gösteriyor ve pencerelerin ALTINDA kalıyor.

	Davranış hazır çubukla aynı: tıkla ya da 1-9'a bas → kuşan; kuşanılıysa
	bırak. Araçlar sunucudan geliyor (GearService); burası yalnızca gösterip
	kuşandırıyor.

	KULLANIM GERİ BİLDİRİMİ ("itemleri kullanırken kullandığımız belli
	olmuyor"): kuşanılı ekipmanın adı ve ne yapılacağı çubuğun üstünde
	yazıyor; kullanınca yuva zıplıyor, üstüne karanlık bir perde iniyor ve
	bekleme bitene kadar saniye sayıyor. Beklerken basınca yuva sallanıyor
	ve "READY IN 3s" diyor. Kullanım anı sunucunun GearFX "use" yankısından
	alınıyor: yalnızca gerçekten kullanıldıysa (bekleme dolmuşsa) geliyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CardKit = require(script.Parent.CardKit)
local UiKit = require(script.Parent.UiKit)

local Hotbar = {}

export type Bar = {
	Destroy: () -> (),
}

local SLOT = 62
local GAP = 8
local ACCENT = Color3.fromRGB(80, 96, 116)

local KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

function Hotbar.Create(screen: ScreenGui): Bar
	local player = Players.LocalPlayer

	-- Hazır çubuğu kapat: oturumun ilk anında çağrı başarısız olabiliyor
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)

	local bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromOffset(SLOT, SLOT + 4)
	bar.BackgroundTransparency = 1
	bar.ZIndex = 2
	bar.Visible = false
	bar.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = bar

	local tools: { Tool } = {}
	local connections: { RBXScriptConnection } = {}

	-- ─── Kullanım göstergesi ────────────────────────────────────────────
	type SlotView = { button: GuiObject, scale: UIScale, shade: Frame, timer: TextLabel }
	local slots: { [string]: SlotView } = {}
	local cooldownUntil: { [string]: number } = {}
	local cooldownTotal: { [string]: number } = {}

	-- Kuşanılı ekipmanın adı + ne yapılacağı, çubuğun hemen üstünde
	local hint = CardKit.bold(screen, "", 20, CardKit.WHITE, 4, 2.5)
	hint.Name = "GearHint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -(14 + SLOT + 4 + 8))
	hint.Size = UDim2.fromOffset(460, 26)
	CardKit.fit(hint, 20, 12)
	hint.Visible = false

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local USE_WORD = if touch then "TAP TO USE" else "CLICK TO USE"

	local function equippedTool(): Tool?
		local char = player.Character
		return char and char:FindFirstChildOfClass("Tool")
	end

	local function gearOf(tool: Tool?): Config.GearDef?
		local id = tool and tool:GetAttribute("GearId")
		return if typeof(id) == "string" then Config.GetGear(id) else nil
	end

	local function refreshHint()
		--[[
			2026-09-27: kullanıcı "elime alınca altta yazmasın" dedi. Adı ve
			"CLICK TO USE" artık yok; yalnızca bekleme sürerken basılırsa
			"READY IN" görünüyor (yuvadaki perde zaten gösteriyor ama basınca
			neden olmadığı anlaşılsın).
		]]
		local def = gearOf(equippedTool())
		local left = if def then (cooldownUntil[def.id] or 0) - os.clock() else 0
		hint.Visible = def ~= nil and bar.Visible and left > 0 and def.kind ~= "speed"
		if not def then
			return
		end
		local left = (cooldownUntil[def.id] or 0) - os.clock()
		if def.kind == "speed" then
			hint.Text = string.format('%s  <font color="#7CFF5B">FASTER WHILE HELD</font>', def.name:upper())
		elseif left > 0 then
			hint.Text = string.format('%s  <font color="#FFB43C">READY IN %ds</font>', def.name:upper(), math.ceil(left))
		else
			hint.Text = string.format('%s  <font color="#7CFF5B">%s</font>', def.name:upper(), USE_WORD)
		end
	end

	local function pop(view: SlotView, big: number)
		view.scale.Scale = big
		TweenService:Create(view.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	local function shake(view: SlotView)
		local b = view.button
		task.spawn(function()
			for _, x in { -6, 6, -4, 4, 0 } do
				b.Position = UDim2.fromOffset(x, 0)
				task.wait(0.04)
			end
		end)
		view.timer.TextColor3 = Color3.fromRGB(255, 90, 90)
		task.delay(0.3, function()
			view.timer.TextColor3 = CardKit.WHITE
		end)
	end

	-- Sunucu kullanımı onayladı: bekleme başlasın, yuva zıplasın
	table.insert(connections, Net.Get("GearFX").OnClientEvent:Connect(function(kind, character, gearId)
		if kind ~= "use" or character ~= player.Character or typeof(gearId) ~= "string" then
			return
		end
		local def = Config.GetGear(gearId)
		if not def then
			return
		end
		-- Quick Recharge yükseltmesiyle kısalmış bekleme
		local cooldown = Config.GetGearCooldown(player, def.cooldown)
		cooldownTotal[gearId] = cooldown
		cooldownUntil[gearId] = os.clock() + cooldown
		local view = slots[gearId]
		if view then
			pop(view, 1.25)
		end
	end))

	-- Beklerken basınca: neden olmadığını göster
	local boundTools: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local function bindTool(tool: Tool)
		if boundTools[tool] then
			return
		end
		boundTools[tool] = true
		tool.Activated:Connect(function()
			local def = gearOf(tool)
			if not def then
				return
			end
			local view = slots[def.id]
			if view and (cooldownUntil[def.id] or 0) > os.clock() then
				shake(view)
			end
		end)
	end

	--[[
		Öğretici kartı (TutorialUI, sol altta nakdin sağında) açıkken çubuğun
		ilk yuvaları kartın altında kalıyordu: çubuk kartın sağına kayıyor.
	]]
	local shift = 0
	local function avoidTutorial()
		local tut = screen:FindFirstChild("Tutorial")
		local want = 0
		if tut and tut:IsA("GuiObject") and tut.Visible and bar.Size.X.Offset > 0 then
			local k = bar.AbsoluteSize.X / bar.Size.X.Offset
			if k > 0 then
				local tutRight = tut.AbsolutePosition.X + tut.AbsoluteSize.X
				local leftUnshifted = bar.AbsolutePosition.X - shift * k
				want = math.max(0, (tutRight + 12 * k - leftUnshifted) / k)
			end
		end
		if math.abs(want - shift) > 0.5 then
			shift = want
			bar.Position = UDim2.new(0.5, shift, 1, -14)
			hint.Position = UDim2.new(0.5, shift, 1, -(14 + SLOT + 4 + 8))
		end
	end

	-- Perde ve sayaç her karede; bitince yuva "hazır" diye bir kez zıplıyor
	table.insert(connections, RunService.RenderStepped:Connect(function()
		avoidTutorial()
		local now = os.clock()
		for id, view in slots do
			local left = (cooldownUntil[id] or 0) - now
			if left > 0 then
				local total = math.max(0.1, cooldownTotal[id] or 1)
				view.shade.Visible = true
				view.shade.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
				view.timer.Visible = true
				view.timer.Text = tostring(math.ceil(left))
			elseif view.shade.Visible then
				view.shade.Visible = false
				view.timer.Visible = false
				cooldownUntil[id] = nil
				pop(view, 1.15)
			end
		end
		refreshHint()
	end))

	local function humanoid(): Humanoid?
		local char = player.Character
		return char and char:FindFirstChildOfClass("Humanoid")
	end

	local function toggle(tool: Tool)
		local hum = humanoid()
		if not hum then
			return
		end
		if tool.Parent == player.Character then
			hum:UnequipTools()
		else
			hum:EquipTool(tool)
		end
	end

	--[[
		Gezegen savunması (2026-10-01, Batur: "uzayda kullandığımız gear'lar
		gezegene gelmesin"): gezegendeyken (DefensePlanet niteliği) çubukta
		yalnızca savunma aletleri — seçilen crewmate'ler (DefenseCrew) ve
		ışın kılıcı (DefenseSaber). Gemide tersi.
	]]
	local function isDefenseTool(tool: Tool): boolean
		return tool:GetAttribute("DefenseCrew") ~= nil or tool:GetAttribute("DefenseSaber") ~= nil
			or tool:GetAttribute("DefenseRayGun") ~= nil
	end
	local function onPlanet(): boolean
		return typeof(player:GetAttribute("DefensePlanet")) == "number"
	end

	local function collect(): { Tool }
		local list: { Tool } = {}
		local backpack = player:FindFirstChildOfClass("Backpack")
		local planet = onPlanet()
		for _, container in { backpack, player.Character } do
			if container then
				for _, child in container:GetChildren() do
					if child:IsA("Tool") and isDefenseTool(child) == planet then
						table.insert(list, child)
					end
				end
			end
		end
		-- Sıra kalıcı: ekipman kimliğine göre (kuşanınca yer değiştirmesin)
		-- Gezegende: crewmate'ler solda, silah (kılıç / ışın tabancası) en sağda
		local function key(t: Tool): string
			local gear = t:GetAttribute("DefenseSaber") ~= nil or t:GetAttribute("DefenseRayGun") ~= nil
			return (if gear then "~" else "") .. tostring(t:GetAttribute("GearId") or t.Name)
		end
		table.sort(list, function(a, b)
			return key(a) < key(b)
		end)
		return list
	end

	--[[
		Gezegen gear'ı (ışın kılıcı / tabanca): aracın kendi 3B görüntüsü,
		kılıç çapraz (Batur: "gear simgesi güzel değil"; eskiden ⚔ / 🔫).
		Rengi seviyeyle değiştiği için her çizimde araçtan kopyalanıyor.
	]]
	local function toolIcon(parent: GuiObject, tool: Tool, gun: boolean)
		local handle = tool:FindFirstChild("Handle") :: BasePart?
		if not handle then
			return
		end
		local vp = Instance.new("ViewportFrame")
		vp.Name = "ToolIcon"
		vp.AnchorPoint = Vector2.new(0.5, 0.5)
		vp.Position = UDim2.fromScale(0.5, 0.5)
		vp.Size = UDim2.fromScale(if gun then 1.05 else 1.25, if gun then 1.05 else 1.25)
		vp.BackgroundTransparency = 1
		vp.Ambient = Color3.fromRGB(200, 202, 212)
		vp.LightColor = Color3.new(1, 1, 1)
		vp.LightDirection = Vector3.new(-0.4, -1, -0.5)
		vp.Rotation = if gun then -12 else -45
		vp.ZIndex = parent.ZIndex + 1
		vp.Parent = parent
		local model = Instance.new("Model")
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") then
				local c = d:Clone()
				for _, x in c:GetChildren() do
					if not x:IsA("DataModelMesh") then
						x:Destroy()
					end
				end
				c.Anchored = true
				c.CFrame = handle.CFrame:ToObjectSpace(d.CFrame)
				c.Parent = model
			end
		end
		model.Parent = vp
		local cf, size = model:GetBoundingBox()
		local extent = math.max(size.X, size.Y, size.Z)
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		local dist = extent * 0.5 / math.tan(math.rad(15)) * 1.1
		-- Kılıç yandan (bıçak sağda, döndürülünce sağ üstte); tabanca namlu sağda
		local side = if gun then Vector3.new(dist, 0, 0) else Vector3.new(-dist, 0, 0)
		cam.CFrame = CFrame.lookAt(cf.Position + side + Vector3.new(0, extent * 0.08, 0), cf.Position)
		cam.Parent = vp
		vp.CurrentCamera = cam
	end

	local function redraw()
		for _, child in bar:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		tools = collect()
		table.clear(slots)
		-- Arayüz gizliyken (Topbar gözü) yeniden çizim çubuğu geri açmasın
		bar.Visible = #tools > 0 and screen:GetAttribute("UiHidden") ~= true
		bar.Size = UDim2.fromOffset(math.max(SLOT, #tools * SLOT + (#tools - 1) * GAP), SLOT + 4)

		for i, tool in tools do
			local equipped = tool.Parent == player.Character
			local tint = if equipped then UiKit.CREW.CYAN:Lerp(Color3.new(0, 0, 0), 0.25) else ACCENT
			local holder, button = UiKit.Raised(bar, "Slot" .. i, tint, UDim2.fromOffset(SLOT, SLOT + 4), 14)
			holder.LayoutOrder = i
			if equipped then
				-- Kuşanılı yuva bir tık yukarıda ve beyaz çerçeveli
				local stroke = button:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = Color3.new(1, 1, 1)
					stroke.Thickness = 2.5
				end
			end

			local icon = Instance.new("Frame")
			icon.Size = UDim2.fromScale(1, 1)
			icon.BackgroundTransparency = 1
			icon.ZIndex = button.ZIndex + 1
			icon.Parent = button
			local gearId = tool:GetAttribute("GearId")
			local crewUnit = tool:GetAttribute("UnitId")
			if typeof(gearId) == "string" then
				UiKit.GearIcon(icon, 40, gearId)
			elseif typeof(crewUnit) == "string" then
				-- Gezegen savunması: elde taşınan crewmate
				pcall(UiKit.UnitIcon, icon, 46, crewUnit)
			elseif tool:GetAttribute("DefenseSaber") ~= nil or tool:GetAttribute("DefenseRayGun") ~= nil then
				toolIcon(icon, tool, tool:GetAttribute("DefenseRayGun") ~= nil)
			else
				local name = Instance.new("TextLabel")
				name.Size = UDim2.new(1, -8, 1, -8)
				name.Position = UDim2.fromOffset(4, 4)
				name.BackgroundTransparency = 1
				name.Font = Enum.Font.GothamBold
				name.TextScaled = true
				name.TextColor3 = Color3.new(1, 1, 1)
				name.Text = tool.Name
				name.ZIndex = icon.ZIndex + 1
				name.Parent = icon
			end

			local key = Instance.new("TextLabel")
			key.Position = UDim2.fromOffset(6, 3)
			key.Size = UDim2.fromOffset(14, 14)
			key.BackgroundTransparency = 1
			key.Font = Enum.Font.FredokaOne
			key.TextSize = 14
			key.TextColor3 = Color3.new(1, 1, 1)
			key.TextStrokeTransparency = 0.4
			key.Text = tostring(i)
			key.ZIndex = icon.ZIndex + 3
			key.Parent = button

			button.MouseButton1Click:Connect(function()
				toggle(tool)
			end)

			if typeof(gearId) == "string" then
				local scale = Instance.new("UIScale")
				scale.Parent = holder

				-- Bekleme perdesi: yukarıdan aşağı çekiliyor
				local shade = Instance.new("Frame")
				shade.Name = "Cooldown"
				shade.AnchorPoint = Vector2.new(0, 1)
				shade.Position = UDim2.fromScale(0, 1)
				shade.Size = UDim2.fromScale(1, 1)
				shade.BackgroundColor3 = Color3.new(0, 0, 0)
				shade.BackgroundTransparency = 0.4
				shade.BorderSizePixel = 0
				shade.ZIndex = icon.ZIndex + 4
				shade.Visible = false
				shade.Parent = button
				UiKit.Corner(shade, 14)

				local timer = CardKit.bold(button, "", 26, CardKit.WHITE, icon.ZIndex + 5, 3)
				timer.Size = UDim2.fromScale(1, 1)
				timer.Visible = false

				slots[gearId] = { button = button, scale = scale, shade = shade, timer = timer }
				bindTool(tool)
			end
		end
	end

	local watched: { [Instance]: { RBXScriptConnection } } = {}
	local function watch(container: Instance?)
		if not container or watched[container] then
			return
		end
		watched[container] = {
			container.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					redraw()
				end
			end),
			container.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") then
					redraw()
				end
			end),
		}
		container.Destroying:Connect(function()
			local list = watched[container]
			if list then
				for _, c in list do
					c:Disconnect()
				end
				watched[container] = nil
			end
		end)
	end

	local function hookCharacter(char: Model?)
		watch(char)
		watch(player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10))
		redraw()
	end

	table.insert(connections, player.CharacterAdded:Connect(hookCharacter))
	-- Gezegene inince / dönünce çubuk değişiyor; eldeki uzay gear'ı bırakılıyor
	table.insert(connections, player:GetAttributeChangedSignal("DefensePlanet"):Connect(function()
		local held = equippedTool()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if held and hum and isDefenseTool(held) ~= onPlanet() then
			hum:UnequipTools()
		end
		redraw()
	end))
	table.insert(connections, player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watch(child)
			redraw()
		end
	end))
	hookCharacter(player.Character)

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		--[[
			Gamepad'de rakam tuşu yok: R1 sıradakini, L1 öncekini kuşandırıyor.
			Uçtan geçince elde bir şey kalmıyor (hazır çubuktaki gibi).
		]]
		if input.KeyCode == Enum.KeyCode.ButtonR1 or input.KeyCode == Enum.KeyCode.ButtonL1 then
			if #tools == 0 then
				return
			end
			local current = 0
			for i, t in tools do
				if t.Parent == player.Character then
					current = i
				end
			end
			local step = if input.KeyCode == Enum.KeyCode.ButtonR1 then 1 else -1
			local nextIndex = (current + step) % (#tools + 1)
			local hum = humanoid()
			if nextIndex == 0 then
				if hum then
					hum:UnequipTools()
				end
			elseif tools[nextIndex] ~= nil and tools[nextIndex].Parent ~= player.Character then
				toggle(tools[nextIndex])
			end
			return
		end

		local index = table.find(KEYS, input.KeyCode)
		local tool = index and tools[index]
		if tool then
			toggle(tool)
		end
	end))

	return {
		Destroy = function()
			for _, c in connections do
				c:Disconnect()
			end
			bar:Destroy()
		end,
	}
end

return Hotbar
