#!/usr/bin/env python3
"""Check a real-terrain render against a photo (fractal_clouds#159).

Two steps. `fit` finds where the camera stood and how the photo maps
directions to pixels, from the skyline alone. `overlay` then draws pscat's
own ridgelines on the photo through that mapping. The fit uses the grid
directly, in Python. The overlay comes from the renderer (depth passes, with
Earth curvature), so it is an independent check of the renderer, the
projection and the grid together.

  fit PHOTO GRID.json --lat LAT --lon LON [--eye M] [--out FIT.json]
      PHOTO is a stitched panorama in which x is linear in bearing (a
      cylindrical or equirectangular stitch). Its skyline is found by
      colour: sky is blue (b > r + 25) or white cloud. GRID.json is
      scripts/dem_fetch.py's metadata, next to its .bin.
      The model is bearing = a0 + (x - W/2)/k and
      y = y0 + A sin(b - a0) + B (cos(b - a0) - 1) - kv k (180/pi) tan(el),
      where el is the grid's horizon at that bearing seen from the camera:
      the highest elevation angle along the ray, less Earth's curvature
      with standard refraction. The sine and cosine terms take up a
      stitch's tilted horizon. kv stays 1 unless --kv-free.
      The camera starts at LAT LON, EYE metres above the grid's ground
      (default 1.6). It moves as the fit needs: geotags are often off by
      100 m or more, and 100 m at 2 km is 3 degrees. Bearings where the
      horizon is the grid's edge, or nearer than --near metres, are left
      out. Prints and writes the fit, including the camera's latitude,
      longitude and eye elevation for the piece's StandLL and CamHeight.

  overlay PHOTO FIT.json OUT DEPTH:YAW:PITCH:HFOV ...
      Each DEPTH is a pscat depth pass (scripts/render.sh --pass depth, or
      fastrender -D Pass=/depth) from the fitted camera, with that Yaw,
      Pitch and HFov. Its skyline (ground under sky) is drawn in magenta
      and its silhouettes (ground at least --jump times nearer than the
      ground beside it) in yellow, mapped into the photo. Prints how far
      the rendered skyline lies from the photo's, in pixels and degrees,
      where it is farther than --near metres (as in the fit).

The grid's cell bounds the precision: 31 m at 6 km is 0.3 degrees.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import map_coordinates
from scipy.optimize import least_squares

R = 6371008.8
REFR = 0.13


class Grid:
    def __init__(self, meta_path):
        m = json.load(open(meta_path))
        self.n = m['n']
        self.cell = m['cell_m']
        self.lat0, self.lon0 = m['center_lat_lon']
        b = os.path.splitext(meta_path)[0] + '.bin'
        self.h = np.fromfile(b, dtype='<f8').reshape(self.n, self.n)
        self.c = (self.n - 1) / 2
        self.half = self.c * self.cell

    def xz(self, lat, lon):
        return (math.radians(lon - self.lon0) * math.cos(math.radians(lat)) * R,
                math.radians(lat - self.lat0) * R)

    def latlon(self, x, z):
        lat = self.lat0 + math.degrees(z / R)
        return lat, self.lon0 + math.degrees(x / (R * math.cos(math.radians(lat))))

    def ground(self, x, z):
        return float(map_coordinates(self.h, [[self.c - z / self.cell], [x / self.cell + self.c]], order=3)[0])

    def horizon(self, x0, z0, eye, bearings, dmax=30000.0):
        """Elevation angle (degrees) of the skyline at each bearing, its
        distance, and whether that point is the grid's edge."""
        d = np.concatenate([np.arange(15, 1000, 5.0), np.arange(1000, dmax, 15.0)])
        A = np.radians(np.asarray(bearings))[:, None]
        x = x0 + d[None, :] * np.sin(A)
        z = z0 + d[None, :] * np.cos(A)
        hh = map_coordinates(self.h, [np.clip(self.c - z / self.cell, 0, self.n - 1).ravel(),
                                      np.clip(x / self.cell + self.c, 0, self.n - 1).ravel()],
                             order=1).reshape(x.shape)
        ang = (hh - eye - d * d * (1 - REFR) / (2 * R)) / d
        k = ang.argmax(1)
        rows = np.arange(len(k))
        edge = (np.abs(x[rows, k]) > self.half - 40) | (np.abs(z[rows, k]) > self.half - 40)
        return np.degrees(np.arctan(ang[rows, k])), d[k], edge


