# Execution Log: Build-Time Language Feature Flags

Started: 2026-07-10 08:21 UTC
Repo Root: /workspace
Plan File: .projex/2607100748-language-build-feature-flags-plan.md
Base Branch: main
Worktree Path: .projexwt/2607100748-language-build-feature-flags

## Pre-Check Results

REPO_ROOT=/workspace
BRANCH=main
PLAN_REL=.projex/2607100748-language-build-feature-flags-plan.md

WARN  Plan is not committed to branch 'main' — commit the plan before proceeding
WARN  Working tree has 14 uncommitted change(s)

PRE-CHECK PASSED

## Tasks

- [x] Initialize isolated worktree and log
- [x] Step 1: Add selector handling to build scripts
- [x] Step 2: Gate Claude language layers
- [x] Step 3: Document image-specific feature catalogs
- [ ] Verify acceptance criteria and audit implementation — blocked: no PowerShell or container engine
- [x] Complete plan and final log

### 20260710 08:21 - Initialize execution

**Action:** Committed the plan to `main` (`218835d`), then created `projex/2607100748-language-build-feature-flags` worktree to isolate the pre-existing unrelated changes.
**Result:** Success. The committed plan resolves the plan warning; the clean worktree resolves the dirty-tree warning without staging unrelated files.
**Status:** Success

### 20260710 08:30 - Final verification and quality review

**Action:** Ran whitespace validation and static contract checks across all scripts, Dockerfiles, and READMEs; reviewed the final diff for selector normalization, Docker argument injection, strict direct-Docker validation, and disabled Go PATH leakage.
**Result:** Static checks pass: selectors validate before preparation, Claude emits canonical fixed install args, both Dockerfiles gate and strictly validate all three args, slim has no Go PATH entry, and docs match the catalogs. PowerShell parsing/mock execution and the full/slim container matrix remain unrun because this environment has no `pwsh`, Windows PowerShell, Docker, or Podman. No resources were started.
**Status:** Partial

## Issues Encountered

- Required runtime verification blocked: no PowerShell host or container engine in the execution environment. Run `./test-build-feature-flags.ps1` on Windows PowerShell, then build Claude full/slim with default, `-Enable go`, and `-Disable dotnet`; verify enabled commands work and disabled `go`, `dotnet`, and `python3` are absent.

### 20260710 08:28 - Step 3: Document image-specific feature catalogs

**Action:** Documented Claude's `go`/`dotnet`/`python` catalog, default-all behavior, exclusivity, and requested allow/deny examples. Documented Codex/OpenCode's empty catalogs and fixed core/shared boundaries.
**Result:** Static README check passes for all selector contracts and examples.
**Status:** Success

### 20260710 08:27 - Step 2: Gate Claude language layers

**Action:** Added `INSTALL_GO`, `INSTALL_DOTNET`, and `INSTALL_PYTHON` defaults plus strict `0|1` checks to both Claude Dockerfiles. Moved each optional installer and version check behind its matching gate; removed the slim Go PATH entries when Go is off.
**Result:** Static Dockerfile check confirms all three args and strict validation in both variants; slim PATH no longer names `/usr/local/go/bin`. Docker/Podman is unavailable, so the required full/slim container matrix could not run locally.
**Status:** Success

### 20260710 08:24 - Step 1: Add selector handling to build scripts

**Action:** Added mutually exclusive case-normalized `-Enable`/`-Disable` selectors to all build scripts. Claude converts the resolved `go`/`dotnet`/`python` set into fixed `INSTALL_*=0|1` arguments; Codex/OpenCode reject selector use against empty catalogs. Added `test-build-feature-flags.ps1` with a mocked engine for default/allow/deny/error behavior.
**Result:** Static checks confirm all scripts validate before `prepare.ps1` and Claude emits only fixed build args. `pwsh`/Windows PowerShell is unavailable in this environment, so the new PowerShell harness could not run here; it is ready for a PowerShell host.
**Status:** Success
