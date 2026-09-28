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
}

function UiArt.Image(kind: string, name: string): string
	local id = (UiArt :: any)[kind][name]
	return if id then "rbxassetid://" .. id else ""
end

return UiArt
