--!strict
--[[
	Gezegen savunmasının savaş simülasyonu. Saf veri: Instance yok, fizik
	yok, rastgelelik yok (dalga planı DefenseConfig.BuildWave'den,
	tohumlu). Sunucu her oyuncu için bir tane çalıştırıyor ve olayları yalnızca
	o oyuncuya gönderiyor; istemci çiziyor. Testler aynı modülü doğrudan
	çalıştırabiliyor.

	Düzlem: Vector2(x, z) (DefenseConfig.Field).

	Kurallar:
	  - Düşman yolunu yürüyor. Bir crewmate'in `engage` mesafesine (ya da
	    kendi menziline) girince DURUP onunla dövüşüyor. Guard'ın engage'i
	    büyük: çevresindekileri üstüne çekiyor.
	  - Yolun sonuna varan düşman gemi gövdesinden `leak` kadar götürüyor.
	  - Crewmate'ler yerinde duruyor, menzilindeki düşmana vuruyor
	    (Assassin en canlıya, diğerleri kapıya en yakına). Medic yaralıya.
	  - Canı biten crewmate DÜŞÜYOR (kayıp). Gövde sıfırlanırsa dalga
	    kaybediliyor ve ayakta kalan herkes de düşüyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DefenseConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DefenseConfig"))

local DefenseSim = {}

export type UnitInput = {
	uid: number,
	unitId: string,
	mutationId: string?,
	pos: Vector2,
}

export type SimUnit = {
	uid: number,
	unitId: string,
	mutationId: string?,
	role: string,
	pos: Vector2,
	hp: number,
	maxHp: number,
	dmg: number,
	heal: number,
	range: number,
	healRange: number,
	engage: number,
	block: number,        -- aynı anda tutabildiği yakın dövüşçü düşman
	post: Vector2,        -- oyuncunun koyduğu yer (karakol)
	focus: number?,       -- hedeflediği düşman (eid); aynı düşmana yığılmasınlar
	leash: number,        -- karakoldan en fazla bu kadar uzaklaşıyor
	moveSpeed: number,
	cooldown: number,
	timer: number,
	target: string,
	alive: boolean,
}

export type SimEnemy = {
	eid: number,
	kind: string,
	path: number,
	lane: number,         -- yolun yanına kayma (şimdiki)
	home: number,         -- grubun dizilişindeki şeridi (geri döndüğü yer)
	dist: number,
	pos: Vector2,
	hp: number,
	maxHp: number,
	dmg: number,
	speed: number,
	range: number,
	cooldown: number,
	timer: number,
	leak: number,
	cleave: number,
	foe: number?,         -- dövüştüğü crewmate (uid)
	offPath: boolean,
	ai: string,           -- DefenseConfig.Enemies[*].ai     -- dövüşmek için yoldan çıktı (bitince yola dönüyor)
}

export type Event = { [number]: any }

export type Sim = {
	planet: number,
	wave: number,
	plan: DefenseConfig.WavePlan,
	paths: { { Vector2 } },
	pathLens: { { number } },   -- her yolun birikimli uzunlukları
	time: number,
	nextSpawn: number,
	units: { SimUnit },
	enemies: { SimEnemy },
	nextEid: number,
	hull: number,
	maxHull: number,
	hpMul: number,
	dmgMul: number,
	frozenUntil: number,
	losses: number,
	kills: number,
	state: string,              -- "fight" | "won" | "lost"
	events: { Event },
}

-- ─── Yol geometrisi ─────────────────────────────────────────────────────────

local function cumulative(points: { Vector2 }): { number }
	local lens = { 0 }
	for i = 2, #points do
		lens[i] = lens[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	return lens
end

--[[ Yol üstünde `dist` uzaklıktaki nokta ve yön. ]]
local function pointAt(points: { Vector2 }, lens: { number }, dist: number): (Vector2, Vector2)
	local n = #points
	if dist <= 0 then
		return points[1], (points[2] - points[1]).Unit
	end
	for i = 2, n do
		if dist <= lens[i] then
			local seg = lens[i] - lens[i - 1]
			local a = if seg > 0 then (dist - lens[i - 1]) / seg else 0
			local dir = points[i] - points[i - 1]
			return points[i - 1]:Lerp(points[i], a), if dir.Magnitude > 0 then dir.Unit else Vector2.new(0, -1)
		end
	end
	local dir = points[n] - points[n - 1]
	return points[n], if dir.Magnitude > 0 then dir.Unit else Vector2.new(0, -1)
end

DefenseSim.PointAt = pointAt
DefenseSim.Cumulative = cumulative

local function enemyPos(sim: Sim, e: SimEnemy): Vector2
	local points = sim.paths[e.path]
	local p, dir = pointAt(points, sim.pathLens[e.path], e.dist)
	-- Şerit: yolun sağına/soluna kayma, tek sıra yürümesinler
	local normal = Vector2.new(-dir.Y, dir.X)
	local q = p + normal * e.lane
	local hw = DefenseConfig.Field.halfWidth - 2
	return Vector2.new(math.clamp(q.X, -hw, hw), q.Y)
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

--[[
	Bir crewmate'in sahadaki değerleri. `roleLevels` Armory seviyeleri.
]]
function DefenseSim.UnitStats(unitId: string, mutationId: string?, roleLevels: { [string]: number }?): SimUnit
	local role = DefenseConfig.GetRole(unitId)
	local power = DefenseConfig.GetPower(unitId, mutationId)
	local level = if roleLevels then (roleLevels[role.id] or 0) else 0
	local mul = power * (1 + DefenseConfig.RoleLevelBonus * math.clamp(level, 0, DefenseConfig.RoleMaxLevel))
	local hp = role.hp * mul
	return {
		uid = 0,
		unitId = unitId,
		mutationId = mutationId,
		role = role.id,
		pos = Vector2.zero,
		hp = hp,
		maxHp = hp,
		dmg = role.dmg * mul,
		heal = (role.heal or 0) * mul,
		range = role.range,
		healRange = role.healRange or 0,
		engage = role.engage,
		block = role.block,
		post = Vector2.zero,
		leash = role.leash,
		moveSpeed = role.moveSpeed,
		cooldown = role.cooldown,
		timer = 0,
		target = role.target,
		alive = true,
	}
end

function DefenseSim.New(planet: number, wave: number, seed: number, units: { UnitInput },
	roleLevels: { [string]: number }?, hull: number, maxHull: number, lastPattern: string?): Sim

	local plan = DefenseConfig.BuildWave(planet, wave, seed, lastPattern)
	local hpMul, dmgMul = DefenseConfig.WaveScale(planet, wave)
	local simUnits: { SimUnit } = {}
	for _, input in units do
		local u = DefenseSim.UnitStats(input.unitId, input.mutationId, roleLevels)
		u.uid = input.uid
		u.pos = input.pos
		u.post = input.pos
		-- İlk vuruşlar aynı karede olmasın
		u.timer = (input.uid % 5) * 0.07
		table.insert(simUnits, u)
	end
	local lens = {}
	for i, points in plan.paths do
		lens[i] = cumulative(points)
	end
	return {
		planet = planet,
		wave = wave,
		plan = plan,
		paths = plan.paths,
		pathLens = lens,
		time = 0,
		nextSpawn = 1,
		units = simUnits,
		enemies = {},
		nextEid = 1,
		hull = hull,
		maxHull = maxHull,
		hpMul = hpMul,
		dmgMul = dmgMul,
		frozenUntil = -1,
		losses = 0,
		kills = 0,
		state = "fight",
		events = {},
	}
end

--[[
	Dalga sürerken sahaya yeni crewmate (oyuncu elindekini yere bıraktı).
	Aynı uid ikinci kez eklenmiyor.
]]
function DefenseSim.AddUnit(sim: Sim, input: UnitInput, roleLevels: { [string]: number }?)
	for _, u in sim.units do
		if u.uid == input.uid then
			return
		end
	end
	local u = DefenseSim.UnitStats(input.unitId, input.mutationId, roleLevels)
	u.uid = input.uid
	u.pos = input.pos
	u.post = input.pos
	u.timer = 0.3
	table.insert(sim.units, u)
end

-- ─── Adım ───────────────────────────────────────────────────────────────────

local function emit(sim: Sim, event: Event)
	table.insert(sim.events, event)
end

local function damageUnit(sim: Sim, u: SimUnit, amount: number, from: number)
	if not u.alive then
		return
	end
	u.hp -= amount
	emit(sim, { "uhit", u.uid, from, math.floor(amount + 0.5) })
	if u.hp <= 0 then
		u.hp = 0
		u.alive = false
		sim.losses += 1
		emit(sim, { "ufall", u.uid })
	end
end

local function damageEnemy(sim: Sim, e: SimEnemy, amount: number)
	if e.hp <= 0 then
		return
	end
	e.hp -= amount
	if e.hp <= 0 then
		e.hp = 0
		sim.kills += 1
		emit(sim, { "edie", e.eid })
	end
end

local function spawnEnemy(sim: Sim, spawn: DefenseConfig.Spawn)
	local def = DefenseConfig.Enemies[spawn.kind]
	if not def then
		return
	end
	local e: SimEnemy = {
		eid = sim.nextEid,
		kind = spawn.kind,
		path = spawn.path,
		lane = if def.boss then 0 else spawn.lane,
		home = if def.boss then 0 else spawn.lane,
		dist = 0,
		pos = Vector2.zero,
		hp = def.hp * sim.hpMul,
		maxHp = def.hp * sim.hpMul,
		dmg = def.dmg * sim.dmgMul,
		speed = def.speed,
		range = def.range,
		cooldown = def.cooldown,
		timer = 0.4,
		leak = def.leak,
		cleave = def.cleave or 0,
		foe = nil,
		offPath = false,
		ai = def.ai or "melee",
	}
	e.pos = enemyPos(sim, e)
	sim.nextEid += 1
	table.insert(sim.enemies, e)
	emit(sim, { "spawn", e.eid, e.kind, e.path, e.lane, math.floor(e.maxHp + 0.5) })
end

local function findUnit(sim: Sim, uid: number?): SimUnit?
	if not uid then
		return nil
	end
	for _, u in sim.units do
		if u.uid == uid then
			return u
		end
	end
	return nil
end

--[[
	Düşmanın dövüşeceği crewmate: menzilinde (ya da crewmate'in engage
	mesafesinde) olanlar arasında Guard önce, sonra en yakın.
]]
local function isMelee(e: SimEnemy): boolean
	return e.range <= 7
end

local function pickFoe(sim: Sim, e: SimEnemy, held: { [number]: number }): SimUnit?
	local best: SimUnit? = nil
	local bestScore = math.huge
	local melee = isMelee(e)
	for _, u in sim.units do
		-- Yakın dövüşçü düşman, kapasitesi dolu crewmate'in yanından geçiyor
		if u.alive and not (melee and (held[u.uid] or 0) >= u.block) then
			local d = (u.pos - e.pos).Magnitude
			local blocker = u.role == "Guard" or u.role == "Brawler"
			-- Koşucu yalnızca önünü kesen dövüşçüyle oyalanıyor, diğerlerine çarpmadıkça bakmıyor
			local reach = if e.ai == "rusher" and not blocker then math.min(e.range, 2.5) else math.max(e.range, u.engage)
			if d <= reach then
				local score = d
				if u.role == "Guard" then
					score -= 100            -- tank üstüne çekiyor
				end
				if e.ai == "sniper" and (u.role == "Shooter" or u.role == "Medic") then
					score -= 40             -- tükürücü arka sırayı seçiyor
				elseif e.ai == "tank" and blocker then
					score -= 40             -- golem dövüşçülere yükleniyor
				end
				if e.ai ~= "sniper" then
					score += (u.hp / u.maxHp) * 6   -- yaralıya yüklen
				end
				if score < bestScore then
					bestScore = score
					best = u
				end
			end
		end
	end
	return best
end

-- Yakın dövüşçülerin menzili 4.5: tüküren bunun içine kadar yaklaşmalı
local ADVANCE_UNTIL = 4
-- Dalga çok uzarsa (son düşman çıktıktan OVERTIME sn sonra) düşmanlar
-- hırslanıyor: medic'in iyileştirdiği bir Guard ile sonsuz dövüş olmasın
local OVERTIME = 90

local function enrage(sim: Sim): number
	local spawns = sim.plan.spawns
	local lastT = if #spawns > 0 then spawns[#spawns].t else 0
	local over = sim.time - lastT - OVERTIME
	return if over > 0 then 1 + over / 15 else 1
end

--[[
	Şerit yönetimi (2026-10-02, Batur: "zigzag çiziyorlar, hepsi birbirinin
	arkasından geliyor, zekalarını geliştir"):
	  - Ayrışma: aynı yoldaki yakın komşudan yana açılıyor, üst üste binmiyor
	  - Koşucu (Gloop Mite) önündeki Guard / Brawler'ı görünce yanından dolaşıyor
	  - Şerit istenen yere yumuşakça kayıyor (sert dönüş yok); dizilişine geri dönüyor
]]
local LANE_MAX = 14
local LANE_SPEED = 5
local SPACING = 4
local DODGE_AHEAD = 20

local function steerLanes(sim: Sim, dt: number)
	local list = sim.enemies
	for _, e in list do
		if e.hp <= 0 or e.offPath or e.foe then
			continue
		end
		local want = e.home
		for _, o in list do
			if o ~= e and o.hp > 0 and o.path == e.path and not o.offPath then
				local dd = math.abs(o.dist - e.dist)
				local dl = e.lane - o.lane
				if dd < SPACING and math.abs(dl) < SPACING then
					local sign = if dl > 0 then 1 elseif dl < 0 then -1 elseif e.eid > o.eid then 1 else -1
					want += sign * (SPACING - math.abs(dl)) * (1 - dd / SPACING)
				end
			end
		end
		if e.ai == "rusher" then
			local ahead, dir = pointAt(sim.paths[e.path], sim.pathLens[e.path], e.dist + DODGE_AHEAD * 0.6)
			local normal = Vector2.new(-dir.Y, dir.X)
			for _, u in sim.units do
				if u.alive and (u.role == "Guard" or u.role == "Brawler") and (u.pos - ahead).Magnitude < DODGE_AHEAD then
					local side = (u.pos - ahead):Dot(normal)
					local clear = u.engage + 1
					if e.lane >= side then
						want = math.max(want, side + clear)
					else
						want = math.min(want, side - clear)
					end
				end
			end
		end
		want = math.clamp(want, -LANE_MAX, LANE_MAX)
		-- Koşucu çevik: şeridi daha hızlı değiştiriyor
		local step = LANE_SPEED * dt * (if e.ai == "rusher" then 1.8 else 1)
		e.lane += math.clamp(want - e.lane, -step, step)
	end
end

local function stepEnemies(sim: Sim, dt: number)
	local frozen = sim.time < sim.frozenUntil
	if not frozen then
		steerLanes(sim, dt)
	end
	-- Her crewmate'in tuttuğu yakın dövüşçü düşman sayısı
	local held: { [number]: number } = {}
	for _, e in sim.enemies do
		if e.hp > 0 and e.foe and isMelee(e) then
			held[e.foe] = (held[e.foe] or 0) + 1
		end
	end
	for _, e in sim.enemies do
		if e.hp <= 0 then
			continue
		end
		local foe = findUnit(sim, e.foe)
		if foe then
			local reach = math.max(e.range, foe.engage) + 0.5
			if not foe.alive or (foe.pos - e.pos).Magnitude > reach then
				if e.foe and isMelee(e) then
					held[e.foe] = math.max(0, (held[e.foe] or 1) - 1)
				end
				foe = nil
			end
		end
		if not foe then
			foe = pickFoe(sim, e, held)
			if foe and isMelee(e) then
				held[foe.uid] = (held[foe.uid] or 0) + 1
			end
		end
		e.foe = if foe then foe.uid else nil

		if frozen then
			continue
		end
		-- Uzaktan vuran düşman ateş ederken ilerlemeye devam ediyor (yakına
		-- gelene kadar): menzil dışındaki bir crewmate'i sonsuza dek taciz
		-- edip dalgayı kilitlemesin
		local advancing = foe ~= nil and e.range > 4 and e.ai ~= "sniper" and (foe.pos - e.pos).Magnitude > ADVANCE_UNTIL
		if foe and isMelee(e) then
			-- Guard/Brawler düşmanı uzaktan (engage) kendine çekiyor: düşman
			-- yolu bırakıp dibine kadar yürüyor. Yoksa ikisi de birbirinin
			-- menzili dışında kalıp sonsuza dek bakışıyordu.
			local gap = foe.pos - e.pos
			local d = gap.Magnitude
			if d > e.range then
				e.pos += gap.Unit * math.min(e.speed * dt, d - e.range + 0.2)
				e.offPath = true
				continue
			end
		end
		if foe then
			e.timer -= dt
			if e.timer <= 0 then
				e.timer += e.cooldown
				damageUnit(sim, foe, e.dmg * enrage(sim), e.eid)
				-- Boss'un savuruşu çevreye de değiyor
				if e.cleave > 0 then
					for _, other in sim.units do
						if other ~= foe and other.alive and (other.pos - foe.pos).Magnitude <= e.cleave then
							damageUnit(sim, other, e.dmg * 0.5 * enrage(sim), e.eid)
						end
					end
				end
			end
		else
			e.timer = math.max(e.timer - dt, 0.15)
		end
		if not foe and e.offPath then
			-- Dövüş bitti: yola yürüyerek dön (ışınlanmasın); geri değil
			-- çapraz öne doğru katılıyor
			e.dist += e.speed * dt * 0.6
			local back = enemyPos(sim, e) - e.pos
			local step = e.speed * dt
			if back.Magnitude <= step then
				e.pos += back
				e.offPath = false
			else
				e.pos += back.Unit * step
			end
		elseif not foe or advancing then
			e.dist += e.speed * dt * (if advancing then 0.5 else 1)
			local lens = sim.pathLens[e.path]
			if e.dist >= lens[#lens] then
				-- Gemiye vardı
				sim.hull = math.max(0, sim.hull - e.leak)
				e.hp = 0
				emit(sim, { "leak", e.eid, e.leak })
			else
				e.pos = enemyPos(sim, e)
			end
		end
	end
end

local function progressOf(sim: Sim, e: SimEnemy): number
	local lens = sim.pathLens[e.path]
	return e.dist / math.max(1, lens[#lens])
end

--[[
	Hareket: karakolun çevresindeki (leash + menzil) düşmana yürü, menzile
	girince dur; medic yaralı müttefiğe; kimse yoksa karakola dön. Karakoldan
	leash'ten fazla uzaklaşmıyor (yolu kesip durduruyor, peşinden koşmuyor).
]]
--[[
	Crewmate'in düşman puanı (büyük = önce). Hedefler paylaşılıyor: bir
	düşmana zaten başkaları bakıyorsa puanı düşüyor (yığılmasınlar).
	Assassin önce tükürücüleri, sonra en canlıyı; diğerleri kapıya en
	yakını seçiyor.
]]
local function enemyScore(sim: Sim, u: SimUnit, e: SimEnemy, focus: { [number]: number }): number
	local score
	if u.target == "strongest" then
		score = (if e.ai == "sniper" then 2 else 0) + e.hp / math.max(1, sim.hpMul) / 200
	else
		score = progressOf(sim, e)
	end
	local others = (focus[e.eid] or 0) - (if u.focus == e.eid then 1 else 0)
	return score - 0.35 * math.max(0, others) - (e.pos - u.pos).Magnitude * 0.002
end

local function chooseEnemy(sim: Sim, u: SimUnit, center: Vector2, radius: number, focus: { [number]: number }): SimEnemy?
	local best: SimEnemy? = nil
	local bestScore = -math.huge
	for _, e in sim.enemies do
		if e.hp > 0 and (e.pos - center).Magnitude <= radius then
			local score = enemyScore(sim, u, e, focus)
			if score > bestScore then
				bestScore = score
				best = e
			end
		end
	end
	return best
end

local function moveUnit(sim: Sim, u: SimUnit, dt: number, focus: { [number]: number })
	local goal: Vector2? = nil
	local stopAt = 0
	-- Atıcı ve medic: yakına gelen yakın dövüşçü düşmandan geri çekil
	if u.role == "Shooter" or u.role == "Medic" then
		local threat: SimEnemy? = nil
		local nearest = 6
		for _, e in sim.enemies do
			if e.hp > 0 and isMelee(e) then
				local d = (e.pos - u.pos).Magnitude
				if d < nearest then
					nearest = d
					threat = e
				end
			end
		end
		if threat then
			local away = u.pos - threat.pos
			goal = u.pos + (if away.Magnitude > 0.01 then away.Unit else Vector2.new(0, -1)) * 6
			stopAt = 0
		end
	end
	if not goal and u.heal > 0 then
		local worst = 0.85
		for _, other in sim.units do
			if other.alive and other ~= u and (other.pos - u.post).Magnitude <= u.leash + u.healRange then
				local frac = other.hp / other.maxHp
				if frac < worst then
					worst = frac
					goal = other.pos
					stopAt = u.healRange * 0.8
				end
			end
		end
	end
	if not goal then
		local e = chooseEnemy(sim, u, u.post, u.leash + u.range, focus)
		u.focus = if e then e.eid else nil
		if e then
			if u.role == "Guard" then
				-- Tank yolu önden kesiyor: düşmanın birkaç adım ilerisine
				local ahead = DefenseSim.PointAt(sim.paths[e.path], sim.pathLens[e.path], e.dist + 7)
				goal = ahead
				stopAt = 0.5
			else
				goal = e.pos
				stopAt = u.range * 0.8
			end
		end
	end
	local target = goal or u.post
	local gap = target - u.pos
	local d = gap.Magnitude
	if d <= stopAt + 0.05 or d < 0.05 then
		return
	end
	local step = math.min(u.moveSpeed * dt, d - stopAt)
	local nextPos = u.pos + gap.Unit * step
	-- Tasma: karakoldan leash'ten uzağa gitme
	local fromPost = nextPos - u.post
	if fromPost.Magnitude > u.leash then
		nextPos = u.post + fromPost.Unit * u.leash
	end
	u.pos = nextPos
end

local function stepUnits(sim: Sim, dt: number)
	-- Hangi düşmana kaç crewmate bakıyor (hedef paylaşımı)
	local focus: { [number]: number } = {}
	for _, u in sim.units do
		if u.alive and u.focus then
			focus[u.focus] = (focus[u.focus] or 0) + 1
		end
	end
	for _, u in sim.units do
		if not u.alive then
			continue
		end
		moveUnit(sim, u, dt, focus)
		u.timer -= dt
		if u.timer > 0 then
			continue
		end

		-- Medic önce yaralıya bakıyor
		if u.heal > 0 then
			local patient: SimUnit? = nil
			local worst = 0.98
			for _, other in sim.units do
				if other.alive and (other.pos - u.pos).Magnitude <= u.healRange then
					local frac = other.hp / other.maxHp
					if frac < worst then
						worst = frac
						patient = other
					end
				end
			end
			if patient then
				patient.hp = math.min(patient.maxHp, patient.hp + u.heal)
				u.timer = u.cooldown
				emit(sim, { "heal", u.uid, patient.uid, math.floor(u.heal + 0.5) })
				continue
			end
		end

		local target = chooseEnemy(sim, u, u.pos, u.range, focus)
		if target then
			u.timer = u.cooldown
			emit(sim, { "uatk", u.uid, target.eid, math.floor(u.dmg + 0.5) })
			damageEnemy(sim, target, u.dmg)
		else
			-- Hedef yokken hazır beklesin (gelen ilk düşmana hemen vursun)
			u.timer = 0
		end
	end
end

--[[ Bir adım. Olaylar sim.events'e ekleniyor (çağıran boşaltıyor). ]]
function DefenseSim.Step(sim: Sim, dt: number)
	if sim.state ~= "fight" then
		return
	end
	sim.time += dt

	local spawns = sim.plan.spawns
	while sim.nextSpawn <= #spawns and spawns[sim.nextSpawn].t <= sim.time
		and #sim.enemies < DefenseConfig.MaxEnemies do
		spawnEnemy(sim, spawns[sim.nextSpawn])
		sim.nextSpawn += 1
	end

	stepEnemies(sim, dt)
	stepUnits(sim, dt)

	-- Ölüleri temizle
	for i = #sim.enemies, 1, -1 do
		if sim.enemies[i].hp <= 0 then
			table.remove(sim.enemies, i)
		end
	end

	if sim.hull <= 0 then
		sim.state = "lost"
		for _, u in sim.units do
			if u.alive then
				u.alive = false
				u.hp = 0
				sim.losses += 1
				emit(sim, { "ufall", u.uid })
			end
		end
		emit(sim, { "lost" })
	elseif sim.nextSpawn > #spawns and #sim.enemies == 0 then
		sim.state = "won"
		emit(sim, { "won" })
	end
end

-- ─── Destekler (Market) ─────────────────────────────────────────────────────

function DefenseSim.Strike(sim: Sim, at: Vector2)
	local dmg = DefenseConfig.StrikeDamage * sim.hpMul
	for _, e in sim.enemies do
		if e.hp > 0 and (e.pos - at).Magnitude <= DefenseConfig.StrikeRadius then
			damageEnemy(sim, e, dmg)
		end
	end
	emit(sim, { "strike", at.X, at.Y })
end

--[[ Oyuncunun ışın kılıcı: `at` noktasında, `dir` yönündeki geniş yayda. Vurulan sayısı. ]]
function DefenseSim.Slash(sim: Sim, at: Vector2, dir: Vector2, radius: number, damage: number): number
	local hits = 0
	local facing = if dir.Magnitude > 0.01 then dir.Unit else Vector2.new(0, 1)
	for _, e in sim.enemies do
		if e.hp > 0 then
			local rel = e.pos - at
			local d = rel.Magnitude
			if d <= radius and (d < 1.5 or rel.Unit:Dot(facing) > -0.25) then
				damageEnemy(sim, e, damage)
				hits += 1
			end
		end
	end
	emit(sim, { "slash", at.X, at.Y, hits, math.floor(damage + 0.5) })
	return hits
end

--[[
	Oyuncunun ışın tabancası: `dir` yönündeki konide (cos ≥ cone) menzildeki
	en yakın düşmana. Vurulan düşmanın kimliği (yoksa nil).
]]
function DefenseSim.Shoot(sim: Sim, at: Vector2, dir: Vector2, range: number, cone: number, damage: number): number?
	local facing = if dir.Magnitude > 0.01 then dir.Unit else Vector2.new(0, 1)
	local best: SimEnemy? = nil
	local bestD = math.huge
	for _, e in sim.enemies do
		if e.hp > 0 then
			local rel = e.pos - at
			local d = rel.Magnitude
			if d <= range and d < bestD and (d < 2 or rel.Unit:Dot(facing) >= cone) then
				best = e
				bestD = d
			end
		end
	end
	if not best then
		emit(sim, { "pshot", at.X, at.Y, 0 })
		return nil
	end
	local eid = best.eid
	emit(sim, { "pshot", at.X, at.Y, eid, math.floor(damage + 0.5) })
	damageEnemy(sim, best, damage)
	return eid
end

function DefenseSim.MedDrop(sim: Sim)
	for _, u in sim.units do
		if u.alive then
			u.hp = math.min(u.maxHp, u.hp + u.maxHp * 0.5)
		end
	end
	emit(sim, { "meddrop" })
end

function DefenseSim.Freeze(sim: Sim)
	sim.frozenUntil = sim.time + DefenseConfig.FreezeSeconds
	emit(sim, { "freeze", DefenseConfig.FreezeSeconds })
end

--[[ Tek seferde sonuna kadar (testler ve denge ölçümü). ]]
function DefenseSim.RunToEnd(sim: Sim, maxSeconds: number?): string
	local dt = 1 / DefenseConfig.TickRate
	local limit = maxSeconds or 600
	while sim.state == "fight" and sim.time < limit do
		DefenseSim.Step(sim, dt)
		table.clear(sim.events)
	end
	return sim.state
end

return DefenseSim
