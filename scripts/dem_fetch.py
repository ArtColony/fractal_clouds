#!/usr/bin/env python3
"""dem_fetch.py -- public elevation data into a terrain grid a piece can read
(fractal_clouds#155, part of the real-terrain epic #164).

    python3 -I scripts/dem_fetch.py --center 36.065 -112.07 --size 24000 \\
        --n 768 --out data/terrain/grand_canyon

downloads the elevation tiles that cover a square SIZE metres across around
CENTER (latitude, longitude), resamples it onto an N x N grid in metres, and
writes:

    OUT.bin    N*N little-endian binary64 heights in metres, row by row, the
               north row first and each row west to east: read it with
               (OUT.bin) N N mul readreals
    OUT.json   where it came from: source, tiles and their sha256, licence
               and attribution, the grid's centre, size and cell, the
               projection, and the height range
    PREVIEW    (--preview, a .png) a hillshade, to check the crop by eye

Map coordinates (as lib/fc_map.ps has them): x east, z north, metres from
the centre; grid row 0 is the far (north, high z) row, as MapGrid's rows run.
The projection is local: each sample's latitude is lat0 + z/R and its
longitude lon0 + x/(R cos(lat)), R the mean earth radius. Over 25 km that is
within a few metres of UTM, well under one 30 m cell. Heights are above the
source's geoid (EGM2008 for Copernicus, NAVD88 for USGS); earth curvature is
#158's business, not this grid's.

Sources:
    cop30   Copernicus GLO-30 DSM, 1 arc-second (about 30 m), worldwide,
            from the public AWS bucket; free to use and redistribute with
            the attribution in the metadata. A surface model: it includes
            trees and buildings.
    usgs13  USGS 3DEP 1/3 arc-second (about 10 m), the US only; public
            domain. Tiles are about 420 MB, and the box must lie in one.

Tiles go to the cache directory (--cache, or $FC_DEM_CACHE, or
renders/dem-cache), each in its own subdirectory, and are reused. They are
untrusted downloads: this script only decodes them as images (Pillow's TIFF
reader), and should be run with python3 -I.
"""
import argparse
import datetime
import hashlib
import json
import math
import os
import struct
import sys
import urllib.request

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = 200_000_000
R_EARTH = 6371008.8  # mean radius, metres

SOURCES = {
    "cop30": {
        "name": "Copernicus GLO-30 DSM",
        "url": "https://copernicus-dem-30m.s3.amazonaws.com/"
               "Copernicus_DSM_COG_10_{ns}{alat:02d}_00_{ew}{alon:03d}_00_DEM/"
               "Copernicus_DSM_COG_10_{ns}{alat:02d}_00_{ew}{alon:03d}_00_DEM.tif",
        "licence": "Copernicus DEM licence: free use and redistribution with attribution",
        "attribution": "Produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and "
                       "(c) Airbus Defence and Space GmbH 2014-2018, provided under "
                       "COPERNICUS by the European Union and ESA; all rights reserved.",
        "datum": "EGM2008",
        "multi": True,
    },
    "usgs13": {
        "name": "USGS 3DEP 1/3 arc-second DEM",
        "url": "https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current/"
               "{nsl}{tlat:02d}{ewl}{alon:03d}/USGS_13_{nsl}{tlat:02d}{ewl}{alon:03d}.tif",
        "licence": "Public domain (US Geological Survey)",
        "attribution": "Elevation: U.S. Geological Survey 3D Elevation Program, 1/3 arc-second DEM.",
        "datum": "NAVD88",
        "multi": False,
    },
}


def tile_url(src, lat, lon):
    """URL of the tile whose south-west corner is (lat, lon), integer degrees."""
    s = SOURCES[src]
    # USGS names a tile by its north-west corner
    return s["url"].format(
        ns="N" if lat >= 0 else "S", alat=abs(lat),
        ew="E" if lon >= 0 else "W", alon=abs(lon),
        nsl="n" if lat + 1 >= 0 else "s", tlat=abs(lat + 1),
        ewl="e" if lon >= 0 else "w")


def fetch(url, cache):
    """The tile at url, downloaded once into its own directory under cache."""
    name = url.rsplit("/", 1)[1]
    d = os.path.join(cache, os.path.splitext(name)[0])
    path = os.path.join(d, name)
    if not os.path.exists(path):
        os.makedirs(d, exist_ok=True)
        tmp = path + ".part"
        print(f"dem_fetch: downloading {url}", file=sys.stderr)
        req = urllib.request.Request(url, headers={"User-Agent": "dem_fetch/1"})
        with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
            while True:
                b = r.read(1 << 20)
                if not b:
                    break
                f.write(b)
        os.replace(tmp, path)
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return path, h.hexdigest()


def read_tile(path):
    """-> (heights float64 [rows, cols], lon of column 0's centre, lat of
    row 0's centre, degrees per column, degrees per row)."""
    im = Image.open(path)
    tags = im.tag_v2
    tie = tags[33922]          # ModelTiepoint: i j k X Y Z
    scale = tags[33550]        # ModelPixelScale: sx sy sz
    keys = tags.get(34735, ())
    area = True                # GTRasterTypeGeoKey (1025): 1 area, 2 point
    for k in range(4, len(keys), 4):
        if keys[k] == 1025:
            area = keys[k + 3] == 1
    off = 0.5 if area else 0.0
    sx, sy = scale[0], scale[1]
    lon0 = tie[3] + (off - tie[0]) * sx
    lat0 = tie[4] - (off - tie[1]) * sy
    a = np.asarray(im, dtype=np.float64)
    nodata = tags.get(42113)
    if nodata is not None:
        try:
            nd = float(str(nodata).strip("\x00 "))
            a = np.where(a == nd, np.nan, a)
        except ValueError:
            pass
    a = np.where(a < -1000, np.nan, a)
    return a, lon0, lat0, sx, sy


