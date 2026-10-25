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
- **Status:** filed PSCatLabs/pscat#727
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
- **Status:** filed PSCatLabs/pscat#728
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
- **Status:** filed PSCatLabs/pscat#729
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
- **Status:** filed PSCatLabs/pscat#730
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
- **Status:** filed PSCatLabs/pscat#731
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

---

## 6. `cvs` writes reals at full precision, so strings sized for Ghostscript overflow

- **Kind:** pscat divergence from Ghostscript (the PLRM leaves the digit count to the implementation)
- **Status:** filed PSCatLabs/pscat#732
- **Where:** `cvs` (and so `=`/`==`, which print the same text) on reals
- **Found:** 2026-10-21, fractal_clouds#1 (debug printing in the trees work)

pscat converts a real with all its significant digits; Ghostscript 10.07.1
gives six. So `0.123456789012345 12 string cvs` works in gs and is a
`rangecheck` in pscat, and code that sizes its buffer the usual way breaks:

```postscript
0.123456789012345 20 string cvs ==   % gs: (0.123457)  pscat: (0.123456789012345)
0.123456789012345 12 string cvs ==   % gs: (0.123457)  pscat: rangecheck in cvs
```

Long reals are the common case once a program computes anything (here a
blend weight like `0.38612390214204787`), so printing a value for
debugging with a small string fails where it wouldn't in gs. Integer
arithmetic matches gs: both print `2147483647 2 mul` as `4294967294`.

**Suggested fix:** match Ghostscript's six significant digits in `cvs` and
`=` (keeping full precision in `==`, or behind a pscat-only operator), or
at least list the difference in the pscat skill's pitfalls.

## 7. Level 2 binary object operators are missing (`writeobject`, `printobject`, `setobjectformat`)

- **Kind:** missing PLRM Level 2 operators
- **Status:** filed PSCatLabs/pscat#733
- **Where:** `systemdict`
- **Found:** 2026-10-22, while looking for a fast way to save baked maps (fractal_clouds erosion and forest maps)

```
$ echo 'systemdict /writeobject known = systemdict /printobject known = systemdict /setobjectformat known =' | pscat --headless -
false
false
false
```

Ghostscript 10.07.1 prints `true` three times. These are how a Level 2
program writes arrays of numbers compactly. Without them, the only way to
save a million-entry real array is as text, which is slow to write and
slow to scan back in.

**Suggested fix:** implement them (binary object sequences, PLRM 3.14), or
see feature request 9 for a simpler pscat-only alternative.

---

The entries below are **feature requests**, not bugs. They come from the
fractal_clouds renders, where one 1280×800 landscape takes 25 to 35
minutes, almost all of it interpreting small numeric procedures. Numbers
are from pscat 0.6.2 on an Apple-silicon Mac.

## 8. Native noise operators

- **Kind:** feature request (performance)
- **Status:** filed PSCatLabs/pscat#734
- **Found:** 2026-10-22, fractal_clouds#1 and #11

Noise is the inner loop of every procedural texture and terrain, and in
pscat it is interpreted PostScript, both in fractal_clouds' own
libraries and in pscat's `lib/artkit.ps` (`noiseinit` / `noise2`).
Measured in fractal_clouds (`spikes/bench_noise3.ps`):

| call | µs per call |
|---|---|
| empty loop iteration | 0.25 |
| 3D value noise (`fc-noise3`) | 1.8 |
| 3D fBm, 4 octaves | 8.5 |
| 3D fBm, 6 octaves | 12.4 |

In the forest render, height evaluations (each one several octaves of
noise) were 86 of the 92 terrain calls per pixel.

**Suggested feature:** native operators with a seedable, documented
algorithm, so results are the same on every platform and a PostScript
fallback can reproduce them exactly. For example:

```postscript
seed noiseseed -                       % build the lattice / permutation tables
x y noise2  n      x y z noise3  n     % gradient noise
x y vnoise2 v      x y z vnoise3 v     % value noise
x y noise2d n dx dy                    % with analytic derivatives
x y oct gain lacunarity fbm2 v         % and fbm3, ridged2
```

A native call should cost about as much as an empty loop iteration, which
would make noise-bound renders several times faster. That's an estimate,
not a measurement.

## 9. Fast save and load of numeric arrays

- **Kind:** feature request (performance)
- **Status:** filed PSCatLabs/pscat#735
- **Found:** 2026-10-22

fractal_clouds bakes maps before rendering: erosion on a 1024² grid (about
1.5 min) and a forest density map (about 9 s). A large frame is rendered
as four parallel processes, and each one bakes the same maps again. Saving
the bake once and reading it back would remove that, but there's no fast
way to write a million reals (entry 7).

