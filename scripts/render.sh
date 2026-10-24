#!/usr/bin/env bash
# Render gallery pieces with pscat, lint each one, and record how long it took.
#
#   scripts/render.sh                    # every gallery/*.ps
#   scripts/render.sh gallery/foo.ps     # just these
#   DPI=144 scripts/render.sh            # higher resolution (default 72)
#   OUT=renders/x scripts/render.sh      # write into another directory
#   scripts/render.sh -D Res=0.25 -D Seed=3 gallery/foo.ps
#                                        # predefine /Res 0.25 and /Seed 3 (pieces
#                                        # opt in with `/Name where { pop } {...} ifelse`)
#   scripts/render.sh --frame gallery/foo.ps
#                                        # framing pass: Res 0.5, no AA, with a thirds
#                                        # grid and the horizon drawn on (lib/fc_frame.ps);
#                                        # writes renders/foo-frame.png
#   scripts/render.sh --sweep Seed=1:9 gallery/foo.ps
#                                        # contact sheet: one frame per value at Res 0.25,
#                                        # each labelled, composited into
#                                        # renders/foo-sweep.png (frames foo-sweep-NNN.png)
#   scripts/render.sh --sweep-seed 1:9 ...   # pscat's own seed sweep: every srand call
#                                        # gets the value (the noises, trees, erosion,
#                                        # jitter); sweep Seed for frames a piece can name
#   --grid 3x3                           # the contact sheet's columns x rows
#                                        # (a -D of the swept name is defined after
#                                        # pscat's sweep value, so it overrides the
#                                        # sweep: every frame gets the -D value)
#
# Output goes to renders/<name>.png (or $OUT/<name>.png); timings are appended
# to timings.tsv in the same directory.
# The page size comes from the piece's %%BoundingBox (default 612x792).
# Exits nonzero if any piece errors.
set -euo pipefail

# the whole script is one function, called on the last line, so bash has
# read all of it before it runs: editing render.sh while a render is in
# flight can't change what that run does
main() {
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"   # pieces load (lib/...) relative to the repo root

dpi="${DPI:-72}"
out="${OUT:-renders}"
mkdir -p "$out"

if ! command -v pscat >/dev/null 2>&1; then
  echo "render: pscat not found on PATH; see README.md" >&2
  exit 2
fi

want="$(cat .pscat-version)"
have="$(pscat --version | awk '{print $2}')"
if [ "$want" != "$have" ]; then
  echo "render: warning: pscat $have installed, repo pins $want (.pscat-version)" >&2
fi

# A repo lib/ file with the same name as one of pscat's own would silently
# replace it, since pscat looks next to the current directory before its
# compiled-in copy. Refuse instead.
bundle_lib="$(dirname "$(realpath "$(command -v pscat)")")/lib"
if [ -d "$bundle_lib" ]; then
  for f in lib/*.ps; do
    [ -e "$f" ] || continue
    if [ -e "$bundle_lib/$(basename "$f")" ]; then
      echo "render: $f shadows pscat's built-in lib/$(basename "$f"); rename it" >&2
      exit 2
    fi
  done
fi

defs=""
frame=0
sweep=()      # extra pscat arguments for a sweep
sweepname=""
grid=()
while [ $# -gt 0 ]; do
  case "$1" in
    --frame) frame=1; shift ;;
    --sweep|--sweep-seed|--grid|-D)
      [ $# -ge 2 ] || { echo "render: $1 needs a value" >&2; exit 2; }
      case "$1" in
        -D) defs="$defs /${2%%=*} ${2#*=} def" ;;
        --sweep) sweep=(--sweep "$2"); sweepname="${2%%=*}" ;;
        --sweep-seed) sweep=(--sweep-seed "$2"); sweepname="" ;;
        --grid) grid=(--grid "$2") ;;
      esac
      shift 2 ;;
    -D*) d="${1#-D}"; defs="$defs /${d%%=*} ${d#*=} def"; shift ;;
    *) break ;;
  esac
done

# a framing pass or a sweep is a quick look: low Res unless the caller set it
# (-D defines come after these, and a swept Res or AA is defined before them),
# and the overlays from lib/fc_frame.ps, loaded ahead of the piece
suffix=""
pre=""
if [ ${#sweep[@]} -gt 0 ]; then
  suffix="-sweep"
  pre="$pre /Res where { pop } { /Res 0.25 def } ifelse"
  [ -z "$sweepname" ] || pre="$pre /FrameLabel /$sweepname def"
fi
if [ "$frame" = 1 ]; then
  [ -n "$suffix" ] || suffix="-frame"
  pre="$pre /Res where { pop } { /Res 0.5 def } ifelse"
  pre="$pre /AA where { pop } { /AA false def } ifelse"
  pre="$pre /FrameGrid true def"
fi
if [ -n "$pre" ]; then
  defs="$pre (lib/fc_frame.ps) run$defs"
fi

if [ $# -gt 0 ]; then
  pieces=("$@")
else
  shopt -s nullglob
  pieces=(gallery/*.ps)
  shopt -u nullglob
  [ ${#pieces[@]} -gt 0 ] || { echo "render: no pieces in gallery/"; exit 0; }
fi

[ -s "$out/timings.tsv" ] || printf 'date\tpiece\tpscat\tdpi\tpage\tseconds\tstatus\tdefines\n' > "$out/timings.tsv"

failed=0
for ps in "${pieces[@]}"; do
  [ -e "$ps" ] || { echo "render: no such piece: $ps" >&2; failed=1; continue; }
  name="$(basename "$ps" .ps)$suffix"
  page="$(awk '/^%%BoundingBox:/ {print $4 "x" $5; exit}' "$ps")"
  page="${page:-612x792}"

  log="$out/$name.log"
  status=ok
  # /usr/bin/time -p writes "real N" to stderr on both macOS and Linux.
  # with defines, feed `defs (piece) run` on stdin so the piece sees them
  if [ -n "$defs" ]; then src=-; else src="$ps"; fi
  if [ ${#sweep[@]} -gt 0 ]; then
    # pscat writes the frames as $name-001.png ... and composites them;
    # it refuses --lint with a sweep, so a sweep isn't linted
    lint=()
    outargs=("${sweep[@]}" ${grid[@]+"${grid[@]}"} --png "$out/$name.png" --contact-sheet "$out/$name.png")
  else
    lint=(--lint)
    outargs=(--png "$out/$name.png")
  fi
  if ! printf '%s (%s) run\n' "$defs" "$ps" | /usr/bin/time -p pscat --page "$page" --dpi "$dpi" ${lint[@]+"${lint[@]}"} "${outargs[@]}" "$src" >"$log" 2>&1; then
    status=error
    failed=1
  fi
  secs="$(awk '/^real/ {print $2}' "$log")"
  [ ${#lint[@]} -eq 0 ] || grep -q 'pscat: lint: clean' "$log" || [ "$status" = error ] || status=lint

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$name" "$have" "$dpi" "$page" "$secs" "$status" "${defs# }" >> "$out/timings.tsv"
  printf '%-28s %8ss  %s\n' "$name" "$secs" "$status"
  [ "$status" = ok ] || { grep -v -E '^(real|user|sys) |^pscat: wrote ' "$log" || true; } | sed 's/^/    /' >&2
done

exit "$failed"
}
main "$@"
