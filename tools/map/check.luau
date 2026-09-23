--!strict
--[[
	Harita denetimi: kurulumdan sonra ölçerek hata arar.

	  1. ÇAKIŞIK YÜZEY (z-fighting): iki parçanın aynı yöne bakan yüzleri
	     aynı düzlemde ve üst üste biniyorsa kamera oynadıkça titrer.
	     Yalnızca eksene hizalı (90°'nin katı dönmüş) parçalar ölçülüyor;
	     aynı renk + malzemedeki çakışma görünmediği için ayrı sayılıyor.
	  2. OYUN ALANI İHLALİ: katı bir dekor parçası bir üssün zeminine
	     (oynanan hacme) giriyorsa oyuncu takılır.

	Kullanım: kurucunun sonunda çağrılıyor; `report` sayıları ve ilk
	örnekleri basıyor.
]]

local Check = {}

type Box = { part: BasePart, min: Vector3, max: Vector3, aligned: boolean }

local function aabb(p: BasePart): (Vector3, Vector3, boolean)
	local cf = p.CFrame
	local s = p.Size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = Vector3.new(
		math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
		math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
		math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
	)
	local function axisAligned(v: Vector3): boolean
		local a = math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
		return a > 0.9999
	end
	local aligned = axisAligned(r) and axisAligned(u) and axisAligned(l)
	return cf.Position - ex, cf.Position + ex, aligned
end

--[[
	Blok olmayan şekiller (küre, silindir, kama, mesh'li) yüz düzlemi
	hesabına girmiyor: yüzeyleri düz değil.
]]
local function isBlock(p: BasePart): boolean
	if not p:IsA("Part") then
		return false
	end
	if (p :: Part).Shape ~= Enum.PartType.Block then
		return false
	end
	if p:FindFirstChildOfClass("SpecialMesh") then
		return false
	end
	return true
end

local function visible(p: BasePart): boolean
	return p.Transparency < 0.98
end

function Check.run(root: Instance, opts: { [string]: any }?): { [string]: any }
	local o = opts or {}
	local boxes: { Box } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and visible(d) then
			local mn, mx, aligned = aabb(d)
			table.insert(boxes, { part = d, min = mn, max = mx, aligned = aligned and isBlock(d) })
		end
	end
	-- Ek parçalar (ör. oyun sırasında kurulan üsler) karşılaştırmaya dahil
	for _, extra in o.extra or {} do
		for _, d in extra:GetDescendants() do
			if d:IsA("BasePart") and visible(d) then
				local mn, mx, aligned = aabb(d)
				table.insert(boxes, { part = d, min = mn, max = mx, aligned = aligned and isBlock(d) })
			end
		end
	end

	-- Uzamsal ızgara
	local CELL = 16
	local grid: { [string]: { number } } = {}
	local function key(x: number, y: number, z: number): string
		return x .. "," .. y .. "," .. z
	end
	for i, b in boxes do
		for x = math.floor(b.min.X / CELL), math.floor(b.max.X / CELL) do
			for y = math.floor(b.min.Y / CELL), math.floor(b.max.Y / CELL) do
				for z = math.floor(b.min.Z / CELL), math.floor(b.max.Z / CELL) do
					local k = key(x, y, z)
					local list = grid[k]
					if not list then
						list = {}
						grid[k] = list
					end
					table.insert(list, i)
				end
			end
		end
	end

	local EPS = 0.012
	local MIN_AREA = 0.02
	local fights: { string } = {}
	local sameLook = 0
	local seen: { [string]: boolean } = {}

	local function overlap1(a0: number, a1: number, b0: number, b1: number): number
		return math.min(a1, b1) - math.max(a0, b0)
	end

	for _, list in grid do
		for ii = 1, #list do
			local a = boxes[list[ii]]
			if not a.aligned then
				continue
			end
			for jj = ii + 1, #list do
				local b = boxes[list[jj]]
				if not b.aligned then
					continue
				end
				local pk = if list[ii] < list[jj] then list[ii] .. ":" .. list[jj] else list[jj] .. ":" .. list[ii]
				if seen[pk] then
					continue
				end
				-- Kutular birbirine değiyor mu (yüz ortaklığı için gerekli)
				if a.min.X > b.max.X + EPS or b.min.X > a.max.X + EPS
					or a.min.Y > b.max.Y + EPS or b.min.Y > a.max.Y + EPS
					or a.min.Z > b.max.Z + EPS or b.min.Z > a.max.Z + EPS then
					continue
				end
				seen[pk] = true

				-- Her eksende aynı yöne bakan yüzler aynı düzlemde mi
				local found: string? = nil
				for axis = 1, 3 do
					local amin = if axis == 1 then a.min.X elseif axis == 2 then a.min.Y else a.min.Z
					local amax = if axis == 1 then a.max.X elseif axis == 2 then a.max.Y else a.max.Z
					local bmin = if axis == 1 then b.min.X elseif axis == 2 then b.min.Y else b.min.Z
					local bmax = if axis == 1 then b.max.X elseif axis == 2 then b.max.Y else b.max.Z
					local sameMin = math.abs(amin - bmin) < EPS
					local sameMax = math.abs(amax - bmax) < EPS
					-- Zemine oturan alt yüzler (y <= 1.1) görünmüyor: sayılmıyor
					if axis == 2 and sameMin and not sameMax and amin <= 1.1 then
						sameMin = false
					end
					if sameMin or sameMax then
						-- Diğer iki eksendeki örtüşme alanı
						local o1, o2
						if axis == 1 then
							o1 = overlap1(a.min.Y, a.max.Y, b.min.Y, b.max.Y)
							o2 = overlap1(a.min.Z, a.max.Z, b.min.Z, b.max.Z)
						elseif axis == 2 then
							o1 = overlap1(a.min.X, a.max.X, b.min.X, b.max.X)
							o2 = overlap1(a.min.Z, a.max.Z, b.min.Z, b.max.Z)
						else
							o1 = overlap1(a.min.X, a.max.X, b.min.X, b.max.X)
							o2 = overlap1(a.min.Y, a.max.Y, b.min.Y, b.max.Y)
						end
						if o1 > EPS and o2 > EPS and o1 * o2 > MIN_AREA then
							found = string.format("%s%s %.2fx%.2f", if axis == 1 then "X" elseif axis == 2 then "Y" else "Z",
								if sameMin then "-" else "+", o1, o2)
							break
						end
					end
				end
				if found then
					local pa, pb = a.part, b.part
					local same = pa.Color == pb.Color and pa.Material == pb.Material
						and math.abs(pa.Transparency - pb.Transparency) < 0.01
					if same then
						sameLook += 1
					else
						table.insert(fights, string.format("%s | %s  [%s] @ (%.1f, %.1f, %.1f)",
							pa:GetFullName():gsub("^Workspace%.", ""), pb:GetFullName():gsub("^Workspace%.", ""), found,
							pa.Position.X, pa.Position.Y, pa.Position.Z))
					end
				end
			end
		end
	end

	-- Oyun alanı ihlalleri: katı dekor, üs hacminin içinde
	local intrusions: { string } = {}
	for _, zone in o.keepClear or {} do
		local zmin, zmax = zone.min, zone.max
		for _, b in boxes do
			local p = b.part
			if not p.CanCollide or not p:IsDescendantOf(root) then
				continue
			end
			if b.max.X > zmin.X + 0.05 and b.min.X < zmax.X - 0.05
				and b.max.Y > zmin.Y + 0.05 and b.min.Y < zmax.Y - 0.05
				and b.max.Z > zmin.Z + 0.05 and b.min.Z < zmax.Z - 0.05 then
				table.insert(intrusions, string.format("%s -> %s", zone.name, p:GetFullName():gsub("^Workspace%.", "")))
			end
		end
	end

	return { parts = #boxes, fights = fights, sameLook = sameLook, intrusions = intrusions }
end

function Check.report(result: { [string]: any }, limit: number?)
	local n = limit or 25
	print(string.format("[check] %d parca | cakisan yuz: %d (ayni gorunumlu %d) | oyun alani ihlali: %d",
		result.parts, #result.fights, result.sameLook, #result.intrusions))
	for i = 1, math.min(n, #result.fights) do
		print("  Z  " .. result.fights[i])
	end
	for i = 1, math.min(n, #result.intrusions) do
		print("  X  " .. result.intrusions[i])
	end
end

return Check
