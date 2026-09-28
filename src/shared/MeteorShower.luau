--!strict
--[[
	Meteor Shower olayının göktaşları — sunucu ve istemci AYNI listeyi
	üretiyor (tohum + başlangıç anı, workspace "MeteorSeed"/"MeteorStart").
	Ağda göktaşı taşınmıyor: istemci çiziyor, sunucu çarpmayı ve yıldız
	parçalarını kendi hesabıyla yapıyor.

	Göktaşı uçuş alanının üstünden ve yanlarından çapraz dalıyor, alanın
	içinde rastgele bir hedefte sönüyor (gezegenlerin içine düşmüyor).
	Her ShardEvery'inci göktaşı söndüğü yerde parlayan bir YILDIZ PARÇASI
	bırakıyor (ilk dokunan alıyor, SpaceService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SpaceField = require(Shared.SpaceField)

local MeteorShower = {}

MeteorShower.Interval = 0.45   -- iki göktaşı arası (sn)
MeteorShower.Flight = 2.6      -- bir göktaşının uçuş süresi
MeteorShower.ShardEvery = 5
MeteorShower.HitRadius = 3.5   -- + göktaşı yarıçapı

export type Meteor = {
	index: number,
	t0: number,
	t1: number,
	from: Vector3,
	to: Vector3,
	size: number,
	shard: boolean,
}

--[[ Uçuş alanında, gezegenlerin dışında rastgele bir hedef. ]]
local function target(r: Random): Vector3
	local lo, hi = Config.Space.BoundsMin, Config.Space.BoundsMax
	for _ = 1, 20 do
		local deck = SpaceField.DeckCenter()
		local p = Vector3.new(
			r:NextNumber(lo.X + 20, hi.X - 20),
			r:NextNumber(deck.Y - 10, deck.Y + 50),
			r:NextNumber(lo.Z + 20, math.min(hi.Z, deck.Z) - 40))
		local clear = SpaceField.InSpace(p)
		for _, def in Config.SpaceMonsters do
			if (p - SpaceField.PlanetCenter(def)).Magnitude < def.radius + 10 then
				clear = false
				break
			end
		end
		if clear then
			return p
		end
	end
	return SpaceField.DeckCenter() + Vector3.new(0, 20, -120)
end

function MeteorShower.Build(seed: number, startAt: number, duration: number): { Meteor }
	local r = Random.new(seed)
	local list: { Meteor } = {}
	local count = math.floor(duration / MeteorShower.Interval)
	for i = 1, count do
		local to = target(r)
		-- Yukarıdan ve bir yandan çapraz geliyor
		local dir = Vector3.new(r:NextNumber(-1, 1), r:NextNumber(0.9, 1.4), r:NextNumber(-0.6, 0.6)).Unit
		local from = to + dir * r:NextNumber(160, 220)
		local t0 = startAt + (i - 1) * MeteorShower.Interval + r:NextNumber(0, MeteorShower.Interval * 0.6)
		table.insert(list, {
			index = i,
			t0 = t0,
			t1 = t0 + MeteorShower.Flight,
			from = from,
			to = to,
			size = r:NextNumber(2.2, 4.6),
			shard = i % MeteorShower.ShardEvery == 0,
		})
	end
	return list
end

--[[ `t` anında göktaşının yeri (uçmuyorsa nil). Sona doğru hızlanıyor. ]]
function MeteorShower.PositionAt(m: Meteor, t: number): Vector3?
	if t < m.t0 or t > m.t1 then
		return nil
	end
	local u = (t - m.t0) / (m.t1 - m.t0)
	return m.from:Lerp(m.to, u * u * 0.4 + u * 0.6)
end

return MeteorShower
