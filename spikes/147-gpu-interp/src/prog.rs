//! The bytecode, a builder for it, the synthetic terrain program, and a CPU
//! reference interpreter (f64, or f64 rounded to f32 after every step).
//!
//! The instruction is four u32 words, `[op, d, a, b]`, the same 16 bytes as
//! pscat's #1101 lowered form (`src/kernel/code.rs`, `L`). An operand with
//! [`IMM`] set indexes the constant table instead of the register file, as
//! `code::IMM` does. Unlike `L`, control flow is lowered to jumps (`Jmp`,
//! `Jz`, `Call`, `Ret`), which a GPU interpreter runs with one program
//! counter and a small return stack; `If`/`Loop`/`Break` lower to these
//! mechanically.

pub const IMM: u32 = 1 << 31;

// Opcodes. The WGSL interpreter (`wgsl.rs`) uses the same numbers.
pub const HALT: u32 = 0;
pub const MOV: u32 = 1;
pub const ADD: u32 = 2;
pub const SUB: u32 = 3;
pub const MUL: u32 = 4;
pub const DIV: u32 = 5;
pub const MIN: u32 = 6;
pub const MAX: u32 = 7;
pub const LT: u32 = 8;
pub const LE: u32 = 9;
pub const GT: u32 = 10;
pub const GE: u32 = 11;
pub const EQ: u32 = 12;
pub const FLOOR: u32 = 13;
pub const SQRT: u32 = 14;
pub const SIN: u32 = 15;
pub const COS: u32 = 16;
pub const ABS: u32 = 17;
pub const NEG: u32 = 18;
pub const NOISE2: u32 = 20;
pub const JMP: u32 = 21; // pc = d
pub const JZ: u32 = 22; // if a == 0 { pc = d }
pub const CALL: u32 = 23; // push pc; pc = d
pub const RET: u32 = 24;
pub const OUT: u32 = 25; // colour = (d, a, b), all operands
/// d = fbm(a, b): the hot subroutine as one native instruction (the tiered
/// variant: compile the hot code, interpret the rest).
pub const FBM: u32 = 26;

/// What each field of an instruction holds.
#[derive(Clone, Copy, PartialEq)]
enum F {
    None,
    Reg,
    Operand,
    Target,
}

fn fields(op: u32) -> [F; 3] {
    match op {
        MOV | FLOOR | SQRT | SIN | COS | ABS | NEG => [F::Reg, F::Operand, F::None],
        ADD..=EQ | NOISE2 | FBM => [F::Reg, F::Operand, F::Operand],
        JMP | CALL => [F::Target, F::None, F::None],
        JZ => [F::Target, F::Operand, F::None],
        OUT => [F::Operand, F::Operand, F::Operand],
        _ => [F::None, F::None, F::None],
    }
}

#[derive(Clone)]
pub struct Program {
    pub code: Vec<[u32; 4]>,
    pub consts: Vec<f64>,
    pub nregs: u32,
    /// The registers the interpreter writes the pixel's column and row to.
    pub ri: u32,
    pub rj: u32,
}

impl Program {
    /// Spread the registers over a file of `file` registers (the gallery's
    /// real counts: 96, ~1,000, ~4,400), keeping their order: register v
    /// becomes v * (file / nregs). The program is the same; only the
    /// addresses it touches, and so the register file's footprint, change.
    pub fn spread(&self, file: u32) -> Program {
        assert!(file >= self.nregs, "file smaller than the program's registers");
        let k = file / self.nregs;
        let m = |r: u32| r * k;
        let mut p = self.clone();
        for ins in &mut p.code {
            let f = fields(ins[0]);
            for (slot, kind) in f.iter().enumerate() {
                let w = &mut ins[slot + 1];
                match kind {
                    F::Reg => *w = m(*w),
                    F::Operand if *w & IMM == 0 => *w = m(*w),
                    _ => {}
                }
            }
        }
        p.ri = m(self.ri);
        p.rj = m(self.rj);
        p.nregs = file;
        p
    }
}

/// A label: an index into `Builder::labels`.
#[derive(Clone, Copy)]
pub struct Label(usize);

