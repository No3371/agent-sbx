# Audit: run-images-without-sbx Execution

> **Audit Date:** 2026-07-06 | **Auditor:** agent (audit-projex) | **Work Period:** 2026-07-06 03:10–03:30
> **Subject:** Execution of `2607060236-run-images-without-sbx-plan.md` (patched by `2607060700-run-images-redteam-fixes-patch.md`) on branch `projex/2607060236-run-images-without-sbx`, worktree `.projexwt/2607060236-run-images-without-sbx`
> **Related:** `2607060232-run-images-without-sbx-eval.md`, `2607060236-run-images-without-sbx-plan.md`, `2607060240-run-images-without-sbx-redteam.md`, `.projex/closed/2607060700-run-images-redteam-fixes-patch.md`, execution log (worktree-only, gitignored)

---

## Audit Summary

**Claim:** Plan (Status: Complete) delivered `claude/run.ps1` + `codex/run.ps1` no-sbx launchers and updated both READMEs, with all 5 redteam-driven patch fixes baked in, across 4 commits (`80420c8`, `1af557c`, `2cf6e7e`, `8b3f4bd`).

**Verdict:** Verified (code delivery) / Partial (status honesty) — the artifacts match the patched plan's spec **verbatim**, but "Plan Status: Complete" overstates what was validated. Zero live-container verification occurred (no correctly-tagged image locally); this is disclosed in the log, not hidden, but the plan-level status field doesn't reflect that caveat.

**Assessment:** Completeness: High (code/docs) | Correctness: Unknown (untested against a real container) | Quality: High | Value: Unproven

**Top Issues:**
1. **Status-accuracy gap** — "Complete" implies the Success Criteria checklist (6 items, all container-behavior claims) is satisfied. None of the 6 have been checked off or observed; the plan's own checkboxes remain unticked in the document. Should be "Complete (code) / Unverified (runtime)" or similar, not a bare "Complete."
2. **No regression path if A1/A3 assumptions are wrong** — if Claude/Codex actually use a keychain or a different auth path than assumed, the wrapper silently "works" (launches container) but never persists login, and the user won't discover this until they hit re-auth friction on run #2 — with no CI/test/smoke-check to catch it before that point.
3. Everything else (script content, README content, commit hygiene, patch-fix presence) checks out cleanly — no scope creep, no shortcuts, no drift between spec and disk.

---

## Claims vs Evidence

