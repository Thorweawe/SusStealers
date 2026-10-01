--!strict
--[[
	GEZEGEN SAVUNMASI (2026-10-01, Batur). Plan: PLAN-GEZEGEN-SAVUNMA.md.

	  Navigasyon odası → PILOT istemi → gezegen seç → iniş (istemcide
	  animasyon) → gezegen yüzeyi (PlanetWorldService). KOMUTA konsolunda
	  bölüm seçip kaidedeki crewmate'leri alana koyuyorsun; her dalga
	  sunucuda DefenseSim ile dönüyor, olaylar yalnızca sahibine gidiyor.

	Kurallar (Batur):
	  - Sahaya konan crewmate kaideden ayrılıyor: "mission", gelir yok.
	  - Dalgada düşen → hastane ("hospital"). Revive = o crewmate'in 15 dk'lık
	    kazancı (o anki bütün çarpanlarla), ya da LET GO (silinir).
	  - Gövde sıfırlanırsa dalga kaybedilir: ayakta kalanlar da hastaneye.
	  - Dalgalar sonsuz, her 5 dalga bir bölüm: kayba göre yıldız, altın
	    YALNIZCA yeni yıldız için ("binlerce kazanılmamalı").
	  - Dalga arasında geri çekilebilirsin; sonraki girişte kaldığın
	    bölümden (en iyi + 1'e kadar) başlayabilirsin.
	  - Dalga ortasında oyundan çıkan kaybetmiş sayılır (kaçış hilesi yok).

	Remote "Defense" (istemci → sunucu): action, ...
	  land(planet) · takeoff() · begin(sector) · place(slot, x, z) ·
	  move(uid, x, z) · recall(uid) · go() · retreat() · support(id, x, z) ·
	  buy(kind, id) · revive(slot) · release(slot) · sync()
	Remote "DefenseState" (sunucu → istemci): kind, payload
	  pilot · data · landing · arrived · launch · home · command · open ·
	  run · tick · waveEnd · over
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local DefenseConfig = require(Shared.DefenseConfig)
local DefenseSim = require(Shared.DefenseSim)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)
local PlanetWorldService = require(script.Parent.PlanetWorldService)
local PromptGuard = require(script.Parent.PromptGuard)

local DefenseService = {}

local NOTIFY_KIND = "gear"
DefenseService.NotifyKind = NOTIFY_KIND

type Deployed = {
	uid: number,
	slot: number,
	unitId: string,
	mutationId: string?,
	pos: Vector2,
	fallen: boolean,
}

type Run = {
	planet: number,
	arena: number,
	sector: number,          -- başlanan bölüm
	wave: number,            -- sıradaki (prep) ya da süren (fight) dalga
	phase: string,           -- "prep" | "fight"
	units: { Deployed },
	nextUid: number,
	hull: number,
	maxHull: number,
	seed: number,
	lastPattern: string?,
	plan: DefenseConfig.WavePlan,
	sim: DefenseSim.Sim?,
	sectorLosses: number,
	used: { [string]: boolean },   -- bu dalgada kullanılan destekler
	acc: number,                   -- adım biriktiricisi
	sendAcc: number,
	pending: { DefenseSim.Event },
	wavesCleared: number,
	goldEarned: number,
}

type Session = {
	planet: number?,
	arena: number?,          -- oyuncunun gezegen kopyası (DefenseConfig.MaxArenas)
	run: Run?,
	busy: boolean,           -- iniş / kalkış animasyonu sürüyor
	lastAction: number,
	lastSlash: number,
}

local sessions: { [Player]: Session } = {}
-- arena -> o arenadaki oyuncu
local arenaOwner: { [number]: Player } = {}
local stateRemote: RemoteEvent? = nil
local notifyRemote: RemoteEvent? = nil
local navSpot: CFrame? = nil

local STEP = 1 / DefenseConfig.TickRate
local SEND_EVERY = 0.2
local LAND_DELAY = 2.4
local LAUNCH_DELAY = 1.6

-- ─── Yardımcılar ────────────────────────────────────────────────────────────

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
	end
end

local function send(player: Player, kind: string, payload: any?)
	if stateRemote and player.Parent then
		stateRemote:FireClient(player, kind, payload)
	end
end

local function session(player: Player): Session
	local s = sessions[player]
	if not s then
		s = { planet = nil, arena = nil, run = nil, busy = false, lastAction = 0, lastSlash = 0 }
		sessions[player] = s
	end
	return s
end

local function podiumBySlot(player: Player, slot: number): Part?
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		return nil
	end
	for _, podium in PlotService.GetPodiums(plot) do
		if podium:GetAttribute("SlotIndex") == slot then
			return podium
		end
	end
	return nil
end

local function planetEntry(profile: DataService.Profile, planet: number): { best: number, stars: { [string]: number } }
	local key = tostring(planet)
	local entry = profile.defense.planets[key]
	if not entry then
		entry = { best = 0, stars = {} }
		profile.defense.planets[key] = entry
	end
	return entry
end

--[[ Gezegen açık mı: uzaydaki rebirth kilidi + bir önceki gezegende yeterli bölüm. ]]
function DefenseService.IsPlanetUnlocked(profile: DataService.Profile, planet: number): (boolean, string?)
	local def = Config.SpaceMonsters[planet]
	if not def then
		return false, "Unknown planet"
	end
	if not Config.MonsterUnlocked(def, profile.rebirths) then
		return false, string.format("%s unlocks at REBIRTH %d", def.planet, def.rebirths or 0)
	end
	if planet > 1 then
		local prev = profile.defense.planets[tostring(planet - 1)]
		local need = DefenseConfig.UnlockSectors
		if not prev or prev.best < need then
			local prevDef = Config.SpaceMonsters[planet - 1]
			return false, string.format("Clear sector %d on %s first", need, if prevDef then prevDef.planet else "the last planet")
		end
	end
	return true, nil
end

function DefenseService.GetReviveCost(player: Player, unitId: string, mutationId: string?): number
	local perSecond = EconomyService.GetUnitIncome(player, unitId, mutationId)
	return math.max(100, math.ceil(perSecond * 60 * DefenseConfig.ReviveMinutes))
end

-- ─── İstemciye giden durum ──────────────────────────────────────────────────

local function dataPayload(player: Player): any?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local d = profile.defense
	local planets = {}
	for i = 1, DefenseConfig.PlanetCount() do
		local entry = d.planets[tostring(i)]
		local unlocked, why = DefenseService.IsPlanetUnlocked(profile, i)
		planets[i] = {
			best = if entry then entry.best else 0,
			stars = if entry then table.clone(entry.stars) else {},
			unlocked = unlocked,
			why = why,
		}
	end
	-- Kaidedeki ekip: istemci gezegendeyken üssü akışta (streaming) olmayabilir
	local crew = {}
	local hospital = {}
	local plot = PlotService.GetPlotOf(player)
	if plot then
		for _, podium in PlotService.GetPodiums(plot) do
			local unitId = podium:GetAttribute("UnitId") :: string
			if unitId == "" then
				continue
			end
			local m = podium:GetAttribute("MutationId") :: string
			local mutationId = if m == "" then nil else m
			table.insert(crew, {
				slot = podium:GetAttribute("SlotIndex"),
				unitId = unitId,
				mutationId = mutationId,
				away = PlotService.GetAway(podium),
			})
			if PlotService.GetAway(podium) == "hospital" then
				table.insert(hospital, {
					slot = podium:GetAttribute("SlotIndex"),
					unitId = unitId,
					mutationId = mutationId,
					cost = DefenseService.GetReviveCost(player, unitId, mutationId),
				})
			end
		end
	end
	return {
		gold = d.gold,
		slots = DefenseConfig.GetSlots(d.slots),
		slotLevel = d.slots,
		saber = d.saber,
		hull = DefenseConfig.GetHull(d.hull),
		hullLevel = d.hull,
		roles = table.clone(d.roles),
		supports = table.clone(d.supports),
		planets = planets,
		crew = crew,
		hospital = hospital,
	}
end

function DefenseService.PushData(player: Player)
	local payload = dataPayload(player)
	if payload then
		send(player, "data", payload)
	end
end

local function runPayload(run: Run): any
	local units = {}
	for _, u in run.units do
		if not u.fallen then
			table.insert(units, {
				uid = u.uid, slot = u.slot, unitId = u.unitId, mutationId = u.mutationId,
				x = u.pos.X, z = u.pos.Y, role = DefenseConfig.GetRole(u.unitId).id,
			})
		end
	end
	local counts = {}
	for _, spawn in run.plan.spawns do
		counts[spawn.kind] = (counts[spawn.kind] or 0) + 1
	end
	local per = DefenseConfig.WavesPerSector
	return {
		planet = run.planet,
		arena = run.arena,
		sector = math.floor((run.wave - 1) / per) + 1,
		wave = run.wave,
		waveInSector = (run.wave - 1) % per + 1,
		phase = run.phase,
		hull = run.hull,
		maxHull = run.maxHull,
		units = units,
		sectorLosses = run.sectorLosses,
		plan = { name = run.plan.name, pattern = run.plan.pattern, paths = run.plan.paths, counts = counts, boss = run.plan.boss },
		goldEarned = run.goldEarned,
	}
end

local function pushRun(player: Player)
	local s = sessions[player]
	local run = s and s.run
	send(player, "run", if run then runPayload(run) else nil)
end

local function aliveDeployed(run: Run): number
	local n = 0
	for _, u in run.units do
		if not u.fallen then
			n += 1
		end
	end
	return n
end

local function refreshDeployedFlag(player: Player)
	local s = sessions[player]
	local run = s and s.run
	player:SetAttribute("DefenseDeployed", if run and aliveDeployed(run) > 0 then true else nil)
end

-- ─── Koşu ───────────────────────────────────────────────────────────────────

local function preparePlan(run: Run)
	run.plan = DefenseConfig.BuildWave(run.planet, run.wave, run.seed, run.lastPattern)
end

--[[ Koşuyu bitirir. Ayakta kalanlar `toHospital` ise hastaneye, değilse kaideye. ]]
local function endRun(player: Player, toHospital: boolean, reason: string)
	local s = sessions[player]
	local run = s and s.run
	if not (s and run) then
		return
	end
	local fell = 0
	for _, u in run.units do
		local podium = podiumBySlot(player, u.slot)
		if podium and PlotService.GetAway(podium) == "mission" then
			if toHospital then
				PlotService.SetAway(podium, "hospital")
				fell += 1
			else
				PlotService.SetAway(podium, nil)
			end
		end
	end
	s.run = nil
	refreshDeployedFlag(player)
	send(player, "over", {
		reason = reason,
		wave = run.wave,
		wavesCleared = run.wavesCleared,
		gold = run.goldEarned,
		fell = fell,
	})
	pushRun(player)
	DefenseService.PushData(player)
end

local function valid(n: any): boolean
	return typeof(n) == "number" and n == n and math.abs(n) < 1e6
end

local function positionOk(run: Run, pos: Vector2, ignoreUid: number?): (boolean, string?)
	local F = DefenseConfig.Field
	if math.abs(pos.X) > F.halfWidth or pos.Y < F.zMin or pos.Y > F.zMax then
		return false, "Place your crew inside the field"
	end
	for _, u in run.units do
		if not u.fallen and u.uid ~= ignoreUid and (u.pos - pos).Magnitude < DefenseConfig.UnitSpacing then
			return false, "Too close to another crewmate"
		end
	end
	return true, nil
end

local function begin(player: Player, sector: number)
	local s = session(player)
	local profile = DataService.Get(player)
	if not (profile and s.planet) or s.run then
		return
	end
	local entry = planetEntry(profile, s.planet)
	local maxSector = entry.best + 1
	sector = math.clamp(math.floor(sector), 1, maxSector)
	local hull = DefenseConfig.GetHull(profile.defense.hull)
	local run: Run = {
		planet = s.planet,
		arena = s.arena or 1,
		sector = sector,
		wave = (sector - 1) * DefenseConfig.WavesPerSector + 1,
		phase = "prep",
		units = {},
		nextUid = 1,
		hull = hull,
		maxHull = hull,
		seed = Random.new():NextInteger(1, 2 ^ 30),
		lastPattern = nil,
		plan = nil :: any,
		sim = nil,
		sectorLosses = 0,
		used = {},
		acc = 0,
		sendAcc = 0,
		pending = {},
		wavesCleared = 0,
		goldEarned = 0,
	}
	preparePlan(run)
	s.run = run
	pushRun(player)
end

local function place(player: Player, slot: number, pos: Vector2)
	local s = sessions[player]
	local run = s and s.run
	local profile = DataService.Get(player)
	if not (run and profile) or run.phase ~= "prep" then
		return
	end
	if aliveDeployed(run) >= DefenseConfig.GetSlots(profile.defense.slots) then
		notify(player, "No free crew slots - buy more at the Command Shop", true)
		return
	end
	local podium = podiumBySlot(player, slot)
	if not (podium and PlotService.IsOccupied(podium)) then
		return
	end
	if PlotService.GetAway(podium) then
		notify(player, "That crewmate is already away", true)
		return
	end
	local ok, why = positionOk(run, pos, nil)
	if not ok then
		notify(player, why or "Can't place there", true)
		return
	end
	local unitId = podium:GetAttribute("UnitId") :: string
	local m = podium:GetAttribute("MutationId") :: string
	PlotService.SetAway(podium, "mission")
	table.insert(run.units, {
		uid = run.nextUid,
		slot = slot,
		unitId = unitId,
		mutationId = if m == "" then nil else m,
		pos = pos,
		fallen = false,
	})
	run.nextUid += 1
	refreshDeployedFlag(player)
	pushRun(player)
end

local function findDeployed(run: Run, uid: number): Deployed?
	for _, u in run.units do
		if u.uid == uid and not u.fallen then
			return u
		end
	end
	return nil
end

local function move(player: Player, uid: number, pos: Vector2)
	local s = sessions[player]
	local run = s and s.run
	if not run or run.phase ~= "prep" then
		return
	end
	local u = findDeployed(run, uid)
	if not u then
		return
	end
	local ok, why = positionOk(run, pos, uid)
	if not ok then
		notify(player, why or "Can't move there", true)
		pushRun(player)
		return
	end
	u.pos = pos
	pushRun(player)
end

local function recall(player: Player, uid: number)
	local s = sessions[player]
	local run = s and s.run
	if not run or run.phase ~= "prep" then
		return
	end
	for i, u in run.units do
		if u.uid == uid and not u.fallen then
			local podium = podiumBySlot(player, u.slot)
			if podium and PlotService.GetAway(podium) == "mission" then
				PlotService.SetAway(podium, nil)
			end
			table.remove(run.units, i)
			break
		end
	end
	refreshDeployedFlag(player)
	pushRun(player)
end

local function go(player: Player)
	local s = sessions[player]
	local run = s and s.run
	local profile = DataService.Get(player)
	if not (run and profile) or run.phase ~= "prep" then
		return
	end
	local inputs: { DefenseSim.UnitInput } = {}
	for _, u in run.units do
		if not u.fallen then
			table.insert(inputs, { uid = u.uid, unitId = u.unitId, mutationId = u.mutationId, pos = u.pos })
		end
	end
	if #inputs == 0 then
		notify(player, "Place at least one crewmate first", true)
		return
	end
	local sim = DefenseSim.New(run.planet, run.wave, run.seed, inputs, profile.defense.roles,
		run.hull, run.maxHull, run.lastPattern)
	run.sim = sim
	run.phase = "fight"
	run.used = {}
	run.acc = 0
	run.sendAcc = 0
	table.clear(run.pending)
	pushRun(player)
end

local function retreat(player: Player)
	local s = sessions[player]
	local run = s and s.run
	if not run then
		return
	end
	if run.phase ~= "prep" then
		notify(player, "You can't retreat in the middle of a wave", true)
		return
	end
	endRun(player, false, "retreat")
end

--[[ Bölüm bitti: yıldız ve (yeni yıldızsa) altın. ]]
local function finishSector(player: Player, run: Run, sectorIndex: number): (number, number, boolean)
	local profile = DataService.Get(player)
	if not profile then
		return 0, 0, false
	end
	local entry = planetEntry(profile, run.planet)
	local stars = DefenseConfig.StarsForLosses(run.sectorLosses)
	local key = tostring(sectorIndex)
	local had = entry.stars[key] or 0
	local gold = DefenseConfig.GoldForImprovement(run.planet, had, stars)
	if stars > had then
		entry.stars[key] = stars
	end
	local newBest = sectorIndex > entry.best
	if newBest then
		entry.best = sectorIndex
	end
	if gold > 0 then
		profile.defense.gold += gold
		profile.defense.goldEarned += gold
		run.goldEarned += gold
	end
	DataService.RequestSave(player)
	return stars, gold, newBest
end

local function onWaveEnd(player: Player, run: Run, sim: DefenseSim.Sim)
	run.sim = nil
	run.hull = sim.hull
	run.lastPattern = run.plan.pattern
	if sim.state == "lost" then
		send(player, "waveEnd", { won = false, wave = run.wave, losses = sim.losses })
		endRun(player, true, "lost")
		return
	end

	local finished = run.wave
	run.wavesCleared += 1
	local result: { [string]: any } = { won = true, wave = finished, losses = sim.losses, kills = sim.kills }
	if finished % DefenseConfig.WavesPerSector == 0 then
		local sectorIndex = finished // DefenseConfig.WavesPerSector
		local stars, gold, newBest = finishSector(player, run, sectorIndex)
		result.sector = sectorIndex
		result.stars = stars
		result.gold = gold
		result.newBest = newBest
		run.sectorLosses = 0
		-- Bölüm arasında gövde tamir
		run.hull = run.maxHull
	end
	run.wave += 1
	run.phase = "prep"
	preparePlan(run)
	-- Düşenler sahadan çıktı (hastanede)
	for i = #run.units, 1, -1 do
		if run.units[i].fallen then
			table.remove(run.units, i)
		end
	end
	refreshDeployedFlag(player)
	send(player, "waveEnd", result)
	pushRun(player)
	DefenseService.PushData(player)
	if aliveDeployed(run) == 0 then
		-- Ayakta kimse kalmadı ama dalga kazanıldı: koşu sürüyor, yeni crewmate konabilir
		notify(player, "Your whole crew is in the hospital - send in fresh crewmates!", false)
	end
end

local function processEvents(player: Player, run: Run, sim: DefenseSim.Sim)
	for _, ev in sim.events do
		if ev[1] == "ufall" then
			local uid = ev[2]
			for _, u in run.units do
				if u.uid == uid and not u.fallen then
					u.fallen = true
					run.sectorLosses += 1
					local podium = podiumBySlot(player, u.slot)
					if podium and PlotService.GetAway(podium) == "mission" then
						PlotService.SetAway(podium, "hospital")
					end
				end
			end
		end
		table.insert(run.pending, ev)
	end
	table.clear(sim.events)
end

local function snapshot(sim: DefenseSim.Sim): any
	local enemies = table.create(#sim.enemies)
	for _, e in sim.enemies do
		table.insert(enemies, {
			e.eid,
			math.floor(e.pos.X * 10 + 0.5) / 10,
			math.floor(e.pos.Y * 10 + 0.5) / 10,
			math.floor(e.hp / e.maxHp * 100 + 0.5) / 100,
			e.foe or 0,
		})
	end
	local units = {}
	for _, u in sim.units do
		table.insert(units, { u.uid, math.floor(u.hp / u.maxHp * 100 + 0.5) / 100 })
	end
	return { t = sim.time, hull = sim.hull, e = enemies, u = units }
end

local function stepAll(dt: number)
	for player, s in sessions do
		local run = s.run
		local sim = run and run.sim
		if not (run and sim) then
			continue
		end
		run.acc += dt
		local steps = 0
		while run.acc >= STEP and sim.state == "fight" and steps < 5 do
			run.acc -= STEP
			steps += 1
			DefenseSim.Step(sim, STEP)
			processEvents(player, run, sim)
		end
		run.sendAcc += dt
		if run.sendAcc >= SEND_EVERY or sim.state ~= "fight" then
			run.sendAcc = 0
			local snap = snapshot(sim)
			snap.ev = run.pending
			run.pending = {}
			send(player, "tick", snap)
		end
		if sim.state ~= "fight" then
			onWaveEnd(player, run, sim)
		end
	end
end

local function useSupport(player: Player, id: string, pos: Vector2?)
	local s = sessions[player]
	local run = s and s.run
	local sim = run and run.sim
	local profile = DataService.Get(player)
	if not (run and sim and profile) or run.phase ~= "fight" then
		return
	end
	local def = DefenseConfig.GetSupport(id)
	if not def then
		return
	end
	if run.used[id] then
		notify(player, def.name .. " already used this wave", true)
		return
	end
	local have = profile.defense.supports[id] or 0
	if have <= 0 then
		notify(player, "Buy " .. def.name .. " at the Market", true)
		return
	end
	if id == "Strike" then
		if not pos then
			return
		end
		DefenseSim.Strike(sim, pos)
	elseif id == "MedDrop" then
		DefenseSim.MedDrop(sim)
	elseif id == "Freeze" then
		DefenseSim.Freeze(sim)
	else
		return
	end
	run.used[id] = true
	profile.defense.supports[id] = if have - 1 > 0 then have - 1 else nil
	processEvents(player, run, sim)
	DefenseService.PushData(player)
end

-- ─── Dükkânlar ──────────────────────────────────────────────────────────────

local function spendGold(player: Player, profile: DataService.Profile, cost: number): boolean
	if profile.defense.gold < cost then
		notify(player, string.format("Not enough gold (%d needed)", cost), true)
		return false
	end
	profile.defense.gold -= cost
	return true
end

function DefenseService.Buy(player: Player, kind: string, id: string?): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local d = profile.defense
	if kind == "role" then
		local role = id and DefenseConfig.Roles[id]
		if not role then
			return false
		end
		local level = d.roles[role.id] or 0
		local cost = DefenseConfig.RoleUpgradeCost(level)
		if not cost then
			notify(player, role.name .. " is maxed", true)
			return false
		end
		if not spendGold(player, profile, cost) then
			return false
		end
		d.roles[role.id] = level + 1
		notify(player, string.format("%s upgraded to level %d", role.name, level + 1), false, "upgrade")
	elseif kind == "slot" then
		local cost = DefenseConfig.SlotCosts[d.slots + 1]
		if not cost then
			notify(player, "Crew slots maxed", true)
			return false
		end
		if not spendGold(player, profile, cost) then
			return false
		end
		d.slots += 1
		notify(player, string.format("Crew slots: %d", DefenseConfig.GetSlots(d.slots)), false, "upgrade")
	elseif kind == "hull" then
		local cost = DefenseConfig.HullCosts[d.hull + 1]
		if not cost then
			notify(player, "Hull maxed", true)
			return false
		end
		if not spendGold(player, profile, cost) then
			return false
		end
		d.hull += 1
		notify(player, string.format("Ship hull: %d", DefenseConfig.GetHull(d.hull)), false, "upgrade")
	elseif kind == "saber" then
		local S = DefenseConfig.Saber
		local cost = if d.saber == 0 then S.price else S.upgradeCosts[d.saber]
		if not cost then
			notify(player, "Lightsaber is maxed", true)
			return false
		end
		if not spendGold(player, profile, cost) then
			return false
		end
		d.saber += 1
		notify(player, if d.saber == 1 then "Lightsaber unlocked! Swing it on the battlefield"
			else string.format("Lightsaber level %d", d.saber), false, "upgrade")
		DefenseService.GiveSaber(player)
	elseif kind == "support" then
		local def = id and DefenseConfig.GetSupport(id)
		if not def then
			return false
		end
		local have = d.supports[def.id] or 0
		if have >= DefenseConfig.SupportStack then
			notify(player, string.format("You can carry %d at most", DefenseConfig.SupportStack), true)
			return false
		end
		if not spendGold(player, profile, def.price) then
			return false
		end
		d.supports[def.id] = have + 1
		notify(player, def.name .. " bought", false, "buy")
	else
		return false
	end
	DataService.RequestSave(player)
	DefenseService.PushData(player)
	return true
end

-- ─── Hastane ────────────────────────────────────────────────────────────────

function DefenseService.Revive(player: Player, slot: number): boolean
	local podium = podiumBySlot(player, slot)
	if not (podium and PlotService.GetAway(podium) == "hospital") then
		return false
	end
	local unitId = podium:GetAttribute("UnitId") :: string
	local m = podium:GetAttribute("MutationId") :: string
	local cost = DefenseService.GetReviveCost(player, unitId, if m == "" then nil else m)
	if not EconomyService.TrySpend(player, cost) then
		notify(player, string.format("Revive costs $%s", Config.FormatCash(cost)), true)
		return false
	end
	PlotService.SetAway(podium, nil)
	local def = Config.GetUnit(unitId)
	notify(player, string.format("%s is back on its podium!", if def then def.name else "Crewmate"), false, "reward")
	DefenseService.PushData(player)
	return true
end

function DefenseService.Release(player: Player, slot: number): boolean
	local podium = podiumBySlot(player, slot)
	if not (podium and PlotService.GetAway(podium) == "hospital") then
		return false
	end
	PlotService.ClearUnit(podium)
	notify(player, "Crewmate let go", false, "sell")
	DefenseService.PushData(player)
	return true
end

-- ─── İniş / kalkış ──────────────────────────────────────────────────────────

local function teleport(player: Player, cf: CFrame)
	local character = player.Character
	if not character then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 5)
	end)
	PlotService.Unseat(character)
	character:PivotTo(cf)
end

local function homeCFrame(): CFrame
	if navSpot then
		return navSpot
	end
	return CFrame.new(0, 8, 0)
end

function DefenseService.Land(player: Player, planet: number): boolean
	local s = session(player)
	local profile = DataService.Get(player)
	if not profile or s.busy or s.planet then
		return false
	end
	if player:GetAttribute("InSpace") == true or player:GetAttribute("SpaceCarry") == true then
		notify(player, "Come back aboard first", true)
		return false
	end
	local ok, why = DefenseService.IsPlanetUnlocked(profile, planet)
	if not ok then
		notify(player, why or "Locked", true)
		return false
	end
	-- Boştaki ilk arena
	local arena: number? = nil
	for i = 1, DefenseConfig.MaxArenas do
		local owner = arenaOwner[i]
		if not owner or not owner.Parent or owner == player then
			arena = i
			break
		end
	end
	if not arena then
		notify(player, "All landing zones are busy - try again in a moment", true)
		return false
	end
	arenaOwner[arena] = player
	local world = PlanetWorldService.Get(planet, arena)
	if not world then
		arenaOwner[arena] = nil
		return false
	end
	s.busy = true
	s.arena = arena
	send(player, "landing", { planet = planet, arena = arena })
	task.delay(LAND_DELAY, function()
		s.busy = false
		if not player.Parent then
			return
		end
		s.planet = planet
		player:SetAttribute("DefensePlanet", planet)
		player:SetAttribute("DefenseArena", arena)
		teleport(player, PlanetWorldService.SpawnCFrame(arena))
		send(player, "arrived", { planet = planet, arena = arena })
		DefenseService.PushData(player)
		DefenseService.GiveSaber(player)
	end)
	return true
end

local function releaseArena(player: Player)
	for i, owner in arenaOwner do
		if owner == player then
			arenaOwner[i] = nil
		end
	end
end

function DefenseService.TakeOff(player: Player): boolean
	local s = session(player)
	if s.busy or not s.planet then
		return false
	end
	local run = s.run
	if run then
		if run.phase == "fight" then
			notify(player, "Finish the wave first!", true)
			return false
		end
		endRun(player, false, "retreat")
	end
	s.busy = true
	send(player, "launch", s.planet)
	task.delay(LAUNCH_DELAY, function()
		s.busy = false
		s.planet = nil
		s.arena = nil
		releaseArena(player)
		if not player.Parent then
			return
		end
		player:SetAttribute("DefensePlanet", nil)
		player:SetAttribute("DefenseArena", nil)
		DefenseService.TakeSaber(player)
		teleport(player, homeCFrame())
		send(player, "home", nil)
	end)
	return true
end

-- ─── Işın kılıcı ────────────────────────────────────────────────────────────

local SABER_COLORS = {
	Color3.fromRGB(80, 170, 255), Color3.fromRGB(90, 255, 120), Color3.fromRGB(190, 90, 255),
	Color3.fromRGB(255, 60, 70), Color3.fromRGB(255, 210, 60),
}

local function slash(player: Player)
	local s = sessions[player]
	local run = s and s.run
	local sim = run and run.sim
	local profile = DataService.Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (s and run and sim and profile and root and s.arena) or run.phase ~= "fight" then
		return
	end
	local now = os.clock()
	if now - s.lastSlash < DefenseConfig.Saber.cooldown then
		return
	end
	s.lastSlash = now
	local rel = root.Position - DefenseConfig.WorldOrigin(s.arena)
	local look = root.CFrame.LookVector
	DefenseSim.Slash(sim, Vector2.new(rel.X, rel.Z), Vector2.new(look.X, look.Z), DefenseConfig.Saber.radius,
		DefenseConfig.SaberDamage(profile.defense.saber, sim.hpMul))
	processEvents(player, run, sim)
end

--[[ Gezegendeyken ve kılıcı varsa sırt çantasına (seviyenin renginde) verir. ]]
function DefenseService.GiveSaber(player: Player)
	local s = sessions[player]
	local profile = DataService.Get(player)
	if not (s and s.arena and profile) or profile.defense.saber <= 0 then
		return
	end
	DefenseService.TakeSaber(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local level = profile.defense.saber
	local color = SABER_COLORS[math.clamp(level, 1, #SABER_COLORS)]
	local tool = Instance.new("Tool")
	tool.Name = "Lightsaber"
	tool.ToolTip = "Lightsaber Lv " .. level
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("DefenseSaber", level)
	-- Klasik kılıç tutuşu: sap -Z ucunda, bıçak +Z yönünde yukarı
	tool.GripPos = Vector3.new(0, 0, -3.1)
	tool.GripForward = Vector3.new(-1, 0, 0)
	tool.GripRight = Vector3.new(0, 1, 0)
	tool.GripUp = Vector3.new(0, 0, 1)
	local blade = Instance.new("Part")
	blade.Name = "Handle"
	blade.Size = Vector3.new(0.32, 0.32, 5)
	blade.Material = Enum.Material.Neon
	blade.Color = color
	blade.CanCollide = false
	blade.Massless = true
	blade.Parent = tool
	local hilt = Instance.new("Part")
	hilt.Name = "Hilt"
	hilt.Size = Vector3.new(0.5, 0.5, 1.4)
	hilt.Color = Color3.fromRGB(70, 74, 86)
	hilt.Material = Enum.Material.Metal
	hilt.CanCollide = false
	hilt.Massless = true
	hilt.CFrame = blade.CFrame * CFrame.new(0, 0, -3.1)
	hilt.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = blade
	weld.Part1 = hilt
	weld.Parent = blade
	local glowLight = Instance.new("PointLight")
	glowLight.Color = color
	glowLight.Range = 10
	glowLight.Brightness = 2
	glowLight.Parent = blade
	tool.Activated:Connect(function()
		slash(player)
	end)
	tool.Parent = backpack
end

function DefenseService.TakeSaber(player: Player)
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, item in container:GetChildren() do
				if item:IsA("Tool") and item:GetAttribute("DefenseSaber") ~= nil then
					item:Destroy()
				end
			end
		end
	end
end

-- ─── Remote ─────────────────────────────────────────────────────────────────

local function onAction(player: Player, action: any, a: any, b: any, c: any)
	if typeof(action) ~= "string" or not DefenseConfig.IsEnabled() then
		return
	end
	local s = session(player)
	local now = os.clock()
	if now - s.lastAction < 0.08 then
		return
	end
	s.lastAction = now

	if action == "sync" then
		DefenseService.PushData(player)
		pushRun(player)
		return
	elseif action == "land" then
		DefenseService.Land(player, DefenseConfig.OnlyPlanet)
		return
	elseif action == "revive" then
		if valid(a) and s.planet then
			DefenseService.Revive(player, math.floor(a))
		end
		return
	elseif action == "release" then
		if valid(a) and s.planet then
			DefenseService.Release(player, math.floor(a))
		end
		return
	elseif action == "buy" then
		if typeof(a) == "string" and (b == nil or typeof(b) == "string") and s.planet then
			DefenseService.Buy(player, a, b)
		end
		return
	end

	-- Buradan sonrası gezegendeyken
	if not s.planet or s.busy then
		return
	end
	if action == "takeoff" then
		DefenseService.TakeOff(player)
	elseif action == "command" then
		-- Ekrandaki DEFEND düğmesi: konsola yürümeden taktik görünüm
		DefenseService.PushData(player)
		pushRun(player)
		send(player, "command", s.planet)
	elseif action == "begin" then
		if valid(a) then
			begin(player, a)
		end
	elseif action == "place" then
		if valid(a) and valid(b) and valid(c) then
			place(player, math.floor(a), Vector2.new(b, c))
		end
	elseif action == "move" then
		if valid(a) and valid(b) and valid(c) then
			move(player, math.floor(a), Vector2.new(b, c))
		end
	elseif action == "recall" then
		if valid(a) then
			recall(player, math.floor(a))
		end
	elseif action == "go" then
		go(player)
	elseif action == "retreat" then
		retreat(player)
	elseif action == "support" then
		if typeof(a) == "string" then
			useSupport(player, a, if valid(b) and valid(c) then Vector2.new(b, c) else nil)
		end
	end
end

local function onPrompt(player: Player, arena: number, kind: string)
	local s = session(player)
	if not s.planet or s.arena ~= arena then
		return
	end
	if kind == "takeoff" then
		DefenseService.TakeOff(player)
		return
	end
	DefenseService.PushData(player)
	if kind == "command" then
		pushRun(player)
		send(player, "command", s.planet)
	else
		send(player, "open", kind)
	end
end

-- ─── Pilot paneli ───────────────────────────────────────────────────────────

local function setupPilot()
	local decor = workspace:FindFirstChild("Decor")
	local landmarks = decor and decor:FindFirstChild("Landmarks")
	local nav = landmarks and landmarks:FindFirstChild("Navigation")
	local dash = nav and nav:FindFirstChild("Dash")
	if not (dash and dash:IsA("BasePart")) then
		warn("[DefenseService] Navigation/Dash bulunamadı: PILOT istemi yok")
		return
	end
	-- Dönüş noktası: pilot koltuklarının arkası (dash'in batısı)
	navSpot = CFrame.lookAt(dash.Position + Vector3.new(-18, 3, 0), dash.Position + Vector3.new(0, 3, 0))
	local old = dash:FindFirstChild("PilotPrompt")
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PilotPrompt"
	prompt.ActionText = "Pilot"
	prompt.ObjectText = "LAND ON A PLANET"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = dash
	PromptGuard.Connect(prompt, function(player)
		if session(player).planet then
			return
		end
		-- Tek gezegen: seçim penceresi yok, doğrudan iniş
		DefenseService.Land(player, DefenseConfig.OnlyPlanet)
	end)
end

-- ─── Yaşam döngüsü ──────────────────────────────────────────────────────────

local function onCharacterAdded(player: Player, character: Model)
	local s = sessions[player]
	if not (s and s.planet) then
		return
	end
	-- Gezegende ölen / sıfırlayan oyuncu gemide değil gezegende doğuyor
	local arena = s.arena
	task.defer(function()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and arena and s.arena == arena and player.Parent then
			teleport(player, PlanetWorldService.SpawnCFrame(arena))
			DefenseService.GiveSaber(player)
		end
	end)
end

function DefenseService.Start()
	stateRemote = Net.Get("DefenseState")
	notifyRemote = Net.Get("Notify")
	-- Remote dinleniyor ama kapalıyken her şeyi reddediyor (onAction)
	Net.Get("Defense").OnServerEvent:Connect(onAction)
	if not DefenseConfig.IsEnabled() then
		return
	end
	PlanetWorldService.Start()
	PlanetWorldService.OnPrompt(onPrompt)
	-- İlk inen beklemesin: ilk arena sunucu açılırken kuruluyor
	task.spawn(PlanetWorldService.Get, DefenseConfig.OnlyPlanet, 1)
	setupPilot()

	-- Çıkışta: dalga ortasındaysa sahadakiler hastaneye, değilse kaideye
	-- (son kayıttan önce; PlotService o sırada profile yazmıyor)
	DataService.OnBeforeRelease(function(player, profile)
		local s = sessions[player]
		local run = s and s.run
		local fighting = run ~= nil and run.phase == "fight"
		for _, entry in profile.units do
			if entry.away == "mission" then
				entry.away = if fighting then "hospital" else nil
			end
		end
	end)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		releaseArena(player)
		-- OnBeforeRelease koşuyu okuyabilsin diye biraz sonra
		task.delay(5, function()
			if not player.Parent then
				sessions[player] = nil
			end
		end)
	end)

	RunService.Heartbeat:Connect(function(dt)
		stepAll(math.min(dt, 0.25))
	end)
end

-- Testler için
DefenseService._sessions = sessions
DefenseService._begin = begin
DefenseService._place = place
DefenseService._go = go
DefenseService._step = stepAll
DefenseService._retreat = retreat
function DefenseService._setPlanet(player: Player, planet: number?)
	local s = session(player)
	s.planet = planet
	s.arena = if planet then 1 else nil
end

return DefenseService
