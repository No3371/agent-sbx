# Patch: Workspace `node_modules` mask + shared package-manager cache volumes

> **Date:** 2026-07-10
> **Author:** Claude (Opus 4.8) — via patch-projex
> **Directive:** Execute the fully-designed mask+from-empty-install plan (2607092303-workspace-node-modules-boundary-plan.md), fold in the review's blocking chown fix, and pivot to a shared package-manager cache volume for all containers of this suite.
> **Source Plan:** 2607092303-workspace-node-modules-boundary-plan.md (Ready → Complete via this patch)
> **Review:** 2607100008-workspace-node-modules-boundary-review.md (blocking chown defect + pm-cache pivot guidance)
> **Result:** Success

---

## Summary

Host (Windows) `node_modules` bind-mounted into the Linux container carries win32 bundler natives (rollup/esbuild/rolldown) → crash. `claude/run.ps1` + `codex/run.ps1` now mask `/workspace/node_modules` with a per-project named volume (`nmvol-<12hex>`) and install Linux-native deps from empty inside the container — **only** when host `node_modules` exists. Adds the review's blocking `sudo chown` (fresh named volume mounts `root:root`; container runs as `agent`) and a shared, cross-project package-manager cache: `pm-cache` (npm `~/.npm`, both images) + `pnpm-store-cache` (pnpm store, claude only). `opencode` untouched (no Node).

---

## Changes

### `claude/run.ps1` — Modified

**What Changed:**
- Added `$pmSetup` (unconditional): `sudo chown agent:agent /home/agent/.pnpm-store 2>/dev/null; corepack pnpm config set store-dir /home/agent/.pnpm-store 2>/dev/null || true;` — relocates pnpm's store off the workspace onto a shared volume.
- Added `$maskNodeModules` gate = `Test-Path (Join-Path $Workspace 'node_modules')`; when set, computes `nmVol = nmvol-<first-12-hex of SHA-256(lowercased $Workspace)>` and `$nmInstall`.
- `$nmInstall` prepends **unconditional** `sudo chown agent:agent /workspace/node_modules;` (before the empty-check), then the from-empty install (`pnpm`/`yarn`/`npm` by lockfile) inside `if [ -z "$(ls -A /workspace/node_modules ...)" ]`.
- Mounts: unconditional `-v pm-cache:/home/agent/.npm` + `-v pnpm-store-cache:/home/agent/.pnpm-store`; `-v ${nmVol}:/workspace/node_modules` only when masking.
- Final CMD is now **always** `sh -lc "$pmSetup $nmInstall exec claude --permission-mode auto"` (was a direct `claude` CMD). `exec` keeps the interactive TTY (proven pattern, already used by codex).

**Why:** Named per-project volume persists Linux-native deps across `--rm`; from-empty is the repo's own precedent (`Dockerfile:150-154`). Always-wrapping is required so the pnpm store relocation + shared caches apply to every run, not just masked ones (fixes the `/workspace/.pnpm-store` host-pollution universally).

### `codex/run.ps1` — Modified

**What Changed:**
- Same `$maskNodeModules` gate + `$nmVol` + `$nmInstall` (with unconditional chown) as claude. No pnpm store handling (pnpm not baked in codex).
- Mounts: unconditional `-v pm-cache:/home/agent/.npm`; `-v ${nmVol}:/workspace/node_modules` when masking.
- `$nmInstall` prepended to the existing `$bootstrap` string (codex already runs via `sh -lc`), before the codegraph steps.

**Why:** codex already `sh -lc`-wraps, so masking needs no command-form change — prepend install + add mounts. Shares the same `pm-cache` volume as claude.

### `claude/README.md` / `codex/README.md` — Modified

**What Changed:** Added `## Workspace node_modules (Windows host)` sections documenting: shared `pm-cache`/`pnpm-store-cache` volumes, per-project `nmvol-<hash>` persistence, pnpm store relocation (claude) / "run pnpm in claude" (codex), yarn/monorepo/opencode caveats, volume-prune commands. **Reframed** the plan's stale "first masked run is slower" → "only the very first install ever pays network cost; later projects' first installs are fast from the local cache volume."

---

## Verification

