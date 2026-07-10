# Build-Time Language Feature Flags

> **Status:** Ready
> **Created:** 2026-07-10
> **Author:** Codex — via plan-projex
> **Source:** Direct request
> **Related Projex:** 2607081900-codegraph-integration-audit.md (shared CodeGraph tool remains unconditional)
> **Worktree:** Yes

---

## Summary

Add `-Enable` and `-Disable` language selectors to every image `build.ps1`, translate selections into Docker build args, and make Claude's optional Go, .NET, and Python installs conditional. Default builds stay identical; `-Enable go` creates a Go-only optional-language Claude image, while `-Disable dotnet` retains other optional Claude languages.

**Scope:** `build.ps1` selector parsing | Claude full/slim Dockerfile language gates | build READMEs. Core runtimes and shared tools stay unconditional.
**Estimated Changes:** 8 files — 3 scripts | 2 Dockerfiles | 3 READMEs.

---

## Objective

### Problem / Gap / Need

Build scripts expose image/output options but no way to omit optional language runtimes. Claude always installs .NET, Go, and Python; its slim Dockerfile has an internal .NET guard, but it is not exposed by `build.ps1` and cannot express an allow-list.

### Success Criteria

- [ ] Every `build.ps1` accepts case-insensitive `-Enable <string[]>` and `-Disable <string[]>`; both together fail before `prepare.ps1` or the engine runs.
- [ ] Omitted selectors preserve each image's current behavior.
- [ ] Claude `-Enable go` enables only Go; .NET/Python are absent.
- [ ] Claude `-Disable dotnet` omits .NET; Go/Python remain.
- [ ] Unknown, duplicate, or image-unsupported names fail with the supported-language list; Node, package managers, CodeGraph, agent-browser, compilers, and OS utilities are never selectable.
- [ ] Full/slim Claude Dockerfiles gate the same optional language set; disabled runtimes leave no PATH entries or version checks.
- [ ] All READMEs document defaults, selector precedence, image-specific support, and both requested examples.

### Out of Scope

- Add language runtimes to images that do not already provide them.
- Toggle Node, package managers, CodeGraph, agent-browser, browser payloads, build-essential, git, or other shared tools.
- Runtime switches, image-tag automation, `prepare.ps1`, or `run.ps1`.

---

## Context

### Current State

The three build scripts validate output options, optionally run `prepare.ps1`, assemble `$buildArgs`, then append `$root`; none passes `--build-arg`. Claude full/slim Dockerfiles install Go, .NET, and Python. Slim has `INSTALL_DOTNET=1`; full has no language gates. Codex requires Node for Codex and uses Python with native build tooling; OpenCode installs no separately managed language runtime. Thus Codex/OpenCode expose the common parameters but have empty language catalogs and reject selectors instead of silently producing a misleading image.

### Key Files

| File | Role | Change |
|------|------|--------|
| `claude/build.ps1` | Claude build entrypoint | Validate selectors; pass three `INSTALL_*` args. |
| `codex/build.ps1` | Codex build entrypoint | Common flags; reject selection against empty catalog. |
| `opencode/build.ps1` | OpenCode build entrypoint | Common flags; reject selection against empty catalog. |
| `claude/Dockerfile` | sbx Claude image | Gate Go/.NET/Python installs. |
| `claude/Dockerfile.slim` | slim Claude image | Replace .NET-only gate with same three gates. |
| `claude/README.md` | Claude docs | Document catalog and examples. |
| `codex/README.md` | Codex docs | Document empty catalog/core boundary. |
| `opencode/README.md` | OpenCode docs | Document empty catalog/core boundary. |

### Dependencies

- **Requires:** Docker/Podman standard `--build-arg` support.
- **Blocks:** None.

### Constraints

- Select only optional runtimes owned by the selected Dockerfile.
- `-Enable`: allow-list. `-Disable`: deny-list. Mutually exclusive.
- Normalize/dedupe canonical names: `go`, `dotnet`, `python`.
- Never forward raw selector values into Dockerfile shell.
- Default image/output/prepare behavior remains unchanged.

### Assumptions

- .NET, Go, Python can be independently removed from Claude images; execution verifies shared plugins do not need a disabled runtime at build time.
- Codex Node/Python and OpenCode base runtime are core, not optional features.

### Impact

- **Direct:** build parameter contract and Claude image layers.
- **Adjacent:** Docker cache keys; README public contract.
- **Downstream:** subset users choose matching image tag at run time; no launcher change.

---

## Implementation

### Overview

Use one small selector routine duplicated in self-contained build scripts: validate each image catalog, resolve default/allow/deny behavior, append fixed `INSTALL_<LANG>=0|1` args. Dockerfiles get one arg and conditional block per optional language. No shared PowerShell module.

### Step 1: Add selector handling to build scripts

**Objective:** Same explicit flag contract; safe, deterministic validation.
**Confidence:** High
**Depends on:** None

**Files:** `claude/build.ps1` | `codex/build.ps1` | `opencode/build.ps1`

**Changes:**

