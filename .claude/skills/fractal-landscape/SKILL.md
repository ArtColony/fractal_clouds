---
name: fractal-landscape
description: Make a new landscape piece in the fractal_clouds repo (PostScript ray-marched mountains, clouds, forests, lakes, rivers, sea, rendered with pscat) from a one-line request such as "a misty valley at dusk with a forest". Use when asked for a landscape, mountain, valley, lake, coast, sunset or cloudscape picture in this repo, to change a piece's look, or to pick settings, presets or a camera for one. Covers presets, the framing pass, full-detail crops, the final banded render and the Codex review loop.
---

# fractal-landscape: request to piece

Work from the repo root (`CLAUDE.md` rules apply). The `pscat` skill covers the
interpreter; this one is the workflow for this repo's landscapes. Link, don't
copy: every setting is in `docs/settings.md`, every method in
`docs/techniques.html`.

## Rules that cost hours when forgotten

1. **Settings before libraries.** A piece sets everything
   (`/Name where { pop } { /Name v def } ifelse`) *before* `(lib/fc_presets.ps) run`
   and `[ ... ] fc-presets`, which come before `(lib/fc_landscape.ps) run`. A
   setting made after the library loaded is silently ignored. Precedence:
   `-D` on the command line, the piece, presets (earlier in the list first),
   library defaults.
2. **Seed every piece** (`/Seed N`, a number you pick) so renders reproduce.
   Mac and Linux renders differ, so compare only on one platform.
3. **Cheap first.** Frame at `DPI=36` (160x100), look, then spend. Check the
   exact final settings on full-detail crops (`-D "Crop=[x0 y0 x1 y1]"`,
   fractions from the top left) before any long render.
4. **Render with `scripts/render.sh`**, never bare `pscat`, and **look at every
   PNG** (Read it). Pieces say `% Status: draft`.
5. **Cores:** the machine may be shared; use at most 3 at once. `render_bands.sh`
   starts one process per band (N cuts, N+1 bands), so use 2 cuts; give
   `regress.sh` `JOBS=3`. Run long renders in the background.
   Use the released pscat in `.pscat-version`, never a source checkout.
6. **Never edit `lib/`** to make one piece. A library change must keep the
   gallery pixel-identical: check with `JOBS=3 scripts/regress.sh --ref main` on
   a Mac (plain `scripts/regress.sh` on Linux); `--docker --update` only for an
   intended look change or a new gallery piece's references. A new library
   file is `lib/fc_*.ps`, with its own name prefix; run `scripts/check_names.sh`. Per-piece changes go in settings, or in hooks the
   piece redefines *after* loading the landscape (`docs/settings.md`, "Hooks").
7. A piece in `gallery/` needs regress references (`regress.sh` renders every
   gallery piece). A trial or example goes elsewhere (e.g. `docs/examples/`)
   with its preview.

## Steps

### 1. Read the request into choices

Pick one item per axis, from "The presets" in `docs/settings.md` and the word
table in `references/recipes.md`:

- **Time of day:** `/Dawn /Noon /Evening /Night`. Dusk: `/Evening`, or
  `SunElev` 2 to 5 with the sky model. Do not combine `/Dawn /Noon /Night`
  with `/Evening` or any `Zenith`/`Horizon`.
- **Weather:** `/Clear /Overcast /Storm`. Mist or fog: a small `HazeDist`
  (150 to 300) and a higher `Turbidity`, not a cloud layer.
- **Terrain:** `/Alpine /Foothills /Mesa`, or a drawn map (`MapOn`,
  `lib/fc_map.ps`) for a particular geography: `gallery/charted_range.ps`.
- **Season** (list before the terrain): `/Spring /Summer /Autumn /Winter`.
- **Features:** `TreesOn` (forest; species mix `FsMix`), `WaterRise` or `WaterY`
  (lake), `Rivers`, `MapWater` (map lakes), `Ocean` (sea; needs `WaterY`;
  `spikes/ocean_shore.ps`), `CloudLayers` (e.g. `[/Cumulus /Cirrus]`).
