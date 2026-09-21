--!strict
-- Her üssü sahibinin renginde boyar.
--
-- Sekiz üs birbirinin aynıysa kimin nerede olduğunu ancak tabelayı okuyarak
-- anlıyorsun. Renk uzaktan okunuyor: çalmaya giderken hedefini seçiyorsun,
-- kendi üssünü kaçarken buluyorsun.
--
-- Tamamen görsel ve tamamen istemci tarafı; renk bilgisi sunucudan gelmiyor,
-- oyuncunun kimliğinden hesaplanıyor. Bu sayede herkes aynı oyuncuyu aynı
-- renkte görüyor ama ağda tek bayt taşınmıyor.

local Players = game:GetService("Players")

local OwnerColors = {}

local player = Players.LocalPlayer

-- Among Us mürettebat renkleri: birbirinden ayırt edilebilir ve temaya uygun
local PALETTE = {
	Color3.fromRGB(197, 17, 17),    -- kırmızı
	Color3.fromRGB(19, 46, 210),    -- mavi
	Color3.fromRGB(0, 158, 55),     -- yeşil
	Color3.fromRGB(236, 84, 187),   -- pembe
	Color3.fromRGB(239, 125, 13),   -- turuncu
	Color3.fromRGB(245, 245, 87),   -- sarı
	Color3.fromRGB(56, 254, 220),   -- camgöbeği
	Color3.fromRGB(107, 47, 187),   -- mor
	Color3.fromRGB(113, 73, 30),    -- kahve
	Color3.fromRGB(80, 240, 100),   -- fıstık
}

local NEUTRAL = Color3.fromRGB(44, 124, 152)   -- sahipsiz üs

--[[ Aynı oyuncu her zaman aynı renk. UserId sabit olduğu için oturumlar
     arasında da değişmiyor. ]]
local function colorFor(p: Player): Color3
	return PALETTE[(p.UserId % #PALETTE) + 1]
end

--[[ Üssün tabelasındaki isimden sahibini bulur. Sunucu sahiplik bilgisini
     ayrıca yayınlamıyor; tabela zaten replike oluyor. ]]
local function ownerOf(plot: Model): Player?
	local sign = plot:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("OwnerLabel")
	local label = gui and gui:FindFirstChild("Text")
	if not (label and label:IsA("TextLabel")) then
		return nil
	end

	local text = label.Text
	for _, p in Players:GetPlayers() do
		if string.upper(p.DisplayName) == text then
			return p
		end
	end
	return nil
end

export type Colors = {
	Update: () -> (),
	ColorOf: (p: Player) -> Color3,
}

function OwnerColors.Create(): Colors
	-- Son uygulanan renkleri tutuyoruz: her karede bütün parçalara
	-- yazmak yerine sadece sahip değişince dokunuyoruz.
	local applied: { [number]: Color3 } = {}

	local function tintPlot(index: number, color: Color3, owned: boolean)
		local decor = workspace:FindFirstChild("Decor")
		if not decor then
			return
		end

		local plots = decor:FindFirstChild("Plots")
		local pf = plots and plots:FindFirstChild("Plot" .. index)
		if pf then
			for _, part in pf:GetChildren() do
				if not part:IsA("BasePart") then
					continue
				end
				-- Sadece renk taşıyan parçalar: çerçeve ve sütun bandı.
				-- Metal gövde ve sütunlar nötr kalmalı, yoksa üs tek renk
				-- bir blok gibi görünüyor.
				if part.Name == "FrameX" or part.Name == "FrameZ" or part.Name == "PillarBand" then
					part.Color = color
				elseif part.Name == "PodiumRing" then
					-- Halkalar zeminde geniş yer kapladığı için koyultuluyor
					part.Color = color:Lerp(Color3.new(0, 0, 0), 0.55)
				end
			end
		end

		-- Kapı eşiğinin neon hattı da sahibin renginde: koridordan bakınca
		-- hangi kapıdan gireceğin renkten okunuyor
		local doors = decor:FindFirstChild("Doorways")
		local glow = doors and doors:FindFirstChild("DoorGlow" .. index)
		if glow and glow:IsA("BasePart") then
			glow.Color = color
		end

		local markers = decor:FindFirstChild("BayMarkers")
		if markers then
			local pad = markers:FindFirstChild("BayPad" .. index)
			if pad and pad:IsA("BasePart") then
				-- Ped sönük kalsın, zemine yayılmış geniş bir yüzey
				pad.Color = color:Lerp(Color3.new(0, 0, 0), 0.62)
			end

			local post = markers:FindFirstChild("BayPost" .. index)
			local label = post and post:FindFirstChild("BayLabel")
			local text = label and label:FindFirstChild("TextLabel")
			if text and text:IsA("TextLabel") then
				text.TextColor3 = color
				text.Text = if owned
					then string.format("BAY %02d", index)
					else string.format("BAY %02d  ·  FREE", index)
			end
		end
	end

	local function update()
		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			return
		end

		for _, plot in plots:GetChildren() do
			if not plot:IsA("Model") then
				continue
			end

			local index = tonumber(string.match(plot.Name, "%d+"))
			if not index then
				continue
			end

			local owner = ownerOf(plot)
			local color = if owner then colorFor(owner) else NEUTRAL

			-- Kendi üssün biraz daha parlak: kaçarken gözüne çarpsın
			if owner == player then
				color = color:Lerp(Color3.new(1, 1, 1), 0.25)
			end

			if applied[index] ~= color then
				applied[index] = color
				tintPlot(index, color, owner ~= nil)
			end
		end
	end

	return { Update = update, ColorOf = colorFor }
end

return OwnerColors