**Method:** Empirical, against the real `cc-custom:v1` image; PowerShell AST parse + arg-generation simulation for both launchers.

**Results:**

- **Parse + arg-gen:** both `run.ps1` parse OK. Masked claude args: `... -v pm-cache:/home/agent/.npm -v pnpm-store-cache:/home/agent/.pnpm-store -v nmvol-39454ffe467b:/workspace/node_modules cc-custom:v1 sh -lc "<pmSetup> <chown+install> exec claude --permission-mode auto"`. Plain claude: cache volumes only, no nmvol, no install — node_modules behavior unchanged. codex parallel. `nmvol-<12hex>` matches `[a-z0-9-]+`.
- **Blocking chown fix (PROVEN):** fresh named volume at `/workspace/node_modules` → `root:root`, agent `touch` → `Permission denied`; after `sudo -n chown agent:agent` → `agent:agent`, write OK. Passwordless sudo confirmed (agent in `sudo` group).
- **pnpm mechanism (CORRECTED):** `PNPM_STORE_DIR` and `npm_config_store_dir` env vars are **NOT** honored by pnpm 11.10.0 (store still resolves `/workspace/.pnpm-store/v11`). The working mechanism is **`pnpm config set store-dir /home/agent/.pnpm-store`** → resolves `/home/agent/.pnpm-store/v11`. The fresh `pnpm-store-cache` volume is also `root:root` (not pre-baked) → needs chown too. Real cross-volume `pnpm install` succeeds; store volume populates (`v11/`).
- **npm cache:** `~/.npm` is pre-warmed + `agent:agent` in the image; fresh mount copy-ups clean, zero config.
- **End-to-end (synthetic Vite/esbuild, host-installed win32 binary):**
  - Plain bind-mount → `Error: You installed esbuild for another platform` (bug reproduced).
  - Masked run #1 → `[run] node_modules masked + empty -> installing`, installs `@esbuild/linux-x64`, `require("esbuild").transformSync` → `ESBUILD_OK linux-native`.
  - Masked run #2 (same nmvol) → `SKIP_INSTALL (volume already populated)`, `ESBUILD_OK on reuse`.
  - Shared cache: second unrelated project installs esbuild@0.21.5 `--offline` (exit 0) purely from `pm-cache`, loads Linux-native.

**Status:** PASS

---

## Impact on Related Projex

| Document | Relationship | Update Made |
|----------|-------------|-------------|
| 2607092303-workspace-node-modules-boundary-plan.md | Source plan | Objectives marked `[PATCHED]`; chown + pm-cache/pnpm-store folded into Implementation; stale "first run slower" + seed-revisit framing retired; Status → Complete; moved to `.projex/closed/` |
| 2607100008-workspace-node-modules-boundary-review.md | Pre-patch review | Cross-referenced; its blocking chown fix + pnpm-store relocation implemented (pnpm mechanism corrected: `config set store-dir`, not `PNPM_STORE_DIR`) |
| 2607092303-dev-server-port-reachability-plan.md | Sibling (other half of proposal) | None — independent |

---

## Notes

- **Deviation from review guidance:** the review suggested `-e PNPM_STORE_DIR=...`; verified NOT honored by pnpm 11.10.0. Used `pnpm config set store-dir` (run every launch via `$pmSetup`) + a chown of the fresh store volume instead.
- **Scope-guard escalation of the plan's "byte-for-byte unchanged when unmasked" criterion:** the pm-cache pivot intentionally adds shared cache volumes + pnpm-store relocation to *every* run (masked or not) — so unmasked runs now carry cache mounts and always go through `sh -lc`. The *node_modules* behavior when unmasked is still unchanged (no nmvol, no install). This is by design (the human's pivot), not a regression.
- **Monorepo caveat holds:** only top-level `node_modules` is masked. The original `5d-advanced-wars` repo is an npm-workspaces monorepo with nested non-hoisted `node_modules` (`apps/web`, `packages/core`) — the documented "reinstall per-package" caveat — so a synthetic single-package Vite project was used for the decisive clean mechanism proof (reproduces the identical win32-binding crash class).
- Shared volumes to prune if they grow: `nmvol-*` (per-project), `pm-cache`, `pnpm-store-cache`.
