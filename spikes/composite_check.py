"""Re-blend the splat renderer's discs outside pscat (fractal_clouds#1).

Checks whether the colour fringes in pscat's splat render come from pscat's
compositing rather than from the scene. It blends the exact discs pscat
would draw (dumped by spikes/splat.ps with /Dump true) over pscat's own sky
(/SkyOnly true) in two ways:

  float  -- floating-point "over" compositing, quantised once at the end
  q8     -- an 8-bit buffer, alpha rounded to 1/255, every blend rounded

Then it compares both with pscat's real render.

  python3 -I spikes/composite_check.py SKY.png SPLATS.txt PSCAT.png OUTDIR [SCALE]

SCALE is device pixels per point (2 for --dpi 144). Disc edges use an
analytic one-pixel coverage ramp, which is close to pscat's antialiasing
but not identical, so compare structure and colour, not exact values.
"""

import sys

import numpy as np
from PIL import Image


def load_splats(path):
    rows = []
    with open(path) as f:
        for line in f:
            if line.startswith("["):
                rows.append([float(v) for v in line.strip("[]\n ").split()])
    return np.array(rows)


def composite(sky, splats, scale, mode, page_h):
    h, w, _ = sky.shape
    if mode == "float":
        buf = sky.astype(np.float64) / 255.0
    else:
        buf = sky.astype(np.int32)
    for x, y, r, cr, cg, cb, a in splats:
        cx, cy, rr = x * scale, (page_h - y) * scale, r * scale
        x0, x1 = max(int(cx - rr - 1), 0), min(int(cx + rr + 2), w)
        y0, y1 = max(int(cy - rr - 1), 0), min(int(cy + rr + 2), h)
        if x0 >= x1 or y0 >= y1:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1]
        d = np.hypot(xx + 0.5 - cx, yy + 0.5 - cy)
        cov = np.clip(rr - d + 0.5, 0.0, 1.0)
        col = np.clip([cr, cg, cb], 0.0, 1.0)
        region = buf[y0:y1, x0:x1]
        if mode == "float":
            k = (a * cov)[..., None]
            region[:] = region * (1 - k) + col * k
        else:
            a8 = np.rint(a * cov * 255).astype(np.int32)[..., None]
            col8 = np.rint(col * 255).astype(np.int32)
            region[:] = (region * (255 - a8) + col8 * a8 + 127) // 255
    if mode == "float":
        return np.clip(np.rint(buf * 255), 0, 255).astype(np.uint8)
    return buf.astype(np.uint8)


def main():
    sky_p, splat_p, pscat_p, out = sys.argv[1:5]
    scale = float(sys.argv[5]) if len(sys.argv) > 5 else 2.0
    sky = np.array(Image.open(sky_p).convert("RGB"))
    ref = np.array(Image.open(pscat_p).convert("RGB")).astype(np.int32)
    splats = load_splats(splat_p)
    page_h = sky.shape[0] / scale
    print(f"{len(splats)} discs, alpha min {splats[:, 6].min():.4f} "
          f"median {np.median(splats[:, 6]):.4f}")
    results = {}
    for mode in ("float", "q8"):
        img = composite(sky, splats, scale, mode, page_h)
        Image.fromarray(img).save(f"{out}/composite-{mode}.png")
        results[mode] = img.astype(np.int32)
    f, q = results["float"], results["q8"]
    for name, img in (("float", f), ("q8", q)):
        diff = np.abs(img - ref)
        print(f"pscat vs {name:5}: mean |diff| {diff.mean():5.2f}, "
              f"pixels off by >8: {(diff.max(axis=2) > 8).mean() * 100:5.1f}%")
    # hue drift: how far each image's (red - green) strays from the float
    # composite's. A fringe is red and blue moving while green lags.
    for name, img in (("pscat", ref), ("q8", q)):
        drift = (img[..., 0] - img[..., 1]) - (f[..., 0] - f[..., 1])
        print(f"{name:5} red-green drift vs float: mean {drift.mean():+5.2f}, "
              f"|drift| > 10 on {(np.abs(drift) > 10).mean() * 100:5.1f}% of pixels")


if __name__ == "__main__":
    main()
