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

## Presets and scene files (`lib/fc_presets.ps`)

A **preset** is a named dictionary of settings; a **scene file** is the same
kind of dictionary in a `.ps` of its own. Applying either sets each setting
only if nothing has defined it yet, so the order of precedence is: `-D` on
the command line, then the piece's own settings, then presets (earlier in
the list first), then the library's defaults. So a piece's settings must come
**before** the `fc-presets` line to win: written after it, they are skipped
like any setting made after loading. Apply the presets **before**
`(lib/fc_landscape.ps) run`, for the same reason every setting is:

```postscript
/Yaw where { pop } { /Yaw -27 def } ifelse      % the piece's own settings
(lib/fc_presets.ps) run
[ /Evening /Clear /Alpine ] fc-presets          % time of day, weather, terrain
(lib/fc_landscape.ps) run
320 200 fc-landscape
showpage
```

| Procedure | Stack | What it does |
|---|---|---|
| `fc-preset` | `/Name → –` | Apply one preset. An unknown name prints `fc_presets: no preset called Name` and stops with `undefined`. |
| `fc-presets` | `[/Name …] → –` | Apply several in order. Where two set the same setting, the earlier wins, so list the most specific first (a season before the terrain). |
| `fc-settings` | `dict → –` | Apply a dictionary of settings. Its `/Presets` key (an array of preset names) is applied after its other keys, so a dictionary's own values beat its presets; presets may list presets the same way. |

A new preset is one entry (`FcPresets` is an ordinary dictionary in
`userdict`, so a piece can add its own before using it):

```postscript
FcPresets /Dusk << /SunElev 2 /SunAzim 70 /Exposure 2.4 >> put
```

A few settings override each other when both exist: a number in `SunElev`
beats `SunDir`, and `CloudLayers` beats `CloudLo` and `CloudHi`. So a preset
skips `SunDir`, `SunElev` and `SunAzim` when the piece set `SunDir` (a null
`SunElev` does not count), and the other way round; the same for the moon's
three; and `CloudLayers` when the piece set `CloudLo` or `CloudHi`, and the
other way round. The piece wins, as with every other setting. `Threshold` and
`CoverAmp` are not rivals (a layer list reads its own values), so they are
set either way. `/CloudLayers null` in the piece keeps its single layer. Don't put rivals in one dictionary
(`SunDir` and `SunElev` in a scene): the order a dictionary is read in is
not defined, so only one of them survives.

`/Dawn`, `/Noon` and `/Night` set only the sun (and moon) and rely on the sky
model for the colours, so they need `SkyModel` on: don't combine them with
`/Evening` or a piece's `Zenith` or `Horizon` (the sun would move but the
blend sky stays). A preset that sets `Zenith` or `Horizon` (`/Evening`)
turns `SkyModel` off, like any piece that sets them. Settings are made with
`def` in the current dictionary, so apply presets outside any `begin`/`end`.

### Scene files

A scene file holds one dictionary and `fc-settings`:

```postscript
<<
    /Presets [ /Evening /Clear /Alpine ]
    /Seed 5  /Pitch 2  /Yaw -27  /HFov 55
    /WaterRise 1.4
>> fc-settings
```

`scenes/scene.ps` is a driver that loads `lib/fc_presets.ps`, the scene
named by `Scene`, and the landscape, so one scene renders at any size or crop
with no piece to edit:

```
scripts/render.sh -D "Scene=(scenes/evening_lake.ps)" scenes/scene.ps
DPI=144 scripts/render.sh -D "Scene=(scenes/evening_lake.ps)" -D "Crop=[0.3 0.5 0.6 0.8]" scenes/scene.ps
```

`scenes/evening_lake.ps` renders pixel for pixel the same as
`gallery/evening_lake.ps` (which is `[ /Evening /Clear /Alpine ]` plus the
camera and the lake).

### The presets

Presets set only the values in the tables; everything else keeps the
library's defaults. A preset is a group on one axis, so combine one from each:
time of day, weather, terrain, and (optionally) season.

| Time of day | Sets | Look |
|---|---|---|
| `/Dawn` | `SunElev` 6, `SunAzim` −55, `Exposure` 1.9 | Sky model; low sun ahead and to the left |
| `/Noon` | `SunElev` 58, `SunAzim` 25 | Sky model; high sun |
| `/Evening` | `SunDir` [0.50 0.13 −0.55], `SunCol`, `Zenith`, `Horizon`, `SkyAmb`, `Exposure` 1.9 | The hand-picked blend sky of `gallery/evening_lake.ps` (so `SkyModel` is off); a low sun behind the camera on the right |
| `/Night` | `SunElev` −20, `MoonElev` 32, `MoonAzim` 30, `Exposure` 4 | Sky model; a moon and stars |

| Weather | Sets | Look |
|---|---|---|
| `/Clear` | `CloudLo` 62, `CloudHi` 84, `Threshold` 0.60, `CoverAmp` 0.5, `HazeDist` 520 | The single cloud layer above the peaks, in a few groups |
| `/Overcast` | `CloudLayers` `[ Stratus, Lo 64, Hi 78 ]`, `HazeDist` 450 | A flat grey sheet over the peaks |
| `/Storm` | `CloudLayers` `[ Nimbostratus, Lo 64, Hi 108 ]`, `HazeDist` 300 | Dark thick cloud with rain below it; thick air |

| Terrain | Sets | Look |
|---|---|---|
| `/Alpine` | `TreesOn` true, `SnowLine` 25 | The library's range (`TerrH` 52) with a forest and snow above 33 on average |
| `/Foothills` | `TreesOn` true, `TerrH` 28, `TerrScale` 0.014, `SnowLine` 80, `FsLine` 40 | Lower, busier hills, forested to the top, no snow |
| `/Mesa` | `TerrH` 34, `TerrScale` 0.016, `DetailAmp` 0.10, `SnowLine` 100, `Rock`, `Rock2`, `Scree` (reds), `TreeLine` −1000 | Smoother ground in red strata, no snow, and no forest unless a piece sets `TreesOn` (the preset only turns the painted forest off). It does not flatten the summits: the terrain function has no plateau term yet |

| Season | Sets | Look |
|---|---|---|
| `/Spring` | `SnowLine` 25, `FsAutumn` 0 | |
| `/Summer` | `SnowLine` 27, `FsAutumn` 0 | `gallery/alpine_forest.ps`'s early summer |
| `/Autumn` | `SnowLine` 24, `FsAutumn` 1 | Turns the larches gold and the broadleaves, but only if the stand has them: the default `FsMix [1]` is all spruce, which ignores it, so also set `FsMix` (experimental) |
| `/Winter` | `SnowLine` −8, `FsAutumn` 0 | Snow on every slope that is not too steep |

