#!/usr/bin/env python3
"""Make the blue-noise tile in lib/fc_clouds.ps (#27).

    python3 docs/prs/27-cloud-jitter/blue_noise.py 64 > tile.hex

Void and cluster (Ulichney 1993) on an N x N torus with a Gaussian filter
(sigma 1.9), seeded, so it reproduces. Prints the ranks scaled to 0..255,
row by row, as hex; writes a 4x preview to bn<N>.png in the current
directory.
"""
import sys

import numpy as np
from PIL import Image

N = int(sys.argv[1]) if len(sys.argv) > 1 else 64
sigma = 1.9
rng = np.random.default_rng(27)
f = np.fft.fftfreq(N)
kern = np.exp(-2 * np.pi**2 * sigma**2 * (f[:, None] ** 2 + f[None, :] ** 2))


def energy(b):
    return np.real(np.fft.ifft2(np.fft.fft2(b) * kern))


def tightest_cluster(b):
    return np.argmax(np.where(b == 1, energy(b), -np.inf))


def largest_void(b):
    return np.argmin(np.where(b == 0, energy(b), np.inf))


ones = N * N // 10
b = np.zeros((N, N))
b.flat[rng.choice(N * N, ones, replace=False)] = 1
while True:  # relax the initial pattern
    c = tightest_cluster(b)
    b.flat[c] = 0
    v = largest_void(b)
    b.flat[v] = 1
    if v == c:
        break
rank = np.zeros(N * N, int)
bb = b.copy()
for r in range(ones - 1, -1, -1):
    c = tightest_cluster(bb)
    bb.flat[c] = 0
    rank[c] = r
bb = b.copy()
for r in range(ones, N * N):
    v = largest_void(bb)
    bb.flat[v] = 1
    rank[v] = r
vals = (rank.reshape(N, N) * 256 // (N * N)).astype(np.uint8)
print(vals.tobytes().hex())
Image.fromarray(vals).resize((N * 4, N * 4), Image.NEAREST).save(f"bn{N}.png")
