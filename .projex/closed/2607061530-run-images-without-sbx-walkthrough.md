# Walkthrough: Run baked images without sbx

> **Execution Date:** 2026-07-06
> **Completed By:** agent (execute-projex, worktree mode)
> **Source Plan:** `2607060236-run-images-without-sbx-plan.md`
> **Duration:** ~20 min (03:10-03:30)
> **Result:** Success (code/docs) — Runtime: Unverified (see Success Criteria Verification)

---

## Summary

Added `claude/run.ps1` and `codex/run.ps1` — thin `docker|podman run` wrappers that launch the baked `cc-custom`/`codex-custom` images without sbx, mounting cwd as `/workspace` and bind-mounting individual host credential files for OAuth persistence. Updated both READMEs' `## Run` sections to document the new path, retaining the sbx command as "Legacy." All 4 commits are clean, additive, single-file, byte-for-byte faithful to the patched plan — confirmed independently by both the audit and this closeout (`git diff --stat main..projex/2607060236-run-images-without-sbx`: 4 files, 165 insertions, 0 deletions). No live-container verification was performed (no correctly-tagged image locally, no podman on PATH, can't do interactive OAuth as an agent) — this is a real, disclosed gap, not a defect.

---

## Objectives Completion

| Objective | Status | Notes |
|-----------|--------|-------|
| `claude/run.ps1` — workspace mount + OAuth/session persistence + interactive `claude` launch | Complete (code) | Verbatim vs plan Step 1; commit `80420c8` |
| `codex/run.ps1` — same shape, `~/.codex/auth.json` persistence + interactive `codex` launch | Complete (code) | Verbatim vs plan Step 2; commit `1af557c` |
| `claude/README.md` `## Run` — document no-sbx path | Complete | Commit `2cf6e7e` |
| `codex/README.md` `## Run` — document no-sbx path | Complete | Commit `8b3f4bd` |
| Live runtime behavior (workspace mount, persistence, no-shadow, docker/podman parity) | **Not Verified** | No correctly-tagged image / podman available in execution environment; requires human with live container |

---

## Execution Detail

### Step 1: `claude/run.ps1`

**Planned:** CmdletBinding param block (`$Image`, `$Engine='docker'`, `$Workspace`), engine PATH check, BOM-less pre-create of `~/.claude.json` + `~/.claude-docker/.credentials.json`, workspace + individual-file mounts, conditional `--userns=keep-id` for podman, explicit `claude` command.

**Actual:** Created verbatim from plan Step 1. Parse-check (`-Engine __nope__`) threw `__nope__ not found on PATH` at line 27, exit 1 — confirms the file parses under PS5.1 and validation fires.

**Deviation:** None.

**Files Changed (ACTUAL):**
| File | Change Type | Planned? | Details |
|------|-------------|----------|---------|
| `claude/run.ps1` | Created | Yes | 58 lines; security header, BOM-less `WriteAllText`, individual-file mounts, conditional podman flag |

**Verification:** Static parse-check only (PASS). Live behavior (workspace mount, persistence, no-shadow) not run.

**Issues:** None.

---

### Step 2: `codex/run.ps1`

**Planned:** Same shape as Step 1, `~/.codex-docker/auth.json` single-file mount, interactive `codex` command.

**Actual:** Created verbatim from plan Step 2. Parse-check threw `__nope__ not found on PATH` at line 26, exit 1.

**Deviation:** None.

**Files Changed (ACTUAL):**
| File | Change Type | Planned? | Details |
|------|-------------|----------|---------|
| `codex/run.ps1` | Created | Yes | 54 lines; security header, BOM-less `WriteAllText`, single auth-file mount, conditional podman flag |

**Verification:** Static parse-check only (PASS). Live behavior not run.

**Issues:** None.

---

### Step 3: `claude/README.md` `## Run`

**Planned:** Replace sbx-only `## Run` block with `run.ps1` usage, first-run `/login` note, security note, `$PROFILE` `ccrun` alias, legacy sbx path retained.

**Actual:** Matches plan exactly. `git show 2cf6e7e` — additive-only diff, sbx command retained under "Legacy sbx path."

**Deviation:** None.

**Files Changed (ACTUAL):**
| File | Change Type | Planned? | Details |
|------|-------------|----------|---------|
| `claude/README.md` | Modified | Yes | +27 lines in `## Run` section |

