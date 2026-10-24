# fractal_clouds

3D fractal clouds, mountains and trees in PostScript, rendered with
[pscat](https://github.com/PSCatLabs/pscat). An ArtColony project.

## Setup

This repo uses the **released** pscat, at the version pinned in
`.pscat-version`. Install it from the
[releases page](https://github.com/PSCatLabs/pscat/releases):

```sh
v=$(cat .pscat-version)
t=aarch64-apple-darwin          # or x86_64-apple-darwin, x86_64-unknown-linux-musl, ...
gh release download "v$v" -R PSCatLabs/pscat -p "pscat-$v-$t.tar.gz" -p SHA256SUMS
shasum -a 256 -c SHA256SUMS --ignore-missing
tar xzf "pscat-$v-$t.tar.gz"
# keep the bundle together, put pscat and pscat-mcp on your PATH, e.g.
mv "pscat-$v-$t" ~/.local/opt/pscat-$v
ln -sf ~/.local/opt/pscat-$v/pscat ~/.local/opt/pscat-$v/pscat-mcp ~/.local/bin/
pscat --version
```

The bare install has only Helvetica, Times and Courier. `pscat fonts install`
adds the font packs (Palatino and the rest of the LaserWriter 35, and the
display faces).

## Layout

| Path | What |
|---|---|
| `gallery/*.ps` | Finished and in-progress pieces, one file each |
| `gallery/previews/` | Chosen renders, committed by hand |
| `lib/*.ps` | Reusable procedures; load with `(lib/name.ps) run` from the repo root |
| `lib/fc_landscape.ps` | The whole landscape scene (sky, clouds, terrain, erosion, forest) behind one `fc-pixel`; a piece's starting point |
| `lib/fc_presets.ps` | Named presets (time of day, weather, terrain, season) and scene files: groups of settings that a piece loads before the library |
| `scenes/` | Scene files and `scene.ps`, the driver that renders one (`-D "Scene=(scenes/evening_lake.ps)"`) |
| `docs/settings.md` | Every landscape setting, its default and the values tried |
| `docs/techniques.html` | How it works: the algorithms, with diagrams and references (open it in a browser) |
| `scripts/render.sh` | Render, lint and time pieces into `renders/` (git-ignored) |
| `scripts/render_bands.sh` | One large frame as parallel horizontal bands, stitched |
| `scripts/regress.sh` | Pixel-regression check of the gallery against `tests/regress/linux/` or a git ref; run by CI (`.github/workflows/ci.yml`) |
| `docs/pscat-issues.md` | pscat bugs and skill-doc problems, waiting to be filed upstream |
| `.claude/skills/` | The `pscat`, `psart` and `psviz` agent skills, copied from the pscat release |
| `.mcp.json` | Registers `pscat-mcp` for Claude Code |

## Making a landscape

Set options, load `lib/fc_landscape.ps`, render:

```postscript
%!PS-Adobe-3.0
%%BoundingBox: 0 0 320 200
/Seed where { pop } { /Seed 12 def } ifelse
/TreesOn where { pop } { /TreesOn true def } ifelse
/Yaw where { pop } { /Yaw -27 def } ifelse
/TerrOX where { pop } { /TerrOX 180 def /TerrOZ 400 def } ifelse
(lib/fc_landscape.ps) run
320 200 fc-landscape
showpage
```

`docs/settings.md` lists the settings and the hooks a piece can redefine
for anything settings don't cover: `gallery/evening_lake.ps` adds a lake
in about thirty lines.

## Rendering

```sh
scripts/render.sh                    # every piece in gallery/
scripts/render.sh gallery/foo.ps     # one piece
DPI=144 scripts/render.sh            # higher resolution
DPI=288 scripts/render.sh -D "Crop=[0.1 0.8 0.3 0.95]" gallery/foo.ps
                                     # just that part of the large frame, at its detail
DPI=288 scripts/render_bands.sh gallery/foo.ps 0.55 0.66 0.81
                                     # the large frame, four bands at once
```

Each piece sets its canvas with `%%BoundingBox: 0 0 W H`. Timings are
appended to `renders/timings.tsv`.

## Upgrading pscat

Bump `.pscat-version`, install that release as above, and re-copy
`plugin/skills/{pscat,psart,psviz}` from the same tag into `.claude/skills/`,
so the skills always match the binary.

## License

CC0 1.0 (see `LICENSE`).
