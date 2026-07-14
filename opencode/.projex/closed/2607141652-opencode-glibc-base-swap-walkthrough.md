# Walkthrough: Swap OpenCode base → glibc, install opencode at build time

> **Execution Date:** 2026-07-14
> **Completed By:** agent (opus) — orchestrated (execute → audit → patch → close)
> **Source Plan:** `2607140130-opencode-glibc-base-swap-plan.md`
> **Base Branch:** main | **Ephemeral:** `projex/2607140130-opencode-glibc-base-swap` (worktree mode)
> **Merge:** Squash → main | **Result:** Success (7/8 criteria fully met; #7 partial, base-inherent)
> **Related:** `2607140130-opencode-glibc-base-swap-log.md` · `2607142230-opencode-glibc-base-swap-audit.md` · `2607141745-opencode-glibc-base-swap-redteam.md` · `2607141648-opencode-run-cache-comment-patch.md`

---

## Summary

Rewrote `opencode/Dockerfile` off the third-party `ghcr.io/anomalyco/opencode` (Alpine/musl, binary-only, floating `:latest`) onto `debian:bookworm-slim` (glibc), installing the `opencode` CLI at build time via `npm i -g opencode-ai@<pinned>` — mirroring the claude/codex pattern (Debian glibc base + NodeSource Node 24 + tooling installed by RUN steps). glibc reverses every musl workaround the prior port (2607110159) carried: agent-browser and playwright get their standard `install --with-deps` flow, codegraph drops its `ln -sf` node symlink hack, and the prior port's unverifiable musl codegraph blocker (`exec: node: not found`, exit 127) is resolved — `codegraph index` now runs end-to-end. Docker build + runtime independently verified; audit verdict **Accept**, no critical/significant findings.

---

## Objectives Completion

| Objective | Status | Notes |
|-----------|--------|-------|
| glibc base + build-time opencode | Complete | `FROM debian:bookworm-slim`; `npm i -g opencode-ai@1.17.19`; `opencode --version` → 1.17.19 as `agent` |
| Reverse all musl workarounds | Complete | No `AGENT_BROWSER_EXECUTABLE_PATH`, `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD`, `apk`, or codegraph symlink survives (grep → 0 functional hits) |
| Resolve codegraph blocker | Complete (exceeds) | Plain `npm i -g`; `codegraph index` functional at runtime — the whole point reproduced independently |
| Purge stale docs/comments | Complete | SKILL.md / run.ps1 / README carry no stale Alpine/musl/EXEC_PATH claims; README floating-tag gap note removed |

---

## Execution Detail

> Documents what ACTUALLY happened, from git history (`main..HEAD`, 9 commits) and the execution log. Deviations called out explicitly.

### Step 0 (Pre-Execution): resolve pre-existing dirty tree

**Planned:** Discard/commit the dirty Alpine `M`-edits the plan anticipated on `opencode/` before branching.

**Actual:** No-op. `git diff --stat HEAD -- opencode/` on base was **clean** — the anticipated dirty edits were already superseded by committed patch `67026f2` (chown `/home/agent/.cache` parent). Only repo-wide dirty files were `claude/README.md`, `claude/run.ps1` (out of scope, untouched; worktree mode isolates them). Re-derived Step 3/4 text references against the committed baseline.

**Deviation:** Plan expected a dirty tree to clean; reality was already clean. No functional impact.

### Step 1: Dockerfile — swap base to glibc, install opencode at build time

**Planned:** Near-total Dockerfile rewrite onto `debian:bookworm-slim`.

**Actual:** `FROM debian:bookworm-slim` (Dockerfile:20). NodeSource Node 24; `useradd --uid 1000 agent` + NOPASSWD sudo; opencode/codegraph/agent-browser/playwright installed via pinned-ARG `npm i -g` (opencode-ai at :55); standard `agent-browser install --with-deps` (:82) + `playwright install --with-deps chromium` (:92); go-tarball + python-apt toggles under `INSTALL_GO`/`INSTALL_PYTHON`. Removed: `AGENT_BROWSER_EXECUTABLE_PATH`, `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD`, `apk add chromium`, codegraph `ln -sf … node` symlink.

**Deviation D1:** chowned the `/home/agent/.cache` **parent** (not just `.cache/ms-playwright`) so `opencode` runs as the `agent` user — required for Success Criterion 2. Baked agent-owned at build time.

**Files Changed:** `opencode/Dockerfile` — Modified — Yes — 167 lines (+/-), near-total rewrite.

**Verification:** Live build `opencode-custom:v1` / `opencode-custom:v1`; runtime `opencode --version` → 1.17.19, `node` v24.18.0, `pnpm` 11.13.0 (corepack), uid 1000, NOPASSWD_OK, `go1.26.3`, `codegraph index` functional.

### Step 2: agent-browser SKILL.md — drop the musl note

**Planned:** Remove the stale musl / system-Chromium line.

**Actual:** 1-line edit — dropped the `AGENT_BROWSER_EXECUTABLE_PATH` / system-Chromium note now that standard glibc Chrome-for-Testing flow applies.

**Files Changed:** `opencode/skills/agent-browser/SKILL.md` — Modified — Yes — 2 lines.

### Step 3: run.ps1 comments + build.ps1 stale-comment scan

**Planned:** Reword stale musl-framing comments in run.ps1; scan build.ps1.

**Actual:** Reworded the two volume-namespacing comments (was: "this Alpine/musl store never shares a volume with the claude template's Debian/glibc store"; "never shares the claude template's musl-vs-glibc volume") to justify the `opencode-` prefix by per-suite isolation / independent lifecycles — dropping the false musl-vs-glibc contrast. No functional logic touched. `build.ps1` scanned for Alpine/musl/apk → 0 matches, so no build.ps1 edit (a genuine no-op).

**Files Changed:** `opencode/run.ps1` — Modified — Yes — comment blocks only.

**Verification:** `grep -iE 'Alpine|musl' opencode/run.ps1` → 0; `grep -iE 'Alpine|musl|apk' opencode/build.ps1` → 0.

### Step 4: README.md — reflect the new base (+ D1 fix)

**Planned:** Update README's Alpine/musl claims; remove the floating-tag gap note.

**Actual:** Reworked base description to `debian:bookworm-slim` (glibc), removed the "floating tag" gap note (now pinned tooling), added an honest "Note on python" (interpreter always present via nodejs dep; toggle = pip3/venv dev-stack). D1's `.cache`-parent chown committed here alongside the README.

**Files Changed:** `opencode/README.md` — Modified — Yes — 72 lines (+/-).

### Audit + Patch (post-execution)

- **Audit** (`2607142230-...-audit.md`): independently rebuilt/ran the image. Verdict **Accept**. No critical/significant findings. Two minor doc-level items: run.ps1 stale `.cache` comment (patched) and criterion-7 wording (deferred to `revise`).
- **Patch** (`2607141648-...-patch.md`, born closed): corrected the `run.ps1` `.cache` comment (D1 build-time bake now noted; runtime chown documented as defensive for the volume-mounted leaf). Commits `34fdab6` + `b3233a6`.

---

## Complete Change Log

> Derived from `git diff --stat main..HEAD`. Code (4 files) + projex docs (4 files).

### Files Modified (code)
| File | Changes | Lines | In Plan? |
|------|---------|-------|----------|
| `opencode/Dockerfile` | Near-total rewrite: glibc base, build-time opencode/tooling, musl workarounds removed, D1 .cache chown | 167 | Yes |
| `opencode/README.md` | New base description, floating-tag gap removed, python note added | 72 | Yes |
| `opencode/run.ps1` | Volume-comment reword (drop musl framing) + D1 .cache comment correction (patch) | 35 | Yes |
| `opencode/skills/agent-browser/SKILL.md` | Drop stale musl/system-Chromium note | 2 | Yes |

### Files Created (projex, committed on ephemeral branch)
| File | Purpose | In Plan? |
|------|---------|----------|
| `...-log.md` | Execution log | Structural |
| `...-audit.md` | Audit (Accept) | Structural |
| `2607141648-...-run-cache-comment-patch.md` | Patch doc (born closed) | Structural |

### Planned But Not Changed
| File | Planned Change | Why Not Done |
|------|----------------|--------------|
| `opencode/build.ps1` | Possible stale musl comment | Scan → 0 matches; nothing to change (Step 0/3 confirmed) |

---

## Success Criteria Verification

Independently re-verified by the audit (`2607142230-...-audit.md` § Success Criteria Checklist) against the live image; summarized here.

| # | Criterion | Evidence | Result |
|---|-----------|----------|--------|
| 1 | Base `debian:bookworm-slim`, off anomalyco | Dockerfile:20; only anomalyco hit is a header comment | PASS |
| 2 | opencode via pinned `npm i -g opencode-ai`; `--version` succeeds | Dockerfile:55; runtime → 1.17.19 as agent | PASS |
| 3 | No musl workaround survives | grep → 0 functional matches | PASS |
| 4 | agent-browser + playwright standard glibc `--with-deps`; both `--version` | Dockerfile:82,92; runtime both pass | PASS |
| 5 | codegraph plain npm + `--version` (blocker resolved) | no symlink; `codegraph index` functional | PASS (exceeds) |
| 6 | Node 24 + pnpm-corepack; agent uid 1000 + NOPASSWD sudo | node v24.18.0; pnpm 11.13.0; uid 1000; NOPASSWD_OK | PASS |
| 7 | go/python toggles via INSTALL_*; default both on | go1.26.3 + python3 present; `-Disable python` cannot remove interpreter | PARTIAL — go met; python interpreter base-inherent (D2), toggle controls pip3/venv only |
| 8 | SKILL/run.ps1/README no stale Alpine/musl/EXEC_PATH; floating-tag gap removed | grep clean bar intentional historical refs | PASS |

**Overall: 7/8 fully met.** #7 partial = D2 (base-inherent, correctly deferred with rationale).

---

## Deviations from Plan

### D1 — chown `/home/agent/.cache` parent (not just `.cache/ms-playwright`)
- **Reason:** `opencode` must run as the `agent` user; the parent must be agent-owned. Baked agent-owned at build.
- **Impact:** Enables Success Criterion 2. Audit: VERIFIED, correctly applied.

### D2 — `-Disable python` cannot remove the python3 interpreter
- **Reason:** NodeSource `nodejs` on bookworm hard-depends on `python3` (`apt-cache depends nodejs` → `Depends: python3`), so the interpreter arrives transitively in the node layer regardless of `INSTALL_PYTHON`. This genuinely differs from the Alpine original (`apk add nodejs` pulled no python). `apt-get autoremove python3` would break nodejs — no viable code fix.
- **Impact:** Low. Toggle's real effect (pip3/python3-pip/python3-venv present only when enabled) is mechanically sound. README carries an honest "Note on python." Audit: VERIFIED (mechanism), correctly deferred as partially-met.

---

## Issues Encountered

None blocking. One minor stale comment (run.ps1 `.cache`) surfaced by the audit and resolved by the patch step. No rework, no reversed steps.

---

## Key Insights

### Lessons Learned
1. **glibc base dissolves an entire class of workarounds at once.** Every musl-specific hack (system-Chromium redirect, playwright download skip, codegraph node symlink) existed solely to route around musl's inability to exec glibc binaries. Swapping the base removed all four with no per-hack fix — the leverage was in the base choice, not the individual patches.
2. **A "remove X" criterion can be unsatisfiable on the new base.** Criterion 7 assumed `-Disable python` removes python3 (true on Alpine), but NodeSource nodejs hard-depends on python3 on Debian. When porting toggles across base images, re-check each package's transitive deps before promising absence.

### Pattern Discoveries
1. **Base-inherent transitive dependency.** A runtime (python3) arriving via another package's hard dependency (nodejs) rather than an explicit install — cannot be toggled off without breaking the depender. Document as "always present; toggle controls the dev-stack," not as removable.

### Gotchas / Pitfalls
1. **Directory ownership scope for non-root run.** Chowning only the leaf (`.cache/ms-playwright`) is insufficient when the process needs to write elsewhere under the parent — chown the parent `.cache` (D1).
2. **Stale comments outlive the code they describe.** The musl-framing volume comments and the `.cache` "nothing creates that directory" comment both survived the functional change; only a deliberate grep/scan caught them.

---

## Recommendations

### Immediate Follow-ups
- None blocking. Effort is complete and merged.

### Future Considerations
- **`/revise-projex.md` the plan's Criterion 7 wording** (doc-level, deferred here — the plan is now closing and this is not a code fix). Current text ("python3 absent" when `-Disable python` is set) is **not literally satisfiable** on `debian:bookworm-slim` + NodeSource Node 24, because `nodejs` hard-depends on `python3` transitively. Reword to: "python interpreter always present (nodejs dependency); `-Disable python` removes the pip3/python3-venv dev-stack only." This is a plan-document wording correction, best handled by a future revise pass — not by editing a now-closed plan's criterion in place.
- **Digest-pin `debian:bookworm-slim`** if full base reproducibility is later wanted. `bookworm-slim` is a rolling tag; the base still drifts at patch level between rebuilds (agent tooling is truly version-pinned via ARG; the base is not). This matches claude/codex's own tag-pinning convention — noted honestly, not a regression.

---

## Related Projex Updates

| Document | Action |
|----------|--------|
| `2607140130-...-plan.md` | Marked Complete; Completed date + walkthrough link added; moved to `closed/` |
| `2607140130-...-log.md` | Moved to `closed/` alongside plan |
| `2607142230-...-audit.md` | Verdict Accept, resolved by this completion; moved to `closed/` |
| `2607141745-...-redteam.md` | This effort's own red team (Subject = this plan); resolved by completion; moved to `closed/` |
| `2607141648-...-run-cache-comment-patch.md` | Born closed; already in `closed/` from the patch step |

**Left untouched (unrelated / different effort):** `2607110159-opencode-suite-port-plan.md` (already closed), `2607110210-opencode-suite-port-plan-redteam.md`, `2607111343-opencode-suite-port-audit.md`, `2607081900-codegraph-integration-audit.md`, `2607100834-language-build-feature-flags-audit.md` — the prior suite-port / cross-scope efforts; this plan's completion does not resolve them.

---

## Appendix

### Commits (ephemeral branch `main..HEAD`)
```
b3233a6 projex(patch): add patch doc - opencode-run-cache-comment
34fdab6 projex(patch): correct run.ps1 .cache comment for D1 build-time bake
8a2a4ec projex: audit - opencode-glibc-base-swap
4f6b982 projex: complete opencode-glibc-base-swap
4c84f2e projex: step 4 + D1 fix - README new base; chown .cache parent so opencode runs as agent
43c9c90 projex: step 3 - run.ps1 comments drop stale musl framing
31f78a4 projex: step 2 - agent-browser SKILL.md glibc note
4ad6efd projex: step 1 - Dockerfile base swap to debian:bookworm-slim (glibc)
48e4094 projex: step 0 - init log, opencode tree confirmed clean vs HEAD
```
(Squash-merged to `main` as one commit at close.)

### References
- Plan / log / audit / redteam / patch — see header.
- Audit verdict: **Accept** — no critical/significant findings; 2 minor doc items (1 patched, 1 deferred to revise).
