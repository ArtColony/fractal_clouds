#!/usr/bin/env bash
# Pixel-regression check: render every gallery piece cheaply, plus a few
# full-detail crops, and compare them with reference renders pixel for pixel.
#
#   scripts/regress.sh                  # against tests/regress/linux/ (on Linux)
#   scripts/regress.sh --ref main       # against main, rendered here in a git worktree
#   scripts/regress.sh --update         # rewrite tests/regress/linux/ (on Linux)
#   scripts/regress.sh --docker [...]   # run in a Linux container with the pinned pscat
#   scripts/regress.sh mountains alpine_forest_crop   # only these cases
#
# The stored references are Linux renders: the macOS libm rounds a few
# results (atan, exp) differently in the last bit, and the erosion and noise
# grow that into visibly different pixels, so a Mac never matches them
# (docs/pscat-issues.md). On a Mac use --ref, or --docker to check or update
# the references. Linux arm64 and x86_64 renders match each other.
#
# Every render goes through scripts/render.sh. Renders, logs and diff images
# (reference | new | changed pixels in red) go to renders/regress/. Exits 1
# if any case changed, has no reference, failed or didn't lint clean. Run
# one at a time: every run reuses renders/regress/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

refs="tests/regress/linux"
cheap="ErN=256;ErDrops=20000"
# name|piece|defines (;-separated, on top of $cheap); every gallery piece at
# Res 0.5, then the full-detail crops
cases() {
  for p in gallery/*.ps; do
    echo "$(basename "$p" .ps)|$p|Res=0.5"
  done
  echo "alpine_forest_crop|gallery/alpine_forest.ps|Crop=[0.35 0.72 0.5 0.86]"
}

mode=stored ref="" docker=0 only=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) mode=ref; ref="$2"; shift 2 ;;
    --update) mode=update; shift ;;
    --docker) docker=1; shift ;;
    -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "regress: unknown option $1" >&2; exit 2 ;;
    *) only+=("$1"); shift ;;
  esac
done

if [ "$docker" = 1 ]; then
  [ "$mode" != ref ] || { echo "regress: --ref runs on the host; drop --docker" >&2; exit 2; }
  v="$(cat .pscat-version)"
  case "$(uname -m)" in arm64|aarch64) arch=aarch64 ;; *) arch=x86_64 ;; esac
  t="pscat-$v-$arch-unknown-linux-musl"
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/fractal_clouds"
  if [ ! -x "$cache/$t/pscat" ]; then
    mkdir -p "$cache"
    dl="$(mktemp -d)"
    gh release download "v$v" -R PSCatLabs/pscat -p "$t.tar.gz" -p SHA256SUMS -D "$dl"
    (cd "$dl" && shasum -a 256 -c SHA256SUMS --ignore-missing)
    tar xzf "$dl/$t.tar.gz" -C "$cache"
    rm -rf "$dl"
  fi
  args=()
  [ "$mode" = update ] && args+=(--update)
  args+=(${only[@]+"${only[@]}"})
  exec docker run --rm -e JOBS -v "$root:/w" -v "$cache/$t:/pscat:ro" -w /w alpine:3.20 sh -c '
    apk add -q bash py3-pillow >/dev/null && PATH=/pscat:$PATH bash scripts/regress.sh "$@"
    s=$?; chown -R '"$(id -u):$(id -g)"' renders tests/regress 2>/dev/null; exit $s' regress ${args[@]+"${args[@]}"}
fi

if [ "$mode" != ref ] && [ "$(uname -s)" != Linux ]; then
  echo "regress: the references in $refs are Linux renders and never match $(uname -s);" >&2
  echo "regress: use --ref main, or --docker to check them in a Linux container" >&2
  exit 2
fi

# the cases to run
sel=()
while IFS= read -r c; do
  name="${c%%|*}"
  if [ ${#only[@]} -gt 0 ]; then
    case " ${only[*]} " in *" $name "*) ;; *) continue ;; esac
  fi
  sel+=("$c")
done < <(cases)
[ ${#sel[@]} -gt 0 ] || { echo "regress: no such case: ${only[*]}" >&2; exit 2; }

out="$root/renders/regress"
rm -rf "$out/new" "$out/old" "$out/diff"
mkdir -p "$out/new"

tmp="$(mktemp -d)"
cleanup() {
  [ -d "$tmp/ref" ] && git -C "$root" worktree remove --force "$tmp/ref" >/dev/null 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT
# on ^C or a kill, stop the renders (this script's process tree only)
# before the worktree goes
killtree() {
  local c
  for c in $(pgrep -P "$1"); do killtree "$c"; done
  kill "$1" 2>/dev/null || true
}
trap 'trap - INT TERM; for c in $(pgrep -P $$); do killtree "$c"; done; exit 130' INT TERM

# render one case from the checkout at $1 into directory $2, via that
# checkout's scripts/render.sh; the piece is copied to <name>.ps so that two
# cases of one piece get their own PNG, and render.sh's exit status goes to
# <name>.rc
render_case() {
  local from="$1" dir="$2" name piece defs d
  IFS='|' read -r name piece defs <<< "$3"
  mkdir -p "$dir/src"
  cp "$from/$piece" "$dir/src/$name.ps"
  local args=()
  IFS=';' read -ra ds <<< "$cheap;$defs"
  for d in "${ds[@]}"; do [ -n "$d" ] && args+=(-D "$d"); done
  local rc=0
  OUT="$dir" "$from/scripts/render.sh" "${args[@]}" "$dir/src/$name.ps" >/dev/null 2>&1 || rc=$?
  echo "$rc" > "$dir/$name.rc"
}

jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
pids=()
spawn() {
  "$@" &
  pids+=($!)
  if [ ${#pids[@]} -ge "$jobs" ]; then
    wait "${pids[0]}" || true
    pids=("${pids[@]:1}")
  fi
}

if [ "$mode" = ref ]; then
  git worktree add --detach "$tmp/ref" "$ref" >/dev/null 2>&1 \
    || { echo "regress: can't check out $ref" >&2; exit 2; }
  # render both sides with this branch's render.sh
  mkdir -p "$tmp/ref/scripts"
  cp scripts/render.sh "$tmp/ref/scripts/render.sh"
  mkdir -p "$out/old"
fi

start=$(date +%s)
for c in "${sel[@]}"; do
  name="${c%%|*}"; piece="${c#*|}"; piece="${piece%%|*}"
  if [ "$mode" = ref ]; then
    if [ -e "$tmp/ref/$piece" ]; then
      spawn render_case "$tmp/ref" "$out/old" "$c"
    fi
  fi
  spawn render_case "$root" "$out/new" "$c"
done
for p in ${pids[@]+"${pids[@]}"}; do wait "$p" || true; done
echo "regress: rendered ${#sel[@]} case(s) in $(( $(date +%s) - start ))s"

names=()
for c in "${sel[@]}"; do names+=("${c%%|*}"); done

if [ "$mode" = update ]; then
  mkdir -p "$refs"
  status=0
  for n in "${names[@]}"; do
    if [ "$(cat "$out/new/$n.rc" 2>/dev/null)" = 0 ] && grep -q 'pscat: lint: clean' "$out/new/$n.log"; then
      cp "$out/new/$n.png" "$refs/$n.png"
      echo "regress: updated $refs/$n.png"
    else
      echo "regress: $n failed or didn't lint clean; see $out/new/$n.log" >&2
      status=1
    fi
  done
  # with no case names given, drop the references of cases that are gone
  if [ ${#only[@]} -eq 0 ]; then
    for f in "$refs"/*.png; do
      [ -e "$f" ] || continue
      case " ${names[*]} " in *" $(basename "$f" .png) "*) ;; *) rm "$f"; echo "regress: removed $f" ;; esac
    done
  fi
  exit "$status"
fi

if [ "$mode" = ref ]; then refdir="$out/old"; label="$ref"; else refdir="$refs"; label="$refs"; fi
check_stale=0
[ "$mode" = stored ] && [ ${#only[@]} -eq 0 ] && check_stale=1

python3 - "$refdir" "$out" "$label" "$check_stale" "${names[@]}" <<'P'
import os, sys
from PIL import Image, ImageChops

refdir, out, label, check_stale, names = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1", sys.argv[5:]
os.makedirs(f"{out}/diff", exist_ok=True)
def rendered(d, n):
    # render.sh exited 0 and pscat wrote the PNG
    rc = open(f"{d}/{n}.rc").read().strip() if os.path.exists(f"{d}/{n}.rc") else ""
    log = open(f"{d}/{n}.log").read() if os.path.exists(f"{d}/{n}.log") else ""
    return rc == "0" and "pscat: wrote" in log and os.path.exists(f"{d}/{n}.png"), log

ref_rendered = refdir == f"{out}/old"   # --ref: the reference side was rendered now too
rows, bad = [], 0
for n in names:
    new_png, ref_png = f"{out}/new/{n}.png", f"{refdir}/{n}.png"
    ok, logtext = rendered(f"{out}/new", n)
    if not ok:
        rows.append((n, "render failed", f"see renders/regress/new/{n}.log")); bad += 1; continue
    note = "" if "pscat: lint: clean" in logtext else "; not lint clean"
    if not os.path.exists(ref_png) and not (ref_rendered and os.path.exists(f"{refdir}/{n}.log")):
        rows.append((n, "no reference", "new case" + note)); bad += 1; continue
    if ref_rendered and not rendered(refdir, n)[0]:
        rows.append((n, "ref failed", f"see renders/regress/old/{n}.log" + note)); bad += 1; continue
    a, b = Image.open(ref_png).convert("RGB"), Image.open(new_png).convert("RGB")
    if a.size != b.size:
        rows.append((n, "changed", f"size {a.size} -> {b.size}" + note)); bad += 1; continue
    d = ImageChops.difference(a, b)
    box = d.getbbox()
    if box is None:
        rows.append((n, "lint" if note else "same", note[2:])); bad += bool(note); continue
    r, g, b2 = d.point(lambda v: 255 if v else 0).split()
    mask = ImageChops.lighter(ImageChops.lighter(r, g), b2)
    changed = mask.histogram()[255]
    biggest = max(hi for lo, hi in d.getextrema())
    # reference | new | the new render dimmed, changed pixels in red
    w, h = a.size
    marked = Image.composite(Image.new("RGB", a.size, (255, 0, 0)),
                             Image.blend(b, Image.new("RGB", a.size), 0.6), mask)
    sheet = Image.new("RGB", (3 * w, h))
    for i, im in enumerate((a, b, marked)):
        sheet.paste(im, (i * w, 0))
    sheet.save(f"{out}/diff/{n}.png")
    rows.append((n, "changed", f"{changed} px ({100 * changed / (w * h):.2f}%), max {biggest}, box {box}, "
                 f"see renders/regress/diff/{n}.png" + note))
    bad += 1
if check_stale:
    for f in sorted(os.listdir(refdir)):
        if f.endswith(".png") and f[:-4] not in names:
            rows.append((f[:-4], "stale reference", "no such case; run --update")); bad += 1

table = [f"Pixel regression against `{label}`", "", "| case | result | detail |", "|---|---|---|"]
table += [f"| {n} | {r} | {d} |" for n, r, d in rows]
print("\n".join(f"{n:22} {r:16} {d}" for n, r, d in rows))
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as s:
        s.write("\n".join(table) + "\n")
print(f"regress: {len(rows) - bad} of {len(rows)} unchanged" if bad else f"regress: all {len(rows)} unchanged")
sys.exit(1 if bad else 0)
P
