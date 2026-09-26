--!strict
--[[
	Haritanın canlılığı — tamamen istemcide, sunucuya hiçbir şey sormuyor:

	  Uyarı lambaları  — Decor.Polish.Beacons'taki "WarnBeacon"lar sırayla
	                     yanıp sönüyor. Her lambanın fazı farklı; hepsi aynı
	                     anda yansa "alarm" gibi duruyordu.
	  Gezen mürettebat — istasyonda, odalarda, lobide dolaşan Among Us
	                     mürettebatı. Rastgele bir yere yürüyor, orada biraz
	                     duruyor ya da boş bir koltuğa oturup bir süre
	                     dinleniyor. Sadece süs: çarpışmıyor, çalınamıyor, isim
	                     etiketi yok (kaidedeki karakterlerle karışmasın diye).

	YOL: PathfindingService. İlk sürüm koridorda düz çizgide yürüyordu;
	odalara girince duvarlardan geçerdi. Yol bulucu duvarların ve eşyaların
	etrafından dolaşan ara noktalar veriyor, model onları sırayla izliyor.
	Yol bulunamazsa hedef atlanıyor.

	NEDEN İSTEMCİDE: sunucuda her karede konum değiştirmek her oyuncuya her
	karede paket demek. Mürettebatın herkeste aynı yerde olması gerekmiyor.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RogueTrack = require(Shared.RogueTrack)
local UnitModel = require(Shared.UnitModel)

local MapLife = {}

export type Handle = {
	Destroy: () -> (),
}

-- ─── Uyarı lambaları ────────────────────────────────────────────────────────

local BLINK_PERIOD = 1.6
local BLINK_ON = 0.45
local LAMP_ON = Color3.fromRGB(255, 70, 60)
local LAMP_OFF = Color3.fromRGB(90, 24, 24)

-- ─── Gezen mürettebat ───────────────────────────────────────────────────────

local CREW = { "RedCrew", "BlueCrew", "YellowCrew", "LimeCrew", "Engineer", "Scientist", "Janitor", "Guardian" }
local WALK_SPEED = 6
local SIT_CHANCE = 0.3
local SIT_TIME = { 6, 16 }
local IDLE_TIME = { 1.5, 5 }

type Walker = {
	model: Model,
	lift: number,      -- pivottan ayak tabanına (model y=0 ayak)
	pos: Vector3,      -- ayakların yeri
	facing: Vector3,
	path: { Vector3 },
	index: number,
	waitUntil: number,
	seat: Seat?,
	busy: boolean,     -- yol hesaplanıyor
	fails: number,     -- art arda bulunamayan yol
	phase: number,
}

--[[
	Hedef adayları: zemin karoları (koridor, odalar, lobi, kanatlar, ek
	odalar) ve koltuklar. Bir kez toplanıyor; harita oyun sırasında
	değişmiyor.
]]
local function collectTargets(decor: Instance): ({ Vector3 }, { Seat })
	local floors: { Vector3 } = {}
	local seats: { Seat } = {}
	--[[
		Karonun üstünde bir eşya duruyorsa (masa, tank, kasa) o nokta hedef
		olamaz: mürettebat eşyanın içinden başlıyor ve oradan hiç yol
		bulamayıp donuyordu. Karonun üstündeki gövde hacmine katı parça
		değiyorsa eleniyor.
	]]
	local params = OverlapParams.new()
	params.RespectCanCollide = true
	for _, d in decor:GetDescendants() do
		if d:IsA("Seat") then
			table.insert(seats, d)
		elseif d:IsA("BasePart") and d.Size.Y < 1 and string.sub(d.Name, -4) == "Tile" then
			local top = d.Position + Vector3.new(0, d.Size.Y / 2, 0)
			local blocked = workspace:GetPartBoundsInBox(CFrame.new(top + Vector3.new(0, 2.6, 0)), Vector3.new(3, 4.4, 3), params)
			if #blocked == 0 then
				table.insert(floors, top)
			end
		end
	end
	return floors, seats
end

function MapLife.Start(): Handle
	local rng = Random.new()
	local decor = workspace:WaitForChild("Decor", 30)
	local polish = decor and decor:WaitForChild("Polish", 10)
	local beaconFolder = polish and polish:FindFirstChild("Beacons")

	-- Lambalar: her birine sabit bir faz kayması
	local lamps: { { part: BasePart, light: PointLight?, offset: number } } = {}
	if beaconFolder then
		for i, d in beaconFolder:GetChildren() do
			if d:IsA("BasePart") and d.Name == "WarnBeacon" then
				table.insert(lamps, {
					part = d,
					light = d:FindFirstChildOfClass("PointLight"),
					offset = (i * 0.37) % BLINK_PERIOD,
				})
			end
		end
	end

	local floors: { Vector3 }, seats: { Seat } = {}, {}
	if decor then
		floors, seats = collectTargets(decor)
	end
	local reserved: { [Seat]: boolean } = {}

	-- Mürettebat: istemciye özel klasör (sunucu görmüyor)
	local folder = Instance.new("Folder")
	folder.Name = "CrewWalkers"
	folder.Parent = workspace

	local walkers: { Walker } = {}
	for i, unitId in CREW do
		if #floors == 0 then
			break
		end
		local ok, model = pcall(UnitModel.Build, unitId)
		if ok and model and model.PrimaryPart then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.CastShadow = false
				end
			end
			local start = floors[rng:NextInteger(1, #floors)]
			local lift = model:GetPivot().Position.Y
			model:PivotTo(CFrame.new(start + Vector3.new(0, lift, 0)))
			model.Parent = folder
			table.insert(walkers, {
				model = model,
				lift = lift,
				pos = start,
				facing = Vector3.zAxis,
				path = {},
				index = 1,
				waitUntil = 0,
				seat = nil,
				busy = false,
				fails = 0,
				phase = i * 0.7,
			})
		end
	end

	--[[
		Yeni hedef seç ve yolunu hesapla (yield ediyor, kendi görevinde).
		Koltuk seçilirse ayrılıyor ki iki mürettebat aynı koltuğa gitmesin.
	]]
	local function plan(w: Walker)
		w.busy = true
		task.spawn(function()
			local target: Vector3
			local seat: Seat? = nil
			if #seats > 0 and rng:NextNumber() < SIT_CHANCE then
				local candidate = seats[rng:NextInteger(1, #seats)]
				if not reserved[candidate] and not candidate.Occupant then
					seat = candidate
					reserved[candidate] = true
				end
			end
			if seat then
				-- Koltuğun önüne yürü, sonra otur
				target = (seat.CFrame * CFrame.new(0, 0, -2.5)).Position
			else
				target = floors[rng:NextInteger(1, #floors)]
			end

			local path = PathfindingService:CreatePath({
				AgentRadius = 1.6,
				AgentHeight = 5,
				AgentCanJump = false,
				WaypointSpacing = 4,
			})
			local ok = pcall(function()
				path:ComputeAsync(w.pos + Vector3.new(0, 1, 0), target)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				local points = {}
				for _, wp in path:GetWaypoints() do
					table.insert(points, wp.Position)
				end
				w.path = points
				w.index = 1
				w.seat = seat
				w.fails = 0
			else
				-- Ulaşılamaz: koltuğu bırak, biraz sonra başka yere dene
				if seat then
					reserved[seat] = nil
				end
				w.path = {}
				w.waitUntil = os.clock() + 1
				--[[
					Üst üste bulunamıyorsa bulunduğu yer sıkışık: boş bir karoya
					taşı. Kimse bakmıyorken yer değiştirmesi fark edilmiyor, donmuş
					bir mürettebat ise hemen fark ediliyor.
				]]
				w.fails += 1
				if w.fails >= 3 then
					w.fails = 0
					w.pos = floors[rng:NextInteger(1, #floors)]
					w.model:PivotTo(CFrame.new(w.pos + Vector3.new(0, w.lift, 0)))
				end
			end
			w.busy = false
		end)
	end

	local function standUp(w: Walker)
		if w.seat then
			reserved[w.seat] = nil
			w.seat = nil
		end
	end

	--[[
		Gezen impostor (sunucu, RogueService). Sunucu yürüyeceği rotayı
		modelin "RogueTrack" niteliğine yazıyor (shared/RogueTrack); biz onu
		HER KAREDE burada yürütüyoruz: çapalı kökü rotadaki yere koyuyoruz
		(yalnızca bizim ekranımızda), dönüşü yumuşatıyoruz. Sunucunun kökü
		seyrek güncellemesi bizim her kare yazdığımızın altında kalıyor.
		Rota yokken (hackliyor, duruyor) sunucunun koyduğu yer görünüyor.

		Yalpalama gövdeyi köke bağlayan "RogueBob" kaynağının C0'ında:
		zıplama + iki yana sallanma, AYAK HİZASI etrafında (gövde ortası
		etrafında dönünce ayaklar yana kayıp topallıyor gibi duruyordu) ve
		YÜRÜNEN YOLA bağlı (hıza bağlıyken hız her karede oynuyor, adımlar
		düzensizdi).
	]]
	type RogueView = {
		model: Model,
		root: BasePart,
		weld: Weld,
		base: CFrame,
		lift: number,
		text: string?,
		track: RogueTrack.Track?,
		yaw: number?,
		sway: number,     -- 0 duruyor .. 1 yürüyor (yumuşak)
	}
	-- Stud başına faz (radyan). |sin| her π'de bir adım: 11 stud/sn'de saniyede ~3.3 adım
	local STEP_PHASE = 0.95
	local rogueView: RogueView? = nil

	local function yawOf(v: Vector3): number
		return math.atan2(-v.X, -v.Z)
	end

	local function stepRogue(dt: number)
		local model = workspace:FindFirstChild("RogueImpostor")
		if not (model and model:IsA("Model")) then
			rogueView = nil
			return
		end
		local view = rogueView
		if not view or view.model ~= model then
			local root = model:FindFirstChild("RogueRoot")
			local weld = root and root:FindFirstChild("RogueBob")
			if not (root and root:IsA("BasePart") and weld and weld:IsA("Weld")) then
				return
			end
			local lift = model:GetAttribute("Lift")
			view = {
				model = model,
				root = root,
				weld = weld,
				base = weld.C0,
				lift = if typeof(lift) == "number" then lift else 2,
				text = nil,
				track = nil,
				yaw = nil,
				sway = 0,
			}
			rogueView = view
		end
		assert(view)

		local text = model:GetAttribute("RogueTrack")
		if text ~= view.text then
			view.text = if typeof(text) == "string" then text else nil
			view.track = RogueTrack.Decode(view.text)
		end

		local moving = false
		local walked = 0
		local track = view.track
		if track then
			local now = workspace:GetServerTimeNow()
			walked = RogueTrack.Distance(track, now)
			moving = not RogueTrack.Done(track, now)
			local pos, dir = RogueTrack.At(track, walked)
			local yaw = view.yaw or yawOf(view.root.CFrame.LookVector)
			if dir.Magnitude > 0.01 then
				-- En kısa yoldan dön, yumuşak
				local target = yawOf(dir)
				local delta = (target - yaw + math.pi) % (2 * math.pi) - math.pi
				yaw += delta * (1 - math.exp(-12 * dt))
			end
			view.yaw = yaw
			view.root.CFrame = CFrame.new(pos + Vector3.new(0, view.lift, 0)) * CFrame.Angles(0, yaw, 0)
		else
			view.yaw = nil
		end

		view.sway += ((if moving then 1 else 0) - view.sway) * (1 - math.exp(-8 * dt))
		local phase = walked * STEP_PHASE
		local k = view.sway
		local bob = math.abs(math.sin(phase)) * 0.3 * k
		local roll = math.sin(phase) * math.rad(6) * k
		view.weld.C0 = CFrame.new(0, bob - view.lift, 0) * CFrame.Angles(0, 0, roll)
			* CFrame.new(0, view.lift, 0) * view.base
	end
	-- Render'dan hemen önce: sunucudan gelen seyrek kök güncellemesinin üstüne yazılsın
	local rogueConnection = RunService.RenderStepped:Connect(stepRogue)

	local clock = 0
	local lampAccum = 0
	local frameNo = 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		clock += dt
		frameNo += 1
		--[[
			PERFORMANS: gezen mürettebatın modeli yalnızca kameraya yakınsa
			her karede taşınıyor; uzaktakinin konumu (w.pos) yine ilerliyor
			ama modeli 6 karede bir yazılıyor. Model birkaç parça, PivotTo
			hepsini taşıyor.
		]]
		local cam = workspace.CurrentCamera.CFrame.Position
		local farTurn = frameNo % 6 == 0

		-- Lambalar saniyede ~12 kez yeter
		lampAccum += dt
		if lampAccum >= 0.08 then
			lampAccum = 0
			for _, lamp in lamps do
				local on = ((clock + lamp.offset) % BLINK_PERIOD) < BLINK_ON
				lamp.part.Color = if on then LAMP_ON else LAMP_OFF
				if lamp.light then
					lamp.light.Brightness = if on then 3 else 0
				end
			end
		end

		local now = os.clock()
		for _, w in walkers do
			if w.busy or now < w.waitUntil then
				continue
			end

			local target = w.path[w.index]
			if not target then
				-- Yol bitti: koltuktaysa kalk; yeni hedef planla
				standUp(w)
				plan(w)
				continue
			end

			local flat = Vector3.new(target.X - w.pos.X, 0, target.Z - w.pos.Z)
			local dist = flat.Magnitude
			if dist < 0.6 then
				w.pos = Vector3.new(target.X, target.Y, target.Z)
				w.index += 1
				if w.index > #w.path then
					w.path = {}
					if w.seat then
						-- Otur: koltuğun üstüne, koltuğun baktığı yöne
						local s = w.seat :: Seat
						local top = s.CFrame * CFrame.new(0, s.Size.Y / 2, 0)
						w.facing = s.CFrame.LookVector
						w.model:PivotTo(CFrame.lookAt(top.Position, top.Position + w.facing) + Vector3.new(0, w.lift - 0.4, 0))
						w.waitUntil = now + rng:NextNumber(SIT_TIME[1], SIT_TIME[2])
					else
						w.waitUntil = now + rng:NextNumber(IDLE_TIME[1], IDLE_TIME[2])
					end
				end
				continue
			end

			local step = math.min(dist, WALK_SPEED * dt)
			local dir = flat.Unit
			local y = w.pos.Y + (target.Y - w.pos.Y) * math.clamp(step / dist, 0, 1)
			w.pos = Vector3.new(w.pos.X + dir.X * step, y, w.pos.Z + dir.Z * step)
			w.facing = dir
			-- Yürürken zıplar gibi hafif sekme: Among Us yürüyüşü
			local bob = math.abs(math.sin((clock + w.phase) * 9)) * 0.35
			if farTurn or (w.pos - cam).Magnitude <= 160 then
				w.model:PivotTo(CFrame.lookAt(w.pos, w.pos + dir) + Vector3.new(0, w.lift + bob, 0))
			end
		end
	end)

	-- Oyuncu bir mürettebatın ayrılmış koltuğuna oturursa o mürettebat kalkıp gitsin
	local seatWatch: { RBXScriptConnection } = {}
	for _, s in seats do
		table.insert(seatWatch, s:GetPropertyChangedSignal("Occupant"):Connect(function()
			if not s.Occupant then
				return
			end
			for _, w in walkers do
				if w.seat == s then
					standUp(w)
					w.path = {}
					w.waitUntil = 0
				end
			end
		end))
	end

	return {
		Destroy = function()
			connection:Disconnect()
			rogueConnection:Disconnect()
			for _, c in seatWatch do
				c:Disconnect()
			end
			folder:Destroy()
		end,
	}
end

return MapLife
