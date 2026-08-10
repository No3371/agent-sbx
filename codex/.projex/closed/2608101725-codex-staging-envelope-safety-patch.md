# Patch: Harden Codex staging envelope

> **Status:** Complete (Success)
> **Author:** openai-codex/gpt-5.6-terra
> **Directive:** Remediate the immediate bounded findings in 2608101720-codex-suite-modernization-execution-audit.md.
> **Source Plan:** 2608101559-codex-suite-modernization-plan.md
> **Result:** Success
> **Code Commit:** `10ea277` — `projex(patch): harden Codex staging envelope`

---

## Summary

Fixed the caller-controlled staging destination deletion path: existing envelopes now require a marker bound to that exact canonical envelope before any destination mutation. Build output now recommends Docker Desktop only; a Windows PowerShell regression fixture proves unmarked destination data remains untouched.

## Changes

### Staging trust boundary

**File:** `codex/prepare.ps1`
**Change Type:** Modified

- `:100-119` validates marker content against its canonical generated-envelope path; accepts only a new envelope or one previously marked by this script.
- `:121-122,207` gates every staging operation behind the validated marker before `robocopy`, cleanup, or optional-source replacement can mutate targets.

**Why:** An arbitrary pre-existing `<envelope>/.codex` plus `<envelope>/.agents/skills` pair cannot be claimed merely by writing a marker, so missing optional shared skills cannot erase user data.

### Docker-only operator output

**File:** `codex/build.ps1`
**Change Type:** Modified

- `:1,145-155` removes Podman run guidance; Docker-loaded images receive the only run command.
- Podman transfer output remains explicit but unverified and non-runnable; Docker is the sole supported run engine.

**Why:** Aligns build output with the Docker-only release contract in `codex/README.md`.

### Focused regression fixture

**File:** `codex/tests/prepare-envelope-regression.ps1`
**Change Type:** Created

- `:1-43` creates an existing unmarked envelope with Codex/shared-skills sentinels, requires preparation to reject it, then asserts zero mutation and no marker creation.
- Checks build text cannot reintroduce Podman run recommendation/header wording.

**Why:** Captures the destructive override shape named by the audit without reading real host data.

## Verification

**Method:** Static invariant script; `git diff --check`; fixture authored for Windows PowerShell 5.1/`robocopy.exe`.

**Result:**

```text
PASS static patch invariants: trusted envelope, marker-gated staging, Docker-only run output, regression fixture, whitespace clean.
WAIVED: Windows PowerShell/robocopy fixture execution unavailable (no powershell/pwsh/robocopy).
```

**Status:** PASS (static)

## Impact on Related Projex

| Document | Relationship | Update Made |
| --- | --- | --- |
| 2608101720-codex-suite-modernization-execution-audit.md | Remediation trigger | Committed unchanged as audit evidence; High and Podman findings addressed. |
| 2608101559-codex-suite-modernization-plan.md | Source plan | Related-artifact ledger and revision log record this remediation. |
| 2608101559-codex-suite-modernization-log.md | Execution record | Appended post-audit remediation, commit, and verification boundary. |

## Residual

Windows PowerShell/`robocopy` fixture execution, PowerShell AST parsing, Docker/Desktop image probes, workspace/volume tests, and device-auth remain waived/non-blocking because this environment lacks those tools. The new fixture must pass on its supported Windows row before release-support evidence improves. No remaining static path permits an unmarked existing envelope to be mutated.
