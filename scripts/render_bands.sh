#!/usr/bin/env bash
# Render one piece as horizontal bands in parallel (one pscat per band, via
# render.sh with a Crop), then stitch them into renders/<name>.png.
#
#   DPI=288 scripts/render_bands.sh gallery/foo.ps 0.55 0.66 0.81 -- -D ErN=1024
#
# The numbers are the band boundaries, as fractions of the frame from the
# top: put more of them where rows are expensive. Defines after `--` go to
# every band. Each band runs the piece's whole setup (bakes included), so a
# seeded piece builds the same scene in each; but a random sequence used
# while rendering (march jitter) continues differently per band, and each
# band's first row has no row above it for edge antialiasing.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
piece="$1"; shift
cuts=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do cuts+=("$1"); shift; done
[ "${1:-}" = "--" ] && shift
name="$(basename "$piece" .ps)"
tmp="$(mktemp -d)"
edges=(0 "${cuts[@]}" 1)
pids=()
for ((i = 0; i < ${#edges[@]} - 1; i++)); do
  band="$tmp/${name}_band$i.ps"
  cp "$piece" "$band"
  scripts/render.sh "$@" -D "Crop=[0 ${edges[i]} 1 ${edges[i+1]}]" "$band" &
  pids+=($!)
done
failed=0
for p in "${pids[@]}"; do wait "$p" || failed=1; done
[ "$failed" = 0 ] || { echo "render_bands: a band failed; logs in renders/${name}_band*.log" >&2; exit 1; }
python3 - "$name" "${edges[@]}" <<'P'
import sys
from PIL import Image
name, edges = sys.argv[1], [float(e) for e in sys.argv[2:]]
bands = [Image.open(f"renders/{name}_band{i}.png").convert("RGB") for i in range(len(edges) - 1)]
W, H = bands[0].size
out = Image.new("RGB", (W, H), "white")
for i, b in enumerate(bands):
    y0, y1 = round(edges[i] * H), round(edges[i + 1] * H)
    out.paste(b.crop((0, y0, W, y1)), (0, y0))
out.save(f"renders/{name}.png")
print(f"render_bands: wrote renders/{name}.png ({W}x{H}, {len(bands)} bands)")
P
rm -rf "$tmp"
