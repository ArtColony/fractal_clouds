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
# estimated work. N defaults to the number of cores. The probe needs the
# same defines as the real render (bake sizes above all) for its profile
# to be representative.
#
# The bake cache (lib/fc_cache.ps) is on here unless BAKE_CACHE=0: the
# probe (or, with hand cuts, a tiny priming render at PRIME_DPI, default 9)
# bakes the erosion and forest once and files them in renders/cache/, and
# every band reads them back instead of baking them again. With
# BAKE_CACHE=0 each band pays the setup (the bakes) itself; that cost is
# the same for every band, so it doesn't move the cuts, but it is in the
# predicted band times and it is why more bands than cores never pays. Cuts land on whole rows of the final image
# (of fc-render's image, which with -D Res=0.5 has half the rows; keep Res
# at 1 or 1/k for bands, or the band edges fall between device rows).
#
# Hand cuts are fractions of the frame from the top: put more of them where
# rows are expensive. Defines after `--` go to every band (and the probe).
#
# Every band runs with /PixSeed true (lib/fc_render.ps): the random stream
# is reseeded per pixel and each band first computes the depth keys of the
# row above it, so the stitched picture is the same, byte for byte, whatever
# the cuts, and the same as one uncropped render with -D PixSeed=true. Since
# #27 nothing in a pixel draws on the random stream (the cloud-march jitter
# is a blue-noise tile at the pixel), so that is also the same as a plain
# render.sh run of the whole frame.
#
# A render pass (lib/fc_passes.ps) after `--`, as `--pass mask` or
# `-D Pass=/mask`, goes to every band and names the result
# renders/<name>-mask.png, so it doesn't overwrite the picture. OUT, as for
# render.sh, puts the bands and the stitched image in another directory.
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
out="${OUT:-renders}"
# a pass among the defines: always hand it to render.sh as --pass, which
# puts it in the file names (a bare -D Pass=... would not)
pass="" args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pass) [ $# -ge 2 ] || { echo "render_bands: --pass needs a value" >&2; exit 2; }; pass="$2"; shift 2 ;;
    -D) if [[ "${2:-}" == Pass=* ]]; then pass="${2#Pass=}"; pass="${pass#/}"; else args+=("$1" "${2:-}"); fi; shift 2 ;;
    -DPass=*) pass="${1#-DPass=}"; pass="${pass#/}"; shift ;;
    *) args+=("$1"); shift ;;
  esac
done
sfx=""
if [ -n "$pass" ] && [ "$pass" != beauty ]; then
  args+=(--pass "$pass"); sfx="-$pass"
fi
set -- ${args[@]+"${args[@]}"}
dpi="${DPI:-72}"
page_h="$(awk '/^%%BoundingBox:/ {print $5; exit}' "$piece")"
page_h="${page_h:-792}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
wrap=()
[ -z "${BAND_WRAP:-}" ] || read -r -a wrap <<< "$BAND_WRAP"
t_start=$(date +%s)
export BAKE_CACHE="${BAKE_CACHE:-1}"

if [ -n "$auto" ]; then
  probe_dpi="${PROBE_DPI:-$(python3 -c "import sys; print(max(18, float(sys.argv[1]) / 8))" "$dpi")}"
  res=1                                    # the last -D Res=... among the defines
  for a in "$@"; do case "$a" in Res=*) res="${a#Res=}" ;; -DRes=*) res="${a#-DRes=}" ;; esac; done
  [[ "$res" =~ ^[0-9]*\.?[0-9]+$ ]] || { echo "render_bands: --auto needs Res as a plain number, not $res" >&2; exit 2; }
  echo "render_bands: probe at ${probe_dpi} dpi for $auto bands"
  cp "$piece" "$tmp/${name}.ps"
  DPI="$probe_dpi" OUT="$tmp/probe" ${wrap[@]+"${wrap[@]}"} scripts/render.sh "$@" \
    -D RowTimes=true -D PixSeed=true "$tmp/${name}.ps"
  # cut points, one per line, then the plan on stderr
  cutlist="$(python3 - "$tmp/probe/${name}${sfx}.log" "$auto" "$page_h" "$dpi" "$probe_dpi" "$res" "$BAKE_CACHE" <<'P'
import sys, re
log, n, page_h, dpi, pdpi = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
res = float(sys.argv[6])
cached = sys.argv[7] != "0"
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
H = max(1, int(page_h * dpi / 72 * res + 0.5))   # final image rows (IH in fc-render; PostScript rounds halves up)
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
sys.stderr.write(f"render_bands: setup (bakes) {t0/1000:.1f} s"
                 + (" in the probe, read back from renders/cache/ by the bands" if cached else " per band")
                 + f"; rows {total/1000:.1f} s at {pdpi:g} dpi, about {total*scale/1000/60:.1f} min at {dpi:g} dpi\n")
setup = 0 if cached else t0
for i in range(n):
    w = at(edges[i+1] / H) - at(edges[i] / H)
    sys.stderr.write(f"  band {i}: rows {edges[i]}-{edges[i+1]} ({edges[i+1]-edges[i]}), predicted "
                     f"{(setup + w*scale)/1000/60:.1f} min\n")
for c in cuts: print(repr(c / H))
P
)"
  read -r -a cuts <<< "$(echo $cutlist)"
fi

edges=(0 ${cuts[@]+"${cuts[@]}"} 1)
if [ -z "$auto" ] && [ "$BAKE_CACHE" != 0 ]; then
  # hand cuts: no probe has baked yet, so bake once in a tiny render first
  echo "render_bands: priming the bake cache at ${PRIME_DPI:-9} dpi"
  cp "$piece" "$tmp/${name}.ps"
  DPI="${PRIME_DPI:-9}" OUT="$tmp/prime" ${wrap[@]+"${wrap[@]}"} scripts/render.sh "$@" \
    -D PixSeed=true "$tmp/${name}.ps"
fi
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
[ "$failed" = 0 ] || { echo "render_bands: a band failed; logs in $out/${name}_band*${sfx}.log" >&2; exit 1; }
python3 - "$out" "$name" "$sfx" "$(( $(date +%s) - t_start ))" "${edges[@]}" <<'P'
import sys, re
from PIL import Image
out_dir, name, sfx, wall = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
edges = [float(e) for e in sys.argv[5:]]
bands = [Image.open(f"{out_dir}/{name}_band{i}{sfx}.png").convert("RGB") for i in range(len(edges) - 1)]
W, H = bands[0].size
out = Image.new("RGB", (W, H), "white")
for i, b in enumerate(bands):
    # the row fc_render's Crop starts at: PostScript rounds halves up
    y0, y1 = int(edges[i] * H + 0.5), int(edges[i + 1] * H + 0.5)
    out.paste(b.crop((0, y0, W, y1)), (0, y0))
    log = open(f"{out_dir}/{name}_band{i}{sfx}.log").read()
    real = float(re.search(r"^real (\S+)", log, re.M).group(1))
    cpu = float(re.search(r"^user (\S+)", log, re.M).group(1))
    ms = re.search(r"fc-render .* ms (\S+)", log)
    print(f"  band {i}: rows {y0}-{y1}, {real/60:.1f} min wall, {cpu/60:.1f} min CPU"
          + (f" (setup {cpu/60 - float(ms.group(1))/60000:.1f})" if ms else ""))
out.save(f"{out_dir}/{name}{sfx}.png")
print(f"render_bands: wrote {out_dir}/{name}{sfx}.png ({W}x{H}, {len(bands)} bands, {wall/60:.1f} min wall)")
P
