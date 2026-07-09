# context-mode Build-Time Install Pilot

> **Status:** In Progress — code applied via patch; first-build auth gate OPEN
> **Created:** 2026-07-10
> **Author:** agent
> **Source:** 2607100201-build-time-plugin-install-for-sandbox-images-proposal.md (Option C — Recommended)
> **Related Projex:** 2607091752-context-mode-plugin-path-mapping-memo.md
> **Worktree:** No
> **Partial Execution:** All 3 steps' code applied + Step 1 verified via 2607100248-context-mode-build-time-install-pilot-patch.md (commit `79a421a`). Step 2/3 auth gate (does `claude plugin install` run unauthenticated at build time?) NOT yet verified — run `claude/build.ps1` to resolve; if it refuses login-less, fall back to proposal Option B. Do NOT close this plan until the build confirms the gate.

---

## Summary

Pilot the proposal's build-time plugin-install mechanism against `context-mode` only — the one plugin with a confirmed host-path failure. Stop vendoring context-mode's host-built payload; instead install it fresh during `docker build` via `claude plugin marketplace add` / `claude plugin install`, so its paths/caches/hooks are Linux-native and nothing needs rewriting. All other plugins keep the current copy-and-patch path unchanged.

**Scope:** `claude/prepare.ps1` (strip context-mode payload + registry entries), `claude/Dockerfile` + `claude/Dockerfile.slim` (add build-time install RUN). Single projex scope (`claude/.projex/`).
**Estimated Changes:** 3 files, ~1 new prepare block + 3 registry-filter edits, 1 new Dockerfile RUN step each ×2.

---

## Objective

### Problem / Gap / Need

Current pipeline copies host `~/.claude/plugins` byte-for-byte into the image, then rewrites host-absolute paths in `installed_plugins.json` / `known_marketplaces.json` / hook commands via a regex ladder (`prepare.ps1`). `context-mode`'s MCP entrypoint self-heals `settings.json` hook paths to whichever host last booted it — producing exactly the host-absolute shapes the regex allowlist must keep chasing (diagnosed live in 2607091752 memo). Any new host path-shape is a reactive new regex case that silently drops or ships a broken hook.

Pilot goal: prove `claude plugin marketplace add` / `claude plugin install` work non-interactively inside `docker build` (no TTY, `agent` user), against context-mode's public GitHub marketplace, before Option A deletes the rewrite surface for plugins not yet proven to install this way.

### Success Criteria

- [x] `[PATCHED]` `prepare.ps1` does NOT stage context-mode's payload (`plugins/cache/claude-context-mode`, `plugins/marketplaces/claude-context-mode`) nor its registry entries (`context-mode@claude-context-mode` in `installed_plugins.json`; `claude-context-mode` in `known_marketplaces.json`) into `context/.claude/plugins/`. — verified by live `prepare.ps1` run.
- [x] `[PATCHED]` `settings.json` `enabledPlugins["context-mode@claude-context-mode"]` is still preserved (identity kept — only payload dropped). — verified in staged `settings.json`.
- [~] `[PATCHED]` `claude/Dockerfile` and `claude/Dockerfile.slim` each build-time install context-mode via `claude plugin marketplace add mksglu/claude-context-mode` + `claude plugin install context-mode@claude-context-mode --scope user`, placed so the existing native-module `npm install` loop rebuilds context-mode's `better-sqlite3` for Linux. — RUN steps added in correct position; **build not yet run** (auth gate).
- [ ] Built image: `/home/agent/.claude/plugins/cache/claude-context-mode/context-mode/<ver>/` is present, was written by the in-container install (not the host copy), and contains no `C:\Users\...` path in any context-mode install state. — PENDING first build.
- [ ] Built image at runtime: context-mode MCP tools resolve (`ctx_*` callable) and the `context-mode-cache-heal.mjs` SessionStart hook runs without error. — PENDING first build.
- [x] `[PATCHED]` All OTHER plugins remain provisioned by the existing copy-and-patch path — no change to their staging or registry entries. — staging verified (only context-mode stripped); build-side re-confirm at first build.

### Out of Scope

