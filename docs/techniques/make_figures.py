#!/usr/bin/env python3
"""Figures for docs/techniques.html, computed from the formulas and constants
in lib/*.ps (each function below names the procedure it follows).

    python3 docs/techniques/make_figures.py      # from the repo root

Writes SVG (and one PNG) into docs/techniques/. Needs numpy and matplotlib.
The noise here is a Python port with its own random tables, so it has the
same character as the PostScript noise but not the same values.
"""
import math
import os

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyBboxPatch, Rectangle

OUT = os.path.dirname(os.path.abspath(__file__))

INK = "#22262b"
MUTED = "#6b717a"
GRID = "#d9dce0"
ACC = "#2f6fb0"     # blue
ACC2 = "#c0622a"    # orange
ACC3 = "#3f8a4f"    # green
ACC4 = "#8a5aa8"    # purple

plt.rcParams.update({
    "svg.fonttype": "none",
    "font.family": "sans-serif",
    "font.size": 10,
    "axes.edgecolor": MUTED,
    "axes.labelcolor": INK,
    "text.color": INK,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "axes.grid": True,
    "grid.color": GRID,
    "grid.linewidth": 0.6,
    "figure.facecolor": "white",
    "axes.facecolor": "white",
    "axes.spines.top": False,
    "axes.spines.right": False,
    "legend.frameon": False,
})


def save(fig, name):
    path = os.path.join(OUT, name)
    fig.savefig(path, bbox_inches="tight", pad_inches=0.15,
                dpi=90 if name.endswith(".png") else None)
    plt.close(fig)
    print("wrote", os.path.relpath(path))


def smoothstep01(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def fc_smooth(a, b, x):            # fc_terrain.ps fc-smooth
    return smoothstep01((x - a) / (b - a))


# --- noise ports (fc_noise2.ps) ---------------------------------------------
rng = np.random.default_rng(5)
VAL = rng.random((64, 64))
ANG = rng.random((64, 64)) * 2 * np.pi
GX, GY = np.cos(ANG), np.sin(ANG)


def gnoise2(x, y):                 # fc-gnoise2: gradient noise, ~-0.7..0.7
    fx, fy = np.floor(x), np.floor(y)
    u, v = x - fx, y - fy
    i, j = fx.astype(int) & 63, fy.astype(int) & 63
    i1, j1 = (i + 1) & 63, (j + 1) & 63
    s, t = smoothstep01(u), smoothstep01(v)
    n00 = GX[j, i] * u + GY[j, i] * v
    n10 = GX[j, i1] * (u - 1) + GY[j, i1] * v
    n01 = GX[j1, i] * u + GY[j1, i] * (v - 1)
    n11 = GX[j1, i1] * (u - 1) + GY[j1, i1] * (v - 1)
    a = n00 + (n10 - n00) * s
    b = n01 + (n11 - n01) * s
    return a + (b - a) * t


def ridged(x, y, oct_):            # fc-ridged (whole octaves)
    total, amp, w, norm = 0.0, 0.5, 1.0, 0.0
    layers = []
    for _ in range(oct_):
        r = np.clip(1 - np.abs(gnoise2(x, y)) * 1.6, 0, None) ** 2
        layers.append(r * w * amp)
        total = total + r * w * amp
        w = np.minimum(r * 2, 1)
        norm += amp
        amp *= 0.5
        x, y = x * 1.6 - y * 1.2 + 3.1, x * 1.2 + y * 1.6 + 7.7
    return total / norm, layers, norm


# --- 1. the per-pixel pipeline ---------------------------------------------
def fig_pipeline():
    fig, ax = plt.subplots(figsize=(9.2, 3.5))
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 38)
    ax.axis("off")
    boxes = [
        (1, 20, 13, 11, "fc-ray", "pixel (u, v)\n→ unit ray\nMx My Mz", ACC),
        (16.5, 20, 16, 11, "landscape-hit", "march terrain\n(+ trees)\n→ t or −1", ACC),
        (35, 26, 15, 9, "surface", "fc-terrain-shade\nfc-tree-shade", ACC3),
        (35, 14, 15, 9, "sky", "fc-sky\n(or horizon haze)", ACC3),
        (53, 26, 12, 9, "fc-haze", "aerial\nperspective", ACC4),
        (68, 20, 14, 11, "fc-clouds", "march the layer\nup to t; light ·\ntransmittance", ACC2),
        (85, 20, 14, 11, "fc-tone", "exposure curve,\n2.2 gamma\n→ 8-bit", MUTED),
    ]
    for x, y, w, h, title, body, col in boxes:
        ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.3,rounding_size=1.2",
                                    fc="white", ec=col, lw=1.6))
        ax.text(x + w / 2, y + h - 1.6, title, ha="center", va="top", fontsize=9,
                fontweight="bold", color=col, family="monospace")
        ax.text(x + w / 2, y + h / 2 - 1.6, body, ha="center", va="center", fontsize=8, color=INK)

    def arrow(x0, y0, x1, y1, label=None):
        ax.annotate("", (x1, y1), (x0, y0),
                    arrowprops=dict(arrowstyle="->", color=MUTED, lw=1.2))
        if label:
            ax.text((x0 + x1) / 2, (y0 + y1) / 2 + 1.1, label, ha="center", fontsize=7.5, color=MUTED)

    arrow(14.3, 25.5, 16.7, 25.5)
    arrow(32.3, 27, 34.7, 30)
    arrow(32.3, 24, 34.7, 18.5)
    ax.text(33.2, 31.6, "hit", ha="center", fontsize=7.5, color=MUTED)
    ax.text(32.6, 17.2, "miss", ha="center", fontsize=7.5, color=MUTED)
    arrow(50.3, 30.5, 52.7, 30.5)
    arrow(65.3, 30, 67.7, 27)
    arrow(50.3, 18.5, 67.7, 23.5)
    arrow(82.3, 25.5, 84.7, 25.5)
    ax.text(1, 10, "colour = clouds' light + transmittance × (hazed surface or sky).  "
            "Every step works in linear light; fc-landscape-grade runs just before fc-tone.",
            fontsize=8, color=MUTED)
    ax.text(1, 5, "fc_render.ps calls fc-pixel once per pixel (five times on depth edges) and "
            "streams the rows into colorimage.", fontsize=8, color=MUTED)
    save(fig, "pipeline.svg")


