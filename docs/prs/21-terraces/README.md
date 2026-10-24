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
| 3 | hashed (not periodic) hard beds and treads; beds cut from the ground without its fine detail, which goes back on top | 576×300 (DPI 216) | see below | |

Round 1 and 2 reasons: "repeated horizontal terraces look artificial",
"horizontal shelves look mechanically cut", "conspicuous stair-step
terraces". Round 2's hard-bed choice used `sin(k)` with k in radians, which
repeats every 6.3 beds: a fixed rhythm. Round 3 fixes that with a hash and
keeps the gully detail on the ledges, so the lips are ragged instead of
ruler-straight.
