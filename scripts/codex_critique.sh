#!/usr/bin/env bash
# Ask Codex to critique renders, as a second pair of eyes on realism and
# aesthetics. The Codex Claude Code plugin can't attach images, so this calls
# the Codex CLI directly: read-only sandbox, high reasoning effort.
#
#   scripts/codex_critique.sh PROMPT_FILE IMAGE...      # critique to stdout
#
# The critique is also saved beside the first image as <image>.critique.md.
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: $0 PROMPT_FILE IMAGE..." >&2; exit 2; }
prompt="$1"; shift
args=()
for img in "$@"; do args+=(-i "$img"); done
out="${1%.*}.critique.md"
# the prompt goes on stdin: -i takes every following argument as an image
codex exec --sandbox read-only --skip-git-repo-check -c model_reasoning_effort=high \
  -o "$out" "${args[@]}" < "$prompt" >/dev/null 2>&1
cat "$out"
