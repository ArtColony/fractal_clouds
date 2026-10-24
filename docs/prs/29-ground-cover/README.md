# Foreground ground cover (#29): judging protocol and verdicts

`GroundOn` (lib/fc_terrain.ps, lib/fc_ground.ps) adds boulders in the
geometry, stones and shrubs and a clumpy grass texture in the shading, and
`GroundOct` more terrain octaves, all confined to the near ground.

## Protocol, fixed before round 1

- View: the gallery `alpine_forest` at DPI 288 (1280×800), crop
  `[0.62 0.74 1 1]`: the meadow at the lower right, the only gallery
  foreground with grass, forest floor and open ground together (the bottoms
  of `evening_lake` and `charted_range` are water; `mountains` has a bare
  rock ridge, which only tests the boulders).
- Pair: the same piece and settings, only `GroundOn` differs (false vs
  true). `off.png` is the old one, `on.png` the new one, cut to the crop.
- Judge: `scripts/codex_pairwise.sh off.png on.png round_N`, both orders.
- A win is REALISM = new in both orders (as in docs/prs/21-terraces/).
  Aesthetics are recorded, not decisive.
- At most 3 judged rounds, the same crop every round. A loss ships the
  feature opt-in, as "Part of #29".

## Rounds

| Round | Change | Order 1 (old first) | Order 2 (new first) |
|---|---|---|---|
| 1 | boulders (2.6-unit cells, radius up to 0.42), stones and shrubs in shading, grass texture, `GroundRough` 0.12, `GroundOct` 3 | new, new | new, new |

Round 1 reasons: "B's ground texture suggests uneven terrain and low
vegetation; A's looks overly smooth", "more varied light and shadow across
the clearing, adding depth" (both orders; both note the conical trees).

## Verdict

Won in round 1, realism and aesthetics, in both orders: no further rounds.
`GroundOn` stays false in the library (other pieces and spikes are
unchanged) and is turned on in the five gallery pieces with near ground:
mountains, alpine_forest, evening_lake, charted_range and storm.

After the win, `GroundFar` (0.6) keeps the roughness to the near ground
(it reached mid-distance slopes at 640 px and broke up their snow). As a
check for turning it on in `mountains`, the whole gallery frame at
640×400 (`mountains/off.png`, `mountains/on.png`, not a judged round of
the protocol) also went to the new one in both orders, realism and
aesthetics: "rougher foreground ridges feel more like weathered rock",
"irregular snow boundaries look more natural".

Cost, `mountains` at 640×400 with `Profile`: render 664 s off, 781 s on
(+18%); `fc-height` 51.7 → 64.1 µs a call over the same ~10 M calls (the
machine was shared with other renders, so take these as ±10%).
