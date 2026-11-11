# gpu-interp-poc (fractal_clouds#147)

A proof of concept for **idea A** from the kernelimage field report
(`docs/spikes/117-kernelimage/`): run kernels on the GPU through **one fixed
interpreter shader** that reads a flat bytecode from a buffer, instead of
generating, parsing and compiling a new WGSL shader for every kernel. It
also times **idea B** (hand wgpu a naga module, so the WGSL parse is skipped).

The results and what they mean are in `docs/spikes/147-gpu-ideas/`
(`index.html` for people, `pscat-gpu.md` for the pscat GPU session).

This is a standalone crate. Nothing in the repo builds or runs it, and CI
ignores it.

## What is here

- `src/prog.rs`: the bytecode (16-byte `[op, d, a, b]` instructions with an
  `IMM` bit on operands, as pscat's #1101 lowered form `L` in
  `src/kernel/code.rs`), a builder, a CPU reference interpreter (f64, or
  rounded to f32), and the synthetic **terrain** program: a ridged-fbm height
  field ray-marched at world-scale coordinates, with the fbm as a called
  subroutine. It stands in for a gallery scene; it is not one.
- `src/wgsl.rs`: the fixed interpreter in WGSL with three register-file
  layouts (`private`, `storage`, `workgroup`), and a generator for
  straight-line shaders shaped like pscat's per-kernel lowering (one `var`
  per register, one statement per instruction).
- `src/main.rs`: the commands below, and the SAME-LOOK comparison
  (PSNR ≥ 40 dB, p99.9 ≤ 8, mean ≤ 1.5, as `renders/k117b/imgdiff.py`).
- `sweep.sh OUTDIR`: every measurement in the write-up, one `key=value` line
  each, into `OUTDIR/sweep.log`. `sweep.log` here is the run behind the
  write-up.
- `samples/`: sketches (not compiled) for idea C (constants as a table) and
  idea D (CPU first, GPU joins).

## Build and run

It uses pscat's wgpu 30.0.1 and naga 30.0.1, with `Cargo.lock` copied from
pscat's `feature/compute-kernels`, so it builds offline from a cargo cache
that has built pscat. Keep the target directory off the repo:

```sh
export CARGO_TARGET_DIR=/path/on/scratch/gpu-interp-target
cargo build --release --offline
B=$CARGO_TARGET_DIR/release/gpu-interp-poc

$B interp private 128          # compile cost of the fixed interpreter
$B straight 16000 96           # compile cost of a 16k-instruction straight-line shader
$B run 1280 800 storage 4608 8 OUTDIR   # render, compare with the CPU, write PNGs
./sweep.sh OUTDIR              # all of it
```

Each compile is timed cold: every shader gets a new entry-point name, so
Metal's system shader cache can't serve it. Each is then created again to
show the warm, cached cost.
