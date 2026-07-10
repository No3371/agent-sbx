# Walkthrough: Build-Time Language Feature Flags

> **Execution Date:** 2026-07-10
> **Completed By:** Codex
> **Source Plan:** 2607100748-language-build-feature-flags-plan.md
> **Result:** Partial Success — static checks passed; PowerShell/container verification deferred.

---

## Summary

Implemented mutually exclusive `-Enable` allow-list and `-Disable` deny-list selectors in every `build.ps1`. Claude full/slim builds now gate optional `go`, `dotnet`, and `python`; shared tools remain fixed. Runtime proof remains unavailable: no PowerShell, Docker, or Podman host.

## Objectives

| Objective | Status | Evidence |
|---|---|---|
| Selector contract | Complete | `867a4d9`; static inspection |
| Claude install gates | Complete | `ca5f2f8`; static inspection |
| Image catalogs/docs | Complete | `fcca9f5`; static inspection |
| Runtime acceptance matrix | Deferred | no PowerShell/container engine |

## Actual Changes

| File | Change | Plan |
|---|---|---|
| `claude/build.ps1:25-108` | Add `-Enable`/`-Disable` validation; fixed `INSTALL_*=0|1` build args. | Yes |
| `codex/build.ps1:25-104` | Add shared selector validation; reject selections against empty catalog. | Yes |
| `opencode/build.ps1:25-104` | Same empty-catalog selector behavior. | Yes |
| `claude/Dockerfile:24-111` | Gate Go/.NET/Python installs and validate direct build args. | Yes |
| `claude/Dockerfile.slim:13-97` | Gate same runtime set; remove disabled-Go PATH leakage. | Yes |
| `claude/README.md:32-45` | Document Claude catalog/default/exclusive examples. | Yes |
| `codex/README.md:31-37` | Document no optional-language catalog and fixed core/shared tools. | Yes |
| `opencode/README.md:38-43` | Document no optional-language catalog and fixed core/shared tools. | Yes |
| `test-build-feature-flags.ps1:1-66` | Add mocked script contract harness. | Added during execution |
| `2607100748-language-build-feature-flags-log.md` | Record execution, static checks, and runtime blocker. | Execution artifact |

No planned implementation file was skipped. `test-build-feature-flags.ps1` was added to cover the plan's mocked-engine verification.

## Criteria

| Criterion | Result | Evidence |
|---|---|---|
| Flags mutually exclusive; validate before prepare/engine | Pass — static | `867a4d9`; script ordering review |
| Omitted selectors preserve behavior | Pass — static | fixed default `INSTALL_*=1` args |
| `-Enable go` only installs Go | Deferred | Docker images not built |
| `-Disable dotnet` preserves Go/Python | Deferred | Docker images not built |
| Unknown/duplicate/unsupported names fail | Pass — static | selector validator; harness added but unrun |
| Full/slim gate identical runtime set; no disabled PATH/check | Pass — static | `ca5f2f8`; slim PATH review |
| READMEs explain contract/examples | Pass — static | `fcca9f5` |

Static validation passed: `git diff --check 724a85c..969140a`; script/Dockerfile/README contract inspection passed. Not run: `test-build-feature-flags.ps1`, full/slim default, `-Enable go`, and `-Disable dotnet` build/run matrix.

## Deviations and Issues

- Runtime matrix deferred: host lacks `pwsh`, Windows PowerShell, Docker, and Podman. No code deviation; implementation retained at user request.
- Audit `2607100834-language-build-feature-flags-audit.md`: Accept with Conditions. Required follow-up: run harness; build/run both Dockerfiles for default, allow-list, deny-list; assert enabled runtimes work, disabled ones are absent, shared commands remain.

## Insights

- Fixed canonical `INSTALL_*=0|1` arguments keep user selector input out of Dockerfile shell.
- Empty catalogs should reject selectors, avoiding misleading no-op flags.
- Container feature removal requires final-image checks; source-only review cannot prove inherited-image contents.

## Follow-up

- [ ] On a PowerShell host with Docker/Podman, run `./test-build-feature-flags.ps1` and the six-image full/slim matrix.
- [ ] Include unknown, blank, and all-disabled selector cases.

## References

- Commits: `867a4d9`, `ca5f2f8`, `fcca9f5`, `969140a`.
- Execution log: 2607100748-language-build-feature-flags-log.md.
- Audit: 2607100834-language-build-feature-flags-audit.md.
