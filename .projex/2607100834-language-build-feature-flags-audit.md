# Audit: Build-Time Language Feature Flags

> **Audit Date:** 2026-07-10 | **Auditor:** Codex | **Work Period:** 08:21–08:31 UTC
> **Subject:** `projex/2607100748-language-build-feature-flags` at `969140a` | **Related:** 2607100748-language-build-feature-flags-plan.md | 2607100805-language-build-feature-flags-redteam.md | 2607100748-language-build-feature-flags-log.md

---

## Audit Summary

**Claim:** Every image build script accepts mutually exclusive language allow/deny selectors; Claude's full/slim images install only selected optional runtimes; docs describe contract.

**Verdict:** Partial

**Assessment:** Completeness: Medium | Correctness: Medium | Quality: High | Value: Medium

**Top Issues:**

1. Required PowerShell harness and full/slim container matrix were not run: `pwsh`, Windows PowerShell, Docker, and Podman absent.
2. Disabled runtimes cannot be proven absent from produced images, especially inherited full-image contents.
3. Harness lacks executed coverage for unknown/blank selector values and all-disabled selection.

---

## Claims vs Evidence

| Claim | Evidence | Status | Notes |
|-------|----------|--------|-------|
| Exclusive whitelist/blacklist selectors | `claude/build.ps1:25-76`; same resolver in Codex/OpenCode | ✓ | Uses `$PSBoundParameters` to distinguish omitted from explicitly empty; rejects both switches. |
| Claude maps selections to fixed Docker args | `claude/build.ps1:100-104` | ✓ | Only canonical `INSTALL_GO`, `INSTALL_DOTNET`, `INSTALL_PYTHON` values emitted. |
| Claude full/slim gate all optional installs | `claude/Dockerfile:24-110`; `claude/Dockerfile.slim:13-96` | ✓ static | Each arg defaults to `1`, validates `0|1`, and wraps matching installer. |
| Invalid selector has no build/prepare side effect | `test-build-feature-flags.ps1:39-52` | ⚠ unrun | Test exists; host cannot execute it. |
| Runtime matrix proves presence/absence | 2607100748-language-build-feature-flags-log.md | ✗ | Explicitly blocked; no container engine. |
| Docs match catalogs | `claude/README.md:33-45`; `codex/README.md:31-36`; `opencode/README.md:38-42` | ✓ | Claude catalog/examples; other images reject selectors and retain fixed shared/core tools. |

---

## Objective Verification

### Build-script contract

**Evidence:** `867a4d9`, `969140a`; `claude/build.ps1:36-76,100-104`; `codex/build.ps1`; `opencode/build.ps1`.

**Findings:** Case-normalization, duplicate/blank/unknown rejection, mutual exclusion, and fixed empty catalogs are implemented before engine/prepare checks. `-Enable` returns selected names; `-Disable` returns supported names excluding selections; omission returns all.

**Verification:** ✓ static

### Claude Docker gates

**Evidence:** `ca5f2f8`; `claude/Dockerfile:24-110`; `claude/Dockerfile.slim:13-96`.

**Findings:** Go, .NET, Python packages/version checks are conditional; shared Node/pnpm/CodeGraph/agent-browser/build-essential remain outside gates. Direct Docker callers with non-`0|1` values fail early. Slim no longer adds Go to `PATH`.

**Verification:** ⚠ static only — images not built or run.

### Documentation and test artifact

**Evidence:** `fcca9f5`; `claude/README.md:33-45`; `codex/README.md:31-36`; `opencode/README.md:38-42`; `test-build-feature-flags.ps1:30-64`.

**Findings:** Docs reflect implementation. Mock harness asserts default, Go allow-list, .NET deny-list, mutual-exclusion, duplicate, empty, and empty-catalog cases, plus static Dockerfile checks.

**Verification:** ⚠ source inspected; harness unrun.

---

## Testing Validation

**Executed:** `git diff --check 724a85c..969140a` ✓; commit/worktree inspection ✓.

**Not executed:** `test-build-feature-flags.ps1`; Claude full/slim builds for default, `-Enable go`, `-Disable dotnet`; container command/absence checks. Environment provides none of `pwsh`, `powershell`, `docker`, `podman`.

**Missing harness cases:** unknown name | blank name | `-Disable go,dotnet,python` producing no optional runtime args. Source paths handle them, but execution evidence is absent.

---

## Documentation Audit

**Completeness:** Partial — selector/API docs complete; no executable container-verification record.

**Accuracy:** Static match: Yes. Examples unexecuted.

**Quality:** High — concise catalogs, explicit core/shared boundary, requested examples.

---

## Findings

### Critical (Must Address)

- **Runtime acceptance criteria unverified** — final-image absence/presence and shared-tool survival are central feature claims; source inspection cannot prove inherited full-image contents or Docker layer behavior. → Run the plan matrix on a PowerShell host with Docker or Podman before merge/close.

### Significant (Should Address)

- **Harness edge coverage incomplete** — unknown/blank selector and all-disabled behavior have no executable assertions. → Add three small assertions while running the harness.

### Positive

- Fixed Docker args prevent raw selector values entering Dockerfile shell.
- Dockerfiles reject invalid direct build-arg values; slim Go PATH leakage was removed.
- Four focused commits; clean execution worktree; no unrelated implementation changes found.

---

## Final Verdict

**Status:** Accept with Conditions

**Overall Assessment:** Completeness: Medium | Correctness: Medium | Quality: High | Value: Medium

**Conditions:**

- [ ] Run `test-build-feature-flags.ps1` with PowerShell.
- [ ] Run full/slim Claude default, `-Enable go`, and `-Disable dotnet` builds; assert enabled commands work, disabled `go`/`dotnet`/`python3` are absent, and shared commands work.
- [ ] Add or manually execute unknown, blank, and all-disabled selector tests.

**Sign-off:** No — static implementation is sound, but required runtime evidence is unavailable.
