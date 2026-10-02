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
	-- kozmetik şapkalar (CosmeticModel; y=0 kafanın tepesi, kafa ~1.2 geniş) — ölçüler tahmini, Studio'da bakılacak
	pumpkinhead_lo = { "PumpkinHead", 1.9, -1.05, "CosmeticMeshes", 180, "w" },
	witchhat_lo = { "WitchHat", 2.2, -0.1, "CosmeticMeshes", 180, "w" },
	candycrown_lo = { "CandyCrown", 1.5, -0.1, "CosmeticMeshes", 180, "w" },
	-- etkinlik (LimitedFX boyunu kendisi ayarlıyor; burada yalnızca yön ve orta)
	ghost_lo = { "Ghost", 4, 0, "EventMeshes", 180, "h" },
	candy_lo = { "Candy", 3, 0, "EventMeshes", 0, "w" },
	star_lo = { "Star", 3, 0, "EventMeshes", 0, "w" },
	-- Starfall şapkaları (CosmeticMeshes)
	starvisor_lo = { "StarVisor", 1.6, -0.55, "CosmeticMeshes", 180, "w" },
	cometcrown_lo = { "CometCrown", 1.6, -0.1, "CosmeticMeshes", 180, "w" },
	galaxyhalo_lo = { "GalaxyHalo", 1.7, 0.1, "CosmeticMeshes", 180, "w" },
	-- petler (PetModel tasarım uzayı, 1.0 ölçek: boy ~2, taban y=0.15; ölçek ScaleTo ile sonra)
	bolt_lo = { "Bolt", 2.0, 0.15, "PetMeshes", 180, "h" },
	ventrat_lo = { "VentRat", 2.0, 0.15, "PetMeshes", 180, "h" },
	hamster_lo = { "Hamster", 2.0, 0.15, "PetMeshes", 180, "h" },
	sparepod_lo = { "SparePod", 2.0, 0.15, "PetMeshes", 180, "h" },
	fuelcan_lo = { "FuelCan", 2.0, 0.15, "PetMeshes", 180, "h" },
	minicrew_lo = { "MiniCrew", 2.0, 0.15, "PetMeshes", 180, "h" },
	brainslug_lo = { "BrainSlug", 2.0, 0.15, "PetMeshes", 180, "h" },
	taskbot_lo = { "TaskBot", 2.0, 0.15, "PetMeshes", 180, "h" },
	meddrone_lo = { "MedDrone", 2.0, 0.15, "PetMeshes", 180, "h" },
	securitycam_lo = { "SecurityCam", 2.0, 0.15, "PetMeshes", 180, "h" },
	primeshield_lo = { "PrimeShield", 2.0, 0.15, "PetMeshes", 180, "h" },
	snowpal_lo = { "SnowPal", 2.0, 0.15, "PetMeshes", 180, "h" },
	ventcrab_lo = { "VentCrab", 2.0, 0.15, "PetMeshes", 180, "h" },
	coreshard_lo = { "CoreShard", 2.0, 0.15, "PetMeshes", 180, "h" },
	escapepod_lo = { "EscapePod", 2.0, 0.15, "PetMeshes", 180, "h" },
	susshadow_lo = { "SusShadow", 2.0, 0.15, "PetMeshes", 180, "h" },
	meetingbell_lo = { "MeetingBell", 2.0, 0.15, "PetMeshes", 180, "h" },
	theegg_lo = { "TheEgg", 2.0, 0.15, "PetMeshes", 180, "h" },
	voidmite_lo = { "VoidMite", 2.0, 0.15, "PetMeshes", 180, "h" },
	starjelly_lo = { "StarJelly", 2.0, 0.15, "PetMeshes", 180, "h" },
	cometpup_lo = { "CometPup", 2.0, 0.15, "PetMeshes", 180, "h" },
	ghostcrew_lo = { "GhostCrew", 2.0, 0.15, "PetMeshes", 180, "h" },
	miniimp_lo = { "MiniImp", 2.0, 0.15, "PetMeshes", 180, "h" },
	nebulaeye_lo = { "NebulaEye", 2.0, 0.15, "PetMeshes", 180, "h" },
	voidshard_lo = { "VoidShard", 2.0, 0.15, "PetMeshes", 180, "h" },
	dustbunny_lo = { "DustBunny", 2.0, 0.15, "PetMeshes", 180, "h" },
	nebslime_lo = { "NebSlime", 2.0, 0.15, "PetMeshes", 180, "h" },
	warpdrone_lo = { "WarpDrone", 2.0, 0.15, "PetMeshes", 180, "h" },
	cosmoray_lo = { "CosmoRay", 2.0, 0.15, "PetMeshes", 180, "h" },
	phantomcrew_lo = { "PhantomCrew", 2.0, 0.15, "PetMeshes", 180, "h" },
	starwhale_lo = { "StarWhale", 2.0, 0.15, "PetMeshes", 180, "h" },
	riftwalker_lo = { "RiftWalker", 2.0, 0.15, "PetMeshes", 180, "h" },
	luckystar_lo = { "LuckyStar", 2.0, 0.15, "PetMeshes", 180, "h" },
	cloverbot_lo = { "CloverBot", 2.0, 0.15, "PetMeshes", 180, "h" },
	frostsprite_lo = { "FrostSprite", 2.0, 0.15, "PetMeshes", 180, "h" },
	sunbeetle_lo = { "SunBeetle", 2.0, 0.15, "PetMeshes", 180, "h" },
	prismfox_lo = { "PrismFox", 2.0, 0.15, "PetMeshes", 180, "h" },
	cometking_lo = { "CometKing", 2.0, 0.15, "PetMeshes", 180, "h" },
	celestcore_lo = { "CelestCore", 2.0, 0.15, "PetMeshes", 180, "h" },
	-- Starfall sınırlı petler + yumurta (EggMeshes: ileride kuluçka/vitrin)
	starmote_lo = { "StarMote", 2.0, 0.15, "PetMeshes", 180, "h" },
	meteormole_lo = { "MeteorMole", 2.0, 0.15, "PetMeshes", 180, "h" },
	starowl_lo = { "StarOwl", 2.0, 0.15, "PetMeshes", 180, "h" },
	stardrake_lo = { "StarDrake", 2.0, 0.15, "PetMeshes", 180, "h" },
	galaxycorn_lo = { "GalaxyCorn", 2.0, 0.15, "PetMeshes", 180, "h" },
	wishstar_lo = { "WishStar", 2.0, 0.15, "PetMeshes", 180, "h" },
	StarfallEgg_lo = { "StarfallEgg", 6, 0, "EggMeshes", 0, "h" },
	-- jetpackler (JetpackModel; genişlik 2.4, alt = meme ağzı -1.55; arkadan görünüş konsepti → 180 tahmini)
	Starter_lo = { "Starter", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	Scout_lo = { "Scout", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	Comet_lo = { "Comet", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	Plasma_lo = { "Plasma", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	Nova_lo = { "Nova", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	Pulsar_lo = { "Pulsar", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	Quasar_lo = { "Quasar", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	Galaxy_lo = { "Galaxy", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	NebulaJet_lo = { "NebulaJet", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	Stellar_lo = { "Stellar", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	Supernova_lo = { "Supernova", 2.4, -1.55, "JetpackMeshes", 180, "w" },
	CosmicJet_lo = { "CosmicJet", 2.4, -1.55, "JetpackMeshes", 180, "w" },
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
