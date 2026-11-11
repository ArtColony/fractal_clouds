//! WGSL sources: the fixed interpreter (idea A) in three register-file
//! layouts, and a straight-line generator shaped like pscat's per-kernel
//! lowering (`src/kernel/gpu.rs`, `lower`: one `var rN: f32` per register,
//! one statement per instruction) for the compile-time comparison.

use std::fmt::Write as _;

/// Where the interpreter keeps a pixel's registers.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum RegFile {
    /// `var<private> R: array<f32, N>`: per thread, dynamically indexed, so
    /// the compiler must put it in memory (a stack frame), not registers.
    Private,
    /// One storage buffer, register-major: `RS[r * stride + thread]`, so a
    /// warp's accesses to one register are contiguous (coalesced).
    Storage,
    /// Threadgroup memory, `RW[r * 64 + local]`: on-chip, but 32 KB per
    /// workgroup of 64 threads holds at most 128 f32 registers each.
    Workgroup,
}

impl RegFile {
    pub fn parse(s: &str) -> RegFile {
        match s {
            "private" => RegFile::Private,
            "storage" => RegFile::Storage,
            "workgroup" => RegFile::Workgroup,
            _ => panic!("regfile: private, storage or workgroup"),
        }
    }
}

const INTERP: &str = r#"
struct Params { w: u32, row0: u32, npx: u32, ri: u32, rj: u32, stride: u32, budget: u32, h: u32 }
@group(0) @binding(0) var<uniform> P: Params;
@group(0) @binding(1) var<storage, read> code: array<vec4<u32>>;
@group(0) @binding(2) var<storage, read> K: array<f32>;
@group(0) @binding(3) var<storage, read> perm: array<u32>;
@group(0) @binding(4) var<storage, read_write> outp: array<u32>;
//REGS
var<private> T: u32;
var<private> LID: u32;
const IMM: u32 = 0x80000000u;

fn rd(o: u32) -> f32 {
  if ((o & IMM) != 0u) { return K[o & 0x7fffffffu]; }
  return //RD;
}
fn wr(d: u32, v: f32) { //WR = v; }

fn grad(h: u32, x: f32, y: f32) -> f32 {
  switch (h & 7u) {
    case 0u: { return x; }
    case 1u: { return -x; }
    case 2u: { return y; }
    case 3u: { return -y; }
    case 4u: { return 0.70710678 * (x + y); }
    case 5u: { return 0.70710678 * (-x + y); }
    case 6u: { return 0.70710678 * (x - y); }
    default: { return 0.70710678 * (-x - y); }
  }
}

fn noise2(x: f32, y: f32) -> f32 {
  let x0 = floor(x);
  let y0 = floor(y);
  let ix = u32(i32(x0) & 255);
  let iy = u32(i32(y0) & 255);
  let fx = x - x0;
  let fy = y - y0;
  let u = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0);
  let v = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0);
  let a = perm[ix] + iy;
  let b = perm[ix + 1u] + iy;
  let g00 = grad(perm[a], fx, fy);
  let g10 = grad(perm[b], fx - 1.0, fy);
  let g01 = grad(perm[a + 1u], fx, fy - 1.0);
  let g11 = grad(perm[b + 1u], fx - 1.0, fy - 1.0);
  let l0 = g00 + (g10 - g00) * u;
  let l1 = g01 + (g11 - g01) * u;
  return l0 + (l1 - l0) * v;
}

fn fbm(ax: f32, az: f32) -> f32 {
  var x = ax * (1.0 / 700.0) + 0.31;
  var z = az * (1.0 / 700.0) + -0.17;
  var sum = 0.0;
  var wt = 1.0;
  var amp = 1.0;
  for (var o = 0u; o < 8u; o++) {
    var r = 1.0 - abs(noise2(x, z));
    r = r * r;
    sum = sum + r * wt * amp;
    wt = min(r * 1.8, 1.0);
    let t2 = x * 1.6 + z * 1.2;
    z = z * 1.6 + x * -1.2;
    x = t2 + 3.1;
    amp = amp * 0.5;
  }
  return sum * 210.0 + -40.0;
}

fn b2f(b: bool) -> f32 { return select(0.0, 1.0, b); }

