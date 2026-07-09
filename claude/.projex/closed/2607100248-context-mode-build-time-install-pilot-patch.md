# Patch: context-mode Build-Time Install Pilot

> **Date:** 2026-07-10
> **Author:** agent (opus)
> **Directive:** Execute the 3 steps of 2607100235-context-mode-build-time-install-pilot-plan.md — prepare.ps1 exclusion list + both Dockerfiles' build-time install RUN.
> **Source Plan:** 2607100235-context-mode-build-time-install-pilot-plan.md
> **Result:** Partial Success — code complete + Step 1 verified; Step 2/3 auth gate (docker build) deferred to human (see Notes).

---

## Summary

Stop vendoring context-mode's host-built payload into the sbx images; install it fresh during `docker build` via the claude CLI so its paths/caches/hooks are Linux-native. `prepare.ps1` now strips context-mode's payload dirs + registry entries (identity in `settings.json` preserved); both Dockerfiles install it in-container before the native-module npm loop. All other plugins keep the copy-and-patch path unchanged.

Step 1 (prepare.ps1) verified end-to-end by running the script. Step 2/3 runtime validity hinges on the plan's designated first-build "auth gate" unknown — deferred, not forced (rationale below).

---

## Changes

### prepare.ps1 — exclude context-mode from vendored payload

**File:** `claude/prepare.ps1`
**Change Type:** Modified
**What Changed:**
- Added `$buildTimeInstallMarketplaces = @('claude-context-mode')` exclusion list. **Placement deviation from plan:** plan Step 1a said "after line 156"; placed instead immediately *before* the `installed_plugins.json` block (its first consumer). PowerShell executes top-to-bottom — defining it after that block would leave it `$null` at use and silently no-op the removal. Comment in-code notes why.
- `installed_plugins.json` block: after `ConvertFrom-Json`, drop any plugin whose marketplace suffix (after `@`) is in the list.
- After the `$pluginCachesToDrop` loop: drop `plugins/cache/$mp` + `plugins/marketplaces/$mp` for each excluded marketplace.
- `known_marketplaces.json` block: after `ConvertFrom-Json`, remove excluded marketplace keys before the rewrite loop.

**Why:** One list drives all three exclusions (matches existing `$pluginCachesToDrop` pattern, trivially extensible for Option A cutover). Removing registry entries (not just dirs) means build-time `marketplace add` starts clean with no stale `installLocation` pointing at an uncopied dir. `enabledPlugins` untouched → identity survives.

---

### Dockerfile / Dockerfile.slim — build-time install RUN

**File:** `claude/Dockerfile`, `claude/Dockerfile.slim`
**Change Type:** Modified (identical RUN in each)
**What Changed:**
- Inserted `RUN set -eux; claude plugin marketplace add mksglu/claude-context-mode; claude plugin install context-mode@claude-context-mode --scope user` immediately after the plugins `COPY`, before the native-module npm loop. Runs as `USER agent` (already in effect). In `Dockerfile.slim`, `claude` resolves via the `/home/agent/.local/bin/claude` symlink already on PATH.

**Why:** `--scope user` writes into the container's own `~/.claude` (avoids leaking install state onto a host bind-mount). Placing it before the npm loop reuses the existing native-rebuild machinery so context-mode's `better-sqlite3` gets a Linux rebuild — no second loop. Copy path for other plugins is untouched.

---

## Verification

**Method:** PowerShell syntax parse; live `pwsh prepare.ps1` run with staged-output inspection. Docker build deferred (see Notes).

**Result:**
```
PARSE-OK  (prepare.ps1)

[prepare] run:
  installed_plugins.json: removed context-mode@claude-context-mode (build-time install)
  dropped build-time-install payload: plugins/cache/claude-context-mode
  dropped build-time-install payload: plugins/marketplaces/claude-context-mode
  known_marketplaces.json: removed claude-context-mode (build-time install)

staged context/.claude checks:
  enabledPlugins["context-mode@claude-context-mode"]: true        PRESENT (identity kept)
  hooks/context-mode-cache-heal.mjs                                PRESENT (standalone hook survives)
  installed_plugins.json  context-mode@claude-context-mode key     ABSENT
  known_marketplaces.json "claude-context-mode" key                ABSENT
  plugins/cache|marketplaces/claude-context-mode dirs              ABSENT
```

**Status:** Step 1 PASS. Step 2/3 code correct by inspection vs plan diffs; runtime auth gate DEFERRED.

**Side effect (expected/desirable):** Two SessionStart hook entries in host `settings.json` pointing at `plugins/cache/claude-context-mode/context-mode/1.0.75/hooks/heal.mjs` were dropped by prepare's existing dangling-hook validation once the payload was removed. These are context-mode's *self-healed host-absolute* plugin hook entries — exactly the shape the pilot exists to eliminate. The standalone `hooks/context-mode-cache-heal.mjs` (out-of-scope, must survive) is unaffected and still staged.

---

## Impact on Related Projex

| Document | Relationship | Update Made |
|----------|-------------|-------------|
| 2607100235-context-mode-build-time-install-pilot-plan.md | Source plan | Objectives marked `[PATCHED]`; Step 1 verified, Step 2/3 code applied w/ auth gate open; kept Active (not closed) pending first-build auth verification |
| 2607100201-build-time-plugin-install-for-sandbox-images-proposal.md | Originating proposal (Option C) | No edit (pilot in progress; not concluded) |
| 2607091752-context-mode-plugin-path-mapping-memo.md | Originating memo | No edit |

---

## Notes

### Auth gate — deferred, not resolved (the plan's decisive unknown)
Plan Step 2/3 confidence is Medium, gated on: *do `claude plugin marketplace add` / `install` run non-interactively in a credential-free build container (no baked OAuth)?* This is only answerable by a real `docker build`.

**Why deferred rather than run here:**
- Base image `docker/sandbox-templates:claude-code` is **not cached locally** — verifying requires pulling it (unknown large size) or a full multi-minute build (Chrome download + npm-global installs).
- A local probe on the Windows host is invalid: the dev host claude *is* authenticated, so it cannot reproduce the credential-free build container.
- The plan's own failure path for this gate is "stop and report → fall back to proposal **Option B**" — an architectural fallback that is a human/orchestrator decision, outside patch scope. Forcing it would violate the patch scope guard.

**Recommended next action (human):** run `claude/build.ps1` (or `docker build -f claude/Dockerfile`). Watch the new RUN layer:
- Exits 0, no interactive login prompt → pilot mechanism proven; proceed to runtime checks (ctx_* tools callable, heal hook OK) and consider Option A cutover.
- Refuses unauthenticated → hard blocker; per plan, drop `'claude-context-mode'` from `$buildTimeInstallMarketplaces` (restores copy path) and escalate to Option B.

### Rollback
Per plan Rollback Plan: revert `claude/prepare.ps1`, `claude/Dockerfile`, `claude/Dockerfile.slim` (single commit `79a421a`), re-run `prepare.ps1` — context-mode returns to copy-and-patch, no image/host state persists.

### Out-of-scope confirmed untouched
Rewrite ladder (`Convert-WinPathToLinux`/`Rewrite-Command`/`allowedPathPrefixes`), other plugins' staging, standalone `context-mode-cache-heal.mjs`, stale `context-mode@context-mode` enabledPlugins entry, `codex/`+`opencode/` siblings.