# --- 2. marching a heightfield ----------------------------------------------
def fig_march():
    x = np.linspace(0, 120, 1200)
    r, _, _ = ridged(x * 0.022 + 0.3, np.full_like(x, 2.7), 5)
    h = r * 26 - 2

    def hf(t):
        return np.interp(t, x, h)

    cam_y, my = 24.0, -0.10
    fig, axes = plt.subplots(1, 2, figsize=(10, 3.6), gridspec_kw=dict(width_ratios=[2.2, 1]))
    ax = axes[0]
    ax.fill_between(x, -6, h, color="#cfc7b8", lw=0)
    ax.plot(x, h, color="#7a6e5c", lw=1)
    ts = [0.5]
    while True:
        t = ts[-1]
        gap = cam_y + my * t - hf(t)
        if gap < 0 or t > 118:
            break
        ts.append(t + max(gap * 0.42, t * 0.004 + 0.2))    # fc-terrain-hit's step
    ts = np.array(ts)
    ys = cam_y + my * ts
    ax.plot([0, ts[-1]], [cam_y, ys[-1]], color=ACC, lw=1.2)
    ax.plot(ts[:-1], ys[:-1], "o", ms=3.5, color=ACC)
    ax.plot(ts[-1:], ys[-1:], "o", ms=5, mfc="white", color=ACC2)
    for t, y in zip(ts[:-1:2], ys[:-1:2]):
        ax.plot([t, t], [y, hf(t)], color=ACC, lw=0.6, ls=":")
    ax.text(ts[2] + 1, (ys[2] + hf(ts[2])) / 2, "clearance d", fontsize=8, color=ACC)
    ax.text(2, 26, "camera", fontsize=8, color=INK)
    ax.text(ts[-1] + 2, ys[-1] + 2, "first sample\nbelow ground", fontsize=8, color=ACC2)
    ax.set_xlim(0, 100)
    ax.set_ylim(-6, 30)
    ax.set_xlabel("distance along the ray")
    ax.set_ylabel("height")
    ax.set_title(f"fc-terrain-hit: step = max(0.42·d, 0.2 + 0.004·t)   ({len(ts)} samples)",
                 fontsize=9, loc="left")
    # zoom: bisection
    ax = axes[1]
    a, b = ts[-2], ts[-1]
    xx = np.linspace(a - 0.5, b + 0.5, 200)
    ax.fill_between(xx, -10, hf(xx), color="#cfc7b8", lw=0)
    ax.plot(xx, hf(xx), color="#7a6e5c", lw=1)
    ax.plot(xx, cam_y + my * xx, color=ACC, lw=1.2)
    for k in range(5):                                       # fc-terrain-hit bisects 5 times
        m = (a + b) / 2
        below = cam_y + my * m - hf(m) < 0
        ax.plot([m], [cam_y + my * m], "o", ms=4, color=ACC2 if below else ACC)
        ax.text(m, cam_y + my * m + 0.25 + 0.18 * (k % 2), str(k + 1), fontsize=7, ha="center", color=MUTED)
        if below:
            b = m
        else:
            a = m
    yc = cam_y + my * (a + b) / 2
    span = ts[-1] - ts[-2]
    ax.set_ylim(yc - span * 0.8, yc + span * 0.8)
    ax.set_xlim(ts[-2] - span * 0.1, ts[-1] + span * 0.1)
    ax.set_title("then 5 bisections bracket the surface", fontsize=9, loc="left")
    ax.set_xlabel("distance")
    save(fig, "march.svg")


