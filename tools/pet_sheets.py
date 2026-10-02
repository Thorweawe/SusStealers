"""Pet konseptleri: ChatGPT'de 2x2 sayfalar (her sayfada 4 pet), sonra
tools/pet_sheets.py split ile çeyreklere kesilip models_3d/pets/<Id>_concept.png.

    python tools/pet_sheets.py first 1 | next 2..11   -> prompt metni
    python tools/pet_sheets.py split <sayfa no> <ham.png>
"""
import os
import sys

D = {
    # Supply Egg
    "Bolt": "a cute living metal bolt-and-nut creature with two big shiny eyes and tiny stubby feet",
    "VentRat": "a cute chubby brown space rat wearing tiny aviator goggles on its head",
    "Hamster": "a chubby golden cargo hamster carrying a tiny cargo crate backpack",
    "SparePod": "a cute floating spare astronaut helmet with cute eyes glowing inside the light-blue visor and two tiny side thrusters",
    "FuelCan": "a cute yellow fuel canister creature with big eyes, black hazard stripes and a little flame-shaped cap",
    # Skeld Egg
    "MiniCrew": "a tiny chibi red bean-shaped astronaut crewmate with a big light-blue visor and a small backpack",
    "BrainSlug": "a cute squishy pink alien brain slug with two little antennae and big happy eyes",
    "TaskBot": "a cute small teal robot on one wheel with a screen face showing happy eyes and a tiny wrench arm",
    "MedDrone": "a cute round white-and-light-blue medical drone with a red plus sign, two small propellers and a scanner eye",
    "SecurityCam": "a cute floating security camera creature with one big glowing lens eye and little propeller",
    "PrimeShield": "a cute floating blue energy-shield guardian with a glowing core in the middle and small wings",
    # Polus Egg
    "SnowPal": "a cute snowman pal made of two snowballs wearing a tiny astronaut helmet and a red scarf",
    "VentCrab": "a cute dark grey metal crab whose shell is a little floor vent grate, with big claws",
    "CoreShard": "a cute glowing orange reactor crystal shard creature with a happy face and small floating rock bits attached",
    "EscapePod": "a cute tiny white escape pod capsule with a round window face and small thruster fins",
    "SusShadow": "a cute purple shadow crewmate made of dark smoky purple goo with two glowing yellow eyes",
    "MeetingBell": "a cute red emergency meeting button dome creature with a glass top and tiny legs",
    "TheEgg": "a mysterious cream-colored egg with a glowing golden crack and a tiny curious eye peeking out",
    # Void Egg
    "VoidMite": "a cute small purple void mite bug with six little legs and glowing violet eyes",
    "StarJelly": "a cute pink jellyfish whose bell is shaped like a star, with short glowing tentacles",
    "CometPup": "a cute cyan puppy with a long glowing comet tail and star-shaped spots",
    "GhostCrew": "a cute pale blue ghostly floating crewmate with a wispy ghost tail instead of legs",
    "MiniImp": "a tiny cute crimson impostor crewmate with two small horns and a cheeky grin",
    "NebulaEye": "a floating cute eyeball made of swirling purple nebula with two small bat-like wings",
    "VoidShard": "a floating black obsidian crystal shard creature with glowing violet void cracks and one eye",
    # Nebula Egg
    "DustBunny": "a cute fluffy pink stardust bunny with sparkling fur and long ears",
    "NebSlime": "a cute purple nebula slime blob with stars swirling inside its translucent body",
    "WarpDrone": "a cute cyan warp drone with a glowing ring around it and a single round eye",
    "CosmoRay": "a cute blue cosmic manta ray with starry patterns on its wings",
    "PhantomCrew": "a cute lavender phantom crewmate wearing a flowing spectral hooded cloak",
    "StarWhale": "a cute navy blue baby whale with glowing constellation star spots on its back",
    "RiftWalker": "a mysterious dark purple rift creature with a body made of a glowing tear in space and small claws",
    # Celestial Egg
    "LuckyStar": "a cute chubby yellow star with a happy face and rosy cheeks",
    "CloverBot": "a cute small green robot shaped like a four-leaf clover with a round head",
    "FrostSprite": "a cute tiny ice fairy sprite with crystal wings and a snowflake crown",
    "SunBeetle": "a cute orange sun scarab beetle with a glowing sun disc on its back",
    "PrismFox": "a cute cyan fox made of shiny prism crystal with rainbow reflections",
    "CometKing": "a cute pink comet with a fiery tail and a tiny golden crown",
    "CelestCore": "a teal celestial orb core with two golden orbit rings and tiny stars",
}
IDS = list(D)
SHEETS = [IDS[i:i + 4] for i in range(0, len(IDS), 4)]  # 10 sayfa (son sayfa 1 pet)

STYLE = ("Create a 2x2 grid image of FOUR separate cute pet companion concepts for a Roblox space game, to be cut into four "
         "equal squares and each converted into a 3D model with an image-to-3D AI tool. STYLE: premium glossy collectible-toy "
         "3D render, chunky readable silhouettes, big cute eyes, rich saturated colors, soft even studio lighting. RULES: each "
         "pet is fully visible and centered in its own quadrant with plenty of empty space around it so nothing crosses into "
         "another quadrant, slight 3/4 front view from slightly above, the whole image has one plain flat light-grey seamless "
         "background, no grid lines, no borders, no shadows, no ground, no loose particles, no text. Square 1:1.")


def items(k):
    ids = SHEETS[k - 1]
    pos = ["top-left", "top-right", "bottom-left", "bottom-right"]
    return " ".join(f"{pos[i]}: {D[x]}." for i, x in enumerate(ids))


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode in ("first", "next"):
        k = int(sys.argv[2])
        if mode == "first":
            print(STYLE + " The four pets: " + items(k) + " I will ask for more sheets after this one; keep exactly the same style and rules.")
        else:
            print("Great. Next sheet, exactly the same style and rules (2x2, four separate pets, plain light-grey background, lots of space, no grid lines, no text, square). The four pets: " + items(k))
    elif mode == "split":
        from PIL import Image
        k, src = int(sys.argv[2]), sys.argv[3]
        im = Image.open(src).convert("RGB")
        w, h = im.size
        out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models_3d", "pets")
        for i, pid in enumerate(SHEETS[k - 1]):
            r, c = divmod(i, 2)
            cell = im.crop((c * w // 2, r * h // 2, (c + 1) * w // 2, (r + 1) * h // 2)).resize((1024, 1024), Image.LANCZOS)
            cell.save(os.path.join(out, pid + "_concept.png"))
            print(pid)
    elif mode == "count":
        print(len(IDS), "pet,", len(SHEETS), "sayfa")