def photo_skyline(im):
    """Row of the skyline in each column (nan where none): the first row
    below which six rows in a row are neither blue sky nor white cloud."""
    a = np.asarray(im.convert('RGB')).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    sky = (b > r + 25) | ((r > 200) & (g > 200) & (b > 200) & (np.abs(r - b) < 30))
    h, w = sky.shape
    out = np.full(w, np.nan)
    ground = ~sky[: h * 2 // 3]
    for x in range(w):
        run = np.convolve(ground[:, x].astype(int), np.ones(6, int), 'valid')
        idx = np.nonzero(run == 6)[0]
        if idx.size:
            out[x] = idx[0]
    return out


def pano_y(p, bearing, el):
    a0, k, y0, A, B, kv = p[:6]
    t = np.radians(bearing - a0)
    return y0 + A * np.sin(t) + B * (np.cos(t) - 1) - kv * k * 180 / math.pi * np.tan(np.radians(el))


def pano_x(p, bearing, w):
    a0, k = p[0], p[1]
    return w / 2 + ((bearing - a0 + 180) % 360 - 180) * k


def fit(args):
    grid = Grid(args.grid)
    im = Image.open(args.photo)
    w = im.width
    sky = photo_skyline(im)
    X = np.arange(w)
    x0, z0 = grid.xz(args.lat, args.lon)

    def model(p, xs):
        dx, dz, dh = p[6:]
        cx, cz = x0 + dx, z0 + dz
        eye = grid.ground(cx, cz) + args.eye + dh
        b = p[0] + (xs - w / 2) / p[1]
        el, _, _ = grid.horizon(cx, cz, eye, b)
        return pano_y(p, b, el)

    # coarse: the centre's bearing and the span, camera at the geotag
    eye0 = grid.ground(x0, z0) + args.eye
    bs = np.arange(0, 360, 0.1)
    el0, dist0, edge0 = grid.horizon(x0, z0, eye0, bs)
    ok = ~np.isnan(sky)
    best = None
    for span in np.arange(args.span_lo, args.span_hi + 1e-6, 5):
        k = w / span
        for a0 in np.arange(0, 360, 2):
            b = np.mod(a0 + (X[ok] - w / 2) / k, 360)
            y = pano_y([a0, k, 0, 0, 0, 1], b, np.interp(b, bs, el0, period=360))
            off = np.median(sky[ok] - y)
            cost = np.median(np.abs(sky[ok] - y - off))
            if best is None or cost < best[0]:
                best = (cost, [a0, k, off, 0, 0, 1])
    p = best[1]
    # the columns used: a skyline found, not the grid's edge, not right by the camera
    b = np.mod(p[0] + (X - w / 2) / p[1], 360)
    use = ok & ~(np.interp(b, bs, edge0.astype(float), period=360) > 0.01) \
        & (np.interp(b, bs, dist0, period=360) > args.near)
    xs, ys = X[use][::2], sky[use][::2]
    P = p + [0.0, 0.0, 0.0]
    for stage in ([0, 1, 2, 3, 4], [0, 1, 2, 3, 4, 6, 7, 8] + ([5] if args.kv_free else [])):
        def full(q, free=stage):
            out = list(P)
            for i, v in zip(free, q):
                out[i] = v
            return out
        steps = [1e-5 if i in (0, 1, 2) else 1e-3 if i in (3, 4, 5) else 0.05 for i in stage]
        r = least_squares(lambda q: ys - model(full(q), xs), [P[i] for i in stage],
                          loss='soft_l1', f_scale=4, diff_step=steps)
        P = full(r.x)
    p = P
    res = np.abs(ys - model(p, xs))
    a0, k, y0, A, B, kv, dx, dz, dh = p
    cx, cz = x0 + dx, z0 + dz
    lat, lon = grid.latlon(cx, cz)
    out = dict(model='pano', a0=a0, k=k, y0=y0, A=A, B=B, kv=kv, width=w,
               lat=lat, lon=lon, ground_m=grid.ground(cx, cz),
               eye_m=grid.ground(cx, cz) + args.eye + dh, moved_m=[dx, dz, dh],
               columns=int(use.sum()), median_px=float(np.median(res)),
               median_deg=float(np.median(res) / k), p90_px=float(np.percentile(res, 90)))
    print(json.dumps(out, indent=1))
    if args.out:
        json.dump(out, open(args.out, 'w'), indent=1)


def ridgelines(depth_png, jump):
    """(rows, cols) of the skyline and of the silhouettes in a depth pass
    (8-bit, 1 - t/far, sky 0), and each pixel's distance as a fraction of
    far."""
    v = np.asarray(Image.open(depth_png).convert('L')).astype(np.float64) / 255.0
    sky = v <= 0
    t = np.where(sky, np.inf, 1.0 - v + 1.0 / 510)
    h, w = v.shape
    skyline = np.zeros((h, w), bool)
    skyline[1:] = sky[:-1] & ~sky[1:]
    sil = np.zeros((h, w), bool)
    for dy, dx in ((1, 0), (0, 1)):
        a, b = t[:h - dy, :w - dx], t[dy:, dx:]
        okk = np.isfinite(a) & np.isfinite(b)
        sil[:h - dy, :w - dx] |= okk & (b > a * jump)
        sil[dy:, dx:] |= okk & (a > b * jump)
    return np.nonzero(skyline), np.nonzero(sil & ~skyline), (h, w), t


def directions(rows, cols, shape, yaw, pitch, hfov):
    """Bearing and elevation (degrees) of depth-pass pixels: fc_render's
    pixel to (u, v), then fc_sky's fc-ray."""
    h, w = shape
    th = math.tan(math.radians(hfov / 2))
    u = (2 * (cols + 0.5) / w - 1) * th
    v = (2 * ((h - 1 - rows) + 0.5) / h - 1) * (h / w) * th
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    y = v * cp + sp
    z = cp - v * sp
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    wx = u * cy + z * sy
    wz = z * cy - u * sy
    n = np.sqrt(wx * wx + y * y + wz * wz)
    return np.degrees(np.arctan2(wx, wz)) % 360, np.degrees(np.arcsin(y / n))


def overlay(args):
    f = json.load(open(args.fit))
    p = [f['a0'], f['k'], f['y0'], f['A'], f['B'], f['kv']]
    im = Image.open(args.photo).convert('RGB')
    w, h = im.size
    sky = photo_skyline(im)
    d = ImageDraw.Draw(im)
    lw = max(2, w // 1500)
    resid = []
    for spec in args.tiles:
        path, yaw, pitch, hfov = spec.rsplit(':', 3)
        sk, sil, shape, t = ridgelines(path, args.jump)
        for (rr, cc), col, is_sky in ((sil, (255, 225, 40), False), (sk, (255, 40, 210), True)):
            b, e = directions(rr, cc, shape, float(yaw), float(pitch), float(hfov))
            x = pano_x(p, b, w)
            y = pano_y(p, b, e)
            inside = (x >= 0) & (x < w) & (y >= 0) & (y < h)
            for xi, yi in zip(x[inside], y[inside]):
                d.ellipse((xi - lw, yi - lw, xi + lw, yi + lw), fill=col)
            if is_sky:
                # (as the fit: only skyline farther than --near, which a
                # geotag's error barely moves)
                far = t[rr, cc] * args.far_m > args.near
                xi = x[inside].astype(int)
                ok = ~np.isnan(sky[xi]) & far[inside]
                resid.append(np.abs(sky[xi[ok]] - y[inside][ok]))
    im.save(args.out)
    r = np.concatenate(resid)
    print(f"rendered skyline against the photo's: {r.size} points, median {np.median(r):.1f} px "
          f"({np.median(r) / p[1]:.3f} deg), 75% {np.percentile(r, 75):.1f} px, "
          f"90% {np.percentile(r, 90):.1f} px")
    print(f'wrote {args.out}')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    f = sub.add_parser('fit')
    f.add_argument('photo')
    f.add_argument('grid')
    f.add_argument('--lat', type=float, required=True)
    f.add_argument('--lon', type=float, required=True)
    f.add_argument('--eye', type=float, default=1.6)
    f.add_argument('--near', type=float, default=500)
    f.add_argument('--span-lo', type=float, default=60)
    f.add_argument('--span-hi', type=float, default=360)
    f.add_argument('--kv-free', action='store_true')
    f.add_argument('--out')
    o = sub.add_parser('overlay')
    o.add_argument('photo')
    o.add_argument('fit')
    o.add_argument('out')
    o.add_argument('tiles', nargs='+')
    o.add_argument('--jump', type=float, default=1.3)
    o.add_argument('--far-m', type=float, default=30000,
                   help="the depth pass's far distance in metres (TMax times DemUnit)")
    o.add_argument('--near', type=float, default=500)
    args = ap.parse_args()
    {'fit': fit, 'overlay': overlay}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