# --- 3. ridged octaves -------------------------------------------------------
def fig_ridged():
    x = np.linspace(0, 6, 500)
    y = np.full_like(x, 0.37)
    n = gnoise2(x, y)
    fig, axes = plt.subplots(1, 3, figsize=(10.5, 3.1))
    ax = axes[0]
    ax.plot(x, n, color=MUTED, lw=1, label="gradient noise n")
    ax.plot(x, np.clip(1 - np.abs(n) * 1.6, 0, None) ** 2, color=ACC2, lw=1.6,
            label="(1 − 1.6·|n|)²")
    ax.axhline(0, color=GRID, lw=0.8)
    ax.set_title("one octave: a crest at every zero of n", fontsize=9, loc="left")
    ax.legend(fontsize=8, loc="lower right")
    ax = axes[1]
    xs = np.linspace(0, 4, 500)
    total, layers, norm = ridged(xs * 1.0, np.full_like(xs, 0.37), 5)
    acc = np.zeros_like(xs)
    cols = [ACC, ACC3, ACC4, ACC2, INK]
    for k, L in enumerate(layers):
        ax.fill_between(xs, acc / norm, (acc + L) / norm, color=cols[k], alpha=0.55, lw=0,
                        label=f"octave {k + 1}")
        acc = acc + L
    ax.set_title("five octaves stacked (fc-ridged)", fontsize=9, loc="left")
    ax.legend(fontsize=7, ncol=2, loc="upper right")
    ax.set_ylim(0, 1.15)
    ax = axes[2]
    m = np.linspace(-0.2, 1.2, 300)
    mm = smoothstep01((m - 0.30) / (0.56 - 0.30))
    ax.plot(m, mm, color=ACC3, lw=1.6, label="massif mask Hm")
    ax.plot(m, mm * 0.6 + 0.4, color=ACC, lw=1.2, ls="--", label="detail scale 0.4 + 0.6·Hm")
    ax.plot(m, mm * 0.92, color=ACC2, lw=1.2, ls=":", label="ridge scale 0.92·Hm")
    ax.axvspan(0.30, 0.56, color=GRID, alpha=0.5, lw=0)
    ax.set_xlabel("two smooth octaves of value noise")
    ax.set_title("the massif mask (MassifLo 0.30, MassifHi 0.56)", fontsize=9, loc="left")
    ax.legend(fontsize=7, loc="lower right")
    save(fig, "ridged.svg")


