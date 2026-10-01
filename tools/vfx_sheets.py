"""Tematik parçacık sayfaları (3x3). python vfx_sheets.py first|next <A..E>  -> JS basar"""
import json
import sys

SHEETS = {
    "A": [("leaf", "a small fresh sprout leaf"), ("note", "a musical eighth note"), ("paw", "a cute pet paw print"),
          ("wrench", "a mechanic wrench"), ("feather", "a soft angel feather"), ("badge", "a five-pointed sheriff star badge"),
          ("atom", "an atom symbol with three electron orbits"), ("alert", "a bold exclamation mark inside a circle"),
          ("cloud", "a fluffy puffy cloud")],
    "B": [("heart", "a glowing heart"), ("bolt", "a jagged lightning bolt"), ("gem", "a faceted diamond gem"),
          ("sun", "a sun disc with straight rays"), ("phoenix", "a flaming phoenix feather made of fire"),
          ("ringed", "a small planet with a tilted ring"), ("vortex", "a black hole spiral vortex swirl"),
          ("rune", "a magic rune circle with mystical symbols"), ("galaxy", "a spiral galaxy")],
    "C": [("crown", "a royal crown"), ("crewmate", "a cute bean-shaped astronaut silhouette with a visor and a small backpack"),
          ("comet", "a comet with a long flowing tail"), ("confetti", "a handful of curly ribbon and square confetti pieces"),
          ("bell", "a jester bell"), ("pumpkin", "a carved jack-o-lantern pumpkin"), ("bat", "a flying bat"),
          ("candy", "a wrapped candy"), ("warning", "a warning triangle with an exclamation mark")],
    "D": [("slime", "a gooey slime droplet"), ("lava", "a cracked glowing lava rock chunk"), ("sandswirl", "a swirling sand gust"),
          ("eye", "a menacing glowing eye"), ("flare", "a solar flare arc"), ("moon", "a crescent moon"),
          ("shard", "a sharp ice shard"), ("pitchfork", "a devil pitchfork trident"), ("steam", "rising curly steam wisps")],
    "E": [("gear", "a machine gear cog"), ("tube", "a laboratory test tube with bubbles"), ("shield", "a knight shield"),
          ("sword", "a sword pointing up"), ("soundwave", "three concentric sound wave arcs"), ("shooting", "a shooting star with a short trail"),
          ("snowflake2", "an ornate royal snowflake"), ("vent", "a square floor vent grate"), ("plasma", "a plasma orb with electric arcs")],
}

STYLE = ("Create a 3x3 SPRITE SHEET of 9 separate particle-effect sprites for a Roblox game (they will be cut into 9 equal squares "
         "and used as ParticleEmitter textures, tinted in-game). STRICT RULES: pure solid black background; every sprite is drawn "
         "in WHITE and light grey only (no colors), glowing soft edges, bold readable silhouette, centered in its own cell with "
         "generous empty black padding so nothing touches the cell borders; no grid lines, no borders, no text, no labels, no "
         "numbers; flat front view; square 1:1 image. The 9 sprites in reading order (left to right, top to bottom): ")


def items(k):
    return "; ".join(f"{i + 1}. {d}" for i, (_, d) in enumerate(SHEETS[k])) + "."


def first(k):
    return STYLE + items(k) + " I will ask for more sheets after this one; keep exactly the same style and rules."


def nxt(k):
    return ("Great. Next sheet, exactly the same style and rules (3x3, white glowing sprites on pure black, generous padding, "
            "no grid lines, no text, square). The 9 sprites in reading order: " + items(k))


if __name__ == "__main__":
    mode, k = sys.argv[1], sys.argv[2]
    if mode == "names":
        print(" ".join(n for n, _ in SHEETS[k]))
        sys.exit()
    msg = first(k) if mode == "first" else nxt(k)
    print("const t=document.querySelector('[contenteditable=\"true\"]'); t.focus(); document.execCommand('selectAll'); "
          "document.execCommand('delete'); document.execCommand('insertText', false, " + json.dumps(msg) + "); t.innerText.length")