pub struct Builder {
    code: Vec<[u32; 4]>,
    consts: Vec<f64>,
    nregs: u32,
    labels: Vec<Option<u32>>,
    fixups: Vec<(usize, Label)>,
}

impl Builder {
    pub fn new() -> Self {
        Builder { code: vec![], consts: vec![], nregs: 0, labels: vec![], fixups: vec![] }
    }
    pub fn reg(&mut self) -> u32 {
        self.nregs += 1;
        self.nregs - 1
    }
    /// An immediate operand (deduplicated by bits).
    pub fn k(&mut self, v: f64) -> u32 {
        let i = match self.consts.iter().position(|c| c.to_bits() == v.to_bits()) {
            Some(i) => i,
            None => {
                self.consts.push(v);
                self.consts.len() - 1
            }
        };
        IMM | i as u32
    }
    pub fn emit(&mut self, op: u32, d: u32, a: u32, b: u32) {
        self.code.push([op, d, a, b]);
    }
    /// `d = a op b` into a fresh register.
    pub fn bin(&mut self, op: u32, a: u32, b: u32) -> u32 {
        let d = self.reg();
        self.emit(op, d, a, b);
        d
    }
    /// `d = a op v` with an immediate.
    pub fn bk(&mut self, op: u32, a: u32, v: f64) -> u32 {
        let c = self.k(v);
        self.bin(op, a, c)
    }
    pub fn un(&mut self, op: u32, a: u32) -> u32 {
        let d = self.reg();
        self.emit(op, d, a, 0);
        d
    }
    pub fn set(&mut self, d: u32, a: u32) {
        self.emit(MOV, d, a, 0);
    }
    pub fn setk(&mut self, d: u32, v: f64) {
        let c = self.k(v);
        self.emit(MOV, d, c, 0);
    }
    /// a + (b - a) * f
    pub fn mix(&mut self, a: u32, b: u32, f: u32) -> u32 {
        let d = self.bin(SUB, b, a);
        let d = self.bin(MUL, d, f);
        self.bin(ADD, a, d)
    }
    pub fn clamp01(&mut self, a: u32) -> u32 {
        let d = self.bk(MIN, a, 1.0);
        self.bk(MAX, d, 0.0)
    }
    pub fn label(&mut self) -> Label {
        self.labels.push(None);
        Label(self.labels.len() - 1)
    }
    pub fn place(&mut self, l: Label) {
        self.labels[l.0] = Some(self.code.len() as u32);
    }
    fn jump(&mut self, op: u32, l: Label, a: u32) {
        self.fixups.push((self.code.len(), l));
        self.emit(op, 0, a, 0);
    }
    pub fn jmp(&mut self, l: Label) {
        self.jump(JMP, l, 0)
    }
    pub fn jz(&mut self, cond: u32, l: Label) {
        self.jump(JZ, l, cond)
    }
    pub fn call(&mut self, l: Label) {
        self.jump(CALL, l, 0)
    }
    pub fn finish(mut self, ri: u32, rj: u32) -> Program {
        for (at, l) in std::mem::take(&mut self.fixups) {
            self.code[at][1] = self.labels[l.0].expect("label never placed");
        }
        Program { code: self.code, consts: self.consts, nregs: self.nregs, ri, rj }
    }
}

