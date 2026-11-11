#!/bin/bash
# sweep.sh OUTDIR: every measurement in docs/spikes/147-gpu-ideas, one
# key=value line each, into OUTDIR/sweep.log (PNGs alongside).
# Build first:  CARGO_TARGET_DIR=... cargo build --release --offline
# B=path/to/gpu-interp-poc overrides the binary.
set -u
out=${1:?OUTDIR}; mkdir -p "$out"
B=${B:-${CARGO_TARGET_DIR:-target}/release/gpu-interp-poc}
log=$out/sweep.log
# a compile that runs past CAP seconds is recorded as a timeout
CAP=${CAP:-900}
lim() { perl -e 'alarm shift; exec @ARGV' "$CAP" "$@" || echo "TIMEOUT or failure (rc=$?) after cap ${CAP}s: $*"; }
{
echo "# $(date) $(sysctl -n machdep.cpu.brand_string) $(sw_vers -productVersion) load $(uptime | sed 's/.*averages: //')"
echo "## fixed interpreter: compile cost (does not depend on the kernel)"
for f in private storage; do for n in 128 1024 4608; do lim "$B" interp $f $n; done; done
lim "$B" interp workgroup 128
echo "## straight-line shaders, pscat's current shape: compile cost against size"
for r in 96 4608; do for n in 1000 4000 16000 64000; do lim "$B" straight $n $r; done; done
lim "$B" straight 256000 96
echo "## the synthetic terrain on the interpreter vs the CPU reference"
for f in private storage; do for n in 128 1024 4608; do lim "$B" run 1280 800 $f $n 8 "$out"; done; done
lim "$B" run 1280 800 workgroup 128 8 "$out"
lim "$B" run 640 400 private 128 8 "$out"
echo "## the same program as a native shader, and tiered (interpreter + the fbm as one native instruction)"
for k in 1 2; do lim "$B" run 1280 800 native 128 8 "$out"; lim "$B" run 1280 800 hybrid 128 8 "$out"; done
echo "# done $(date)"
} 2>&1 | grep -v '^adapter\|^terrain program' | tee "$log"