# --- 4. octaves follow distance ---------------------------------------------
def fig_octaves():
    t = np.geomspace(0.5, 900, 400)
    fig, ax = plt.subplots(figsize=(7.5, 3.2))
    for iw, ls in [(320, "-"), (1280, "--")]:
        pix = 2 * math.tan(math.radians(32)) / iw          # PixAng at HFov 64
        to = np.clip(np.log2(1 / (t * pix * 2 * 0.011)), 2, 8)       # fc-terrain-oct
        co = np.clip(np.floor(np.log(1 / (t * pix * 2 * 0.045)) / np.log(2.03)) + 1, 1, 5)  # fc-cloud-oct
        ax.plot(t, to, ls, color=ACC, lw=1.6, label=f"terrain octaves, {iw} px wide")
        ax.step(t, co, ls, color=ACC2, lw=1.4, where="post", label=f"cloud octaves, {iw} px wide")
    ax.set_xscale("log")
    ax.set_xlabel("distance t (world units, ~10 m each)")
    ax.set_ylabel("octaves evaluated")
    ax.set_title("Octaves finer than about two pixels are left out (HFov 64°)", fontsize=9, loc="left")
    ax.legend(fontsize=7.5, ncol=2, loc="lower left")
    ax.set_ylim(0, 8.6)
    save(fig, "octaves.svg")


# --- 5. haze -----------------------------------------------------------------
def fig_haze():
    t = np.linspace(0, 900, 500)
    cam_y, H, D = 8.0, 45.0, 520.0                  # fc_sky.ps HazeH, HazeDist
    fig, ax = plt.subplots(figsize=(7.5, 3.2))
    for my, col in [(-0.05, ACC2), (0.0, INK), (0.05, ACC), (0.15, ACC3)]:
        dens0 = math.exp(-cam_y / H)
        xk = my * t / H
        with np.errstate(divide="ignore", invalid="ignore"):
            f = np.where(np.abs(xk) < 1e-4, 1.0, (1 - np.exp(-xk)) / xk)
        od = dens0 * f * t
        ax.plot(t, np.exp(-od / D), color=col, lw=1.6,
                label=f"ray slope {my:+.2f}" + (" (down)" if my < 0 else ""))
    ax.set_xlabel("distance t")
    ax.set_ylabel("transmittance")
    ax.set_ylim(0, 1.02)
    ax.set_title("fc-haze: exponential-height air, integrated along the ray (camera at y = 8)",
                 fontsize=9, loc="left")
    ax.legend(fontsize=8)
    save(fig, "haze.svg")


# --- 6. phase function --------------------------------------------------------
def fig_phase():
    th = np.linspace(0, np.pi, 400)
    mu = np.cos(th)
    g = 0.45
    hg = (1 - g * g) / (1 + g * g - 2 * g * mu) ** 1.5
    p = hg * 0.25 + 0.55                                # fc-phase
    fig, axes = plt.subplots(1, 2, figsize=(9, 3.1))
    ax = axes[0]
    ax.plot(np.degrees(th), p, color=ACC2, lw=1.8, label="fc-phase = 0.25·HG + 0.55")
    ax.plot(np.degrees(th), hg / (4 * np.pi) * 4 * np.pi * 0.25, color=MUTED, lw=1, ls="--",
            label="0.25·HG alone")
    ax.set_xlabel("angle between view ray and sun (°)")
    ax.set_title("Henyey–Greenstein, g = 0.45, lifted", fontsize=9, loc="left")
    ax.legend(fontsize=8)
    ax = fig.add_subplot(1, 2, 2, projection="polar")
    axes[1].remove()
    full = np.linspace(0, 2 * np.pi, 600)
    pf = ((1 - g * g) / (1 + g * g - 2 * g * np.cos(full)) ** 1.5) * 0.25 + 0.55
    ax.plot(full, pf, color=ACC2, lw=1.6)
    ax.set_title("polar: sun to the right", fontsize=9)
    ax.set_yticklabels([])
    save(fig, "phase.svg")