/// A synthetic stand-in for a fractal_clouds scene: a camera ray marched
/// over a ridged-fbm height field at world-scale coordinates (camera near
/// x 2400, z 1800, as in the gallery's erosion-map area), with the fbm as a
/// shared subroutine called once per march step and twice more for the
/// normal, a slope/height material, a diffuse light and distance fog. It is
/// not a gallery scene and not pscat's IR; it exercises the same kinds of
/// work (noise, a data-dependent loop, calls, divergence).
/// With `native_fbm`, each call of the fbm subroutine is one [`FBM`]
/// instruction instead (8 octaves; the subroutine stays in the code, unused).
pub fn terrain(w: u32, h: u32, octaves: u32, native_fbm: bool) -> Program {
    let mut b = Builder::new();
    let ri = b.reg();
    let rj = b.reg();
    let main = b.label();
    let fbm = b.label();
    // The subroutine's argument and result registers (like PostScript names
    // a procedure reads and defines).
    let ax = b.reg();
    let az = b.reg();
    let hres = b.reg();
    b.jmp(main);

    // ---- fbm: hres = ridged fbm(ax, az); registers reused across octaves
    b.place(fbm);
    let x = b.reg();
    let z = b.reg();
    let sum = b.reg();
    let wt = b.reg();
    let t1 = b.reg();
    let t2 = b.reg();
    let t3 = b.reg();
    let c = b.k(1.0 / 700.0);
    b.emit(MUL, t1, ax, c);
    let c = b.k(0.31);
    b.emit(ADD, x, t1, c);
    let c = b.k(1.0 / 700.0);
    b.emit(MUL, t1, az, c);
    let c = b.k(-0.17);
    b.emit(ADD, z, t1, c);
    b.setk(sum, 0.0);
    b.setk(wt, 1.0);
    for o in 0..octaves {
        b.emit(NOISE2, t1, x, z); // n
        b.emit(ABS, t1, t1, 0);
        let one = b.k(1.0);
        b.emit(SUB, t1, one, t1); // r = 1 - |n|
        b.emit(MUL, t1, t1, t1); // r^2
        b.emit(MUL, t2, t1, wt);
        let amp = b.k(0.5f64.powi(o as i32));
        b.emit(MUL, t2, t2, amp);
        b.emit(ADD, sum, sum, t2);
        let c = b.k(1.8);
        b.emit(MUL, wt, t1, c);
        let one = b.k(1.0);
        b.emit(MIN, wt, wt, one);
        // rotate and scale the domain: (1.6 1.2; -1.2 1.6), plus an offset
        let (c16, c12, cm12) = (b.k(1.6), b.k(1.2), b.k(-1.2));
        b.emit(MUL, t2, x, c16);
        b.emit(MUL, t3, z, c12);
        b.emit(ADD, t2, t2, t3);
        b.emit(MUL, t3, x, cm12);
        b.emit(MUL, z, z, c16);
        b.emit(ADD, z, z, t3);
        let c = b.k(3.1);
        b.emit(ADD, x, t2, c);
    }
    let c = b.k(210.0);
    b.emit(MUL, t1, sum, c);
    let c = b.k(-40.0);
    b.emit(ADD, hres, t1, c);
    b.emit(RET, 0, 0, 0);

    // ---- main
    b.place(main);
    let (wf, hf) = (w as f64, h as f64);
    let u = b.bk(ADD, ri, 0.5);
    let u = b.bk(MUL, u, 2.0 / wf);
    let u = b.bk(SUB, u, 1.0);
    let hm = b.k(hf - 0.5);
    let v = b.bin(SUB, hm, rj);
    let v = b.bk(MUL, v, 2.0 / hf);
    let v = b.bk(SUB, v, 1.0);
    let v = b.bk(MUL, v, hf / wf);
    let dx = b.bk(MUL, u, 0.55);
    let dy = b.bk(MUL, v, 0.55);
    let dy = b.bk(SUB, dy, 0.06);
    let n2 = b.bin(MUL, dx, dx);
    let t = b.bin(MUL, dy, dy);
    let n2 = b.bin(ADD, n2, t);
    let n2 = b.bk(ADD, n2, 1.0);
    let n = b.un(SQRT, n2);
    let one = b.k(1.0);
    let inv = b.bin(DIV, one, n);
    let dx = b.bin(MUL, dx, inv);
    let dy = b.bin(MUL, dy, inv);
    let dz = inv;
    let (ox, oy, oz) = (2400.5, 230.0, 1800.25);
    let tt = b.reg();
    b.setk(tt, 2.0);
    let hit = b.reg();
    b.setk(hit, 0.0);
    let steps = b.reg();
    b.setk(steps, 0.0);
    let px = b.reg();
    let py = b.reg();
    let pz = b.reg();
    let top = b.label();
    let nohit = b.label();
    let cont = b.label();
    let done = b.label();
    let sky = b.label();
    b.place(top);
    let s = b.bin(MUL, dx, tt);
    let c = b.k(ox);
    b.emit(ADD, px, s, c);
    let s = b.bin(MUL, dy, tt);
    let c = b.k(oy);
    b.emit(ADD, py, s, c);
    let s = b.bin(MUL, dz, tt);
    let c = b.k(oz);
    b.emit(ADD, pz, s, c);
    if native_fbm {
        b.emit(FBM, hres, px, pz);
    } else {
        b.set(ax, px);
        b.set(az, pz);
        b.call(fbm);
    }
    let below = b.bin(LT, py, hres);
    b.jz(below, nohit);
    b.setk(hit, 1.0);
    b.jmp(done);
    b.place(nohit);
    let dist = b.bin(SUB, py, hres);
    let st = b.bk(MUL, dist, 0.35);
    let mn = b.bk(MUL, tt, 0.002);
    let mn = b.bk(ADD, mn, 0.5);
    let st = b.bin(MAX, st, mn);
    b.emit(ADD, tt, tt, st);
    let far = b.bk(GT, tt, 3500.0);
    b.jz(far, cont);
    b.jmp(done);
    b.place(cont);
    let c = b.k(1.0);
    b.emit(ADD, steps, steps, c);
    let more = b.bk(LT, steps, 260.0);
    b.jz(more, done);
    b.jmp(top);
    b.place(done);
    b.jz(hit, sky);
    // shade: normal from two more fbm calls
    let h0 = b.reg();
    b.set(h0, hres);
    let e = 1.5;
    let c = b.k(e);
    b.emit(ADD, ax, px, c);
    b.set(az, pz);
    if native_fbm {
        b.emit(FBM, hres, ax, az);
    } else {
        b.call(fbm);
    }
    let h1 = b.reg();
    b.set(h1, hres);
    b.set(ax, px);
    let c = b.k(e);
    b.emit(ADD, az, pz, c);
    if native_fbm {
        b.emit(FBM, hres, ax, az);
    } else {
        b.call(fbm);
    }
    let nx = b.bin(SUB, h0, h1);
    let nz = b.bin(SUB, h0, hres);
    let ee = b.k(e);
    let ny = b.reg();
    b.set(ny, ee);
    let l2 = b.bin(MUL, nx, nx);
    let t = b.bin(MUL, nz, nz);
    let l2 = b.bin(ADD, l2, t);
    let l2 = b.bk(ADD, l2, e * e);
    let l = b.un(SQRT, l2);
    let nx = b.bin(DIV, nx, l);
    let ny = b.bin(DIV, ny, l);
    let nz = b.bin(DIV, nz, l);
    let d1 = b.bk(MUL, nx, 0.6);
    let d2 = b.bk(MUL, ny, 0.7);
    let d3 = b.bk(MUL, nz, -0.38);
    let d = b.bin(ADD, d1, d2);
    let d = b.bin(ADD, d, d3);
    let diff = b.bk(MAX, d, 0.0);
    let g = b.bk(SUB, ny, 0.78);
    let g = b.bk(MUL, g, 6.0);
    let g = b.clamp01(g);
    let sn = b.bk(SUB, h0, 220.0);
    let sn = b.bk(MUL, sn, 1.0 / 40.0);
    let sn = b.clamp01(sn);
    let sn = b.bin(MUL, sn, ny);
    let lit = b.bk(MUL, diff, 0.85);
    let lit = b.bk(ADD, lit, 0.22);
    let fd = b.bk(ADD, tt, 1400.0);
    let fog = b.bin(DIV, tt, fd);
    let mut rgb = [0u32; 3];
    let rock = [0.42, 0.38, 0.34];
    let grass = [0.25, 0.36, 0.17];
    let snow = [0.92, 0.94, 0.97];
    let haze = [0.70, 0.78, 0.88];
    for ch in 0..3 {
        let (r, gr, s, hz) = (b.k(rock[ch]), b.k(grass[ch]), b.k(snow[ch]), b.k(haze[ch]));
        let base = b.mix(r, gr, g);
        let base = b.mix(base, s, sn);
        let col = b.bin(MUL, base, lit);
        rgb[ch] = b.mix(col, hz, fog);
    }
    b.emit(OUT, rgb[0], rgb[1], rgb[2]);
    b.emit(HALT, 0, 0, 0);
    // sky
    b.place(sky);
    let f = b.bk(MUL, dy, 3.0);
    let f = b.clamp01(f);
    let zen = [0.30, 0.48, 0.78];
    for ch in 0..3 {
        let (hz, zn) = (b.k(haze[ch]), b.k(zen[ch]));
        rgb[ch] = b.mix(hz, zn, f);
    }
    b.emit(OUT, rgb[0], rgb[1], rgb[2]);
    b.emit(HALT, 0, 0, 0);
    b.finish(ri, rj)
}

