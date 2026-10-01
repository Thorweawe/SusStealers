-- Import 3D ile workspace'e gelen <ad>_roblox modellerini şablona çevirir:
-- boy = parça modelinin boyu, taban = parça modelinin tabanı, x/z merkezli,
-- ReplicatedStorage.MonsterMeshes / UnitMeshes altına <Id> adıyla.
-- 5. alan: ek Y dönüşü (derece). TRELLIS her modelin önünü aynı eksene
-- koymuyor; 2026-10-01 importunda Studio'da önden/arkadan bakılarak bulundu.
local SPEC = {
	glorp = { "Glorp", 16.0, -0.6, "MonsterMeshes", 180 },
	kraken = { "Kraken", 21.1, 0.5, "MonsterMeshes" },
	sandmaw = { "SandMaw", 28.6, -1.7, "MonsterMeshes" },
	riftstalker = { "RiftStalker", 16.5, 0, "MonsterMeshes", 90 },
	voidleviathan = { "VoidLeviathan", 28.9, -0.3, "MonsterMeshes", 180 },
	frostwyrm = { "FrostWyrm", 17.9, 1.3, "MonsterMeshes", 180 },
	crystalgolem = { "CrystalGolem", 18.8, -0.1, "MonsterMeshes", 180 },
	solarphoenix = { "SolarPhoenix", 18.3, 0.9, "MonsterMeshes" },
	blackhole = { "BlackHole", 17.5, 0.2, "MonsterMeshes" },
	galaxytitan = { "GalaxyTitan", 27.6, -0.4, "MonsterMeshes", 180 },
	ejected = { "Ejected", 5.4, 0, "UnitMeshes", 180 },
}
local out = {}
for _, m in workspace:GetChildren() do
	local key = m:IsA("Model") and m.Name:match("^(%w+)_roblox$")
	local spec = key and SPEC[key]
	if spec then
		local function aabb()
			local lo, hi = Vector3.one * 1e9, -Vector3.one * 1e9
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") then
					local c, s = p.CFrame, p.Size
					for _, sx in { -1, 1 } do for _, sy in { -1, 1 } do for _, sz in { -1, 1 } do
						local w = c:PointToWorldSpace(Vector3.new(sx * s.X / 2, sy * s.Y / 2, sz * s.Z / 2))
						lo = lo:Min(w) hi = hi:Max(w)
					end end end
				end
			end
			return lo, hi
		end
		local lo, hi = aabb()
		m:ScaleTo(m:GetScale() * spec[2] / (hi.Y - lo.Y))
		lo, hi = aabb()
		local shift = Vector3.new(-(lo.X + hi.X) / 2, spec[3] - lo.Y, -(lo.Z + hi.Z) / 2)
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.CFrame = p.CFrame + shift
				p.Anchored = true
			end
		end
		if spec[5] then
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") then p.CFrame = CFrame.Angles(0, math.rad(spec[5]), 0) * p.CFrame end
			end
		end
		local folder = game.ReplicatedStorage:FindFirstChild(spec[4]) or Instance.new("Folder")
		folder.Name = spec[4]
		folder.Parent = game.ReplicatedStorage
		local old = folder:FindFirstChild(spec[1])
		if old then old:Destroy() end
		m.Name = spec[1]
		m.Parent = folder
		local n = 0
		for _, p in m:GetDescendants() do if p:IsA("MeshPart") then n += 1 end end
		table.insert(out, string.format("%s -> %s.%s (%d ağ, boy %.1f)", key, spec[4], spec[1], n, hi.Y - lo.Y))
	end
end
print(#out == 0 and "workspace'te *_roblox modeli yok" or table.concat(out, "\n"))
