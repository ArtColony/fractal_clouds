# pscat issues log

Problems found with pscat and its agent skills while working on fractal_clouds,
kept here until they are filed against
[PSCatLabs/pscat](https://github.com/PSCatLabs/pscat/issues).

Environment unless noted: pscat 0.6.2 release bundle
(`pscat-0.6.2-aarch64-apple-darwin.tar.gz`), macOS 15 (Darwin 24.6) on arm64, no font packs
installed. Skills copied from `plugin/skills/` at tag `v0.6.2`.

Status values: `open` (not filed yet), `filed #N`, `wontfile` (with the reason).

---

## 1. Skills say the LaserWriter 35 fonts "always resolve", but they need the texgyre pack

- **Kind:** skill docs
- **Status:** open
- **Where:** `plugin/skills/pscat/SKILL.md` line 129 (Fonts), `plugin/skills/psart/SKILL.md` line 102 (Type is material)
- **Found:** 2026-10-21

The skills say: "The LaserWriter 35 always resolve (Palatino, Bookman,
AvantGarde, ZapfChancery, NewCenturySchlbk, Symbol, ZapfDingbats, …)". On a
bare release install, only Helvetica, Times and Courier (12 faces) resolve.
The rest belong to the `texgyre` font pack, and `findfont` raises an error:

```
$ echo '/Bookman-Demi findfont pop' | pscat --headless -
%%[ Error: invalidfont; OffendingCommand: findfont; Line: 1 ]%%
pscat: font /Bookman-Demi is in the texgyre font pack, which is not installed; run `pscat fonts install` (or `pscat fonts install --pack texgyre`)
```

`pscat --fonts` on the same install lists only Helvetica, Times and Courier.

**Suggested fix:** say that only Helvetica, Times and Courier are built in, and
that the rest of the LaserWriter 35 come from `pscat fonts install`
(`--pack texgyre`). Or bundle texgyre in the release archive.

## 2. Skills say unknown font names "substitute Helvetica", but pack fonts error out

- **Kind:** skill docs (possibly a behaviour question)
- **Status:** open
- **Where:** `plugin/skills/pscat/SKILL.md` (Fonts: "Unknown names substitute Helvetica rather than erroring"), `plugin/skills/psart/SKILL.md` ("an unknown name silently becomes Helvetica")
- **Found:** 2026-10-21

The fallback happens only for names pscat has never heard of. A name that
belongs to an uninstalled font pack raises `invalidfont` (see #1):

```
$ echo '/NoSuchFont-Bold findfont 12 scalefont setfont 10 10 moveto (x) show' | pscat --headless -   # exit 0, Helvetica
$ echo '/Palatino-Italic findfont pop' | pscat --headless -                                          # exit 1, invalidfont
```

The error message is useful, but an agent that trusts the skill expects a
fallback, not a failed render.

**Suggested fix:** describe both cases in the skills. It's also worth
deciding whether a pack font should fall back the way an unknown name does
(with a warning), or keep erroring.

## 3. psart's "A sketch to start from" fails on a bare install

- **Kind:** skill docs
- **Status:** open
- **Where:** `plugin/skills/psart/SKILL.md`, the final code block
- **Found:** 2026-10-21

The starter sketch uses `/Palatino-Italic`, so running it as written on a
fresh release install stops at `findfont` (line 8) with `invalidfont`. The
partial PNG is still written, but the run exits 1. This is the first thing
an agent tries.

**Suggested fix:** use `/Times-Italic` in the sketch, or add a note that it
needs `pscat fonts install`. CI could run the skills' code blocks against a
bare bundle with no font catalog.

## 4. `/Interpolate true` on images is ignored

- **Kind:** pscat divergence from Ghostscript (PLRM allows ignoring it; it's a hint)
- **Status:** open
- **Where:** `image` / `colorimage` with an image dictionary, PNG output
- **Found:** 2026-10-21, fractal_clouds#1 spike

An 8×4 RGB image scaled up to 100×100 points renders as hard-edged blocks
whether or not the image dictionary has `/Interpolate true`. Ghostscript
10.07.1 (`gs -sDEVICE=png16m -r144`) renders the same file with the
interpolated half smooth. A program that computes an image at low resolution
(a ray-marched cloud, say) and wants it scaled smoothly has to upsample by
hand in PostScript.

```postscript
%%BoundingBox: 0 0 100 100
/W 8 def /H 4 def /row W 3 mul string def /j 0 def
100 100 scale
<< /ImageType 1 /Width W /Height H /BitsPerComponent 8 /Decode [0 1 0 1 0 1]
   /ImageMatrix [W 0 0 H neg 0 H] /Interpolate true
   /DataSource { 0 1 W 1 sub { /i exch def row i 3 mul i 255 mul W 1 sub idiv put
     row i 3 mul 1 add j 255 mul H 1 sub idiv put row i 3 mul 2 add 128 put } for
     /j j 1 add def row } >>
/DeviceRGB setcolorspace image showpage
```

**Suggested fix:** honour `/Interpolate` with bilinear sampling in the PNG
and PDF backends (in PDF it's just the `/Interpolate` key on the image), or
document that it's ignored.

## 5. Many low-alpha layers stall: `setalpha` blending loses precision in 8 bits

- **Kind:** pscat rendering precision
- **Status:** open
- **Where:** `setalpha` fills, PNG output
- **Found:** 2026-10-21, fractal_clouds#1 spike (splat renderer)

Stacking many faint translucent fills never reaches the colour the maths
says it should, and stops early. White over black, 10×10-point squares:

| alpha × layers | expected (`255·(1−(1−a)ⁿ)`) | pscat 0.6.2 |
|---|---|---|
| 0.05 × 40 | 222 | 221 |
| 0.01 × 200 | 221 | 192 |
| 0.002 × 1000 | 221 | **128** |

```postscript
%%BoundingBox: 0 0 40 10
0 setgray 0 0 40 10 rectfill  1 setgray
0.01 setalpha 200 { 0 0 10 10 rectfill } repeat
0.05 setalpha 40 { 10 0 10 10 rectfill } repeat
0.002 setalpha 1000 { 20 0 10 10 rectfill } repeat
showpage
```

The precision is lost somewhere in compositing; the exact mechanism isn't
confirmed. The 0.002 row fits alpha being stored as a multiple of 1/255
with each blend rounded to 8 bits, so that a layer changes nothing once
`(target − current) × alpha < 0.5`. The 0.01 row doesn't fit that: 3/255
predicts a stall near 213, and pscat gives 192. Because the cut-off depends
on each channel's distance to its target, colours also
**drift in hue**: in the splat cloud render, red kept moving toward the cloud
colour while green stalled, leaving purple fringes on cloud edges
(`docs/spikes/1-cloud-timing.md`).

**Confirmed in a real scene.** `spikes/composite_check.py` takes the exact
301,814 discs pscat draws for the splat render, dumped with `/Dump true`,
and blends them outside pscat over pscat's own sky. A floating-point blend
has **no fringes**. An 8-bit model (alpha rounded to 1/255, every blend
rounded) **reproduces the fringes in the same places**. pscat's own render
is worse than that model: stronger fringes and a greyer cloud field overall.
So pscat loses even more precision than per-blend 8-bit rounding.
Side by side (pscat | float | 8-bit model):
`docs/spikes/1-cloud-timing/fringe-pscat-float-8bit.png`.

**Suggested fix:** composite in a higher-precision buffer (16-bit or float)
and quantise once at the end, or at least keep alpha unquantised and dither
the per-blend rounding. Volume splatting, soft glows and airbrush effects
all stack hundreds of faint layers.
