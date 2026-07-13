# Audit: Port Claude suite features → OpenCode suite (execution)

> **Audit Date:** 2026-07-11 | **Auditor:** agent (sonnet) | **Work Period:** 2026-07-11, single session (13:06-13:55 execution)
> **Subject:** Execution of `2607110159-opencode-suite-port-plan.md` on ephemeral branch `projex/2607110159-opencode-suite-port` (worktree `.projexwt/2607110159-opencode-suite-port`, 6 commits, not yet merged/closed)
> **Related:** 2607110159-opencode-suite-port-plan.md | 2607110210-opencode-suite-port-plan-redteam.md | 2607110159-opencode-suite-port-log.md | 2607081900-codegraph-integration-audit.md

---

## Audit Summary

**Claim:** All 5 plan steps completed successfully; 5 of 8 acceptance criteria fully met, 1 partial (codegraph, pre-existing/out-of-scope blocker), remainder unaffected; 5 redteam findings (F2-F6) folded in as within-scope correctness fixes; F1 (permission) given a minimal warning-only fix; F7/F8 deliberately deferred; a plan assumption (opencode storage layout) was found wrong and corrected during execution.

**Verdict:** Partial

**Assessment:** Completeness: High (7/8 criteria fully met, 1 legitimately partial with real independent-build evidence) | Correctness: High (independently re-verified, not just re-read) | Quality: High (honest deviation logging, no scope creep, clean worktree) | Value: High (Alpine-correct re-derivation, not a naive port)

**Top Issues:**
1. Plan document's own Success Criteria checkboxes are all unchecked (`[ ]`) despite `Status: Complete` — cosmetic but a real self-audit gap (Minor, easy fix before close).
2. F1 (`permission` block) is warning-only with no enforcement path — `build.ps1 -Push` has no mechanism to detect or block on the warning prepare.ps1 printed; redteam's "No-Go If" condition is not tool-enforced (Significant residual risk, correctly flagged by the executor for human judgment).
3. Criterion 3 (codegraph always present) is genuinely unverifiable end-to-end because of a pre-existing, independently-reproduced base-image defect, not a defect in this plan's work — confirmed below, not just accepted on the executor's word.

---

## Claims vs Evidence

