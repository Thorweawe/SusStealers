--!strict
-- Unvanlar: sohbette adının yanında görünen gösterge.
--
-- Rozetlerden farkı: rozet Roblox tarafında kalıcı bir nişan, unvan oyun
-- içi bir gösterge ve açılınca para ödülü veriyor.
--
-- Koşullar profildeki sayaçlara bakıyor (Config.Titles). Her unvan için
-- ayrı kod yok; yeni unvan eklemek Config'e bir satır.
--
-- Sohbette gösterme işi istemci tarafında (TextChatService.OnIncomingMessage
-- yalnızca istemcide çalışıyor). Sunucu unvanı oyuncunun "Title" niteliğine
-- yazıyor, istemci onu okuyup öneki basıyor. Nitelik replike olduğu için
-- herkes birbirinin unvanını görebiliyor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)
local UpgradeService = require(script.Parent.UpgradeService)

local TitleService = {}

local notifyRemote: RemoteEvent
local paused = false

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError)
	end
end

-- ─── Sayaçlar ───────────────────────────────────────────────────────────────

--[[
	Unvan koşullarının baktığı sayaçlar. Çoğu profilde duruyor; türetilen
	birkaçı burada hesaplanıyor. Bilinmeyen isim 0 dönüyor ki Config'e
	yanlış yazılmış bir koşul oyunu patlatmasın.
]]
local function statValue(player: Player, stat: string): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end

	if stat == "steals" then
		return profile.stolen
	elseif stat == "robbed" then
		return profile.robbed
	elseif stat == "caught" then
		return profile.caught
	elseif stat == "maxStreak" then
		return profile.maxStreak
	elseif stat == "secrets" then
		--[[
			Sahip olunan Secret karakter sayısı, kaydedilen listeden
			türetiliyor. Ayrı sayaç tutup PlotService'ten bildirmek
			PlotService -> TitleService -> EconomyService -> PlotService
			döngüsü yaratıyordu. Unvan bir kez açılınca kalıcı, yani
			karakteri sonradan satmak ya da kaptırmak sorun değil.
		]]
		local count = 0
		for _, entry in profile.units do
			local def = Config.GetUnit(entry.unitId)
			if def and def.rarity == "Secret" then
				count += 1
			end
		end
		return count
	elseif stat == "rebirths" then
		return profile.rebirths
	elseif stat == "maxedUpgrades" then
		local maxed = 0
		for _, def in Config.Upgrades do
			if (profile.upgrades[def.id] or 0) >= def.maxLevel then
				maxed += 1
			end
		end
		return maxed
	end

	return 0
end

-- ─── Takılı unvan ───────────────────────────────────────────────────────────

--[[
	Açık unvanlar arasından en yükseğini takar.

	Seçim arayüzü istemci işi; o gelene kadar en iyisini otomatik takmak
	hem mantıklı hem de oyuncunun hiçbir şey yapmadan ilerlemesini
	görmesini sağlıyor.
]]
local function refreshEquipped(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local best: Config.TitleDef? = nil
	for _, def in Config.Titles do
		if profile.titles[def.id] and (not best or def.order > best.order) then
			best = def
		end
	end

	profile.activeTitle = if best then best.id else ""
	player:SetAttribute("Title", if best then best.name else "")
end

--[[ Oyuncunun takılı unvanının görünen adı. ]]
function TitleService.GetTitle(player: Player): string
	local value = player:GetAttribute("Title")
	return if typeof(value) == "string" then value else ""
end

-- ─── Açma ───────────────────────────────────────────────────────────────────

--[[
	Koşulu sağlanan ve henüz açılmamış unvanları açar.
	Sayaçları değiştiren her yerden çağrılıyor; ucuz bir tarama.
]]
function TitleService.Check(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local unlockedAny = false

	for _, def in Config.Titles do
		if not profile.titles[def.id] and statValue(player, def.stat) >= def.threshold then
			profile.titles[def.id] = true
			unlockedAny = true

			local reward = Config.GetTitleReward(def, EconomyService.GetIncome(player))
			if reward > 0 then
				EconomyService.AddCash(player, reward)
				notify(player, string.format(
					"Title unlocked: %s  ·  +$%s",
					def.name, Config.FormatCash(reward)
				), false)
			else
				notify(player, string.format("Title unlocked: %s", def.name), false)
			end
		end
	end

	if unlockedAny then
		refreshEquipped(player)
		DataService.RequestSave(player)
	end
end

-- ─── Sayaç güncelleyiciler ──────────────────────────────────────────────────
-- Servisler kendi olaylarında bunları çağırıyor; TitleService onları
-- require etmiyor, bağımlılık tek yönlü kalıyor.

function TitleService.AddRobbed(player: Player)
	local profile = DataService.Get(player)
	if profile then
		profile.robbed += 1
		TitleService.Check(player)
	end
end

function TitleService.AddCaught(player: Player)
	local profile = DataService.Get(player)
	if profile then
		profile.caught += 1
		TitleService.Check(player)
	end
end

--[[ Seri rekoru yalnızca yükseldiğinde yazılıyor. ]]
function TitleService.ReportStreak(player: Player, streak: number)
	local profile = DataService.Get(player)
	if profile and streak > profile.maxStreak then
		profile.maxStreak = streak
		TitleService.Check(player)
	end
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

--[[
	Arka plan taramasını durdurur.

	Testler profili doğrudan değiştiriyor (rebirth seviyesi ver, yükseltmeyi
	tavana çek). Tarama o sırada dönerse koşullar gerçekten sağlanmış gibi
	görünüyor, ödül dağıtılıyor ve testin saydığı nakit tutmuyor. Bir kez
	böyle oldu: rebirth testi, ilgisiz bir unvan ödülü yüzünden kaldı.

	Yalnızca döngüyü durduruyor; Check doğrudan çağrılınca yine çalışıyor.
]]
function TitleService.SetPaused(value: boolean)
	paused = value
end

function TitleService.Start()
	notifyRemote = Net.Get("Notify")

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player) then
				-- Giriş anında da kontrol: eski oyuncu koşulu zaten
				-- sağlıyor olabilir, ya da Config'e yeni unvan eklenmiştir
				TitleService.Check(player)
				refreshEquipped(player)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Yükseltme ve rebirth sayaçları başka servislerde değişiyor ama
	-- olay yayını yok; saniyede bir tarama en ucuz çözüm ve gecikmesi
	-- oyuncunun fark edemeyeceği kadar küçük.
	task.spawn(function()
		while true do
			task.wait(2)
			if paused then
				continue
			end
			for _, player in Players:GetPlayers() do
				TitleService.Check(player)
			end
		end
	end)
end

return TitleService
