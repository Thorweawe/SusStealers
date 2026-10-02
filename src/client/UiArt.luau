--!strict
--[[
	Arayüz görsellerinin Roblox kimlikleri (2026-09-28, "UI'lar videodaki gibi
	kaliteli olsun"). Hepsi saydam PNG:

	  Dokular (tools/ui_art.py): ImageColor3 ile boyanıyor
	    halftone       döşenebilir nokta ızgarası
	    halftone_fade  üstte büyük, altta küçülen noktalar (kart üstü)
	    sparkle        dört köşeli parıltı (yükselen parçacık)
	    glow           yumuşak daire (ikon arkası hale)
	    stripes        döşenebilir çapraz şeritler (başlık şeridi)

	  İkonlar (ui_art/icons/, tools/ui_icons.py): oyunun kendi modelleriyle
	  Studio'da 3B render + koyu dış çizgi.

	Yeni görsel: PNG'yi üret, Studio MCP upload_image ile yükle, kimliği
	buraya yaz.
]]

local UiArt = {}

UiArt.Texture = {
	halftone = 107506421356942,
	halftone_fade = 138293741076476,
	sparkle = 96494736086101,
	glow = 105820443796981,
	stripes = 127645580329632,
	rays = 121213630524182,
	wheel_face = 139605001347962,
	wheel_pointer = 118581784688287,
}

UiArt.Icon = {
	Cash100K = 83419074810007,
	Cash1M = 95690573965959,
	Cash10M = 134477383072280,
	DoubleIncome = 83645543792614,
	ExtraPodiums = 77969748690488,
	TripleHatch = 83748630208294,
	FastSteal = 129745034534885,
	StrongLock = 110311137898872,
	ExtraSpin = 140532760122223,
	LuckyRoll = 71477843264344,
	InstantRebirth = 110316852701915,
	Potion_Income2x = 89145444737480,
	Potion_Income3x = 134082346937668,
	Potion_FastSteal = 131791620825008,
	Potion_StrongLock = 91791015797563,
	Gift = 139278632459793,
	Crewmate = 103077116178309,
	Jackpot = 140269949452609,
	-- Sol menü, üst şerit, gear (2026-09-28)
	Nav_Shop = 97169877415725,
	Nav_Items = 100732446466588,
	Nav_Pass = 101823903298869,
	Nav_Index = 101101085972157,
	Top_Invite = 79813361359000,
	Top_Eye = 85711644460792,
	Top_Settings = 92911947544549,
	Gear_SlapGlove = 132543684529943,
	Gear_SpeedCoil = 106848659288772,
	Gear_StunGun = 111727037136617,
	Gear_EmergencyButton = 120840718417896,
	-- Envanter sekmeleri, sol alt haplar
	Tab_Pets = 105447129249807,
	Tab_Potion = 105612339081576,
	Tab_Style = 91214765132761,
	Stat_Speed = 99403146956988,
	-- Sunucu şansı ve troller (mağaza SERVER bölümü, şans hapı)
	ServerLuck = 79817173307828,
	Troll_Tiny = 109290408619292,
	Troll_Moon = 86179954993615,
	Troll_Alarm = 115282988948591,
}

--[[
	Etkinlik penceresinin tema arka planı (2026-10-02, ChatGPT; ui_art/event/).
	Etkinlik kimliğiyle; 0 = yok (pencere düz renkte kalıyor). Kare görsel:
	ortası sakin, kenarlarda temanın süsleri (kartlar üstüne çiziliyor).
]]
UiArt.EventArt = {
	Starfall2026 = 0,
	Spooky2026 = 0,
} :: { [string]: number }

--[[ Etkinlik ikonları (2026-10-02, ChatGPT; ui_art/event/): etkinlik parası ve
     etkinlik mutasyonlu crewmate. 0 = yok (pencere emojiye düşüyor). ]]
UiArt.EventIcon = {
	Starfall2026 = { currency = 0, crew = 0 },
	Spooky2026 = { currency = 0, crew = 0 },
} :: { [string]: { currency: number, crew: number } }

function UiArt.Image(kind: string, name: string): string
	local id = (UiArt :: any)[kind][name]
	return if id then "rbxassetid://" .. id else ""
end

return UiArt
