# Workspace `node_modules` Boundary (named-volume mask + from-empty install)

> **Status:** Complete — [PATCHED] via 2607100024-workspace-node-modules-pm-cache-patch.md (2026-07-10). All objectives implemented + verified end-to-end, plus the review's blocking chown fix and the shared pm-cache/pnpm-store pivot. See patch doc for the final mechanism, deviations, and proof.
> **Prior Status:** Ready
> **Created:** 2026-07-09
> **Author:** Claude (Opus 4.8) — via plan-projex
> **Source:** 2607092240-workspace-node-modules-and-dev-server-reachability-proposal.md (Accepted) — Recommended Approach Option A
> **Related Projex:** 2607092303-dev-server-port-reachability-plan.md (sibling — other half of the same proposal, independent, no ordering dep) | 2607092254-workspace-node-modules-and-dev-server-reachability-review.md (review: recommends from-empty install over cp -a seed) | 2607060232-run-images-without-sbx-eval.md (run.ps1 mount model)
> **Worktree:** Yes
> **Reviewed:** 2026-07-10 — 2607100008-workspace-node-modules-boundary-review.md
> **Executed:** 2026-07-10 — 2607100024-workspace-node-modules-pm-cache-patch.md (full execution + chown fix + pm-cache pivot)
> **Review Outcome:** Needs Modification — refs/HOME/from-empty premise verified accurate, but a fresh named volume at `/workspace/node_modules` is `root:root` while the container runs as `agent` → from-empty install fails EACCES (blocking; fix: `sudo chown` prepend, verified). Plan is a sound base for the pm-cache pivot (orthogonal); pivot must also carry the ownership fix, relocate pnpm store (`/workspace/.pnpm-store` by default, not `$HOME`), skip inert opencode, and retire the now-stale "first run slower" / seed-revisit framing.

---

## Summary

Stop the host's Windows-built `node_modules` from shadowing into the Linux container. When (and only when) `$Workspace\node_modules` exists on the host, `run.ps1` masks `/workspace/node_modules` with a **named** per-project Docker volume and, on the volume's first (empty) start, installs deps **from empty** inside the container (`npm install` / `pnpm install` by lockfile) so native binaries are Linux-native. **Deviation from proposal:** drops the `cp -a` seed + `npm rebuild` in favor of the repo's own from-empty precedent (see Notes — the seed is not precedent-backed and adds a cross-boundary copy cost). Applies to `claude` + `codex` only; `opencode` has no Node toolchain (excluded — see Out of Scope).

**Scope:** named-volume mask + from-empty install-if-empty wrapper in `claude/run.ps1` and `codex/run.ps1`; caveat doc in `claude/README.md` + `codex/README.md`; one end-to-end verification.
**Estimated Changes:** 4 files (2 `run.ps1`, 2 `README.md`).

---

## Objective

### Problem / Gap / Need

The `/workspace` bind-mount is total: a host `node_modules/` (installed on Windows) appears verbatim in the Linux container. Vite's bundler stack ships OS/arch-specific native optional-deps (`@rollup/rollup-linux-x64-gnu` vs `-win32-x64-msvc`, esbuild/rolldown `binding-*`), so a Windows tree crashes in-container (`binding-BxaeY8HI.mjs ... command failed: vite`). The repo already solves the identical problem for its baked plugin trees (`claude/Dockerfile:150-154`, `codex/Dockerfile`) via **from-empty** `npm install --no-audit --no-fund` — this plan applies that same principle to `/workspace`.

### Success Criteria

