--!strict
-- Remote'ları tek yerden yaratır/verir. Sunucu yaratır, istemci bekler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

-- Sadece gerçekten kullanılanlar. Boş duran bir RemoteEvent, ileride
-- doğrulamasız bir handler bağlanmasını davet ediyor.
--
-- Yön önemli: server -> client olanlar güvenli, istemci onları tetikleyemez.
-- İstemciden sunucuya dinlenen tek remote TutorialSkip ve o da hiçbir şey
-- vermiyor — sadece oyuncunun kendi öğreticisini kapatıyor, kalan ödülleri
-- yakarak. Yani istismarı oyuncunun kendi zararına.
local EVENTS = {
	"Notify",       -- server -> client (text, isError)
	"StealAlert",   -- server -> client (thiefName, unitName)
	"Tutorial",     -- server -> client (payload, target)
	"Titles",       -- server -> client (açık unvanlar, takılı olan)
	"Quests",       -- server -> client (vade -> görev listesi)
	"Potions",      -- server -> client (envanter + aktif takviye)
	"TutorialSkip", -- client -> server (argümansız)
	"TitleEquip",   -- client -> server (titleId: string)
	"PotionUse",    -- client -> server (potionId: string)
	"UpgradeBuy",   -- client -> server (upgradeId: string)
	"Sprint",       -- client -> server (active: boolean)
}

--[[
	İstemciden sunucuya DİNLENEN remote'lar. Buraya bir isim eklemek yeni
	bir saldırı yüzeyi açmak demek: istemci onu istediği argümanla,
	istediği sıklıkta tetikleyebiliyor.

	Kural: buradaki her remote sunucuda doğrulanıyor ve sınırlanıyor.
	Hiçbiri oyuncuya bedava bir şey VEREMİYOR — biri öğreticiyi kapatıyor
	(kalan ödülleri yakarak), biri zaten açılmış bir unvanı takıyor, biri
	envanterdeki bir iksiri harcıyor, biri de oyuncunun KENDİ parasını
	kendi üssünde harcıyor.

	UpgradeBuy yeni bir yüzey açmıyor: aynı işlem zaten tezgâhtaki
	ProximityPrompt ile yapılabiliyordu ve doğrulama aynı yerde
	(UpgradeService.TryUpgrade) — üs sahibi mi, seviye tavanda mı, parası
	yetiyor mu. Prompt yerine arayüz geçti, kontrol aynı kaldı.
]]
local CLIENT_TO_SERVER = {
	TutorialSkip = true,
	TitleEquip = true,
	PotionUse = true,
	UpgradeBuy = true,
	--[[
		Sprint yalnızca bir bayrak; hızı sunucu belirliyor ve TAŞIRKEN
		reddediyor. Roblox'ta oyuncu zaten kendi WalkSpeed'ini istemciden
		değiştirebiliyor, yani bu remote yeni bir kaçak açmıyor — tersine,
		koşmayı sunucunun bildiği ve sınırladığı bir şey haline getiriyor.
	]]
	Sprint = true,
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

--[[ Bu remote istemciden sunucuya mı dinleniyor. Testler buna bakıyor. ]]
function Net.IsClientToServer(name: string): boolean
	return CLIENT_TO_SERVER[name] == true
end

--[[ İstemciden sunucuya dinlenen remote adları. ]]
function Net.GetClientToServer(): { string }
	local names = {}
	for name in CLIENT_TO_SERVER do
		table.insert(names, name)
	end
	table.sort(names)
	return names
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
