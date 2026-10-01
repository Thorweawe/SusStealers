--!strict
--[[
	Temaya özel parçacık dokuları (2026-10-02). ChatGPT'den 3x3 sayfalar
	(siyah zemin, beyaz sprite; tools/vfx_slice.py ile kesilip vfx_art/vfx_<ad>.png),
	Roblox'a yüklenince kimlikleri buraya. Boş olan ad, çağıranın verdiği genel
	dokuya (Config.Vfx) düşüyor — kimlik gelmeden de her şey çalışıyor.

	    local T = require(Shared.VfxThemes)
	    e.Texture = T("note", Config.Vfx.Ring)
]]
local IDS: { [string]: string } = {
	-- Sayfa A
	leaf = "", -- a small fresh sprout leaf
	note = "", -- a musical eighth note
	paw = "", -- a cute pet paw print
	wrench = "", -- a mechanic wrench
	feather = "", -- a soft angel feather
	badge = "", -- a five-pointed sheriff star badge
	atom = "", -- an atom symbol with three electron orbits
	alert = "", -- a bold exclamation mark inside a circle
	cloud = "", -- a fluffy puffy cloud
	-- Sayfa B
	heart = "", -- a glowing heart
	bolt = "", -- a jagged lightning bolt
	gem = "", -- a faceted diamond gem
	sun = "", -- a sun disc with straight rays
	phoenix = "", -- a flaming phoenix feather made of fire
	ringed = "", -- a small planet with a tilted ring
	vortex = "", -- a black hole spiral vortex swirl
	rune = "", -- a magic rune circle with mystical symbols
	galaxy = "", -- a spiral galaxy
	-- Sayfa C
	crown = "", -- a royal crown
	crewmate = "", -- a cute bean-shaped astronaut silhouette with a visor and a small backpack
	comet = "", -- a comet with a long flowing tail
	confetti = "", -- a handful of curly ribbon and square confetti pieces
	bell = "", -- a jester bell
	pumpkin = "", -- a carved jack-o-lantern pumpkin
	bat = "", -- a flying bat
	candy = "", -- a wrapped candy
	warning = "", -- a warning triangle with an exclamation mark
	-- Sayfa D
	slime = "", -- a gooey slime droplet
	lava = "", -- a cracked glowing lava rock chunk
	sandswirl = "", -- a swirling sand gust
	eye = "", -- a menacing glowing eye
	flare = "", -- a solar flare arc
	moon = "", -- a crescent moon
	shard = "", -- a sharp ice shard
	pitchfork = "", -- a devil pitchfork trident
	steam = "", -- rising curly steam wisps
	-- Sayfa E
	gear = "", -- a machine gear cog
	tube = "", -- a laboratory test tube with bubbles
	shield = "", -- a knight shield
	sword = "", -- a sword pointing up
	soundwave = "", -- three concentric sound wave arcs
	shooting = "", -- a shooting star with a short trail
	snowflake2 = "", -- an ornate royal snowflake
	vent = "", -- a square floor vent grate
	plasma = "", -- a plasma orb with electric arcs
}

return function(name: string, fallback: string): string
	local id = IDS[name]
	if id and id ~= "" then
		return id
	end
	return fallback
end