- [x] `run.ps1` masks `/workspace/node_modules` with a named volume **only** when `$Workspace\node_modules` exists on host. [PATCHED]
- [x] Host `node_modules` absent → no mask, no from-empty install. [PATCHED] **Amended by pivot:** shared cache volumes (`pm-cache`, `pnpm-store-cache`) + the `sh -lc` wrap now apply to *every* run by design; only the *node_modules* path is unchanged when unmasked.
- [x] Volume name is a legal Docker name derived from a hash of the workspace path (`nmvol-<12-hex>`), stable per project, distinct across projects. [PATCHED] — verified `nmvol-39454ffe467b`.
- [x] On first (empty-volume) start, deps install from empty (npm/pnpm/yarn by lockfile) after an **unconditional `sudo chown`** (fresh volume is `root:root`); subsequent starts reuse the populated volume (no reinstall). [PATCHED]
- [x] `opencode/run.ps1` unchanged. [PATCHED]
- [x] README caveats document the masked-empty first run + shared cache + pnpm/yarn/monorepo/opencode limits. [PATCHED]
- [x] End-to-end: host project with Windows `node_modules` runs in-container Linux-native (esbuild `win32→linux-x64`, no crash; plain bind reproduces the crash). [PATCHED]
- [x] **[Pivot]** Shared package-manager cache: `pm-cache` (npm, both images) + `pnpm-store-cache` (pnpm store relocated via `pnpm config set store-dir`, claude); populated + reused offline across unrelated projects. [PATCHED]

### Out of Scope

- **`opencode/run.ps1`** — base is `ghcr.io/anomalyco/opencode` (Alpine, opencode binary only): "No Node in this Alpine base" (`opencode/Dockerfile`). Masking without an in-container installer would replace a contaminated `node_modules` with an *empty* one and break the app worse. Excluded; documented caveat: run Node/Vite apps in the `claude` or `codex` image. Adding Node to opencode is a Dockerfile change → out of scope per task constraint.
- **`cp -a` seed + `npm rebuild`** — dropped in favor of from-empty install (see Notes → Deviations). **[Pivot supersedes]** the shared warm `pm-cache`/`pnpm-store-cache` volumes are what make from-empty cheap by design (verified: 2nd project installs offline from cache), so the seed-as-speed-optimization question is retired, not merely deferred.
- Monorepo/nested `node_modules` globbing — single top-level mask only; caveat documented (agent reinstalls per-package as needed).
- yarn Berry/PnP — no `node_modules` to mask; documented no-op caveat.
- Dockerfile changes of any kind.

### Success dependency on `-Ports`

None. Sibling `2607092303-dev-server-port-reachability-plan.md` is independent — either can ship first.

---

## Context

### Current State

`claude/run.ps1` (lines ~94-104): `$runArgs = @('run','-it','--rm','-v',"${Workspace}:/workspace",'-w','/workspace', <+3 individual-file -v mounts>)`, then podman/tz conditionals, then `$runArgs += @($Image, 'claude', '--permission-mode', 'auto')` — a **direct CMD**.

`codex/run.ps1` (lines ~46-65): same mount head, tz conditional, then a `$bootstrap` string run via `$runArgs += @($Image, 'sh', '-lc', $bootstrap)` — already a **`sh -lc` wrapper** (codegraph install/init + `codex login` + `exec codex`).

`run.ps1` holds only `$Workspace = $PWD.Path` as a project identifier. In-container toolchain: `claude` = Node 24 + npm + pnpm (corepack) + build-essential; `codex` = nodejs (npm) + build-essential (pnpm/corepack not confirmed baked — see Constraints). Precedent (`claude/Dockerfile:150-154`) reinstalls plugin deps from empty with `npm install --no-audit --no-fund`; build-essential covers node-gyp source fallback.

### Key Files

| File | Role | Change Summary |
|------|------|----------------|
| `claude/run.ps1` | Launcher (direct CMD) | Gated named-volume mask + wrap CMD in `sh -lc` install-if-empty |
| `codex/run.ps1` | Launcher (`sh -lc` bootstrap) | Gated named-volume mask + prepend install-if-empty to bootstrap |
| `claude/README.md` | Docs | node_modules-masking caveat section |
| `codex/README.md` | Docs | Same |

### Dependencies

- **Requires:** run.ps1 no-sbx launcher (`2607060232`) — met. In-container npm (claude+codex) — met.
- **Blocks:** nothing.

