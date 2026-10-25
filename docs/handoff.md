# Handoff: after epic #36, toward the pscat release

Written on 2026-10-25 by the lead session that ran epic #36. Replace this file when the next handoff is due.

## Where things stand

Epic #36 (the landscape toolkit) is finished, and the owner closes it.

- **Write-up:** `docs/landscape-toolkit.html`. It covers the features, numbers and gallery, with the showcase piece `gallery/golden_coast.ps` as its hero.
- **How the renderer works:** `docs/techniques.html`. Both pages are also published as claude.ai Artifacts; the links are in #36's last comment.
- **Closed by merged PRs:** #13, #14, #15, #17, #18, #19, #20, #22, #23, #24, #25, #26, #27, #28, #29, #31, #32, #33, #34, #38, #39, #40, #49 and #53.
- **Open, waiting on the owner:**
  - **#21 (terraces and fractured rock):** two attempts, #63 and #67, are merged as opt-in, but both lost blind Codex pairwise in every round. Decide whether Codex's taste is the bar, or yours.
  - **#30 (thermal erosion and far map):** opt-in, merged in #62. Talus reads only from above, and the far map shows no drainage channels.

The owner's goal for this stage was "a usable library MVP with an attractive gallery piece as a starting off point to illustrate what can be done with pscat". **Next comes releasing pscat to a wider audience.** Iterating on this library comes after that.

## Actions only the owner can take

1. **Cut the first library release.** Push a tag such as `v0.1.0`. `.github/workflows/release.yml` then builds the tarball, the standalone techniques page and `SHA256SUMS`. Until a tag exists, other projects can't pin the library (`.fc-version` and `scripts/fetch_fc.sh`; see `docs/template-repo-notes.md`).
2. **Optional: GitHub Pages** for `docs/`, if you want public URLs besides the Artifacts.
3. **Set the bar for #21:** Codex pairwise, or your own eye.
4. **Mark pieces final.** Every gallery piece is still `% Status: draft`.
5. **Triage the pscat issues** filed on 2026-10-25 as PSCatLabs/pscat#727–#742 (see `docs/pscat-issues.md` for the mapping).

## Phase A: help the pscat release

This repo is pscat's showcase. Useful work here, in order:

1. **Follow the upstream pscat issues.** All 16 entries of `docs/pscat-issues.md` are filed (PSCatLabs/pscat#727–#742). For a public release, the ones that matter most are:
   - first-run fonts and skills: #727, #728, #729;
   - cross-platform reproducibility: #738;
   - speed: native noise #734, `--bands` #736, array I/O #735;
   - masked images #739, file writing / `--allow-write` #740;
   - MCP async renders: #741.

   When one ships, adopt it here. #16 tracks the native operators, and #87 tracks soft-alpha passes.
2. **Showcase material for the pscat README or site:** `gallery/previews/golden_coast-1280x800.png`, and the refreshed 640x400 previews of mountains, alpine_forest, pnw_coast and tropical_island. Fix #79 (the tropical_island reframe) first if that piece will be shown.
3. **Time budget for any new showcase render:** about 60 core-minutes at 1280x800. Use `render_bands.sh --auto 3`, which turns on the bake cache, wrapped in a slot lock.

## Phase B: library iteration (later)

Look follow-ups, filed:

- **#77:** regular ripple banding on the sea at low sun. This is the main weakness of the showcase.
- **#78:** the wet-sand mirror lights cliff walls (golden_coast works around it with `WetSand 0`), and narrow map stacks break the march, which leaves stack tops boxy.
- **#79:** reframe tropical_island; storm's rain curtain; the edge of the PNW fog; far palms.
- **#80:** an olive horizon band at low sun with the sky model; soft billow cumulus.
- **#81:** a plan-only mode for `render_bands.sh`, and a generic subject for `codex_pairwise.sh`.
- **#84–#86:** ground cover up close, topiary pines, faint sun shafts.
- **#87:** soft-alpha render passes, once pscat has masked images.
- **#88:** 1280x800 previews for every piece; mark pieces final.
- **#89:** cut the v0.1.0 library release (owner).
- **#21 and #30,** as above.

Known limitations, written up in their PR bodies:

- **Ground cover (#69):** a grazing ray can step over a small rock, and boulders read as smooth pills up close.
- **Crowns (#73):** pines can read as topiary up close.
- **Sun shafts (#70):** faint.
- **Render passes (#71):** compositing uses hard clips, because pscat has no alpha masks.

## How the epic was run, and what to keep

- **The pattern that worked:** a lead session dispatches one subagent per issue in its own worktree. A fresh opus reviewer checks each PR, the findings go back to the implementer, and the lead updates the branch, waits for CI and merges. Keep one in-flight issue per shared library.
- **Concurrency:** no more than about 3 implementers at once. Four fable agents in parallel hit the account's session limit within hours; default to opus. Every render goes through a shared 3-slot lock (a `mkdir`-based wrapper script; `BAND_WRAP` for `render_bands.sh`).
- **Stalls:** if an agent hasn't committed for over an hour, check on it. One agent sat idle for about 6 hours behind a hung `codex exec`. Run Codex with a timeout and with stdin redirected (`</dev/null`).
- **GitHub auto-close:** a PR opened with `Closes #N` and later edited to say "Part of #N" still closes the issue when it merges. That happened to #21 and #34, and both were reopened. Check the issue after merging such a PR.
- **Merge order:** a PR that adds regress references makes every later PR re-run regress. Merging main into the branch and regenerating the references in Docker (`regress.sh --docker --update`) settles it.
- **Blind pairwise** (`scripts/codex_pairwise.sh`, both orders) has strong first-position bias. A split result is a tie, not a loss.
