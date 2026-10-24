# Landscape settings

The settings for the landscape libraries in `lib/`. A piece sets any of
them **before** `(lib/fc_landscape.ps) run`, in the usual form

```postscript
/HazeDist where { pop } { /HazeDist 650 def } ifelse
```

so `scripts/render.sh -D HazeDist=400` can still override it from the
command line. A library keeps whatever is already defined (`fc-default`), so
a setting written in that form *after* loading is skipped: the library has
already defined the name. Several values are
worked out when a library loads (the camera's trigonometry, the sun's unit
vector, `TerrTop` from `TerrH`), so this rule applies even to settings
that look as if they're only read later.

**Colours** are `[r g b]` in sRGB, 0–1, as you'd pick them. The library
converts them to linear light (a 2.2 power) when it loads, and `fc-tone`
converts back at the end.

**Units:** one world unit is roughly ten metres. Heights are absolute `y`
values, with the valley floor near `TerrBase` (−6) and the tallest peaks
near `TerrBase + TerrH` (46).

**"Used" column:** the values that pieces and test renders have actually
used. A value outside them isn't known to be wrong, just untried. Blank
means only the default has been rendered.

See `docs/techniques.html` for how each part works.

## Scene (`lib/fc_landscape.ps`)

| Setting | Default | What it does | Used |
|---|---|---|---|
| `Seed` | 5 | Seeds everything: both noises, the trees and the march jitter. A new seed is a new range. | 5 |
| `TreesOn` | false | Loads `lib/fc_trees.ps` and marches the forest. It also turns off `fc_terrain`'s painted forest (`TreeLine` −1000) unless the piece sets `TreeLine`. | false, true |
| `Erode` | true | Bakes droplet erosion over the view (`fc_erode.ps`). Off skips the bake (about 1.5 min at `ErN` 1024); valleys then lack drainage channels and debris fans. | true |
| `CamLift` | 0 | If above 0, the camera sits at this fraction of `TerrTop`, but at least `CamAbove` over the ground below it (a high viewpoint). | 0, 0.72 |
| `CamAbove` | 6 | Otherwise, the camera sits this far above the ground below it. | 5, 6, 8 |
| `CamHeight` | null | A number puts the camera at exactly that height and overrides both of the above. | |
| `Profile` | false | true loads `lib/fc_bench.ps`, wraps the main procedures with call counters and timers, and prints a table when `fc-render` finishes (see Profiling below). false wraps nothing and the picture is unchanged. | false, true |

The camera always stands at x = z = 0, looking along +z before `Yaw`.
To stand somewhere else in the terrain, move the terrain under it with
`TerrOX`/`TerrOZ`.

## Profiling (`lib/fc_bench.ps`, with `Profile`)

`scripts/render.sh -D Profile=true gallery/mountains.ps` (usually with a small
`-D Res=0.25`) prints a table of calls, calls per pixel (render only, not the bakes),
**inclusive** milliseconds, share of the run and microseconds per call for
each wrapped procedure that ran, sorted by time. Rows overlap, because a procedure's time contains
its callees'. A footer measures the cost of the profiling itself (about
0.8 µs per wrapped call on an Apple-silicon Mac, a few percent of a run).
Wrapping happens when `fc-landscape-setup` starts and again before
`fc-render`, so it sees the piece's own hooks; a piece that redefines a
procedure after that must call `fc-bench-wrap` again. A procedure that was
wrapped and then redefined (the lake's `fc-landscape-hit`, which calls the
original as `fc-dry-hit`) gets a new row, and the old one stays as
`fc-landscape-hit#1`, so a hook and what it calls aren't mixed. Only
procedures defined in `userdict` are wrapped. How to read the
table is in `docs/techniques.html`, section 15.

| Setting | Default | What it does | Used |
|---|---|---|---|
| `ProfileProcs` | `fc-render`, the four `fc-landscape-*` hooks, `fc-terrain-hit`, `fc-forest-hit`, `fc-crowns`, `fc-canopy`, `fc-height`, `fc-terrain-shade`, `fc-terrain-shadow`, `fc-tree-shade`, `fc-tree-sunvis`, `fc-sky`, `fc-haze-colour`, `fc-haze`, `fc-tone`, `fc-clouds`, `fc-density`, `fc-cloud-light`, `fc-erode-bake`, `fc-forest-bake` | Array of procedure names to wrap. Names that aren't defined (the tree procedures without `TreesOn`) are skipped. Set it before loading to choose your own, e.g. `-D "ProfileProcs=[/fc-height /fc-noise3]"`. Very hot leaves such as `fc-noise3` are mostly overhead when wrapped. | default |