| Claim | Evidence | Status | Notes |
|-------|----------|--------|-------|
| Step 1: language toggles work, unknown rejected | `build.ps1` line 76 (`-Supported @('go','python')`), Dockerfile `ARG INSTALL_GO/PYTHON` block; live-ran `-Enable dotnet` under PS5.1 | ✓ | Reproduced independently: `Unknown language 'dotnet'. Supported: go, python.` |
| Step 2: agent-browser runs on musl Alpine via system Chromium | Dockerfile agent-browser block; log's build-time `--version` + real `navigate` claim | ✓ | **Independently re-built** an isolated Dockerfile reproducing the exact block (apk chromium/nodejs/npm/corepack/agent-browser) — `agent-browser --version` and `agent-browser navigate "data:text/html,..."` both succeeded on musl. Confirms the plan's single highest-risk assumption is genuinely resolved, not merely asserted. Image removed after test. |
| Step 2: skill stub adapted, not blind copy | Diffed `opencode/skills/agent-browser/SKILL.md` vs `claude/skills/agent-browser/SKILL.md` | ✓ | Only 2 lines differ (install-note reworded for baked-Chromium, added "opencode" to agent list) — a genuine, minimal, correct adaptation, not leftover Claude-specific framing. |
| Step 3: MCP rewrite covers every `command[]` element, not just [0] (redteam F2) | `prepare.ps1` lines 119-133, 162-176 | ✓ | Loop iterates `foreach ($el in $cmdArr)`, rewrites/checks every element; log's claimed "pathArg" fixture case (`["node","C:\\...\\index.js"]` → dropped) matches the code path. |
| Step 3: PS5.1 single-element array collapse defeated (F3) | `prepare.ps1` line 157 (`@($srv.command)` force-cast), line 173 (`[string[]]$newArr`), line 185 (output regex repairing collapsed single-element `command` back to array) | ✓ | Both the input-side collapse and the `ConvertTo-Json` output-side collapse (a subtler bug the redteam didn't even name) are handled. |
| Step 3: F1 permission handling | `prepare.ps1` lines 148-150 (warn-only, no strip) | ⚠ | Matches log's claim exactly. Functionally a warning, not a gate — see Findings. |
| Step 4: volumes namespaced `opencode-*` (F4), chowned (F5), corepack/pnpm baked (F6) | `run.ps1` lines 90-122; Dockerfile agent-browser block lines 58-60 | ✓ | All three redteam fixes present and consistent with each other (F6's corepack install is what makes F5's `.pnpm-store`/F4's namespaced volumes usable). |
| Step 4 deviation: opencode 1.17.14 uses single SQLite DB, not `storage/` dir | `run.ps1` lines 72-84, comments cite version 1.17.14 | ✓ (per log; not independently re-probed against a live opencode session, see Gaps) | Mount design (single-file bind-mount, not whole-dir) is internally consistent with the stated constraint ("never shadow baked config/auth-mount") and technically correct for SQLite WAL semantics (0-byte file = valid empty DB; `-wal`/`-shm` sidecars land in the container's own dir and checkpoint into the mounted `.db` on clean exit — accurately caveated in both code comment and README, not glossed over). |
| Codegraph blocked by pre-existing, out-of-scope Alpine defect, reproduces on `main` | `git show main:opencode/Dockerfile` (codegraph block byte-identical, untouched by this plan) | ✓ | **Independently rebuilt** `main`'s exact Dockerfile fragment (apk base tools + pinned codegraph install, nothing from this plan) in isolation — reproduced the identical failure: `exec: /opt/codegraph/versions/v1.3.0/node: not found`, exit 127. Confirms the blocker predates and is unrelated to this execution. |
| "Throwaway verify image built + removed, never committed" | `git status` (worktree clean), `docker images`/`docker volume ls` (no opencode/verifytmp artifacts, no `opencode-*` volumes) | ✓ | No leftover images, containers, or volumes from the executor's own verification runs. |
| Step 5: README reflects shipped behavior | `opencode/README.md` diff | ✓ | Toggle table, agent-browser section, run-state section, MCP-rewrite section, permission-warning note all present and match code; stale "no optional language features" claim removed. |
| Plan `Status: Complete` | `opencode/.projex/2607110159-opencode-suite-port-plan.md` line 3 vs Success Criteria checkboxes (lines 37-44) | ✗ | All 8 checkboxes still read `[ ]` — plan document itself was never updated to reflect which criteria passed/partial. Minor but a genuine gap: a reader of the plan alone (without the log) would see "Complete" next to an entirely unchecked list. |

---

## Objective Verification

### Objective: Language toggles (Step 1)
**Evidence:** `opencode/build.ps1`, `opencode/Dockerfile` (worktree, commit `b975845`)
**Findings:** Actual matches plan sketch closely; build-arg loop, validation, and error message all present and independently exercised.
**Verification:** ✓ Verified

### Objective: agent-browser on Alpine (Step 2)
**Evidence:** `opencode/Dockerfile` (commit `575bb8b`), `opencode/skills/agent-browser/SKILL.md`
**Findings:** Independently rebuilt in isolation — musl compatibility confirmed live, not taken on faith. Corepack/pnpm addition (F6) present and necessary for Step 4 to function.
**Verification:** ✓ Verified

### Objective: prepare.ps1 MCP rewrite (Step 3)
**Evidence:** `opencode/prepare.ps1` (commit `dab89ad`)
**Findings:** All three "Must Fix" redteam items (F1 partial/by design, F2, F3) traced to specific code lines; logic is sound on read (force-array-cast before the `-is [Array]`-style check is gone entirely — replaced with a strictly-safer always-array approach — and the output-side collapse repair is a detail beyond what the redteam even flagged).
**Verification:** ✓ Verified (code-read; not independently re-run under PS5.1 in this audit — see Gaps)

### Objective: run.ps1 persistent state (Step 4)
**Evidence:** `opencode/run.ps1` (commit `7c1001d`)
**Findings:** Deviation (SQLite single-file vs `storage/` dir) is well-reasoned and consistent with stated mount constraints; all three "Should Fix" redteam items (F4, F5, F6) present and mutually consistent. The log's own account of a second ownership gap found live (`~/.npm` also needed chowning, beyond the plan's `.pnpm-store`-only sketch) is corroborated by the code (`$pmSetup` chowns all three paths) — this is exactly the kind of self-correction an audit should reward, not just a claim to wave through.
**Verification:** ✓ Verified

### Objective: README (Step 5)
**Evidence:** `opencode/README.md` diff
**Verification:** ✓ Verified

---

## Gap Analysis

### Promised But Not Delivered
| Promise | Status | Impact |
|---------|--------|--------|
| Criterion 3: codegraph always present in a real build | Blocked (pre-existing, confirmed independent of this plan) | Medium — cannot demonstrate a full end-to-end `./build.ps1` + `./run.ps1` history-persistence cycle on the real image; every individual feature was verified on a substitute image instead |

### Undocumented Issues
None found beyond what the execution log itself already disclosed — notably the log's own "Deviations" and "Issues Encountered" sections are unusually forthcoming (they self-report a bug found mid-execution — the `~/.npm` chown gap — that nothing forced them to admit).

### Unhandled Edge Cases
- F1 (`permission` block): a template author who runs `-Push` without reading console output ships a permissive posture with only a warning as the guard — no hard fail, no `-Force`-style override needed to proceed. This is a real, if narrow, gap (see Findings).
- No test coverage retained in-repo for Step 3's 7-case fixture — verification happened live in the session and the fixtures were (correctly, per worktree-cleanliness) not committed, but there's also no lightweight `Pester`/smoke script left behind for a future regression check. Given repo convention (no existing test harness for these `.ps1` scripts), this matches existing practice rather than falling short of it.

---

## Quality Assessment

### Completeness: High
**Strengths:** All 5 steps executed, 5 of 6 redteam Must/Should-Fix items incorporated, deferred items (F7, F8) explicitly reasoned rather than silently dropped.
**Gaps:** Plan checkbox state not updated; criterion 3 partial.

### Correctness: High
**Works:** Independently reproduced 3 of the log's most load-bearing claims (dotnet rejection, agent-browser-on-musl, codegraph pre-existing failure) with fresh, isolated builds rather than trusting the log's prose.
**Bugs:** None found in the shipped code during this audit's inspection of `prepare.ps1`/`run.ps1`/`Dockerfile`/`build.ps1`.

### Code Quality: High
**Positive:** Comments consistently explain *why*, not just *what* (e.g., the SQLite WAL bind-mount caveat, the `ponytail:` comment on unpinned apk versions). Deviations are logged inline in code comments as well as in the execution log — redundant in a good way, not scope creep.
**Concerns:** F1's warning has no machine-checkable gate (see Findings).
**Tech Debt:** Low — F7 (no agent-browser toggle) and F8 (unpinned go/python) are named, reasoned, and match the redteam's own accepted remediation language ("document the drift" was the redteam's own fallback for F8).

### Value Delivered: High
**Intended:** Four Claude-suite capabilities re-derived (not transliterated) against opencode's actual Alpine/Bun/SQLite substrate.
**Actual:** Genuine re-derivation confirmed at the code level (skill-stub diff, SQLite-vs-storage/ correction, Alpine-native package choices) — this is qualitatively different from, and better than, a mechanical port.

---

## Open Findings

### Undocumented Discoveries
- None beyond the log's own self-reported `~/.npm` chown fix.

### Impact Analysis
- **Downstream:** `2607081900-codegraph-integration-audit.md` (an install-audit, not a bug tracker) does not yet have a companion issue for the Alpine `node: not found` defect this execution surfaced and confirmed pre-existing. The log recommends raising one; as of this audit, none exists yet.
- **Future:** A future codex/ or other suite port following this plan's process (steps drafted "independently" per the plan's own Overview, then cross-checked only at execute time) will hit the same class of gap the redteam's Finding 6 named — worth feeding back into the planning template, not just this execution.
- **Risks:** F1's warning-only gap is Low likelihood (requires an operator to both have a permissive `opencode.json` AND run `-Push` AND not read output) but non-zero and easy to close later (e.g., an explicit `-Force`/`-AcknowledgePermission` gate would cost little).

