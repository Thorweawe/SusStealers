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
	cooldown: number,
	timer: number,
	target: string,
	alive: boolean,
}

export type SimEnemy = {
	eid: number,
	kind: string,
	path: number,
	lane: number,
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
	offPath: boolean,     -- dövüşmek için yoldan çıktı (bitince yola dönüyor)
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
	return p + normal * e.lane
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
	return e.range <= 4.5
end

local function pickFoe(sim: Sim, e: SimEnemy, held: { [number]: number }): SimUnit?
	local best: SimUnit? = nil
	local bestScore = math.huge
	local melee = isMelee(e)
	for _, u in sim.units do
		-- Yakın dövüşçü düşman, kapasitesi dolu crewmate'in yanından geçiyor
		if u.alive and not (melee and (held[u.uid] or 0) >= u.block) then
			local d = (u.pos - e.pos).Magnitude
			local reach = math.max(e.range, u.engage)
			if d <= reach then
				local score = d - (if u.role == "Guard" then 100 else 0)
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

local function stepEnemies(sim: Sim, dt: number)
	local frozen = sim.time < sim.frozenUntil
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
		local advancing = foe ~= nil and e.range > 4 and (foe.pos - e.pos).Magnitude > ADVANCE_UNTIL
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
			-- Dövüş bitti: yola yürüyerek dön (ışınlanmasın)
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

local function stepUnits(sim: Sim, dt: number)
	for _, u in sim.units do
		if not u.alive then
			continue
		end
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

		local target: SimEnemy? = nil
		local best = -math.huge
		for _, e in sim.enemies do
			if e.hp > 0 and (e.pos - u.pos).Magnitude <= u.range then
				local score = if u.target == "strongest" then e.hp else progressOf(sim, e)
				if score > best then
					best = score
					target = e
				end
			end
		end
		if target then
			u.timer = u.cooldown
			emit(sim, { "uatk", u.uid, target.eid })
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