def bilinear(a, fr, fc):
    """a sampled at fractional rows fr and columns fc (arrays), clamped."""
    rows, cols = a.shape
    fr = np.clip(fr, 0, rows - 1.000001)
    fc = np.clip(fc, 0, cols - 1.000001)
    r0 = np.floor(fr).astype(int)
    c0 = np.floor(fc).astype(int)
    tr = fr - r0
    tc = fc - c0
    v00 = a[r0, c0]
    v01 = a[r0, c0 + 1]
    v10 = a[r0 + 1, c0]
    v11 = a[r0 + 1, c0 + 1]
    return (v00 * (1 - tc) + v01 * tc) * (1 - tr) + (v10 * (1 - tc) + v11 * tc) * tr


def hillshade(h, cell, out):
    gy, gx = np.gradient(h, cell)
    # light from the north-west, 45 degrees up; row 0 is north
    lx, ly, lz = -1 / math.sqrt(3), 1 / math.sqrt(3), 1 / math.sqrt(3)
    nx, ny, nz = -gx, gy, np.ones_like(h)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    s = np.clip((nx * lx + ny * ly + nz * lz) / n, 0, 1)
    t = (h - np.nanmin(h)) / max(np.nanmax(h) - np.nanmin(h), 1)
    rgb = np.stack([0.55 + 0.45 * t, 0.5 + 0.3 * t, 0.4 + 0.2 * t], -1) * (0.25 + 0.75 * s)[..., None]
    Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8)).save(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--center", nargs=2, type=float, required=True, metavar=("LAT", "LON"))
    ap.add_argument("--size", type=float, required=True, help="square side, metres")
    ap.add_argument("--n", type=int, default=512, help="grid samples per side")
    ap.add_argument("--source", choices=sorted(SOURCES), default="cop30")
    ap.add_argument("--out", required=True, help="output path without extension")
    ap.add_argument("--preview", help="write a hillshade PNG here")
    ap.add_argument("--cache", default=os.environ.get("FC_DEM_CACHE", "renders/dem-cache"))
    a = ap.parse_args()

    lat0, lon0 = a.center
    n, size = a.n, a.size
    src = SOURCES[a.source]
    cell = size / (n - 1)
    # sample positions, row 0 north, each row west to east
    t = np.linspace(-0.5, 0.5, n) * size
    x = np.broadcast_to(t[None, :], (n, n))
    z = np.broadcast_to(-t[:, None], (n, n))
    lat = lat0 + np.degrees(z / R_EARTH)
    lon = lon0 + np.degrees(x / (R_EARTH * np.cos(np.radians(lat))))

    la0, la1 = math.floor(lat.min()), math.floor(lat.max())
    lo0, lo1 = math.floor(lon.min()), math.floor(lon.max())
    tiles = [(la, lo) for la in range(la0, la1 + 1) for lo in range(lo0, lo1 + 1)]
    if len(tiles) > 1 and not src["multi"]:
        sys.exit(f"dem_fetch: the box spans {len(tiles)} {a.source} tiles; pick a box in one, or --source cop30")

    h = np.full((n, n), np.nan)
    meta_tiles = []
    for la, lo in tiles:
        url = tile_url(a.source, la, lo)
        path, sha = fetch(url, a.cache)
        arr, tlon0, tlat0, sx, sy = read_tile(path)
        meta_tiles.append({"url": url, "sha256": sha})
        # this tile's samples (the south-west corner owns a sample)
        m = (np.floor(lat) == la) & (np.floor(lon) == lo)
        fr = (tlat0 - lat[m]) / sy
        fc = (lon[m] - tlon0) / sx
        h[m] = bilinear(arr, fr, fc)
    # a tile's last row or column stops a fraction of a cell short of its
    # neighbour's first: the clamp holds it there (under one source cell)
    if np.isnan(h).any():
        k = int(np.isnan(h).sum())
        sys.exit(f"dem_fetch: {k} samples have no data (sea or a void); not written")

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out + ".bin", "wb") as f:
        f.write(struct.pack("<%dd" % (n * n), *h.ravel().tolist()))
    meta = {
        "source": src["name"], "source_key": a.source, "tiles": meta_tiles,
        "licence": src["licence"], "attribution": src["attribution"],
        "vertical_datum": src["datum"], "units": "metres",
        "center_lat_lon": [lat0, lon0], "size_m": size, "n": n, "cell_m": cell,
        "layout": "N*N little-endian binary64, row 0 north, rows west to east; x east, z north, metres from the centre",
        "projection": "local: lat = lat0 + z/R, lon = lon0 + x/(R cos lat), R = 6371008.8 m",
        "height_min_m": float(h.min()), "height_max_m": float(h.max()),
        "made": datetime.date.today().isoformat(), "made_by": "scripts/dem_fetch.py (#155)",
    }
    with open(a.out + ".json", "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    if a.preview:
        hillshade(h, cell, a.preview)
    print(f"dem_fetch: {a.out}.bin: {n}x{n}, cell {cell:.1f} m, heights {h.min():.0f}..{h.max():.0f} m, "
          f"{len(tiles)} tile(s)")


if __name__ == "__main__":
    main()
