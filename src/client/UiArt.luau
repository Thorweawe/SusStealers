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

	  İkonlar: 2026-10-02'den beri ui_art/icons_v2/ (ChatGPT, magenta zeminli
	  3x3 sayfalar → tools/icon_sheet.py; parlak çizgi film stili). Eskileri
	  (ui_art/icons/, Studio'da 3B render) dosya olarak duruyor.

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
	Cash100K = 101600801200737,
	Cash1M = 127364938569593,
	Cash10M = 136211766671654,
	DoubleIncome = 133557552469415,
	ExtraPodiums = 106705094573175,
	TripleHatch = 121118783438751,
	FastSteal = 120979117242158,
	StrongLock = 92050187191209,
	ExtraSpin = 110502213246084,
	LuckyRoll = 98801791089572,
	InstantRebirth = 79936549702522,
	Potion_Income2x = 76711568720765,
	Potion_Income3x = 117620987532024,
	Potion_FastSteal = 120389774662304,
	Potion_StrongLock = 77243707333799,
	Gift = 91789982665200,
	Crewmate = 133066838831577,
	Jackpot = 135057121803128,
	-- Sol menü, üst şerit, gear (2026-09-28)
	Nav_Shop = 75153510754378,
	Nav_Items = 113753771507006,
	Nav_Pass = 115232483891113,
	Nav_Index = 82447085989765,
	Top_Invite = 98723437212104,
	Top_Eye = 123892011958484,
	Top_Settings = 120433182136660,
	Gear_SlapGlove = 114915689320946,
	Gear_SpeedCoil = 77142471834660,
	Gear_StunGun = 128260156202040,
	Gear_EmergencyButton = 123780118268197,
	-- Envanter sekmeleri, sol alt haplar
	Tab_Pets = 132303795808238,
	Tab_Potion = 73196109363977,
	Tab_Style = 95551139044578,
	Stat_Speed = 120497940892462,
	-- Sunucu şansı ve troller (mağaza SERVER bölümü, şans hapı)
	ServerLuck = 76100846397960,
	Troll_Tiny = 93073892358290,
	Troll_Moon = 102387005407705,
	Troll_Alarm = 78113371691560,
}

--[[
	Etkinlik penceresinin tema arka planı (2026-10-02, ChatGPT; ui_art/event/).
	Etkinlik kimliğiyle; 0 = yok (pencere düz renkte kalıyor). Kare görsel:
	ortası sakin, kenarlarda temanın süsleri (kartlar üstüne çiziliyor).
]]
UiArt.EventArt = {
	Starfall2026 = 108816904618367,
	Spooky2026 = 122653922985764,
} :: { [string]: number }

--[[ Etkinlik ikonları (2026-10-02, ChatGPT; ui_art/event/): etkinlik parası ve
     etkinlik mutasyonlu crewmate. 0 = yok (pencere emojiye düşüyor). ]]
UiArt.EventIcon = {
	Starfall2026 = { currency = 128326808881128, crew = 110567546413682, egg = 138771601239015 },
	Spooky2026 = { currency = 114255378192611, crew = 97201831635569, egg = 0 },
} :: { [string]: { currency: number, crew: number, egg: number? } }

--[[ Yumurta penceresi parçaları (2026-10-03, ChatGPT taslağından; ui_art/egg_panel/).
     card ve button beyaz: nadirlik / düğme rengine ImageColor3 ile boyanıyor. ]]
UiArt.EggPanel = {
	panel = 88071937394696,
	ribbon = 132227460423845,
	pill = 107693385557081,
	card = 139933795705752,
	button = 107252720516918,
	padlock = 83299827826686,
	toggleOn = 99240466746290,
	toggleOff = 135665526365399,
	sparkle = 87251950512046,
} :: { [string]: number }

function UiArt.Image(kind: string, name: string): string
	local id = (UiArt :: any)[kind][name]
	return if id then "rbxassetid://" .. id else ""
end

--[[ 2026-10-03: unvan amblemleri (ChatGPT, ui_art/title_emblems; magenta zemin
     tools/cut_emblems.py ile kesildi). Anahtar Config.Titles kimliği; "Auto" =
     otomatik seçim satırı. Menüde ve baş üstü etiketinde. ]]
UiArt.TitleIcon = {
	Crewmate = "rbxassetid://78594507077324",
	SpaceRookie = "rbxassetid://114318060659644",
	SpaceThief = "rbxassetid://90067359652140",
	Rocketeer = "rbxassetid://80826202577036",
	Yeeted = "rbxassetid://124072381304024",
	HeistPro = "rbxassetid://127798963826874",
	MonsterTamer = "rbxassetid://98064024258130",
	IronWill = "rbxassetid://138631536178253",
	Captain = "rbxassetid://100532327581939",
	WarpRunner = "rbxassetid://130596462800335",
	VoidRaider = "rbxassetid://74437127033652",
	MutantHunter = "rbxassetid://99769028712891",
	Engineer = "rbxassetid://100824654622763",
	WeeklyTop10 = "rbxassetid://87947734407303",
	Lightspeed = "rbxassetid://116851664576203",
	GalaxyBandit = "rbxassetid://71015742679578",
	Collector = "rbxassetid://108856287751339",
	Admiral = "rbxassetid://109394160672775",
	WeeklyTop3 = "rbxassetid://89234230359248",
	LeviathanRobber = "rbxassetid://97820865159020",
	AmogusPrime = "rbxassetid://73824692760624",
	WeeklyChampion = "rbxassetid://71576547215012",
	MonstersNightmare = "rbxassetid://132055619931274",
	Auto = "rbxassetid://82367906378172",
} :: { [string]: string }

--[[ 2026-10-03: ana ekran (TitleScreen) ChatGPT görselleri, ui_art/title_screen:
     nebula arka planı, maskotlu logo, düğme yüzleri (dokuz dilim), cam kart. ]]
UiArt.TitleScreen = {
	bg = "rbxassetid://126802633649069",
	logo = "rbxassetid://74805130441503",
	play = "rbxassetid://131398909374576",
	purple = "rbxassetid://81675585191268",
	orange = "rbxassetid://113801390466137",
	panel = "rbxassetid://117742854490258",
}

return UiArt