## Camera and render (`fc_sky.ps`, `fc_render.ps`)

| Setting | Default | What it does | Used |
|---|---|---|---|
| `Pitch` | 9 | Degrees above the horizon. | 0, 2, 3, 9 |
| `Yaw` | 0 | Degrees; positive turns right. | −27, 0, 10 |
| `HFov` | 64 | Horizontal field of view, degrees. | 50, 55, 64 |
| `TMax` | 900 | How far rays look, world units. Beyond it is sky. | 900 |
| `Res` | 1 | Image pixels per device pixel. 0.25 or 0.5 make fast composition checks. | 0.25, 0.5, 1 |
| `AA` | false | Antialias depth edges: 4 extra samples on pixels where the hit distance jumps (a few percent of pixels). Pieces turn it on. | false, true |
| `Crop` | (none) | `[x0 y0 x1 y1]`, fractions of the frame from the top left: render only that patch, at the full frame's detail. | many |

Resolution comes from the page size times `DPI` (a `render.sh` variable):
`DPI=72` gives 320×200 for a 320×200 pt piece, and `DPI=288` gives 1280×800.

## Sun, sky, haze and tone (`fc_sky.ps`)

| Setting | Default | What it does | Used |
|---|---|---|---|
| `SunDir` | [−0.55 0.42 0.72] | Direction *toward* the sun (x right, y up, z ahead before yaw). Normalised on load. Low `y` gives long shadows; negative `z` puts the sun behind the camera. | [−0.62 0.40 0.62], [0.55 0.50 0.45], [0.50 0.13 −0.55] |
| `SunCol` | [1.00 0.93 0.80] | Sunlight colour (sRGB). | also [1.00 0.72 0.48] (evening) |
| `Zenith` | [0.20 0.38 0.74] | Sky colour overhead. | also [0.24 0.34 0.58] |
| `Horizon` | [0.70 0.78 0.88] | Sky colour at the horizon. It's also the haze colour. | also [0.94 0.74 0.58] |
| `Exposure` | 1.6 | Brightness before the tone curve `1 − exp(−Exposure·L)`. | 1.6, 1.9 |
| `HazeDist` | 520 | Distance at which haze reaches 63% at height 0. Smaller means thicker air. | 400, 520, 650 |
| `HazeH` | 45 | Height over which the haze thins by a factor of e. | 45 |

## Clouds (`fc_clouds.ps`)

| Setting | Default | What it does | Used |
|---|---|---|---|
| `CloudLo`, `CloudHi` | 14, 40 | Bottom and top of the cloud layer. Pieces with mountains raise it above the peaks. | 14/40, 60/88, 62/84 |
| `Threshold` | 0.47 | Density cut-off. Higher means less cover. | 0.47, 0.57, 0.60 |
| `NoiseScale` | 0.045 | 1 / size of the cloud billows. | 0.045 |
| `CoverAmp` | 0 | Strength of a broad coverage map that gathers clouds into groups with clear gaps. | 0, 0.45, 0.5 |
| `CoverScale` | 0.0045 | 1 / wavelength of that map. | 0.0045 |
| `Sigma` | 0.09 | Extinction per unit density. Higher makes darker, more solid clouds. | 0.09 |
| `DensOct` | 5 | Most noise octaves, for near clouds; distant clouds use fewer. | 5 |
| `ShadOct`, `ShadStep` | 3, 3.2 | Octaves and spacing of the two probes toward the sun. | |
| `CloudSteps` | 96 | Most samples per ray. | |
| `AmbTop`, `AmbBot` | [0.62 0.72 0.88], [0.34 0.38 0.48] | Ambient light at the layer's top and bottom (sRGB). | |
| `CloudLayers` | null | null marches the one layer the settings above describe. Otherwise an array of layers (below), marched one after another, nearest band first. | null, `[/Cumulus /Altocumulus /Cirrus]` |

### Cloud layers (`CloudLayers`)

Each element of `CloudLayers` is a preset name or a dict that starts from a
preset and overrides some of its keys:

```postscript
/CloudLayers where { pop } {
    /CloudLayers [ /Default << /Type /Cirrus /Lo 140 /Hi 152 /Wind 60 >> ] def
} ifelse
```

