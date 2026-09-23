--!strict
--[[
	Lobideki üç sıralama panosu — KÜRESEL (bütün sunucular, bütün zamanlar).

	Eskiden panoları istemci dolduruyordu ve yalnızca o sunucudaki oyuncuları
	gösteriyordu: sekiz kişilik bir sunucuda "RICHEST" panosu en fazla sekiz
	isimdi ve oyuncu gerçekten ne kadar iyi olduğunu göremiyordu.

	Artık sunucu OrderedDataStore'a yazıyor ve oradan okuyor:

	    TOP EARNERS  — hayat boyu kazanılan para (profile.earned). Nakit
	                   harcandıkça düştüğü için "en zengin" yerine bu.
	    MOST STOLEN  — hayat boyu çalma sayısı (profile.stolen)
	    TOP INCOME   — saniyelik gelir (profile.incomePerSecond)

	Panolar Decor'daki SurfaceGui'ler; sunucu yazınca herkese replike
	oluyor, istemcinin bir şey yapmasına gerek yok.

	═══ KOTA ═══════════════════════════════════════════════════════════════

	OrderedDataStore kotası dar. Yazma oyuncu başına dakikada bir (ve
	çıkarken), okuma üç pano için dakikada bir. İsimler UserId'den bir kez
	çözülüp önbelleğe alınıyor.

	Studio'da API erişimi kapalıysa ya da istek başarısızsa pano o
	sunucudaki oyunculara düşüyor — boş kalmıyor.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local DataService = require(script.Parent.DataService)

local GlobalBoardService = {}

local INTERVAL = 60
local ROWS = 8

type Board = {
	index: number,
	title: string,
	store: string,
	value: (profile: any) -> number,
	format: (number) -> string,
}

local BOARDS: { Board } = {
	{ index = 1, title = "TOP EARNERS", store = "Global_Earned_v1",
		value = function(p) return p.earned or 0 end,
		format = function(v) return "$" .. Config.FormatCash(v) end },
	{ index = 2, title = "MOST STOLEN", store = "Global_Stolen_v1",
		value = function(p) return p.stolen or 0 end,
		format = function(v) return tostring(math.floor(v)) end },
	{ index = 3, title = "TOP INCOME", store = "Global_Income_v1",
		value = function(p) return p.incomePerSecond or 0 end,
		format = function(v) return "+$" .. Config.FormatCash(v) .. "/s" end },
}

-- İlk üçün renkleri: altın, gümüş, bronz
local PODIUM = { "#FFC83C", "#C8D2DE", "#D68C50" }

local stores: { [string]: OrderedDataStore? } = {}
local names: { [number]: string } = {}

local function storeFor(board: Board): OrderedDataStore?
	if stores[board.store] == nil then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.store)
		end)
		stores[board.store] = if ok then store else nil
	end
	return stores[board.store]
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		names[userId] = online.DisplayName
		return online.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and typeof(name) == "string" then name else "Crewmate"
	names[userId] = result
	return result
end

local function screenBody(index: number): (TextLabel?, TextLabel?)
	local decor = workspace:FindFirstChild("Decor")
	local boards = decor and decor:FindFirstChild("Boards")
	local screen = boards and boards:FindFirstChild("BoardScreen" .. index)
	local surface = screen and screen:FindFirstChild("Display")
	local body = surface and surface:FindFirstChild("Body")
	local header = surface and surface:FindFirstChild("Header")
	return (if body and body:IsA("TextLabel") then body else nil),
		(if header and header:IsA("TextLabel") then header else nil)
end

type Row = { name: string, value: number }

local function render(board: Board, rows: { Row }, global: boolean)
	local body, header = screenBody(board.index)
	if not body then
		return
	end
	if header then
		header.Text = if global then "GLOBAL " .. board.title else board.title .. " · THIS SERVER"
	end
	body.RichText = true
	body.TextSize = 18
	local lines = {}
	for rank, row in rows do
		local color = PODIUM[rank]
		local line = string.format("%d.  %s   %s", rank, string.sub(row.name, 1, 16), board.format(row.value))
		table.insert(lines, if color then string.format('<font color="%s">%s</font>', color, line) else line)
	end
	body.Text = if #lines > 0 then table.concat(lines, "\n") else "no crewmates yet"
end

--[[ Yedek: o sunucudaki oyuncular (API yoksa ya da istek düştüyse). ]]
local function localRows(board: Board): { Row }
	local rows: { Row } = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile then
			table.insert(rows, { name = player.DisplayName, value = board.value(profile) })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	while #rows > ROWS do
		table.remove(rows)
	end
	return rows
end

local function write(player: Player)
	local profile = DataService.Get(player)
	if not profile or not DataService.IsAvailable() then
		return
	end
	for _, board in BOARDS do
		local store = storeFor(board)
		if store then
			local value = math.floor(math.max(0, board.value(profile)))
			pcall(function()
				(store :: OrderedDataStore):SetAsync(tostring(player.UserId), value)
			end)
		end
	end
end

local function refresh()
	for _, board in BOARDS do
		local store = if DataService.IsAvailable() then storeFor(board) else nil
		local rows: { Row }? = nil
		if store then
			local ok, page = pcall(function()
				return (store :: OrderedDataStore):GetSortedAsync(false, ROWS):GetCurrentPage()
			end)
			if ok and typeof(page) == "table" then
				local list: { Row } = {}
				for _, entry in page do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(list, { name = nameOf(userId), value = entry.value })
					end
				end
				rows = list
			end
		end
		if rows and #rows > 0 then
			render(board, rows, true)
		else
			render(board, localRows(board), false)
		end
	end
end

function GlobalBoardService.Start()
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(write, player)
	end)

	task.spawn(function()
		-- İlk çizim hemen (yerel), küresel veri ilk turda gelince yerini alıyor
		task.wait(5)
		refresh()
		while true do
			for _, player in Players:GetPlayers() do
				write(player)
			end
			refresh()
			task.wait(INTERVAL)
		end
	end)
end

return GlobalBoardService