```powershell
# Before
[switch]$NoCache,
[string]$Dockerfile = 'Dockerfile.slim',
...
$buildArgs = @('build', '-t', $Image, '-f', $dockerfilePath)
if ($NoCache) { $buildArgs += '--no-cache' }

# After
[switch]$NoCache,
[string[]]$Enable,
[string[]]$Disable,
[string]$Dockerfile = 'Dockerfile.slim',
...
$enabled = Resolve-LanguageSelection -Enable $Enable -Disable $Disable -Supported @('go', 'dotnet', 'python')
$buildArgs = @('build', '-t', $Image, '-f', $dockerfilePath)
foreach ($lang in @('go', 'dotnet', 'python')) {
    $buildArgs += '--build-arg'; $buildArgs += "INSTALL_$($lang.ToUpperInvariant())=$([int]($lang -in $enabled))"
}
if ($NoCache) { $buildArgs += '--no-cache' }
```

Validate before existing `prepare.ps1`: reject both flags, blank/unknown/duplicate names, and any selector with empty catalog. Codex/OpenCode use `@()` and emit no language args. Log resolved languages (or `none; no optional language features`) beside existing engine command.

**Rationale:** Fixed generated args are inspectable and avoid free-form injection. Repeating a small routine is less fragile than a cross-directory module.

**Verification:** Mock engine and `prepare.ps1`: default, `-Enable go`, `-Disable dotnet`, both flags, unknown name, selector against Codex/OpenCode. Assert invalid cases call neither prepare nor engine; valid Claude cases emit expected three args.

**If this fails:** Revert script edits; Dockerfiles remain default-compatible.

---

### Step 2: Gate Claude language layers

**Objective:** Honor build args in both Claude variants without gating shared tooling.
**Confidence:** Medium
**Depends on:** Step 1

**Files:** `claude/Dockerfile` | `claude/Dockerfile.slim`

**Changes:**

```dockerfile
# Before (slim only)
ARG INSTALL_DOTNET=1
if [ "$INSTALL_DOTNET" = "1" ]; then ... dotnet-sdk-${DOTNET_CHANNEL}; fi

# After (both)
ARG INSTALL_GO=1
ARG INSTALL_DOTNET=1
ARG INSTALL_PYTHON=1
if [ "$INSTALL_DOTNET" = "1" ]; then ... dotnet-sdk-${DOTNET_CHANNEL}; fi
if [ "$INSTALL_PYTHON" = "1" ]; then ... install python3 python3-pip python3-venv; fi
if [ "$INSTALL_GO" = "1" ]; then ... download/extract Go ...; fi
```

Move optional packages out of shared core lists. Gate Go tarball layer, `/usr/local/go` PATH/symlinks, and version checks together. Retain Node/pnpm, CodeGraph, agent-browser, OS prerequisites, and `build-essential` outside gates. Strictly accept `0`/`1` for direct Docker callers.

**Rationale:** Dockerfiles are the single install point; build args are cacheable and need no runtime-script changes.

**Verification:** Build full/slim × default | Go-only | no-.NET. Assert shared commands work; enabled language commands work; disabled commands are absent; full Dockerfile no longer unconditionally installs optional language packages.

**If this fails:** Restore old install blocks, then keep Step 1 only after default arg compatibility is confirmed.

---

### Step 3: Document image-specific feature catalogs

**Objective:** Users know what is selectable before build.
**Confidence:** High
**Depends on:** Step 1

**Files:** `claude/README.md` | `codex/README.md` | `opencode/README.md`

**Changes:** Add “Optional language features” after each Build section. Claude lists `go`, `dotnet`, `python`, default-all behavior, exclusivity, and:

```powershell
./build.ps1 -Image claude-custom:go -Enable go
./build.ps1 -Image claude-custom:no-dotnet -Disable dotnet
```

Codex/OpenCode state their images currently expose no optional language features, so selector input is rejected; core runtimes/shared tools intentionally remain fixed.

**Rationale:** Per-image catalogs prevent valid-looking no-op commands.

**Verification:** Compare docs with param declarations/catalogs; copy examples into Step 1 harness.

**If this fails:** Revert docs only.

---

## Verification Plan

### Automated Checks

- [ ] Parse all modified `build.ps1` scripts.
- [ ] Mocked PowerShell harness asserts exact build args and zero-side-effect invalid cases.
- [ ] Build matrix: Claude full/slim × default | `-Enable go` | `-Disable dotnet`.
- [ ] Container checks: shared commands plus enabled/disabled `go`, `dotnet`, `python3`.

### Manual Verification

- [ ] Printed engine command contains only canonical fixed `INSTALL_*` args.
- [ ] README selectors/catalogs match scripts.

### Acceptance Criteria Validation

| Criterion | Verify | Expected |
|-----------|--------|----------|
| Default compatibility | Build defaults | Same optional languages as before. |
| `-Enable go` | Claude command checks | Go present; .NET/Python absent. |
| `-Disable dotnet` | Claude command checks | .NET absent; Go/Python present. |
| Invalid safety | Mock harness | Error before prepare/engine. |
| Shared boundary | Subset image checks | Claude CLI, Node/pnpm, CodeGraph, agent-browser remain. |

---

## Rollback Plan

1. Revert the eight planned files as one set.
2. Rebuild default tags; no migration or runtime cleanup.

---

## Notes

### Risks

- Package refactor may gate a shared prerequisite: cover it in every build-matrix image.
- Direct Docker callers bypass PowerShell validation: use strict Dockerfile values and docs.

### Split Decision

No split — one repo/.projex scope; scripts, Dockerfiles, and docs are one build-time contract within focused-session size.

### Open Questions

None.
