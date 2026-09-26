--!strict
--[[
	Şans çarkının açısı — sunucu SAATİNDEN hesaplanıyor, herkeste aynı.

	Eskiden her istemci çarkı kendi açtığı andan beri biriktirdiği açıyla
	döndürüyordu: iki oyuncu çarkı farklı konumda görüyordu ve çark
	ödülün diliminde duramazdı. Şimdi:

	  - Boşta: açı = boşta hız × sunucu saati.
	  - Çevirme: sunucu Wheel modeline SpinFrom / SpinTo (derece) ve
	    SpinStart / SpinEnd (sunucu saati) yazıyor. Açı SpinFrom'dan
	    SpinTo'ya yavaşlayarak gidiyor (kübik), kazanılan dilim tepedeki
	    dilin altında duruyor.
	  - Durduktan sonra HOLD saniye bekliyor (oyuncu ödülü görsün), sonra
	    oradan boşta dönmeye devam ediyor.

	Açı, çarkın bakış ekseni (SpinAxisVec, odaya doğru) etrafında
	derece; DecorFX parçaları bununla döndürüyor.
]]

local WheelSpin = {}

WheelSpin.HOLD = 3
WheelSpin.TURNS = 5          -- çevirmede en az kaç tam tur
WheelSpin.SLICE_JITTER = 0.3 -- dilimin ortasından en fazla bu kadar (dilim genişliğinin oranı) sap

local function easeOut(u: number): number
	local v = 1 - math.clamp(u, 0, 1)
	return 1 - v * v * v
end

--[[ `wheel` modelinin niteliklerine göre `now` anındaki açı (derece). ]]
function WheelSpin.Angle(wheel: Instance, now: number, idleSpeed: number): number
	local from = wheel:GetAttribute("SpinFrom")
	local to = wheel:GetAttribute("SpinTo")
	local start = wheel:GetAttribute("SpinStart")
	local finish = wheel:GetAttribute("SpinEnd")
	if typeof(from) ~= "number" or typeof(to) ~= "number" or typeof(start) ~= "number" or typeof(finish) ~= "number" then
		return (idleSpeed * now) % 360
	end
	if now < start then
		-- Çevirmeden önce: kaydedilen başlangıç açısına kadar boşta hız
		return from - idleSpeed * (start - now)
	elseif now < finish then
		return from + (to - from) * easeOut((now - start) / (finish - start))
	end
	return to + idleSpeed * math.max(0, now - finish - WheelSpin.HOLD)
end

--[[
	Dilimin durma açısı. Dilim i (1'den) çarkın yerel düzleminde
	(i-1)·360/n derecede; tepedeki dil yerel +Y'de (90°). Çark bakış ekseni
	etrafında `a` kadar dönünce dilim (i-1)·360/n − a'ya geliyor.
]]
function WheelSpin.TargetFor(index: number, count: number, jitter: number): number
	local width = 360 / count
	return (index - 1) * width - 90 + jitter * width
end

--[[ `from`dan en az TURNS tur ötede, `target` (mod 360) açısı. ]]
function WheelSpin.SpinTo(from: number, target: number): number
	local base = from + 360 * WheelSpin.TURNS
	local offset = (target - base) % 360
	return base + offset
end

return WheelSpin
