# Execution Log: Drop obsolete sbx-derived images

> **Status:** Complete (Execution Blocked; Branch Abandoned)
> **Started:** 20260803 04:56 UTC
> **Repo Root:** `<repo-root>`
> **Plan File:** 2608022321-drop-obsolete-sbx-images-plan.md
> **Base Branch:** main
> **Worktree Path:** .projexwt/2608022321-drop-obsolete-sbx-images
> **Walkthrough:** 2608022321-drop-obsolete-sbx-images-walkthrough.md

## Pre-Check Results
PASS  Plan is committed (fc30eb7 projex(revise): align image bases on Node 25)
WARN  Working tree has 6 uncommitted change(s)

PRE-CHECK PASSED

Manual validation: repo ownership ✓ | base branch `main` ✓ | no open questions ✓ | source dependencies met ✓ | worktree bootstrap manifest scan found no package-manager bootstrap. Required host-tool availability was checked late at Step 4 and failed; see Deviations.

## Steps

### 20260803 04:58 UTC - Step 1: Preserve image capabilities in self-built definitions
**Action:** Ported each suite's tracked `rm-guard` install/self-test block into its self-built definition. Added pinned `playwright@1.61.1`, agent-owned CLI link, baked Chromium, and cache ownership to Codex.
**Result:** Source inspection confirmed Claude layer order `agent-browser → Playwright Chromium → rm-guard → CLAUDE_CODE_CACHEBUST`; Codex order `global CLIs → agent-browser Chrome → Playwright Chromium → system git config → rm-guard → USER agent`. Both self-tests cover direct and ancestor protected deletion, normal `/tmp` deletion, and `/usr/bin/rm.real` fixture cleanup.
**Status:** Success

### 20260803 04:59 UTC - Step 2: Delete sbx-derived files and promote self-built files
**Action:** Recorded pre-swap revision `db056f5e72c5b065492fa66119f0c5d0758d6d79`; SHA-256 ledger: `claude/Dockerfile` `a44d2982e5df4fb372eaab15d88ae6808a8df4656340d7ca77829d102fc850b2`, `claude/Dockerfile.slim` `6bd626934a7ceab173a1eb479ca3449127181b67930b81f8a1d17905728be8ff`, `codex/Dockerfile` `50fbbccbda90ddd645ce02626b5f4bf0de1f9c4cdec84630b4130dd032029629`, `codex/Dockerfile.slim` `ec70c671023cb7a714e1e1f681d35847f6d882312c757cd370a88eadba9200ca`. Deleted legacy files via `del-n-stage`; promoted both self-built files via `move-n-stage`; neutralized variant comparisons; aligned Codex to Node 25.
**Result:** Both helpers succeeded for their two explicit paths/pairs. Inventory contains only `claude/Dockerfile` and `codex/Dockerfile`; no `.slim` variant. Both canonical `FROM` lines are `node:25-bookworm-slim`; generic sandbox-persistent hooks remain unchanged.
**Status:** Success

### 20260803 05:01 UTC - Step 3: Align build drivers and suite documentation
**Action:** Changed Claude's default build file to `Dockerfile` and made its cachebust probe comment variant-neutral. Rewrote Claude/Codex intro, Build, Run, Layout, and base-image notes for one official Node 25 self-built image; retained direct Docker/Podman launcher instructions; documented rm-guard as an accident guard, not a security boundary.
**Result:** `codex/build.ps1` remains unchanged with default `Dockerfile`. End-to-end README review found one canonical flow per suite. Scoped maintained-file search returned zero non-projex matches for `Dockerfile.slim`, `docker/sandbox-templates`, or `sbx run`; remaining matches are historical suite `.projex/` documents excluded by plan.
**Status:** Success

