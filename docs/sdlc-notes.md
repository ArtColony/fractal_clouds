# SDLC notes for ArtColony projects

> **Status: working draft, not adopted.** ArtColony's SDLC is still being
> decided. These notes are a proposal and nobody is bound by them. They are
> merged so they live on `main` and later PRs can revise them. Read what's
> here as "what we did and what we'd suggest", not as policy.

The goal: agents can work issue to merged PR without waiting on the owner,
while anything that changes what the repo trusts, or what it publishes, still
needs the owner. It's adapted from pscat's `SDLC.md` (its "agent-full" merge
policy, CODEOWNERS exceptions and release lifecycle) for a repo whose product
is images, not a binary.

## What's different about an art repo

- **The test is looking.** Code can pass every check and still be ugly, or
  not read as clouds at all. Lint and render-clean checks are necessary but
  never enough. Judging a piece needs eyes, and for "does it look real"
  (fractal_clouds#1) that means the owner's eyes and reference photos.
- **Renders are the artifacts.** A release is a set of images (PNG/PDF) plus
  the exact source and the exact pscat version that made them.
- **Render time is a cost to track,** not just a nice-to-have, because a
  CPU PostScript interpreter can make a piece take minutes.

## Lifecycle (agent can run it end to end)

1. **Issue first.** Each piece or library change has an issue.
   Research spikes get their own issue or a clearly labelled branch on the
   piece's issue.
2. **Branch per issue**: `<kind>/<issue#>-<slug>`, e.g. `feat/11-landscape-lib`,
   `fix/<n>-<slug>`, `spike/<n>-<slug>`, `docs/8-pscat-features`; `chore/<slug>`
   when there is no issue. A PR that builds on an unmerged one is
   **stacked**: base it on the earlier branch and say so in the description.
   After the earlier PR merges, retarget the later one to `main`. Prefer a
   plain merge over a squash for a stack, so the later branch's history
   still lines up.
3. **Plan before building.** Write the approach in the issue or PR, and get a
   second opinion (advisor, or a fresh session) before writing the bulk of it.
4. **Render-look-refine.** Commit at coherent checkpoints. Every checkpoint
   that changes a picture is rendered and looked at. Before a long render,
   check its exact settings on small crops at full detail
   (`-D "Crop=[x0 y0 x1 y1]"`), because a small whole-frame preview
   misjudges fine detail. A long render is split across cores with
   `scripts/render_bands.sh` (pscat is single-threaded; the script arrives
   with the stacked forest PR).
5. **Quality gate before the PR:**
   - `scripts/render.sh` clean (`ok`, not `lint` or `error`) for every piece
     the PR touches;
   - **determinism:** the same piece rendered twice gives the same PNG hash
     (seeded randomness only, no time or environment dependence);
     The #1 spike checked this by hand and both renderers passed. It should be
     a `render.sh` flag;
   - **no unintended change to existing pieces:** when a PR touches a shared
     library, the existing pieces render pixel-identical to `main` at a
     cheap setting (`-D ErN=256 -D ErDrops=20000 -D Res=0.5`), unless the
     change is meant to alter them. This is done by hand today; a script
     is planned;
   - timings recorded in the PR; flag any piece that got more than 2x slower;
   - pscat problems found along the way logged in `docs/pscat-issues.md`.
6. **PR** with `Closes #N`, a summary, the timings and **preview images
   attached** (committed to `gallery/previews/` or uploaded to the PR), so a
   reviewer can see what changed without rendering.
7. **Independent review** by a reviewer with no implementation context
   (`/code-review`, a fresh session, or Codex read-only:
   `codex exec -s read-only ...`) of the diff *and* the previews. It must
   come back clean. Commit the fixes as a separate commit after the
   reviewed one, so the PR shows what the review found. (Codex also
   critiques renders: `scripts/codex_critique.sh`, and
   `scripts/codex_pairwise.sh` for a blind A/B. These help, but they don't
   replace the owner's eyes.)
8. **Agent merges** once CI (when there is CI) is green and review is clean,
   unless the PR touches an owner path (below).
9. **After merge:** delete the branch, confirm the issue closed, and check
   that CI on `main` went green for the merge commit.

## Spikes

A spike answers a question that decides how something gets built (for
fractal_clouds#1: ray-march or splat?). It follows the same lifecycle,
plus:

- **Plan comment on the issue before the work** (the question, the
  approach, what will be measured), and a **results comment after it**
  linking the write-up. The issue is where the decision gets recorded.
- **Measure the cheapest deciding number first.** In #1 that was the cost of
  one noise sample, which showed whether per-pixel marching was seconds or
  hours before any renderer existed.
- **Review the measurements, not just the code.** In #1 the second-opinion
  review caught a benchmark that was 3× unfair (one renderer paid for work
  it then threw away), which turned "3× slower" into "the same speed". A
  fair comparison means the same scene, the same seed, and each side
  reasonably optimised.
- **The outcome is a recommendation**, which the owner confirms by looking
  at the images. The spike's PR merges as evidence, not as the decision.
- Pscat problems found along the way go in `docs/pscat-issues.md` with a
  minimal repro, checked against Ghostscript where possible. Claims about
  *why* pscat misbehaves are marked unconfirmed unless they are. They are
  filed upstream only when the owner asks; until then an issue in this repo
  (e.g. #8) tracks the pending filing.

## Planning and handoff

- **A roadmap epic** (fractal_clouds#36) lists the work as a checklist of
  issues, grouped by theme and noting which depend on which.
- **A handoff note** (`docs/handoff.md`, arriving with the stacked PRs) lets a new session pick up the epic:
  what's on `main`, what to read first, the order of work, and the rules that
  cost time when forgotten. Replace it at each handoff rather than
  accumulating them.
- **Subagents in worktrees** suit independent work: reviews, docs, figures,
  presets, packaging, timing, small crop experiments. Renders are heavy (one
  core per pscat, about 30 minutes for a full piece across all cores), so
  limit how many agents render at once to what the CPU allows. Changes to
  shared libraries go one at a time in the lead session.

## Two kinds of "done"

The agent can merge without the owner because merging is not the same as
the piece being finished:

- **Merged** means technically sound: renders clean, deterministic, reviewed.
  Pieces merge with `% Status: draft` in their header and stay draft until
  the owner marks them final.
- **Finished** means artistically accepted. Only the owner flips a piece to
  `% Status: final`, in a one-line PR the owner merges, or by asking the
  agent to make it. Releases only include `final` pieces.

This keeps the agent unblocked (it can iterate and merge drafts freely),
and the human judgment lands exactly where it's needed.

## Owner paths (agent opens the PR, owner merges)

These change what gets trusted, run or published, so they're listed in
`.github/CODEOWNERS` and the agent stops at "awaiting owner merge":

- `.pscat-version` and the vendored skills in `.claude/skills/` (which
  interpreter and which instructions agents run with);
- `.claude/settings.json`, `.mcp.json` (permissions, tool servers);
- `CLAUDE.md` and this SDLC file once adopted (the rules themselves);
- `.github/` (workflows, CODEOWNERS), `scripts/release*`;
- `LICENSE`;
- any `% Status: final` change.

As in pscat, GitHub can't enforce this in a one-person repo where agents
push as the owner (a required approval can't be self-given), so the agent
enforces it: a small `scripts/owner_paths_check.sh --base origin/main`
reads CODEOWNERS *as it is on main* and exits 1 if the PR touches any of
those paths.

## Branch protection on `main`

PR required, the render CI check required, no force-push, no deletion,
0 required approvals, admin bypass kept for emergencies. Up-to-date branches
not required (same reasoning as pscat: CI on every push to main is the
safety net).

## CI (once there's something to test)

- Install the pinned pscat release on Linux (the musl archive is headless and
  static), verify its checksum, run `scripts/render.sh` over every piece at
  72 dpi, and upload the renders as a workflow artifact so previews exist for
  every PR without anyone committing PNGs.
- Run the determinism check (render twice, compare hashes).
- Open question: are pscat renders bit-identical between macOS arm64 and
  Linux x86_64? If they are, CI can also check committed preview hashes.
  If not, compare only within one platform.

## Release process (rigorous, owner-gated at one point)

A release is a curated, reproducible set of finished pieces. Version it by
date, e.g. `v2026.11`, or by series.

1. **Release PR** (agent): `scripts/release.sh <version>` branches
   `release/<version>`, renders every `final` piece at print resolution
   (e.g. 300 dpi PNG plus PDF), writes `MANIFEST.json` (piece, source SHA,
   pscat version, dpi, seed, output SHA-256, render time) and a
   `CHANGELOG.md` entry, and opens the PR. It touches `scripts/release*`
   outputs, so the owner merges it. The owner looks at the final renders here.
2. **Tag** (owner): push the tag on the merge commit. Make tags immutable with a
   tag ruleset.
3. **Pipeline** (CI): from the tag, install the pinned pscat, re-render, and
   **check every output hash against `MANIFEST.json`**. A mismatch fails the
   release, because it means the render isn't reproducible. Then create a draft
   GitHub Release with the images, PDFs, manifest and `SHA256SUMS`, plus build
   provenance (`actions/attest-build-provenance`).
4. **Publish** (owner): approve the protected `release` environment, the only
   manual step. Nothing outside that environment can publish.
5. **Never overwrite.** A wrong release gets a new version and a note on the old
   one, never a replaced asset.

## Labels

`in-progress` (claimed), `in-review` (PR open), `awaiting-owner` (owner path
or final sign-off), `spike`, `upstream` (should become a PSCatLabs/pscat issue).

## Not adopted yet

Claim/heartbeat scripts for several agents working in parallel (pscat's
`work-issue`) can wait. Parallel agents have worked so far by being given
separate issues or worktrees by the lead session, with no claim protocol.