/// A 512-entry (doubled) permutation, from a fixed LCG: the same table on
/// both sides.
pub fn perm() -> Vec<u32> {
    let mut p: Vec<u32> = (0..256).collect();
    let mut s: u64 = 0x2545F4914F6CDD1D;
    for i in (1..256).rev() {
        s = s.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let j = ((s >> 33) % (i as u64 + 1)) as usize;
        p.swap(i, j);
    }
    let mut q = p.clone();
    q.extend_from_slice(&p);
    q.push(p[0]);
    q
}

const R2: f64 = 0.70710678;

fn grad(h: u32, x: f64, y: f64) -> f64 {
    match h & 7 {
        0 => x,
        1 => -x,
        2 => y,
        3 => -y,
        4 => R2 * (x + y),
        5 => R2 * (-x + y),
        6 => R2 * (x - y),
        _ => R2 * (-x - y),
    }
}

/// 2-D gradient noise; the WGSL `noise2` is the same formula in f32.
pub fn noise2(p: &[u32], x: f64, y: f64) -> f64 {
    let (x0, y0) = (x.floor(), y.floor());
    let ix = (x0 as i64 & 255) as usize;
    let iy = (y0 as i64 & 255) as u32;
    let (fx, fy) = (x - x0, y - y0);
    let u = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0);
    let v = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0);
    let a = (p[ix] + iy) as usize;
    let bb = (p[ix + 1] + iy) as usize;
    let g00 = grad(p[a], fx, fy);
    let g10 = grad(p[bb], fx - 1.0, fy);
    let g01 = grad(p[a + 1], fx, fy - 1.0);
    let g11 = grad(p[bb + 1], fx - 1.0, fy - 1.0);
    let l0 = g00 + (g10 - g00) * u;
    let l1 = g01 + (g11 - g01) * u;
    l0 + (l1 - l0) * v
}

