# Fractal mountains (#1)

`gallery/mountains.ps`: an alpine range under cumulus, one ray per pixel,
rendered by pscat 0.6.2. Status: draft until the owner marks it final.

## How it's made

| Layer | Library | What it does |
|---|---|---|
| Camera, sky, haze, tone | `lib/fc_sky.ps` | Pitched and yawed pinhole camera; sky with a soft sun; haze integrated along each ray through air that thins with height; linear light, tone curve, sRGB gamma at the end |
| Clouds | `lib/fc_clouds.ps` | 3D fBm density in a layer with a coverage map (cloud groups with gaps); Beer–Lambert march with steps and octaves that follow distance; two shadow probes, forward scattering, a multiple-scattering term |
| Terrain shape | `lib/fc_terrain.ps`, `lib/fc_noise2.ps` | A massif mask decides where ranges and valleys are; domain-warped ridged multifractal on gradient noise makes the ridges; erosion fBm (noise with analytic gradient) adds gullies |
| Erosion | `lib/fc_erode.ps` | 240k water droplets on a 1024² map over the view; only the *change* is kept and added to the procedural terrain, through a Catmull-Rom lookup |
| Terrain shading | `lib/fc_terrain.ps` | Soft cast shadows and cloud shadows; sky visibility and concavity from a four-sample ring; snow by elevation, flatness, hollows and aspect; rock with strata, patches and mottling; normals tilted on steep rock so faces fracture in the light |
| Renderer | `lib/fc_render.ps` | Image sized from page × DPI × `Res`; adaptive antialiasing on depth edges |

Every noise octave finer than about two pixels is dropped, for clouds and
terrain alike, so distance never turns into sparkle.

## How it got here

Each round was rendered, looked at, and critiqued by Codex
(`scripts/codex_critique.sh`), and later compared blind against the
previous best (`scripts/codex_pairwise.sh`).

| Round | Change | Result |
|---|---|---|
| draft 1 | ridged fBm, no shadows | "melted wax"; camera facing a wall at first |
| + shadows | soft terrain and cloud shadows | needed a bias: the coarse shadow terrain started inside the mountain |
| + linear light | sRGB palette → linear, gamma at the end | shadows no longer crushed to black |
| + hierarchy | massif mask, warp, gradient-noise ridges | value-noise ridges had drawn rings; the first view looked across lowland (found with `spikes/heightmap.ps`) |
| draft 2 | seed 5, yaw 10, integrated haze, cloud coverage | first render that read as a landscape |
| + erosion | droplet bake | replacing the terrain with the map lost crispness (bilinear facets, then B-spline rounding); adding only erosion's change kept it |
| + fractured rock | normal perturbation, greyer rock, more sky light | **beat draft 2 and the first erosion version in blind pairwise tests, in both orders, twice** |
| + AA, framing | edge antialiasing, level camera | the foreground ridge cropped out |

Codex's absolute 1–10 realism score stayed at 3 from the first critique to
the last, so it was used for symptoms, not progress. Pairwise A/B in both
orders was the useful measure, and even that was position-biased until the
differences were large.

## Timings (pscat 0.6.2, Apple-silicon Mac, one thread)

| Render | Bake | Render | Total |
|---|---|---|---|
| 320×200, 512² map | 21 s | 119 s | 140 s |
| 640×400, 1024² map | 85 s | 481 s | 566 s |
| 1280×800, 1024² map, AA | 84 s | 32.8 min (7,430 px antialiased) | 34.2 min |

Large render: `gallery/previews/mountains-1280x800.png`
(`DPI=288 scripts/render.sh -D ErN=1024 -D ErDrops=240000 gallery/mountains.ps`).

## Known limits

- Snow is a colour, not geometry: it doesn't fill channels.
- The erosion map covers the view's first ~1150 units; beyond it the
  terrain is procedural (blended over the map's outer 6%).
- No trees yet (issue #1's stretch goal).
- The foreground ridge at the bottom centre is still smooth and dune-like.
- Faint grain inside the clouds from the jittered march steps (#27: now
  blue-noise jitter and shorter dense steps).
