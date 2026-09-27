--!strict
--[[
	İç gövde kavisleri (2026-09-28, "duvarlar hâlâ dümdüz, kavisli olsun,
	geminin içindeymiş hissi versin"; önceki koridor kemerleri kalktı).

	Uzun duvarlar (kuzey, güney) ve batı duvarı:
	  - ÜST KAVİS: duvarın tavanla birleştiği köşede büyük içbükey kavis
	    (kutu − silindir, CSG): duvar tavana eğrilerek dönüyor, gövdenin
	    içi gibi. Lombozların (y ~24..37) üstünde başlıyor, onları kapatmıyor.
	  - Kavis boyunca aralıklı kaburgalar (biraz daha içeri taşan dilim).
	  - Kavisin alt kenarında camgöbeği neon hat.
	  (Zemin kavisi denendi, KALDIRILDI: duvar dibindeki vent kapaklarını ve
	  oda eşyalarını örtüyordu. Üst kavis yalnızca eski tavan ışık bandını,
	  kornişi örtüyor; ışığı neon hat veriyor.)
	Tavan cam şeridinin kenarında neon hat duruyor.

	Hepsi hayalet (çarpışmasız); oynanan alan değişmiyor.
]]

return {
	folders = { "Arches", "InteriorCurves" },

	build = function(K: any)
		local M, C = K.M, K.C
		local rgb = K.rgb
		local FLOOR = M.TILE_TOP
		local f = K.folder("InteriorCurves")

		local shell = rgb(206, 214, 224)
		local rib = rgb(160, 172, 188)
		local neon = rgb(70, 220, 255)

		local ceilY = M.WALL_H          -- tavanın alt yüzü (duvar tepesi)
		local R = 13                    -- üst kavis yarıçapı

		--[[
			Köşe kavisi: yerel çerçevede köşe (0,0,0), duvar yüzü z=0 (içerisi
			+z), `up` true ise tavan y=0 (kavis aşağıda), değilse zemin y=0
			(kavis yukarıda). Uzunluk X boyunca.
		]]
		local function fillet(name: string, len: number, radius: number, up: boolean, at: CFrame, color: Color3, grow: number?)
			local g = grow or 0
			local sy = if up then -1 else 1
			local key = string.format("fillet %.2f %.2f %s %.2f", len, radius, tostring(up), g)
			return K.carved(f, name, at, color, key, function()
				local body = K.boxAt(workspace, "Body", CFrame.new(0, sy * radius / 2, radius / 2), Vector3.new(len, radius, radius), color)
				local cut = K.boxAt(workspace, "Cut", CFrame.new(0, sy * radius, radius), Vector3.new(len + 2, (radius - g) * 2, (radius - g) * 2), color,
					{ shape = Enum.PartType.Cylinder })
				return body, { cut }
			end, false)
		end

		-- Duvarlar: iç yüz çizgisi, içeri yön, uzunluk
		type Side = { name: string, cf: CFrame, len: number, doors: { { number } } }
		local space = K.Config.Space or {}
		local gateX = space.GateX or M.centerX
		local gateW = space.GateWidth or M.GATE_W
		local southDoors = { { M.centerX - M.GATE_W / 2, M.centerX + M.GATE_W / 2 } }
		for _, x in M.ANNEX_X do
			table.insert(southDoors, { x - M.ANNEX_DOOR_W / 2, x + M.ANNEX_DOOR_W / 2 })
		end
		local lenX = M.IX1 - M.IX0
		local midX = (M.IX0 + M.IX1) / 2
		local sides: { Side } = {
			-- Kuzey: iç yüz z = IZ0, içerisi +z
			{ name = "North", cf = CFrame.new(midX, 0, M.IZ0), len = lenX, doors = { { gateX - gateW / 2, gateX + gateW / 2 } } },
			-- Güney: iç yüz z = IZ1, içerisi -z (Y çevresinde 180°; X de ters döner)
			{ name = "South", cf = CFrame.new(midX, 0, M.IZ1) * CFrame.Angles(0, math.pi, 0), len = lenX, doors = southDoors },
		}

		for _, side in sides do
			-- Üst kavis ve kaburgalar
			fillet(side.name .. "HullCurve", side.len, R, true, side.cf * CFrame.new(0, ceilY, 0), shell)
			local ribs = math.floor(side.len / 36)
			for k = 1, ribs - 1 do
				local x = -side.len / 2 + k * side.len / ribs
				fillet(side.name .. "HullRib", 1.6, R, true, side.cf * CFrame.new(x, ceilY, 0), rib, 0.7)
			end
			-- Neon: kavisin alt kenarı
			local strip = K.boxAt(f, side.name .. "CurveNeon", side.cf * CFrame.new(0, ceilY - R + 0.25, 0.35), Vector3.new(side.len - 2, 0.5, 0.7), neon,
				{ ghost = true, emit = "Fixture" })
			strip.CastShadow = false

		end

		-- Batı duvarı (reaktörün arkası): yalnızca üst kavis
		do
			local lenZ = M.IZ1 - M.IZ0
			local cf = CFrame.new(M.IX0, 0, (M.IZ0 + M.IZ1) / 2) * CFrame.Angles(0, math.rad(90), 0)
			fillet("WestHullCurve", lenZ, R, true, cf * CFrame.new(0, ceilY, 0), shell)
			local strip = K.boxAt(f, "WestCurveNeon", cf * CFrame.new(0, ceilY - R + 0.25, 0.35), Vector3.new(lenZ - 2, 0.5, 0.7), neon,
				{ ghost = true, emit = "Fixture" })
			strip.CastShadow = false
		end

		-- Tavan: cam şeridin iki kenarı boyunca camgöbeği neon hat
		for _, z in { M.SPINE_Z0 + 8 - 1.2, M.SPINE_Z1 - 8 + 1.2 } do
			local strip = K.box(f, "CeilingNeon", (M.X0 + M.X1) / 2, M.WALL_H - 0.9, z, (M.X1 - M.X0) - 96, 0.35, 0.6, neon,
				{ ghost = true, emit = "Fixture" })
			strip.CastShadow = false
		end
	end,
}
