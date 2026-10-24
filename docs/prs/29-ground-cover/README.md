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