# --- 7. erosion ----------------------------------------------------------------
def fig_erosion():
    N = 160
    xs = np.linspace(0, 1, N)
    X, Z = np.meshgrid(xs, xs)
    r, _, _ = ridged(X * 4 + 1.3, Z * 4 + 0.6, 5)
    hmap = (r * 0.9 + 0.15 * smoothstep01(1 - np.hypot(X - 0.5, Z - 0.5) * 1.6)).astype(float)
    orig = hmap.copy()
    # fc-erode-bake's constants (map units: texels; heights normalised)
    inertia, cap_k, min_cap, erode, deposit, evap, grav, steps = 0.06, 0.6, 0.0004, 0.35, 0.04, 0.015, 4, 48
    drng = np.random.default_rng(202)
    paths = []

    def interp(px, py):
        ix, iy = int(px), int(py)
        fx, fy = px - ix, py - iy
        h00, h10 = hmap[iy, ix], hmap[iy, ix + 1]
        h01, h11 = hmap[iy + 1, ix], hmap[iy + 1, ix + 1]
        gx = (h10 - h00) * (1 - fy) + (h11 - h01) * fy
        gy = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
        h = (h00 * (1 - fx) + h10 * fx) * (1 - fy) + (h01 * (1 - fx) + h11 * fx) * fy
        return ix, iy, fx, fy, gx, gy, h

    lim = N - 2
    ndrops = 30000
    for d in range(ndrops):
        px, py = drng.random() * lim, drng.random() * lim
        dx = dy = 0.0
        spd, wat, sed = 1.0, 1.0, 0.0
        path = [(px, py, 0.0)] if d < 14 else None
        for _ in range(steps):
            ix, iy, fx, fy, gx, gy, h = interp(px, py)
            dx = dx * inertia - gx * (1 - inertia)
            dy = dy * inertia - gy * (1 - inertia)
            ln = math.hypot(dx, dy)
            if ln < 1e-6:
                break
            dx, dy = dx / ln, dy / ln
            px, py = px + dx, py + dy
            if px < 0 or px > lim or py < 0 or py > lim:
                break
            dh = interp(px, py)[6] - h
            cap = max(-dh * spd * wat * cap_k, min_cap)
            if sed > cap or dh > 0:
                amt = min(dh, sed) if dh > 0 else (sed - cap) * deposit
                sed -= amt
            else:
                amt = -min((cap - sed) * erode, -dh)
                sed -= amt
            hmap[iy, ix] += amt * (1 - fx) * (1 - fy)
            hmap[iy, ix + 1] += amt * fx * (1 - fy)
            hmap[iy + 1, ix] += amt * (1 - fx) * fy
            hmap[iy + 1, ix + 1] += amt * fx * fy
            if path is not None:
                path.append((px, py, amt))
            spd = math.sqrt(max(spd * spd - dh * grav, 0))
            wat *= 1 - evap
        if path is not None:
            paths.append(path)

    def shade(hm):
        gy, gx = np.gradient(hm)
        return np.clip(0.55 - (gx + gy) * 18 + (hm - hm.min()) * 0.5, 0, 1)

    fig, axes = plt.subplots(1, 3, figsize=(10.5, 3.7))
    for ax in axes:
        ax.set_xticks([])
        ax.set_yticks([])
        ax.grid(False)
    axes[0].imshow(shade(orig), cmap="gray", origin="lower", vmin=0, vmax=1)
    for p in paths:
        p = np.array(p)
        axes[0].plot(p[:, 0], p[:, 1], color=ACC, lw=0.8)
        ero = p[1:, 2] < 0
        axes[0].scatter(p[1:, 0][ero], p[1:, 1][ero], s=3, color=ACC2, zorder=3)
        axes[0].scatter(p[1:, 0][~ero], p[1:, 1][~ero], s=3, color=ACC3, zorder=3)
    axes[0].set_title("droplet paths: orange erodes,\ngreen deposits", fontsize=9)
    delta = hmap - orig
    v = np.percentile(np.abs(delta), 99)
    axes[1].imshow(delta, cmap="BrBG", origin="lower", vmin=-v, vmax=v)
    axes[1].set_title(f"the change after {ndrops:,} droplets\n(brown cut, green filled)", fontsize=9)
    axes[2].imshow(shade(hmap), cmap="gray", origin="lower", vmin=0, vmax=1)
    axes[2].set_title("procedural + change\n(what fc-height returns)", fontsize=9)
    save(fig, "erosion.png")