### Constraints

- No Dockerfile changes → opencode (no Node) cannot be included.
- codex may lack pnpm/corepack: the install snippet tries `corepack pnpm install || pnpm install` for pnpm lockfiles but only `npm` is guaranteed in codex. pnpm projects are best run in the `claude` image; documented.
- Named volume must match `[a-zA-Z0-9][a-zA-Z0-9_.-]+` — a Windows path (`S:\...`) is illegal, so hash it.

### Assumptions

- First in-container install has network (prebuilt-binary fetch); else build-essential source-compiles (slower but works). Acknowledged in proposal as "offline-permitting".
- Emptiness check `[ -z "$(ls -A /workspace/node_modules 2>/dev/null)" ]` reliably distinguishes a fresh volume from a populated one. Verify early.
- Wrapping claude's CMD in `sh -lc "...; exec claude --permission-mode auto"` preserves interactive TTY behavior (claude on PATH). Verify.

### Impact Analysis

- **Direct:** `claude/run.ps1`, `codex/run.ps1`, 2 READMEs.
- **Adjacent:** the workspace history mount / codegraph bootstrap in codex — install prefix runs before them; ordering preserved by prepending, not reordering.
- **Downstream:** [Pivot-reframed] with the shared warm `pm-cache`/`pnpm-store-cache`, only the **very first install ever** (across all projects) pays real network cost; every later project's first install pulls tarballs from the local cache volume → fast. Host IDE keeps its own host `node_modules` (divergent by design — the mask isolates container from host).

---

## Implementation

### Overview

Shared logic (computed identically in each launcher — duplicated, matching the existing per-file tz-block convention, since the three `run.ps1` share no library):

- **Gate:** `if (Test-Path (Join-Path $Workspace 'node_modules'))` → masking active.
- **Volume name:** SHA-256 of the lowercased workspace path, first 12 hex chars → `nmvol-<hex>`.
- **Mount:** append `-v "${nmVol}:/workspace/node_modules"`.
- **Install snippet (POSIX sh, in-container):** install from empty only when the masked dir is empty.

Install snippet string (`$nmInstall`):

```sh
if [ -z "$(ls -A /workspace/node_modules 2>/dev/null)" ]; then
  echo '[run] node_modules masked + empty -> installing Linux-native deps';
  if [ -f pnpm-lock.yaml ]; then corepack pnpm install || pnpm install;
  elif [ -f yarn.lock ]; then yarn install;
  else npm install; fi;
fi
```

> **[PATCHED — two mechanism additions folded in by 2607100024 patch]**
> 1. **Blocking chown (both launchers).** A fresh named volume mounts `root:root`; the container runs as `agent`. `$nmInstall` is prefixed with `sudo chown agent:agent /workspace/node_modules;` **unconditionally, before** the empty-check (a recreated volume must be re-chowned every run). Empirically verified: without it, `npm install` → EACCES.
> 2. **Shared pm-cache pivot.** Unconditional named volumes reused by all projects/containers: `pm-cache:/home/agent/.npm` (npm cache, both images — pre-warmed + agent-owned, zero config) and, **claude only**, `pnpm-store-cache:/home/agent/.pnpm-store`. pnpm's store otherwise defaults to `/workspace/.pnpm-store` (pollutes host repo, per-project). Relocation env var `PNPM_STORE_DIR` is **NOT honored** by pnpm 11.10.0 — the working mechanism is `corepack pnpm config set store-dir /home/agent/.pnpm-store` (run every launch via `$pmSetup`), plus a chown of the fresh (root:root) store volume. claude's CMD is therefore **always** `sh -lc "$pmSetup $nmInstall exec claude --permission-mode auto"` (the pnpm relocation must apply to every run). codex gets `pm-cache` only (no pnpm baked).

### Step 1: `claude/run.ps1` — gated mask + install wrapper

