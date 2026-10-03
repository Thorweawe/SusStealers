--!strict
-- Sana ait olmayan promptları gizler.
--
-- Sunucu promptları herkese açık yaratmak zorunda: ProximityPrompt.Enabled
-- oyuncu bazında ayarlanamıyor, sunucu açtığında herkes görüyor. Sonuç olarak
-- başkasının üssünde Sell / Lock / Rebirth / Upgrade / Buy görünüyordu,
-- kendi üssünde de Steal.
--
-- Enabled istemcide yerel olarak değiştirilebildiği için burada süzüyoruz.
--
-- ÖNEMLİ: prompt basılı tutulurken Enabled'a yazmak basışı sıfırlıyor ve
-- sunucudaki PromptGuard tetiklemeyi sessizce reddediyor. Bu yüzden değer
-- zaten doğruysa YAZMIYORUZ — satış (0.4 sn) ve çalma (4 sn) basışları
-- sürekli iptal oluyordu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local PromptFilter = {}

export type Filter = {
	Update: (myPlot: Model?) -> (),
}

-- Yalnızca kendi üssünde görünmeli
local OWN_ONLY: { [string]: boolean } = {
	SellPrompt = true,
	MergePrompt = true,
	RebirthPrompt = true,
	UpgradePrompt = true,
	CapsulePrompt = true,
	TrainingPrompt = true,
}

--[[
	Kaide promptları ayrıca kaidenin dolu olmasını istiyor. Sunucu bunu
	UnitId niteliğine bakarak yapıyor; biz de aynı kuralı uyguluyoruz,
	yoksa boş kaidede prompt açık bırakırdık.
]]
local NEEDS_UNIT: { [string]: boolean } = {
	SellPrompt = true,
	MergePrompt = true,
}

--[[
	Aynı parçaya bağlı promptlar ekranda üst üste biniyor. Lock ve Rebirth
	ikisi de tabelaya bağlı olduğu için yazıları iç içe geçiyordu.

	UIOffset promptun ekrandaki yerini piksel cinsinden kaydırıyor ve
	istemciden ayarlanabiliyor, yani sunucuya dokunmadan ayırabiliyoruz.
	Kalıcı çözüm ayrı bir arayüz olurdu ama o istemciden sunucuya remote
	açmayı gerektiriyor; Net.luau'da bunun bilinçli olarak yapılmadığı
	yazıyor, o karar Batur'un.
]]
local UI_OFFSET: { [string]: Vector2 } = {
	RebirthPrompt = Vector2.new(0, 46),
	-- Birleştirme (MergeService): Sell'in hemen altında
	MergePrompt = Vector2.new(0, 46),
}

local function podiumHasUnit(prompt: ProximityPrompt): boolean
	local podium = prompt.Parent
	if not (podium and podium:IsA("BasePart")) then
		return false
	end
	local unitId = podium:GetAttribute("UnitId")
	return typeof(unitId) == "string" and unitId ~= ""
end

--[[
	Üsteki dolu kaide sayısı. Son karakterin satılmasını engellemek için
	gerekiyor: tek karakterini satan oyuncunun geliri sıfırlanıyor ve eline
	geçen para en ucuz karakteri almaya yetmezse oyun kilitleniyor — hiçbir
	şey yapamadan beklemek zorunda kalıyor.

	Bu yalnızca arayüz koruması; gerçek kontrol sunucuda olmalı. Burada
	promptu gizlemek sıradan oyuncuyu tuzaktan kurtarıyor.
]]
local function filledCount(plot: Model): number
	local podiums = plot:FindFirstChild("Podiums")
	if not podiums then
		return 0
	end

	local n = 0
	for _, podium in podiums:GetChildren() do
		if podium:IsA("BasePart") then
			local unitId = podium:GetAttribute("UnitId")
			if typeof(unitId) == "string" and unitId ~= "" then
				n += 1
			end
		end
	end
	return n
end

--[[
	Uzaydaki mürettebatın kişisel kapma süresi (Fast Steal pass'i / Fast Hands
	iksiri + Quick Hands yükseltmesi). Prompt herkese ortak, sunucu tabanı
	yazıyor (Config.Space.GrabHold); kendi ekranımızda kısaltıyoruz. Sunucu
	aynı formülle (Config.GetPersonalGrabHold) doğruluyor. Promptlar uzayda
	(SpaceZone.Crew), üslerin altında değil: ayrı izleniyor.
]]
local function personalGrabHold(): number
	local player = Players.LocalPlayer
	local mul = player:GetAttribute("StealHoldMul")
	local quick = player:GetAttribute("Upg_QuickHands")
	return Config.GetPersonalGrabHold(Config.Space.GrabHold,
		if typeof(mul) == "number" then mul else 1, if typeof(quick) == "number" then quick else 0)
