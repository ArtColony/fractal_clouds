//! gpu-interp-poc: fractal_clouds#147, idea A (and B's timing).
//!
//!   gpu-interp-poc straight N NREGS     time one straight-line shader of N
//!                                        instructions (pscat's current shape)
//!   gpu-interp-poc interp FILE NREGS    time the fixed interpreter shader
//!   gpu-interp-poc run W H FILE NREGS [OCT] [OUTDIR]
//!                                        render the synthetic terrain on the
//!                                        GPU interpreter and on the CPU (f64
//!                                        and f32), compare, write PNGs; FILE
//!                                        `native` runs src/terrain_native.wgsl,
//!                                        `hybrid` the interpreter with the fbm
//!                                        as one native instruction
//!
//! FILE is private, storage or workgroup (see wgsl::RegFile). Every timing
//! line is one `key=value` record, so a shell loop can collect them.

mod prog;
mod wgsl;

use std::time::Instant;
use wgsl::RegFile;

fn ms(t: Instant) -> f64 {
    t.elapsed().as_secs_f64() * 1e3
}

/// A fresh entry-point name, so Metal's shader cache can't serve the
/// compile from an earlier run.
fn fresh_entry() -> String {
    let n = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    format!("k{}_{}", std::process::id(), n % 1_000_000_000)
}

fn device() -> (wgpu::Device, wgpu::Queue, String) {
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle());
    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        ..Default::default()
    }))
    .expect("no GPU adapter");
    let name = adapter.get_info().name;
    let (d, q) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
        label: Some("poc"),
        required_limits: adapter.limits(),
        ..Default::default()
    }))
    .expect("no GPU device");
    (d, q, name)
}

/// Parse and validate with naga alone (the work wgpu repeats inside
/// `create_shader_module` for WGSL): (module, parse ms, validate ms).
fn naga_front(src: &str) -> (naga::Module, f64, f64) {
    let t = Instant::now();
    let m = naga::front::wgsl::parse_str(src).unwrap_or_else(|e| panic!("WGSL: {}", e.emit_to_string(src)));
    let parse = ms(t);
    let t = Instant::now();
    naga::valid::Validator::new(naga::valid::ValidationFlags::all(), naga::valid::Capabilities::all())
        .validate(&m)
        .expect("naga validation");
    (m, parse, ms(t))
}

/// Module plus compute pipeline, timed (Metal compiles here).
fn pipeline(dev: &wgpu::Device, src: wgpu::ShaderSource, entry: &str) -> (wgpu::ComputePipeline, f64) {
    let t = Instant::now();
    let scope = dev.push_error_scope(wgpu::ErrorFilter::Validation);
    let module = dev.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("poc"), source: src });
    let p = dev.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("poc"),
        layout: None,
        module: &module,
        entry_point: Some(entry),
        compilation_options: Default::default(),
        cache: None,
    });
    if let Some(e) = pollster::block_on(scope.pop()) {
        panic!("shader rejected: {e}");
    }
    let _ = dev.poll(wgpu::PollType::wait_indefinitely());
    (p, ms(t))
}

/// Time one shader four ways: naga parse, naga validate, wgpu from WGSL
/// (parse + validate + MSL + Metal compile) and wgpu from naga IR (idea B:
/// no WGSL parse).
fn time_shader(dev: &wgpu::Device, make: &dyn Fn(&str) -> String, what: &str) {
    let e1 = fresh_entry();
    let src = make(&e1);
    let (_, parse, validate) = naga_front(&src);
    let (_, wgsl_ms) = pipeline(dev, wgpu::ShaderSource::Wgsl(src.as_str().into()), &e1);
    // the same source again: Metal's own cache (in-process or system)
    let (_, warm_ms) = pipeline(dev, wgpu::ShaderSource::Wgsl(src.as_str().into()), &e1);
    // idea B: hand wgpu a naga module (here parsed from WGSL, untimed; in
    // pscat it would be built from the kernel IR directly)
    let e2 = fresh_entry() + "b";
    let src2 = make(&e2);
    let (m2, _, _) = naga_front(&src2);
    let (_, ir_ms) = pipeline(dev, wgpu::ShaderSource::Naga(std::borrow::Cow::Owned(m2)), &e2);
    println!(
        "{what} wgsl_bytes={} naga_parse_ms={parse:.1} naga_validate_ms={validate:.1} pipeline_from_wgsl_ms={wgsl_ms:.1} pipeline_from_wgsl_again_ms={warm_ms:.1} pipeline_from_naga_ir_ms={ir_ms:.1}",
        src.len()
    );
}

fn bytes_u32(v: &[u32]) -> &[u8] {
    bytemuck::cast_slice(v)
}