**Objective:** Mask `/workspace/node_modules` with a named volume and install from empty on first run, only when host `node_modules` exists.
**Confidence:** Medium (TTY-through-`sh -lc` wrap is the one thing to verify).
**Depends on:** None

**Files:** `claude/run.ps1`

**Changes:**

1. After the history-dir block and **before** `$runArgs = @(...)`, compute the gate:

```powershell
# node_modules boundary: a host (Windows) node_modules bind-mounted into the
# Linux container carries win32-native bundler binaries (rollup/esbuild/
# rolldown) that crash here. Only when the host actually has a node_modules do
# we mask it with a per-project NAMED volume (empty on first run) and install
# Linux-native deps from empty inside the container — mirroring the plugin
# reinstall precedent in this Dockerfile. Absent -> plain bind-mount, unchanged.
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
if ($maskNodeModules) {
    $sha  = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "nmvol-$hash"
    $nmInstall = "if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then corepack pnpm install || pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi"
}
```

2. Append the mask mount inside/after the `$runArgs` assembly (after the existing `-v` mounts, before podman/tz conditionals):

```powershell
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
```

3. Replace the final command append:

```powershell
# Before:
$runArgs += @($Image, 'claude', '--permission-mode', 'auto')

# After:
if ($maskNodeModules) {
    $runArgs += @($Image, 'sh', '-lc', "$nmInstall; exec claude --permission-mode auto")
} else {
    $runArgs += @($Image, 'claude', '--permission-mode', 'auto')
}
```

**Rationale:** Named volume (keyed by path hash) persists deps across `--rm` runs and is one-time cost; from-empty install is the repo's proven mechanism. The `sh -lc` wrap only wraps when masking is active, so the unmasked path is byte-for-byte the current CMD. `exec` replaces the shell so claude keeps the TTY as PID-equivalent foreground.

**Verification:**
- Host dir with `node_modules` present → echoed run command has `-v nmvol-<hash>:/workspace/node_modules` and `sh -lc "if [ -z ...; exec claude --permission-mode auto"`.
- Host dir without `node_modules` → command identical to today (direct `claude --permission-mode auto`, no `nmvol`).
- First real run on a Windows-`node_modules` project: `[run] node_modules masked + empty` prints, install runs, claude starts interactive; second run: no install line (volume populated).

**If this fails:** Remove the three inserted blocks; `run.ps1` returns to plain bind-mount. Named volume(s) can be pruned (`docker volume rm nmvol-*`).

---

### Step 2: `codex/run.ps1` — gated mask + install prefix

**Objective:** Same mask + from-empty install, prepended to codex's existing `sh -lc` bootstrap.
**Confidence:** Medium
**Depends on:** None (independent of Step 1)

**Files:** `codex/run.ps1`

**Changes:**

1. After the tz conditional (the `$runArgs = @(...)` array literal sits *above* the tz line in codex) and before the `$bootstrap` string, add the same gate block as Step 1.1 (identical PowerShell — `$maskNodeModules`, `$nmVol`, `$nmInstall`).

2. Append the mask mount (place after the gate block, before the bootstrap):

```powershell
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
```

3. Prepend the install snippet to the bootstrap string:

```powershell
# Before:
$bootstrap = "codegraph install --yes --target=codex --location=global; " +
             "test -d .codegraph || codegraph init; " +
             "codex login --device-auth; exec codex --dangerously-bypass-approvals-and-sandbox"

# After:
$nmPrefix = if ($maskNodeModules) { "$nmInstall; " } else { "" }
$bootstrap = $nmPrefix +
             "codegraph install --yes --target=codex --location=global; " +
             "test -d .codegraph || codegraph init; " +
             "codex login --device-auth; exec codex --dangerously-bypass-approvals-and-sandbox"
```

**Rationale:** codex already runs via `sh -lc`, so masking needs no command-form change — just prepend the install and add the mount. Install runs before codegraph init (which may scan the tree), so deps exist first.