end

local function applyHeistHold(d: Instance)
	if d:IsA("ProximityPrompt") and d.Name == "HeistPrompt" then
		local hold = personalGrabHold()
		if math.abs(d.HoldDuration - hold) > 0.005 then
			d.HoldDuration = hold
		end
		-- Rebirth canavarı (2026-09-29): yeterli rebirth yoksa istem hiç görünmüyor
		local need = d:GetAttribute("Rebirths")
		local have = Players.LocalPlayer:GetAttribute("Rebirths")
		local open = typeof(need) ~= "number" or (if typeof(have) == "number" then have else 0) >= need
		if d.Enabled ~= open then
			d.Enabled = open
		end
	end
end

function PromptFilter.Create(): Filter
	workspace.DescendantAdded:Connect(applyHeistHold)
	local function refreshHeist()
		local zone = workspace:FindFirstChild("SpaceZone")
		local crew = zone and zone:FindFirstChild("Crew")
		if crew then
			for _, d in crew:GetDescendants() do
				applyHeistHold(d)
			end
		end
	end
	Players.LocalPlayer:GetAttributeChangedSignal("StealHoldMul"):Connect(refreshHeist)
	Players.LocalPlayer:GetAttributeChangedSignal("Upg_QuickHands"):Connect(refreshHeist)
	Players.LocalPlayer:GetAttributeChangedSignal("Rebirths"):Connect(refreshHeist)
	refreshHeist()

	--[[
		PERFORMANS (2026-10-03, Batur: "oyun kasıyor"): her 0.2 sn'de bütün
		üslerin GetDescendants'ı geziliyordu (8 üs × binlerce parça, her
		turda yeni dizi = çöp toplayıcı takılması). Artık her üsteki
		promptlar bir kez toplanıp DescendantAdded/Removing ile güncelleniyor.
	]]
	local promptCache: { [Model]: { [ProximityPrompt]: boolean } } = {}
	local function promptsOf(plot: Model): { [ProximityPrompt]: boolean }
		local set = promptCache[plot]
		if set then
			return set
		end
		local fresh: { [ProximityPrompt]: boolean } = {}
		promptCache[plot] = fresh
		for _, d in plot:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				fresh[d] = true
			end
		end
		plot.DescendantAdded:Connect(function(d)
			if d:IsA("ProximityPrompt") then
				fresh[d] = true
			end
		end)
		plot.DescendantRemoving:Connect(function(d)
			if d:IsA("ProximityPrompt") then
				fresh[d] = nil
			end
		end)
		plot.Destroying:Connect(function()
			promptCache[plot] = nil
		end)
		return fresh
	end

	local function update(myPlot: Model?)
		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			return
		end

		for _, plot in plots:GetChildren() do
			if not plot:IsA("Model") then
				continue
			end

			local mine = plot == myPlot
			-- Son karakterini satmana izin yok (yukarıdaki nota bak)
			local lastUnit = mine and filledCount(plot) <= 1

			for d in promptsOf(plot) do
				local offset = UI_OFFSET[d.Name]
				if offset and d.UIOffset ~= offset then
					d.UIOffset = offset
				end

				local want: boolean
				if OWN_ONLY[d.Name] then
					want = mine
				else
					-- Tanımadığımız prompt: sunucu ne dediyse o kalsın
					continue
				end

				if want and NEEDS_UNIT[d.Name] then
					want = podiumHasUnit(d)
				end

				if want and d.Name == "SellPrompt" and lastUnit then
					want = false
				end

				-- Birleştirme yalnızca kaidede eşi varken (sunucu "CanMerge" yazıyor)
				if want and d.Name == "MergePrompt" then
					local podium = d.Parent
					want = podium ~= nil and podium:GetAttribute("CanMerge") == true
				end

				-- Sadece gerçekten değişiyorsa yaz
				if d.Enabled ~= want then
					d.Enabled = want
				end

			end
		end
	end

	return { Update = update }
end

return PromptFilter
