# Terraces in the geometry (#21): judging protocol and verdicts

Second attempt at #21, after the shading-only strata of PR #63 lost every
blind round. `TerraceAmp` (lib/fc_terrain.ps) cuts steep outcrops into
dipping beds in `fc-height-proc` itself, so ledges change silhouettes, the
march and the normals.

## Protocol, fixed before round 1

- View: `spikes/terraces_view.ps` (the gallery `mountains` massif, seed 5,
  with a 30° lens and the sun behind the camera, so the faces toward us are
  sunlit and a bed spans 10+ px). Crop `[0.0 0.5 0.6 1.0]`.
- Pair: the same view and settings (`CrevAmp=0.5 CrestAmp=0.3` in both),
  only `TerraceAmp` differs (0 vs 1). `off.png` is A, `on.png` is B.
- Judge: `scripts/codex_pairwise.sh off.png on.png round_N`, both orders.
- A win is REALISM = new in both orders. Aesthetics are recorded, not
  decisive.
- At most 3 judged rounds. A win would earn one extra round on the gallery
  massif to decide the default; a loss ships the feature opt-in, as
  "Part of #21".

## Rounds

| Round | Change | Crop | Order 1 (old first) | Order 2 (new first) |
|---|---|---|---|---|
| 1 | step 3, tread 0.65, dip [0.40 0.20], every bed a ledge | 384×200 (DPI 144) | old, old | old, old |
| 2 | dip [0.60 0.25], only 45% of beds stand out (`TerraceBeds`) | 384×200 (DPI 144) | old, old | old, old |
| 3 | hashed (not periodic) hard beds and treads; beds cut from the ground without its fine detail, which goes back on top | 576×300 (DPI 216) | old, old | old, old |

Round 1 and 2 reasons: "repeated horizontal terraces look artificial",
"horizontal shelves look mechanically cut", "conspicuous stair-step
terraces". Round 2's hard-bed choice used `sin(k)` with k in radians, which
repeats every 6.3 beds: a fixed rhythm. Round 3 fixes that with a hash and
keeps the gully detail on the ledges, so the lips are ragged instead of
ruler-straight.

Round 3 reasons: "angular ledges and abrupt cliff bands look artificially
cut", "fewer conspicuous block-like interruptions" (for the old one).

## Verdict

Lost all three rounds, in both orders, on realism and aesthetics alike. The
judge consistently prefers the continuous, eroded-looking slopes over any
visible bedding, even sparse, dipping, faulted beds with ragged lips. Per
the protocol, terraces ship opt-in (`TerraceAmp 0` by default) and the PR is
"Part of #21"; the gallery massif round was not run, since it only decides
the default after a win.

## Cost

`-D Profile=true`, the same 192×100 crop of the test view, DPI 72 (the
machine was shared, so timings are approximate):

| | `fc-height` µs/call | `fc-height` share | `fc-render` ms |
|---|---|---|---|
| `TerraceAmp 0` | 59.7 | 66.5% | 84 157 |
| `TerraceAmp 1` | 89.5 | 74.6% | 121 573 (+44%) |

The view is almost all massif in outcrop patches, so this is near the worst
case; most of it is the slope gate's three 2-octave ridged samples. Off, the
term is one comparison and one store per height call.
