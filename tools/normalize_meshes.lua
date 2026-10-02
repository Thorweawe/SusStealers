-- Import 3D ile workspace'e gelen modelleri şablona çevirir (Studio'da run_code).
-- Ad -> { Id, ölçü, taban/yer, klasör, Y dönüşü (derece), kip }
--   kip "h": boy = ölçü, taban = yer (canavar/karakter, ayak tabanı y)
--   kip "w": genişlik = ölçü, alt = yer (şapka: karakterin kafasına oturur)
-- Y dönüşü: TRELLIS her modelin önünü aynı eksene koymuyor; Studio'da önden/
-- arkadan bakılarak bulundu (2026-10-01). *_rig / *_lo dosyaları split_mesh'in
-- 180°'sini almadığı için onlarda +180 eklenmiş hâli yazılı.
local SPEC = {
	-- eski (split_mesh, zaten 180° çevrilmiş) dosyalar
	glorp_roblox = { "Glorp", 16.0, -0.6, "MonsterMeshes", 180, "h" },
	kraken_roblox = { "Kraken", 21.1, 0.5, "MonsterMeshes", 0, "h" },
	sandmaw_roblox = { "SandMaw", 28.6, -1.7, "MonsterMeshes", 0, "h" },
	riftstalker_roblox = { "RiftStalker", 16.5, 0, "MonsterMeshes", 90, "h" },
	voidleviathan_roblox = { "VoidLeviathan", 28.9, -0.3, "MonsterMeshes", 180, "h" },
	frostwyrm_roblox = { "FrostWyrm", 17.9, 1.3, "MonsterMeshes", 180, "h" },
	crystalgolem_roblox = { "CrystalGolem", 18.8, -0.1, "MonsterMeshes", 180, "h" },
	solarphoenix_roblox = { "SolarPhoenix", 18.3, 0.9, "MonsterMeshes", 0, "h" },
	blackhole_roblox = { "BlackHole", 17.5, 0.2, "MonsterMeshes", 0, "h" },
	galaxytitan_roblox = { "GalaxyTitan", 27.6, -0.4, "MonsterMeshes", 180, "h" },
	ejected_roblox = { "Ejected", 5.4, 0, "UnitMeshes", 180, "h" },
	-- iskeletli (tools/auto_rig.py) tek parça boss'lar
	chomper_rig = { "Chomper", 17.0, 0, "MonsterMeshes", 180, "h" },
	glorp_rig = { "Glorp", 16.0, -0.6, "MonsterMeshes", 0, "h" },
	kraken_rig = { "Kraken", 21.1, 0.5, "MonsterMeshes", 180, "h" },
	kraken_rigged = { "Kraken", 21.1, 0.5, "MonsterMeshes", 180, "h" }, -- UniRig (daha ince dokunaç zinciri)
	sandmaw_rig = { "SandMaw", 28.6, -1.7, "MonsterMeshes", 180, "h" },
	riftstalker_rig = { "RiftStalker", 16.5, 0, "MonsterMeshes", 270, "h" },
	voidleviathan_rig = { "VoidLeviathan", 28.9, -0.3, "MonsterMeshes", 0, "h" },
	frostwyrm_rig = { "FrostWyrm", 17.9, 1.3, "MonsterMeshes", 0, "h" },
	crystalgolem_rig = { "CrystalGolem", 18.8, -0.1, "MonsterMeshes", 0, "h" },
	solarphoenix_rig = { "SolarPhoenix", 18.3, 0.9, "MonsterMeshes", 180, "h" },
	blackhole_rig = { "BlackHole", 17.5, 0.2, "MonsterMeshes", 180, "h" },
	galaxytitan_rig = { "GalaxyTitan", 27.6, -0.4, "MonsterMeshes", 0, "h" },
	ejected_lo = { "Ejected", 5.4, 0, "UnitMeshes", 0, "h" },
	-- nadirlik şapkaları (kafa merkezi y=3.0, yarıçap ~1.03, üstü ~4.0)
	hat_uncommon_lo = { "Uncommon", 2.25, 3.45, "HatMeshes", 180, "w" },
	hat_rare_lo = { "Rare", 2.45, 2.55, "HatMeshes", 180, "w" },
	hat_epic_lo = { "Epic", 2.7, 3.7, "HatMeshes", 180, "w" },
	hat_legendary_lo = { "Legendary", 2.15, 3.7, "HatMeshes", 180, "w" },
	hat_mythic_lo = { "Mythic", 2.8, 3.65, "HatMeshes", 180, "w" },
	hat_secret_lo = { "Secret", 2.6, 3.55, "HatMeshes", 180, "w" },
	hat_celestial_lo = { "Celestial", 2.7, 3.55, "HatMeshes", 180, "w" },
}
local out = {}
for _, m in workspace:GetChildren() do
	local spec = m:IsA("Model") and SPEC[m.Name]
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
		-- önce dönüş (genişlik ölçümü yöne bağlı)
		if spec[5] ~= 0 then
			local pivot = m:GetPivot()
			m:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, math.rad(spec[5]), 0) * pivot.Rotation)
		end
		local lo, hi = aabb()
		local cur = if spec[6] == "w" then math.max(hi.X - lo.X, hi.Z - lo.Z) else hi.Y - lo.Y
		m:ScaleTo(m:GetScale() * spec[2] / cur)
		lo, hi = aabb()
		m:PivotTo(m:GetPivot() + Vector3.new(-(lo.X + hi.X) / 2, spec[3] - lo.Y, -(lo.Z + hi.Z) / 2))
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then p.Anchored = true p.CanCollide = false end
		end
		local folder = game.ReplicatedStorage:FindFirstChild(spec[4]) or Instance.new("Folder")
		folder.Name = spec[4]
		folder.Parent = game.ReplicatedStorage
		local old = folder:FindFirstChild(spec[1])
		if old then old:Destroy() end
		m.Name = spec[1]
		m.Parent = folder
		local n, b = 0, 0
		for _, p in m:GetDescendants() do
			if p:IsA("MeshPart") then n += 1 elseif p:IsA("Bone") then b += 1 end
		end
		lo, hi = aabb()
		table.insert(out, string.format("%s.%s: %d ağ, %d kemik, boyut %s", spec[4], spec[1], n, b, tostring(hi - lo)))
	end
end
print(#out == 0 and "workspace'te tanınan model yok" or table.concat(out, "\n"))