| Claim | Evidence | Status | Notes |
|-------|----------|--------|-------|
| `claude/run.ps1` created, matches plan Step 1 | `.projexwt/.../claude/run.ps1` read in full; diffed line-by-line vs plan lines 110-169 | ✓ | Byte-identical to plan's fenced block |
| `codex/run.ps1` created, matches plan Step 2 | `.projexwt/.../codex/run.ps1` read in full; diffed vs plan lines 190-245 | ✓ | Byte-identical |
| `claude/README.md` `## Run` updated per Step 3 | `git show 2cf6e7e` | ✓ | Diff is additive-only; sbx block retained under "Legacy sbx path" |
| `codex/README.md` `## Run` updated per Step 4 | `git show 8b3f4bd` | ✓ | Same pattern |
| 4 commits contain claimed content | `git show` on all 4 SHAs | ✓ | Each commit touches exactly 1 file, matches its stated step |
| Automated PS5.1 parse-check passed | Log narrative only (not re-run by this audit) | ⚠ | Plausible given script structure (`throw` on line 27/26 matches log's claim), but not independently re-executed — see Gap Analysis |
| Live-container verification (workspace mount, OAuth persistence, no-shadow, docker/podman parity) | Log explicitly states none performed; no image available | ✗ (honestly disclosed) | Real gap, correctly flagged in log — but not reflected in plan's `Status: Complete` field |

---

## Objective Verification

### Objective 1: `claude/run.ps1` — exact mount/flag structure per patched plan

**Evidence:** `.projexwt/2607060236-run-images-without-sbx/claude/run.ps1` (58 lines), plan lines 110-169.

**Findings:**
- Actual: SECURITY header comment present (lines 12-15) ✓. `[System.IO.File]::WriteAllText($claudeJson/$credsFile, '{}', $utf8NoBom)` BOM-less writes present, no `Set-Content -Encoding utf8` anywhere ✓. `-v cwd:/workspace`, `-w /workspace`, individual-file mounts for `.claude.json` and `.credentials.json` (not whole-`.claude` dir) ✓. `if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }` wired conditionally, not left as manual fallback ✓. Interactive launch: `run', '-it', '--rm'` + explicit `claude` command ✓.
- Missing: Nothing vs spec.
- Quality: High — matches build.ps1 conventions (param block, `$ErrorActionPreference='Stop'`, engine check, splatting).

**Verification:** ✓ Verified

**Issues:** None.

### Objective 2: `codex/run.ps1` — same structure, codex-specific paths

**Evidence:** `.projexwt/2607060236-run-images-without-sbx/codex/run.ps1` (54 lines), plan lines 190-245.

**Findings:**
- Actual: SECURITY header (lines 11-14) ✓. BOM-less `WriteAllText` for `auth.json` ✓. Single-file mount `/home/agent/.codex/auth.json` (not whole `.codex` dir) ✓. Conditional `--userns=keep-id` for podman ✓. Interactive `codex` command ✓.
- Missing: Nothing vs spec.
- Quality: High.

**Verification:** ✓ Verified

### Objective 3: 5 patch fixes present in code (not just plan text)

| Fix | claude/run.ps1 | codex/run.ps1 | claude/README.md | codex/README.md |
|---|---|---|---|---|
| (a) Security comments | ✓ lines 12-15 | ✓ lines 11-14 | ✓ "**Security:**" para | ✓ "**Security:**" para |
| (b) BOM-less write | ✓ `WriteAllText`+`UTF8Encoding($false)` | ✓ same | N/A (doc) | N/A (doc) |
| (c) Conditional `--userns=keep-id` | ✓ line 53 | ✓ line 49 | N/A | N/A |
| (d) Security note + `ccrun`/`codexrun` alias snippet | N/A | N/A | ✓ both present | ✓ both present |
| (e) Verification Plan A1/A2/A3 one-at-a-time callout | N/A (plan doc, not code) | — | — | — |

**Verification:** ✓ Verified — all 5 fixes present in the actual artifacts, not merely claimed in plan prose. (e) is a plan-document-only fix by nature (it governs manual verification sequencing) and is present in plan lines 356-358.

### Objective 4: Commit integrity

**Evidence:** `git show` on `80420c8`, `1af557c`, `2cf6e7e`, `8b3f4bd`.

**Findings:** Each commit is single-file, additive-only (no deletions/edits to unrelated lines), matches its commit message exactly. `git diff main..projex/2607060236-run-images-without-sbx --stat`: 4 files changed, 165 insertions, 0 deletions — consistent with "2 new scripts + 2 README additions," no surprise files.

**Verification:** ✓ Verified

### Objective 5: Gap analysis — Plan Status: Complete vs zero live-container verification

**Findings:**
- Log is candid: explicitly lists local image mismatch (`sbx-cc-custom:v1` present, `cc-custom:v1`/`codex-custom:v1` absent), podman absent from PATH, and inability to perform interactive OAuth login as an agent. It enumerates exactly which Success Criteria/Acceptance Criteria rows are unverified (all 6, per the Verification Plan table) and attributes them to "Requires human with a correctly-tagged built image (NOT automatable here)."
- Nothing was silently skipped or misrepresented **within the log** — the log's own "Completion — Verification Summary" section separates "Automated (passed here)" from "Requires human ... NOT automatable" clearly.
- However, the **plan document's header field** (`> **Status:** Complete`) carries no such qualifier. A reader who only looks at the plan header (not the log, which lives in a gitignored worktree path and won't survive worktree cleanup) would reasonably assume "Complete" means the Success Criteria are met. All 6 Success Criteria checkboxes in the plan are still unchecked (`- [ ]`), which is itself internally inconsistent with a "Complete" status — the plan file was never updated to check any of them off.
- This is a genuine **claim/evidence mismatch at the status-field level**, even though the underlying log is honest. Audits exist to catch exactly this: a technically-truthful log paired with an overclaiming status header.