- **Camera:** `Yaw`, `Pitch`, `HFov`, `CamAbove` or `CamLift`, and where you
  stand: `TerrOX`/`TerrOZ`. Moving these is how you find a composition; a new
  `Seed` is a new range.

### 2. Write the piece

Copy the skeleton in `references/recipes.md` to `gallery/<name>.ps` (or the
example directory); for a presets-only idea write a scene file in `scenes/`
and render it with `scripts/render.sh -D "Scene=(scenes/x.ps)" scenes/scene.ps`.
Header: `%%BoundingBox: 0 0 320 200`, a title, `% Status: draft`, the preview
command. Use only settings that exist in `docs/settings.md` (grep the name).
A misspelt preset stops with `fc_presets: no preset called ...`.

### 3. Framing pass (cheap)

```sh
DPI=36 scripts/render.sh gallery/<name>.ps       # 160x100, minutes
```

`-D Res=0.25` and a lower `-D ErN=256 -D ErDrops=20000` are cheaper still.
Check the composition: horizon height, where the light falls, what is in the
foreground. Adjust camera, then seed, then settings. Two or three passes, not
ten. `-D Profile=true` prints where the time goes if a render is slow.

### 4. Crops at full detail

Decide the final size (`DPI=144` is 640x400, `DPI=288` is 1280x800, with
`-D ErN=1024 -D ErDrops=240000` at 288) and render the parts that matter (the
forest edge, the water, the cloud base) as small crops at that DPI:

```sh
DPI=288 scripts/render.sh -D "Crop=[0.3 0.6 0.5 0.8]" -D ErN=1024 -D ErDrops=240000 gallery/<name>.ps
```

Look at them. Trees, water and clouds change character at full detail, and a
crop is the only cheap check. Fix, repeat, and note the exact final settings.

### 5. Final render

```sh
DPI=288 scripts/render_bands.sh gallery/<name>.ps 0.6 0.8 -- -D ErN=1024 -D ErDrops=240000
```

The cuts are fractions from the top (two cuts, three bands); put the cuts so
the expensive rows (forest, water: lower in the frame) get narrower bands. Each band repeats the bakes. Run it in
the background (tens of minutes to an hour); the result is
`renders/<name>.png`. Check the seams along the cuts. Copy the chosen render
to `gallery/previews/` (or the example's `docs/` directory) by hand:
`renders/` is git-ignored.

### 6. Review loop

- **Critique** (what to fix): write a prompt file (what the picture should be;
  ask for ranked realism and aesthetic problems), then
  `scripts/codex_critique.sh PROMPT.txt IMAGE.png [CROP.png]`; it saves
  `IMAGE.critique.md` (see `docs/mountains-draft-02.critique.md`).
- **Pairwise** (did the change help): `scripts/codex_pairwise.sh OLD.png NEW.png`
  judges both orders, so a split verdict is position bias, not a result. Keep
  the change if both orders agree. Compare images of equal size.
- Codex is a second opinion: fix what you can see. `docs/forest/` shows the
  habit (image, critique, next iteration).

### 7. Finish

Branch `<kind>/<issue#>-<slug>`, PR into `main`; `CLAUDE.md` says when to
merge, close and write an HTML page (epics). Log a pscat bug or skill-doc
error in `docs/pscat-issues.md` with a repro; don't file upstream until asked.

## When something looks wrong

- Default look, setting ignored: it came after the `run` line.
- `undefined` error naming a preset, or a `CloudLayers` key or layer with `Hi`
  not above `Lo`: fix the name. A misspelt ordinary setting is not an error;
  it is silently ignored, so grep `docs/settings.md` for every name.
- Black or flat sky at night: raise `Exposure` (`/Night` does).
- Clouds hide the peaks: `TerrTop` is 59 by default; with a taller `TerrH`,
  raise `CloudLo`/`CloudHi`, or each layer's `/Lo` and `/Hi` if the piece or a
  weather preset (`/Overcast`, `/Storm`) sets `CloudLayers`.
- Trees missing: `TreesOn` false, ground above `FsLine`, or `/Mesa`.
- Compare with `gs` before calling it a pscat bug.
