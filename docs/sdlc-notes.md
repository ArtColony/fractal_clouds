# SDLC notes for ArtColony projects

A proposal, not yet in force. The goal: agents can work issue to merged PR
without waiting on the owner, while anything that changes what the repo
trusts, or what it publishes, still needs the owner. It's adapted from
pscat's `SDLC.md` (its "agent-full" merge policy, CODEOWNERS exceptions and
release lifecycle) for a repo whose product is images, not a binary.

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
2. **Branch per issue**: `feat/<n>-<slug>`, `fix/<n>-<slug>`,
   `spike/<n>-<slug>`, `chore/<slug>`, `docs/<slug>`.
3. **Plan before building.** Write the approach in the issue or PR, and get a
   second opinion (advisor, or a fresh session) before writing the bulk of it.
4. **Render-look-refine.** Commit at coherent checkpoints. Every checkpoint
   that changes a picture is rendered and looked at.
5. **Quality gate before the PR:**
   - `scripts/render.sh` clean (`ok`, not `lint` or `error`) for every piece
     the PR touches;
   - **determinism:** the same piece rendered twice gives the same PNG hash
     (seeded randomness only, no time or environment dependence);
   - timings recorded in the PR; flag any piece that got more than 2x slower;
   - pscat problems found along the way logged in `docs/pscat-issues.md`.
6. **PR** with `Closes #N`, a summary, the timings and **preview images
   attached** (committed to `gallery/previews/` or uploaded to the PR), so a
   reviewer can see what changed without rendering.
7. **Independent review** by a reviewer with no implementation context
   (`/code-review`, or a fresh session) of the diff *and* the previews. It must
   come back clean.
8. **Agent merges** once CI (when there is CI) is green and review is clean,
   unless the PR touches an owner path (below).
9. **After merge:** delete the branch, confirm the issue closed, and check
   that CI on `main` went green for the merge commit.

## Two kinds of "done"

The agent can merge without the owner because merging is not the same as
the piece being finished:

- **Merged** means technically sound: renders clean, deterministic, reviewed.
  Pieces merge with `% Status: draft` in their header.
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
`work-issue`) can wait until more than one agent works a repo at a time.
