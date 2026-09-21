--!strict
-- Sana ait olmayan promptları gizler.
--
-- Sunucu promptları herkese açık yaratmak zorunda: ProximityPrompt.Enabled
-- oyuncu bazında ayarlanamıyor, sunucu açtığında herkes görüyor. Sonuç olarak
-- başkasının kaidesinde "Sell", kendi kaidende "Steal", ve herkesin üssünde
-- "Lock" görünüyordu.
--
-- Enabled istemcide yerel olarak değiştirilebildiği için burada süzüyoruz.
--
-- ÖNEMLİ: prompt basılı tutulurken Enabled'a yazmak basışı sıfırlıyor. Bu
-- yüzden döngüde her seferinde yazmıyoruz; her kaideyi bir kez bağlayıp
-- yalnızca durumu gerçekten değiştiğinde dokunuyoruz.

local PromptFilter = {}

export type Filter = {
	Update: (myPlot: Model?) -> (),
}

local function isOccupied(podium: Part): boolean
	local unitId = podium:GetAttribute("UnitId")
	return typeof(unitId) == "string" and unitId ~= ""
end

local function setEnabled(instance: Instance?, want: boolean)
	if instance and instance:IsA("ProximityPrompt") and instance.Enabled ~= want then
		instance.Enabled = want
	end
end

function PromptFilter.Create(): Filter
	local hookedPodiums: { [Part]: boolean } = {}
	local myPlot: Model? = nil

	local function refreshPodium(podium: Part, plot: Model)
		local mine = plot == myPlot
		local occupied = isOccupied(podium)

		-- Sadece kendi kaideni satabilirsin
		setEnabled(podium:FindFirstChild("SellPrompt"), mine and occupied)
		-- Kendi karakterini çalamazsın
		setEnabled(podium:FindFirstChild("StealPrompt"), (not mine) and occupied)
	end

	local function refreshLock(plot: Model)
		local sign = plot:FindFirstChild("Sign")
		if sign then
			-- Sadece kendi üssünü kilitleyebilirsin
			setEnabled(sign:FindFirstChild("LockPrompt"), plot == myPlot)
		end
	end

	local function update(plot: Model?)
		local ownerChanged = plot ~= myPlot
		myPlot = plot

		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			return
		end

		for _, candidate in plots:GetChildren() do
			if not candidate:IsA("Model") then
				continue
			end

			if ownerChanged then
				refreshLock(candidate)
			end

			local podiums = candidate:FindFirstChild("Podiums")
			if not podiums then
				continue
			end

			for _, podium in podiums:GetChildren() do
				if not podium:IsA("Part") then
					continue
				end

				if not hookedPodiums[podium] then
					hookedPodiums[podium] = true
					-- Karakter konunca/kalkınca promptlar değişmeli
					podium:GetAttributeChangedSignal("UnitId"):Connect(function()
						refreshPodium(podium, candidate)
					end)
					refreshPodium(podium, candidate)
				elseif ownerChanged then
					refreshPodium(podium, candidate)
				end
			end
		end
	end

	return { Update = update }
end

return PromptFilter
