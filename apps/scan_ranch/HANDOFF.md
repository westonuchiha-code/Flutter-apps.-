# Scan Ranch — hand-off notes (art + prototype)

The game is a working prototype. **The monster art is the unfinished part.**
These notes are for whoever takes over the art: what the owner wants, what was
tried, what was rejected and why, what was approved, and how the art plugs
into the game.

## 1. What the game is

An Android app where you **scan real barcodes** to get monsters, then keep them
on a **ranch** (a field where up to 8 roam) or in a **box** (storage).

- **Inspirations:** *Skannerz* (Radica, 2004) for getting monsters from
  barcodes, and *Pokémon Ranch* (Wii) for the ranch. All creatures, names and
  art must be **original**: borrow the ideas, never the content.
- **Mechanics in the prototype:**
  - A barcode always gives the same species. Each catch also gets its own
    shade, size, personality and a 1-in-128 "shiny" colouring.
  - Some barcodes hold food items instead of a monster (a Skannerz nod).
  - Nicknames, the box, petting by tapping, dropping food, and hunger and
    happiness that change in real time.
- **Room to grow:** cleaning up after monsters, toys, battles, adventures. The
  hooks are in `lib/sim/ranch_sim.dart` (new behaviour states), `ItemKind`
  (new items), `Creature.extraNeeds` (new needs) and `Genome.baseStats`
  (battle stats; tribes already have a strength triangle).

## 2. The look the owner wants (read this first)

- **Edgy, aggressive and cool, like Skannerz or Digimon.** That toy was
  marketed as edgy. **Not cute, not cozy, not a Tamagotchi.** The owner said
  this explicitly after the cozy attempt.
- **Every monster should look like a deliberately designed creature**, not a
  random kit of parts. Coherent silhouettes, mean faces, sharp teeth, claws,
  spikes, strong stances.
- **Big enough to be detailed.** There is no LCD size limit; this is an
  Android game. 64×64 was the minimum the owner found workable; bigger is fine.
- **Teeth must be sharp fangs** that taper to a point, not "Chiclets or Tic
  Tacs".
- **Legs must not look like teddy-bear legs**: no round blobs on top of straight
  columns with stubby feet.
- **The CRT look is required: monsters only, always on, never a setting.**
  That means scan lines, a soft glow and a vignette (`5-crt-options...png`,
  option 4). The owner felt it "smooths it out and makes it look like a much
  nicer piece of art". Backgrounds and UI stay clean. It is applied in code
  (`lib/render/monster_art.dart`), so new art gets it automatically.
