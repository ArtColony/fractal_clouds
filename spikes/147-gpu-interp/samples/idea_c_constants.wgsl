// Idea C (fractal_clouds#147): constants as a table, so the shader text stops
// changing when only settings change. A SKETCH of pscat's per-kernel lowering
// (src/kernel/gpu.rs, `lower`), not compiled.
//
// Today every Op::Imm is written into the WGSL as a literal. Two renders of
// one scene that differ only in a setting (Seed, Yaw, a colour, the frame
// size baked into FrDu/PixAng) give different text, so neither wgpu nor
// Metal's system shader cache can reuse the compile.

// ---- before: the setting is in the text
//   r17 = r12 * 0.0015625;          // FrDu = 2 / IW, at IW = 1280
//   r18 = r17 + 431.25;             // a camera coordinate

// ---- after: one f32 table per kernel, indexed by the constant's slot
@group(0) @binding(3) var<storage, read> KC: array<f32>;
//   r17 = r12 * KC[41];             // slot 41 holds 0.0015625 this run
//   r18 = r17 + KC[42];
//
// The text now depends only on the kernel's *shape*. Key a cache by a hash
// of the text: a setting change or a new frame size hits it and skips parse
// + validate + Metal compile entirely.
//
// Costs and limits:
// - A literal lets the compiler fold (x * 1.0, x + 0.0, select on a known
//   bool); a table read can't. Keep literals for 0, 1, 0.5, 2 and the like:
//   they rarely encode a setting, and folding them matters.
// - A setting that changes control flow (an `if` on a constant, a loop
//   count) is folded away by pscat's compiler before lowering, so it still
//   changes the shape. That is right: those really are different kernels.
// - Under idea A (the fixed interpreter) this is free: constants are
//   already a buffer (`K` in src/wgsl.rs), and the shader never changes.
