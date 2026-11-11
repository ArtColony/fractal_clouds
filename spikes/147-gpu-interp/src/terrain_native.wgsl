// The synthetic terrain (prog::terrain) written directly in WGSL, as a
// compiled per-kernel shader would be: the reference for how much speed the
// fixed interpreter gives up. Same formulas and constants as src/prog.rs.
struct Params { w: u32, row0: u32, npx: u32, ri: u32, rj: u32, stride: u32, budget: u32, h: u32 }
@group(0) @binding(0) var<uniform> P: Params;
@group(0) @binding(3) var<storage, read> perm: array<u32>;
@group(0) @binding(4) var<storage, read_write> outp: array<u32>;

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

fn mixf(a: f32, b: f32, f: f32) -> f32 { return a + (b - a) * f; }

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= P.npx) { return; }
  let px = P.row0 * P.w + gid.x;
  let wf = f32(P.w);
  let hf = f32(P.h);
  let i = f32(px % P.w);
  let j = f32(px / P.w);
  let u = (i + 0.5) * (2.0 / wf) - 1.0;
  let v = ((hf - 0.5 - j) * (2.0 / hf) - 1.0) * (hf / wf);
  var dx = u * 0.55;
  var dy = v * 0.55 - 0.06;
  let inv = 1.0 / sqrt(dx * dx + dy * dy + 1.0);
  dx = dx * inv;
  dy = dy * inv;
  let dz = inv;
  var t = 2.0;
  var hit = false;
  var px3 = vec3<f32>(0.0);
  var hres = 0.0;
  for (var s = 0; s < 260; s++) {
    px3 = vec3<f32>(dx * t + 2400.5, dy * t + 230.0, dz * t + 1800.25);
    hres = fbm(px3.x, px3.z);
    if (px3.y < hres) { hit = true; break; }
    t = t + max((px3.y - hres) * 0.35, t * 0.002 + 0.5);
    if (t > 3500.0) { break; }
  }
  var col: vec3<f32>;
  if (hit) {
    let h0 = hres;
    let h1 = fbm(px3.x + 1.5, px3.z);
    let h2 = fbm(px3.x, px3.z + 1.5);
    let n = vec3<f32>(h0 - h1, 1.5, h0 - h2) / sqrt((h0 - h1) * (h0 - h1) + (h0 - h2) * (h0 - h2) + 2.25);
    let diff = max(n.x * 0.6 + n.y * 0.7 + n.z * -0.38, 0.0);
    let g = clamp((n.y - 0.78) * 6.0, 0.0, 1.0);
    let sn = clamp((h0 - 220.0) * (1.0 / 40.0), 0.0, 1.0) * n.y;
    let lit = diff * 0.85 + 0.22;
    let fog = t / (t + 1400.0);
    let rock = vec3<f32>(0.42, 0.38, 0.34);
    let grass = vec3<f32>(0.25, 0.36, 0.17);
    let snow = vec3<f32>(0.92, 0.94, 0.97);
    let haze = vec3<f32>(0.70, 0.78, 0.88);
    let base = mix(mix(rock, grass, g), snow, sn);
    col = mix(base * lit, haze, fog);
  } else {
    let f = clamp(dy * 3.0, 0.0, 1.0);
    col = mix(vec3<f32>(0.70, 0.78, 0.88), vec3<f32>(0.30, 0.48, 0.78), f);
  }
  let q = vec3<u32>(round(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)) * 255.0));
  outp[px] = q.x | (q.y << 8u) | (q.z << 16u) | (255u << 24u);
}
