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
	LockPrompt = true,
	RebirthPrompt = true,
	UpgradePrompt = true,
	BuyPrompt = true,
}

-- Yalnızca başkasının üssünde görünmeli
local OTHERS_ONLY: { [string]: boolean } = {
	StealPrompt = true,
}

--[[
	Kaide promptları ayrıca kaidenin dolu olmasını istiyor. Sunucu bunu
	UnitId niteliğine bakarak yapıyor; biz de aynı kuralı uyguluyoruz,
	yoksa boş kaidede prompt açık bırakırdık.
]]
local NEEDS_UNIT: { [string]: boolean } = {
	SellPrompt = true,
	StealPrompt = true,
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
	LockPrompt = Vector2.new(0, -46),
	RebirthPrompt = Vector2.new(0, 46),
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

function PromptFilter.Create(): Filter
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

			for _, d in plot:GetDescendants() do
				if not d:IsA("ProximityPrompt") then
					continue
				end

				local offset = UI_OFFSET[d.Name]
				if offset and d.UIOffset ~= offset then
					d.UIOffset = offset
				end

				local want: boolean
				if OWN_ONLY[d.Name] then
					want = mine
				elseif OTHERS_ONLY[d.Name] then
					want = not mine
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

				-- Sadece gerçekten değişiyorsa yaz
				if d.Enabled ~= want then
					d.Enabled = want
				end

				--[[
					Kişisel çalma süresi (Fast Steal pass'i / Fast Hands iksiri).
					Prompt herkese ortak, sunucu tabanı yazıyor; oyuncunun kendi
					ekranında süreyi çarpanla kısaltıyoruz. Sunucu aynı formülle
					(Config.GetPersonalStealHold) doğruluyor.
				]]
				if d.Name == "StealPrompt" then
					local base = d:GetAttribute("BaseHold")
					if typeof(base) == "number" then
						local mul = Players.LocalPlayer:GetAttribute("StealHoldMul")
						local hold = Config.GetPersonalStealHold(base, if typeof(mul) == "number" then mul else 1)
						if math.abs(d.HoldDuration - hold) > 0.005 then
							d.HoldDuration = hold
							d.ObjectText = string.format("%.1fs", hold)
						end
					end
				end
			end
		end
	end

	return { Update = update }
end

return PromptFilter