### 20260803 05:07 UTC - Step 4: Validate canonical builds and runtime parity
**Action:** Bound verification to source `6a81e1fb4e3c74e8baa205eee33e43903c453a28`, reviewed its eight-path tracked change set, confirmed `git diff --check` clean, and recorded prepare blobs (`claude` `f1e5bccdfc7c96107e95a3ee28cd8235876890e3`; `codex` `182adcba3b5cd0ad7c051930e3899363cceb052c`). Probed required PowerShell and Docker/Podman executables before creating run-owned inputs or refs.
**Result:** `pwsh`, `powershell.exe`, `docker`, `docker.exe`, `podman`, and `podman.exe` were all absent (`which` exit `1`). No permitted engine could be selected, so no refs, prepared context, manifest, image IDs, builds, direct probes, trust review, credential-owner approval request, launcher smoke, or runtime cleanup artifact was created. Independent verify-projex round 1 verdict: **Rejected** — static canonical state exists, but every mandatory Step 4 runtime claim lacks evidence; correct completion requires the full same-source/same-engine sequence. Execution stopped rather than substituting another engine or installing persistent host tooling outside plan scope.
**Status:** Partial

### 20260803 05:10 UTC - Post-execution: Finalize blocked execution
**Action:** Revalidated all feasible acceptance criteria, reviewed linked launcher plan/walkthrough and slim-image rationale, performed static quality review, and checked cleanup scope.
**Result:** Static cutover requirements are met with no collateral tracked paths or patch-integrity errors. Linked launcher history explicitly records live runtime as unverified; this execution did not repeat that overclaim. Historical closed guide remains intentionally unchanged. Mandatory build/probe/launcher criteria remain Blocked on unavailable host tooling, so plan/log terminal status is `Blocked`.
**Status:** Partial

## Deviations
Workflow deviation: required PowerShell/container-engine availability should have been confirmed during manual pre-execution validation. It was checked only at Step 4. Impact: Steps 1–3 were completed and committed before the external verification blocker was discovered; no runtime or distribution artifact was created.

## Issues Encountered

Required verification tooling unavailable: neither plan-permitted engine nor PowerShell exists on PATH. Phase: `engine/store`; blocker external to tracked source. No distribution event or unknown destination occurred.

## Data Gathered

Lineage: source `6a81e1fb4e3c74e8baa205eee33e43903c453a28` | context-manifest ID `N/A (prepare not run)` | engine/version `N/A (docker/podman absent)` | refs/IDs `N/A` | distribution `none`.

| Criterion | State | Sanitized evidence |
|---|---|---|
| One image definition per paired suite | Pass | Inventory: only `claude/Dockerfile`, `codex/Dockerfile` |
| No Docker sbx product base | Pass | Both `FROM node:25-bookworm-slim`; maintained-source retired-base search empty |
| Canonical build defaults | Blocked | Both defaults statically `Dockerfile`; required `build.ps1 -SkipPrepare` commands not run — engine/PowerShell absent |
| Immutable one-engine lineage | Blocked | No permitted engine, refs, or immutable IDs |
| rm-guard parity | Blocked | Source blocks/self-tests present; build + ID runtime probes not run |
| Browser parity | Blocked | Playwright/Chromium source layers present; offline ID probes not run |
| Maintained docs match cutover | Pass | Build/Run/Layout review + maintained-source retired-reference search |
| Launcher/runtime intact | Blocked | Direct probes prerequisite unmet; credential trust approval not requested/reached; launcher smoke not run |
| Local-only + safe evidence | Pass | No push/export/load/registry/remote destination; no refs or auth attempt created |
| Atomic approval | Blocked | Mandatory runtime rows lack current-lineage Pass evidence |

Cleanup ledger: no run root, host-source dirs, prepared destinations, workspaces, refs, images, containers, transcripts, or credentials were created; nothing run-owned required removal. Shared launcher volumes were untouched.

## User Interventions

Caller reviewed the blocked result and selected close-projex Option D: abandon the unverified execution branch without merging product changes.

Base worktree had a pre-existing tracked edit to `2608021410-retire-sbx-legacy-plan.md`; close stashed it before lifecycle integration and restored it after branch finalization.