| Tone and grade | Sets | Look |
|---|---|---|
| `/Filmic` | `ToneCurve` /ACES | The filmic tone curve |
| `/Classic` | `ToneCurve` /Exp | The original exponential curve and 2.2 power |
| `/Warm` | `GradeTemp` 0.4 | Warmer white balance |
| `/Cool` | `GradeTemp` −0.4 | Cooler white balance |
| `/Muted` | `GradeSat` 0.75, `GradeLift` 0.006 | Less saturated, slightly lifted blacks |
| `/Matte` | `GradeLift` 0.02, `GradeSat` 0.9 | Milky, lifted blacks |
| `/SplitTone` | `GradeSplit` 0.5 | Teal shadows, warm highlights |
| `/CoolMuted` | `GradeTemp` −0.3, `GradeSat` 0.72, `GradeLift` 0.006, `GradeSplit` 0.3 | Muted and cool, for an overcast Pacific Northwest look (#40) |
| `/Vignette` | `Vignette` 0.3 | Darker edges and corners; deliberately subtle (edges at 70%), raise `Vignette` for more |

| Coast | Sets | Look |
|---|---|---|
| `/Tropical` | `SunElev` 62, clear air (`HazeDist` 1500), trade-wind `/Cumulus` (60–92, scattered), `/ACES`, `Ocean` with turquoise shallows and pale sand (`SeaShallow`, `SeaDepth` 2.4, `SandCol`, `CoastSand`, no cobbles or stacks), a reef the surf breaks on (`CoastReef` [60 30 0.15]), palms (`FsMix` all palm, `FsCell` 2.2, no dead trees) | A tropical island at midday: `gallery/tropical_island.ps` |
| `/PNWCoast` | `SunElev` 30 under two `/Stratus` layers (sea fog 4–20 thickened at the coast by `fc-coast-fog`, overcast 34–46), thick low haze, a cool muted grade (`GradeTemp` −0.4, `GradeSat` 0.62), a grey-green `Ocean`, dark basalt (`Rock`, `Rock2`, `Scree`), grey sand and cobble (`CoastCobbles` 0.5 plus `CoastCobbleK` 1.2 under cliffs), more stacks and surf rocks, driftwood (`CoastDrift` 1), Sitka spruce and red cedar (`FsMix`) to the cliff tops (`FsLine` 90) | The Pacific Northwest coast in fog: `gallery/pnw_coast.ps` |

Each is a whole look for a map with `MapSea` 0 (the fog layer's heights
assume it); the piece brings the map, the camera and `SunAzim`. Pick the
sun's azimuth so the view doesn't look into a low sun over open sea (the
sea toward a low sun reads cream).

Grade presets combine with each other (list the one whose values should win
first: `[ /CoolMuted /Vignette ]`) and with the other groups. See the colour
grade section below for what each setting does.

`/Alpine` sets a snow line, so a season listed *before* it wins. The cloud
heights in `/Clear`, `/Overcast` and `/Storm` assume the standard terrain
(`TerrTop` 59); with a taller `TerrH`, raise them.

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
| `WaterY` | null | A number puts a lake (or sea) surface at that height everywhere the ground is lower (`lib/fc_water.ps`). | null, −0.5 |
| `WaterRise` | null | A number sets `WaterY` this far above the ground under the camera (worked out during setup, from the terrain before erosion). | 1.4 |
| `Rivers` | false | Carve rivers along the erosion map's drainage and fill them (needs `Erode`). Adds the flow pass to the bake and the river bake after it. | false, true |
| `MapWater` | false | Fill the terrain map's `/lake` features (`MapOn`) with water at their levels, each over its polygon and shore band. | true |

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
wrapped and then redefined (`fc_water`'s `fc-landscape-hit`, which calls the
original as `fc-water-dry-hit`) gets a new row, and the old one stays as
`fc-landscape-hit#1`, so a hook and what it calls aren't mixed. Only
procedures defined in `userdict` are wrapped. How to read the
table is in `docs/techniques.html`, section 16.

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

The sun's direction is the time of day. With the sky model on (the
default), the sun, sky and ambient colours all follow from it: a piece
sets `SunDir` or `SunElev`/`SunAzim` and nothing else, and gets noon,
golden hour, alpenglow, dusk or a moonlit night. Any colour a piece does
set is kept. A piece that sets `Zenith` or `Horizon` gets the older
blend sky (`SkyModel` false), exactly as before.

