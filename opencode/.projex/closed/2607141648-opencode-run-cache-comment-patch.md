# Patch: run.ps1 `.cache` comment — correct for D1 build-time bake

> **Date:** 2026-07-14
> **Author:** projex orchestration subagent (opus)
> **Directive:** Reword the `/home/agent/.cache` chown comment in `opencode/run.ps1` (~ln 99-108) — it claimed "nothing creates that directory at build time," which D1's Dockerfile rewrite made false (playwright now bakes+chowns `.cache`/`.cache/ms-playwright` at build time). Comment-only fix, no behavior change.
> **Source Plan:** `2607140130-opencode-glibc-base-swap-plan.md` — minor post-audit accuracy follow-up, NOT an unfinished plan objective (plan already `Complete`).
> **Result:** Success

---

## Summary

Post-audit doc-accuracy fix. Deviation D1 during execution changed the Dockerfile so `playwright install --with-deps chromium` bakes `/home/agent/.cache` (incl. `.cache/ms-playwright`) into the image at build time as root, then chowns it back to agent. This falsified the run.ps1 comment premise that "nothing creates that directory at build time." Reworded the comment to reflect the baked-in reality; the operative `$pmSetup` chown logic is unchanged.

---

## Changes

### opencode/run.ps1 — cache-chown explanatory comment

**File:** `opencode/run.ps1`
**Change Type:** Modified (comment-only)
**What Changed:**
- Reworded the comment block above `$pmSetup` (was ln 99-108) that explains why `/home/agent/.cache` is chowned.
- Removed the stale premise "nothing creates that directory at build time" and the "Docker auto-create the missing parent as root:root" mechanism that depended on it.
- New text states: the image bakes `.cache` at build via `playwright install --with-deps chromium` (root, HOME=/home/agent), creating `.cache/ms-playwright` + the `.cache` parent root:root, and the Dockerfile chowns it back to agent (D1). The runtime chown here fixes ownership on top of that baked-in state rather than a directory the image never touched.
- Preserved the still-accurate details: the `opencode-cache` named volume mounts onto the nested `.cache/opencode` leaf (fresh volume = root:root); only suite mounting under `.cache/`; corepack's sibling `~/.cache/node/corepack` needs the parent agent-owned. Noted that with D1's bake the parent chown is now a defensive no-op while the leaf chown stays load-bearing.

**Why:**
Comment described a mechanism (missing build-time dir → Docker-created root:root parent) that D1 eliminated. A future reader diagnosing cache permissions would be misled. The `$pmSetup` line (`sudo chown agent:agent /home/agent/.cache ... /home/agent/.cache/opencode`) is untouched — the parent chown is a harmless no-op post-D1 and the leaf chown remains necessary, so no behavior change is warranted.

**Before (ln 99-108):**
```
# `/home/agent/.cache` itself is also chowned: nothing creates that directory at
# build time, so mounting a volume onto the nested `.cache/opencode` path makes
# Docker auto-create the missing parent as root:root before the container starts
# (a Docker mount-point quirk, independent of the image's own user setup — this
# is the only one of the three suites that mounts anything under `.cache/`, so
# it's the only one exposed to it). F5's chown covered the volume leaf but not
# this parent, so corepack (which caches to the sibling `~/.cache/node/corepack`
# on first pnpm-version fetch) hit EACCES trying to `mkdir` under the root-owned
# parent. Chowning the parent (non-recursive — the leaf keeps its own chown) is
# enough: agent can then create any sibling under `.cache` itself.
```

**After:**
```
# `/home/agent/.cache` itself is also chowned. The image bakes this directory at
# build time: `playwright install --with-deps chromium` runs as root with
# HOME=/home/agent, creating `.cache/ms-playwright` (and the `.cache` parent)
# root:root, and the Dockerfile chowns it back to agent right after (D1). So the
# parent already exists agent-owned in the image before the container starts. The
# runtime chown here fixes ownership on top of that baked-in state rather than a
# directory the image never touched: run.ps1 mounts the `opencode-cache` named
# volume onto the nested `.cache/opencode` leaf, and a fresh volume mounts
# root:root — this is the only one of the three suites that mounts anything under
# `.cache/`, so it's the only one exposed to it. F5's chown covered the volume
# leaf but not the parent; corepack (which caches to the sibling
# `~/.cache/node/corepack` on first pnpm-version fetch) needs the parent
# agent-owned to `mkdir` its sibling. With D1's build-time bake the parent is
# already agent-owned, so chowning it here is a defensive no-op; the leaf chown
# stays load-bearing for the fresh volume.
```

---

## Verification

**Method:** Static review — comment-only change with no runtime surface. Confirmed against source-of-truth artifacts:
- `opencode/Dockerfile:85-93` — `RUN HOME=/home/agent playwright install --with-deps chromium && chown -R agent:agent /home/agent/.cache` (D1 bake+chown at build).
- `opencode/run.ps1:135` — `-v opencode-cache:/home/agent/.cache/opencode` (nested leaf mount).
- `opencode/run.ps1:109` — `$pmSetup` chown line unchanged (parent + leaf both chowned).

**Result:**
```
Committed: projex(patch): correct run.ps1 .cache comment for D1 build-time bake (34fdab6)
```

**Status:** PASS

---

## Impact on Related Projex

| Document | Relationship | Update Made |
|----------|-------------|-------------|
| `2607140130-opencode-glibc-base-swap-plan.md` | Source plan (already `Complete`) | None — status untouched; this is a post-audit accuracy follow-up, not a plan objective. Left for `/close-projex`. |
| `2607140130-opencode-glibc-base-swap-log.md` | Execution log (self-flagged the stale comment) | None — resolution recorded here in the patch doc. |
| `2607142230-opencode-glibc-base-swap-audit.md` | Audit (flagged this as Minor #1 / optional patch) | None — this patch discharges that recommendation. |

---

## Notes

- Comment-only fix; zero behavior change. The `$pmSetup` chown remains correct: parent-`.cache` chown is now a defensive no-op (image bakes it agent-owned via D1), leaf-`.cache/opencode` chown stays necessary (fresh named volume mounts root:root).
- Committed directly to the ephemeral branch `projex/2607140130-opencode-glibc-base-swap` per patch convention (no separate branch).
- Plan status transition and branch finalization are deferred to `/close-projex`.
