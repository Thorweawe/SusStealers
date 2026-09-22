--!strict
--[[
	Oyuncunun kendi üssünü bulur.

	NEDEN AYRI BİR MODÜL: bu arama iki yerde ayrı ayrı yazılıydı
	(init.client'taki HUD ve Lobby'deki ışınlanma düğmesi). İkisi de
	tabeladaki yazıyı oyuncunun adıyla TAM eşitlik arayarak karşılaştırıyordu.

	Tabelaya rebirth rozeti eklenince ("ATCIKM  [R1]") eşleşme bozuldu.
	HUD'daki kopyayı düzelttim ama Lobby'deki kopya gözden kaçtı ve
	rebirth atmış oyuncu ışınlanma düğmesine bastığında "You don't own a
	base yet" görmeye devam etti.

	Aynı bilgiyi iki yerde hesaplamak bu hatayı davet ediyordu. Artık tek
	yerde.

	NASIL BULUYOR: sunucu üssü verirken oyuncunun "Plot" niteliğine adını
	yazıyor (PlotService.grantPlot) ve nitelik kendiliğinden replike
	oluyor, yani remote gerekmiyor.

	Tabela araması yedek olarak duruyor: nitelik henüz gelmemişse (oyuncu
	girer girmez) ya da sunucu eski sürümdeyse arayüz boş kalmasın. Yedek
	artık tam eşitlik değil "ile başlıyor" diye bakıyor, yani rozet takılı
	olsa da buluyor.
]]

local Players = game:GetService("Players")

local OwnPlot = {}

local player = Players.LocalPlayer

function OwnPlot.Get(): Model?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end

	local assigned = player:GetAttribute("Plot")
	if typeof(assigned) == "string" and assigned ~= "" then
		local plot = plots:FindFirstChild(assigned)
		if plot and plot:IsA("Model") then
			return plot
		end
	end

	local wanted = string.upper(player.DisplayName)
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") then
			local sign = plot:FindFirstChild("Sign")
			local gui = sign and sign:FindFirstChild("OwnerLabel")
			local label = gui and gui:FindFirstChild("Text")
			if label and label:IsA("TextLabel")
				and string.sub(label.Text, 1, #wanted) == wanted
			then
				return plot
			end
		end
	end

	return nil
end

return OwnPlot