/// The fbm subroutine of [`terrain`] (8 octaves) as one function, in the
/// same order of operations, rounding each step with `q`.
fn fbm(p: &[u32], ax: f64, az: f64, q: &dyn Fn(f64) -> f64) -> f64 {
    let mut x = q(q(ax * q(1.0 / 700.0)) + q(0.31));
    let mut z = q(q(az * q(1.0 / 700.0)) + q(-0.17));
    let (mut sum, mut wt) = (0.0, 1.0);
    for o in 0..8 {
        let mut r = q(noise2(p, x, z)).abs();
        r = q(1.0 - r);
        r = q(r * r);
        let t2 = q(q(r * wt) * q(0.5f64.powi(o)));
        sum = q(sum + t2);
        wt = q(r * q(1.8)).min(1.0);
        let t2 = q(q(x * q(1.6)) + q(z * q(1.2)));
        let t3 = q(x * q(-1.2));
        z = q(q(z * q(1.6)) + t3);
        x = q(t2 + q(3.1));
    }
    q(q(sum * 210.0) + -40.0)
}

/// Run `prog` for one pixel. `f32` rounds every result to f32 (the GPU's
/// precision, though not its exact transcendentals). Returns the colour
/// and the number of instructions run.
/// `kc` is the constant table, already rounded when `f32`.
pub fn run_pixel(prog: &Program, kc: &[f64], perm: &[u32], i: u32, j: u32, f32: bool, regs: &mut Vec<f64>) -> ([f64; 3], u64) {
    regs.clear();
    regs.resize(prog.nregs as usize, 0.0);
    let q = |x: f64| if f32 { x as f32 as f64 } else { x };
    regs[prog.ri as usize] = i as f64;
    regs[prog.rj as usize] = j as f64;
    let rd = |regs: &Vec<f64>, o: u32| if o & IMM != 0 { kc[(o & !IMM) as usize] } else { regs[o as usize] };
    let mut pc = 0usize;
    let mut stack = [0usize; 16];
    let mut sp = 0usize;
    let mut col = [1.0, 0.0, 1.0];
    let mut n = 0u64;
    loop {
        let [op, d, a, b] = prog.code[pc];
        pc += 1;
        n += 1;
        let (va, vb) = (|| rd(regs, a), || rd(regs, b));
        let r = match op {
            HALT => break,
            MOV => va(),
            ADD => va() + vb(),
            SUB => va() - vb(),
            MUL => va() * vb(),
            DIV => va() / vb(),
            MIN => va().min(vb()),
            MAX => va().max(vb()),
            LT => (va() < vb()) as u8 as f64,
            LE => (va() <= vb()) as u8 as f64,
            GT => (va() > vb()) as u8 as f64,
            GE => (va() >= vb()) as u8 as f64,
            EQ => (va() == vb()) as u8 as f64,
            FLOOR => va().floor(),
            SQRT => va().sqrt(),
            SIN => va().sin(),
            COS => va().cos(),
            ABS => va().abs(),
            NEG => -va(),
            NOISE2 => noise2(perm, va(), vb()),
            FBM => fbm(perm, va(), vb(), &q),
            JMP => {
                pc = d as usize;
                continue;
            }
            JZ => {
                if va() == 0.0 {
                    pc = d as usize;
                }
                continue;
            }
            CALL => {
                stack[sp] = pc;
                sp += 1;
                pc = d as usize;
                continue;
            }
            RET => {
                sp -= 1;
                pc = stack[sp];
                continue;
            }
            OUT => {
                col = [rd(regs, d), rd(regs, a), rd(regs, b)];
                continue;
            }
            _ => panic!("bad opcode {op}"),
        };
        regs[d as usize] = q(r);
    }
    (col, n)
}

