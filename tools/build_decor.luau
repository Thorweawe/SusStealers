--!strict
--[[
	Haritayı koddan kurar. Studio'da (MCP run_code) sync sunucusu açıkken:

	    local src = game:GetService("HttpService"):GetAsync(
	        "http://127.0.0.1:8788/tools/build_decor.luau")
	    loadstring(src)()

	Tek bölümü yeniden kurmak için önce:  _G.MAP_ONLY = { "lobby" }
	(Bölümler aşağıdaki SECTIONS listesinde. İş bitince _G.MAP_ONLY = nil.)

	Tema: Among Us — The Skeld. İstasyon Skeld'in koridorları; her üs bir
	Skeld odası (Engine, Security, Electrical...), koridorun batı ucunda
	Reaktör, doğu ucunda Navigasyon kokpiti. Lobi Kafeterya: beş yuvarlak
	masa, ortadakinde acil toplantı düğmesi (üsse dönüş). Kafeteryanın
	doğusunda MedBay (yumurtalar + tarayıcı = birleştirme makinesi),
	batısında Weapons (ekipman dükkânı).

	Kod bölümlere ayrıldı: tools/map/*.luau. Her bölüm kendi klasörlerini
	siliyor ve yeniden kuruyor; diğerlerine dokunmuyor.

	OYUNU ENGELLEMEME KURALI: üsler arası geçiş açık kalmalı. Çalmanın
	bütün riski rakip üsse koşmakta. Oda bölmeleri alçak ve kapılı; ön
	tarafları koridora tamamen açık.
]]

local HttpService = game:GetService("HttpService")

local BASE = "http://127.0.0.1:8788/tools/map/"

local function fetch(name: string): string
	return HttpService:GetAsync(BASE .. name .. ".luau?t=" .. tostring(os.clock()), true)
end

local function load(name: string): any
	local fn, err = loadstring(fetch(name), "=map/" .. name)
	assert(fn, err)
	return fn()
end

-- polish EN SONDA: diğer bölümlerin parçalarına bakıyor (vent kopyası, gölge)
local SECTIONS = { "station", "bays", "rooms", "landmarks", "exterior", "lobby", "wings", "annex", "finish", "polish" }

local only = _G.MAP_ONLY
local K = load("kit")

-- Tam kurulumda eski dekorun tamamı gidiyor (eski sürümün klasörleri dahil)
if only == nil then
	K.root:ClearAllChildren()
end

local started = os.clock()
for _, name in SECTIONS do
	if only ~= nil and not table.find(only, name) then
		continue
	end
	local section = load(name)
	K.clear(section.folders)
	local t0 = os.clock()
	section.build(K)
	print(string.format("  [%s] %.2fs", name, os.clock() - t0))
end

-- Alt modeller de uzaktan pişmiş (eski) mesh ile çizilmesin (kit.luau, kök)
for _, d in K.root:GetDescendants() do
	if d:IsA("Model") then
		d.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
	end
end

print(string.format("Decor: %d parca, %.1fs", K.count(K.root), os.clock() - started))

-- Denetim
local Check = load("check")
local keepClear = {}
for i = 1, K.M.PLOT_COUNT do
	local o = K.plotOrigin(i)
	table.insert(keepClear, {
		name = "Plot" .. i,
		min = Vector3.new(o.X - K.M.halfX, K.M.topY + 0.4, o.Z - K.M.halfZ),
		max = Vector3.new(o.X + K.M.halfX, K.M.topY + 40, o.Z + K.M.halfZ),
	})
end
local extra = {}
local plots = workspace:FindFirstChild("Plots")
if plots then
	table.insert(extra, plots)
end
Check.report(Check.run(K.root, { keepClear = keepClear, extra = extra }), _G.MAP_CHECK_LIMIT or 30)
