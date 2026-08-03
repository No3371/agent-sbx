# Patch: Drop `-Push` Across Current Suites

> **Status:** Complete (Success)
> **Author:** OpenAI Codex
> **Directive:** "Instead of 'A local-only suite MUST NOT expose `-Push`', we should just orchestrate-projex patch(slow) drop -Push across the board"
> **Source Plan:** Direct
> **Related Projex:** 2608030706-coding-agent-sandbox-suite-contract-def.md | 2608030737-coding-agent-sandbox-suite-contract-redteam.md
> **Result:** Success

---

## Summary

Removed `-Push` parameters, engine-push branches, completion output, preparation hints, and maintained operator guidance from all four current suites: `claude/`, `codex/`, `opencode/`, `omp/`. Updated shared-suite Definition from conditional local-only policy to suite-wide registry-publication prohibition while retaining explicit tar/retag/load actions.

## Scope Guard

**Result:** Qualified. Surface: 12 files, one repeated mechanical interface deletion across four equivalent build drivers plus direct docs/callers and one root contract. No design branch, migration, or runtime dependency; focused static verification is immediate. File count exceeds the usual signal only because the same bounded product contract is duplicated per self-contained suite.

---

## Changes

### Build interfaces

**Files:** `claude/build.ps1` | `codex/build.ps1` | `opencode/build.ps1` | `omp/build.ps1`  
**Change Type:** Modified  
**What Changed:**
- Removed `-Push` from each `[CmdletBinding()]` parameter surface (`claude/build.ps1:12-30`; `codex/build.ps1:12-29`; `opencode/build.ps1:12-29`; `omp/build.ps1:12-30`).
- Removed each post-build engine `push` execution/error branch.
- Simplified completion output to local-store or explicit tar/load guidance (`claude/build.ps1:158-166`; `codex/build.ps1:140-148`; `opencode/build.ps1:144-152`; `omp/build.ps1:150-158`).

**Why:** Current suites are local build/run products; registry publication is no longer part of their product interface.

### Maintained callers and operator docs

**Files:** `claude/prepare.ps1` | `codex/prepare.ps1` | `opencode/prepare.ps1` | `claude/README.md` | `codex/README.md` | `opencode/README.md` | `omp/README.md`  
**Change Type:** Modified  
**What Changed:**
- Preparation completion hints now show local image builds only (`claude/prepare.ps1:591-592`; `codex/prepare.ps1:379-380`; `opencode/prepare.ps1:208-209`).
- OpenCode permission warning now applies before build/export instead of a removed flag (`opencode/prepare.ps1:105-107,146-149`; `opencode/README.md:178-179`).
- Suite layouts and build examples describe local build plus explicit export/load only (`claude/README.md:155-162`; `codex/README.md:87-94`; `opencode/README.md:36-44`; `omp/README.md:38-45`).
- OMP secret warning forbids registry publication generically and still forbids sharing exported tar (`omp/README.md:25-27,142-150`).

**Why:** No maintained caller or operator guidance may advertise a removed interface.

### Shared-suite Definition

**File:** `.projex/2608030706-coding-agent-sandbox-suite-contract-def.md`  
**Change Type:** Modified  
**What Changed:**
- Observed build role/interface now lists build/export/load only (`:54,68`).
- R3 prohibits `-Push` and all registry-publication actions suite-wide, not only for a conditional local-only subset (`:133-142`).
- Distribution disclosure, invariant, and lifecycle language now model export/retag/load without registry publication (`:156-168,194-218`).
- Added patch relationship and revision-log entry (`:177-191,247-256`).

**Why:** Directive replaces a future conditional rule with the implemented product-wide contract.

---

## Verification

**Method:** Focused static contract fixture over four build scripts, eight maintained README/prepare surfaces, and root Definition; targeted product-surface search. PowerShell is unavailable on this Linux host, so no unrelated build/runtime command was run; Definition R6 explicitly accepts static focused build-script fixtures.

**Result:**
```text
PASS: 4 build interfaces have no Push parameter/path; retained local export/load controls and balanced blocks.
PASS: 8 maintained README/prepare surfaces contain no -Push caller or guidance.
PASS: root Definition records suite-wide prohibition and updated observed interface/lifecycle.
Targeted case-insensitive product search: no matches for -Push, $Push, push, pushed, pushes, or pushing.
```

**Status:** PASS

---

## Impact on Related Projex

| Document | Relationship | Update Made |
|---|---|---|
| `2608030706-coding-agent-sandbox-suite-contract-def.md` | Root shared-suite Definition | Current observations, R3, invariants, lifecycle, relationship, revision log updated |
| `2608030737-coding-agent-sandbox-suite-contract-redteam.md` | Final pre-patch adversarial snapshot | Unchanged; its publication findings are accurate evidence of the remediated pre-patch state |

## Intentionally Retained `Push` References

- **Normative/history:** `2608030706-coding-agent-sandbox-suite-contract-def.md` retains suite-wide `-Push` prohibition and dated revision history.
- **Pre-patch root records:** `2607060232-run-images-without-sbx-eval.md`, `2608030737-coding-agent-sandbox-suite-contract-redteam.md`, `2607271806-sbx-base-image-suite-plan.md`, `2608022321-drop-obsolete-sbx-images-plan.md`, `2608022327-drop-obsolete-sbx-derived-images-plan-redteam.md` retain period-accurate evaluation, adversarial, abandoned, or closed evidence.
- **OpenCode history:** `2607110159-opencode-suite-port-log.md`, `2607110210-opencode-suite-port-plan-redteam.md`, `2607111343-opencode-suite-port-audit.md`, `2607110159-opencode-suite-port-walkthrough.md` retain the removed interface's execution/review history; their proposed `-Push` gate is superseded by this removal.
- **Non-product planned suite:** `2608030408-c-c-combined-suite-plan.md` and `2608030417-c-c-combined-suite-plan-set-redteam.md` describe a not-yet-runnable `c_c/` design, not a current product surface. R3 now requires removing that planned interface before execution.

---

## Commits

- `2894877` — `projex(patch): remove Push from current suites`