**Suggested feature:** either Level 2 `writeobject` (entry 7), or a pair of
pscat operators that read and write a packed array of 32- or 64-bit floats:

```postscript
array (path) writereals -
(path) n readreals array
```

**Workaround (2026-10-24, #18):** `lib/fc_cache.ps` prints a bake as
PostScript text, which `scripts/render.sh` files in `renders/cache/` (entry
15), and reads it back with `run`. That is exact (`cvs` gives the shortest
round-trip digits) and fast enough: 0.17 s to read a million reals, 0.6 s
to print them. Fixed-point hex (`readhexstring`; there is no
`writehexstring`) would lose bits, so the cached picture wouldn't match.

## 10. Parallel rendering of independent image bands

- **Kind:** feature request (performance)
- **Status:** filed PSCatLabs/pscat#736
- **Found:** 2026-10-22

pscat runs on one core. fractal_clouds' `scripts/render_bands.sh` starts
one pscat per horizontal band (each told which rows to render through a
define) and stitches the PNGs, which gives about 4× on four cores. Every
program with an expensive `colorimage` procedure needs the same thing.
PostScript's global state rules out threads inside one interpreter, but
separate processes work.

**Suggested feature:** `pscat --bands N`. It runs N copies of the program
with `/BandIndex` and `/BandCount` defined, has each render only its rows
(or lets the program read those names), and composites the pages.

## 11. A profiler

- **Kind:** feature request (tooling)
- **Status:** filed PSCatLabs/pscat#737
- **Found:** 2026-10-22

Finding where render time went meant hand-written call counters in
PostScript. **Suggested feature:** `pscat --profile`, reporting per
procedure (by name, for procedures bound to names) the call count,
inclusive time and exclusive time.

**Workaround in this repo:** `Profile` (`lib/fc_bench.ps`) wraps chosen
procedures with counters and `usertime` deltas: inclusive time only, whole
milliseconds, about 0.8 µs of overhead per wrapped call.

## 12. Research: a GPU path for pure numeric procedures

- **Kind:** research idea
- **Status:** filed PSCatLabs/pscat#742 (as a compiled kernel subset, CPU first, GPU as a preview backend)
- **Found:** 2026-10-22

The per-pixel procedures in a ray marcher are pure arithmetic over a few
arrays. A restricted subset of PostScript (numbers, arithmetic, `for`,
`if`, array reads, and names used as scratch variables) could be compiled
to a GPU kernel, behind an operator such as `proc w h kernelimage`.

Open questions:
- Floating-point results differ between GPUs, which matters for
  reproducible seeds.
- GPU support would add dependencies to a single headless binary.
- How much of the gain features 8 and 10 already give.

Worth investigating after those two.

## 13. Seeded renders differ between macOS and Linux

- **Kind:** reproducibility caveat (not a correctness bug)
- **Status:** filed PSCatLabs/pscat#738
- **Environment:** pscat 0.6.2: `aarch64-apple-darwin` on macOS 15 against
  `aarch64-unknown-linux-musl` and `x86_64-unknown-linux-musl` in Alpine 3.20
  containers
- **Found:** 2026-10-22 (fractal_clouds#35)

The same seeded piece renders different pixels on macOS and on Linux.
`gallery/mountains.ps` at `/ErN 256 def /ErDrops 20000 def /Res 0.25 def`
differs in 27k of 64k pixels, by up to 101 levels. The two Linux builds
(arm64 and x86_64) match each other exactly, on all four regression cases.

The trig and exponential operators round differently in the last bit. They
appear to use the platform libm: Apple's on macOS, musl's on Linux. The
erosion and noise then grow those differences into visible ones. Repro, with
400 lines of 7 results each:

```postscript
/p { 30 string cvs print ( ) print } def
1 1 400 { /i exch def
 i 0.37 mul sin p i 0.37 mul cos p i 0.013 mul 1.7 exp p i 0.01 mul ln p
 i 0.7 mul sqrt p 3.3 i 0.11 mul atan p i 0.01 mul 2.5 exp p (\n) print } for
```

Run it with `pscat --headless` on both platforms and diff the output. Out of
400 results each, these differ: `atan` 88, `cos` 17, `sin` 13, `exp` 4,
`ln` 0, `sqrt` 0. For example, `3.3 0.88 atan` gives `75.06858282186245` on
macOS and `75.06858282186246` on Linux. Ghostscript can't serve as the
reference here, because it computes reals in single precision
(`75.0685806`).

**Effect here:** "seed every piece so renders reproduce" holds only per
platform. The regression references in `tests/regress/linux/` are Linux
renders, and a Mac checks them with `scripts/regress.sh --docker` or compares
against a git ref with `--ref`.

**Possible request:** if cross-platform reproducibility matters to pscat,
bundle one libm (for example a port of musl's or of CORE-MATH) instead of
using the platform's.

## 14. No masked images (`ImageType 3`) and no `nulldevice`

- **Kind:** bug (missing operators)
- **Status:** filed PSCatLabs/pscat#739
- **Found:** 2026-10-24

Found while adding render passes (#33), pscat 0.6.2. An `image` with an
`ImageType 3` dictionary (a picture with a stencil mask, PostScript Level 3)
fails with `typecheck`, and `nulldevice` (Level 1) is `undefined`.
Ghostscript runs both. Repro:

```postscript
{ << /ImageType 3 /InterleaveType 3
   /DataDict << /ImageType 1 /Width 2 /Height 1 /BitsPerComponent 8 /Decode [0 1 0 1 0 1] /ImageMatrix [2 0 0 -1 0 1] /DataSource <ff000000ff00> >>
   /MaskDict << /ImageType 1 /Width 2 /Height 1 /BitsPerComponent 1 /Decode [1 0] /ImageMatrix [2 0 0 -1 0 1] /DataSource <80> >> >>
/DeviceRGB setcolorspace 100 100 scale image } stopped { (ImageType 3 failed\n) } { (ImageType 3 ok\n) } ifelse print
{ gsave nulldevice 0 0 10 10 rectfill grestore } stopped { (nulldevice failed\n) } { (nulldevice ok\n) } ifelse print
```

`pscat --headless` prints `failed` twice; `gs -sDEVICE=nullpage` prints `ok`
twice. (`(name) (w) file` is refused too, with `invalidfileaccess`; that
looks deliberate.)

**Effect here:** a landscape can't carry its mask as the picture's alpha
within PostScript. `lib/fc_passes.ps` clips instead (`fc-sky-clip`,
`fc-land-clip`: the mask's runs as `rectclip` rectangles, hard-edged), and
renders without painting through an empty clip (`0 0 0 0 rectclip`), which
pscat honours while still running the image's data procedure. A soft alpha is
the `--pass mask` PNG.

**Possible request:** `ImageType 3` (at least `InterleaveType 3` with a 1-bit
mask) and `nulldevice`.

## 15. No way to write a file: `file` refuses every write, and the file operators are missing

- **Kind:** missing feature (file output)
- **Status:** filed PSCatLabs/pscat#740
- **Found:** 2026-10-24, fractal_clouds#18 (caching the erosion and forest bakes)

pscat 0.6.2 refuses to open any file for writing, whatever the path, even
`%stdout`, and has none of the Level 2 operators that manage files:

```postscript
/try { dup print ( ) print { (w) file dup (hi\n) writestring closefile (ok\n) print } stopped { (fail\n) print } if } def
(renders/x.txt) try (x.txt) try (/tmp/x.txt) try (%stdout) try
[ /renamefile /deletefile /filenameforall /writehexstring /writeobject ]
{ dup systemdict exch known { pop } { 20 string cvs print ( undefined\n) print } ifelse } forall
```

`pscat --headless` prints `fail` four times (`invalidfileaccess`) and lists all
five operators as undefined. Ghostscript (`gs -dNOSAFER`) writes the files and
has the operators. Entry 14 noted the refusal in passing; this is the full
picture. Reading works: `(path) run`, `(path) (r) file`, `readstring`,
`readhexstring` and `token`.

**Effect here:** `lib/fc_cache.ps` (#18) can't write its cache. It prints the
bake to stdout between `%%FcCacheBegin` and `%%FcCacheEnd` lines, and
`scripts/render.sh` cuts that out of the log into `renders/cache/`, using a
temporary file and `mv`, since the PostScript can't rename. Without a
wrapper script, nothing is cached.

**Possible request:** writing files in a directory the user allows (a
`--allow-write DIR` option), with `renamefile` and `deletefile`; or the
`writereals` of entry 9. As a workaround, text written with `print` is
fast enough: pscat's `cvs` prints a real with its shortest round-trip
digits, so a million reals print in 0.6 s (in 64 KB buffers; 2.5 s with a
`print` per number) and `run` reads them back exactly in 0.17 s.

## 16. The MCP render tool stops every call at 60 s

- **Kind:** feature request (agents and MCP)
- **Status:** filed PSCatLabs/pscat#741
- **Found:** 2026-10-24

The pscat MCP server limits each `render_postscript` call to 60 s (the server
has a `--timeout` flag, but the default plugin setup and the server
instructions use 60 s). A landscape here takes 30 to 60 core-minutes, and even a
quarter-size draft takes minutes, so an agent working only through MCP can't
render these pieces.

**Possible request:** async render jobs (start, poll with progress, fetch,
cancel), or a documented way to raise the timeout for a local server.