**Verification:**
- Host `node_modules` present → echoed bootstrap begins with `if [ -z ... npm install; fi; codegraph install ...` and mount present.
- Absent → bootstrap unchanged from today, no `nmvol`.
- codex pnpm caveat: on a `pnpm-lock.yaml` project without corepack/pnpm in the image, `corepack pnpm install || pnpm install` errors visibly — that's the documented "run pnpm projects in claude" caveat, not a silent failure.

**If this fails:** Remove the gate block, mount append, and `$nmPrefix`; restore the original `$bootstrap` string.

---

### Step 3: README caveats (claude + codex)

**Objective:** Explain the masked-empty first run + pnpm/yarn/monorepo/opencode limits.
**Confidence:** High
**Depends on:** Steps 1-2

**Files:** `claude/README.md`, `codex/README.md`

**Changes:** Add a section after `## Run`:

```markdown
## Workspace `node_modules` (Windows host)

If your project already has a `node_modules/` on the host (Windows), `run.ps1`
masks it with a per-project Docker volume and installs Linux-native deps inside
the container on first launch — a Windows `node_modules` carries win32 bundler
binaries (rollup/esbuild/rolldown) that crash on Linux.

- **Shared cache makes installs cheap** — deps install into a named volume
  (`nmvol-<hash>`) that persists across runs; tarballs come from the shared
  `pm-cache`/`pnpm-store-cache` volumes, so only the very first install ever
  pays network cost. `node_modules` looking empty at the very start of the
  first masked run is expected (mask, pre-install).
- **No host `node_modules`?** Nothing changes — deps install straight into the
  mount as before.
- **pnpm** — supported in this (claude) image via corepack. In codex, run
  pnpm projects in the claude image (pnpm not guaranteed baked there).
- **yarn Berry/PnP** — no `node_modules` to mask; masking is a no-op. Run
  `yarn install` inside the container yourself if `.yarn/unplugged` natives
  break.
- **Monorepos / nested `node_modules`** — only the top-level dir is masked.
  Reinstall per-package inside the container where needed.
- **opencode image** — has no Node toolchain; masking is disabled there. Run
  Node/Vite apps in the claude or codex image.
- **Host IDE** keeps its own host `node_modules` (unaffected by the container's
  volume — they diverge by design).
```

(codex README: swap "this (claude) image" phrasing for codex context, keep the "run pnpm in claude" note.)

**Rationale:** The empty-looking `node_modules` on first run is the most confusing symptom; documenting it prevents a false "install broke" read.

**Verification:** Read both READMEs — section present, caveats accurate per image.

**If this fails:** Revert README additions (docs-only).

---

### Step 4: End-to-end verification (from-empty install works on a real tree)

**Objective:** Confirm the chosen from-empty mechanism resolves the original Vite failure, and record whether a follow-up seed optimization is even warranted.
**Confidence:** High (this is a verification step, not a code change).
**Depends on:** Steps 1-3

**Files:** none (verification only).

