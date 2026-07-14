# Audit: OpenCode glibc base swap — execution of 2607140130-opencode-glibc-base-swap-plan.md

> **Audit Date:** 2026-07-14 | **Auditor:** agent (opus, projex auditor subagent) | **Work Period:** 2026-07-14 20:30–21:20
> **Subject:** Execution of `2607140130-opencode-glibc-base-swap-plan.md` (log: `2607140130-opencode-glibc-base-swap-log.md`)
> **Method:** Independent inspection of worktree artifacts + live `docker run` against the left-behind `opencode-custom:v1` (id `50eb0320c3bf`, 3.69 GB, built ~5 min before audit). No rebuild — every claim was verifiable against the existing image + source. All verification containers `--rm`.

---

## Audit Summary

**Claim:** Swap `opencode/Dockerfile` base `ghcr.io/anomalyco/opencode` (Alpine/musl) → `debian:bookworm-slim` (glibc); install opencode at build time via npm; drop all musl workarounds; standard glibc agent-browser/playwright/codegraph; toggles preserved; docs updated. Build + runtime verified end-to-end.

**Verdict:** Verified (with one documented base-inherent partial + one Minor stale comment).

**Assessment:** Completeness: High | Correctness: High | Quality: High | Value: High

**Top Issues:**
1. **run.ps1 stale comment** (Minor, doc-accuracy) — lines 99–100 assert "nothing creates that directory at build time" about `/home/agent/.cache`, but D1's fix means playwright now bakes+chowns `.cache` at build time. Self-flagged by execute; confirmed stale. Operative chown still correct (harmless no-op). Candidate for optional `[patch]`.
2. **Acceptance criterion 7 (python) partial** (D2) — `-Disable python` cannot remove the `python3` interpreter (NodeSource `nodejs` hard-depends on it). Base-inherent, not a defect; correctly deferred with rationale. Plan criterion wording is now stale (candidate for `revise`, not `patch`).
3. No third issue — no critical/significant findings.

---

## Claims vs Evidence

