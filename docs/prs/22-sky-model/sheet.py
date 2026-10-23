#!/usr/bin/env python3
"""Lay the sweep.sh tiles out as a labelled contact sheet (docs/prs/22-sky-model/sweep.png)."""
import os, sys
from PIL import Image, ImageDraw

src = sys.argv[1] if len(sys.argv) > 1 else "renders/sweep22"
dst = sys.argv[2] if len(sys.argv) > 2 else "docs/prs/22-sky-model/sweep.png"
tiles = [("t0540", "05:40  sun -4.8  dawn, exposure 3"), ("t0610", "06:10  sun +1.4  sunrise, exposure 2.2"),
         ("t0700", "07:00  sun 14"), ("t0900", "09:00  sun 39"),
         ("t1200", "12:00  sun 55"), ("t1500", "15:00  sun 39"),
         ("t1700", "17:00  sun 14"), ("t1750", "17:50  sun +1.4  sunset, exposure 2.2"),
         ("t1820", "18:20  sun -4.8  dusk, exposure 3"), ("t1900", "19:00  sun -14, moon 25  exposure 4"),
         ("t2300", "23:00  moon 45  exposure 4"), ("t0300", "03:00  moon 20  exposure 4")]
cols, label = 4, 16
ims = [(Image.open(os.path.join(src, f"{n}.png")).convert("RGB") if os.path.exists(os.path.join(src, f"{n}.png")) else None, t)
       for n, t in tiles]
w, h = next(im.size for im, _ in ims if im is not None)
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * (h + label)), (24, 24, 24))
draw = ImageDraw.Draw(sheet)
for i, (im, text) in enumerate(ims):
    x, y = (i % cols) * w, (i // cols) * (h + label)
    if im is not None:
        sheet.paste(im, (x, y + label))
    draw.text((x + 4, y + 2), text, fill=(230, 230, 230))
sheet.save(dst)
print("wrote", dst, sheet.size)