**Verification:** `git diff` confirmed only `## Run` section changed.

**Issues:** None.

---

### Step 4: `codex/README.md` `## Run`

**Planned:** Same pattern for codex — `run.ps1` usage, auth note, security note, `$PROFILE` `codexrun` alias, legacy sbx retained.

**Actual:** Matches plan exactly. `git show 8b3f4bd` — additive-only, sbx retained under "Legacy."

**Deviation:** None.

**Files Changed (ACTUAL):**
| File | Change Type | Planned? | Details |
|------|-------------|----------|---------|
| `codex/README.md` | Modified | Yes | +26 lines in `## Run` section |

**Verification:** `git diff --stat` confirmed only `codex/README.md` changed.

**Issues:** None.

---

## Complete Change Log

> **Derived from:** `git diff --stat main..projex/2607060236-run-images-without-sbx` — 4 files changed, 165 insertions(+), 0 deletions. Commits: `80420c8`, `1af557c`, `2cf6e7e`, `8b3f4bd`.

### Files Created
| File | Purpose | Lines | In Plan? |
|------|---------|-------|----------|
| `claude/run.ps1` | No-sbx launcher for cc-custom | 58 | Yes |
| `codex/run.ps1` | No-sbx launcher for codex-custom | 54 | Yes |

### Files Modified
| File | Changes | Lines Affected | In Plan? |
|------|---------|----------------|----------|
| `claude/README.md` | `## Run` replaced: run.ps1 path primary, sbx legacy retained | +27 | Yes |
| `codex/README.md` | `## Run` replaced: run.ps1 path primary, sbx legacy retained | +26 | Yes |

### Files Deleted
None.

### Planned But Not Changed
None — all 4 planned files were changed exactly as scoped. Out-of-scope files (`Dockerfile`, `prepare.ps1`, `build.ps1`, `retag-tar.ps1`) confirmed untouched via `git diff --stat` against those paths (empty).

---

## Success Criteria Verification

> Per the audit's Condition 1 (Significant finding): the plan's `Status: Complete` header conflicted with all 6 unchecked Success Criteria checkboxes and zero live-container testing. Per audit/closeout agreement, each criterion below is marked **Not Verified** rather than PASS/FAIL — none were actually exercised against a running container. Marking any as PASS without evidence would repeat the exact overclaim the audit flagged.

### Criterion 1: `run.ps1` mounts arbitrary project dir as `/workspace`, workdir `/workspace`

**Verification Method:** Requires live container run (`mkdir demo; cd demo; run.ps1 -Engine docker`).
**Evidence:** None captured — no correctly-tagged image locally (store has `sbx-cc-custom:v1`, not `cc-custom:v1`/`codex-custom:v1`).
**Result:** Not Verified — requires live image, deferred to first real use.

### Criterion 2: `claude`/`codex` launches interactively against mounted workspace

**Verification Method:** Requires live container run + TTY.
**Evidence:** None captured.
**Result:** Not Verified — requires live image, deferred to first real use.

### Criterion 3: Agent-created file in `/workspace` appears on host (bind-mount agent-writable, A2)

**Verification Method:** Requires live container run.
**Evidence:** None captured.
**Result:** Not Verified — requires live image, deferred to first real use.

### Criterion 4: Login in run #1 persists into run #2 without re-auth (A1)

**Verification Method:** Requires two consecutive live container runs + interactive OAuth.
**Evidence:** None captured — agent cannot perform interactive OAuth login.
**Result:** Not Verified — requires live image, deferred to first real use.

### Criterion 5: Baked skills/agents/tools/settings remain visible (no `~/.claude`/`~/.codex` shadowing)

**Verification Method:** Requires live container run, inspect `~/.claude/skills` or `~/.codex/config.toml` in-container.
**Evidence:** None captured. Static code review confirms only individual files are mounted (not whole dirs), which by construction should avoid shadowing — but this is a structural inference, not an observed result.
**Result:** Not Verified — requires live image, deferred to first real use.

### Criterion 6: `-Engine docker` and `-Engine podman` both work

**Verification Method:** Requires live container run under both engines.
**Evidence:** Docker present on PATH in execution environment; podman absent. Neither exercised end-to-end.
**Result:** Not Verified — requires live image, deferred to first real use.

### Acceptance Criteria Summary