**Procedure:**
1. Take a representative host project that has a Windows-built `node_modules` and a bundler (the proposal's `5d-advanced-wars` Vite case, or any Vite app).
2. `claude\run.ps1` (masking auto-activates since `node_modules` exists) → confirm the `[run] node_modules masked + empty` line, install completes.
3. Inside the container: `npm run dev` (or `vite --host 0.0.0.0`) → **no** `binding-*.mjs` / native-load crash; native modules resolve Linux binaries.
4. [PATCHED — decision resolved] The shared warm `pm-cache`/`pnpm-store-cache` makes from-empty cheap by design (verified: from-empty install ~1s; 2nd project installs offline from cache). The seed-optimization escape hatch is **retired**, not deferred.
5. Re-run: confirm the volume persists (no reinstall, `node_modules` populated).

**Verification:** Vite dev server starts clean in-container; second run skips install.

**If this fails:** If from-empty install itself fails (e.g. offline, no prebuilt + no build-essential path), fall back to running the app in an image with network, or document the offline limitation. This does not invalidate the mask — it's an install-environment issue.

---

## Verification Plan

### Automated Checks
- [ ] Each edited `run.ps1` parses (PowerShell AST / dot-source without exec).
- [ ] Gate off (no host `node_modules`) → echoed command identical to pre-change (no `nmvol`, no `sh -lc` wrap for claude).
- [ ] Gate on → `-v nmvol-<12hex>:/workspace/node_modules` present; volume name matches `[a-z0-9-]+`.

### Manual Verification
- [ ] Step 4 end-to-end (Vite app, Windows `node_modules`, in-container clean start).
- [ ] Volume persistence across two runs (second run: no install line).
- [ ] Two different projects → two different `nmvol-<hash>` names (no cross-project bleed).

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected Result |
|-----------|---------------|-----------------|
| Existence gate | Run with/without host `node_modules` | Mask only when present |
| Legal volume name | Inspect echoed `-v` | `nmvol-<12hex>` |
| From-empty install | First masked run | Deps install, native loads |
| Persistence | Second run | No reinstall |
| opencode untouched | Diff opencode/run.ps1 | No change |
| Caveats documented | Read READMEs | Section present ×2 |

---

## Rollback Plan

1. Remove the gate block, mask-mount append, and command/bootstrap change in `claude/run.ps1` and `codex/run.ps1`.
2. Revert the two README sections.
3. Prune stray volumes: `docker volume ls -q --filter name=nmvol- | % { docker volume rm $_ }`.

All changes are gated + additive; unmasked projects are unaffected throughout.

---

## Notes

### Deviations from proposal

- **From-empty install instead of `cp -a` seed + `npm install && npm rebuild`.** The proposal's Recommended Approach specifies seeding the volume by copying the host tree (`cp -a` from a read-only shadow bind-mount) then `install && rebuild`. Dropped, for reasons the review already flagged and this plan's research confirmed:
  1. **No precedent** — the repo's own plugin fix (`claude/Dockerfile:150-154`, `codex/Dockerfile`) does from-empty `npm install --no-audit --no-fund`, never a seed or `rebuild`.
  2. **Seed dodges nothing the named volume doesn't already** — the named volume makes install one-time; the seed only front-loads a copy.
  3. **Cost inversion + a bug class** — `cp -a` of a large `node_modules` across the Docker-Desktop-for-Windows file-sharing boundary (hundreds of thousands of tiny files) is plausibly slower than a clean install, and installing *on top of* a foreign-platform tree is exactly npm's optional-deps long-tail bug (`Cannot find module @rollup/rollup-linux-x64-gnu`) that from-empty sidesteps.
  This removes the read-only shadow bind-mount, the `cp -a` step, and `npm rebuild` entirely — simpler and precedent-backed. Step 4 records the actual install time so a seed can be revisited *only if* from-empty proves too slow on a real tree (proposal's benchmark, reframed: measure the chosen path rather than benchmark a mechanism we're not shipping).
- **opencode excluded** — no Node in its Alpine base; masking there would break apps. Proposal listed all three launchers; this plan scopes opencode out with a documented caveat rather than forcing a Dockerfile change.
- **Doc channel** — README caveats (+ the sibling plan's launch reminder), not a baked agent skill (would require a Dockerfile `COPY`; forbidden by the no-Dockerfile constraint). Proposal Open Q #4 left this open; resolved toward README.

### Risks
- codex pnpm project without corepack → visible install error (not silent). Mitigation: caveat says run pnpm in claude image.
- Named volume accumulates across many projects → `docker volume prune`/rollback command documented.
- First-run install needs network for prebuilt binaries; build-essential source-fallback (claude+codex) covers the offline compile path.

### Open Questions
- None. [PATCHED] The seed optimization is retired (shared cache supersedes it). Monorepo nested-`node_modules` globbing remains an explicit non-goal (documented caveat: reinstall per-package in-container).