/// Render `p` on the GPU interpreter: RGB bytes and the dispatch time.
/// `native`: run src/terrain_native.wgsl (the same program compiled as its
/// own shader) instead of the interpreter.
fn run_gpu(dev: &wgpu::Device, q: &wgpu::Queue, p: &prog::Program, perm: &[u32], w: u32, h: u32, file: RegFile, native: bool) -> (Vec<u8>, f64, f64) {
    use wgpu::util::DeviceExt;
    let entry = "main";
    let src = if native { include_str!("terrain_native.wgsl").to_string() } else { wgsl::interpreter(file, p.nregs, entry) };
    let (pipe, compile) = pipeline(dev, wgpu::ShaderSource::Wgsl(src.into()), entry);
    let code: Vec<u32> = p.code.iter().flatten().copied().collect();
    let consts: Vec<f32> = p.consts.iter().map(|&c| c as f32).collect();
    let mk = |label, contents: &[u8], usage| dev.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some(label), contents, usage });
    let code_b = mk("code", bytes_u32(&code), wgpu::BufferUsages::STORAGE);
    let k_b = mk("consts", bytemuck::cast_slice(&consts), wgpu::BufferUsages::STORAGE);
    let perm_b = mk("perm", bytes_u32(perm), wgpu::BufferUsages::STORAGE);
    let npx_all = (w * h) as u64;
    let out_b = dev.create_buffer(&wgpu::BufferDescriptor {
        label: Some("out"),
        size: npx_all * 4,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    let staging = dev.create_buffer(&wgpu::BufferDescriptor {
        label: Some("staging"),
        size: npx_all * 4,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    // Whole rows per dispatch, at most 64k pixels (as pscat's CHUNK_PIXELS),
    // fewer when the storage register file would pass 256 MB.
    let mut chunk_px: u64 = 65536;
    if file == RegFile::Storage {
        chunk_px = chunk_px.min((64u64 << 20) / p.nregs as u64);
    }
    let rows_per = (chunk_px / w as u64).max(1) as u32;
    let stride = rows_per * w;
    let regs_b = (file == RegFile::Storage).then(|| {
        dev.create_buffer(&wgpu::BufferDescriptor {
            label: Some("regs"),
            size: p.nregs as u64 * stride as u64 * 4,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        })
    });
    let params = dev.create_buffer(&wgpu::BufferDescriptor {
        label: Some("params"),
        size: 32,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let mut entries = vec![
        wgpu::BindGroupEntry { binding: 0, resource: params.as_entire_binding() },
        wgpu::BindGroupEntry { binding: 3, resource: perm_b.as_entire_binding() },
        wgpu::BindGroupEntry { binding: 4, resource: out_b.as_entire_binding() },
    ];
    if !native {
        entries.push(wgpu::BindGroupEntry { binding: 1, resource: code_b.as_entire_binding() });
        entries.push(wgpu::BindGroupEntry { binding: 2, resource: k_b.as_entire_binding() });
    }
    if let Some(r) = &regs_b {
        entries.push(wgpu::BindGroupEntry { binding: 5, resource: r.as_entire_binding() });
    }
    let bind = dev.create_bind_group(&wgpu::BindGroupDescriptor { label: None, layout: &pipe.get_bind_group_layout(0), entries: &entries });
    let t = Instant::now();
    let mut j = 0;
    while j < h {
        let n = rows_per.min(h - j);
        let px = n * w;
        let prm: [u32; 8] = [w, j, px, p.ri, p.rj, stride, 1 << 22, h];
        q.write_buffer(&params, 0, bytes_u32(&prm));
        let mut enc = dev.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
        {
            let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor { label: None, timestamp_writes: None });
            pass.set_pipeline(&pipe);
            pass.set_bind_group(0, &bind, &[]);
            pass.dispatch_workgroups(px.div_ceil(64), 1, 1);
        }
        q.submit(Some(enc.finish()));
        // one dispatch at a time, as pscat does (and so the storage
        // register file is never shared by two dispatches in flight)
        let _ = dev.poll(wgpu::PollType::wait_indefinitely());
        j += n;
    }
    let mut enc = dev.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
    enc.copy_buffer_to_buffer(&out_b, 0, &staging, 0, npx_all * 4);
    q.submit(Some(enc.finish()));
    let slice = staging.slice(..);
    let (tx, rx) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |r| {
        let _ = tx.send(r);
    });
    let _ = dev.poll(wgpu::PollType::wait_indefinitely());
    rx.recv().unwrap().expect("map");
    let run = ms(t);
    let view = slice.get_mapped_range().expect("mapped range");
    let mut rgb = Vec::with_capacity((npx_all * 3) as usize);
    for px in view.chunks_exact(4) {
        rgb.extend_from_slice(&px[..3]);
    }
    (rgb, compile, run)
}

/// fractal_clouds' SAME-LOOK numbers (renders/k117b/imgdiff.py): PSNR over
/// all channels, the 99.9th percentile and the mean of |a - b|.
fn same_look(a: &[u8], b: &[u8]) -> (f64, u8, f64) {
    let mut hist = [0u64; 256];
    let (mut se, mut sa) = (0f64, 0f64);
    for (x, y) in a.iter().zip(b) {
        let d = (*x as i32 - *y as i32).unsigned_abs() as usize;
        hist[d] += 1;
        se += (d * d) as f64;
        sa += d as f64;
    }
    let n = a.len() as f64;
    let mse = se / n;
    let psnr = if mse == 0.0 { f64::INFINITY } else { 10.0 * (255.0f64 * 255.0 / mse).log10() };
    let (mut acc, mut p999) = (0u64, 0u8);
    for (d, c) in hist.iter().enumerate() {
        acc += c;
        if acc as f64 >= 0.999 * n {
            p999 = d as u8;
            break;
        }
    }
    (psnr, p999, sa / n)
}

fn write_png(path: &str, w: u32, h: u32, rgb: &[u8]) {
    let f = std::fs::File::create(path).expect("create png");
    let mut e = png::Encoder::new(std::io::BufWriter::new(f), w, h);
    e.set_color(png::ColorType::Rgb);
    e.set_depth(png::BitDepth::Eight);
    e.write_header().unwrap().write_image_data(rgb).unwrap();
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let arg = |i: usize| a.get(i).unwrap_or_else(|| panic!("see the usage at the top of src/main.rs"));
    match a.get(1).map(String::as_str) {
        Some("straight") => {
            let (n, nregs): (usize, usize) = (arg(2).parse().unwrap(), arg(3).parse().unwrap());
            let (dev, _, name) = device();
            eprintln!("adapter: {name}");
            time_shader(&dev, &|e| wgsl::straight(n, nregs, e), &format!("straight n={n} nregs={nregs}"));
        }
        Some("interp") => {
            let file = RegFile::parse(arg(2));
            let nregs: u32 = arg(3).parse().unwrap();
            let (dev, _, name) = device();
            eprintln!("adapter: {name}");
            time_shader(&dev, &|e| wgsl::interpreter(file, nregs, e), &format!("interp file={file:?} nregs={nregs}"));
        }
        Some("run") => {
            let (w, h): (u32, u32) = (arg(2).parse().unwrap(), arg(3).parse().unwrap());
            // FILE `native` runs the hand-written shader instead
            // `hybrid`: the interpreter (private registers) with the fbm as
            // one native instruction
            let native = arg(4) == "native";
            let hybrid = arg(4) == "hybrid";
            let file = if native || hybrid { RegFile::Private } else { RegFile::parse(arg(4)) };
            let nregs: u32 = arg(5).parse().unwrap();
            let oct: u32 = a.get(6).map(|s| s.parse().unwrap()).unwrap_or(8);
            let outdir = a.get(7).cloned();
            let base = prog::terrain(w, h, oct, hybrid);
            eprintln!("terrain program: {} instructions, {} registers", base.code.len(), base.nregs);
            let p = base.spread(nregs);
            let perm = prog::perm();
            let (dev, q, name) = device();
            eprintln!("adapter: {name}");
            let (gpu, compile, gpu_ms) = run_gpu(&dev, &q, &p, &perm, w, h, file, native);
            let t = Instant::now();
            let (cpu64, instrs) = prog::run_cpu(&p, &perm, w, h, false);
            let cpu64_ms = ms(t);
            let t = Instant::now();
            let (cpu32, _) = prog::run_cpu(&p, &perm, w, h, true);
            let cpu32_ms = ms(t);
            let (g_psnr, g_p, g_mean) = same_look(&gpu, &cpu64);
            let (c_psnr, c_p, c_mean) = same_look(&cpu32, &cpu64);
            let same = |psnr: f64, p: u8, m: f64| psnr >= 40.0 && p <= 8 && m <= 1.5;
            println!(
                "run w={w} h={h} file={} nregs={nregs} prog_instrs={} prog_regs={} octaves={oct} lane_instrs={instrs} per_px={:.0} \
                 compile_ms={compile:.1} gpu_ms={gpu_ms:.1} gpu_glane_per_s={:.2} cpu_f64_ms={cpu64_ms:.1} cpu_f32_ms={cpu32_ms:.1} \
                 gpu_vs_f64: psnr={g_psnr:.2} p999={g_p} mean={g_mean:.3} same_look={} cpu_f32_vs_f64: psnr={c_psnr:.2} p999={c_p} mean={c_mean:.3} same_look={}",
                if native { "native".to_string() } else if hybrid { "hybrid".to_string() } else { format!("{file:?}") },
                p.code.len(),
                base.nregs,
                instrs as f64 / (w * h) as f64,
                instrs as f64 / gpu_ms / 1e6,
                same(g_psnr, g_p, g_mean),
                same(c_psnr, c_p, c_mean),
            );
            if let Some(d) = outdir {
                let tag = if native { "native".to_string() } else if hybrid { "hybrid".to_string() } else { format!("{file:?}_{nregs}") };
                write_png(&format!("{d}/terrain_{w}x{h}_gpu_{tag}.png"), w, h, &gpu);
                write_png(&format!("{d}/terrain_{w}x{h}_cpu64.png"), w, h, &cpu64);
                write_png(&format!("{d}/terrain_{w}x{h}_cpu32.png"), w, h, &cpu32);
            }
        }
        _ => {
            eprintln!("usage: see the top of src/main.rs");
            std::process::exit(2);
        }
    }
}