**Verification:** ⚠ Partial — gap is real, correctly disclosed in the log's prose, but not reflected in the plan's machine-readable status/checkbox state.

### Objective 6: Undocumented changes / scope creep / TODOs

**Findings:** No TODO/FIXME/HACK/XXX markers in any of the 4 new/modified files. No Dockerfile/prepare.ps1/build.ps1/retag-tar.ps1 touched (confirmed via `git diff --stat` against those paths — empty). No stray files in the commits. One minor self-reported issue in the log: "Log-file edit during Step 3 briefly placed the Step 3 entry ahead of Step 2's body (ordering slip in the log only)" — cosmetic, log-only, doesn't affect committed code.

**Verification:** ✓ Verified — no scope creep found.

---

## Code/Implementation Inspection

### `claude/run.ps1` / `codex/run.ps1`

**Claimed:** Verbatim per patched plan Steps 1-2.
**Actual:** Verbatim match, confirmed by direct line-by-line read against plan's fenced code blocks. Quality: High.

**Issues Found:** None at Critical/High. One Medium-severity **design gap inherited from the plan, not introduced by execution**: if assumption A1 (creds persist to file, not keychain) or A3 (codex auth path) is wrong, the script still "succeeds" (container launches) but silently fails to persist login — no error surfaces until the user notices re-auth prompts on a later run. This is a correctness risk the plan itself flagged as an open assumption (A1/A3) with a documented fallback (named volume), so it's not undisclosed — but it means "Correctness" cannot be rated until a human runs the manual verification steps.

**Undocumented:** None found beyond the log's own minor ordering-slip note.

**Metrics:**
- Readability/Maintainability: High (short, single-purpose, follows existing `build.ps1` conventions)
- Test Coverage: 0% live-behavior coverage; 100% of the one automatable check (PS5.1 parse-check) claimed passed, not independently re-run by this audit
- Technical Debt: Low — deferred items (named-volume fallback, `--userns=keep-id` already wired) are pre-planned contingencies, not debt

### `claude/README.md` / `codex/README.md`

**Claimed:** Replace `## Run` with no-sbx path + legacy sbx retained + security note + profile alias.
**Actual:** Matches exactly; diffs are purely additive (`git show` confirms no lines removed except within the `## Run` section being extended, sbx command retained verbatim under "Legacy sbx path").

**Issues Found:** None.

---

## Testing Validation

**Coverage:** Automated: 1 of 1 planned automated check (parse-check with bogus `-Engine`) — claimed pass in log, plausible given script structure (both scripts `throw` before any container interaction when engine missing), not independently re-executed by this audit (would require live PS5.1 environment). Manual/live: 0 of 6 Acceptance Criteria rows executed.

**Execution:** Automated check: claimed pass, not re-verified here (no meaningful risk — pure static logic, `Get-Command $Engine` + `throw` is deterministic and both scripts contain the exact guard clause read above). Manual/live: not run.

**Missing:** All 6 manual verification items (workspace mount, agent-writable, login persistence x2, no-shadow, docker/podman parity) — correctly identified as blocked on a locally-absent correctly-tagged image + inability to perform interactive OAuth as an agent.

**Quality Issues:** None in what was tested; the untested surface is the majority of the plan's actual value proposition (does it work at all, end-to-end).

---

## Documentation Audit

**Completeness:** User docs (READMEs) — Complete for the no-sbx path as specified. No migration/rollback doc needed beyond the plan's own Rollback Plan section (delete scripts, restore original `## Run` — trivial, correctly scoped).

**Accuracy:** Matches implementation exactly (script paths, flag names, param names all consistent between README prose and actual `run.ps1` param blocks). Examples (the `run.ps1 -Image ... -Engine docker` invocation) are syntactically plausible but unexecuted.

