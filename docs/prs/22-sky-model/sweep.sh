#!/usr/bin/env bash
# Time-of-day sweep of gallery/mountains.ps for fractal_clouds#22: the same
# scene with the sun moved round its day (elevation 55 sin(15 (h - 6)),
# azimuth 10 (h - 12) degrees), three low-sun tiles turned so the sun is
# in frame (azimuth 20-30; the view looks along azimuth 10), a moon at
# night, and the exposure opened as a camera would after dark. Everything
# else is the piece's own; the sun, sky, haze and ambient colours follow
# from SunElev alone.
#
#   docs/prs/22-sky-model/sweep.sh              # tiles into renders/sweep22/
#   JOBS=3 WRAP=/path/to/slot.sh docs/prs/22-sky-model/sweep.sh
#   python3 docs/prs/22-sky-model/sheet.py      # then the contact sheet
set -euo pipefail
cd "$(dirname "$0")/../../.."
out="${OUT:-renders/sweep22}"
mkdir -p "$out"
jobs="${JOBS:-3}"

# hour  elev   azim   exposure  moon(elev/azim or -)
tiles='
05:40  -4.8   -63   6.0  -
06:10   1.4   -58   3.0  -
06:25   5.0    20   2.6  -
06:45  10.0    25   2.0  -
07:00  14.2   -50   1.8  -
09:00  38.9   -30   1.6  -
12:00  55.0     0   1.6  -
15:00  38.9    30   1.6  -
17:00  14.2    50   1.8  -
17:30   5.0    30   2.6  -
17:50   1.4    58   3.0  -
18:20  -4.8    63   6.0  -
19:00 -14.0    70   3.0  25/-40
23:00 -55.0   110   3.0  45/10
03:00 -40.0  -110   3.0  20/60
'
pids=()
while read -r hour elev azim expo moon; do
  [ -n "$hour" ] || continue
  name="t${hour/:/}"
  args=(-D "SunElev=$elev" -D "SunAzim=$azim" -D "Exposure=$expo")
  if [ "$moon" != - ]; then
    args+=(-D "MoonElev=${moon%/*}" -D "MoonAzim=${moon#*/}")
  fi
  mkdir -p "$out/$name"
  cp gallery/mountains.ps "$out/$name/$name.ps"
  (
    OUT="$out/$name" ${WRAP:-} scripts/render.sh "${args[@]}" "$out/$name/$name.ps" >/dev/null 2>&1 \
      && cp "$out/$name/$name.png" "$out/$name.png" && echo "$hour done" || echo "$hour FAILED"
  ) &
  pids+=($!)
  if [ ${#pids[@]} -ge "$jobs" ]; then
    wait "${pids[0]}" || true
    pids=("${pids[@]:1}")
  fi
done <<< "$tiles"
wait