- Deleting `Convert-WinPathToLinux` / `Rewrite-Command` / `allowedPathPrefixes` / the rest of the rewrite ladder (that's Option A full cutover — a follow-up, gated on this pilot).
- Migrating any plugin other than context-mode to build-time install.
- Removing or altering the `context-mode-cache-heal.mjs` SessionStart hook (may become redundant once build-time install proves stable — separate follow-up).
- Cleaning up the stale `context-mode@context-mode` `enabledPlugins` entry (no matching marketplace exists; harmless — noted below).
- `codex/` and `opencode/` sibling prepare/Dockerfile pairs.
- Private/gated-marketplace auth story (context-mode's marketplace is a public GitHub repo).

---

## Context

### Current State

- `prepare.ps1:87-103` — generic loop copies each host `~/.claude/<dir>` (incl. `plugins/`) into `context/.claude/<dir>` via `Copy-ItemFiltered`.
- `prepare.ps1:139-156` — loads `plugins/installed_plugins.json`, rewrites every `installPath` Win→Linux.
- `prepare.ps1:158-170` — `$pluginCachesToDrop` removes host-state cache dirs post-copy (`claude-hud/config-cache`, `claude-hud/transcript-cache`).
- `prepare.ps1:172-186` — loads `plugins/known_marketplaces.json`, rewrites every `installLocation` Win→Linux.
- `Dockerfile:142` / `Dockerfile.slim:128` — `COPY context/.claude/plugins/ → /home/agent/.claude/plugins/`.
- `Dockerfile:150-154` / `Dockerfile.slim:136-140` — `RUN` loop: `npm install` in every plugins subdir with a `package.json` (rebuilds native addons like context-mode's `better-sqlite3` for Linux).

context-mode facts (verified in staged context this session):
- Marketplace `claude-context-mode`, source GitHub `mksglu/claude-context-mode` (from `known_marketplaces.json` — **NOT** in `settings.json` `extraKnownMarketplaces`).
- `enabledPlugins` has TWO context-mode entries: `context-mode@claude-context-mode` (real, matches marketplace) and `context-mode@context-mode` (stale — no `context-mode` marketplace in registry; ignored).
- Payload dirs: `plugins/cache/claude-context-mode/context-mode/1.0.169/`, `plugins/marketplaces/claude-context-mode/`.
- Registry: `installed_plugins.json` key `context-mode@claude-context-mode`; `known_marketplaces.json` key `claude-context-mode`.

### Key Files

| File | Role | Change Summary |
|------|------|----------------|
| `claude/prepare.ps1` | Stages + rewrites host payload | Add build-time-install exclusion list; strip context-mode payload dirs + its 2 registry entries so image arrives with no context-mode host state |
| `claude/Dockerfile` | Full sbx image build | Add `RUN` (as agent) installing context-mode via claude CLI, before the native-module npm loop |
| `claude/Dockerfile.slim` | Slim image build | Same `RUN` inserted before its npm loop — parity |

### Dependencies

- **Requires:** `claude` CLI invocable non-interactively as `agent` at build time. Base `Dockerfile` (`docker/sandbox-templates:claude-code`) ships claude preinstalled; `Dockerfile.slim` installs+symlinks it to `/home/agent/.local/bin/claude` on PATH. **Assumption to verify first (see Assumptions).**
- **Blocks:** Option A full-cutover plan/proposal (gated on this pilot proving the mechanism).

### Constraints

- `docker build` already has network egress (nodesource, Go tarball, npm -g, Chrome-for-Testing). Adding a GitHub marketplace clone is within the existing network model — no new *auth* is introduced for a public repo.
- No version pin available on `claude plugin install` (confirmed in proposal) — build-time install gets marketplace-latest, not host-pinned. Accepted trade for the pilot.
- `settings.json` `enabledPlugins` identity for context-mode must survive prepare.ps1 (only the payload is dropped).

### Assumptions

- **`claude plugin install` / `marketplace add` run without an authenticated login in a build with no baked OAuth.** sbx supplies OAuth only at runtime; the build container has none. If any `claude plugin` subcommand refuses to run unauthenticated, this is a hard blocker → fall back to proposal Option B. **This is the pilot's primary unknown — verify at the very first build.**
- `claude plugin marketplace add` accepts the `owner/repo` GitHub shorthand `mksglu/claude-context-mode` (matches `known_marketplaces.json` `source:github, repo:...`). If it needs a full URL, swap to `https://github.com/mksglu/claude-context-mode`. Low risk.
- `claude plugin install` merges into existing `~/.claude/plugins/installed_plugins.json` (adds context-mode alongside the copied entries for other plugins) rather than overwriting. Verify the other plugins survive the install step.
- Installing context-mode lays down a `package.json` under its cache dir before the existing npm loop runs, so the loop rebuilds `better-sqlite3` for Linux. (Ordering enforced in Step 2/3.)

### Impact Analysis

- **Direct:** `claude/prepare.ps1`, `claude/Dockerfile`, `claude/Dockerfile.slim`.
- **Adjacent:** `settings.json` hook `context-mode-cache-heal.mjs` (still staged from `hooks/`, unchanged); native-module npm loop now also covers the build-time-installed context-mode dir.
- **Downstream:** None to running images' behavior. Local builds no longer mirror the host's exact context-mode version (gets marketplace-latest). Two provisioning mechanisms coexist until Option A cutover (intentional pilot state).

---

## Implementation

### Overview

Two coordinated edits: (1) `prepare.ps1` stops vendoring context-mode (payload dirs + registry entries removed, `enabledPlugins` identity kept); (2) both Dockerfiles install context-mode in-container via the claude CLI, ordered before the existing npm-install loop so native deps get a Linux rebuild. A single top-of-block list drives the exclusion so Option A can later extend it.

### Step 1: prepare.ps1 — exclude context-mode from vendored payload

**Objective:** Image build context arrives with zero context-mode host state; identity preserved in `settings.json`.
**Confidence:** High
**Depends on:** None

**Files:**
- `claude/prepare.ps1`

**Changes:**

1a. Add exclusion list near the existing `$pluginCachesToDrop` (after line 156, before the `$pluginCachesToDrop` definition at 160):

```powershell
# --- Build-time install pilot (see 2607100235-context-mode-build-time-install-pilot-plan.md) ---
# Marketplaces listed here are NOT vendored from the host. The Dockerfile installs
# their plugins fresh via `claude plugin install`, so paths/caches/hook commands are
# whatever Claude Code writes on Linux — nothing to rewrite. Strip their payload dirs
# and registry entries so the image has no host-baked state for them and the in-container
# install writes its own. Extend this list (not fork the logic) for Option A cutover.
$buildTimeInstallMarketplaces = @('claude-context-mode')
```

1b. In the `installed_plugins.json` block (currently 139-156), after `$obj = ... ConvertFrom-Json` and before the rewrite loop, drop entries whose marketplace (suffix after `@`) is build-time-installed:

```powershell
# After: $obj = Get-Content $installedPluginsPath -Raw | ConvertFrom-Json
if ($obj.PSObject.Properties['plugins']) {
    foreach ($name in @($obj.plugins.PSObject.Properties.Name)) {
        $mp = ($name -split '@')[-1]
        if ($buildTimeInstallMarketplaces -contains $mp) {
            $obj.plugins.PSObject.Properties.Remove($name)
            Write-Host "[prepare] installed_plugins.json: removed $name (build-time install)"
        }
    }
}
# ... existing rewrite loop continues on the remaining entries ...
```

1c. Extend the post-copy payload drop. After the existing `$pluginCachesToDrop` loop (ends ~170), add:

```powershell
foreach ($mp in $buildTimeInstallMarketplaces) {
    foreach ($sub in @("plugins/cache/$mp", "plugins/marketplaces/$mp")) {
        $p = Join-Path $Destination $sub
        if (Test-Path $p) {
            Remove-Item $p -Recurse -Force
            Write-Host "[prepare] dropped build-time-install payload: $sub"
        }
    }
}
```

1d. In the `known_marketplaces.json` block (currently 172-186), after `$obj = ... ConvertFrom-Json`, drop build-time-installed marketplace keys before the rewrite loop:

```powershell
# After: $obj = Get-Content $knownMarketplacesPath -Raw | ConvertFrom-Json
foreach ($mp in $buildTimeInstallMarketplaces) {
    if ($obj.PSObject.Properties[$mp]) {
        $obj.PSObject.Properties.Remove($mp)
        Write-Host "[prepare] known_marketplaces.json: removed $mp (build-time install)"
    }
}
# ... existing rewrite loop continues on the remaining entries ...
```

**Rationale:** One list drives all three exclusions (payload dirs + both registry files) — matches the existing `$pluginCachesToDrop` pattern and is trivially extensible for Option A. Removing the registry entries (not just the dirs) means the build-time `marketplace add` starts from a clean slate with no stale `installLocation` pointing at a dir we didn't copy. `settings.json` `enabledPlugins` is untouched — identity survives.

**Verification:** Run `pwsh claude/prepare.ps1`; confirm `[prepare]` logs the three removals; confirm `context/.claude/plugins/cache/claude-context-mode` and `.../marketplaces/claude-context-mode` are absent; confirm `context/.claude/plugins/installed_plugins.json` has no `context-mode@claude-context-mode` key and `known_marketplaces.json` has no `claude-context-mode` key; confirm `context/.claude/settings.json` still has `enabledPlugins["context-mode@claude-context-mode"]: true`.

**If this fails:** Revert prepare.ps1 edits; the copy-and-patch path for context-mode is restored intact.

---

### Step 2: Dockerfile — build-time install context-mode

**Objective:** Full image installs context-mode in-container, native deps rebuilt for Linux.
**Confidence:** Medium (gated on the CLI-auth assumption)
**Depends on:** Step 1

**Files:**
- `claude/Dockerfile`

**Changes:** Insert a new `RUN` between the plugins `COPY` (line 142) and the native-module npm loop (line 150), as `USER agent` (already in effect since line 109):

```dockerfile
# Plugins payload ... (existing COPY at 142, unchanged)
COPY --chown=agent:agent context/.claude/plugins/      /home/agent/.claude/plugins/

# Build-time install pilot (see .projex/2607100235-context-mode-build-time-install-pilot-plan.md).
# prepare.ps1 strips context-mode's host-vendored payload + registry entries, so it is
# installed fresh here against the container's own Linux filesystem — no host-baked paths
# to rewrite. Public GitHub marketplace, no auth. Runs BEFORE the npm loop below so
# context-mode's better-sqlite3 gets rebuilt for Linux by that same loop.
RUN set -eux; \
    claude plugin marketplace add mksglu/claude-context-mode; \
    claude plugin install context-mode@claude-context-mode --scope user

# prepare.ps1 skips node_modules/ ... (existing npm loop at 150-154, unchanged)
RUN set -eux; \
    for d in $(find /home/agent/.claude/plugins -maxdepth 8 -name package.json -printf '%h\n'); do \
        echo "[build] npm install: $d"; \
        (cd "$d" && npm install --no-audit --no-fund); \
    done
```

**Rationale:** `--scope user` writes into the container's own `~/.claude` (decided in proposal — avoids project/local scope leaking install state onto a host bind-mount). Placing the install before the existing npm loop reuses the already-present native-rebuild machinery instead of adding a second one. No new deletion of the copy path — other plugins still flow through it.

**Verification:** `docker build` (or `podman build`) succeeds. In the built image: `ls /home/agent/.claude/plugins/cache/claude-context-mode/context-mode/` shows an install; `grep -r 'C:\\\\Users' /home/agent/.claude/plugins/installed_plugins.json /home/agent/.claude/plugins/known_marketplaces.json` finds nothing for context-mode; other plugins' cache dirs still present.

**If this fails (esp. auth):** Remove this `RUN`; restore context-mode to `prepare.ps1`'s copy path by dropping `'claude-context-mode'` from `$buildTimeInstallMarketplaces` (Step 1). If failure is CLI-auth-at-build-time → escalate to proposal Option B (narrow the rewrite surface, no build-time install).

---

### Step 3: Dockerfile.slim — parity

**Objective:** Slim image mirrors Step 2 exactly.
**Confidence:** Medium (same gate as Step 2)
**Depends on:** Step 1

**Files:**
- `claude/Dockerfile.slim`

**Changes:** Insert the identical `RUN` between the plugins `COPY` (line 128) and the npm loop (line 136), under `USER agent` (in effect since line 115). claude resolves via `/home/agent/.local/bin/claude` (symlinked at 102, on PATH via line 16 ENV):

```dockerfile
COPY --chown=agent:agent context/.claude/plugins/            /home/agent/.claude/plugins/

# Build-time install pilot — see .projex/2607100235-context-mode-build-time-install-pilot-plan.md.
# (identical rationale to Dockerfile; runs before the npm loop so better-sqlite3 rebuilds for Linux)
RUN set -eux; \
    claude plugin marketplace add mksglu/claude-context-mode; \
    claude plugin install context-mode@claude-context-mode --scope user

# prepare.ps1 skips node_modules/ ... (existing npm loop at 136-140, unchanged)
RUN set -eux; \
    for d in $(find /home/agent/.claude/plugins -maxdepth 8 -name package.json -printf '%h\n'); do \
        echo "[build] npm install: $d"; \
        (cd "$d" && npm install --no-audit --no-fund); \
    done
```

**Rationale:** Resolves the proposal's open `Dockerfile.slim` parity question by changing both in lockstep — avoids the two images diverging on plugin handling.

**Verification:** Same as Step 2, against the slim image.

**If this fails:** Same as Step 2.

---

## Verification Plan

### Automated Checks
- [ ] `pwsh claude/prepare.ps1` exits 0 and logs the three context-mode removals.
- [ ] `docker build -f claude/Dockerfile` (via `claude/build.ps1`) succeeds.
- [ ] `docker build -f claude/Dockerfile.slim` succeeds.

### Manual Verification
- [ ] Staged `context/.claude/plugins/` has no `claude-context-mode` cache/marketplace dir and no context-mode registry entries; `settings.json` still enables `context-mode@claude-context-mode`.
- [ ] Built image: context-mode installed under `plugins/cache/claude-context-mode/...`, `better-sqlite3` loads (no native-addon error), no `C:\Users` path in context-mode install state.
- [ ] Run a container: context-mode MCP tools callable (`ctx_*`); `context-mode-cache-heal.mjs` SessionStart hook runs without error; other plugins unaffected.
- [ ] **Auth gate:** confirm the `claude plugin` steps ran without requiring interactive login in the credential-free build.

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected Result |
|-----------|---------------|-----------------|
| context-mode payload not vendored | inspect staged `context/.claude/plugins/` after prepare | no `claude-context-mode` dirs/registry entries |
| identity preserved | grep staged `settings.json` | `enabledPlugins["context-mode@claude-context-mode"]: true` present |
| build-time install works | `claude plugin` steps in build log | exit 0, no auth prompt, context-mode cache dir created |
| Linux-native paths | grep image registry JSONs | no `C:\Users` for context-mode |
| runtime resolves | run container, invoke a ctx tool | tool responds; heal hook no error |
| others unchanged | inspect image plugins for other marketplaces | all present via copy path |

---

## Rollback Plan

Per-step rollback noted above. Full abandon:

1. Revert `claude/prepare.ps1` (removes `$buildTimeInstallMarketplaces` + the three filter blocks) — context-mode returns to copy-and-patch.
2. Revert `claude/Dockerfile` and `claude/Dockerfile.slim` (remove the two `RUN` steps).
3. Re-run `claude/prepare.ps1`; context-mode is vendored + rewritten as before. No image or host state persists from the pilot.

---

## Notes

### Risks
- **claude CLI requires auth at build time (Med likelihood, High impact):** build container has no OAuth. If any `claude plugin` subcommand refuses unauthenticated, pilot is blocked → fall back to proposal Option B. Surface at the first build; do not delete the copy path for other plugins until proven.
- **marketplace-add source form (Low):** if `owner/repo` shorthand rejected, use full GitHub URL.
- **Version drift (Low-Med, accepted):** no pin flag; build gets marketplace-latest. Only lever is a tagged marketplace ref if the repo supports it — out of scope for the pilot.
- **npm-loop ordering (Low):** if `claude plugin install` doesn't lay down `package.json` before the loop runs, `better-sqlite3` won't rebuild → context-mode MCP fails to load at runtime. Caught by the runtime ctx-tool check; fix by making the install `RUN` also `npm install` in the new cache dir.

### Open Questions
- [ ] (execution-time) Confirm claude CLI runs `plugin install` without interactive login in a credential-free build — THE pilot's decisive finding. If it can't, stop and report; do not force it.

### Observations (not blocking)
- Stale `enabledPlugins` entry `context-mode@context-mode` has no matching marketplace and is ignored by Claude Code — left as-is (out of scope). Worth cleaning in a later pass.
- If the pilot holds, follow-ups: (a) Option A full cutover extending `$buildTimeInstallMarketplaces` + deleting the rewrite ladder; (b) reassess whether `context-mode-cache-heal.mjs` is still needed; (c) apply to `codex/` / `opencode/` siblings.

---

## Second-Pass Review Notes

Re-read all three files against the drafted steps:
- `enabledPlugins` identity for context-mode is in `settings.json`, untouched by the plugins-payload edits → identity survives (confirmed against `settings.json:48,52`).
- Marketplace source for context-mode is in `known_marketplaces.json` (`mksglu/claude-context-mode`), NOT `extraKnownMarketplaces` — the proposal's phrasing (install "per `extraKnownMarketplaces` entry") does not apply to context-mode; source is hardcoded in the `RUN` from `known_marketplaces.json`. Discrepancy resolved in favor of the verified file.
- npm-loop ordering: install `RUN` placed before the loop in both Dockerfiles so native rebuild is reused, not duplicated.
- No over-engineering: single list, no parameterization of prepare.ps1, no new script — three small filter blocks + two identical RUN steps.