**Quality:** Clarity High, Completeness High for the documented surface, Usability unproven (depends on the untested runtime behavior).

---

## Gap Analysis

### Promised But Not Delivered
| Promise | Status | Impact |
|---------|--------|--------|
| Success Criteria: cwd mounted as `/workspace`, interactive launch, agent-writable, login persistence, no-shadow, docker/podman parity | Not verified — plan checkboxes still unchecked | Medium — this is the entire point of the plan; code exists but is unproven |

### Undocumented Issues
| Issue | Severity | Affects |
|-------|----------|---------|
| Plan `Status: Complete` header doesn't carry a runtime-unverified caveat, despite 6/6 Success Criteria checkboxes remaining unchecked in the same document | Medium | Future reader of the plan (or a `/close-projex` decision) who trusts the header without reading the log |

### Unhandled Edge Cases
- A1/A3 wrong (keychain-only or different auth path) — silent persistence failure, no error surfaced, discovered only via manual re-auth friction on run #2. Plan already has a documented fallback (named volume); risk is in *detection*, not *remediation*.
- Podman path entirely untested (podman not on PATH in the execution environment) — the `--userns=keep-id` wiring is code-reviewed-correct but has never been exercised against a live podman-rootless container.

---

## Quality Assessment

### Completeness: High (for code/docs) / Low (for runtime validation)
**Strengths:** All 4 planned files created/updated exactly as specified; all 5 patch fixes present in actual code, not just plan prose.
**Gaps:** Zero live-container verification; plan's own Success Criteria checklist unchecked.

### Correctness: Unknown
**Works:** Static/structural correctness (param parsing, engine-check throw path): Yes, by inspection. Runtime correctness (mounts, persistence, interactivity): Unverified.
**Bugs:** None found in static review. Potential silent-failure mode on A1/A3 mismatch — Severity: Medium (documented risk, not a coding defect).

### Code Quality: High
**Positive:** Mirrors existing `build.ps1` conventions, self-contained scripts (no premature shared-module abstraction — appropriately lazy given only 2 near-identical wrappers), BOM-less writes, conditional podman flag, clear header comments including security warnings.
**Concerns:** None beyond the inherited runtime-unverified status.
**Tech Debt:** None created — deferred items (named-volume fallback, whole-dir mount avoidance) were pre-identified contingencies already reasoned about in the plan, not shortcuts taken during execution.

### Value Delivered: Unproven
**Intended:** A working no-sbx launcher usable from any project dir on Win10.
**Actual:** Code that should do this, matching a well-reasoned spec, but never run against a real container.
**Impact:** User: Neutral-to-Positive pending first live run — if A1/A3 hold as assumed, this fully delivers; if not, user hits a first-run surprise (re-auth) that the plan already anticipated and has a fallback for.

---

## Open Findings

### Undocumented Discoveries
- Changes: None beyond the 4 files; no scope creep confirmed via `git diff --stat` against out-of-scope files (Dockerfile, prepare.ps1, build.ps1, retag-tar.ps1) — all show zero changes on this branch.
- Problems: None hidden — the log is unusually candid about what wasn't tested and why.
- Workarounds: None needed yet (contingencies for A1/A3 failure are pre-planned, not yet exercised).

