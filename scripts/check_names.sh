#!/usr/bin/env bash
# List names that more than one lib/*.ps file assigns with `def`.
# PostScript has no local variables: library procedures keep their
# temporaries in userdict, so two libraries using the same scratch name
# overwrite each other silently whenever one calls into the other.
# Names a piece is meant to share (settings like PixAng, and the terrain
# material hook's Alb KlMul KskyMul KbMul, and the settings and per-pixel
# values fc_landscape.ps sets for the other libraries, such as the ray
# Mx My Mz that fc_water.ps points along a reflection) go in ALLOW.
set -euo pipefail
cd "$(dirname "$0")/.."
ALLOW=" PixAng ErBaked ErBaking ErDelta Alb KlMul KskyMul KbMul CamY FcKey TreeLine TreesOn SkyAmb AmbTop AmbBot Mx My Mz MarchT0 MpX MpZ "

dups=$(for f in lib/*.ps; do
    grep -o '/[A-Za-z][A-Za-z0-9]*' "$f" | sort -u | sed "s|^/||; s|$| $f|"
  done | awk '{n[$1]++; f[$1]=f[$1] " " $2} END {for (k in n) if (n[k] > 1) print k ":" f[k]}' | sort)

# keep only names that are actually def'd (a /Name literal followed by def
# on the same line), and not allowed
status=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  name=${line%%:*}
  case "$ALLOW" in *" $name "*) continue ;; esac
  files=${line#*:}
  defs=0
  for f in $files; do
    grep -q -E "/$name( |\$).*def|/$name exch def" "$f" && defs=$((defs + 1))
  done
  if [ "$defs" -gt 1 ]; then
    echo "check_names: /$name is defined in:$files"
    status=1
  fi
done <<< "$dups"
[ "$status" = 0 ] && echo "check_names: no shared scratch names in lib/"
exit "$status"