| Criterion | Method | Result | Evidence |
|-----------|--------|--------|----------|
| cwd mounted as workspace | Live run | Not Verified | Deferred — no image locally |
| Agent interactive in workspace | Live run | Not Verified | Deferred — no image locally |
| Workspace writable | Live run | Not Verified | Deferred — no image locally |
| Login persists | Two live runs | Not Verified | Deferred — no image locally, no OAuth as agent |
| Baked content intact | Live run | Not Verified | Deferred — no image locally |
| `-Engine` both work | Live run (docker + podman) | Not Verified | Docker present, podman absent from PATH |

**Overall:** 0/6 criteria verified live. 2/2 automatable checks (PS5.1 parse-check on both scripts) passed. Code/doc fidelity to spec: verified byte-for-byte by both the audit and this closeout.

---

## Deviations from Plan

None. Execution log and audit both confirm scripts/READMEs were written verbatim per plan Steps 1-4, with all 5 redteam-driven patch fixes present in the actual artifacts (security comments, BOM-less writes, conditional `--userns=keep-id`, profile-alias snippets, one-at-a-time verification callout).

---

## Issues Encountered

### Issue 1: Local image store mismatch — cannot live-verify

- **Description:** Local docker store contains `sbx-cc-custom:v1`, not the plan's `cc-custom:v1`/`codex-custom:v1`. Podman not on PATH. Agent cannot perform interactive OAuth login.
- **Severity:** Medium (blocks the plan's core value proposition from being confirmed, though code is complete)
- **Resolution:** Deferred to human — see Recommendations below.
- **Time Impact:** None to this execution; adds a follow-up task.
- **Prevention:** N/A — this is inherent to agent-driven execution of interactive/OAuth-gated tooling; not something the plan could have avoided.

### Issue 2: Plan `Status: Complete` header vs 6 unchecked Success Criteria (audit Significant finding)

- **Description:** Plan header said `Status: Complete` while all 6 Success Criteria checkboxes remained `- [ ]` and zero live verification had occurred — a genuine claim/evidence mismatch at the document level (log itself was honest).
- **Severity:** Medium (documentation-honesty issue, not a code defect)
- **Resolution:** Reconciled during this close: plan status updated to `Complete (code delivered and verified byte-for-byte against spec) — Runtime: Unverified (no live container test performed)`; Success Criteria left unchecked with a note pointing to this walkthrough's verification table (all 6 explicitly marked "Not Verified — requires live image, deferred to first real use").
- **Time Impact:** None — resolved as part of standard close.
- **Prevention:** Future plans for personal/interactive tooling should consider a two-part status convention ("artifacts complete" vs "criteria verified") from the start, per audit's Process recommendation.

---

## Key Insights

### Lessons Learned

1. **Two-part status for agent-executed, human-verified plans**
   - Context: This plan's runtime behavior requires an interactive OAuth login and a specific pre-built image — neither achievable by an executing agent.
   - Insight: A single `Status: Complete` field can't represent "code done, runtime pending" — it collapses two independent facts into one, and readers default to assuming the stronger claim.
   - Application: For any plan whose acceptance criteria require live human interaction (auth flows, physical hardware, GUI-only steps), state a two-part status explicitly from the plan-drafting stage, not just at close.

2. **Audits catch status-field drift even when logs are honest**
   - Context: The execution log here was exemplary — it explicitly separated "automated, passed" from "requires human, not automatable." Yet the plan header still overclaimed.
   - Insight: Honesty at the log level doesn't automatically propagate to the plan's machine-readable status field; these need independent reconciliation.
   - Application: Close-projex should always check the plan's status/checkbox state against the log's actual verification claims, not just against "did commits land."

### Pattern Discoveries

1. **Individual-file bind-mounts to avoid directory shadowing**
   - Observed in: `claude/run.ps1`, `codex/run.ps1`
   - Description: Mounting single host files (`.claude.json`, `.credentials.json`, `auth.json`) instead of whole `~/.claude`/`~/.codex` directories preserves baked image content (skills, agents, config) while still persisting host-side state.
   - Reuse potential: Any Dockerized dev-tool wrapper that bakes config into the image but needs selective host persistence.

### Gotchas / Pitfalls

1. **PS5.1 `Set-Content -Encoding utf8` BOM prefix**
   - Trap: Default PS5.1 UTF-8 encoding prepends a BOM, which can break strict JSON parsers reading a freshly pre-created `{}` file.
   - How encountered: Flagged by redteam before execution, fixed via patch; confirmed present as `[System.IO.File]::WriteAllText(..., UTF8Encoding($false))` in both scripts by this audit/closeout.
   - Avoidance: Always use `UTF8Encoding($false)` + `WriteAllText` for BOM-less writes in PS5.1, not `Set-Content -Encoding utf8`.

2. **Docker bind-mount source auto-creation as directory**
   - Trap: If the bind-mount source path doesn't exist, Docker/podman create a directory there instead of a file, breaking file-mount semantics.
   - How encountered: Pre-empted in the plan (A5) — scripts pre-create empty files before invoking `docker run`.
   - Avoidance: Always pre-create host-side bind-mount targets as files when mounting to a file path in the container.

### Technical Insights

- `.projex/` is gitignored in this repo (`.gitignore:10`) — active development notes intentionally never committed. This means plan/log/walkthrough files can be moved and edited on disk per convention but cannot be staged or committed; only the actual code/doc deliverables (`claude/run.ps1`, `codex/run.ps1`, both READMEs) land in git history.
- Worktree-mode execution isolated all changes cleanly — the 3 pre-existing dirty files on `main` (`claude/prepare.ps1`, `codex/prepare.ps1`, `claude/sbx-cc-custom`) were never touched throughout eval → plan → redteam → patch → execute → audit → close.

---

## Recommendations

### Immediate Follow-ups
- [ ] Once a correctly-tagged `cc-custom:v1`/`codex-custom:v1` image exists locally, run the plan's Verification Plan manual checks **one at a time** (per the redteam's own No-Go-If condition): A1 (creds-file-vs-keychain persistence), A2 (cwd-writability), A3 (codex-auth-path) — in that order, not batch-executed, since `--rm` discards container state on exit and a compound failure across multiple unverified assumptions is hard to diagnose blind.
- [ ] After manual verification, update the plan's Success Criteria checkboxes (or record results in a follow-up log/patch) to reflect actual PASS/FAIL rather than leaving them permanently unchecked.