@compute @workgroup_size(64)
fn //ENTRY(@builtin(global_invocation_id) gid: vec3<u32>, @builtin(local_invocation_index) lid: u32) {
  if (gid.x >= P.npx) { return; }
  T = gid.x;
  LID = lid;
  let px = P.row0 * P.w + gid.x;
  wr(P.ri, f32(px % P.w));
  wr(P.rj, f32(px / P.w));
  var pc = 0u;
  var sp = 0u;
  var stack: array<u32, 16>;
  var fuel = P.budget;
  var done = false;
  var col = vec3<f32>(1.0, 0.0, 1.0);
  loop {
    if (fuel == 0u) { col = vec3<f32>(1.0, 0.0, 1.0); break; }
    fuel -= 1u;
    let c = code[pc];
    pc += 1u;
    switch c.x {
      case 0u: { done = true; }
      case 1u: { wr(c.y, rd(c.z)); }
      case 2u: { wr(c.y, rd(c.z) + rd(c.w)); }
      case 3u: { wr(c.y, rd(c.z) - rd(c.w)); }
      case 4u: { wr(c.y, rd(c.z) * rd(c.w)); }
      case 5u: { wr(c.y, rd(c.z) / rd(c.w)); }
      case 6u: { wr(c.y, min(rd(c.z), rd(c.w))); }
      case 7u: { wr(c.y, max(rd(c.z), rd(c.w))); }
      case 8u: { wr(c.y, b2f(rd(c.z) < rd(c.w))); }
      case 9u: { wr(c.y, b2f(rd(c.z) <= rd(c.w))); }
      case 10u: { wr(c.y, b2f(rd(c.z) > rd(c.w))); }
      case 11u: { wr(c.y, b2f(rd(c.z) >= rd(c.w))); }
      case 12u: { wr(c.y, b2f(rd(c.z) == rd(c.w))); }
      case 13u: { wr(c.y, floor(rd(c.z))); }
      case 14u: { wr(c.y, sqrt(rd(c.z))); }
      case 15u: { wr(c.y, sin(rd(c.z))); }
      case 16u: { wr(c.y, cos(rd(c.z))); }
      case 17u: { wr(c.y, abs(rd(c.z))); }
      case 18u: { wr(c.y, -rd(c.z)); }
      case 20u: { wr(c.y, noise2(rd(c.z), rd(c.w))); }
      case 21u: { pc = c.y; }
      case 22u: { if (rd(c.z) == 0.0) { pc = c.y; } }
      case 23u: { stack[sp & 15u] = pc; sp += 1u; pc = c.y; }
      case 24u: { sp -= 1u; pc = stack[sp & 15u]; }
      case 25u: { col = vec3<f32>(rd(c.y), rd(c.z), rd(c.w)); }
      case 26u: { wr(c.y, fbm(rd(c.z), rd(c.w))); }
      default: { done = true; }
    }
    if (done) { break; }
  }
  let q = vec3<u32>(round(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)) * 255.0));
  outp[px] = q.x | (q.y << 8u) | (q.z << 16u) | (255u << 24u);
}
"#;

/// The interpreter for a register file of `nregs` registers. `entry` names
/// the entry point: a new name makes a new MSL source, so Metal's system
/// shader cache can't serve it (a cold compile).
pub fn interpreter(file: RegFile, nregs: u32, entry: &str) -> String {
    let (decl, rd, wr) = match file {
        RegFile::Private => (format!("var<private> R: array<f32, {nregs}>;"), "R[o]", "R[d]"),
        RegFile::Storage => (
            "@group(0) @binding(5) var<storage, read_write> RS: array<f32>;".to_string(),
            "RS[o * P.stride + T]",
            "RS[d * P.stride + T]",
        ),
        RegFile::Workgroup => {
            assert!(nregs * 64 * 4 <= 32768, "workgroup registers: at most 128 per thread");
            (format!("var<workgroup> RW: array<f32, {}>;", nregs * 64), "RW[o * 64u + LID]", "RW[d * 64u + LID]")
        }
    };
    INTERP
        .replace("//REGS", &decl)
        .replace("//RD", rd)
        .replace("//WR", wr)
        .replace("//ENTRY", entry)
}

/// A straight-line shader of `n` instructions over `nregs` registers, in
/// the shape pscat's per-kernel lowering produces: every register a `var`,
/// every instruction a statement, an `if` every 64 instructions. Synthetic
/// (not a gallery kernel), for timing parse, validation and the Metal
/// compile against size.
pub fn straight(n: usize, nregs: usize, entry: &str) -> String {
    let mut s = String::new();
    s.push_str("@group(0) @binding(0) var<storage, read_write> outp: array<f32>;\n");
    s.push_str("@compute @workgroup_size(64)\n");
    let _ = writeln!(s, "fn {entry}(@builtin(global_invocation_id) gid: vec3<u32>) {{");
    let _ = writeln!(s, "  var r0: f32 = f32(gid.x);");
    for r in 1..nregs {
        let _ = writeln!(s, "  var r{r}: f32 = 0.0;");
    }
    let mut open = false;
    for k in 0..n {
        let d = (k * 7 + 3) % nregs;
        let a = (k * 13 + 1) % nregs;
        let b = (k * 29 + 5) % nregs;
        if k % 64 == 0 {
            if open {
                s.push_str("  }\n");
            }
            let _ = writeln!(s, "  if (r{a} < r{b}) {{");
            open = true;
        }
        let _ = match k % 6 {
            0 => writeln!(s, "  r{d} = r{a} + r{b};"),
            1 => writeln!(s, "  r{d} = r{a} * 0.9990234;"),
            2 => writeln!(s, "  r{d} = min(r{a}, r{b});"),
            3 => writeln!(s, "  r{d} = r{a} - r{b} * 1.0009766;"),
            4 => writeln!(s, "  r{d} = select(r{a}, r{b}, r{a} > 0.5);"),
            _ => writeln!(s, "  r{d} = floor(r{a}) + 0.25;"),
        };
    }
    if open {
        s.push_str("  }\n");
    }
    s.push_str("  outp[gid.x] = 0.0");
    for r in 0..nregs.min(16) {
        let _ = write!(s, " + r{r}");
    }
    s.push_str(";\n}\n");
    s
}
