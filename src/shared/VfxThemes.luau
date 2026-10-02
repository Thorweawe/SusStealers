--!strict
--[[
	Temaya özel parçacık dokuları (2026-10-02). ChatGPT'den 3x3 sayfalar
	(siyah zemin, beyaz sprite; tools/vfx_slice.py ile kesilip vfx_art/vfx_<ad>.png),
	Roblox'a yüklenince kimlikleri buraya (2026-10-02 yüklendi: grubun Decal'ları,
	burada decal'ın içindeki Image kimliği). Boş olan ad, çağıranın verdiği genel
	dokuya (Config.Vfx) düşüyor — kimlik gelmeden de her şey çalışıyor.

	    local T = require(Shared.VfxThemes)
	    e.Texture = T("note", Config.Vfx.Ring)
]]
local IDS: { [string]: string } = {
	-- Sayfa A
	leaf = "rbxassetid://120340439733829", -- a small fresh sprout leaf
	note = "rbxassetid://126572814688920", -- a musical eighth note
	paw = "rbxassetid://79310862597196", -- a cute pet paw print
	wrench = "rbxassetid://77050447843090", -- a mechanic wrench
	feather = "rbxassetid://96221186177933", -- a soft angel feather
	badge = "rbxassetid://73547005911014", -- a five-pointed sheriff star badge
	atom = "rbxassetid://131935112656985", -- an atom symbol with three electron orbits
	alert = "rbxassetid://113696936438998", -- a bold exclamation mark inside a circle
	cloud = "rbxassetid://119223125538889", -- a fluffy puffy cloud
	-- Sayfa B
	heart = "rbxassetid://133905130797732", -- a glowing heart
	bolt = "rbxassetid://79157092184264", -- a jagged lightning bolt
	gem = "rbxassetid://99564978038159", -- a faceted diamond gem
	sun = "rbxassetid://106379280150860", -- a sun disc with straight rays
	phoenix = "rbxassetid://108765919437105", -- a flaming phoenix feather made of fire
	ringed = "rbxassetid://72412263711701", -- a small planet with a tilted ring
	vortex = "rbxassetid://131063125988695", -- a black hole spiral vortex swirl
	rune = "rbxassetid://115303978938984", -- a magic rune circle with mystical symbols
	galaxy = "rbxassetid://111377579097051", -- a spiral galaxy
	-- Sayfa C
	crown = "rbxassetid://123853210098061", -- a royal crown
	crewmate = "rbxassetid://132874565469959", -- a cute bean-shaped astronaut silhouette with a visor and a small backpack
	comet = "rbxassetid://113929181841792", -- a comet with a long flowing tail
	confetti = "rbxassetid://123250983740748", -- a handful of curly ribbon and square confetti pieces
	bell = "rbxassetid://80023354657421", -- a jester bell
	pumpkin = "rbxassetid://138890511963828", -- a carved jack-o-lantern pumpkin
	bat = "rbxassetid://127871856780507", -- a flying bat
	candy = "rbxassetid://92212473825476", -- a wrapped candy
	warning = "rbxassetid://74067198269212", -- a warning triangle with an exclamation mark
	-- Sayfa D
	slime = "rbxassetid://74013114985649", -- a gooey slime droplet
	lava = "rbxassetid://75435476468098", -- a cracked glowing lava rock chunk
	sandswirl = "rbxassetid://107100570955493", -- a swirling sand gust
	eye = "rbxassetid://79944851730340", -- a menacing glowing eye
	flare = "rbxassetid://78890878771364", -- a solar flare arc
	moon = "rbxassetid://71803667210244", -- a crescent moon
	shard = "rbxassetid://101427202972447", -- a sharp ice shard
	pitchfork = "rbxassetid://126953834519661", -- a devil pitchfork trident
	steam = "rbxassetid://113483113300845", -- rising curly steam wisps
	-- Sayfa E
	gear = "rbxassetid://88989066274799", -- a machine gear cog
	tube = "rbxassetid://130042803836867", -- a laboratory test tube with bubbles
	shield = "rbxassetid://112297517043003", -- a knight shield
	sword = "rbxassetid://91503707048158", -- a sword pointing up
	soundwave = "rbxassetid://70591123699832", -- three concentric sound wave arcs
	shooting = "rbxassetid://115046902921301", -- a shooting star with a short trail
	snowflake2 = "rbxassetid://91105421259690", -- an ornate royal snowflake
	vent = "rbxassetid://137239933661871", -- a square floor vent grate
	plasma = "rbxassetid://121894492395302", -- a plasma orb with electric arcs
}

return function(name: string, fallback: string): string
	local id = IDS[name]
	if id and id ~= "" then
		return id
	end
	return fallback
end