---

## Findings

### Critical (Must Address)
None. No finding in this audit rises to blocking severity for close.

### Significant (Should Address)
- **F1 permission handling is warning-only, unenforced at `-Push`** — `build.ps1`'s `-Push` path (lines 119-123) has zero awareness of prepare.ps1's warning; nothing stops a `-Push` immediately after a printed-and-scrolled-past warning. The redteam's own remediation offered "strip or warn" as alternatives, so this is a defensible interim choice, not a violation of the plan — but the redteam's explicit "No-Go If" condition (`-Push` before Finding 1 is fixed) is not tool-enforced, only human-observable. → Recommend logging as a tracked follow-up (e.g., a small patch: fail `-Push` when a staged `permission` block is present unless a new explicit flag is passed), not a blocker for closing this plan.
- **Plan document Success Criteria left unchecked despite `Status: Complete`** — cosmetic inconsistency a future reader would trip over. → Recommend close-projex update the checkboxes (7 met, 1 partial) as part of finalizing.

### Minor (Nice to Fix)
- No lightweight regression script retained for prepare.ps1's MCP-rewrite fixture set (matches existing repo convention of no `.ps1` test harness, so not a regression, just an opportunity).
- Codegraph follow-up projex (debug/patch) not yet created, though recommended by the execution log itself.