| Claim | Evidence (independently re-run) | Status | Notes |
|-------|--------------------------------|--------|-------|
| Full build on `debian:bookworm-slim`, both browser layers reached | `docker history` shows agent-browser layer (668 MB, `apt-get update && agent-browser install --with-deps`) + playwright layer (898 MB, `playwright install --with-deps chromium`); base present as `debian:bookworm-slim` id `cae69e86e0b0` | ✓ | Both browser layers materially present with expected sizes |
| In-build versions (opencode 1.17.19, codegraph 1.3.0, agent-browser 0.31.1, playwright 1.61.1, Node 24, go1.26.3, python 3.11.2) | Runtime `docker run`: opencode `1.17.19`, node `v24.18.0`, `go1.26.3`, Python `3.11.2`, agent-browser `0.31.1`, playwright `Version 1.61.1`; pnpm `11.13.0` | ✓ | All match exactly |
| agent uid 1000, NOPASSWD sudo | `id agent` → `uid=1000(agent) gid=1000(agent)`; `sudo -n true` → `NOPASSWD_OK`; default `whoami` → `agent` | ✓ | |
| pnpm via corepack; tini entrypoint | `pnpm --version` → 11.13.0 (corepack fetch); `tini` at `/usr/bin/tini` | ✓ | |
| **codegraph functional (native better-sqlite3 on glibc)** | Re-ran `codegraph init && codegraph index .` on throwaway git repo → `Indexed 1 files`, `2 nodes, 1 edges`, `CODEGRAPH_OK`, exit 0, no native-module error | ✓ | The plan's core objective (prior port's `node: not found` blocker) — RESOLVED |
| **D1 chown fix** (`.cache` parent, not just `ms-playwright`) | Dockerfile:93 `chown -R agent:agent /home/agent/.cache`; `opencode --version` prints `1.17.19` as `agent` (no EACCES) | ✓ | Correctly scoped; opencode runs as agent |
| **D2** (`-Disable python` can't remove interpreter) | `apt-cache depends nodejs` → `Depends: python3` (hard dep confirmed in-image) | ✓ (mechanism) | nopy image not rebuilt; pip3-absent-when-disabled rests on Dockerfile source (mechanically sound — pip3/venv only inside `INSTALL_PYTHON` block) |
| No musl relics survive | `grep -RniE 'anomalyco\|AGENT_BROWSER_EXECUTABLE_PATH\|PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD\|apk \|ln -sf.*codegraph'` on Dockerfile → only line 2 header comment (historical, intentional) | ✓ | No functional relic |
| Docs updated, no stale current-state claims | grep README/SKILL/run.ps1 → SKILL + run.ps1 clean of target terms; README 3 hits all intentional (historical "prior Alpine base" past-tense + honest "off unaudited `:latest`" caveat) | ✓ | |

---

## Objective Verification

### Objective: glibc base + build-time opencode, reverse all musl workarounds, resolve codegraph blocker

**Evidence:** `opencode/Dockerfile` (worktree), live `opencode-custom:v1`.

**Findings:**
- Actual: `FROM debian:bookworm-slim`; opencode/codegraph/agent-browser/playwright installed via `npm i -g` pinned ARGs in one layer; NodeSource Node 24; `useradd --uid 1000 agent` + NOPASSWD sudo; standard `agent-browser install --with-deps` + `playwright install --with-deps chromium`; go-tarball + python-apt toggles; no `AGENT_BROWSER_EXECUTABLE_PATH`, no `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD`, no apk, no codegraph symlink hack.
- Missing: nothing material.
- Quality: High. Dockerfile is coherent, well-commented, layer ordering sound (F1 apt-list refresh before agent-browser confirmed present at line 81).

**Verification:** ✓ Verified — the whole point (codegraph native addon loading on glibc) reproduced independently.

---

## Success Criteria Checklist (independently verified)

| # | Criterion | Evidence | Result |
|---|-----------|----------|--------|
| 1 | Base = `debian:bookworm-slim`, off anomalyco `FROM` | Dockerfile:20 `FROM debian:bookworm-slim`; only anomalyco hit is header comment | ✓ Met |
| 2 | opencode via `npm i -g opencode-ai@${OPENCODE_VERSION}`; `--version` succeeds | Dockerfile:55; runtime `opencode --version` → 1.17.19 as agent | ✓ Met |
| 3 | No musl workaround survives | grep → 0 functional matches | ✓ Met |
| 4 | agent-browser + playwright standard glibc `--with-deps`; both `--version` | Dockerfile:82,92; history layers present; runtime `--version` both pass | ✓ Met |
| 5 | codegraph plain npm + `codegraph --version` succeeds (blocker resolved) | plain `npm i -g` (no symlink); `codegraph index` functional | ✓ Met (exceeds — real index run) |
| 6 | Node 24 + pnpm-corepack; agent uid 1000 + NOPASSWD sudo | node v24.18.0; pnpm 11.13.0; uid 1000; NOPASSWD_OK | ✓ Met |
| 7 | go/python toggles via INSTALL_*; default both on | go1.26.3 + python3 present by default; `-Enable dotnet` rejected (per log); **python interpreter not removable by `-Disable python`** | ⚠ Partial — go Met; python interpreter base-inherent (D2), toggle controls pip3/venv only |
| 8 | SKILL/run.ps1/README no stale Alpine/musl/EXEC_PATH; floating-tag gap removed | grep clean bar intentional historical refs | ✓ Met |

**7 of 8 fully met; #7 partial = D2 (base-inherent, correctly deferred).**

---

## Deviation Verification

### D1 — chown `/home/agent/.cache` parent — VERIFIED, correctly applied
Dockerfile:92–93 `RUN HOME=/home/agent playwright install --with-deps chromium && chown -R agent:agent /home/agent/.cache`. Scope is the whole `.cache` parent (not just `ms-playwright`), exactly matching the deviation. Live proof the regression is fixed: `opencode --version` prints as the `agent` user with no EACCES. Root cause (playwright creates `.cache` as root under `HOME` override) is real and the fix is minimal + in-scope. **Sound.**

### D2 — `-Disable python` cannot remove python3 interpreter — VERIFIED (mechanism), correctly deferred
Independently confirmed in-image: `apt-cache depends nodejs` → `Depends: python3`. NodeSource `nodejs` on bookworm hard-depends on `python3`, so the interpreter arrives transitively in the node layer regardless of `INSTALL_PYTHON`. This genuinely differs from the Alpine original (`apk add nodejs` pulled no python). Not a Dockerfile defect (faithful to plan); `apt-get autoremove` on python3 would break nodejs, so no code fix is viable. Toggle's real effect (pip3/python3-pip/python3-venv present only when enabled) is mechanically sound — pip3 confirmed at `/usr/bin/pip3` in the default image; absence-when-disabled rests on the Dockerfile placing those pkgs solely inside the `INSTALL_PYTHON` block (not independently rebuilt — a full nopy rebuild was not warranted for a source-evident sub-claim). **Correctly classified as partially-met with rationale.** Recommend a `revise` to reword criterion 7 (interpreter always present; toggle = dev-stack on/off).

### Flagged item — run.ps1 stale comment — CONFIRMED stale (Minor)
run.ps1:99–100: `"/home/agent/.cache itself is also chowned: nothing creates that directory at build time..."`. Post-D1 this is false — Dockerfile:92–93 creates and chowns `.cache` at build time. The operative code (`$pmSetup` chown at line 109) remains correct: a Docker volume mounted at `.cache/opencode` (run.ps1:135) can still surface a root-owned leaf at container start, so the runtime chown stays useful; the parent-`.cache` chown is now a harmless no-op. Only the *comment's stated premise* is stale. **Minor, doc-accuracy.**

---

## Log Completeness & Artifact Forensics

- **Every plan step logged with timestamp:** Step 0 (20:30), Step 1 (20:35), Step 2 (20:40), Step 3 (20:45), Step 4 (21:05), COMPLETE (21:20). ✓
- **Commits referenced exist on ephemeral branch** `projex/2607140130-opencode-glibc-base-swap`: `64ef933` start, `48e4094` step0, `4ad6efd` step1, `31f78a4` step2, `43c9c90` step3, `4c84f2e` step4+D1, `4f6b982` complete. All present in `git log`. ✓
- **Diff scope vs main:** 6 files — `Dockerfile` (167±), `README.md` (72±), `run.ps1` (10±), `skills/agent-browser/SKILL.md` (2±), plus log.md (new) + plan.md status line (3±). No scope creep, no unexpected files. Plan.md change is the status→Complete update (expected of execute). ✓
- **Plan status:** reads `Complete` (plan:3). ✓
- **Cleanup:** `opencode-custom:nopy` removed (per log); no dangling verification containers — the only two running containers (`friendly_wozniak` on old `opencode-custom:v1` id `c1a1a7fc`, `vigorous_goldwasser` on `cc-custom:v1`) are the user's own pre-existing sandboxes (started 2 h / 15 h ago, predating this build), not execution leftovers. The old `opencode-custom:v1` layer is now untagged but pinned by the user's running container — not this execution's concern. ✓
- **Image size:** 3.69 GB (3,686,191,677 B). Largest layers: base tooling 1.78 GB, playwright browser 898 MB, agent-browser 668 MB, go 232 MB, python 28 MB. Within the plan's explicitly-accepted size-growth expectation (two full browsers vs Alpine's single system chromium). ✓

