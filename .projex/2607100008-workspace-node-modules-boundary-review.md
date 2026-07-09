# Review: Workspace `node_modules` Boundary (named-volume mask + from-empty install)

> **Review Date:** 2026-07-10
> **Reviewer:** Claude (Opus 4.8) — via review-projex
> **Reviewed Projex:** 2607092303-workspace-node-modules-boundary-plan.md (Status: Ready)
> **Original Date:** 2026-07-09
> **Time Since Creation:** ~1 day
> **Trigger:** Pre-patch review — human wants to pivot the plan to add a shared package-manager cache volume; verify plan still valid/accurate before it receives that addition.

---

## Review Summary

**Verdict:** Needs Modification — one **blocking** accuracy defect, empirically confirmed.

Plan's structure, gate logic, file/line refs, and "from-empty" premise all verified **accurate**. HOME=`/home/agent` confirmed for claude+codex. BUT: a fresh named volume mounted at `/workspace/node_modules` comes up **`root:root`**-owned while the container runs as **`agent` (uid 1000)** — so the plan's core mechanism (from-empty `npm install` into that volume) **fails with EACCES on the very first masked run**. The plan never addresses volume ownership. This is independent of the pm-cache pivot and must be fixed regardless. The plan IS ready to receive the pm-cache addition (orthogonal, no conflict) — but the patch dispatch must also carry the ownership fix or nothing installs.

---

## Timeline Analysis

### When Authored
- Created 2026-07-09 (yesterday), Status: Ready, not yet executed.
- Source: 2607092240-...-proposal.md (Accepted, Option A). Deviated from proposal by dropping `cp -a` seed → from-empty install.

### What Changed Since
| Area | Then | Now | Impact |
|------|------|-----|--------|
| `claude/run.ps1` / `codex/run.ps1` | direct CMD / `sh -lc` bootstrap | **unchanged** (not in git-modified set) | No launcher drift; plan's line refs still land |
| `claude/Dockerfile` `codex/Dockerfile` | — | show `M` in git status (agent-browser/skills work) | Cited precedent lines still match current tree (see Accuracy) |
| `.gitignore` `.projex` entry | ignored (per prior chain) | **un-ignored** (verified: no `projex` line in `.gitignore`) | Review doc committable if requested; does not change present-only policy |

### Related Events
- pm-cache pivot (conversation, not yet in any doc): human wants one shared, cross-image named volume at the package-manager cache dir so from-empty installs are cheap without a bulk copy. This review verifies the plan is a sound base for that.

---

## Status Quo Assessment — Empirical Verification

Ran the plan's exact mount model against the real images (`cc-custom:v1`, `codex-custom:v1`): bind host workspace (with a `node_modules`) → `/workspace`, fresh named volume → `/workspace/node_modules`, image-default user.

### Confirmed ACCURATE in plan
| Plan claim | Verified |
|------------|----------|
| `claude/run.ps1` ~94-104: direct CMD `claude --permission-mode auto` | ✓ line 104; `$runArgs` at 94, `-it` + 3 file mounts at 95-100 |
| `codex/run.ps1` ~46-65: `sh -lc` bootstrap, array literal above tz line | ✓ `$runArgs` 46-50, tz 51-52, `$bootstrap` 62-64, `sh -lc` append 65 |
| from-empty plugin reinstall precedent `claude/Dockerfile:150-154` | ✓ `RUN ... for d in $(find ... package.json) ... npm install --no-audit --no-fund` at 150-154 |
| codex equivalent `codex/Dockerfile` | ✓ same loop at 85-89 |
| claude toolchain: Node 24 + npm + pnpm(corepack) + build-essential | ✓ Dockerfile 55-58 |
| codex toolchain: nodejs(npm) + build-essential, pnpm **not** baked | ✓ Dockerfile 37-38; `pnpm` absent at runtime (`NO_PNPM`). Corepack *is* present (`/usr/local/bin/corepack`) but pnpm not activated |
| **HOME = `/home/agent`** (both images) | ✓ `WORKDIR /home/agent`, `USER agent`, runtime `uid=1000(agent)` |
| Emptiness check `ls -A /workspace/node_modules` distinguishes fresh vs populated (plan Assumption L84) | ✓ fresh volume returns **empty** — no accidental copy-up from the host bind; "from-empty" premise is **sound** |
| npm default cache dir | ✓ `/home/agent/.npm` (both images) |

### Drift from Projex Assumptions
| Assumption | Original | Current Reality | Drift |
|------------|----------|-----------------|-------|
| Fresh masked volume is writable by the install | implied (never stated) | **`root:root 755`; agent-user write → `Permission denied`** | **MAJOR (blocking)** |
| Emptiness check reliable | "Verify early" (L84) | reliably empty on fresh volume | None — confirmed true |
| TTY through `sh -lc` wrap | flagged Medium risk (L120) | codex already ships identical `sh -lc "...; exec <agent>"` + `-it`; `exec` keeps TTY | Overstated — low risk, proven pattern |

---

## Accuracy Assessment

### Blocking defect — volume ownership (not in plan)
`docker run ... -v nmvol:/workspace/node_modules cc-custom:v1` (and `codex-custom:v1`), image-default user:
```
uid=1000(agent) ...
stat /workspace/node_modules -> root:root 755
touch /workspace/node_modules/.probe -> Permission denied  (WRITE_FAIL)
```
The plan's `$nmInstall` runs `npm install` (cwd `/workspace`, target `/workspace/node_modules`) as `agent`. Root-owned mountpoint → **EACCES**, install fails, node_modules stays empty, next run retries and fails again. Step 1/2's entire mechanism is non-functional as written.