- **A good variety system** (the owner's own idea): around 10 well-made
  silhouettes × around 10 eye designs × a good palette set, plus 2–3 more
  random slots such as markings or hats. That gives thousands of distinct
  individuals from a small amount of good art.

## 3. What was tried, and why it was rejected

Pictures of every round are in `docs/art_history/`.

1. **Procedural vector shapes** (`1-vector-shapes-REJECTED.png`). Ellipses and
   paths combined at random. The owner called them "atrocious". Random parts
   don't add up to a designed creature.
2. **Procedural cute pixel art at 40 px, plus a cozy ranch**
   (`2-…REJECTED.png`, `2b-…`). Chibi faces and pastel grass. **Wrong tone
   (cute and cozy)**, and still a random kit of parts.
3. **Hand-pixelled 32×32 silhouettes** (`3-…REJECTED.png`): drake, hound,
   beetle, gargoyle, wyrm, brute, mantis, wraith, harpy and scorpion. Edgier
   and "a thousand times better" than the earlier attempts, but still ugly:
   too small for detail and stiff shapes. The owner said: go bigger.
4. **64×64 shaded silhouettes: drake and hound**, refined with the owner
   (`4a-…` to `4b-…APPROVED.png`). Hand-placed shapes with volume shading. Fixes
   made with the owner:
   - **Teeth:** fewer, spaced fangs, 2 px at the gum, a 1 px point and a curved
     canine, in a wider-open jaw.
   - **Legs:** the teddy-bear look came from round thighs over straight columns
     with stubby feet. It was fixed with *predator* legs: a heavy thigh, the
     knee pushed forward, a thin shin swept back to a raised heel, long toes,
     and bone-white hooked claws.
   - **Outlines:** coloured from the neighbouring skin (darker on the shadow
     side, softer on the lit side) instead of flat black. Overlaps get a soft
     shadow instead of a hard seam line.

   Owner's verdict: **"okay"**. These are the only approved designs, and only
   just. They are the bar to beat, not a finished standard.
5. **Eight more 64×64 silhouettes** in the same method (`6-…REJECTED.png`):
   beetle, gargoyle, wyrm, brute, mantis, wraith, harpy, scorpion. All
   rejected: "they all look bad except for the two we went over together".
   Kept in `assets/monsters/rejected/` for reference only; the game does not
   use them.

## 4. Why it went wrong, and how to do better

- **Procedural parts can't produce designed creatures.** Don't generate
  silhouettes. Design each silhouette by hand (or with a real art tool), then
  generate *variation* (palette, eyes, markings, size) on top. This is the
  owner's own plan, and the right one.
- **Iterate one design at a time with the owner.** The two designs that passed
  were the only ones reviewed closely together. Batches of eight drafted
  without review all failed. Show one or two, get notes, fix them, then move on.
- **Readability over detail.** Each design needs a strong, instantly
  recognisable silhouette in solid black before any shading. Several rejected
  ones only read with colour (the mantis looked like a deer, the harpy's wing
  like a rag, the wraith like a cute ghost).
- **Shape language for "edgy":** angular forms, forward-leaning stances,
  exaggerated weapons (horns, claws, fangs, scythes), small mean eyes or
  glowing eyes, heavy brows. Avoid round heads, big eyes, symmetric stubby
  limbs and pastel colours.
- **Shading:** pillow shading (darkening every edge) makes things look plush.
  Use one light direction, a clear shadow side, a highlight on the lit edge,
  and keep planes crisp. Hue-shift shadows cooler and highlights warmer.
- **Use a real pixel-art or illustration tool** (e.g. Aseprite) if you can.
  The shape-scripting workbench was a workaround, not an art tool.

## 5. How art plugs into the game

- **Sprites:** `assets/monsters/<name>.png`, listed in
  `assets/monsters/manifest.json` → `"silhouettes"`. The order matters: a
  monster's `Genome.silhouette` indexes this list, and `silhouetteCount` in
  `lib/model/genome.dart` must match its length.
- **Format: a material map, so one drawing works with every palette.**
  64×64 PNG, sprite facing **right**, feet on the bottom rows.
  - `R` = material id, an index into the manifest's `"materials"`: body, back
    (far limbs), belly, accent, claw, mouth, outline, eye, eye glow, pupil,
    teeth, claw tips.
  - `G` = shade tone 0–4 × 50 (0 = deepest shadow, 200 = highlight). For
    outline pixels, `G` is the material id it touches instead.
  - `B` = 1 on the lit side of the outline. `A` = 255 where drawn.
- **Palettes:** 12 edgy palettes in `lib/render/monster_art.dart`
  (`monsterPalettes`). Each material gets a 5-tone hue-shifted ramp.
- **Want to paint full-colour art instead?** Set `MonsterArt.fullColour =
  true` and ship ready-coloured PNGs. Palettes are then ignored, so colour
  variety would need separate PNGs or a hue-shift filter. The CRT look still
  applies.
- **Bigger sprites:** change the PNG size. The code reads the size from the
  image and scales to the ranch.
- **Animation (current):** single frame. Walking is a bob and lean, eating is
  a head dip, petting is a hop. Real animation frames (walk, idle, eat, happy)
  would be a good upgrade. Add frames to the manifest and pick them in
  `RanchPainter`.
- **Eye designs (planned, not done):** the eye is part of each drawing today.
  The plan was ~10 eye overlays (slit, glowing, cyclops, visor, triple,
  scarred, compound…) placed at a per-silhouette eye anchor.

## 6. Tools

- `tool/sprite_design/` holds the Python workbench used for rounds 3–6
  (`hd.py` renderer; `hd_drake.py` and `hd_hound.py` are the approved ones;
  `export.py` writes the material-map PNGs; `scan.py` previews the CRT look).
  Run with `PYTHONPATH=. python3 <script>.py`. It needs Pillow.
- Generation rules (pure Dart, tested): `lib/model/genome.dart`.
