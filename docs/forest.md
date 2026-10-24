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
| Which | One candidate per 1.3-unit cell, jittered by up to 0.45 cell, kept where a hash is under the density (which an 8-unit noise thins into groves). A quarter are young or suppressed (about half height); the rest 1.6–3.2 units (16–32 m), crown radius ~0.28 × height. |
| Shape | A crown is a heightfield over the ground: nine whorls of branches, each hanging from the trunk and drooping (most at the tips) to a straight-cone envelope. Seen from above the surface is the highest whorl that reaches that far, so it steps down at each whorl's end. Whorls vary in length, and each whorl's reach varies around the trunk, so the outline is ragged. |
| Species, trunks | (#25) Each tree is of a species from the `FsSpecies` table, picked by `FsMix` (spruce only by default; mixes are experimental: one with pine and broadleaf lost blind pairwise, #53). In a closed stand the crown is lifted onto a bare trunk (self-pruned lower branches); at the edge and in the open it reaches the ground. A few trees are snags or logs. All of it only where a crown is over ~4 px wide. |
| March | `fc-forest-hit` replaces `fc-terrain-hit`. Above the trees it steps by clearance over the steepest nearby ground (a slope map baked with the density, so gentle valleys take long steps); among them, by vertical clearance over the crowns or horizontal distance to the nearest crown, whichever is larger. Bisection finds the surface. |
| Light | Crown normals come from the smooth envelope plus noise laid out along the branches, not from differencing the stepped whorls (that flips at random between pixels). Branch tops catch light, undersides and the gaps between clumps are dark. Sunlit needles are warm olive, sky-lit ones blue-green. Sun through other crowns (a short march toward it), the terrain's shadow, cloud shadow, sky light reduced inside and low in the crown. |
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
| iteration 2 | darker floor, treeline by curvature, canopy texture band-limited, haze back | **beat iteration 1 in blind pairwise, both orders, realism and aesthetics** |
| iteration 3 | crowns 0.28 × height on 1.5-unit cells, groves, two-tone needles | beat iteration 2 on aesthetics in both orders; realism split (position bias) |
| iteration 4 | 1.3-unit cells, gentler grove thinning | tied with iteration 3 (each order preferred the image shown second); kept, as the closed stand reads more like a valley forest |
| #25 | trunks under lifted crowns, fuller edge crowns, snags and logs, species table; bisection keeps the inside end (no ground speckle in the skirts) | close forest-edge crop beat iteration 4 in blind pairwise, both orders, realism and aesthetics (`docs/prs/25-trees-species/`) |
| #17 | exact early outs in the crown search (cells too far to matter, shadow probes above the tallest tree), species values in globals | pixel-identical; near and mid crops 16% faster (`docs/techniques.html`) |

Codex's absolute score for the trees was 4/10 at both critiques
(`docs/forest/iter01-320.critique.md`, and for iteration 2), as its absolute
scores were for the mountains; its notes were used for symptoms and the
pairwise tests for progress. Images for each round are in `docs/forest/`.

## Rendering

`scripts/render_bands.sh` splits a frame into horizontal bands, one pscat
per band (each a `render.sh` run with a `Crop`), and stitches them. Every
band does the whole setup, so the seeded scene is the same in each. (At
the time the cloud-march jitter continued differently per band and a band's
first row had no row above it for edge antialiasing; since #27 the jitter is
a hash of the pixel and a crop samples its neighbours' depth, so bands stitch
into exactly the whole-frame render.) Crops with the final settings (`-D Crop=...`) were
checked at full detail before the large render: foreground forest,
mid-distance slope and a cliff inside the forest map.

### Timings (pscat 0.6.2, Apple-silicon Mac, one thread per band)

| Render | Time |
|---|---|
| 320×200, 512² erosion map | 5.5 min (bakes 28 s) |
| 256×120 full-detail crop of the foreground forest | 2.6 min (5.1 ms/px) |
| 384×104 crop of the mid-distance slope | 4.6 min (6.6 ms/px) |
| 1280×800, 1024² erosion map, four bands | **25.5 min wall**, 81.6 min CPU; each band bakes in 1.7 min; the top band (sky, clouds, massif; 440 rows) was the slowest at 25 min |

Large render: `gallery/previews/alpine_forest-1280x800.png`
(`DPI=288 scripts/render_bands.sh gallery/alpine_forest.ps 0.55 0.66 0.81 -- -D ErN=1024 -D ErDrops=240000`).
The cut points were guessed from crop timings; the sky band turned out the
slowest, so `0.45 0.62 0.8` would balance better.

## Known limits

- The near-tree march is the cost: crowns are marched in short steps
  through the 3-unit tree band, and each step samples the terrain
  (`fc-height` is about two thirds of the time after #17). Fewer steps
  would move the hits, so #17 kept the step sequence and sped up only the
  crown search.
- Trunks only show where a crown is over about 4 px wide (#25 lifted the
  crowns of interior trees onto trunks, added snags and logs, and a
  species table; `FsMix` turns the spruce stand into a mixed one, experimental
  for now (pine and broadleaf lost blind pairwise; #53); see
  `docs/techniques.html`, "Species, trunks and dead trees").
- Trees don't know about snow: the density map is baked without it, and the
  ground shading thins the canopy colour where snow lies.
- The massif's rock still reads as folded rather than fractured (Codex's
  worst non-tree problem); finer octaves appear at larger sizes.
