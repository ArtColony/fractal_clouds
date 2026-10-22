# Alpine forest (#1, trees)

`gallery/alpine_forest.ps`: the range from `gallery/mountains.ps`, seen from
the edge of a valley floor, with a spruce forest on the floor and lower
slopes. One ray per pixel, rendered by pscat 0.6.2. Status: draft until
the owner marks it final.

The mountains view looked down from high over the range, and the lowest
ground in it was at height 14 (`spikes/treemask.ps` bands the visible
ground by height). Below a realistic treeline (about a third of the relief
above the valley floor, ~20 here) there was only one hazy valley, where
trees would have been a pixel or two. So this piece moves the camera
(`TerrOX`/`TerrOZ` shift the procedural terrain under it) to a valley edge
8 units (~80 m) above the ground, looking up at the massif.

## How the trees are made (`lib/fc_trees.ps`)

| Part | What it does |
|---|---|
| Where | A density map baked over the view (384², 700 units): below a wandering treeline that ribs raise and gullies lower, off slopes steeper than ~45°, with clearings, meadows on the flattest valley floor, and a few stunted trees above the line. Trees near the line are shorter. |
| Which | One candidate per 1.2-unit cell, jittered by up to 0.45 cell, kept where a hash is under the density. A quarter are young or suppressed (about half height); the rest 1.6–3.2 units (16–32 m), crown radius ~0.22 × height. |
| Shape | A crown is a heightfield over the ground: nine whorls of branches, each hanging from the trunk and drooping (most at the tips) to a straight-cone envelope. Seen from above the surface is the highest whorl that reaches that far, so it steps down at each whorl's end. Whorls vary in length, and each whorl's reach varies around the trunk, so the outline is ragged. |
| March | `fc-forest-hit` replaces `fc-terrain-hit`. Above the trees it steps by clearance over the steepest nearby ground (a slope map baked with the density, so gentle valleys take long steps); among them, by vertical clearance over the crowns or horizontal distance to the nearest crown, whichever is larger. Bisection finds the surface. |
| Light | Crown normals come from the smooth envelope plus noise laid out along the branches, not from differencing the stepped whorls (that flips at random between pixels). Branch tops catch light, undersides and the gaps between clumps are dark. Sun through other crowns (a short march toward it), the terrain's shadow, cloud shadow, sky light reduced inside and low in the crown. |
| Ground | `fc-terrain-shade`'s material hook: dark needle litter under the trees, with their shadows and most of the sky hidden; grass on open gentle ground below the line. |
| Distance | Branch detail fades out between 12 and 4 px crown radius; below ~2 px, crowns melt into a canopy layer of the same mean height, shaded as a texture no finer than about three pixels. |

## How it got here

| Round | Change | Result |
|---|---|---|
| eligibility | `spikes/treemask.ps` on the mountains view | nothing below 14; moved the camera |
| first trees | cones with branch tiers, 2×2 cells | a forest at 160 px, but grey speckle in crowns and 6 ms/px |
| speckle | material false-colour render | ground seen through gaps (fine) lit as rock (not): dark floor |
| speed | call counts | 86 of 92 `fc-height` calls per pixel in the march, most above the trees at 7° rays; slope-map steps cut the above-tree steps 30–50% |
| look | sun from the right, meadows | lit massif, green valley, cloud shadows |
| noise | tiers off / normals view | the tier formula made the surface rise outward (inverted facets); then finite-difference normals across whorl steps flipped per pixel; fixed with drooping whorls and analytic normals |
| proportions | `spikes/tree_side.ps` side view; Codex | 3:1 alone but only slivers visible in the stand, uniform sizes, grid lanes: wider crowns, 3×3 cells with full jitter, suppressed trees |

## Known limits

- The near-tree march is the cost: crowns are marched in short steps
  through the 3-unit tree band.
- No trunks: under dense spruce they're hidden, but they'd show at a
  forest edge seen close.
- Trees don't know about snow: the density map is baked without it, and the
  ground shading thins the canopy colour where snow lies.
- The massif's rock still reads as folded rather than fractured (Codex's
  worst non-tree problem); finer octaves appear at larger sizes.
