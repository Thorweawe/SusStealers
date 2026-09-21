--!strict
-- Remote'ları tek yerden yaratır/verir. Sunucu yaratır, istemci bekler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local EVENTS = {
	"BuyUnit",        -- client -> server (conveyorItemId)
	"RequestLock",    -- client -> server ()
	"Notify",         -- server -> client (text, color)
	"PlotAssigned",   -- server -> client (plotModel)
	"StealAlert",     -- server -> client (thiefName, unitName)
}

local Net = {}

local folder: Folder
if IS_SERVER then
	folder = ReplicatedStorage:FindFirstChild("Net") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Net"
		folder.Parent = ReplicatedStorage
	end

	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Net") :: Folder
end

--[[ İsimle remote verir. İstemcide hazır olana kadar bekler. ]]
function Net.Get(name: string): RemoteEvent
	if IS_SERVER then
		local remote = folder:FindFirstChild(name)
		assert(remote, string.format("Net: no remote named '%s'", name))
		return remote :: RemoteEvent
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return Net