### Impact Analysis
- Downstream: None — sbx path (`build.ps1 -LoadToSbx`) untouched, so existing Win11 users unaffected.
- Future: Enabled — Win10 users get a documented path once a live smoke-test confirms A1-A3. Blocked — nothing; this is additive.
- Risks: Silent auth-persistence failure on first real use — Likelihood: Low-Medium (per redteam's own assessment, unchanged by this audit). Podman path fully unexercised — Likelihood: Unknown (no podman available in either execution or audit environment).

### Improvements
- Could be better: The plan/log could have set `Status: Complete (code) — Runtime: Unverified` or similar two-part status, rather than a single "Complete" that conflicts with 6 unchecked criteria in the same file.
- Would make excellent: A lightweight non-interactive smoke test (e.g., `docker run --rm <image> claude --version` or similar non-TTY probe) that doesn't require OAuth but at least confirms the image tag exists and the entrypoint responds — closeable gap even without a human present, though this weakens ponytail's "don't build what isn't needed" principle for genuinely personal tooling; flagging as an option, not a requirement.
- Missed: Nothing structural — the plan correctly scoped out compose/devcontainer/auto-load, consistent with the eval's recommendation.

---

## Stakeholder Impact

| Stakeholder | Promised | Reality | Impact |
|-------------|----------|---------|--------|
| Sole developer (Win10, no sbx) | Working launcher, testable today | Code delivered exactly as specified; first real use is simultaneously the first test | Neutral — expected for personal tooling; risk is bounded and self-disclosed |

---

## Findings

### Critical (Must Address)
- None.

### Significant (Should Address)
- **Plan `Status: Complete` header vs 6 unchecked Success Criteria in the same document** — Update the plan's status field (or add a qualifier) before `/close-projex` treats this as fully done, so a future reader doesn't mistake "code complete" for "verified working." → Either check off criteria after a real smoke test, or change header to reflect code-complete/runtime-pending.

### Minor (Nice to Fix)
- **Log ordering slip during Step 3** (self-reported, log-only, no code impact) → No action needed, already corrected before commit.
- **No non-interactive smoke test** for image-tag/entrypoint sanity → Optional; would catch a subset of failures (wrong tag, broken entrypoint) without needing OAuth, but adds a maintenance surface for genuinely single-user tooling — weigh against YAGNI before adding.

### Positive
- Byte-for-byte fidelity between patched plan and shipped code/docs — unusually clean execution with zero drift.
- All 5 redteam-driven patch fixes verified present in actual artifacts, not just plan prose — the patch step demonstrably did its job.
- Execution log is exemplary in honesty: it proactively separates "automated, passed here" from "requires human, not automatable here" rather than glossing over the untested majority.
- No scope creep: confirmed zero changes to Dockerfile/prepare.ps1/build.ps1/retag-tar.ps1 and no stray files across all 4 commits.

---

## Recommendations

**Immediate:** Before `/close-projex`, either (a) run the deferred manual verification once a correctly-tagged image + podman are available and check off the Success Criteria, or (b) explicitly downgrade the plan's status language to acknowledge code-complete-but-runtime-unverified, so the merge to `main` doesn't imply more confidence than the evidence supports.

**Future:** When the human next builds `cc-custom:v1`/`codex-custom:v1` locally, run the Verification Plan's manual checks one-at-a-time (per the redteam's own No-Go-If condition, already folded into the plan) before relying on `run.ps1` for daily use.

**Process:** For personal-tooling plans where live verification can't be automated end-to-end, consider a plan-status convention that distinguishes "artifacts complete" from "acceptance criteria verified" — this audit's core finding is a status-field ambiguity, not a code defect.

---

## Final Verdict

**Status:** Accept with Conditions

**Overall Assessment:**
- Completeness: High (artifacts) / Low (verification)
- Correctness: Unknown (untested runtime behavior; no static defects found)
- Quality: High
- Value: Unproven pending first live run

**Conditions:**
- [ ] Before merge/close, reconcile the plan's `Status: Complete` with its 6 unchecked Success Criteria — either verify live or relabel status to reflect what's actually confirmed.
- [ ] Run the Verification Plan's manual checks (A1/A2/A3, one at a time per the redteam's No-Go-If condition) at first opportunity with a correctly-tagged image.

**Sign-off:** Yes, with conditions — the code and docs are a faithful, high-quality, zero-drift implementation of the patched plan; the only real issue is a status/evidence mismatch at the plan-document level, not a defect in what was built. Given this is personal single-user tooling with a documented fallback for the main risk (A1/A3), the bar for "Accept with Conditions" rather than "Needs Rework" is met — the conditions are about honesty of status, not correctness of code.
