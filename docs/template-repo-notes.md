# Notes for an ArtColony template repo

What a GitHub template repo for new ArtColony projects should hold, collected
while setting up fractal_clouds. Each item says why it's there and how
fractal_clouds did it. Move this file to the template repo once that exists.

## Include

### pscat, pinned
- **`.pscat-version`** holding the pscat release a project renders with. Tools
  read it, and the render script warns when the installed pscat differs.
  Renders only reproduce on the same interpreter version.
- **README setup section**: download the release archive, check it against
  `SHA256SUMS`, keep the bundle together, symlink `pscat` and `pscat-mcp`
  onto `PATH`. Optionally `gh attestation verify <archive> --repo PSCatLabs/pscat`.
  fractal_clouds installed the bundle at `~/.local/opt/pscat-<v>` with
  symlinks in `~/.local/bin`.
- **Mention the font packs.** A bare install has only Helvetica, Times and
  Courier. `pscat fonts install` is a separate download (see
  `docs/pscat-issues.md` #1).

### Agent setup
- **`.claude/skills/{pscat,psart,psviz}`**, copied from `plugin/skills/` at the
  pinned tag. These are copies, not the marketplace plugin, so the skills are
  versioned with the repo and match `.pscat-version`.
  - Alternative: rely on `/plugin install pscat --marketplace PSCatLabs/pscat`
    and ship no copies. That's simpler, but the plugin version then floats
    away from the pinned binary. Decide this for the template.
  - Either way, a `scripts/update-pscat.sh <version>` that bumps
    `.pscat-version` and re-copies the skills would be worth having.
- **`.mcp.json`** registering `pscat-mcp` (stdio), plus `.claude/settings.json`
  with `"enabledMcpjsonServers": ["pscat"]`, so sessions don't ask to approve it,
  and an allowlist for `Bash(pscat:*)` and `Bash(scripts/render.sh:*)`.
  Don't also install the pscat plugin, or the tools appear twice.
- **`CLAUDE.md`** with the house rules: released pscat only, render through the
  script, seed everything, check fonts, log pscat problems, branch per issue.
  Keep it generic and let each project add a line or two. An `AGENTS.md`
  pointing at the same rules would cover Codex.
- **Serena**: commit `.serena/project.yml` (it's portable) and its own
  `.gitignore`. `project.local.yml` and the cache stay ignored. The template
  needs `project_name` filled in per project, so either leave a placeholder
  or have a bootstrap step set it.

### Layout
- `gallery/` for pieces (one `.ps` each, `%%BoundingBox: 0 0 W H` sets the
  canvas), `gallery/previews/` for hand-picked PNGs that get committed,
  `lib/` for reusable procedures, `scripts/`, `docs/`.
- `.gitignore` ignoring `renders/` (all script output) and `.DS_Store`.

### `scripts/render.sh`
Every project needs the same thing, so it belongs in the template:
- renders `gallery/*.ps`, or named files, to `renders/<name>.png` at `DPI`
  (default 72), with the page size read from `%%BoundingBox`;
- always passes `--lint` and reports `ok` / `lint` / `error` per piece,
  printing the log when it isn't clean;
- times each render (`/usr/bin/time -p`, which works on macOS and Linux) and
  appends to `renders/timings.tsv` with the pscat version and DPI. Render
  time matters for this kind of work (fractal_clouds#1 asks for timings);
- refuses a repo `lib/` file that has the same name as one of pscat's built-in
  `lib/` files. pscat looks for `(lib/x.ps)` relative to the current
  directory before its compiled-in copy, so a repo `lib/artkit.ps` would
  quietly replace the real one;
- exits 0 on an empty gallery, so a fresh project from the template passes.

Learned in the #1 spike:
- **defines** (added to `render.sh` on the mountains branch):
  `-D NAME=VALUE`, sent as `/NAME VALUE def (piece) run` on stdin, and
  logged in `timings.tsv`. Pieces opt in with `/NAME where { pop } {...} ifelse`.
  Before this existed, timing runs bypassed the script and skipped the log;
- **resolution from DPI**: `matrix defaultmatrix 0 get` gives device pixels
  per point under `--dpi`, so a per-pixel renderer can size its image from
  the page and `DPI=144` doubles the detail, with a `Res` factor for quick
  previews;
- **`--determinism`**: render twice and compare SHA-256s. It was done by hand
  for the spike, and the SDLC notes make it a gate;
- a `spikes/` glob alongside `gallery/`, or a `--all` that covers both.

### `scripts/check_names.sh`
PostScript has no local variables. Library procedures keep their scratch
values in `userdict`, so two libraries that both use `/Fv` overwrite each
other silently whenever one calls into the other. On the mountains branch
this turned the first render into noise and streaks: the renderer's row
coordinate `Fv` was clobbered by the 3D noise's `Fv`. The script lists every
name `def`'d in more than one `lib/` file, with an allowlist for intended
shared settings. It belongs in the template and in CI, and each library
should keep its temporaries under its own prefix.

### Review tooling (from the mountains work)
- **`scripts/codex_critique.sh PROMPT IMAGE...`**: a Codex critique of
  renders. The Codex Claude Code plugin can't attach images, so it calls
  `codex exec -i` directly, read-only with high reasoning effort. `-o FILE`
  (last message to a file) is what made the output reliable; filtering
  stdout for the answer broke as soon as stderr was discarded.
- **`scripts/codex_pairwise.sh OLD NEW`**: blind A/B judgment in both
  orders. Use it to see whether a change helped. Absolute 1–10 scores
  stopped moving after the first fixes (3/10 four times running while the
  images clearly improved), and the critiques repeated advice that had
  already been applied. Later pairs got split or position-biased verdicts
  (whichever image came first won), so a split verdict means "can't tell",
  and the owner's eye decides.
- Treat a critique's *where* observations as symptoms and its suggested
  fixes as hypotheses: test the cheapest explanation first (for example,
  render with one layer turned off) before building anything.
- **`spikes/heightmap.ps`**: a top-down hillshade of the terrain with the
  camera's field of view drawn on. It found why the mountains had
  vanished (the view looked across lowland) and why ridges looked like rings.

### Rendering lessons worth carrying into any project
- **Work in linear light.** Give palette colours in sRGB, convert them on
  load, light in linear, then tone-map and gamma-encode once at the end.
  Writing linear values straight to 8 bits crushed shadows to black and
  made lit faces look metallic.
- **Ridged noise must be built on gradient noise.** On value noise its
  ridges trace closed rings around blobs.
- **Detail should follow distance.** Drop noise octaves finer than about
  two pixels, and measure normals over a pixel footprint. That fixes
  sparkle and horizon grain at the source.
- **Bias coarse shadow rays.** A shadow march on coarser terrain starts
  "inside" the detailed surface unless it's lifted by the height of the
  octaves it leaves out.
- **Erosion as a correction.** Baking droplet erosion and *replacing* the
  terrain with the map lost all crispness (bilinear facets, or B-spline
  rounding). Storing only the *change* erosion made, and adding it to the
  full procedural terrain, kept the detail and gained drainage and
  glacier-like valley fills.
- **Defaults across libraries:** a "safe default" in one library silently
  wins over another library's `fc-default` if it loads first. A flag
  belongs to the library that owns it.
- **Settings go before the libraries.** The same rule bit a piece: its
  `/AA where {...}` came after `(lib/fc_render.ps) run`, so the library's
  `false` won and a 33-minute render came out without antialiasing. Have
  every renderer print the settings it actually used (fc-render prints its
  antialiased-pixel count, which is how this was caught), and do a tiny
  render before any long one.
- **A crop window and a band splitter in the renderer from day one.**
  Judging detail in a 320 px frame misleads, and full large frames cost
  an hour. `fc-render`'s `/Crop` renders any rectangle at the full frame's
  detail in minutes; `scripts/render_bands.sh` runs one frame as parallel
  bands (pscat is single-threaded, so four cores give about 4x).
- **Diagnostic spikes beat staring at the beauty render.** The trees work
  was steered by small single-purpose renders: ground banded by height
  (where can trees grow?), materials in false colour (is that speckle ground
  or crown?), normals as colour (why noise?), one crown from the side
  (proportions), call counters (where does the time go?). Keep a habit and a
  place (`spikes/`) for them.
- **Don't difference a discontinuous surface for normals.** Finite
  differences across a step flip from pixel to pixel; take normals from a
  smooth envelope and put the detail in the shading.

- **Pull the scene into a library once two pieces share it.** fractal_clouds
  did this after its second piece: one `fc_landscape.ps` that loads the
  rest in order, does setup, and gives a general `fc-pixel` with named
  hooks (hit, surface, sky, grade). A new piece is then settings and a
  few hooks. Prove the refactor with a pixel diff of cheap renders before
  and after, not by eye.
- **Write the settings reference with only the values actually rendered**,
  not guessed safe ranges.

### Conventions worth writing down
- **Prefix repo libraries** (`lib/fc_noise3.ps` here; something like
  `lib/<project>_*.ps`). The render-script guard catches a clash with
  today's pscat, but only a prefix protects against a library pscat adds
  later.
- **Spikes**: code in `spikes/` and the write-up in
  `docs/spikes/<issue>-<slug>.md`, with its images committed beside it in
  `docs/spikes/<issue>-<slug>/`. They're small (under 250 KB each here) and
  they're the evidence for a decision.
- **No Ghostscript-only operators.** pscat doesn't have `=only` and friends,
  and the spike hit that twice. Print numbers with `N string cvs print`.
  This belongs in `CLAUDE.md`.
- **Ghostscript as the oracle.** When pscat output looks wrong, render the
  same file with `gs` (here 10.07.1 from Homebrew) before calling it a pscat
  bug. That's how issue #4 got confirmed. The README should list it as an
  optional dependency.
- **Benchmark helpers:** `usertime` deltas in milliseconds match wall-clock
  time in pscat, so in-program timings can be trusted. A shared
  `lib/<project>_bench.ps` helper is worth having.

### Process
- **`docs/pscat-issues.md`**: a log of pscat bugs and skill-doc mistakes, each
  with kind, status (`open` / `filed #N` / `wontfile`), location, repro and a
  suggested fix. Projects collect these, then file them upstream in a batch.
- **Issue templates** (`.github/ISSUE_TEMPLATE/`): at least "gallery piece"
  (idea, references, approach, open questions, deliverable; fractal_clouds#1
  is a good model) and "research".
- **PR template** with a "renders" checklist: previews attached, `render.sh`
  clean, timings noted.
- **License**: fractal_clouds uses CC0 1.0. Decide whether that's the colony
  default.

## Leave out, for now
- **CI.** With pscat pinned, a workflow that installs the release and runs
  `scripts/render.sh` would catch broken pieces. It isn't worth it until
  projects have `lib/` code to test. When it's added, a Linux musl archive
  works headless.
- **The full pscat-style SDLC** (`sdlcify`, claim/heartbeat scripts, release
  pipeline). Gallery repos don't ship releases.

- **Stacked PRs merge into their base, not `main`.** GitHub retargets a
  stacked PR to `main` only when the branch below it is deleted on merge. In
  fractal_clouds, #12 and #37 merged into their parent branches and needed a
  catch-up PR. Turn on "Automatically delete head branches" in a new repo, or
  retarget each stacked PR to `main` by hand before merging it.

## Open questions
- Skills as copies vs. the marketplace plugin (see above).
- Should shared procedures that turn up across projects (a camera / 3D
  projection helper, for one) live in the template, in a separate ArtColony
  library repo, or be sent upstream to pscat's `lib/`?
- Branch protection and required reviews on `main`: set them up by hand per
  repo, or with a bootstrap script (`gh api`)? Template repos don't copy
  settings.
