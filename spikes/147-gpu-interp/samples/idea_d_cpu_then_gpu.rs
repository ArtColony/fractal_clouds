// Idea D (fractal_clouds#147): start on the CPU and let the GPU join when
// its pipeline is ready. A SKETCH in pscat's terms (src/kernel/mod.rs runs
// rows on threads; src/kernel/gpu.rs `run`), not compiled.
//
// The GPU's fixed cost (device, WGSL parse, Metal compile) is paid before
// the first pixel today. Here it overlaps the CPU's work: if the compile
// finishes late or fails, the frame is no slower than the CPU path alone.
// The CPU takes rows from the top and the GPU takes chunks from the bottom,
// so the GPU's start-up shows only if it finishes early.

use std::sync::Mutex;

/// Rows not yet taken: `top..bottom`. One lock per row or chunk taken is
/// nothing next to rendering a row, and a mutex makes the meeting point
/// trivially right (a lock-free two-ended counter can hand the same row to
/// both sides).
struct Rows(Mutex<(usize, usize)>);

impl Rows {
    /// CPU: one row from the top, or None once the two ends meet.
    fn cpu_take(&self) -> Option<usize> {
        let mut g = self.0.lock().unwrap();
        let (top, bottom) = *g;
        (top < bottom).then(|| { g.0 += 1; top })
    }
    /// GPU: up to `n` rows from the bottom.
    fn gpu_take(&self, n: usize) -> Option<(usize, usize)> {
        let mut g = self.0.lock().unwrap();
        let (top, bottom) = *g;
        (top < bottom).then(|| { let a = bottom.saturating_sub(n).max(top); g.1 = a; (a, bottom) })
    }
}

fn render(k: &Kernel, w: usize, h: usize) {
    let rows = Rows(Mutex::new((0, h)));
    std::thread::scope(|s| {
        // the GPU thread: compile, then take chunks until the ends meet
        s.spawn(|| {
            let Ok(gpu) = gpu::prepare(k) else { return }; // parse + compile, off the critical path
            while let Some((a, b)) = rows.gpu_take(gpu.rows_per_dispatch(w)) {
                gpu.run_rows(a, b); // f32: approximate
            }
        });
        // the CPU threads, exactly as now, but taking from `rows`
        for _ in 0..threads() {
            s.spawn(|| while let Some(j) = rows.cpu_take() { exec::run_row(k, j) });
        }
    });
}

// Exactness: rows from the GPU are f32 and rows from the CPU are exact, in
// one image. That is acceptable only when the caller opts into approximate
// output (pscat's default must stay exact), and only if the two halves look
// the same. The proof of concept measured f32 against f64 on a synthetic
// terrain at 63 dB PSNR (fractal_clouds' SAME-LOOK bar is 40 dB), so a seam
// should be invisible there; check on real scenes before relying on it.
