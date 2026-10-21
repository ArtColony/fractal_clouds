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
| `scripts/render.sh` | Render, lint and time pieces into `renders/` (git-ignored) |
| `docs/pscat-issues.md` | pscat bugs and skill-doc problems, waiting to be filed upstream |
| `.claude/skills/` | The `pscat`, `psart` and `psviz` agent skills, copied from the pscat release |
| `.mcp.json` | Registers `pscat-mcp` for Claude Code |

## Rendering

```sh
scripts/render.sh                    # every piece in gallery/
scripts/render.sh gallery/foo.ps     # one piece
DPI=144 scripts/render.sh            # higher resolution
```

Each piece sets its canvas with `%%BoundingBox: 0 0 W H`. Timings are
appended to `renders/timings.tsv`.

## Upgrading pscat

Bump `.pscat-version`, install that release as above, and re-copy
`plugin/skills/{pscat,psart,psviz}` from the same tag into `.claude/skills/`,
so the skills always match the binary.

## License

CC0 1.0 (see `LICENSE`).
