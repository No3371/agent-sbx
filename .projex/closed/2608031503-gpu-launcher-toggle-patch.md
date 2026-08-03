# Patch: GPU launcher toggle

> **Status:** Complete (Success)
> **Author:** agent
> **Directive:** `patch-projex add a --GPU toggle to run scripts to supply gpu to the containers`
> **Source Plan:** Direct
> **Result:** Success
> **Related Projex:** 2608030706-coding-agent-sandbox-suite-contract-def.md

---

## Summary

All four PowerShell launchers accept opt-in `-GPU`. It adds `--gpus all` before
the image argument; default launches remain unchanged.

## Changes

### Launchers

**Files:** `claude/run.ps1` | `codex/run.ps1` | `opencode/run.ps1` | `omp/run.ps1`  
**Change Type:** Modified

- Added `[switch]$GPU`: `claude/run.ps1:81` | `codex/run.ps1:17` | `opencode/run.ps1:30` | `omp/run.ps1:20`.
- Appends `@('--gpus', 'all')` only when set, before each image argument: `claude/run.ps1:222` | `codex/run.ps1:76` | `opencode/run.ps1:147` | `omp/run.ps1:123`.

**Why:** Docker and Podman receive their documented GPU request only when the operator opts in.

### Operator contract

**Files:** `claude/README.md` | `codex/README.md` | `opencode/README.md` | `omp/README.md` | `2608030706-coding-agent-sandbox-suite-contract-def.md`  
**Change Type:** Modified

- Documented `-GPU` and the emitted `--gpus all` runtime argument.
- Requires a preconfigured GPU runtime; no GPU capability is implied by the image alone.
- Updated the suite run-boundary definition.

## Verification

**Method:** Python contract check across all four scripts and READMEs.

**Result:**
```text
PASS: four launchers consistently parse -GPU, emit exactly one --gpus all before the image, and document the opt-in contract.
```

**Status:** PASS

Live launch unavailable: this workspace has neither `pwsh`/`powershell.exe` nor `docker`/`docker.exe`.

## Impact on Related Projex

| Document | Relationship | Update Made |
|----------|--------------|-------------|
| 2608030706-coding-agent-sandbox-suite-contract-def.md | Suite contract | Run boundary now includes `-GPU` → `--gpus all`. |

## Notes

Implementation commit: `9e0aeee` (`projex(patch): add GPU launcher toggle`).
