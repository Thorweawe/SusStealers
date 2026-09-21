--!strict
-- Sana ait olmayan promptları gizler.
--
-- Sunucu promptları herkese açık yaratmak zorunda: ProximityPrompt.Enabled
-- oyuncu bazında ayarlanamıyor, sunucu açtığında herkes görüyor. Sonuç olarak
-- başkasının kaidesinde "Sell", kendi kaidende "Steal" görünüyordu.
--
-- Enabled istemcide yerel olarak değiştirilebildiği için burada süzüyoruz.
-- Sunucu bir promptu tekrar açarsa döngü 0.2 sn içinde geri kapatır.

local PromptFilter = {}

export type Filter = {
	Update: (myPlot: Model?) -> (),
}

local function isOccupied(podium: Part): boolean
	local unitId = podium:GetAttribute("UnitId")
	return typeof(unitId) == "string" and unitId ~= ""
end

--[[
	Değer zaten doğruysa YAZMA. Prompt basılı tutulurken Enabled'a yazmak
	basışı sıfırlıyor; döngü 0.2 sn'de bir çalıştığı için 0.4 sn'lik satış
	ve 4 sn'lik çalma basışları sürekli iptal oluyordu.
]]
local function setEnabled(prompt: ProximityPrompt, want: boolean)
	if prompt.Enabled ~= want then
		prompt.Enabled = want
	end
end

local function applyTo(podium: Part, mine: boolean)
	local occupied = isOccupied(podium)

	local sell = podium:FindFirstChild("SellPrompt")
	if sell and sell:IsA("ProximityPrompt") then
		-- Sadece kendi kaideni satabilirsin
		setEnabled(sell, mine and occupied)
	end

	local steal = podium:FindFirstChild("StealPrompt")
	if steal and steal:IsA("ProximityPrompt") then
		-- Kendi karakterini çalamazsın
		setEnabled(steal, (not mine) and occupied)
	end
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

			local podiums = plot:FindFirstChild("Podiums")
			if not podiums then
				continue
			end

			local mine = plot == myPlot
			for _, podium in podiums:GetChildren() do
				if podium:IsA("Part") then
					applyTo(podium, mine)
				end
			end
		end
	end

	return { Update = update }
end

return PromptFilter