The presets are `/Cumulus` (the gallery pieces' band, 60–88, with billow
noise: `Noise /Billow`, `Threshold` 0.41, `Gain` 12), `/Stratus`,
`/Altocumulus`, `/Cirrus`, `/Nimbostratus`, and `/Default`, which is the
single layer the `Cloud*` settings describe (so `[/Default /Cirrus]` keeps a piece's clouds and adds
cirrus above them). A dict without `/Type` starts from `/Default`. A
misspelt preset or key stops the job with an `undefined` error naming it,
and so does a layer with `Hi` not above `Lo` or with `Steps`, `DensOct` or
`ShadOct` below 1. The list is compiled the first time a ray needs it: a
piece that changes `CloudLayers` or a `Cloud*` setting after that calls
`fc-clouds-compile`. Layers must not overlap in height: each is marched
through its own band, and a ray's bands are taken in height order. A
layer's band runs from `Lo − Rain` (its rain counts) to `Hi`, and a band
that starts below the `Hi` of the layer under it stops the job with an
`undefined` error (`CloudLayers-overlap`). The sun probes of a layer see
only that layer, so a layer isn't shaded by another above it. In a layer
list, each layer's samples fade out over the last 30% of `TMax`, so a layer
that reaches the horizon thins out instead of ending in a hard line (the
single layer, `CloudLayers` null, keeps its old cut-off).