---

## Gap Analysis

### Promised But Not Delivered
| Promise | Status | Impact |
|---------|--------|--------|
| `-Disable python` → python3 absent | Partial (interpreter present; dev-stack removable) | Low — base-inherent, documented (D2), README carries honest "Note on python" |

### Undocumented Issues
None discovered beyond what execute self-reported.

### Unhandled Edge Cases
- nopy image's pip3-absence not independently rebuilt — Impact: Low (Dockerfile source is unambiguous; toggle branch installs pip/venv only under `INSTALL_PYTHON=1`).

---

## Findings

### Critical (Must Address)
- None.

### Significant (Should Address)
- None.

### Minor (Nice to Fix)
- **run.ps1:99–100 stale comment** ("nothing creates that directory at build time") — now contradicted by D1's build-time `.cache` bake. Reword to note `.cache` is baked agent-owned at build (D1) and the runtime chown is defensive for the volume-mounted leaf. Optional `[patch]`.
- **Plan criterion 7 wording** — "python3 absent" is unsatisfiable on this base. `revise` the plan/acceptance table to "python interpreter always present (nodejs dep); `-Disable python` removes pip3/venv dev-stack." Doc-level, not code.

### Positive
- codegraph blocker (the entire reason for the swap) not just claimed but reproduced end-to-end with a real index.
- D1 caught a genuine EACCES regression the base swap introduced and fixed it minimally, in-scope, with an explanatory Dockerfile comment.
- Honest self-reporting: both deviations, the stale comment, and the codegraph `init`-before-`index` command gap were all surfaced by execute, not hidden — audit confirmed each rather than discovering them.
- Clean relic sweep; no scope creep; cleanup disciplined.

---

## Final Verdict

**Status:** Accept

**Overall Assessment:**
- Completeness: High
- Correctness: High
- Quality: High
- Value: High

**Conditions:** None blocking. Two optional, non-blocking follow-ups:
- [ ] (Optional `[patch]`) Reword run.ps1:99–100 stale `.cache` comment.
- [ ] (Optional `revise`) Reword plan acceptance criterion 7 to match D2 reality.

**Sign-off:** Yes — core objective (glibc base, build-time opencode, codegraph native path resolved, all musl workarounds gone) delivered and independently verified against the live image. The sole partial (python interpreter) is a correctly-documented base-inherent limitation, not a defect. Safe to `close`.

---

> **Related:** `2607140130-opencode-glibc-base-swap-plan.md` | `2607140130-opencode-glibc-base-swap-log.md` | `2607141745-opencode-glibc-base-swap-redteam.md` | `2607111343-opencode-suite-port-audit.md` | `2607081900-codegraph-integration-audit.md`