# --- 8. one crown -----------------------------------------------------------
def fig_crown():
    T, droop, env = 9, 0.30, 1.0                 # FsTiers FsDroop FsEnv
    u = np.linspace(0, 0.999, 2000)
    fps = (1 - u) ** env
    k = np.minimum(np.floor((fps + droop) * T), T)
    ky = k / T
    reach = 1 - np.maximum(ky - droop, 0) ** (1 / env)
    y = ky - (u / reach) ** 2.5 * droop
    y = np.where(k < 1, -1, y)
    surf = np.where(y < 0.001, np.nan, y * 0.94 + 0.06)
    fig, ax = plt.subplots(figsize=(4.6, 7.2))
    for kk in range(1, T + 1):
        yk = kk / T
        rk = 1 - max(yk - droop, 0) ** (1 / env)
        uu = np.linspace(0, rk, 120)
        yy = (yk - (uu / rk) ** 2.5 * droop) * 0.94 + 0.06
        for s in (1, -1):
            ax.plot(s * uu, yy, color=ACC3, lw=0.7, alpha=0.6)
    for s in (1, -1):
        ax.plot(s * u, surf, color=INK, lw=1.8)
        ax.plot(s * u, fps * 0.94 + 0.06, color=ACC2, lw=1, ls="--")
    ax.plot([0, 0], [0, 0.06], color="#7a5a3a", lw=3)
    ax.text(0.3, 0.86, "envelope\n(1 − u)^FsEnv", color=ACC2, fontsize=8)
    ax.text(-1.0, -0.2, "green: whorls hang from the trunk and\ndroop by FsDroop·(u/reach)^2.5",
            color=ACC3, fontsize=8)
    ax.text(-1.0, -0.27, "black: the surface, the highest whorl reaching u", color=INK, fontsize=8)
    ax.set_aspect(1 / 0.28 / 1.05)   # true proportions: radius 0.28 x height
    ax.set_xlabel("u = distance from trunk / crown radius")
    ax.set_ylabel("height / tree height")
    ax.set_title("fc-tree-prof: FsTiers 9, FsDroop 0.30,\nFsEnv 1.0 (ragged reach off)",
                 fontsize=9, loc="left")
    ax.set_xlim(-1.05, 1.05)
    ax.set_ylim(0, 1.05)
    save(fig, "crown.svg")


