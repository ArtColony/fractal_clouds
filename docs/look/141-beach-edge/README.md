# #141 beach edge, round 2: dune grass

Crops of tropical_island (1280x800 frame, crop [0.4 0.45 1 0.85], 2x supersampled through the kernel test build).

- `edge-r2-before.png`: `CoastRag` 0.8 (#154).
- `edge-r2-dune05.png`: plus `CoastDune` 0.5 (the piece's setting).
- `edge-r2-dune1-sharp-rejected.png`: `CoastDune` 1 with `CoastRagW` 0.3.

Blind Codex pairs, before against each variant, in both orders. In each `verdicts/` file, A and B are the images in the order shown: order 1 shows the old image first, order 2 the new.

| Variant | Realism | Aesthetics |
|---|---|---|
| `t9`: `CoastDune` 0.5 | new, new | new, new |
| `t7`: `CoastDune` 1, `CoastRagW` 0.3 | old, old | old, old |
| `t8`: `CoastDune` 1, `CoastRag` 1.2, `CoastRagW` 0.3 | old, old | new, old |

Codex said the full-strength straw band "looks slightly painted onto the slope". It called the winning version "nearly indistinguishable at this size", so the gain is small.

Found along the way: on the flat beach top, the grass that `CoastRag` lets through rendered lime-green. A dune tint of at least 0.75 there fixes that.
