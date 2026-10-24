#!/usr/bin/env bash
# A framing pass: a fast, low-resolution render with a rule-of-thirds grid
# and the horizon drawn on (lib/fc_frame.ps), to judge a composition before
# paying for detail. Shorthand for `scripts/render.sh --frame`:
#
#   scripts/frame.sh gallery/foo.ps                    # renders/foo-frame.png
#   scripts/frame.sh -D 'LookAt=[190 185]' gallery/foo.ps
#   scripts/frame.sh -D Res=0.25 gallery/foo.ps        # faster still (default 0.5)
exec "$(dirname "$0")/render.sh" --frame "$@"
