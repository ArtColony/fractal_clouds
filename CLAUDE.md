# fractal_clouds

PostScript generative art rendered with pscat. See `README.md` for setup and layout.

- Use the released pscat at the version in `.pscat-version`, never a source checkout. The `pscat`, `psart` and `psviz` skills in `.claude/skills/` come from that same release tag.
- Render with `scripts/render.sh`, not bare `pscat`, so every run is linted and timed. Look at the PNG after every render.
- Load repo procedures with `(lib/name.ps) run` from the repo root. Never give a `lib/` file the same name as one of pscat's built-in `lib/` files: it would replace the built-in (`render.sh` refuses).
- Seed every piece (`N srand`) so renders reproduce.
- pscat has no Ghostscript-only operators (`=only` and friends): print numbers with `N string cvs print`. When pscat output looks wrong, compare with `gs` before calling it a pscat bug.
- Repo libraries get a project prefix (`lib/fc_*.ps`). Spikes go in `spikes/`, with the write-up and its images in `docs/spikes/<issue>-<slug>`.
- Bare installs have only Helvetica, Times and Courier; check `pscat --fonts` before using any other face.
- When a pscat bug or a mistake in the skills turns up, log it in `docs/pscat-issues.md` with a repro. Don't file upstream until asked.
- Work happens on a branch per issue (`<kind>/<issue#>-<slug>`), merged by PR into `main`.