| Setting | Default | What it does | Used |
|---|---|---|---|
| `SunDir` | [−0.55 0.42 0.72] | Direction *toward* the sun (x right, y up, z ahead before yaw). Normalised on load. Low `y` gives long shadows; negative `z` puts the sun behind the camera. | [−0.62 0.40 0.62], [0.55 0.50 0.45], [0.50 0.13 −0.55] |
| `SunElev`, `SunAzim` | null, 0 | The sun by angles instead: elevation above the horizon and azimuth (0 is +z, ahead before `Yaw`; 90 is +x, to the right), degrees. A number in `SunElev` overrides `SunDir`. | −5 … 55 (the sweep) |
| `SkyModel` | true unless the piece set `Zenith` or `Horizon` | The scattering sky below. false is the zenith-to-horizon blend with three sun lobes. | true, false |
| `SunCol` | derived | Sunlight colour at the camera (sRGB if the piece sets it). Derived: white sunlight (`SunPower`) through the air along the sun's path, so it reddens as the sun drops. | [1.00 0.72 0.48] (evening lake) |
| `Zenith` | derived | Sky colour overhead. Derived from the model; setting it turns `SkyModel` off. | [0.24 0.34 0.58] |
| `Horizon` | derived | Sky colour at the horizon. Derived from the model (90° round from the sun); setting it turns `SkyModel` off. | [0.94 0.74 0.58] |
| `SunPower` | 1.1 | Sunlight above the atmosphere, white. | 1.1 |
| `SunDisc` | 40 | Brightness of the sun's (and moon's) disc in the sky. | 40 |
| `SkyGain` | 12.7 | The scattered sky's brightness relative to the sun (both are scaled by `SunPower`). | 12.7 |
| `SkySat` | 1.2 | Saturation of the sky's colour about its luminance; 1 is the model as computed. | 1.2 |
| `Turbidity` | 1 | Aerosol amount: 1 is a clear mountain day. More whitens the horizon and widens the glow round the sun. | 1 |
| `MultiScatter` | 1 | Light scattered more than once (the sky's mean radiance scattered again): brightens and blues the horizon. 0 for single scattering. | 1 |
| `AmbGain` | 2.1 | Derived `SkyAmb` is this times the sky's cosine-weighted mean, pulled 65% toward grey (sky light reaches the ground after far more scattering than the model follows, and a bluer ambient turned the alpine forest teal); `AmbTop` and `AmbBot` are 1.2 and 0.31 of that. Pieces that set any of the three keep theirs. | 2.1 |
| `MoonDir`, `MoonElev`, `MoonAzim` | null, null, 0 | A moon, by vector or by angles. Null means none. It lights the sky, and once it outshines the sun at the camera it takes over `SunDir` and `SunCol` for the ground and clouds. | 20/60, 25/−40, 45/10 |
| `MoonLight` | 0.12 | Moonlight as a fraction of `SunPower` (a day-for-night convention; raise `Exposure` too). | 0.12 |
| `MoonCol` | [0.60 0.76 1.00] | Moonlight colour above the air, sRGB: blue-grey, as night reads to the eye. | |
| `Stars` | 1 | Star brightness, where the sky is dark enough. 0 for none. | 1 |
| `Exposure` | 1.6 | Brightness before the tone curve. Means the same with either `ToneCurve`: mid-tones land in the same place. | 1.6, 1.9, 3, 4 (night) |
| `ToneCurve` | /Exp | The tone curve, chosen as `fc_sky.ps` loads. `/Exp`: `1 − exp(−Exposure·L)` per channel, then a 2.2 power (no toe, so shadows stay light). `/ACES`: a filmic curve (Hill's fit of ACES) with a toe and a long shoulder, then the exact sRGB transfer function: deeper, more colourful shadows and softer highlights. Also the `/Filmic` and `/Classic` presets. | /Exp, /ACES |
| `HazeDist` | 520 | Distance at which haze reaches 63% at height 0. Smaller means thicker air. | 400, 520, 650 |
| `HazeH` | 45 | Height over which the haze thins by a factor of e. | 45 |
| `HazeChroma` | 1 with `SkyModel`, else 0 | How far the haze fades each channel at its own rate. 1 takes the haze to be the model's Rayleigh air plus enough neutral aerosol to reach `HazeDist` in green, so blue fades a little sooner and red a little later (about 15% and 4% at `HazeDist` 650: a haze that thick is mostly aerosol); 0 fades every channel over `HazeDist`; 2 or 3 exaggerates the blue distance. `HazeDist` is the green channel's distance. | 0, 1 |

`fc-sun-update` recomputes everything derived after a piece changes
`SunDir`, `SunElev` or the moon after loading.

## Colour grade (`fc_grade.ps`)

A grade in linear light, applied by the `fc-landscape-grade` hook just
before the tone curve. `fc_landscape.ps` loads `lib/fc_grade.ps` only when
one of `GradeTemp`, `GradeSat`, `GradeSplit`, `GradeLift` or `Vignette` is
away from its neutral value, so a piece without a grade renders exactly as
before. The steps run in this order: white balance, split toning,
saturation, vignette, lift. The grade presets below set these.

| Setting | Default | What it does | Used |
|---|---|---|---|
| `GradeTemp` | 0 | White balance: above 0 warmer (red ×(1 + 0.15·t), green ×(1 + 0.02·t), blue ×(1 − 0.15·t)), below 0 cooler. | −0.4 … 0.4 |
| `GradeSat` | 1 | Saturation about the luminance (Rec. 709 weights); below 1 mutes. | 0.72, 0.75, 0.9 |
| `GradeSplit` | 0 | Split toning strength, 0–1: shadows lean toward `GradeShadows`, highlights toward `GradeHighlights`, blended by luminance about `GradePivot`. | 0.3, 0.5 |
| `GradeShadows` | [0.32 0.45 0.52] | Shadow tint, sRGB; only its hue counts (it is scaled to luminance 1). Teal by default. | |
| `GradeHighlights` | [0.62 0.52 0.40] | Highlight tint, sRGB, the same way. Warm by default. | |
| `GradePivot` | 0.25 | Linear luminance at which a pixel is half shadow, half highlight. | |
| `GradeLift` | 0 | Light added to every channel (a veil, like lens flare): lifted, milky blacks. 0.01 is gentle. | 0.006, 0.02 |
| `Vignette` | 0 | Darkening toward the frame's edge, following the ray's angle off the view axis as cos⁴: the left and right edges get 1 − `Vignette`, the corners a little darker. Independent of resolution and crop. | 0.3 |

The vignette's view axis is taken as `fc_grade.ps` loads; a piece that
changes `Pitch`, `Yaw` or `HFov` afterwards calls `fc-camera-update` and then
`fc-grade-update`.

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
| `AmbTop`, `AmbBot` | derived (or [0.62 0.72 0.88], [0.34 0.38 0.48] without `SkyModel`) | Ambient light at the layer's top and bottom (sRGB). With the sky model, 1.2 and 0.31 of the derived `SkyAmb` unless the piece sets them. | |
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
| `Shape` | null | A procedure `x y z oct → dd` (`oct`: the octaves the sample wants, fewer with distance) added to the density before the gain: a positive value adds cloud, a negative one cuts it. Only called inside the band (`Lo < y < Hi`), so a placed object needs a band tall enough to hold it. For placed objects such as a cumulonimbus (#15). Costs a call per sample. It is called before the noise: a value of −1 or less means nothing is there, and the noise is skipped (keep the threshold and coverage such that the noise can't lift −1 above 0). |
| `RainShafts` | 0 | Above 0: the rain is broken into shafts by 2-D noise with this many cells per unit (the storm uses 0.06); 0 is the old solid curtain. |
| `Bounds` | null | `[x0 z0 x1 z1]`, world x and z (the camera stands at x = z = 0): the layer is empty outside this box, and each ray marches only the part of the band inside it, with all its `Steps`. For a placed object, so a tall band doesn't make every sky ray march its whole height. Rays that miss the box draw no jitter (`fc-rnd`), so setting it shifts the global random stream for every later draw, not only that layer's grain. |
| `RainMask` | null | A procedure `x z → 0..1` multiplying the rain (after `RainShafts`). A layer with one also lights its rain with `AmbBot`, as under the base, rather than the ambient a quarter of the way up. The storm uses it to fade the rain toward the edge of the tower's foot. |
| `Probes` | 1 | A whole number, at least 1: density probes per layer for the ground's cloud shadow and `fc-cloud-sky`, spread evenly over the band above the point. 1 keeps the old single probe at the middle; a tall object needs more (the storm uses 3) or its anvil casts no shadow. |
| `LightDepth` | null | A procedure `x y z → od`: optical depth toward the sun added to the two short sun probes', for a placed object's shadow on itself at a larger scale than the probes reach (#15). Called once per lit sample. |

The Base column is where every preset starts (the gallery pieces' layer,
value noise); each preset's own values are in `FcClPresets` in
`lib/fc_clouds.ps`.

`x y z fc-cloud-shadow` gives the sunlight that reaches a point through
every layer above it (`Probes` density probes per layer, one by default; no march), for ground
shadows and sun shafts. `fc_terrain`'s `CloudShadowsOn` uses it with a
layer list; with `CloudLayers` null it keeps its old single probe at the
middle of `CloudLo`–`CloudHi`. Only the direct sun is shaded there.

`x y z fc-cloud-sky` gives how much of the sky a point sees through the
clouds overhead, 0..1: `Probes` probes straight up through every layer
above it. `fc_terrain`'s `CloudSkyDim` dims the ground's sky light and
bounce by it (off by default, so existing pieces are unchanged).

## Storm (`fc_storm.ps`, #15)

A cumulonimbus placed in the scene like a mountain. Load it *after*
`lib/fc_landscape.ps`: it builds a storm layer from these settings and puts
it in front of `CloudLayers`. Set them, like every setting, before the run lines.

- The storm's band runs from `StormBase` to `StormTop + 1.2 DomeR + 1`, rain
  below it to `StormBase − StormRain`. Other layers must lie wholly above
  it: layers composite by height, so they can't share its heights.
- With `CloudLayers` null the storm *replaces* the default single cloud
  layer: the sky holds only the storm.
- The scene presets `/Storm` and `/Overcast` (`lib/fc_presets.ps`) set
  low layers that overlap the storm's band, so combining them with
  `fc_storm.ps` stops the job with `CloudLayers-overlap`.
- `CloudSkyDim` dims the ground's sky light, not the tree canopy
  (`fc_trees.ps` shades crowns itself), so the piece uses the painted forest.

| Setting | Default | Meaning | Storm |
|---|---|---|---|
| `StormDist` | 420 | Ground distance from the camera to the tower's foot. | 460 |
| `StormAzim` | 0 | Its bearing in degrees: 0 is +z (straight ahead at `Yaw` 0), 90 is +x. | −5 |
| `StormBase` | 70 | The flat, dark base (keep it above the peaks in front, or it hides). | |
| `StormTop` | 180 | The anvil's flat top. | |
| `StormR` | 55 | Tower radius at the base. | |
| `StormFlare` | 0.3 | The tower is this much wider at the top. | |
| `StormLean` | 0.15 | The tower leans downwind this much per unit height. | |
| `StormWind` | 0 | Where the anvil spreads, degrees from +x (as a layer's `Wind`). | 200 |
| `AnvilBot` | 152 | Where the anvil starts to spread from the tower; it widens with height up to the top. | |
| `AnvilR` | 170 | How far it reaches downwind (upwind: a third of that). | |
| `AnvilW` | 0.4 | Its half-width across the wind, as a fraction of its reach. | |
| `DomeR` | 34 | Radius of the overshooting dome, centred 0.2 `DomeR` above the tower top; 0 for none. | |
| `StormEdge` | 2 | Gain of the envelope against the noise: higher is a tighter, smoother outline, lower more ragged. | |
| `AnvilEdge` | 4 | The anvil's gain relative to the tower's (smoother). | |
| `StormShade` | 0.25 | Optical depth per unit length of envelope toward the sun (the layer's `LightDepth`): how dark the far side and the base get. | |
| `StormShadeN`, `StormShadeStep` | 5, 16 | Its steps toward the sun, starting past the noise's two probes. | |
| `Virga` | 0.3 | Strength of the streaks hanging under the anvil; 0 for none. | |
| `VirgaLen` | 26 | How far they hang. | |
| `StormRain` | 84 | Rain shafts this far below the base (the layer's `Rain`). | |
| `StormRainDens` | 0.3 | Their density, as a fraction of the cloud's; the rain is masked by `fc-storm-rainmask` (fades toward the edge of the tower's foot, broad shafts streaked by a finer noise). | |
| `StormGloom` | 0 | Above 0: the air under the storm is in shade. Rays crossing a column of radius `StormGloomR · StormR` below the base fade toward `StormGloomCol`, by this extinction per unit length, weighted by depth below the base and closeness to the axis (it wraps `fc-landscape-grade`). | 0.03 |
| `StormGloomR` | 2 | That column's radius, in `StormR`. | 2.2 |
| `StormGloomCol` | [0.10 0.11 0.13] | The shaded air's colour (sRGB). | |
| `StormLayer` | `<< >>` | Overrides for the storm layer's keys (the cloud-layer keys above), e.g. `<< /Steps 160 >>`. | |

`x y z oct fc-storm-shape` is the layer's `Shape`; `fc-storm-layer` builds
the layer dict, `fc-storm-bounds` its `Bounds`.

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
| `MapGrid` | null | A painted mask: an array of rows, the far (high `z`) row first, each a string of `MapChars` or an array of numbers 0–1, stretched over `MapRect`. 1 grows full mountains, 0 leaves valley floor. Every row must be the same length (`fc-map-bake` stops with a rangecheck otherwise). The grid sets only the mask (`MapLiftGrid` paints elevation), and doesn't pin: its mountains keep the usual warp, so they land only roughly where painted. | |
| `MapChars` | `( .:-=+*#%@)` | The characters a string row may use, from 0 to 1. | |
| `MapFeatures` | [ ] | Features, each `[ /kind numbers… ]` (below). Heights and levels are world `y`. | |
| `MapBackground` | [0 0] | `[lift mask]` outside the rectangle, and inside it where no feature reaches. With a `MapGrid` the grid replaces the mask over the whole rectangle (its lift still applies). | [5 0.04] |
| `MapFeather` | 120 | Blend from the table to the background past `MapRect`'s edge. 0 or less gives a hard edge. | |
| `MapPlanRect` | null | The area `fc-map-plan` draws (null: `MapRect`). | [−800 −560 800 440] |
| `MapPlanN` | 150 | Hillshade samples across the plan. | 320 |
| `MapPlanOct` | 5 | Terrain octaves in the plan. | 5 |
| `MapLiftGrid` | null | A painted ground height (#39), rows like `MapGrid`'s (its own size), values 0–1 standing for `MapLiftRange`. It replaces `MapBackground`'s lift inside the rectangle, so low land (a beach plain, an atoll) can be painted without growing mountains: with mask 0 the ground stands at the painted height, give or take the valley-floor detail. | `spikes/coast.ps` |
| `MapLiftRange` | [−10 30] | `lo hi`: the world `y` that `MapLiftGrid`'s 0 and 1 stand for. | [−20 30] |
| `MapVolcMask` | 0.22 | A `/volcano`'s ridged mask on its flanks (gullies); its lift is lowered to make room for them. | |
| `MapSea` | null | Sea level, world `y` (#39). A number loads `lib/fc_coast.ps` (next section) and, when the piece sets no `WaterY`, puts the water's plane there. | 0 |

Features (applied peaks and ridges first, the tallest winning, then
valleys, then lakes, whatever their order in the list):

| Feature | What it does |
|---|---|
| `[ /peak height spread x z ]` | Raises the mask in a round bump of radius `spread`, aimed so the ridge crest it grows stands about `height` high (within about 15%: the ridges' own height varies). Measured with `spikes/map_pins.ps`, the summit lands 10–32 units from `x z` over four seeds. |
| `[ /ridge height spread x0 z0 x1 z1 … ]` | The same along a polyline. |
| `[ /valley depth width x0 z0 x1 z1 … ]` | Carves: the mask falls to 0 along the polyline and the ground drops `depth`. |
| `[ /lake level depth shore x0 z0 x1 z1 x2 z2 … ]` | A closed polygon: inside it the mask is 0 and the bed sits `depth` below `level`, blending to the surroundings over `shore` units centred on the drawn edge, so the waterline lands near the line. `MapWater` true fills it with the library's water at `level` (`gallery/charted_range.ps`). |
| `[ /volcano height radius x z ]` | An island preset (#39): a cone of lift with concave flanks (`(1 − d/radius)^1.5`) toward a summit about `height` high, a small crater at the top, and `MapVolcMask` of ridged mask on the flanks for gullies. Applied with the peaks; lift only ever rises. Add `CoastReef` for a fringing reef. |
| `[ /atoll height radius width x z ]` | An island preset: a ring of low land `height` high (world `y`), `radius` from `x z`, falling off over `width` either side; the lagoon inside stays sea. With `CoastWobble` the ring breaks into islets where it dips under the water. |
| `[ /cliff height spread x0 z0 x1 z1 … ]` | With `MapSea`: along the polyline (falling off over `spread`), the sea has cut the land back to where it stands `height` above the water, so the coast there is a cliff about that high (shorter where the land isn't that high). |
| `[ /stack height radius x z ]` | A sea stack: a steep column `radius` wide with its top at `height` (world `y`), drawn per point by `fc_coast.ps` (too narrow for the table). |

Heights have two ceilings. A peak or ridge asks for a mask of at most 1,
so heights above about `lift + TerrBase + 1.02 TerrH` (47 with the
defaults and no lift) all give the tallest ridges the noise makes there.
And the march stops above `TerrTop` (`TerrBase + 1.25 TerrH`, 59): the
ground can reach about `lift + TerrBase + 1.16 TerrH`, so a lift over
about 5 can cut the tops flat. Raise `TerrH` for taller maps.

With any of #39's extras (`MapLiftGrid`, `MapSea`, a `/volcano`, `/atoll`
or `/stack`) the bake raises `TerrTop` over the tallest lift (and the
stacks), so a tall island isn't cut flat. Older maps keep the old ceiling,
so their pixels don't change.

`x z fc-map-water` (map coordinates) gives the water level the map puts
at a point, or −1000: the higher of `MapSea` and the level of any `/lake`
whose polygon or shore band holds it.

A lake's bed is flat only at the scale of the map: the valley-floor detail
(about ±`0.2 DetailAmp TerrH`, ±1.7 units with the defaults) stays, so a
lake shallower than that shows rocks and islands of bed.

## The coast (`fc_coast.ps`, with `MapSea`)

The map's bake measures each texel's signed distance to the coastline
(land positive): land is where the map's noise-free height (its lift, plus
`0.64 TerrH` per unit of mask) stands above `MapSea`, or above `MapSea +
height` near a `/cliff`. `fc-height-proc` then reshapes the ground near
the coast (see `docs/techniques.html#coast`): a cliff face cuts back high
land, low ground is pressed onto a beach-and-shallows profile, and stacks
and rocks stand offshore. Set `CamHeight`: over the sea, `CamAbove`
measures from the sea floor. Leave `WaterY` and `WaterRise` unset: the
water then sits at `MapSea`; a plane anywhere else detaches it from the
shore profile (`fc_coast.ps` prints a warning). Erosion's droplets stop when they reach the
sea (their load is lost).

| Setting | Default | What it does | Used |
|---|---|---|---|
| `CoastSlope` | 0.12 | Gradient of the beach face and the shallows at the waterline. | |
| `CoastDepth` | 14 | The deep sea floor, below `MapSea`; the shallows reach it over about `3 CoastDepth / CoastSlope` units. | |
| `CoastBerm` | 1.2 | The berm: the beach's flat top above `MapSea`. | |
| `CoastFlat` | 1.5 | Low ground within this of the beach profile is pressed flat onto it ... | |
| `CoastBeachW` | 80 | ... within this far of the water (fading out over its outer half). | |
| `CoastCliff` | 3.5 | Cliff faces' gradient (rise per unit across). | |
| `CoastCliffLo`, `CoastCliffHi` | 4, 12 | Over this range of the nearest land's height above the sea, a shore turns from low to cliffed: benches and stacks need it, reefs and sand avoid it. | |
| `CoastWobble` | 18 | The coastline wanders this far either way (two noise octaves), into coves and points. | |
| `CoastWobbleScale` | 0.012 | 1 / the wobble's wavelength. | |
| `CoastRough` | 1.2 | Fine roughness of cliff faces, in units across (near detail only). | |
| `CoastBench` | [8 0.3] | `width depth`: the wave-cut bench at a cliff's foot, which stands in for the notch a heightfield can't undercut. | |
| `CoastStacks` | 0.5 | Stacks off cliffed shores, 0–1 (more and wider). 0: none. | |
| `CoastStackH` | 0.75 | Their height, as a fraction of the nearby cliffs'. | |
| `CoastStackOut` | 45 | How far offshore they stand (from 10 out). | |
| `CoastStackScale` | 0.045 | 1 / their spacing. | |
| `CoastRocks` | 0.5 | Rocks in the surf, from 14 units out to the waterline, 0–1. 0: none. | |
| `CoastReef` | null | `[out width depth]`: a patchy reef `width` wide, its inshore edge `out` offshore, its top about `depth` under the water; off low shores only. | [70 50 0.5] |
| `CoastSand`, `CoastCobble` | sRGB | The beach's colours; cobbles are mottled. | |
| `CoastCobbles` | 0.3 | How much of the beaches is cobble, 0–1. | |
| `CoastSandW` | 40 | How far inland the beach material reaches. | |
| `CoastCobbleK` | 0 | More cobble under cliffs: added to `CoastCobbles` in proportion to how cliffed the shore is (#40), so coves under cliffs are cobble and open beaches sand. | 1.2 (`/PNWCoast`) |
| `CoastDrift` | 0 | Driftwood along the top of the beach, 0–1 (#40): logs 0.8–1.8 units long and 0.1–0.2 across, lying at any angle, a third sunk in the sand, one candidate per 2.5-unit cell kept by noise (half of them at 1) (more with a higher value; the random stream is untouched). A heightfield bump, so near detail only (more than five terrain octaves), on low shores only (cliffedness under 0.5). | 1 (`/PNWCoast`) |
| `CoastDriftBand` | [8 24] | `lo hi`: the band of (wobbled) distance from the water the logs lie in: the high-tide line at the back of the beach. | |
| `CoastDriftCol` | [0.60 0.57 0.52] | Bleached wood, sRGB, darker along the grain. | |
| `CoastFog` | [1.2 40] | `add reach` for `fc-coast-fog` (below). | |

`x y z oct fc-coast-fog dd` is a cloud layer's `Shape` (see Cloud layers):
it adds `add` to the layer's density at the coastline (by `fc-coast-dist`,
over land or water), fading to nothing `reach` away, so fog lies along the
shore and fills coves (all of a cove is near some shore) while the open sea
and the land inland stay clearer. `/PNWCoast` uses it on a low `/Stratus`.

## Terrain surface and light (`fc_terrain.ps`)

| Setting | Default | What it does | Used |
|---|---|---|---|
| `SnowLine` | 23 | Snow height: it fades in from 8 below to 8 above `SnowLine + 16·v`, where `v` is a broad 0–1 noise (so about `SnowLine + 8` on average). Snow also needs flat enough ground, and favours hollows and faces turned from the sun. | 23, 25, 27 |
| `TreeLine` | 7 | The *painted* forest colour on low gentle ground (no geometry). `TreesOn` sets it to −1000; real trees use `FsLine`. | 7, −1000 |
| `Rock`, `Rock2` | [0.42 0.41 0.39], [0.52 0.50 0.46] | Rock colours, mixed by strata and patches. | |
| `Scree` | [0.50 0.49 0.47] | Gentler slopes below cliffs. | |
| `Snow` | [0.94 0.95 0.97] | | |
| `Forest` | [0.20 0.26 0.18] | Painted-forest colour (see `TreeLine`). | |
| `SkyAmb` | derived (or [0.58 0.66 0.80] without `SkyModel`) | Sky light on the ground and trees. With the sky model, the sky's mean times `AmbGain` unless the piece sets it. | [0.52 0.56 0.70] (evening lake) |
| `SkyLight` | 1.15 | Strength of that sky light. | 1.15 |
| `Bounce` | [0.40 0.36 0.30] | Warm light reflected up from the ground below. | |
| `BumpAmp` | 0.55 | How strongly steep rock breaks into lit and shaded facets. | 0, 0.55 |
| `ShadowsOn` | true | Terrain casts shadows (a march toward the sun per lit pixel). | true |
| `CloudShadowsOn` | true | Clouds shade the ground. | true |
| `CloudSkyDim` | 0 | Above 0: clouds overhead (`fc-cloud-sky`) dim the ground's sky light and warm bounce, by this fraction of what they block, so the ground under a storm is darker and cooler. Costs `Probes` density probes per layer per ground pixel. | 0.75 (storm) |
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
| `FsTiers` | 9 | Branch whorls per spruce crown (other species: `FsSpecies`). | 9 |
| `FsDroop` | 0.30 | How far each spruce whorl's tips hang below its base, as a fraction of tree height. | 0.30 |
| `FsEnv` | 1.0 | Spruce crown outline: 1 is a straight cone, more is a slimmer spire. | 1.0 |

`FsEnv`, `FsDroop` and `FsTiers` are copied into the spruce dict of `FsSpecies` when `lib/fc_trees.ps` loads, so set them before the `run` line, like every other setting; setting them afterwards has no effect.

| `FsTrunks` | true | Trunks, and crowns lifted off the ground where the lower branches have died (dense stands; the species' `base` and `baseDense`). Only where a crown is over about 4 px wide. false keeps every crown on the ground, every tree alive (snags and logs need trunks), near spruce outlines as smooth as before: the look before #25. | true |
| `FsSnag` | 0.03 | Fraction of the trees that are dead snags: a bare, broken-off trunk. Only drawn where trunks are. | 0.03 |
| `FsFallen` | 0.02 | Fraction lying on the ground as logs. | 0.02 |
| `FsMix` | [1] | **Experimental.** Weights of the species in `FsSpecies`, in order: spruce, fir, pine, larch, broadleaf, Sitka spruce, red cedar, palm (zero weights skip a species: `/PNWCoast` has `[0 0 0 0 0 0.6 0.4]`). `[1]` is a pure spruce forest (the default look). Broadleaves only grow well below the treeline, so their share is smaller higher up. A mix with pine and broadleaf (`[0.45 0.2 0.15 0.1 0.1]`) lost blind pairwise to the spruce stand on the current sky (blocky pine and broadleaf crowns, pole-like trunks; `docs/prs/25-trees-species/`); work continues in #53. | [1] |
| `FsAutumn` | 0 | Season: at 1 the larches are gold and the broadleaves turned (per-tree, some earlier than others). Evergreens ignore it. | 0 |
| `FsSpecies` | (eight dicts) | The species table (pine and broadleaf are experimental, see `FsMix` and #53; Sitka spruce, western red cedar and the palm are #40's): one dict per species with its crown profile (`env droop tiers`, and optionally `rag` and `lobes`, how ragged the outline is and how many lobes it has round the trunk, both 1 for spruce), `rad` (crown radius / height), `hmul` (height), `base` and `baseDense` (crown base / height in the open and in a dense stand), `trunk` (radius / height), colours `alb alb2 shade autumn bark` (sRGB; `null` means the spruce setting) and an altitude band `lo hi` (height relative to the treeline). Define a whole table to add a species; the pieces' `FsMix` then needs a weight for it. Optional `form`: `/palm` makes a palm instead of a conifer (#40): `fronds` drooping fronds (11) on a curved trunk leaning `lean` of its height (0.14, varied per tree), `droop` how far the fronds hang (1 is the tips about 0.65 crown radius under the crown's centre), `rad` the crown radius; `env`, `tiers`, `base` and `baseDense` are unused, and palms are never dead. A palm needs a larger `FsCell` (about 2.2): its lean and crown together stay within 0.55 cell, which caps the crown. | |
| `FsBark` | [0.21 0.16 0.12] | Spruce bark (other species carry their own). | |
| `FsShoreH` | 1.5 | On a coast (`lib/fc_coast.ps` loaded): no trees on low ground (under `FsShoreH` above the beach's berm, `MapSea + CoastBerm`) within `CoastSandW` of the water, fading in over its outer half; higher ground (cliff tops, stacks) keeps its trees however near the sea. 0 turns the gate off (#40). | 1.5 |
| `FsSnagCol` | [0.40 0.36 0.31] | Weathered dead wood: snags, and the sides of logs. | |
| `FsLogCol` | [0.30 0.27 0.20] | The mossy top of a fallen trunk. | |
| `FsN` | 384 | Density map resolution. | 384 |
| `FsSize`, `FsDist` | 700, 300 | Map size and its distance ahead. | |
| `FsAlb`, `FsAlb2` | [0.27 0.31 0.15], [0.22 0.29 0.21] | Sunlit needles, per-tree mix of olive and bluer spruce. | |
| `FsShade` | [0.15 0.22 0.21] | Needles lit only by the sky. | |
| `FsFloor` | [0.17 0.15 0.11] | Needle litter under the trees. | |
| `FsGrass`, `FsGrass2` | [0.36 0.41 0.20], [0.50 0.47 0.29] | Meadow colours, mixed by noise. | |

## Water (`fc_water.ps`, with `WaterY`, `WaterRise`, `Rivers` or `MapWater`)

`fc_landscape.ps` loads it after its hooks and wraps `fc-landscape-hit` and
`fc-landscape-surface`; it also chains onto `fc-terrain-material` (the
shore) and, with trees, `fc-forest-dens` (no trees in the water or within
about 0.3 above it). With none of the four settings on, it isn't loaded and
nothing changes. The surface is built for #38's sea to extend: its normal
and its own colour are hooks (`fc-water-normal`, `fc-water-colour`, below).

| Setting | Default | What it does | Used |
|---|---|---|---|
| `WaterCol` | [0.10 0.15 0.16] | The water's own colour seen straight down (sRGB), lit by `SkyAmb`. | default |
| `WaterClear` | 0.6 | Path length through the water over which the bed fades to `WaterCol` (1/e), world units. Shallows show the bed; 0 makes the water opaque. | 0.6 |
| `RippleAmp` | 0.035 | Ripple slope. | 0.035 |
| `RippleScale` | 2 | 1 / ripple wavelength (2 is 5 m). Two octaves; each fades out as it nears three pixels, and its slope then tilts the mean normal toward the camera, so far rough water shows more sky. | 2 |
| `WindDir` | 20 | Degrees from +x toward +z: the wind's direction. Ripple crests run across it, streaks along it. | 20 |
| `WindStreaks` | 0.7 | Contrast of calm and rough bands along the wind, 0..1. | 0.7 |
| `StreakScale` | 0.012 | 1 / streak spacing across the wind. | 0.012 |
| `RiverRough` | 1.8 | Rivers' ripples, against still water's. | 1.8 |
| `ShoreWet` | 0.5 | How far above the waterline the ground is wet (darker, smoother). Noise moves the line a little. | 0.5 |
| `ShoreEdge` | 0.15 | Width of the light band (`ShoreCol`) at the water's edge. | 0.15 |
| `ShoreCol` | [0.60 0.56 0.48] | Its colour: sand and pebbles (sRGB). | default |
| `ShoreStones` | 0.5 | Stone cover along the shore and in the shallows, 0..1. | 0.5 |
| `StoneScale` | 1.6 | 1 / stone size. | 1.6 |
| `ShoreReach` | 3 | Stones and the light band keep within about this distance of the water across the ground (height above it over the slope), so they don't spread over flat meadows. | 3 |
| `RiverLo` | 10000 | Catchment, in square world units, where a channel starts (10000 is 1 km²). | 10000 |
| `RiverHi` | 400000 | Catchment where a channel is full size; strength grows on a log scale between the two. | 400000 |
| `RiverWidth` | 14 | Width of a full-size channel (the groove; the water is narrower), world units. A young stream is 35% of it. | 14 |
| `RiverDepth` | 2 | Depth carved into the erosion map at full size. | 2 |
| `RiverFill` | 0.7 | How full of water the channels are, 0..1. | 0.7 |
| `ErFlowOn` | false | (`fc_erode.ps`) Compute the flow map without rivers (`Rivers` turns it on). | |
| `Ocean` | false | Load `lib/fc_ocean.ps`: the sea (below). Needs `WaterY` or `WaterRise` too, which load this file. | true |

| Procedure | Stack | What it does |
|---|---|---|
| `fc-water-level` | `x z → y` | The water surface height there: the highest of `WaterY`, a map lake around the point and a river's level; −1000 if none. |
| `fc-water-normal` | `x z t → nx ny nz` | The surface normal at distance `t` (ripples, streaks). A hook: redefine it for waves. Waves made this way change only the shading: the hit is still the flat plane, so crests that hide what's behind them would need a height hook in `fc-water-plane`. |
| `fc-water-colour` | `t depth → r g b` | Light scattered back from inside the water, before the bed shows through. `depth` is the bed's depth under the surface point (1000 where the ray meets no bed). A hook: depth tint goes here. |
| `fc-water-shade` | `t → r g b` | The whole surface: Fresnel mix of the reflection and the water (with the bed through shallows). Reads `AqLev` (the level hit) and `AqBedT` (the bed's distance). |
| `fc-water-rivers` | `–` | After the bake: carve and fill the channels. Setup calls it. |

### The sea (`fc_ocean.ps`, with `Ocean`)

`fc_water.ps` loads it last. It replaces `fc-water-normal` (swell plus the
ripples as wind chop) and `fc-water-colour` (colour by depth), and wraps
`fc-water-shade` (sun glitter and foam), `fc-landscape-surface` (wet sand),
`fc-terrain-material` (sand on the beach and the bed) and `fc-water-dry-hit`
(the march under the sea stops about `6 WaterClear` past the surface, where
the bed no longer shows; this needs `WaterY`, and it shortens `TMax` for the
march and puts it back, until `fc_landscape.ps` has a separate march bound).
Only the sea is changed: the plane at `WaterY`. Rivers, and map lakes above
it, keep the lake's ripples and colour, with no surf, wet sand or sand. The chop is the lake's ripples, so a sea raises
`RippleAmp` (0.07 in `spikes/ocean_shore.ps`) and points `WindDir`. Waves
change the shading only: the hit is still the flat plane (`docs/techniques.html`
§12, The sea, has the numbers). Depth below is sea level minus the
ground's height straight under the surface point, not `fc-water-colour`'s
depth along the ray. With `Ocean` false nothing here loads.

| Setting | Default | What it does | Used |
|---|---|---|---|
| `SwellAmp` | 0.10 | Slope of the main swell component (four directional sine waves, slopes 1, 0.75, 0.6, 0.45 of it). Each fades out as its wavelength nears three pixels, and the slope it loses tilts the normal toward the camera, as the ripples' does, so far water doesn't sparkle. | 0.10 |
| `SwellLen` | 12 | Longest swell wavelength, world units (120 m); the others are 0.63, 0.41 and 0.27 of it. | 12 |
| `SwellSpread` | 30 | Degrees the components' headings spread around `WindDir`. | 30 |
| `SwellShoal` | 0.8 | Extra steepness where the water is shallower than `3 SurfDepth`. | 0.8 |
| `SeaShallow` | [0.10 0.70 0.66] | The water's own colour over shallows (turquoise), sRGB. Lit by `SkyAmb` and, more over a shallow bed, the sun. | default |
| `SeaDeep` | [0.03 0.11 0.13] | ... and over deep water (dark blue-green). | default |
| `SeaDepth` | 1.5 | Depth over which `SeaShallow` turns `SeaDeep` (1/e), world units. The bed itself also shows through, by `WaterClear`. | 1.5 |
| `SeaDepthOct` | 5 | Terrain octaves for the depth (one `fc-height` per water pixel; four more in the surf zone). | 5 |
| `FoamCol` | [0.90 0.92 0.93] | Foam albedo, sRGB, lit by the sun (with terrain and cloud shadow) and the sky. | default |
| `FoamCrest` | 0.85 | Swell height (−1..1, the components' weighted sum) where crests start to foam, fully from 0.2 higher; 1 or more: no crest foam. | 0.85 |
| `FoamScale` | 1.2 | 1 / foam lace size. Noise thresholded so a cover of *f* leaves about *f* of the surface white; under three pixels it fades to the flat mean. | 1.2 |
| `SurfDepth` | 0.35 | Water shallower than this breaks (the surf zone, fading in from 0.7 of it). | 0.35 |
| `SurfSpacing` | 1.5 | Distance between breaker lines, world units. The lines follow the depth contours: their phase is the distance to the waterline, estimated as depth over the bed's slope, plus a wander. Lines under three pixels apart fade to their mean cover. | 1.5 |
| `SurfTrail` | 0.3 | Foam trail behind each breaker (seaward, after a sharp shoreward front), as a fraction of the spacing (1/e). | 0.3 |
| `SurfFoam` | 1 | Surf foam cover, 0..1; 0 turns off the breakers and the swash line at the waterline. | 1 |
| `WetSand` | 0.1 | Height above the water of the wet band, where the ground mirrors the sky and clouds (Fresnel on a level film; no ground in the reflection). Measured on the same `SeaDepthOct` height as the surf, so the swash meets it; its edge widens to the height a pixel spans. 0: none. | 0.1 |
| `WetMirror` | 0.75 | How mirror-like the wet band is, 0..1. | 0.75 |
| `GlitterGain` | 1 | Sun glitter: a microfacet lobe (Beckmann, with Smith shadowing-masking) on the wave normal, its width `GlitterRough` plus the slope the waves lose with distance, so near glints break up and far ones merge into a smooth path. Shadowed by terrain and clouds. 0: none. | 1 |
| `GlitterRough` | 0.03 | Slope spread the waves don't resolve. | 0.03 |
| `SandHeight` | 0.8 | Sand on the sea bed and up to this height above the water (on gentle ground), before `fc_water`'s wet ground. With `lib/fc_coast.ps` loaded (`fc-coast-material` defined) the beach is the coast's, and this paints only the bed under water. 0: none. | 0.8 |
| `SandCol` | [0.74 0.67 0.52] | Its colour, sRGB. | default |

| Procedure | Stack | What it does |
|---|---|---|
| `fc-ocean-lace` | `f → f'` | Foam cover to the lace's cover at the current water point. |
| `fc-water-reflect-at` | `t y → r g b` | (`fc_water.ps`) The reflection off a level film at distance `t` and height `y`: the wet sand's. It overwrites `AqLev`, `AqSurfT` and `AqNrx AqNry AqNrz`, so call it outside `fc-water-shade`. |

## Hooks a piece can redefine

These are procedures, not settings. Redefine them **after** loading
`fc_landscape.ps`. `lib/fc_water.ps` uses four of them (see Water above).

| Hook | Stack | Default |
|---|---|---|
| `fc-landscape-hit` | `– → t \| −1` | `fc-forest-hit` with trees, `fc-terrain-hit` without. |
| `fc-landscape-surface` | `t → r g b` | `fc-tree-shade` on a tree (`FsMat` 1; `FsKind` says which part: 0 a crown, 1 a trunk, 2 a log, 3 a crown's underside), otherwise `fc-terrain-shade`. Linear light, before haze. |
| `fc-landscape-sky` | `dx dy dz → r g b` | `fc-sky` above the horizon, the haze colour below it. |
| `fc-landscape-grade` | `r g b → r g b` | `fc-grade` when a grade setting is set (see Colour grade), otherwise nothing. Linear light, just before the tone curve. A piece that redefines it can call `fc-grade` itself (after loading `lib/fc_grade.ps`). |
| `fc-forest-dens` | `x z h ny curv → density height-scale` | `fc_trees`' rules. Wrap it to keep trees off some ground, as `fc_water` does. Redefine it before `fc-landscape-setup`. |
| `fc-terrain-material` | reads and changes `Alb KlMul KskyMul KbMul` | Defined by `fc_trees` (forest floor), and chained onto by `fc_coast` (beaches) and `fc_water` (shores). With none of them it doesn't exist, and a piece can define it to paint the ground. |
| `fc-terrain-base` | `x z → lift mask pin` | Defined by `fc_map.ps` (`MapOn`); otherwise absent and the noise massif is used. Map coordinates in; the lift in world units, the massif mask 0–1 and the pin 0–1 out. A piece can define its own (an analytic island, say) before `fc-landscape-setup`. |
| `fc-pixel` | `u v → r g b` | `fc-landscape-pixel`. Replace it entirely for a different scene. |

While a hook runs, `Mx My Mz` is the pixel's unit ray, from `(0, CamY, 0)`.
`PixAng` is the angle one pixel covers, so `t PixAng mul` is a pixel's
size at distance `t`. Use it to fade out detail that would be smaller than
a pixel.