### Future Considerations
- Optional non-interactive smoke test (e.g., `docker run --rm <image> claude --version`) could catch a subset of failures (wrong tag, broken entrypoint) without needing OAuth — audit flagged this as optional, weigh against YAGNI for single-user personal tooling before adding.
- If podman becomes available, exercise the `--userns=keep-id` path at least once — currently code-reviewed-correct but never run against a live podman-rootless container.

### Plan Improvements
If this plan were executed again:
- Draft the plan's `Status` field convention up front as two-part (artifacts vs. verification) when acceptance criteria require live human/interactive steps an agent cannot perform.

---

## Related Projex Updates

### Documents to Update
| Document | Update Needed |
|----------|---------------|
| `2607060236-run-images-without-sbx-plan.md` | Status reconciled to `Complete (code) — Runtime: Unverified`; moved to `.projex/closed/`; linked to this walkthrough |

### New Projex Suggested
| Type | Description |
|------|-------------|
| Patch or Log | Once live verification is performed (image exists, human runs A1/A2/A3 checks), record results — either a small patch updating the plan's checkboxes, or a log-projex documenting the live-run outcome |

---

## Appendix

### Execution Log
Full log at `.projex/2607060236-run-images-without-sbx-log.md` inside worktree `.projexwt/2607060236-run-images-without-sbx` (gitignored; not in git history — this walkthrough is the durable record of its content).

### References
- Plan: `2607060236-run-images-without-sbx-plan.md`
- Eval: `2607060232-run-images-without-sbx-eval.md`
- Red Team: `2607060240-run-images-without-sbx-redteam.md`
- Patch: `2607060700-run-images-redteam-fixes-patch.md`
- Audit: `2607061500-run-images-without-sbx-audit.md`
- Commits: `80420c8`, `1af557c`, `2cf6e7e`, `8b3f4bd` on `projex/2607060236-run-images-without-sbx` (base `main`)

### Repo Bookkeeping Note
`.projex/` is gitignored in this repo — the standard close-projex commit step for walkthrough/plan-move paths is **not stageable** here (git reports them ignored). Per repo convention, file moves and edits are still performed on disk (this walkthrough, and the plan's move to `.projex/closed/`), but no separate "add walkthrough" commit is made. The only git-committed artifact from this close is the branch-finalization squash-merge commit itself, which carries the 4 already-committed code/doc changes. This is expected repo behavior, not a missed workflow step.
