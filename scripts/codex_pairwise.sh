#!/usr/bin/env bash
# Blind pairwise judgment by Codex: is image A or image B more realistic, and
# which is more pleasing? Runs both orders (A,B then B,A) at the same
# reasoning effort, so position bias shows up as a split verdict.
#
#   scripts/codex_pairwise.sh OLD.png NEW.png [OUTDIR]
#
# The images are copied to neutral names, so file names don't leak which is
# which. Prints each order's verdict mapped back to OLD/NEW.
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: $0 OLD.png NEW.png [OUTDIR]" >&2; exit 2; }
old="$1"; new="$2"; out="${3:-$(mktemp -d)}"
mkdir -p "$out"
cat > "$out/prompt.txt" <<'P'
Two procedurally generated renders of a mountain landscape under clouds are attached: the first is image A, the second is image B. Judge them blind, on what you can see, as a landscape photographer would.

Answer exactly in this format, one line each, then at most 5 short bullet points of reasons:
REALISM: A or B (which looks more like a real photograph)
AESTHETICS: A or B (which is the more pleasing image)
P
run() { # first second label
  cp "$1" "$out/image_A.png"; cp "$2" "$out/image_B.png"
  codex exec --sandbox read-only --skip-git-repo-check -c model_reasoning_effort=high \
    -o "$out/$3.txt" -i "$out/image_A.png" -i "$out/image_B.png" < "$out/prompt.txt" >/dev/null 2>&1
}
verdict() { # file A-is B-is
  r=$(grep -m1 -o 'REALISM: *[AB]' "$1" | tail -c 2); a=$(grep -m1 -o 'AESTHETICS: *[AB]' "$1" | tail -c 2)
  [ "$r" = A ] && r=$2 || r=$3; [ "$a" = A ] && a=$2 || a=$3
  echo "realism: $r   aesthetics: $a"
}
run "$old" "$new" order1; run "$new" "$old" order2
echo "order 1 (old shown first): $(verdict "$out/order1.txt" old new)"
echo "order 2 (new shown first): $(verdict "$out/order2.txt" new old)"
echo "reasons in $out/order1.txt and $out/order2.txt"