**Fix (verified feasible):** passwordless `sudo` works in both images (`sudo -n chown agent:agent /workspace/node_modules` → `SUDO_CHOWN_OK`, then `touch` → `WRITE_OK`). Patch must prepend a chown to `$nmInstall` (inside the emptiness branch, before install). Small; rides in the same snippet the pivot edits.

### Line refs / technical content — otherwise accurate
No broken refs. Plan variously cites `145-154` and `150-154` for the claude precedent; the `RUN` block is 150-154, comment 144-149 — close enough, not misleading.

---

## Challenge Questions

### Challenge 1: Does the shared pm-cache pivot conflict with anything the plan assumes?
**No conflict.** pm-cache (content-addressed tarball cache) is orthogonal to the per-project `nmvol` (extracted `node_modules`). Verified: a fresh volume at `/home/agent/.npm` mounts **`agent:agent`, writable, no chown needed** — the image pre-bakes `~/.npm` (from the Dockerfile plugin installs), so Docker copy-up seeds ownership *and* pre-warms the cache. Clean npm mount in both images.
**But two things the pivot must handle (heads-up for patch subagent):**
1. **pnpm store is NOT under `$HOME`.** `pnpm store path` → `/workspace/.pnpm-store/v11` (on the bind-mounted Windows fs, per-project, cross-boundary). A `/home/agent/.npm` volume does **nothing** for pnpm. To share pnpm's store the patch must relocate it (`PNPM_STORE_DIR=/home/agent/.pnpm-store` or `pnpm config set store-dir`) **and** mount a volume there. Claude-only (codex has no pnpm).
2. **opencode is inert for the cache.** Runs as agent, HOME=`/home/agent`, but **no Node/npm** → a cross-image pm-cache mount there is harmless but useless. The pivot's "all three images alike" framing overstates; effectively **claude+codex only**.

### Challenge 2: Is "first masked run is slower" still the right framing once a shared warm cache exists?
**No — pivot makes it stale.** Appears in Impact Analysis (L91), Step 3 README caveat ("First masked run is slower", L240), and success framing. With a shared warm pm-cache, only the **first-ever** install across all projects pays network cost; every later project's first install pulls tarballs from the local cache volume → fast. Reframe: "first-ever run populates the shared cache; subsequent projects' first installs are fast."

### Challenge 3: Does the pivot kill the plan's seed-revisit escape hatch?
**Largely, yes.** Step 4's decision rule (L280), the Out-of-Scope seed note (L40), and Open Questions (L341) all hinge on "measure from-empty install time; revisit `cp -a` seed only if too slow." A warm shared cache makes from-empty cheap **by design** — which is the whole point of the pivot. The seed-optimization escape hatch becomes effectively dead. Patch should note the pivot supersedes the seed-revisit question rather than leaving it dangling.

### Challenge 4: Was the plan's own flagged risk (TTY-through-`sh -lc`) the right one?
**No.** codex already runs `sh -lc "...; exec codex ..."` with `-it` in production — `exec` replaces the shell so the agent inherits the TTY as foreground. Low risk, proven. The risk the plan **should** have flagged is the **volume ownership** defect above. Recommend the patch demote the TTY note and elevate ownership to the Medium/High risk.

---

## Value Assessment

| Aspect | Original | Current | Change |
|--------|----------|---------|--------|
| Problem (Windows `node_modules` shadows Linux container, Vite native-binary crash) | real | still real | unchanged — worth doing |
| Solution benefit (mask + from-empty) | high | high **once ownership fixed** | unchanged intent |
| Impl cost | 4 files | +1 chown line, +pnpm store handling (pivot) | small |

**Value Verdict:** Still valuable. Mechanism sound; needs the ownership fix to actually run.

---

## Recommendations

### Required (blocking — patch must include, independent of pivot)
1. Prepend `sudo chown agent:agent /workspace/node_modules` inside the emptiness branch of `$nmInstall`, before the install, in **both** launchers. Passwordless sudo verified in both images.

### For the pm-cache pivot (patch subagent)
2. npm cache: mount one shared named volume at `/home/agent/.npm` — no chown needed (already agent-owned, pre-warmed). Applies to claude+codex.
3. pnpm cache: relocate store to a `$HOME`-based path (`PNPM_STORE_DIR=/home/agent/.pnpm-store`) and mount a volume there, else pnpm gets no benefit (store defaults to `/workspace/.pnpm-store`). Claude-only.
4. Skip pm-cache wiring in `opencode/run.ps1` — no Node, inert.
5. Reframe stale plan text: "first masked run is slower" (L91, L240) → "first-ever populates shared cache; later projects fast"; retire the seed-revisit escape hatch (L40, L280, L341) as superseded by the cache.
6. Demote the TTY-wrap risk; elevate volume-ownership to the plan's headline risk.

### Next Review
- After patch lands: audit the edited `$nmInstall` (chown + pnpm store) end-to-end on a real Vite tree.

---

## Appendix — Independent Observations (pre-plan-read)

Empirical test matrix (both images, image-default user, fresh volumes):
- `/workspace/node_modules` fresh vol → `root:root`, empty, agent write **fails**.
- `/home/agent/.npm` fresh vol → `agent:agent`, **pre-warmed** (`_cacache _logs _prebuilds`), agent write ok.
- npm cache = `/home/agent/.npm`; pnpm store = `/workspace/.pnpm-store/v11` (claude); pnpm absent in codex; corepack present in both.
- `sudo -n` chown works in both.

### Ready-to-patch verdict
**Yes** — the plan is a sound base and the pm-cache pivot is orthogonal (no conflict). **Caveat:** the patch dispatch must additionally carry the blocking `sudo chown` ownership fix, or the from-empty install cannot run at all.
