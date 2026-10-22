# Handoff: landscape toolkit roadmap

Notes for the session that picks up the roadmap epic (#36). Written 2026-10-22, when the landscape library (#11) landed. Replace this file when the next handoff is due.

## Where things stand

- **On `main`** (once PRs #10, #12, #37 and #6 are merged):
  - three pieces: `mountains`, `alpine_forest` and `evening_lake`, all `% Status: draft`;
  - the shared scene `lib/fc_landscape.ps`, with settings first and then hooks;
  - the settings reference `docs/settings.md`;
  - the technique guide `docs/techniques.html`, with figures from `docs/techniques/make_figures.py`;
  - the pscat log `docs/pscat-issues.md`, with entries 1–12;
  - the SDLC notes `docs/sdlc-notes.md`, a working draft that isn't adopted.
- **After merging:**
  - Close #1 by hand, because no PR closes it.
  - #11 closes through #12.
  - #8 (filing the pscat issues upstream) stays open until the owner asks.
- **Known approximation:** in `evening_lake`, the reflected clouds get hazed twice (it's noted in the code). It shows little at the current settings, and #28 is the place to fix it.

## Read first

1. `CLAUDE.md`, which holds the rules.
2. `docs/settings.md` for every setting and hook, and `gallery/evening_lake.ps` as the example of a piece that overrides hooks.
3. `docs/techniques.html` for how the renderer works (ray march, terrain, erosion, trees, clouds, haze).
4. The epic #36 and the issue you're starting on. Its body lists what it depends on.

## Order of work

The suggested order is in #36. In short:

1. **#35 regression script and CI** comes first, because it protects every change after it. Until it lands, check by hand:
   ```sh
   d='/ErN 256 def /ErDrops 20000 def'
   echo "$d /Res 0.5 def (gallery/mountains.ps) run"     | pscat --page 320x200 --png out/mountains.png -
   echo "$d /Res 0.5 def (gallery/alpine_forest.ps) run" | pscat --page 320x200 --png out/alpine.png -
   echo "$d /Crop [0.35 0.72 0.5 0.86] def (gallery/alpine_forest.ps) run" | pscat --page 320x200 --png out/alpine_crop.png -
   ```
   Run those once on `main` for the baselines and once on the branch. Compare each pair with PIL: `ImageChops.difference(a, b).getbbox()` must be `None`. Add `evening_lake` to the set; it takes about 5 minutes at 320×200.
2. **#20 timing**, so the performance work can be measured.
3. **Features, along their dependencies:**
   - #13 (terrain from a map) → #39 (coastal terrain);
   - #28 (water) → #38 (ocean) → #40 (coastal pieces), which also needs #39;
   - #14 (cloud types) → #15 (thunderstorm).
4. The aesthetics, realism and packaging issues fit in between. Most don't depend on each other.

#16 and #3 depend on pscat upstream. Leave them until the owner files #8.

## Working rules

These are the ones that cost time when forgotten:

- **Branches:** use one branch per issue (`<kind>/<issue#>-<slug>`). Stack a PR on an earlier branch only when it needs that branch's code, and say so in the PR body.
- **Settings:** set them before the `(lib/...) run` lines, because `fc-default` keeps a value that is already defined.
- **Random stream:** keep the setup order in `fc-landscape-setup` (noise seeds, trees seed, `srand`, erosion bake, forest bake, camera). The erosion bake draws from the random stream, so reordering these steps changes every picture.
- **Names:** there are no locals. Give scratch names the library's prefix, and run `scripts/check_names.sh`.
- **Renders:**
  - Render with `scripts/render.sh` and look at every PNG.
  - Check settings on small full-detail crops before a long render.
  - Use `scripts/render_bands.sh` for full-size renders.
- **Reviews:** have Codex review the change before the PR (`codex exec -s read-only -c model_reasoning_effort=high -o FILE "prompt"`). Put the fixes in their own commit and list them in the PR.
- **pscat:** log bugs and skill-doc mistakes in `docs/pscat-issues.md` with a repro. Check against `gs` first, and don't file upstream.
- **Pieces:** they stay `% Status: draft`; only the owner marks one final.
- **Docs:** update `docs/settings.md` with each new setting or hook. Update `docs/techniques.html` when an algorithm changes.

## Parallel work and models

- **Rendering:** the machine has 10 cores and 16 GB of memory, and pscat runs on one core. A full piece takes about 30 minutes across all cores, and a 320×200 preview takes 5 minutes on one. Keep it to 2–3 agents rendering at a time.
- **Shared libraries:** most features change `fc_terrain`, `fc_render` or `fc_landscape`. Do those one at a time in the lead session, not in parallel worktrees.
- **Good subagent work:** Codex reviews, docs and figures, presets (#31), packaging (#32, #34), CI (#35), timing (#20), and small test-crop experiments. Run them in worktrees.
- **Models:**
  - The strongest available model: new algorithms and decisions about how pieces look (#13, #14, #15, #28, #38, #39, #22).
  - Opus: the lead session and reviews.
  - Sonnet: mechanical work (tables, presets, wrappers, doc updates).