### Positive
- Independent re-verification (not just re-reading) confirmed the two highest-risk technical claims in the entire plan: agent-browser-on-musl and the codegraph pre-existing failure being genuinely independent of this plan's changes.
- The execution log is unusually honest: it self-reports a bug found mid-session (the `~/.npm` chown gap) that nothing in the plan or redteam named in advance, and explicitly flags two judgment calls (F1 minimal-touch, F7/F8 deferral) for human review rather than silently deciding and moving on.
- The skill-stub adaptation (Step 2) is a genuine, minimal, correct port — not a copy-paste with leftover Claude-specific framing (verified by direct diff against the source file).
- Worktree and Docker state left exactly as found — no stray images, volumes, or fixture files from the executor's own verification work.

---

## Recommendations

**Immediate (before close):** None blocking. Optionally have close-projex update the plan's Success Criteria checkboxes to reflect the true 7-met/1-partial state before merge, for document hygiene.

**Future:**
- Track the codegraph `node: not found` Alpine defect as its own debug/patch projex (the execution log already recommends this; not yet created).
- Consider a `-Push`-time hard gate (or at least a re-printed confirmation prompt) tied to the `permission`-block warning, closing the residual F1 gap.
- Consider an `INSTALL_AGENT_BROWSER` toggle (F7) and apk version pinning (F8) as low-priority future patches — both already reasoned and deferred deliberately, not omissions.

**Process:** Feed Finding 6's root cause (steps drafted independently, cross-checked only at execute time — already named in the redteam) into how future multi-step ports are drafted, per the redteam's own "at 100x" scale note.

---

## Final Verdict

**Status:** Accept with Conditions

**Overall Assessment:**
- Completeness: High
- Correctness: High
- Quality: High
- Value: High

**Conditions:**
- [ ] None required before close — the two Significant findings (F1 unenforced warning, unchecked plan checkboxes) are documentation/process follow-ups, not defects in the shipped code, and were already self-flagged by the executor for human review.

**Sign-off:** Yes — proceed to close-projex. The codegraph blocker is confirmed pre-existing and independent of this plan (verified via isolated rebuild of `main`'s untouched Dockerfile fragment); it should not hold up merging genuinely-complete, independently-verified work. Recommend close-projex note criterion 3 as "partial, pre-existing blocker" rather than silently marking it done, and carry forward the two Significant findings as tracked follow-ups.
