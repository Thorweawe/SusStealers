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