# --- 9. jittered cells ---------------------------------------------------------
def fig_cells():
    C = 1.3
    crng = np.random.default_rng(303)
    fig, ax = plt.subplots(figsize=(5.6, 5.0))
    ax.grid(False)
    q = np.array([2.35, 2.55]) * C
    i0, j0 = int(q[0] // C), int(q[1] // C)
    ax.add_patch(Rectangle(((i0 - 1) * C, (j0 - 1) * C), 3 * C, 3 * C, fc="#e8f0f8", ec=ACC, lw=1.4))
    for i in range(6):
        for j in range(6):
            if crng.random() > 0.8:
                continue
            cx = (i + 0.5 + (crng.random() - 0.5) * 0.9) * C
            cz = (j + 0.5 + (crng.random() - 0.5) * 0.9) * C
            R = min(2.6 * 0.28 * (crng.random() * 0.3 + 0.85), C * 0.55)
            inside = abs(i - i0) <= 1 and abs(j - j0) <= 1
            ax.add_patch(Circle((cx, cz), R, fc=ACC3 if inside else "#c9d9c9", alpha=0.45 if inside else 0.35,
                                ec=ACC3, lw=0.8))
            ax.plot(cx, cz, ".", color=INK, ms=3)
    for k in range(7):
        ax.axvline(k * C, color=GRID, lw=0.8, zorder=0)
        ax.axhline(k * C, color=GRID, lw=0.8, zorder=0)
    ax.plot(*q, "x", color=ACC2, ms=9, mew=2)
    ax.text(q[0] + 0.1, q[1] + 0.12, "query point", color=ACC2, fontsize=8)
    ax.text((i0 - 1) * C + 0.05, (j0 + 2) * C + 0.08, "3 × 3 cells searched", color=ACC, fontsize=8)
    ax.set_xlim(0, 6 * C)
    ax.set_ylim(0, 6 * C)
    ax.set_aspect(1)
    ax.set_title("FsCell 1.3: centre jitter ≤ 0.45 cell, radius ≤ 0.55 cell", fontsize=9, loc="left")
    ax.set_xticks([])
    ax.set_yticks([])
    save(fig, "cells.svg")


# --- 10. level of detail for the forest -----------------------------------------
def fig_lod():
    t = np.geomspace(2, 900, 400)
    fig, ax = plt.subplots(figsize=(7.5, 3.0))
    for iw, ls in [(320, "-"), (1280, "--")]:
        pix = 2 * math.tan(math.radians(25)) / iw          # HFov 50 (alpine_forest)
        w = np.clip(0.3 / (t * pix) - 1, 0, 1)             # fc-forest-w
        R = 2.4 * 0.28
        fpl = np.clip((R / (t * pix) - 4) / 8, 0, 1)        # whorl detail in fc-tree-prof
        ax.plot(t, w, ls, color=ACC3, lw=1.6, label=f"crowns vs canopy slab (fc-forest-w), {iw} px")
        ax.plot(t, fpl, ls, color=ACC4, lw=1.3, label=f"whorl detail (R = 0.67), {iw} px")
    ax.set_xscale("log")
    ax.set_xlabel("distance t")
    ax.set_ylabel("weight")
    ax.set_title("Forest level of detail (HFov 50°)", fontsize=9, loc="left")
    ax.legend(fontsize=7.5, loc="lower left")
    save(fig, "lod.svg")


# --- 11. antialiasing samples -------------------------------------------------
def fig_aa():
    fig, axes = plt.subplots(1, 2, figsize=(8, 3.4))
    ax = axes[0]
    ax.grid(False)
    ax.add_patch(Rectangle((-0.5, -0.5), 1, 1, fc="#f2f4f6", ec=MUTED))
    off = [(0.125, 0.375), (0.375, -0.125), (-0.125, -0.375), (-0.375, 0.125)]
    ax.plot(0, 0, "o", color=INK, ms=7)
    for x, y in off:
        ax.plot(x, y, "o", color=ACC2, ms=6)
    ax.set_xlim(-0.6, 0.6)
    ax.set_ylim(-0.6, 0.6)
    ax.set_aspect(1)
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_title("one pixel: centre + 4 rotated-grid samples", fontsize=9)
    ax = axes[1]
    ax.grid(False)
    ax.set_xlim(0, 7)
    ax.set_ylim(0, 4)
    ax.set_aspect(1)
    ax.set_xticks([])
    ax.set_yticks([])
    for i in range(7):
        for j in range(4):
            ax.add_patch(Rectangle((i, j), 1, 1, fc="white", ec=GRID))
    keys = [["sky", "sky", "sky", "412", "396", "380", "371"],
            ["sky", "sky", "88", "86", "84", "83", "82"],
            ["sky", "71", "70", "69", "68", "67", "66"],
            ["55", "54", "54", "53", "52", "52", "51"]]
    from_sky = lambda s: s == "sky"

    def edge(a, b):
        if from_sky(a) != from_sky(b):
            return True
        if from_sky(a):
            return False
        a, b = float(a), float(b)
        return abs(a - b) > max(a, b) * 0.08
    for jr, row in enumerate(keys):
        for i, k in enumerate(row):
            e = (i > 0 and edge(k, row[i - 1])) or (jr > 0 and edge(k, keys[jr - 1][i]))
            if e:
                ax.add_patch(Rectangle((i, 3 - jr), 1, 1, fc="#f7dccb", ec=ACC2))
            ax.text(i + 0.5, 3 - jr + 0.5, k, ha="center", va="center", fontsize=7.5,
                    color=ACC2 if e else MUTED)
    ax.set_title("FcKey (hit distance): shaded pixels differ by > 8%\nfrom the left or upper neighbour",
                 fontsize=9)
    save(fig, "aa.svg")


if __name__ == "__main__":
    fig_pipeline()
    fig_march()
    fig_ridged()
    fig_octaves()
    fig_haze()
    fig_phase()
    fig_erosion()
    fig_crown()
    fig_cells()
    fig_lod()
    fig_aa()