| Key | Base | What it does |
|---|---|---|
| `Lo`, `Hi` | 60, 88 | Base and top. |
| `Profile` | [6 1.6] | Height profile `min(a·h, 1)·min(b·(1 − h), 1)` over the band: `a` rounds the base, `b` the top. Larger is flatter. |
| `ProfAmp` | 0.35 | How much the profile raises the threshold: `(1 − profile)·ProfAmp`. |
| `Noise` | /Value | `/Value` is fBm; `/Billow` folds each octave (`abs(2n − 1)`) into rounded lumps with creases. Billow fBm is lower and wider (mean 0.30, sd 0.13, against 0.50 and 0.11), so it wants a lower `Threshold`. |
| `Scale` | 0.045 | 1 / billow size, like `NoiseScale`. |
| `Stretch` | [1 1.6 1] | Multiplies the noise coordinates along the wind, up, and across the wind. Below 1 stretches: cirrus uses 0.1 along the wind. |
| `Wind` | 0 | Degrees from +x (0 is across the default view, 90 is away from the camera): the direction streaks run. |
| `Shear` | 0 | The pattern leans with height, in world units: at height `h` above the base it is the base's pattern moved `Shear·h` against `Wind`. Invisible on streaks stretched along the wind (no preset uses it); meant for leaning towers and anvils. |
| `Threshold` | 0.57 | Density cut-off, like `Threshold`. |
| `CoverAmp`, `CoverScale` | 0.45, 0.0045 | The coverage map, like `CoverAmp` and `CoverScale`. |
| `Gain` | 14 | Density per unit of noise above the threshold. Lower is softer and more translucent. |
| `Sigma` | 0.09 | Extinction, like `Sigma`. |
| `DensOct`, `ShadOct`, `ShadStep` | 5, 3, 3.2 | Octaves and sun probes, like the settings. |
| `Steps` | 96 | Most samples per ray through this layer, like `CloudSteps`. A thin layer needs fewer. |
| `AmbTop`, `AmbBot` | as the settings | Ambient at the top and bottom (sRGB). |
| `Rain` | 0 | If above 0, rain shafts reach this far below the base: the cloud a quarter of the way up the band, in vertical columns that thin toward the ground. Extends the march. |
| `RainDens` | 0.15 | Their density, as a fraction of the cloud's. |
| `Shape` | null | A procedure `x y z oct → dd` (`oct`: the octaves the sample wants, fewer with distance) added to the density before the gain: a positive value adds cloud, a negative one cuts it. Only called inside the band (`Lo < y < Hi`), so a placed object needs a band tall enough to hold it. For placed objects such as a cumulonimbus (#15). Costs a call per sample. |

The Base column is where every preset starts (the gallery pieces' layer,
value noise); each preset's own values are in `FcClPresets` in
`lib/fc_clouds.ps`.

`x y z fc-cloud-shadow` gives the sunlight that reaches a point through
every layer above it (one density probe per layer, no march), for ground
shadows and sun shafts. `fc_terrain`'s `CloudShadowsOn` uses it with a
layer list; with `CloudLayers` null it keeps its old single probe at the
middle of `CloudLo`–`CloudHi`. Only the direct sun is shaded, not the sky ambient,
so an overcast darkens the ground only a little.

## Terrain shape (`fc_terrain.ps`)

| Setting | Default | What it does | Used |
|---|---|---|---|
| `TerrOX`, `TerrOZ` | 0, 0 | Shift the terrain under the camera: a cheap way to explore the same range. | 0/0, 180/400 |
| `TerrScale` | 0.011 | 1 / wavelength of the main ridges. Larger makes smaller, busier mountains. | 0.011 |
| `TerrH` | 52 | Height of the tallest peaks above `TerrBase`. | 52 |
| `TerrBase` | −6 | Valley floor. | −6 |
| `TerrOct` | 8 | Most octaves, used only close up; farther away detail under ~2 px is dropped. | 8 |
| `MassifScale` | 0.22 | Frequency of the mask that decides where ranges and broad valleys are, relative to the ridges: its wavelength is `1 / MassifScale` (4.5) ridge wavelengths. | 0.22 |
| `MassifLo`, `MassifHi` | 0.30, 0.56 | That mask's ramp. Raising both gives fewer, separate massifs. | |
| `WarpAmp` | 0.45 | Domain warp, in ridge wavelengths: how much the ridges wander. | 0.45 |
| `DetailAmp` | 0.16 | Strength of the gully texture (erosion fBm). | 0.16 |
| `TerrFn` | 3 | 3 is the massif hierarchy. 0 (ridged only) and 1 (erosion fBm only) are kept from early drafts. | 0, 1, 3 |
| `MarchT0` | 0.5 | Where marches start along a ray. A reflection sets it to the water distance while it marches, then puts it back. | 0.5 |
| `MapOn` | false | Loads `lib/fc_map.ps`, which defines `fc-terrain-base` from a map (next section). Off, the terrain is exactly the noise it always was. | false, true |
| `MapNoise` | 0 | With a map: how much of the noise massif mask still shows where the map pins nothing (it takes the larger of the two). 0 leaves unpinned ground to the map alone. | 0, 0.25 |
| `MapPin` | 1 | With a map: how fully pinned ground loses the domain warp. 1 keeps the ridges there on the noise's unwarped network, so a peak lands where it was put; 0 lets them wander as usual. | 1 |

## Terrain from a map (`fc_map.ps`, with `MapOn`)

A piece lays out its geography in map coordinates, which are the terrain's
own (`x` east, `z` north; a view's camera stands at `TerrOX`, `TerrOZ`
looking along `Yaw`), so several views share one map by moving only the
camera. The fractals fill in everything finer: the map sets the massif
mask (where ridged mountains grow), a lift in world units, and a pin that
takes the domain warp away near features. `fc-map-bake` samples it all
into a `MapN`² table when the library loads; a piece that changes the map
afterwards calls `fc-map-bake` again, before `fc-landscape-setup` (the
erosion bake reads the terrain). `fc-map-plan` draws the map from above;
`gallery/charted_range.ps` shows the lot. Only `TerrFn` 3 uses the map.

| Setting | Default | What it does | Used |
|---|---|---|---|
| `MapRect` | [−900 −900 900 900] | `x0 z0 x1 z1`: the area the table covers. Past it the map feathers to `MapBackground` over `MapFeather` units. | [−800 −800 800 800] |
| `MapN` | 128 | Table resolution (texels across; 12 units each at 1600 wide). Lookups are Catmull-Rom over 4×4 texels, so features narrower than about two texels blur. | 128 |
| `MapGrid` | null | A painted mask: an array of rows, the far (high `z`) row first, each a string of `MapChars` or an array of numbers 0–1, stretched over `MapRect`. 1 grows full mountains, 0 leaves valley floor. | |
| `MapChars` | `( .:-=+*#%@)` | The characters a string row may use, from 0 to 1. | |
| `MapFeatures` | [ ] | Features, each `[ /kind numbers… ]` (below). Heights and levels are world `y`. | |
| `MapBackground` | [0 0] | `[lift mask]` where nothing is painted and outside the rectangle. | [5 0.04] |
| `MapFeather` | 120 | Blend from the table to the background past `MapRect`'s edge. | |
| `MapPlanRect` | null | The area `fc-map-plan` draws (null: `MapRect`). | [−800 −560 800 440] |
| `MapPlanN` | 150 | Hillshade samples across the plan. | 320 |
| `MapPlanOct` | 5 | Terrain octaves in the plan. | 5 |

Features (applied peaks and ridges first, the tallest winning, then
valleys, then lakes, whatever their order in the list):

| Feature | What it does |
|---|---|
| `[ /peak height spread x z ]` | Raises the mask in a round bump `spread` units across, aimed so the ridge crest it grows stands about `height` high (within about 15%: the ridges' own height varies). Measured with `spikes/map_pins.ps`, the summit lands 10–32 units from `x z` over four seeds. |
| `[ /ridge height spread x0 z0 x1 z1 … ]` | The same along a polyline. |
| `[ /valley depth width x0 z0 x1 z1 … ]` | Carves: the mask falls to 0 along the polyline and the ground drops `depth`. |
| `[ /lake level depth shore x0 z0 x1 z1 x2 z2 … ]` | A closed polygon: inside it the mask is 0 and the bed sits `depth` below `level`, blending to the surroundings over `shore` units inside the edge. The piece puts its water plane at `level` (`gallery/charted_range.ps` uses `evening_lake`'s water hooks). |

Heights have two ceilings. A peak or ridge asks for a mask of at most 1,
so heights above about `lift + TerrBase + 1.02 TerrH` (47 with the
defaults and no lift) all give the tallest ridges the noise makes there.
And the march stops above `TerrTop` (`TerrBase + 1.25 TerrH`, 59): the
ground can reach about `lift + TerrBase + 1.16 TerrH`, so a lift over
about 5 can cut the tops flat. Raise `TerrH` for taller maps.

A lake's bed is flat only at the scale of the map: the valley-floor detail
(about ±`0.2 DetailAmp TerrH`, ±1.7 units with the defaults) stays, so a
lake shallower than that shows rocks and islands of bed.

## Terrain surface and light (`fc_terrain.ps`)

| Setting | Default | What it does | Used |
|---|---|---|---|
| `SnowLine` | 23 | Snow height: it fades in from 8 below to 8 above `SnowLine + 16·v`, where `v` is a broad 0–1 noise (so about `SnowLine + 8` on average). Snow also needs flat enough ground, and favours hollows and faces turned from the sun. | 23, 25, 27 |
| `TreeLine` | 7 | The *painted* forest colour on low gentle ground (no geometry). `TreesOn` sets it to −1000; real trees use `FsLine`. | 7, −1000 |
| `Rock`, `Rock2` | [0.42 0.41 0.39], [0.52 0.50 0.46] | Rock colours, mixed by strata and patches. | |
| `Scree` | [0.50 0.49 0.47] | Gentler slopes below cliffs. | |
| `Snow` | [0.94 0.95 0.97] | | |
| `Forest` | [0.20 0.26 0.18] | Painted-forest colour (see `TreeLine`). | |
| `SkyAmb` | [0.58 0.66 0.80] | Sky light on the ground and trees. | also [0.52 0.56 0.70] |
| `SkyLight` | 1.15 | Strength of that sky light. | 1.15 |
| `Bounce` | [0.40 0.36 0.30] | Warm light reflected up from the ground below. | |
| `BumpAmp` | 0.55 | How strongly steep rock breaks into lit and shaded facets. | 0, 0.55 |
| `ShadowsOn` | true | Terrain casts shadows (a march toward the sun per lit pixel). | true |
| `CloudShadowsOn` | true | Clouds shade the ground. | true |
| `ShadOctT` | 4 | Octaves of the terrain the shadow march uses. | 4 |
| `Penumbra` | 10 | Shadow-edge sharpness; larger is harder. | 10 |

## Erosion (`fc_erode.ps`)

The bake covers a square `ErSize` wide, centred `ErDist` ahead of the
camera along `Yaw`. Outside it, the terrain is procedural, blended over the
square's outer 6%.

| Setting | Default | What it does | Used |
|---|---|---|---|
| `ErN` | 512 | Map resolution. Use 1024 for a 1280-pixel render, 256 for quick tests. | 256, 512, 1024 |
| `ErDrops` | 60000 | Number of droplets. Scale it with `ErN²` (240000 at 1024). | 20000, 60000, 240000 |
| `ErSize`, `ErDist` | 1150, 430 | Area covered, world units. | |
| `ErSteps` | 48 | Most steps per droplet. | |
| `ErInertia` | 0.06 | How much a droplet keeps its direction. | |
| `ErCapacity`, `ErMinCap` | 0.6, 0.0004 | Sediment a droplet can carry. | |
| `ErErode`, `ErDeposit` | 0.35, 0.04 | How fast it picks up and drops sediment. | |
| `ErEvap` | 0.015 | Water lost per step. | |
| `ErGravity` | 4 | Acceleration downhill. | |
| `ErBaseOct` | 5 | Procedural octaves baked into the map. | 5 |
| `ErDelta` | true | Keep only erosion's *change* and add it to the full procedural terrain. false replaces the terrain with the map, which loses detail. | true, false |
| `FineAmp`, `FineScale` | 0.07, 7 | Detail added back in replace mode (`ErDelta` false). | |

## Forest (`fc_trees.ps`, with `TreesOn`)

The density map covers a square `FsSize` wide, centred `FsDist` ahead. Past
it, the forest is only a colour texture on the ground.

| Setting | Default | What it does | Used |
|---|---|---|---|
| `FsLine` | 20 | Treeline height. Ribs raise it and gullies lower it (`FsCurve`), and noise moves it ±`FsLineVar`. | 20 |
| `FsLineVar` | 5 | How far the treeline wanders. | 5 |
| `FsCurve` | 3 | How far ground curvature moves the treeline. | 3 |
| `FsCell` | 1.3 | One candidate tree per cell this wide. Smaller makes a denser stand, and the march slows near trees. | 1.3, 1.5 |
| `FsHMin`, `FsHMax` | 1.6, 3.2 | Heights of the dominant trees (16–32 m). A quarter are suppressed, at about half height. | |
| `FsTiers` | 9 | Branch whorls per crown. | 9 |
| `FsDroop` | 0.30 | How far each whorl's tips hang below its base, as a fraction of tree height. | 0.30 |
| `FsEnv` | 1.0 | Crown outline: 1 is a straight cone, more is a slimmer spire. | 1.0 |
| `FsN` | 384 | Density map resolution. | 384 |
| `FsSize`, `FsDist` | 700, 300 | Map size and its distance ahead. | |
| `FsAlb`, `FsAlb2` | [0.27 0.31 0.15], [0.22 0.29 0.21] | Sunlit needles, per-tree mix of olive and bluer spruce. | |
| `FsShade` | [0.15 0.22 0.21] | Needles lit only by the sky. | |
| `FsFloor` | [0.17 0.15 0.11] | Needle litter under the trees. | |
| `FsGrass`, `FsGrass2` | [0.36 0.41 0.20], [0.50 0.47 0.29] | Meadow colours, mixed by noise. | |

## Hooks a piece can redefine

These are procedures, not settings. Redefine them **after** loading
`fc_landscape.ps`. `gallery/evening_lake.ps` uses three of them to add a
lake.

| Hook | Stack | Default |
|---|---|---|
| `fc-landscape-hit` | `– → t \| −1` | `fc-forest-hit` with trees, `fc-terrain-hit` without. |
| `fc-landscape-surface` | `t → r g b` | `fc-tree-shade` on a crown, otherwise `fc-terrain-shade`. Linear light, before haze. |
| `fc-landscape-sky` | `dx dy dz → r g b` | `fc-sky` above the horizon, the haze colour below it. |
| `fc-landscape-grade` | `r g b → r g b` | Nothing. Linear light, just before the tone curve; a place for a colour grade or vignette. |
| `fc-forest-dens` | `x z h ny curv → density height-scale` | `fc_trees`' rules. Wrap it to keep trees off some ground, as the lake does. Redefine it before `fc-landscape-setup`. |
| `fc-terrain-material` | reads and changes `Alb KlMul KskyMul KbMul` | Defined by `fc_trees`. Without trees it doesn't exist, and a piece can define it to paint the ground. |
| `fc-terrain-base` | `x z → lift mask pin` | Defined by `fc_map.ps` (`MapOn`); otherwise absent and the noise massif is used. Map coordinates in; the lift in world units, the massif mask 0–1 and the pin 0–1 out. A piece can define its own (an analytic island, say) before `fc-landscape-setup`. |
| `fc-pixel` | `u v → r g b` | `fc-landscape-pixel`. Replace it entirely for a different scene. |

While a hook runs, `Mx My Mz` is the pixel's unit ray, from `(0, CamY, 0)`.
`PixAng` is the angle one pixel covers, so `t PixAng mul` is a pixel's
size at distance `t`. Use it to fade out detail that would be smaller than
a pixel.
