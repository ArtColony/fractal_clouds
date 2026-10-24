# #24: current curve (`/Exp`) against filmic (`/ACES`), blind pairwise

`scripts/codex_pairwise.sh OLD NEW`: Codex (high effort) sees the two images
under neutral names, in both orders. "old" is `ToneCurve /Exp`, "new" is
`ToneCurve /ACES`. The full reasons are in `verdicts/`.

Bar set before reading any verdict: ACES becomes the default only if it wins
realism in both orders on mountains and alpine_forest, and loses no other
piece in both orders.

| Pair | Order 1 (old first) | Order 2 (new first) |
|---|---|---|
| mountains, Res 0.5 | realism new, aesthetics new | realism new, aesthetics new |
| alpine_forest, Res 0.5 | new, new | old, new |
| evening_lake, Res 0.5 | new, new | old, new |
| charted_range, Res 0.5 | old, old | new, new (called identical: a tie) |
| mountains, full detail | old, old | new, new (called identical: a tie) |
| alpine_forest, full detail | new, new | old, new |

ACES won aesthetics in both orders on alpine_forest (both sizes),
evening_lake and mountains at Res 0.5. Realism split by position everywhere
except mountains at Res 0.5, and at full detail mountains was a tie. The bar
is not met, so `/Exp` stays the default and `/ACES` is opt-in
(`ToneCurve /ACES`, or the `/Filmic` preset).

Images (all macOS renders):

- `*-exp-res05.png` and `*-aces-res05.png`: the regression settings
  (Res 0.5, ErN 256, ErDrops 20000), from `scripts/regress.sh --ref main`
  with `/ACES` made the default for that run.
- `*-exp-full.png` and `*-aces-full.png`: the full-detail 320×200 pieces.
- `grades.png`: mountains at the regression settings. Top row: no grade,
  `/Warm`, `/CoolMuted`. Bottom row: `/Matte`, `/SplitTone` with `/Vignette`.
