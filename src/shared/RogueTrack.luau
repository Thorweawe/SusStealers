--!strict
--[[
	Gezen impostorun rotası: zemine oturtulmuş noktalar, başlangıç anı
	(sunucu saati) ve hız. Sunucu (RogueService) rotayı modelin
	"RogueTrack" niteliğine yazıyor; her istemci (MapLife) impostoru bu
	rotadan HER KAREDE kendisi yürütüyor. Sunucu da aynı fonksiyonla
	(Sample) kökü seyrek güncelliyor — yakalama mesafesi, admin haritası
	ve sırtlanan karakter için.

	NEDEN: fizikle yürüyen Humanoid engel sayılmayan her çıkıntıya basamak
	gibi tırmanıyordu ("uçuyor") ve hızı her karede oynadığı için yalpalama
	düzensizdi ("sakat gibi yürüyor"). Rota fiziksiz ve belirli: herkes
	aynı anda aynı yerde görüyor, titreme yok.
]]

local HttpService = game:GetService("HttpService")

local RogueTrack = {}

export type Track = {
	points: { Vector3 },
	lengths: { number },   -- noktaya kadar toplam yol (lengths[1] = 0)
	total: number,
	start: number,         -- workspace:GetServerTimeNow()
	speed: number,         -- stud/sn
}

function RogueTrack.New(points: { Vector3 }, start: number, speed: number): Track
	local pts: { Vector3 } = {}
	for _, p in points do
		-- Üst üste binen noktalar sıfır uzunluklu parça yapıp yönü bozuyordu
		if #pts == 0 or (p - pts[#pts]).Magnitude > 0.05 then
			table.insert(pts, p)
		end
	end
	local lengths = { 0 }
	for i = 2, #pts do
		lengths[i] = lengths[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	return {
		points = pts,
		lengths = lengths,
		total = lengths[#lengths] or 0,
		start = start,
		speed = math.max(speed, 0.01),
	}
end

local function round(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

function RogueTrack.Encode(track: Track): string
	local flat = {}
	for _, p in track.points do
		table.insert(flat, round(p.X))
		table.insert(flat, round(p.Y))
		table.insert(flat, round(p.Z))
	end
	return HttpService:JSONEncode({ s = track.start, v = track.speed, p = flat })
end

--[[ Bozuk ya da boş metin nil. ]]
function RogueTrack.Decode(text: string?): Track?
	if typeof(text) ~= "string" or text == "" then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if not ok or typeof(data) ~= "table" or typeof(data.p) ~= "table"
		or typeof(data.s) ~= "number" or typeof(data.v) ~= "number"
	then
		return nil
	end
	local points = {}
	for i = 1, #data.p - 2, 3 do
		table.insert(points, Vector3.new(data.p[i], data.p[i + 1], data.p[i + 2]))
	end
	if #points == 0 then
		return nil
	end
	return RogueTrack.New(points, data.s, data.v)
end

--[[ Rotada `distance` kadar yürümüş ayakların yeri ve o andaki yön (yatay). ]]
function RogueTrack.At(track: Track, distance: number): (Vector3, Vector3)
	local pts, lengths = track.points, track.lengths
	if #pts == 1 then
		return pts[1], Vector3.zAxis
	end
	local d = math.clamp(distance, 0, track.total)
	for i = 2, #pts do
		if d <= lengths[i] or i == #pts then
			local segment = lengths[i] - lengths[i - 1]
			local a = if segment > 0 then math.clamp((d - lengths[i - 1]) / segment, 0, 1) else 1
			local dir = pts[i] - pts[i - 1]
			return pts[i - 1]:Lerp(pts[i], a), Vector3.new(dir.X, 0, dir.Z)
		end
	end
	return pts[#pts], Vector3.zAxis
end

--[[ `now` anında (sunucu saati) yürünen yol. Rota bittiyse total. ]]
function RogueTrack.Distance(track: Track, now: number): number
	return math.clamp((now - track.start) * track.speed, 0, track.total)
end

function RogueTrack.Done(track: Track, now: number): boolean
	return (now - track.start) * track.speed >= track.total
end

return RogueTrack
