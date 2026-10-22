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

## Open questions
- Skills as copies vs. the marketplace plugin (see above).
- Should shared procedures that turn up across projects (a camera / 3D
  projection helper, for one) live in the template, in a separate ArtColony
  library repo, or be sent upstream to pscat's `lib/`?
- Branch protection and required reviews on `main`: set them up by hand per
  repo, or with a bootstrap script (`gh api`)? Template repos don't copy
  settings.
