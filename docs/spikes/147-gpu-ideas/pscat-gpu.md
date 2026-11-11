# GPU approaches for kernelimage: a hand-off for the pscat GPU session

From the fractal_clouds Claude Code session, 2026-11-11 (ArtColony/fractal_clouds#147).
For people, the same material is in `index.html` next to this file.

**What this is.** The kernelimage field report (`docs/spikes/117-kernelimage/index.html`) says why the GPU preview path was parked for fractal_clouds, and lists approaches nobody tried. This note tests the ones that can be tested outside pscat, with a small standalone proof of concept, and maps the results onto pscat's code.

Nothing here asks you to start work. The owner decides when (#1101 came first, and it is done). Everything below is for when the GPU path is picked up again.

**Paths.**
- pscat checkout: `/Volumes/YOTUO/dev/pscat_gpu` (`feature/compute-kernels`).
- Proof of concept: `spikes/147-gpu-interp/` in the fractal_clouds repo. Every number below is from its `sweep.log` (one run of `sweep.sh`).

## The three walls (from the field report)

1. **Inlining.** `gpu.rs::lower` inlines every `Call`, and gives up past `MAX_INLINED` = 2^20. The six shared-subroutine scenes exceed it.
2. **The Metal compile.** With the WGSL functions kept as calls instead, the Metal compile ran for more than 10 minutes.
3. **naga's WGSL parse** (`Typifier::grow`): 5–12 s per process, paid again by every process. fractal_clouds renders one frame per process.

## What the proof of concept measured

Measured on an Apple M4 (10-core GPU), macOS 15.7.7, with wgpu 30.0.1 and naga 30.0.1 (pscat's versions, and its `Cargo.lock`). Each cold compile uses a new entry-point name, so Metal's system cache can't serve it.

### Straight-line shaders get slower to compile faster than they grow, then the compiler crashes

`gpu-interp-poc straight N R` generates WGSL in the shape `lower` produces: one `var rN: f32` per register, one statement per instruction, and an `if` every 64 instructions. The shaders are synthetic, not gallery kernels.

| instructions | registers | WGSL | naga parse | Metal pipeline (cold) | again (Metal cache hit) | from naga IR (idea B) |
|---:|---:|---:|---:|---:|---:|---:|
| 1,000 | 96 | 29 KB | 1.9 ms | 59 ms | 2.8 ms | 30 ms |
| 4,000 | 96 | 111 KB | 13 ms | 143 ms | 15 ms | 100 ms |
| 16,000 | 96 | 435 KB | 125 ms | 656 ms | 138 ms | 418 ms |
| 64,000 | 96 | 1.7 MB | 1,752 ms | 4,186 ms | 1,802 ms | 2,284 ms |
| 64,000 | 4,608 | 2.2 MB | 1,920 ms | 5,282 ms | 2,002 ms | 3,166 ms |
| 256,000 | 96 | — | — | **Metal: "Compiler encountered an internal error"** | — | — |

- **The parse is superlinear.** From 16k to 64k instructions (4×), the parse grows 14×. It is the same wall as `Typifier::grow` in the report.
- **A Metal cache hit still pays the parse.** The second create of a 64k shader takes 1.8 s, nearly all of it naga parsing WGSL again. Caching alone doesn't remove wall 3.
- **There is a hard ceiling below the gallery's sizes.** Inlined, mountains is 103k instructions and storm 141k. The shared-subroutine scenes pass 2^20. At 256k straight-line instructions, Metal's compiler crashes rather than slowing down. So per-kernel codegen for these scenes needs more than a faster parser: either far smaller shaders or no per-kernel shader at all.

### Idea A: a fixed interpreter shader removes all three walls

`src/wgsl.rs::interpreter` is one WGSL compute shader, about 3.7 KB, that runs a flat bytecode from a storage buffer:
- one thread per pixel, with a `pc` and a 16-deep return stack per thread;
- the instruction is `vec4<u32>` `[op, d, a, b]` with an `IMM` bit, the same 16 bytes as #1101's `L`;
- constants come from a buffer, and noise is one opcode.

The shader never changes, so the kernel's size is only data.

| register file | registers | cold pipeline | warm |
|---|---:|---:|---:|
| `private` array | 128 / 1,024 / 4,608 | 69–103 ms | 0.6 ms |
| `storage` (register-major, coalesced) | 128 / 1,024 / 4,608 | 71–73 ms | 0.6–0.7 ms |

A first run of the sweep measured 63–140 ms cold; its 140 ms was the first compile of the process, while the Metal compiler service started up.

The test program is a synthetic terrain (`prog::terrain`): a ridged-fbm height field, ray-marched at world-scale coordinates (camera near x 2400, z 1800), with the fbm as a called subroutine. It is 270 instructions, 121 registers, and about 6,000 instructions run per pixel. At 1280×800:

| how | time | vs CPU f64 (SAME-LOOK) |
|---|---:|---|
| native WGSL, the program hand-written as one shader | 66–83 ms | 59.3 dB, p99.9 1, mean 0.011 |
| **tiered**: interpreter + the fbm as one native instruction | **125–129 ms** | 59.2 dB |
| interpreter, 128 or 1,024 registers (private or storage) | 425–497 ms | 58.9 dB, p99.9 1, mean 0.012 |
| interpreter, 4,608 registers (private or storage) | 737–831 ms | 58.9 dB |
| interpreter, threadgroup-memory registers (128) | 1,590 ms | 58.9 dB |
| CPU reference: scalar bytecode interpreter, f64, 10 threads | 3,190–3,490 ms (one run 4,190) | (reference) |

What this says:

- **f32 is fine for this kind of picture.** GPU f32 against CPU f64 gives 58.9 dB, well past fractal_clouds' SAME-LOOK bar of 40 dB, even with world coordinates in the thousands. CPU f32 against f64 gives the same 59 dB, so the GPU's own math adds nothing visible.
- **Interpreting costs about 6–8× on the GPU** (425–497 ms against 66–83 ms native). The cost is the per-thread `switch` and its divergence when threads' `pc`s differ, plus register traffic through memory.
- **A big register file costs about 1.6×, not a cliff.** golden_coast-sized files (4.4k) still work, in a private array or a storage buffer. Threadgroup memory is *slower* (1.59 s): 32 KB per 64-thread group limits occupancy. Drop that option.
- **Tiering gets most of the speed back.** Compile only the hot subroutine natively and interpret the rest. Here that is 125–129 ms, within 2× of native and about 3.7× faster than pure interpretation, while the compiled part stays small enough to compile quickly.
  - **It depends on the hot code's share.** The native fbm took over about 86% of the instructions run: 822 per pixel left, from 5,996 (hybrid: 6.74 G/s × 125 ms over 1,024,000 pixels).
  - A kernel whose time is spread thinly gains less. Before trying it, measure each shared subroutine's share of dispatches on the CPU executor.
  - fractal_clouds' noise is PostScript by default (`lib/fc_noise2.ps`/`fc_noise3.ps`, `NativeNoise false`): lattice gathers, not pscat's `gnoise2`/`vnoise2` operators. With `NativeNoise true` (fractal_clouds#16; it changes the look), each noise call is one IR instruction, and on the GPU one native WGSL function. That is the cheapest tiering there is.
- **Against pscat's CPU executor** (a rough comparison, because the instruction sets differ):
  - The interpreter runs about 12.4–14.4 G lane-instructions/s.
  - Build2's executor runs about 12 G useful lane-instructions/s on mountains at 1280×800: 8.13 G 16-lane dispatches × 12.2 active lanes in 8.23 s (`kernel batches:` line).
  - So **on a base M4, a pure interpreter is roughly level with the CPU path**. The GPU only pulls ahead with tiering, with a bigger GPU, or with both devices working together (idea D).

## How idea A and the tiered variant would map onto pscat

This is a sketch to start from, not a decision.

1. **Interpret `Code`, not the IR tree.** `kernel/code.rs` already produces what a GPU interpreter wants: flat 16-byte instructions, nested blocks inline, subroutines placed first, and a constant pool.
   - Either run its structured forms directly, or lower once more to jumps, as the proof of concept does (`Jmp`, `Jz`, `Call`, `Ret`):
     - `If(c, t, e)` becomes a `Jz` over the then-block, plus a `Jmp` over the else-block;
     - `Loop(n)` becomes a backward `Jmp`, and `Break` a `Jmp` to the loop's end;
     - `Call(start, len)` becomes `Call` and `Ret`.
   - Jumps keep the shader's control stack to one return stack.
2. **`L::Ext` and `Gather1`.**
   - The noise and table ops become opcodes over the one f32 buffer that `gpu.rs` already packs (permutation plus tables, `toff`).
   - `Gather1` is an indexed read with a bound check.
   - `Assert`/`Abort` paint magenta, as the preview does now.
3. **Integer registers.** Keep the register file as `u32` bits, and `bitcast` per opcode:
   - `IBin`/`IUn` read `i32`;
   - `Bin`/`Un` read `f32`.

   The preview's current choice of i32 for I64 carries over, and so does its accuracy contract.
4. **The register file.** Use a `private` array sized from `Kernel::nregs` and rounded up to a few buckets (128, 1k, 8k), so there are only three shaders, each compiled once and then cached by Metal. Or use one register-major storage buffer, which costs the same.
5. **Limits.** Keep `LOOP_CAP` as a per-thread fuel count, and keep the per-dispatch `ctl.poll` as `gpu.rs::run` does now.
6. **Tiering (the new idea from this test).**
   - Pick the hot shared subroutines: those called inside loops, or the ones the CPU executor's dispatch counts show as hot.
   - Lower only those to WGSL functions, under a size cap. 16k instructions compiles in about 0.7 s cold, 4k in about 0.14 s.
   - Call them through a `NativeCall(k)` opcode.
   - The interpreter source plus these functions is the per-scene shader. It is small, so it compiles fast, and when the hot code is unchanged it hits the cache.
7. **What to measure first.** mountains and storm (96 registers, no shared subroutines) under `--gpu-preview` at 1280×800:
   - interpreter alone, against build2's 8.2 s for mountains;
   - then tiered.

   Use fractal_clouds' SAME-LOOK metric (`kernels/samelook.py`) against `/interpret`.

## Ideas B, C and D in numbers

- **B: skip the WGSL parse.**
  - Add wgpu's `naga-ir` feature and hand it `ShaderSource::Naga(Cow::Owned(module))`.
  - In the proof of concept that saves exactly the parse: at 64k instructions, 4.19 → 2.28 s cold; at 16k, 0.66 → 0.42 s.
  - Combined with a Metal cache hit, the warm cost drops from about 1.8 s (the parse) to near zero.
  - pscat would build the naga `Module` from `Kernel` directly, instead of formatting WGSL text.
  - It doesn't help with the 256k crash, and naga's validator still runs (10 ms at 64k, which is cheap).
- **C: constants as a table.**
  - With every non-trivial `Op::Imm` read from a buffer, the WGSL depends only on the kernel's shape. A setting or frame-size change then hits the cache.
  - Under idea A this comes free.
  - Sketch: `spikes/147-gpu-interp/samples/idea_c_constants.wgsl`.
- **D: CPU first, GPU joins.**
  - The CPU takes rows from the top and the GPU takes chunks from the bottom once its pipeline is ready, so the compile overlaps the work and a failed or slow compile costs nothing.
  - With the interpreter roughly level with the executor, that alone is about 2×.
  - Mixing exact CPU rows with f32 GPU rows needs an opt-in, because pscat's default stays exact. The 59 dB above suggests no visible seam.
  - Sketch: `spikes/147-gpu-interp/samples/idea_d_cpu_then_gpu.rs`.
- **E (wavefront / multi-pass, #1044) and F (typed integer registers, a long-lived process)** are unchanged from the report and not tested here.

## Limits of this test

- **The program is synthetic.** 270 instructions is far smaller than a gallery kernel. What carries over is that the interpreter's compile cost doesn't depend on size, and that it pays a constant factor per instruction run. Its absolute speed on mountains must be measured in pscat.
- **One machine.** These are base-M4 numbers. A Pro or Max GPU has 2–4× the cores, and the CPU path doesn't scale that way.
- **The same-look check is on this program only.** pscat's tables, tags and integer paths add f32 risks of their own; for example, integers past 2^24 in f32 registers.

## Other known work (for context, not GPU)

From `notes/compute-kernels-handoff.md`:
- **Executor levers:** divergence (about a third of lane-work is masked), move coalescing (about 3%), and `Gather1` still scalar.
- **#1100:** AVX2.
- **Before #1061 merges:** the Codex review, `cargo test --profile ci`, and the owner's merge.
- **New from fractal_clouds:** PSCatLabs/pscat#1102, `kernelarray` (a compiled procedure that fills an array of numbers). fractal_clouds#145 waits on it to move its map bakes, about 16 s on a cache miss, onto kernels.
