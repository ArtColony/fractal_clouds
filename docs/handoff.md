# Handoff: shepherd epic #36 to completion

These notes are for the lead session that runs the whole landscape-toolkit epic (#36) through subagents. They were written on 2026-10-23, after #35 (pixel regression and CI) landed. Replace this file when the next handoff is due.

## Starting prompt

The session that runs this handoff starts with:

> You are the lead session for epic #36 in this repo. Read `CLAUDE.md` and `docs/handoff.md`, then follow the handoff until the epic is complete.
> Three rules hold for the whole run, including after the context is summarized:
> 1. Dispatch every issue to a subagent in its own worktree, on the model the handoff names.
> 2. Review, merge and close each PR yourself; subagents never merge.
> 3. Don't ask me anything. Record your decisions as the handoff says, and contact me only once, when the epic is complete.

## The job

The lead session works through every open issue in #36. It hands each issue to a subagent and picks the model to suit the work. It then reviews the PR, merges it once CI is green, and closes the issue. **The owner doesn't want to be interrupted.** Make judgment calls yourself and write them down (see *Decisions* below). Contact the owner once, when the epic is complete.

### In scope

These are the open issues listed in #36:

| Group | Issues |
|---|---|
| Features | #13, #14, #15, #38, #39, #40 |
| Performance | #17, #18, #19, #20 |
| Aesthetics | #21, #22, #23, #24 |
| Realism | #25, #26, #27, #28, #29, #30 |
| Packaging | #31, #32, #33, #34 |

#35 is done.

### Out of scope

- #16 and #3 depend on pscat upstream, through #8. Leave them open and untouched. The owner decides when #8 gets filed.
- #2 and #4 are not part of this epic.

### The epic is complete when

1. Every in-scope issue is closed by a merged PR, or is left open with a comment explaining what blocks it. A blocker means something only the owner or upstream can resolve. Being hard to do doesn't count.
2. The write-up exists (see *Finishing* below).
3. The owner has been notified, once.

The owner closes #36 itself.

## Read first

1. `CLAUDE.md` holds the rules. It includes the merge policy: the lead merges green PRs and closes their issues without asking.
2. `docs/settings.md` lists every setting and hook. `gallery/evening_lake.ps` is the example of a piece that overrides hooks.
3. `docs/techniques.html` explains how the renderer works: the ray march, terrain, erosion, trees, clouds and haze.
4. Read the body of #36 and of each issue before you dispatch it. Issue bodies state their dependencies.

## Order and dependencies

Start with **#20 (per-stage timing)**, so that the performance work can be measured. After that, follow these dependencies:

- #13 (terrain from a map) → #39 (coastal terrain)
- #28 (water) → #38 (ocean) → #40 (coastal pieces). #40 also needs #39.
- #14 (cloud types) → #15 (thunderstorm)
- #31 (presets) should come before #32 (agent skill) and #34 (reusable libraries), so that they can describe it.
- #33 (render passes) and #23 (composition tools) are easier once the scene settings have stopped moving.

The rest can fit in between, in any order.

**Libraries are the constraint, not the issues.** Run at most one in-flight issue per shared library (`fc_terrain`, `fc_render`, `fc_landscape`, `fc_clouds`, `fc_sky`, `fc_trees`, `fc_erode`). Issues that touch different libraries, or only docs, tooling or new files, can run in parallel. Before dispatching an issue, decide which libraries it will touch and check that none of them is busy.

## Running subagents

- **One subagent per issue.** Each runs in its own git worktree (`isolation: "worktree"`) on the branch `<kind>/<issue#>-<slug>`. Its job is to implement the issue, render, look at the results, run the checks, push, and open the PR with `Closes #N`. It does not merge.
- **Models:**
  - **The strongest model the Agent tool offers** (fable at the time of writing; confirm which is strongest at the start of the run): new algorithms and decisions about how pieces look. That means #13, #14, #15, #21, #22, #25, #26, #28, #30, #38, #39 and #40.
  - **opus**: performance and tooling that needs judgment (#17, #18, #19, #23, #24, #27, #29, #33), and every PR review.
  - **sonnet**: mechanical work. That means #20, #31, #32, #34, doc updates, preset tables and wrappers.

  If a mechanical-looking issue turns out to need design work, re-dispatch it on a stronger model rather than accept a weak PR.
- **Concurrency:** the machine has 10 cores and 16 GB of memory, and pscat runs on one core. Have no more than 3 subagents rendering at a time, and tell each one to use `JOBS=3` for `regress.sh`. A 320×200 preview takes about 5 minutes on one core. A full-size piece takes about 30 minutes on all cores.
- **Brief each subagent fully.** It sees nothing of your context. Give it:
  - the issue number;
  - the files to read (`CLAUDE.md`, the issue, `docs/settings.md`, `docs/techniques.html`);
  - the libraries it may change;
  - the look policy below;
  - the "done" checklist below;
  - a request to report back the PR URL, the decisions it made, and anything it logged in `docs/pscat-issues.md`;
  - this line, word for word: "Don't merge the PR or close the issue, even though `CLAUDE.md` says to; the lead merges after review."
- **Keep your own checkout on an up-to-date `main`** (`git pull` after each merge) before dispatching, because new worktrees branch from it.
- **"Done" checklist for a subagent:**
  - the change is implemented;
  - a new setting or hook has an entry in `docs/settings.md`;
  - a changed algorithm is described in `docs/techniques.html`;
  - `scripts/check_names.sh` passes;
  - `scripts/regress.sh --ref main` is clean, or its changes are intended and explained;
  - every render has been looked at;
  - a Codex review has been run (`codex exec -s read-only -c model_reasoning_effort=high -o FILE "prompt"`), with the fixes in their own commit and listed in the PR body;
  - the PR is open and its CI is green.

## Look policy (the pixel references)

CI compares every gallery piece with `tests/regress/linux/`. For each PR:

- **A new feature is opt-in.** Its setting defaults to off, so existing pieces stay pixel-identical and the references don't change. This applies to #13, #14, #23, #28, #33, #38 and #39.
- **An issue that improves the existing look may change the pieces.** This applies to #21, #22, #24, #25, #26, #27, #29 and #30.
  - Regenerate the references with `scripts/regress.sh --docker --update`. Docker runs through OrbStack; start it with `orb start`.
  - Commit before/after images under `docs/prs/<issue>-<slug>/` and link them from the PR body. `gh` can't upload images into a PR body.
  - The reviewer judges whether the new look is better, not just different.
- **A performance issue (#17, #18, #19) must keep the pixels identical.** If exact identity is impossible, say why in the PR and keep the visible difference negligible.
- **Pieces stay `% Status: draft`.** New pieces (#15, #40) go in `gallery/` and get references. Only the owner marks a piece final.
- **Reference conflicts:** two PRs that both change the references will conflict. Merge one of them, rebase the other onto `main`, and regenerate its references. Don't hand-merge PNGs.

## Reviewing and merging (the lead)

For each PR:

1. **Have a fresh opus subagent review it.** Give it the PR number, `CLAUDE.md` and the issue, not your opinion of the PR. It should look for correctness bugs, broken settings order, reordering of the random stream, name clashes, and missing docs. For a PR that changes the look, it should also open the before/after images and judge them.
2. **Send the findings back to the implementing subagent** with SendMessage, or start a new one, to fix them in a new commit.
3. **Merge once CI is green and the review is resolved.**
   - First bring the branch up to date: `gh pr update-branch N`, or a rebase. Wait for CI to pass again. Branch protection doesn't make a PR test against the latest `main`.
   - Then merge with `gh pr merge N --merge --delete-branch`, and check that the issue closed.
   - Confirm that the CI run on `main` after the push is green before dispatching the next issue. A broken `main` spoils every branch made from it.
4. **Rebase any in-flight branch** that the merge affects.
5. **Comment on #36** with one line: what merged, and any decision worth knowing about.

## Decisions

The owner is not available. When an issue leaves a real choice open, make a sensible decision and record it in two places: the PR body, under "Decisions", and the comment on #36. Examples are a default value, a naming scheme, or which variant of an algorithm to use.

Only these actions need the owner:

- changing repo settings or branch protection;
- filing upstream issues (#8);
- marking a piece final;
- anything destructive outside a branch.

Leave those undone and list them in the final report. **Don't stop to ask about anything else.**

## Rules that cost time when forgotten

- **Settings come before the `(lib/...) run` lines,** because `fc-default` keeps a value that is already defined.
- **Keep the setup order in `fc-landscape-setup`:** noise seeds, trees seed, `srand`, erosion bake, forest bake, camera. The bakes draw from the random stream, so reordering these steps changes every picture.
- **There are no locals.** Give scratch names the library's prefix, and run `scripts/check_names.sh`.
- **Rendering:**
  - Render with `scripts/render.sh` and look at every PNG.
  - Check settings on small full-detail crops before a long render.
  - Use `scripts/render_bands.sh` for full-size renders.
- **Mac renders never match the Linux references** (`docs/pscat-issues.md` #13). Locally, use `scripts/regress.sh --ref main`; use `--docker` to check or update the stored references.
- **`renders/regress/` is per checkout.** Worktrees don't collide there, but don't run two `regress.sh` at once in the same checkout.
- **pscat problems:** log bugs and skill-doc mistakes in `docs/pscat-issues.md` with a repro. Check against `gs` first, keeping in mind that `gs` computes reals in single precision. Don't file upstream.
- **The GitHub MCP server may fail to connect.** The `gh` CLI works.

## Finishing

When every in-scope issue is resolved:

1. **Write `docs/landscape-toolkit.html`.** It documents what the epic produced:
   - the features, with settings and example renders;
   - before/after comparisons for the look changes;
   - the performance numbers from #20's profiler;
   - how to use the presets, the agent skill and the reusable libraries;
   - what is still open and why.

   Follow the style of `docs/techniques.html`. Merge it by PR, and also publish it as an Artifact so the owner gets a link.
2. **Make a demo piece** in `gallery/` that shows the new features together, such as a coastal scene with layered clouds and golden-hour light. It stays `% Status: draft`.
   - Render it full size with `render_bands.sh`.
   - Commit the chosen render to `gallery/previews/`.
   - Feature it in the write-up.
3. **Notify the owner once.** Load PushNotification with ToolSearch if it exists, send the demo render with SendUserFile, and also send a final message. Include:
   - the Artifact link and the demo render;
   - the list of merged PRs;
   - the issues left open, with their blockers;
   - the decisions the owner may want to revisit;
   - the actions that need the owner.
4. **Replace this file** with a handoff for whatever comes next.
