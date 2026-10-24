# Using the landscape libraries from another repo

The landscape libraries (`lib/fc_*.ps`) are released as a tarball, so another
ArtColony project can render with them without copying files by hand. A
project **pins** a release the way it pins pscat: one file holds the version,
a script installs exactly that, and CI uses the same script.

## What a release holds

Each release (a tag `vX.Y.Z` and its GitHub release) has three files:

| File | What |
|---|---|
| `fractal_clouds-X.Y.Z.tar.gz` | `lib/fc_*.ps`, `docs/settings.md`, `docs/techniques.html`, `LICENSE`, `VERSION`, and `PSCAT_VERSION` (the pscat the release was tested with), under one folder `fractal_clouds-X.Y.Z/` |
| `fractal_clouds-X.Y.Z-techniques.html` | The techniques page by itself |
| `SHA256SUMS` | For the two files above |

`docs/techniques.html` in the tarball and the standalone page are the same
single file: its figures are inlined, so it opens from anywhere, with no
checkout. (In the repo the page points at images beside it.) Its link to
`settings.md` goes to the file at the release's tag on GitHub.

Nothing else is released: this repo's scene files (`scenes/`), its pieces and
the render scripts stay here. The scene *format* (`fc-settings`, see
`docs/settings.md`) is part of the library, so a project writes its own scene
files. `docs/settings.md` ("The public interface") says which names a release
promises and which are internal.

## Pinning a release in your project

1. Copy `scripts/fetch_fc.sh` from this repo into your project's `scripts/`.
   It needs only `gh`, `tar`, `sha256sum` or `shasum`.
2. Pin a version, which installs it:

   ```sh
   scripts/fetch_fc.sh 0.1.0       # installs, then writes .fc-version
   ```

   `.fc-version` holds just the version (`0.1.0`), like `.pscat-version`.
   The script downloads `fractal_clouds-0.1.0.tar.gz` and `SHA256SUMS` with
   `gh release download`, checks the sum, and puts the libraries in `lib/` and
   the docs in `docs/fractal_clouds/` (with `VERSION` and `PSCAT_VERSION`
   beside them). It replaces `lib/fc_*.ps`, so a library a release dropped goes
   too, and it tells you if the release's `PSCAT_VERSION` differs from your
   `.pscat-version`.
3. Commit `.fc-version`, `lib/fc_*.ps` and `docs/fractal_clouds/`. Committing is
   the recommended choice (a clone renders with no network, and an upgrade
   shows as a diff). To git-ignore them instead, run `scripts/fetch_fc.sh` in
   your setup and CI, as you do for pscat.
4. In CI, check that nobody edited an installed library by hand:

   ```yaml
   - run: scripts/fetch_fc.sh --check      # lib/fc_*.ps are exactly .fc-version
   - run: scripts/check_names.sh           # if you keep it: your libraries vs. fc_*
   ```

5. Write pieces as in `README.md` ("Making a landscape"): settings, then
   `(lib/fc_presets.ps) run` and `fc-presets` if you use presets, then
   `(lib/fc_landscape.ps) run`, then `fc-landscape`. Render from the project
   root: the libraries load each other as `(lib/fc_x.ps) run`, relative to the
   directory you render from, and your own `lib/` files sit beside them. Give
   yours a prefix of your own (`lib/<project>_*.ps`): the `fc_` prefix and
   the names in `docs/settings.md` are the libraries'. A file that pscat
   already has under `lib/` still must not be reused, as in every project;
   the prefix prevents that too.

To upgrade, run `scripts/fetch_fc.sh NEW_VERSION`, read the release notes
and `docs/fractal_clouds/settings.md`, re-render, and commit. Renders match
only for one release, one pscat and one platform: the pictures may change
between releases (see "Versions" in `docs/settings.md`), so a project that
keeps reference renders refreshes them when it upgrades.

The presets (`lib/fc_presets.ps`: time of day, weather, terrain, season, and
the colour-grade presets `/Filmic`, `/Warm`, `/Cool`, ...)
and the scene-file format are part of the release and of the public
interface. A project's own presets go into `FcPresets` from its own piece or scene file.

## Cutting a release

A release is outward-facing, so a person does it, from `main` after CI is
green:

```sh
scripts/release.sh 0.1.0      # optional: builds dist/ here to look at it
git tag -a v0.1.0 -m "fractal_clouds 0.1.0"
git push origin v0.1.0
```

Pushing the tag runs `.github/workflows/release.yml`, which runs
`scripts/release.sh 0.1.0` on the tagged commit and attaches `dist/` to a
GitHub release with generated notes (a tag with a suffix, such as
`v0.2.0-rc.1`, is a pre-release). The released files are the committed ones:
`release.sh` builds from `HEAD`, not from your working tree. Edit the notes
afterwards to list the settings and hooks added or changed, and say if
pictures changed (before 1.0 a minor release may change them; a patch release
never does).

Choosing the number: a bug fix that leaves every picture identical is a
patch; anything that adds a setting or hook, or changes a default or a
picture, is a minor release (before 1.0); removing or renaming a public name
is a major release (after 1.0).

## Reading `techniques.html` without a checkout

The release's `fractal_clouds-X.Y.Z-techniques.html` is the page: download it
from the release and open it. To give it an address, the options are:

- **GitHub Pages**: publish the release asset (or run
  `python3 -I scripts/standalone_html.py . site/index.html
  https://github.com/ArtColony/fractal_clouds/blob/vX.Y.Z/docs` in a Pages
  workflow, so the link to `settings.md` points at the tagged file) from a `gh-pages` branch or a Pages deploy. This needs the owner to
  enable Pages for the repo (Settings), so it is not done here.
- **A Claude Artifact**: publish the standalone file (8.5 MB, under the 16 MB
  limit) as an Artifact. It is private until shared and needs no repo setting.
  This is how the epic #36 write-up is meant to be published.
- **The release asset itself**, linked from the README. GitHub serves it as a
  download, not a page, so this is the fallback.

`python3 -I scripts/standalone_html.py SRC_ROOT OUT.html [LINK_BASE]` builds
the standalone page from any checkout.
