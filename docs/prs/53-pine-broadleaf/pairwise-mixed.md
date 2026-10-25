# Blind pairwise (scripts/codex_pairwise.sh): mixed stand, main (spruce only) vs this branch with FsMix=[0.45 0.2 0.15 0.1 0.1]

Crop `Crop=[0.68 0.68 0.98 0.98]` of `gallery/alpine_forest.ps` at 1280x800 (DPI=288), the same close forest edge #25 used. Old: `spruce-main.png` (main 8506578, default `FsMix [1]`). New: `mixed-after.png` (this branch, defaults plus the mix). Final version, three runs of both orders:

| Run | Order 1 (old first) | Order 2 (new first) |
|---|---|---|
| 1 | realism **new**, aesthetics **new** | realism **new**, aesthetics **new** |
| 2 | realism **new**, aesthetics old | realism **new**, aesthetics **new** |
| 3 | realism **new**, aesthetics old | realism **new**, aesthetics **new** |

Realism: new 6/6. Aesthetics: new 4/6 (in order 1 of runs 2 and 3 Codex preferred the old image's composition: "cleaner foreground", "quieter spacing").

## Earlier rounds (not kept)

| Version | Order 1 | Order 2 | Codex's complaint about the new image |
|---|---|---|---|
| masses stacked up the crown (#25's mix) | old, old | new, new | rounded foliage appears disconnected |
| same, mix `[0.4 0.1 0.25 0 0.25]` | old, old | old realism, new aesthetics | crowns floating, thin exposed trunks |
| trunks at every size, crowns always lifted | old, old | new, new | rounded clumps look artificial and detached |
| crown-lit normals, lower bases | old, old | new, new | rounded clumps and exposed trunks artificial |

Sub-crop proxy (`[0.69 0.68 0.82 0.85]`, about 4 minutes a render) while reshaping the crowns: ellipsoid envelope 2/4 (tie), smaller masses 0/4, conical pine 0/4 ("detached" pads: the masses then floated free of the core). Capping each mass's reach so it overlaps the core gave the final version above.

## run 1
### order 1 (old shown first, as A)
REALISM: B
AESTHETICS: B
- B’s irregular foliage and varied silhouettes feel more natural.
- A’s trees look more uniformly conical and repetitive.
- B’s fuller foreground trees create stronger depth and visual interest.
- Both have flat lighting and muted detail that suggest a render.

### order 2 (new shown first, as A)
REALISM: A
AESTHETICS: A
- A’s varied tree shapes feel more organic; B’s repeated cones look manufactured.
- A’s smaller foreground trees create a more convincing sense of scale.
- A has a more balanced foreground; B’s large central tree dominates.
- Both have atmospheric depth, but flat ground and angular foliage limit photographic realism.

## run 2
### order 1 (old shown first, as A)
REALISM: B
AESTHETICS: A
- B’s irregular crowns and varied silhouettes feel more like a natural forest.
- A’s prominent foreground tree provides a stronger visual anchor.
- A’s cleaner spacing and quieter foreground create a more balanced composition.

### order 2 (new shown first, as A)
REALISM: A
AESTHETICS: A
- A’s varied tree shapes and spacing feel more natural; B’s repeated cones look more synthetic.
- A’s softer transitions into haze give the forest more convincing depth.
- A’s open foreground and less dominant central tree create a calmer, more balanced composition.

## run 3
### order 1 (old shown first, as A)
REALISM: B
AESTHETICS: A
- B’s irregular crowns and varied silhouettes make the forest feel less repetitive.
- A’s cleaner foreground and clearer spacing give the composition more breathing room.
- A’s restrained shapes work well with the muted palette and atmospheric haze.

### order 2 (new shown first, as A)
REALISM: A
AESTHETICS: A

- A has more varied tree shapes and spacing, making the forest feel less repetitive.
- A’s open foreground gives the scene more breathing room and depth.
- B’s repeated cone shapes and prominent foreground tree make the procedural structure more obvious.

