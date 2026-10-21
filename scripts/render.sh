#!/usr/bin/env bash
# Render gallery pieces with pscat, lint each one, and record how long it took.
#
#   scripts/render.sh                    # every gallery/*.ps
#   scripts/render.sh gallery/foo.ps     # just these
#   DPI=144 scripts/render.sh            # higher resolution (default 72)
#
# Output goes to renders/<name>.png; timings are appended to renders/timings.tsv.
# The page size comes from the piece's %%BoundingBox (default 612x792).
# Exits nonzero if any piece errors.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"   # pieces load (lib/...) relative to the repo root

dpi="${DPI:-72}"
out="renders"
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

if [ $# -gt 0 ]; then
  pieces=("$@")
else
  shopt -s nullglob
  pieces=(gallery/*.ps)
  shopt -u nullglob
  [ ${#pieces[@]} -gt 0 ] || { echo "render: no pieces in gallery/"; exit 0; }
fi

[ -s "$out/timings.tsv" ] || printf 'date\tpiece\tpscat\tdpi\tpage\tseconds\tstatus\n' > "$out/timings.tsv"

failed=0
for ps in "${pieces[@]}"; do
  [ -e "$ps" ] || { echo "render: no such piece: $ps" >&2; failed=1; continue; }
  name="$(basename "$ps" .ps)"
  page="$(awk '/^%%BoundingBox:/ {print $4 "x" $5; exit}' "$ps")"
  page="${page:-612x792}"

  log="$out/$name.log"
  status=ok
  # /usr/bin/time -p writes "real N" to stderr on both macOS and Linux.
  if ! /usr/bin/time -p pscat --page "$page" --dpi "$dpi" --lint --png "$out/$name.png" "$ps" >"$log" 2>&1; then
    status=error
    failed=1
  fi
  secs="$(awk '/^real/ {print $2}' "$log")"
  grep -q 'pscat: lint: clean' "$log" || [ "$status" = error ] || status=lint

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$name" "$have" "$dpi" "$page" "$secs" "$status" >> "$out/timings.tsv"
  printf '%-28s %8ss  %s\n' "$name" "$secs" "$status"
  [ "$status" = ok ] || grep -v -E '^(real|user|sys) |^pscat: wrote ' "$log" | sed 's/^/    /' >&2
done

exit "$failed"
