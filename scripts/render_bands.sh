#!/usr/bin/env bash
# Render one piece as horizontal bands in parallel (one pscat per band, via
# render.sh with a Crop), then stitch them into renders/<name>.png.
#
#   DPI=288 scripts/render_bands.sh gallery/foo.ps --auto 6 -- -D ErN=1024
#   DPI=288 scripts/render_bands.sh gallery/foo.ps 0.55 0.66 0.81 -- -D ErN=1024
#   DPI=288 scripts/render_bands.sh gallery/foo.ps          # --auto, one band per core
#
# --auto [N] (also used when no cut points are given) first renders the
# piece small (PROBE_DPI, default DPI/8 but at least 18) with /RowTimes,
# which times every row, then cuts the frame into N bands of equal
# estimated work. N defaults to the number of cores. Each band also pays
# the setup (the erosion and forest bakes) once; that cost is the same for
# every band, so it doesn't move the cuts, but it is in the predicted band
# times and it is why more bands than cores never pays. The probe needs
# the same defines as the real render (bake sizes above all) for its
# profile to be representative. Cuts land on whole rows of the final image
# (of fc-render's image, which with -D Res=0.5 has half the rows; keep Res
# at 1 or 1/k for bands, or the band edges fall between device rows).
#
# Hand cuts are fractions of the frame from the top: put more of them where
# rows are expensive. Defines after `--` go to every band (and the probe).
#
# Every band runs with /PixSeed true (lib/fc_render.ps): the random stream
# is reseeded per pixel and each band first computes the depth keys of the
# row above it, so the stitched picture is the same, byte for byte, whatever
# the cuts, and the same as one uncropped render with -D PixSeed=true. It is
# not the same as a plain render.sh run, whose cloud-march jitter runs on
# from pixel to pixel (same grain, different pixels).
#
# BAND_WRAP, if set, is put in front of each band's command (for example a
# lock that limits how many renders run at once).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ $# -gt 0 ] || { sed -n '2,30p' "$0"; exit 2; }
piece="$1"; shift
cuts=(); auto=""
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  if [ "$1" = "--auto" ]; then
    auto=0
    if [ $# -gt 1 ] && [[ "$2" =~ ^[0-9]+$ ]]; then auto="$2"; shift; fi
  else
    cuts+=("$1")
  fi
  shift
done
[ "${1:-}" = "--" ] && shift
[ -n "$auto" ] || [ ${#cuts[@]} -gt 0 ] || auto=0
if [ -n "$auto" ] && [ ${#cuts[@]} -gt 0 ]; then
  echo "render_bands: give cut points or --auto, not both" >&2; exit 2
fi
[ "$auto" != 0 ] || auto="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"

name="$(basename "$piece" .ps)"
dpi="${DPI:-72}"
page_h="$(awk '/^%%BoundingBox:/ {print $5; exit}' "$piece")"
page_h="${page_h:-792}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
wrap=()
[ -z "${BAND_WRAP:-}" ] || read -r -a wrap <<< "$BAND_WRAP"
t_start=$(date +%s)

if [ -n "$auto" ]; then
  probe_dpi="${PROBE_DPI:-$(python3 -c "import sys; print(max(18, float(sys.argv[1]) / 8))" "$dpi")}"
  res=1                                    # the last -D Res=... among the defines
  for a in "$@"; do case "$a" in Res=*) res="${a#Res=}" ;; esac; done
  echo "render_bands: probe at ${probe_dpi} dpi for $auto bands"
  cp "$piece" "$tmp/${name}.ps"
  DPI="$probe_dpi" OUT="$tmp/probe" ${wrap[@]+"${wrap[@]}"} scripts/render.sh "$@" \
    -D RowTimes=true -D PixSeed=true "$tmp/${name}.ps"
  # cut points, one per line, then the plan on stderr
  cutlist="$(python3 - "$tmp/probe/${name}.log" "$auto" "$page_h" "$dpi" "$probe_dpi" "$res" <<'P'
import sys, re
log, n, page_h, dpi, pdpi = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
res = float(sys.argv[6])
t0, rows = None, []
for line in open(log):
    m = re.match(r"fc-row-t0 (\S+)", line)
    if m: t0 = float(m.group(1))
    m = re.match(r"fc-row (\d+) (\S+)", line)
    if m: rows.append(float(m.group(2)))
if t0 is None or not rows:
    sys.exit("render_bands: no row times in the probe log " + log)
cost = [b - a for a, b in zip([t0] + rows, rows)]
if sum(cost) <= 0: cost = [1.0] * len(cost)   # too fast to time: split rows evenly
ph = len(cost)                               # probe rows (the whole frame)
H = max(1, int(page_h * dpi / 72 * res + 0.5))   # final image rows (fc-render's IH; PostScript rounds halves up)
n = max(1, min(n, H))
cum = [0.0]
for c in cost: cum.append(cum[-1] + c)
total = cum[-1]
def at(y):                                   # work above fraction y of the frame
    x = y * ph; j = min(int(x), ph - 1)
    return cum[j] + (x - j) * cost[j]
cuts, r = [], 0
for k in range(1, n):
    target = total * k / n
    lo, hi = r + 1, H - (n - k)              # leave at least one row per band
    while lo < hi:                           # first row r with at(r/H) >= target
        mid = (lo + hi) // 2
        if at(mid / H) >= target: hi = mid
        else: lo = mid + 1
    r = lo
    cuts.append(r)
scale = (dpi / pdpi) ** 2
edges = [0] + cuts + [H]
sys.stderr.write(f"render_bands: setup (bakes) {t0/1000:.1f} s per band; rows {total/1000:.1f} s at {pdpi:g} dpi,"
                 f" about {total*scale/1000/60:.1f} min at {dpi:g} dpi\n")
for i in range(n):
    w = at(edges[i+1] / H) - at(edges[i] / H)
    sys.stderr.write(f"  band {i}: rows {edges[i]}-{edges[i+1]} ({edges[i+1]-edges[i]}), predicted "
                     f"{(t0 + w*scale)/1000/60:.1f} min\n")
for c in cuts: print(repr(c / H))
P
)"
  read -r -a cuts <<< "$(echo $cutlist)"
fi

edges=(0 ${cuts[@]+"${cuts[@]}"} 1)
echo "render_bands: cuts ${cuts[*]-}"
pids=()
for ((i = 0; i < ${#edges[@]} - 1; i++)); do
  band="$tmp/${name}_band$i.ps"
  cp "$piece" "$band"
  ${wrap[@]+"${wrap[@]}"} scripts/render.sh "$@" -D PixSeed=true -D "Crop=[0 ${edges[i]} 1 ${edges[i+1]}]" "$band" &
  pids+=($!)
done
failed=0
for p in "${pids[@]}"; do wait "$p" || failed=1; done
[ "$failed" = 0 ] || { echo "render_bands: a band failed; logs in renders/${name}_band*.log" >&2; exit 1; }
python3 - "$name" "$(( $(date +%s) - t_start ))" "${edges[@]}" <<'P'
import sys, re
from PIL import Image
name, wall, edges = sys.argv[1], int(sys.argv[2]), [float(e) for e in sys.argv[3:]]
bands = [Image.open(f"renders/{name}_band{i}.png").convert("RGB") for i in range(len(edges) - 1)]
W, H = bands[0].size
out = Image.new("RGB", (W, H), "white")
for i, b in enumerate(bands):
    # the row fc_render's Crop starts at: PostScript rounds halves up
    y0, y1 = int(edges[i] * H + 0.5), int(edges[i + 1] * H + 0.5)
    out.paste(b.crop((0, y0, W, y1)), (0, y0))
    log = open(f"renders/{name}_band{i}.log").read()
    real = float(re.search(r"^real (\S+)", log, re.M).group(1))
    cpu = float(re.search(r"^user (\S+)", log, re.M).group(1))
    ms = re.search(r"fc-render .* ms (\S+)", log)
    print(f"  band {i}: rows {y0}-{y1}, {real/60:.1f} min wall, {cpu/60:.1f} min CPU"
          + (f" (setup {cpu/60 - float(ms.group(1))/60000:.1f})" if ms else ""))
out.save(f"renders/{name}.png")
print(f"render_bands: wrote renders/{name}.png ({W}x{H}, {len(bands)} bands, {wall/60:.1f} min wall)")
P
