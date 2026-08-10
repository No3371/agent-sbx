# Execution Log: Modernize Codex sandbox suite

> **Status:** Complete
> **Started:** 20260810 17:08
> **Repo Root:** /workspace
> **Plan File:** codex/.projex/2608101559-codex-suite-modernization-plan.md
> **Base Branch:** main
> **Worktree Path:** .projexwt/2608101559-codex-suite-modernization

## Pre-Check Results

PASS  Plan is committed (26e8b51 projex(revise): waive Codex acceptance gate)
WARN  Working tree has 11 uncommitted change(s)
PRE-CHECK PASSED

Manual validation: `REPO_ROOT=/workspace` owns the plan; `main` is the base branch; plan has no open questions or blockers. The dirty base worktree is unrelated to the scoped Codex execution and is isolated by the required worktree. Fresh worktree contains no project manifest, so no dependency bootstrap applies.

## Steps

### 20260810 17:10 - Step 1: Convert image to root runtime

**Action:** Rewrote `codex/Dockerfile`: removed `agent`/sudo/home plumbing; retained pinned global tools, browser installs, git settings, rm-guard, tini, and bypass command; copied Codex/shared skills to root homes; added no-login `pluginbuild` package phase with `npm install --ignore-scripts`, inventory requirement, lifecycle-marker rejection, and critical hash record.

**Result:** Static scan passed: no `/home/agent`, `agent:agent`, sudoers, `USER agent`, rename, or agent ownership pattern; root workdir/shared-skill copy/unprivileged `--ignore-scripts` phase/hash record present. Docker unavailable; supported Windows image probe deferred.

**Status:** Success

### 20260810 17:17 - Step 2: Extend safe robocopy staging and root-path generation

**Action:** Reworked `prepare.ps1` around canonical path, envelope-marker, containment, reparse, source/destination layout, malformed-skill, and collision checks before staging. Added Pi-compatible file-or-directory robocopy transport; optional shared-skills mirroring; exclusion/credential cleanup; LF normalization; root-path marketplace generation; and sanitized SHA-256/package/lifecycle inventory. Added suite-local generated-context ignores.

**Result:** Static checks passed for four overrides, file-copy branch, root marketplace path, inventory, collision guard, marker, and both ignores. Windows PowerShell/robocopy synthetic fixtures and AST parse are deferred; no real host payload was read.

**Status:** Success

### 20260810 17:20 - Step 3: Forward both preparation roots through build

**Action:** Added `HostAgentsSkillsDir` and `SkillsDestination` optional `build.ps1` parameters and conditional pass-throughs beside the existing Codex parameters.

**Result:** Static check confirms both parameters and non-empty conditional flags. PowerShell AST/mock-engine argv coverage is deferred.

**Status:** Success

### 20260810 17:23 - Step 4: Align launcher with root and isolate Codex caches

**Action:** Replaced generic volume names with workspace/lock-hash `codex-nmvol-*` and `codex-pm-cache-node25` mounted at `/root/.npm`; removed ownership and Podman userns branches; made CodeGraph install/init degradation explicit while preserving device auth and bypass launch.

**Result:** Static scan confirms generation-aware root cache paths, no agent ownership/home/userns tokens, explicit CodeGraph degradation, and unchanged device-auth/bypass command. Fake-engine and Windows smoke coverage deferred.

**Status:** Success

### 20260810 17:27 - Step 5: Rewrite operator contract to match behavior

**Action:** Replaced stale README engine/user/path/cache/staging claims with the root-runtime, trusted-payload, no-root-lifecycle, shared-skills, Docker-only support, and ephemeral-auth contract.

**Result:** Contract scan passed for Docker-only release support, root paths, shared skills, generated cache names, unprivileged package handling, rm-guard limits, Podman non-support, and no host auth/state mount.

**Status:** Success

### 20260810 17:31 - Post-execution verification and cleanup

**Action:** Reviewed all scoped changes; ran `git diff main...HEAD --check`, legacy-token scan, generated-root ignore checks, and session diagnostics. Checked worktree cleanliness; no bootstrap dependencies, containers, servers, fixtures, or build outputs were created.

**Result:** Local static verification passed; no whitespace or pi-lens session findings. Supported Windows PowerShell/robocopy/Docker Desktop fixture, build, image, device-auth, workspace owner/mode, and sentinel-discovery evidence remains environment-deferred as allowed by the waived Step 0 gate and plan dependency note.

**Status:** Success

### Post-execution audit remediation

**Trigger:** 2608101720-codex-suite-modernization-execution-audit.md identified an untrusted existing staging envelope that could be overwritten or cleaned when optional shared skills were absent; it also found Podman run guidance in `build.ps1`.

**Action:** `10ea277` validates a marker bound to the canonical envelope before all staging mutation, rejects pre-existing unmarked envelopes, limits user-facing run guidance to Docker Desktop, and adds `codex/tests/prepare-envelope-regression.ps1`.

**Result:** Static patch invariants and `git diff --check` passed. Windows PowerShell/`robocopy` fixture execution remains deferred because no compatible executable exists here. Patch record: 2608101725-codex-staging-envelope-safety-patch.md.

**Status:** Success

## Deviations

- Pre-check reported dirty base worktree. Required worktree mode isolates those unrelated changes; no stash or base-tree mutation performed.

## Issues Encountered

## Data Gathered

## User Interventions