/// Quantise like the GPU side: clamp, scale, round half to even.
pub fn quant(c: f64) -> u8 {
    (c.clamp(0.0, 1.0) * 255.0).round_ties_even() as u8
}

/// The whole image on every core: RGB bytes, total instructions run.
pub fn run_cpu(prog: &Program, perm: &[u32], w: u32, h: u32, f32: bool) -> (Vec<u8>, u64) {
    use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
    let next = AtomicU32::new(0);
    let total = AtomicU64::new(0);
    let out = std::sync::Mutex::new(vec![0u8; (w * h * 3) as usize]);
    let threads = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
    let kc: Vec<f64> = prog.consts.iter().map(|&c| if f32 { c as f32 as f64 } else { c }).collect();
    let kc = &kc;
    std::thread::scope(|s| {
        for _ in 0..threads {
            s.spawn(|| {
                let mut regs = Vec::new();
                let mut row = vec![0u8; (w * 3) as usize];
                loop {
                    let j = next.fetch_add(1, Ordering::Relaxed);
                    if j >= h {
                        break;
                    }
                    let mut n = 0;
                    for i in 0..w {
                        let (c, k) = run_pixel(prog, kc, perm, i, j, f32, &mut regs);
                        n += k;
                        for ch in 0..3 {
                            row[(i * 3) as usize + ch] = quant(c[ch]);
                        }
                    }
                    total.fetch_add(n, Ordering::Relaxed);
                    let o = (j * w * 3) as usize;
                    out.lock().unwrap()[o..o + row.len()].copy_from_slice(&row);
                }
            });
        }
    });
    (out.into_inner().unwrap(), total.into_inner())
}
