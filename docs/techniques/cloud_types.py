#!/usr/bin/env python3
"""The cloud-type contact sheet for docs/techniques.html (fractal_clouds#14).

    python3 docs/techniques/cloud_types.py            # from the repo root
    python3 docs/techniques/cloud_types.py --compose  # paste only; skip the renders

Renders each panel of docs/techniques/cloud_types.ps with scripts/render.sh
(into renders/cloud_types/), one after another, then pastes them with their
labels into docs/techniques/cloud_types.png. Needs Pillow. Set RES=0.5 for
a quick half-size check, DPI for a bigger sheet.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "renders", "cloud_types")
PANELS = ["Stratus", "Altocumulus", "Cirrus", "Cumulus", "Nimbostratus", "Cumulus + Altocumulus + Cirrus"]
COLS = 3
GUTTER = 8
LABEL = 18


def render(i):
    args = [os.path.join(ROOT, "scripts", "render.sh"), "-D", f"Panel={i}"]
    if os.environ.get("RES"):
        args += ["-D", f"Res={os.environ['RES']}"]
    args.append("docs/techniques/cloud_types.ps")
    env = dict(os.environ, OUT=OUT)
    subprocess.run(args, cwd=ROOT, env=env, check=True)
    os.replace(os.path.join(OUT, "cloud_types.png"), os.path.join(OUT, f"panel{i}.png"))
    os.replace(os.path.join(OUT, "cloud_types.log"), os.path.join(OUT, f"panel{i}.log"))


def compose():
    panels = [Image.open(os.path.join(OUT, f"panel{i}.png")).convert("RGB") for i in range(len(PANELS))]
    w, h = panels[0].size
    rows = (len(panels) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * w + (COLS + 1) * GUTTER, rows * (h + LABEL + GUTTER) + GUTTER), "white")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default(size=12)
    except TypeError:                      # Pillow < 10.1
        font = ImageFont.load_default()
    for i, (im, label) in enumerate(zip(panels, PANELS)):
        x = GUTTER + (i % COLS) * (w + GUTTER)
        y = GUTTER + (i // COLS) * (h + LABEL + GUTTER)
        sheet.paste(im, (x, y))
        draw.text((x, y + h + 3), label, fill="#22262b", font=font)
    path = os.path.join(ROOT, "docs", "techniques", "cloud_types.png")
    sheet.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    if "--compose" not in sys.argv:
        for i in range(len(PANELS)):
            render(i)
    compose()
