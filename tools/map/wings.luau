--!strict
--[[
	Kafeteryanın iki kanadı.

	MEDBAY (doğu) — yumurta kuluçkası. Dört numune kapsülü (cam tüp içinde
	süzülen yumurta) ve koridorun sonunda Skeld'in MedBay tarayıcısı:
	oyunda BİRLEŞTİRME makinesi. Yan duvarlarda hasta yatakları.
	  Adı sabit: Hatchery.Egg1..4, PodRing1..4, PodScreen1..4, FuseCore

	WEAPONS (batı) — ekipman dükkânı. Tezgâh + görevli, üç vitrin kaidesi,
	duvarda silah rafları, güney duvarında asteroit hedef ekranı ve topçu
	koltuğu (Skeld'in "Clear Asteroids" görevi).
	  Adı sabit: GearShop.GearCounter, GearPlinth1..N (N = #Config.Gear)
]]

return {
	folders = { "Hatchery", "GearShop", "Wings" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local T = M.WALL_T
		local FLOOR = M.TILE_TOP
		local H = M.WING_H
		local wz0 = M.LOBBY_Z0 + M.CAF_CHAMFER
		local wz1 = M.LOBBY_Z1 - M.CAF_CHAMFER
		local wcz = (wz0 + wz1) / 2
		local shell = K.folder("Wings")

		--[[
			Kanat kabuğu: zemin, üç duvar (dördüncüsü kafeteryanın duvarı),
			tavan. `xa` kafeterya tarafı, `xb` dış taraf.
		]]
		local function wing(name: string, xa: number, xb: number, tile: Color3, tile2: Color3, grout: Color3, windowsS: boolean)
			local f = K.folder(name, shell)
			local lo, hi = math.min(xa, xb), math.max(xa, xb)
			K.box(f, "WingDeck", (lo + hi) / 2, -0.5, wcz, hi - lo, 1, wz1 - wz0, grout)
			K.box(f, "WingBelly", (lo + hi) / 2, -4.5, wcz, hi - lo - 3, 7, wz1 - wz0 - 3, C.hullOut)
			K.tiles(f, { lo + T / 2, wz0 + T / 2, hi - T / 2, wz1 - T / 2 }, 10, 10, 0.45, FLOOR, 0.24, tile, tile2, nil, name .. "Tile")
			local spec = { h = H, winBottom = 13, winTop = 25, winW = 10, winGap = 7, rail = 11, exterior = C.hullOut }
			local ext = if xb > xa then 1 else -1
			--[[
				Kuzey, dış, güney duvarları (iç taraf solda). Dış duvar düz:
				önüne tarayıcı paneli / silah rafı ve tabela geliyor, pencere
				kalsa yarısı kapanırdı.
			]]
			local solid = { windows = false }
			local sSpec = if windowsS then {} else solid
			-- Köşelerde süsleme payı: dik duvarın süpürgelik/korkuluğuna girmesin
			local C0, C1 = T + 1, T + 1.4
			if ext > 0 then
				K.wall(f, Vector2.new(xa, wz0), Vector2.new(xb + T / 2, wz0), 1, K.merge(spec, { name = "WingN", inset0 = C0, inset1 = C1 }))
				K.wall(f, Vector2.new(xb, wz0 + T / 2), Vector2.new(xb, wz1 - T / 2), 1, K.merge(spec, K.merge(solid, { name = "WingOut" })))
				K.wall(f, Vector2.new(xb + T / 2, wz1), Vector2.new(xa, wz1), 1, K.merge(spec, K.merge(sSpec, { name = "WingS", inset0 = C1, inset1 = C0 })))
			else
				K.wall(f, Vector2.new(xb - T / 2, wz0), Vector2.new(xa, wz0), 1, K.merge(spec, { name = "WingN", inset0 = C1, inset1 = C0 }))
				K.wall(f, Vector2.new(xb, wz1 - T / 2), Vector2.new(xb, wz0 + T / 2), 1, K.merge(spec, K.merge(solid, { name = "WingOut" })))
				K.wall(f, Vector2.new(xa, wz1), Vector2.new(xb - T / 2, wz1), 1, K.merge(spec, K.merge(sSpec, { name = "WingS", inset0 = C0, inset1 = C1 })))
			end
			K.box(f, "WingCeiling", (lo + hi) / 2, H + 0.6, wcz, hi - lo - T, 1.2, wz1 - wz0 - T, C.ceiling)
			K.box(f, "WingRoof", (lo + hi) / 2, H + 1.6, wcz, hi - lo + T + 1, 0.8, wz1 - wz0 + T + 1, C.hullOut)
			for _, t in { 0.3, 0.7 } do
				local x = lo + (hi - lo) * t
				K.box(f, "LightFrame", x, H - 0.15, wcz, 4.2, 0.3, 20.2, C.frame)
				local p = K.box(f, "LightPanel", x, H - 0.35, wcz, 3, 0.2, 19, C.lamp, { emit = "Fixture" })
				K.surfaceLight(p, Enum.NormalId.Bottom, C.lamp, 36, 1.4, 140)
			end
			return f
		end

		-- ═══ MEDBAY ═══════════════════════════════════════════════════════════
		do
			local xa, xb = M.CAF_X1, M.CAF_X1 + M.WING_W
			wing("MedBay", xa, xb, C.medTile, C.medTile2, C.medGrout, true)
			local h = K.folder("Hatchery")

			-- Kapıdan tarayıcıya uzanan mavi yol
			K.box(h, "Aisle", (xa + xb) / 2 - 4, FLOOR + 0.05 + M.LIFT, wcz, xb - xa - 20, 0.1, 10, rgb(120, 170, 220))
			for k = 0, 4 do
				local ax = xa + 10 + k * 12
				K.boxAt(h, "Chevron", CFrame.new(ax, FLOOR + 0.12 + M.LIFT, wcz - 1.6) * CFrame.Angles(0, math.rad(-40), 0), Vector3.new(4.4, 0.06, 0.9), C.white)
				K.boxAt(h, "Chevron", CFrame.new(ax, FLOOR + 0.12 + M.LIFT, wcz + 1.6) * CFrame.Angles(0, math.rad(40), 0), Vector3.new(4.4, 0.06, 0.9), C.white)
			end

			-- Numune kapsülleri: kuzey sırası (Egg1, Egg2) ve güney sırası (Egg3, Egg4)
			local pods = {
				{ xa + 26, wz0 + 15, 1 }, { xa + 50, wz0 + 15, 1 },
				{ xa + 26, wz1 - 15, -1 }, { xa + 50, wz1 - 15, -1 },
			}
			--[[
				Kapsül efektleri yumurtanın FİYATIYLA büyüyor (1 en ucuz, 4 en
				pahalı). Aynı görünen dört kapsülde pahalı yumurtanın değeri
				okunmuyordu. Kademeler üst üste ekleniyor:
				  1  kaide halkası ve lamba
				  2+ yumurtanın çevresinde dönen ışık halkası, renkli lamba
				  3+ tavana uzanan ışık sütunu, parıltı zerreleri
				  4  ters dönen ikinci halka, yörüngede dönen kristaller,
				     zemine yayılan ışıma
				Renkleri sunucu boyuyor: "PodTint" niteliği taşıyan her parça
				(ve içindeki ışık/zerre) o yumurtanın rengini alıyor
				(PetService.WireHatchery) — fiyat ve renk Config'ten gelsin diye.
			]]
			local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
			local function tinted(p: Instance, i: number): Instance
				p:SetAttribute("PodTint", i)
				return p
			end
			local function halo(i: number, px: number, pz: number, y: number, radius: number, speed: number, count: number)
				local center = Vector3.new(px, y, pz)
				for k = 0, count - 1 do
					local a = k / count * math.pi * 2
					local seg = K.boxAt(h, "PodHalo", CFrame.new(center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
						* CFrame.Angles(0, -(a + math.pi / 2), 0), Vector3.new(radius * 0.36, 0.34, 0.34), C.cyan, { emit = "Fixture" })
					seg.CastShadow = false
					seg:SetAttribute("SpinSpeed", speed)
					seg:SetAttribute("SpinCenter", center)
					seg:SetAttribute("SpinAxisVec", Vector3.yAxis)
					tinted(seg, i)
				end
			end

			for i, p in pods do
				local px, pz, face = p[1], p[2], p[3]
				K.vcyl(h, "PodBase", px, FLOOR + 0.8, pz, 1.6, 10.4, C.frame)
				local ring = K.vcyl(h, "PodRing" .. i, px, FLOOR + 1.75, pz, 0.5, 10.9, C.cyan, { emit = "Screen" })
				ring.CastShadow = false
				K.vcyl(h, "PodPedestal", px, FLOOR + 2.8, pz, 1.8, 5, C.metal)
				tinted(K.vcyl(h, "PodCradle", px, FLOOR + 3.85, pz, 0.3, 4.4, C.cyan, { emit = "Indicator" }), i)
				local egg = K.ellipsoid(h, "Egg" .. i, CFrame.new(px, FLOOR + 7.4, pz), Vector3.new(4.6, 6, 4.6), rgb(236, 228, 210))
				-- Pahalı yumurta daha hareketli süzülüyor
				egg:SetAttribute("BobHeight", 0.25 + i * 0.12)
				egg:SetAttribute("BobPeriod", 2.9 - i * 0.2)

				if i >= 2 then
					-- Halkalar camın İÇİNDE (cam yarıçapı 4.2, yumurta 2.3)
					halo(i, px, pz, FLOOR + 9.2, 3.4, 30 + i * 12, 10)
				end
				if i >= 3 then
					local beam = K.vcyl(h, "PodBeam", px, (FLOOR + 14.9 + H) / 2, pz, H - FLOOR - 15.1, 3.2, C.cyan,
						{ emit = "Fixture", transparency = 0.8 })
					beam.CastShadow = false
					tinted(beam, i)
					local spark = K.box(h, "PodSparkle", px, FLOOR + 7.4, pz, 1, 1, 1, C.cyan, { transparency = 1 })
					tinted(spark, i)
					local emitter = Instance.new("ParticleEmitter")
					emitter.Texture = SPARKLE
					emitter.LightEmission = 1
					emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
					emitter.Lifetime = NumberRange.new(0.9, 1.6)
					emitter.Rate = if i >= 4 then 14 else 6
					-- Yavaş: zerreler camın içinde kalsın
					emitter.Speed = NumberRange.new(0.5, 1.1)
					emitter.SpreadAngle = Vector2.new(180, 180)
					emitter.Parent = spark
				end
				if i >= 4 then
					halo(i, px, pz, FLOOR + 11.6, 3.2, -(40 + i * 10), 10)
					-- Yörüngede dönen kristaller
					local center = Vector3.new(px, FLOOR + 5.2, pz)
					for k = 0, 2 do
						local a = k / 3 * math.pi * 2
						local shard = K.boxAt(h, "PodShard", CFrame.new(center + Vector3.new(math.cos(a) * 3.3, (k - 1) * 0.5, math.sin(a) * 3.3))
							* CFrame.Angles(math.rad(45), 0, math.rad(45)), Vector3.new(0.7, 0.7, 0.7), C.cyan, { emit = "Fixture" })
						shard.CastShadow = false
						shard:SetAttribute("SpinSpeed", 60)
						shard:SetAttribute("SpinCenter", center)
						shard:SetAttribute("SpinAxisVec", Vector3.yAxis)
						tinted(shard, i)
					end
					local aura = K.vcyl(h, "PodAura", px, FLOOR + 0.05 + M.LIFT, pz, 0.1, 17, C.cyan,
						{ emit = "Screen", transparency = 0.55 })
					aura.CastShadow = false
					tinted(aura, i)
				end
				local glass = K.vcyl(h, "PodGlass", px, FLOOR + 7.9, pz, 11.6, 8.4, C.glass,
					{ material = Enum.Material.Glass, transparency = 0.78 })
				glass.CastShadow = false
				K.vcyl(h, "PodCap", px, FLOOR + 14.3, pz, 1.2, 9.6, C.frame)
				local lamp = K.vcyl(h, "PodLamp", px, FLOOR + 13.6, pz, 0.2, 5, C.lamp, { emit = "Fixture" })
				K.light(lamp, C.lamp, 8 + i * 3, 0.6 + i * 0.25)
				if i >= 2 then
					tinted(lamp, i)
				end
				-- Kaide ile kapak arası dikmeler
				for k = 0, 2 do
					local a = math.rad(90 + k * 120)
					K.vcyl(h, "PodStrut", px + math.cos(a) * 4.5, FLOOR + 7.9, pz + math.sin(a) * 4.5, 11.6, 0.5, C.frame)
				end
				-- Fiyat ekranı: koridora (aisle) dönük, hafif yukarı eğik
				local sz = pz + face * 7.4
				K.box(h, "ScreenStand", px, FLOOR + 1.6, sz, 1, 3.2, 1, C.metalDark)
				local screenCF = CFrame.lookAt(Vector3.new(px, FLOOR + 4.3, sz), Vector3.new(px, FLOOR + 4.3, sz + face)) * CFrame.Angles(math.rad(18), 0, 0)
				K.boxAt(h, "ScreenBezel", screenCF * CFrame.new(0, 0, 0.3), Vector3.new(7.2, 3.8, 0.4), C.frame)
				K.boxAt(h, "PodScreen" .. i, screenCF, Vector3.new(6.6, 3.2, 0.3), rgb(14, 24, 38))
			end

			-- ── MedBay tarayıcısı = birleştirme makinesi ────────────────────
			local sx, sz = xb - 13, wcz
			K.vcyl(h, "ScanBase", sx, FLOOR + 0.5, sz, 1, 15, C.frame)
			local core = K.vcyl(h, "FuseCore", sx, FLOOR + 1.1, sz, 0.4, 11.4, rgb(40, 120, 110))
			core.CanCollide = true
			K.vcyl(h, "ScanPad", sx, FLOOR + 1.35, sz, 0.12, 9, C.green, { emit = "Screen" })
			-- Tarama halkası: aşağı yukarı gidip geliyor (DecorFX bob)
			-- Halka ışık sütununun (çap 10.5) içinde kalıyor, sallanmadan yalnızca inip çıkıyor
			-- ghost: oyuncu halkanın içinde duruyor, halka onun etrafında inip çıkıyor
			local ring = K.vcyl(h, "ScanRing", sx, FLOOR + 5.5, sz, 0.35, 9.8, C.green, { emit = "Fixture", transparency = 0.2, ghost = true })
			ring:SetAttribute("BobHeight", 3.8)
			ring:SetAttribute("BobPeriod", 3)
			ring:SetAttribute("BobWobble", 0)
			ring.CastShadow = false
			local beam = K.vcyl(h, "ScanBeam", sx, FLOOR + 7.2, sz, 12, 10.5, C.green, { emit = "Screen", transparency = 0.88 })
			beam.CastShadow = false
			K.light(beam, C.green, 18, 0.9)
			-- Arka panel: duvara yaslı, ekranında FUSE
			K.box(h, "ScanPanel", xb - 3, FLOOR + 8, sz, 2.2, 16, 16, C.frame)
			local screen = K.box(h, "ScanScreen", xb - 4.2, FLOOR + 10, sz, 0.2, 7, 12, rgb(14, 40, 36))
			K.text(screen, Enum.NormalId.Left, "FUSE", C.green, { h = 0.5, y = 0.08 })
			local sub = K.box(h, "ScanSub", xb - 4.25, FLOOR + 7.4, sz, 0.1, 1.8, 11, rgb(14, 40, 36), { transparency = 1 })
			K.text(sub, Enum.NormalId.Left, "3 same pets → bigger", C.white, { h = 0.9, y = 0.05 })
			K.box(h, "ScanArm", xb - 7, FLOOR + 15.3, sz, 8, 1.2, 3, C.frame)
			K.vcyl(h, "ScanHead", sx, FLOOR + 15.3, sz, 1.2, 6, C.frame)

			-- ── Hasta yatakları ─────────────────────────────────────────────
			for _, bz in { wz0 + 6, wz1 - 6 } do
				local bxp = xb - 24
				K.box(h, "BedFrame", bxp, FLOOR + 1.1, bz, 13, 2.2, 6, C.metal)
				K.box(h, "Mattress", bxp, FLOOR + 2.7, bz, 12.4, 1, 5.4, C.white)
				K.box(h, "Blanket", bxp - 2, FLOOR + 3.25, bz, 7, 0.2, 5.6, rgb(110, 176, 230))
				K.ellipsoid(h, "Pillow", CFrame.new(bxp + 4.6, FLOOR + 3.5, bz), Vector3.new(2.6, 1, 4.2), C.white)
			end
			-- İlaç dolabı ve kırmızı artı
			-- Dolap pencere pervazının altında kalıyor (pervaz 11.2'de)
			K.box(h, "Cabinet", xa + 12, FLOOR + 6.2, wz0 + T / 2 + 1, 10, 8, 2.4, C.white)
			K.box(h, "CrossV", xa + 12, FLOOR + 6.2, wz0 + T / 2 + 2.25, 1.4, 4.4, 0.1, C.red)
			K.box(h, "CrossH", xa + 12, FLOOR + 6.2, wz0 + T / 2 + 2.26, 4.4, 1.4, 0.1, C.red)
			local signPos = Vector3.new(xb - T / 2 - 0.8, 22.5, sz)
			local sign = CFrame.lookAt(signPos, signPos - Vector3.xAxis)
			K.sign(h, "MedSign", sign, 20, 4, "MEDBAY", C.green)
		end

		-- ═══ WEAPONS ══════════════════════════════════════════════════════════
		do
			local xa, xb = M.CAF_X0, M.CAF_X0 - M.WING_W
			wing("Weapons", xa, xb, C.weapTile, C.weapTile2, C.weapGrout, false)
			local g = K.folder("GearShop")
			local mx = (xa + xb) / 2

			-- Ortada yuvarlak zemin işareti (Skeld Weapons'ın dairesel zemini)
			K.vcyl(g, "FloorRing", mx + 6, FLOOR + 0.06 + M.LIFT, wcz, 0.12, 30, C.weapGrout:Lerp(C.weapTile, 0.3))
			K.vcyl(g, "FloorInner", mx + 6, FLOOR + 0.1 + M.LIFT, wcz, 0.12, 24, C.weapTile2)

			-- Tezgâh: batı duvarında, kapıya bakıyor
			local cx = xb + 10
			local counter = K.box(g, "GearCounter", cx, FLOOR + 2.2, wcz, 4, 4.4, 24, C.frame)
			counter.CanQuery = true
			K.box(g, "CounterTop", cx, FLOOR + 4.7, wcz, 5, 0.6, 25, rgb(64, 124, 196))
			K.box(g, "CounterStripe", cx + 2.05, FLOOR + 2.4, wcz, 0.1, 1, 23, C.hazard)
			--[[
				Görevli: turuncu, kasklı, tezgâhın arkasında BASAMAĞIN üstünde.
				Basamaksız tezgâh (5.3) görevliyi saklıyordu, yalnızca kaskı
				görünüyordu.
			]]
			local STEP = 1.6
			local VS = 1.55
			K.box(g, "VendorStep", xb + 5, FLOOR + STEP / 2, wcz, 6, STEP, 8, C.metalDark)
			local vendor = K.crewmate(g, CFrame.lookAt(Vector3.new(xb + 5, FLOOR + STEP, wcz), Vector3.new(xa, FLOOR + STEP, wcz)), K.crew(5), VS)
			vendor.Name = "GearVendor"
			-- Kask: kafanın üst yarısını örten zeytin yeşili kubbe + siperlik
			local headY = FLOOR + STEP + 3.1 * VS
			K.ellipsoid(g, "Helmet", CFrame.new(xb + 5, headY + 0.55 * VS, wcz), Vector3.new(2.5 * VS, 1.5 * VS, 2.5 * VS), rgb(96, 118, 70))
			K.box(g, "HelmetBrim", xb + 5 + 1.1 * VS, headY + 0.35 * VS, wcz, 0.9 * VS, 0.2 * VS, 2.2 * VS, rgb(80, 100, 58))
			-- Köşede yeşil kargo kasaları (Skeld Storage'ın kasaları)
			for k, p in { { xb + 8, wz1 - 7, 0, 6 }, { xb + 15, wz1 - 7, 0, 5 }, { xb + 10.5, wz1 - 7.5, 6, 5 } } do
				local s = p[4]
				local crate = K.box(g, "Crate" .. k, p[1], FLOOR + p[3] + s / 2, p[2], s, s, s, rgb(96, 150, 96))
				crate.CastShadow = true
				K.box(g, "CrateBand", p[1], FLOOR + p[3] + s / 2, p[2], s + 0.1, 0.6, s + 0.1, rgb(70, 110, 70))
			end
			local shopPos = Vector3.new(xb + T / 2 + 0.8, 22.5, wcz)
			local shopSign = CFrame.lookAt(shopPos, shopPos + Vector3.xAxis)
			K.sign(g, "ShopSign", shopSign, 22, 4, "GEAR SHOP", C.orange)

			--[[
				Vitrin kaideleri: kuzey duvarı boyunca, güneye (odaya) bakıyor.
				Ekipman başına bir kaide (Config.Gear sırasıyla); sayı değişince
				aralık daralıyor, dizi tezgâhın önünden kapıya kadar ortalı.
			]]
			local gear = K.Config.Gear or {}
			local count = math.max(1, #gear)
			local span = 52
			local step = if count > 1 then math.min(18, span / (count - 1)) else 0
			local startX = xb + 50 - step * (count - 1) / 2
			for i = 1, count do
				local px = startX + (i - 1) * step
				local pz = wz0 + 10
				local cf = CFrame.lookAt(Vector3.new(px, FLOOR + 1.8, pz), Vector3.new(px, FLOOR + 1.8, pz + 1))
				local plinth = K.boxAt(g, "GearPlinth" .. i, cf, Vector3.new(4.4, 3.6, 4.4), C.frame)
				plinth.CanQuery = true
				K.boxAt(g, "PlinthBand", cf * CFrame.new(0, 1.2, 0), Vector3.new(4.6, 0.6, 4.6), C.orange, { emit = "Screen" })
				K.boxAt(g, "PlinthBase", cf * CFrame.new(0, -1.5, 0), Vector3.new(5.6, 0.6, 5.6), C.metalDark)
				local plate = K.boxAt(g, "PlinthLabel", cf * CFrame.new(0, -0.3, -2.25), Vector3.new(4, 1.2, 0.1), C.shadow)
				local def = gear[i]
				K.text(plate, Enum.NormalId.Front, if def then string.upper(def.name) else "GEAR", C.white, { h = 0.8, y = 0.1 })
				-- Üstte spot
				local spot = K.box(g, "Spot", px, H - 0.4, pz + 2, 2, 0.4, 2, C.lamp, { emit = "Fixture" })
				local sl = Instance.new("SpotLight")
				sl.Face = Enum.NormalId.Bottom
				sl.Angle = 40
				sl.Range = 30
				sl.Brightness = 3
				sl.Color = C.lamp
				sl.Parent = spot
			end

			--[[
				═══ CLEAR ASTEROIDS ════════════════════════════════════════════
				Among Us'taki görev: topçu koltuğu, önünde konsol, duvarda hedef
				ekranı. Konsolun ("AsteroidConsole") promptunu sunucu kuruyor
				(MinigameService); basınca oyun açılıyor. Ekrandaki asteroitler
				boşta da süzülüyor — oyuncu uzaktan "burada bir şey oynanıyor"
				görsün.
			]]
			local tz = wz1 - T / 2 - 0.6
			K.box(g, "TargetScreen", mx, 11, tz, 26, 12, 0.6, rgb(10, 16, 30))
			K.box(g, "TargetFrame", mx, 11, tz + 0.3, 27.6, 13.6, 1.0, C.frame)
			--[[
				Süzülen asteroitler: odadan bakana göre sağdan sola. Bakış +z
				yönünde olduğu için sol = +x; başlangıç ekranın -x ucu, hız
				pozitif.
			]]
			for k, p in { { 13, 3, 4.2 }, { 9, 2.2, 3.1 }, { 14.5, 1.6, 5.4 }, { 7.5, 1.8, 3.6 } } do
				local rock = K.ball(g, "Asteroid" .. k, mx - 11.5, p[1], tz - 0.55, p[2], rgb(150, 138, 124))
				rock:SetAttribute("SlideSpeed", p[3])
				rock:SetAttribute("SlideRange", 23)
			end
			K.box(g, "CrossH", mx, 11, tz - 0.4, 26, 0.12, 0.1, C.green, { emit = "Indicator" })
			K.box(g, "CrossV", mx, 11, tz - 0.4, 0.12, 12, 0.1, C.green, { emit = "Indicator" })
			local label = K.box(g, "TaskLabel", mx, 18.9, tz - 0.2, 20, 2.4, 0.4, C.shadow)
			K.text(label, Enum.NormalId.Front, "CLEAR ASTEROIDS", C.green, { h = 0.8, y = 0.1 })

			-- Topçu koltuğu ve önündeki konsol (promptun bağlandığı parça)
			local seat = CFrame.lookAt(Vector3.new(mx, FLOOR, tz - 13), Vector3.new(mx, FLOOR, tz))
			K.boxAt(g, "GunnerPost", seat * CFrame.new(0, 1.2, 0), Vector3.new(1, 2.4, 1), C.metalDark)
			-- Oturulabilir topçu koltuğu (Seat), ekrana bakıyor
			K.boxAt(g, "GunnerSeat", seat * CFrame.new(0, 2.7, 0), Vector3.new(4, 0.8, 4), C.red, { seat = true })
			K.boxAt(g, "GunnerBack", seat * CFrame.new(0, 5.2, 1.9), Vector3.new(4, 4.2, 0.8), C.red)
			local desk = seat * CFrame.new(0, 0, -4.5)
			local console = K.boxAt(g, "AsteroidConsole", desk * CFrame.new(0, 2, 0), Vector3.new(8, 4, 3), C.metal)
			console.CanQuery = true
			K.boxAt(g, "ConsoleTop", desk * CFrame.new(0, 4.3, 0.2) * CFrame.Angles(math.rad(-25), 0, 0), Vector3.new(8.4, 0.5, 3.6), C.frame)
			local panel = K.boxAt(g, "ConsoleScreen", desk * CFrame.new(0, 4.62, 0.05) * CFrame.Angles(math.rad(-25), 0, 0),
				Vector3.new(4.6, 0.12, 2.4), rgb(20, 60, 36), { emit = "Screen" })
			panel.CastShadow = false
			for _, s in { -1, 1 } do
				K.boxAt(g, "Stick", desk * CFrame.new(s * 3, 5.4, 0.6), Vector3.new(0.35, 1.8, 0.35), C.metalDark)
				local knob = K.boxAt(g, "StickTop", desk * CFrame.new(s * 3, 6.4, 0.6), Vector3.new(0.8, 0.8, 0.8), C.red,
					{ shape = Enum.PartType.Ball, emit = "Indicator" })
				knob:SetAttribute("PulsePeriod", 1.6)
			end
		end
	end,
}
