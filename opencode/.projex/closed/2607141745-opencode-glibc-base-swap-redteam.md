# Red Team: OpenCode glibc base swap (debian:bookworm-slim + build-time opencode)

> **Created:** 2026-07-14 | **Lead:** agent (opus, redteam)
> **Subject:** 2607140130-opencode-glibc-base-swap-plan.md | **Related:** 2607110159-opencode-suite-port-plan.md · 2607110210-opencode-suite-port-plan-redteam.md · 2607111343-opencode-suite-port-audit.md · 2607081900-codegraph-integration-audit.md

---

## Bottom Line

**Verdict:** Fix Issues

Core technical thesis is **sound and independently verified**: `opencode-ai@1.17.19` publishes a glibc `opencode-linux-x64` optional dep (npm resolves it natively on Debian x64); NodeSource Node 24 ships corepack (proven — claude/codex do bare `corepack enable`, no `npm i -g corepack`); `debian:bookworm-slim` leaves uid 1000 free; `prepare.ps1` genuinely is base-agnostic **and** its MCP Win→Linux rewrite claim is accurate (not a hand-wave). The swap really does dissolve the musl codegraph blocker. But two concrete pre-execution issues remain, one of them the plan's own self-declared #1 risk that it under-analyzed.

**Top Vulnerabilities:**
1. **F1 — apt lists purged before `--with-deps` on a *slim* base.** `agent-browser install --with-deps` runs first, after layer 1 deleted `/var/lib/apt/lists/*`, on a base that genuinely lacks Chromium libs. The reference images survive only because their *full* base pre-ships those libs. The plan's stated fallback ("pre-apt the lib set") also omits `apt-get update` and would fail identically. Build-blocker.
2. **F2 — Worktree-from-HEAD vs. 51+/40− uncommitted working-tree edits.** Steps 3/4 reference dirty-tree line numbers/text; worktree execution branches from clean HEAD. The M-edits are an *unrelated* in-flight Alpine change that this rewrite obsoletes, and get stranded as nonsensical diffs post-merge. Plan claims "worktree handles this cleanly" — it does not.
3. **F3 — "no more floating tag" is half-true.** `debian:bookworm-slim` is itself a rolling tag; the swap trades `:latest` for another non-digest-pinned tag. Reproducibility gap the plan's framing papers over.

---

## Stakeholder Roles

| Role | Cares About | Pain Points | Critical Assumptions |
|------|-------------|-------------|---------------------|
| Operators (build/push/run image) | `build.ps1` builds clean first try; `run.ps1` launches; state persists across `--rm` | A build that dies mid-layer on a missing apt lib; a rebuild that silently drifts | `--with-deps` self-heals apt on any base; toggles unchanged |
| Developers (maintain Dockerfile/docs) | Plan executes against the tree they see; diffs stay clean | Line/text refs that don't match the branch they land on; stranded uncommitted work | Working-tree == execution baseline |
| End users (agents in container) | opencode + codegraph + agent-browser + playwright actually *work*, not just print `--version` | `--version` passing while the native path (better-sqlite3, browser launch) is broken | Smoke test = functional proof |
| Security (image shared/pushed) | No host secrets / permissive posture baked; reproducible artifact | Rolling base tag → unaudited bytes between rebuilds | Pinning story complete |
| Integrators (consumers rebuilding) | `run.ps1`/`build.ps1` interfaces stable | Interface stable but image contents shift under them | Backward-compatible swap |

---

## Attack Surface (Per Role)

**Operators:**
- Claims: `./build.ps1 -Image … -Engine docker` builds clean; in-build `--version` smoke tests all pass.
- Assumptions: `agent-browser install --with-deps` / `playwright install --with-deps chromium` install missing Chromium libs on `bookworm-slim` even after apt lists were deleted.
- Dependencies: deb.nodesource.com, npm registry, go.dev, Chrome-for-Testing CDN, playwright CDN, Debian apt mirrors — all at build time.

**Developers:**
- Claims: Step 1 is a full rewrite; Steps 3/4 are small incremental edits at cited line ranges.
- Assumptions: the file bytes at execution time match the working tree the plan was authored against.
- Dependencies: `> Worktree: Yes` isolating cleanly despite pre-existing dirty state.

**End users:**
- Claims: codegraph musl `node: not found` blocker resolved; codegraph/agent-browser/playwright function.
- Assumptions: `<tool> --version` exit 0 ⇒ the tool's *real* runtime path works (native sqlite loads, browser launches).

**Security / Integrators:**
- Claims: base "pinned by digest-or-tag not `:latest`"; floating-tag gap removed.
- Assumptions: a `:bookworm-slim` tag is a stable, auditable artifact.

---

## Critical Findings

### Finding 1: apt package lists deleted before `--with-deps` runs, on a base that actually needs them
**Severity:** Medium (build-blocker, loud, cheap fix — elevated because the plan's own fallback shares the defect) | **Likelihood:** High on `bookworm-slim` if agent-browser does not self-`apt-get update`

**Affects Roles:** Operators (build fails), Developers (must patch to unblock)

**Attack Vector:** Layer 1 ends with `apt-get clean; rm -rf /var/lib/apt/lists/*`. Two later, separate RUN layers then execute `agent-browser install --with-deps` (first) and `playwright install --with-deps chromium` (second). With an empty apt cache, `apt-get install <lib>` for a **missing** package fails ("Unable to locate package"). On `bookworm-slim` the Chromium runtime libs are genuinely absent.
- **Verified:** Playwright's installer (`installDependenciesLinux`) prepends `apt-get update` to its own command list → the *playwright* step self-heals and is safe.
- **Unverified & runs first:** agent-browser is a native Rust CLI; its README states only "`agent-browser install --with-deps` … exits nonzero if the package manager cannot install every required browser library." Whether it self-`apt-get update`s is undocumented. If it does not, the build dies at the agent-browser layer before playwright ever runs.
- **Why the reference images don't catch this:** codex/claude delete apt lists in the same position, yet build clean — because their base is the *full* `docker/sandbox-templates:{codex,claude-code}` Debian, which already ships the Chromium libs, so `apt-get install` finds them present (a no-op that succeeds with an empty cache). `bookworm-slim` is the first place agent-browser must install these libs from scratch. The prior audit (2607111343) only verified agent-browser on the **Alpine system-Chromium path with no `--with-deps`** — there is zero evidence in this codebase that `agent-browser install --with-deps` has ever succeeded on a minimal base with purged lists.
- **Fallback is also broken:** the plan's remediation for assumption 2 ("pre-apt the known Chromium lib set if `--with-deps` misses one") is itself an `apt-get install` with no preceding `apt-get update` → fails identically against the deleted cache.

**Role-Specific Impact:**
- **Operators:** first `./build.ps1` aborts mid-build; the documented workaround doesn't work either.
- **Developers:** must diagnose and patch the layering before anyone can build.

**Blast Radius:** Whole build; no image produced. Not a silent/runtime landmine (fails at build), which caps severity.

**Remediation:** Defer `rm -rf /var/lib/apt/lists/*` to *after* the agent-browser + playwright layers (single final cleanup), **or** prepend `apt-get update` to the agent-browser RUN and to the pre-apt fallback. Add an explicit assumption-2 sub-check: "agent-browser `--with-deps` self-refreshes apt, or lists are present when it runs." Verify with an actual `bookworm-slim` build, not by analogy to the full-base images.

---

### Finding 2: Worktree branches from clean HEAD, but the plan was authored against a dirty tree with unrelated in-flight edits
**Severity:** Medium | **Likelihood:** High (dirty state exists now, confirmed)

**Affects Roles:** Developers (execution), Operators (post-merge tree hygiene)

**Attack Vector:** `git diff --stat HEAD -- opencode/` = `Dockerfile 37±, README.md 25±, run.ps1 29±` (51 insertions / 40 deletions) uncommitted. These edits are an **unrelated in-flight change** — they migrate the *Alpine* Dockerfile toward npm-codegraph + playwright + `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` (still `apk`, still musl, still `AGENT_BROWSER_EXECUTABLE_PATH`). They are not partial base-swap work. `> Worktree: Yes` creates the ephemeral branch from committed **HEAD**, which lacks all 51/40 lines. Consequences:
- Step 3 (run.ps1 "~lines 91-92, ~105") and Step 4 (README "floating tag ~lines 170-174") cite **working-tree** offsets/text; in a HEAD-based worktree those references are shifted or absent.
- The stranded M-edits remain in the main working dir. After the base-swap squash-merges to base, those edits become diffs against a Debian Dockerfile that no longer has the `apk`/musl lines they patch — semantically dead, requiring manual discard.
- Step 1 (full Dockerfile rewrite) is immune to the start state, so the *Dockerfile* is fine; only the incremental Steps 3/4 and post-merge hygiene are exposed.

**Role-Specific Impact:**
- **Developers:** edits target text that isn't there on the executing branch; or, if run in checkout mode, the base swap commits *on top of* the M-edits, muddying the diff.
- **Operators:** left with a working tree full of obsolete conflicting edits after merge.

**Blast Radius:** One projex scope; recoverable, but the plan's "worktree mode handles this cleanly" (Rollback section) is false and will mislead the executor.

**Remediation:** Before execution, **commit or discard** the opencode `Dockerfile`/`README`/`run.ps1` M-edits to base — they are superseded by this rewrite. Then re-derive Step 3/4 line/text references against the committed baseline. SKILL.md already requires "Plan must be committed to base branch before execution"; extend that to any working state the plan's incremental steps depend on.

---

## Role-Based Assumption Challenges

### Operators: "`--with-deps` covers the thinner slim base (assumption 2)"
**Challenge:** True for playwright (self-`apt-get update`, verified). Unverified for agent-browser, which runs first, after the cache was purged.
**Counter-Evidence:** Reference-image success is explained by pre-present libs on the full base, not by `--with-deps` self-healing on a bare cache. No in-repo evidence for agent-browser `--with-deps` on a minimal base.
**If Wrong:** Build-blocker (F1).
**Action:** Validate (real bookworm-slim build) + Fix layering.

### Security: "Base is now pinned; the floating-tag gap is removed"
**Challenge:** `debian:bookworm-slim` is a rolling tag rebuilt with security updates; it is not digest-pinned.
**Counter-Evidence:** Success-criterion wording "digest-or-tag" is literally satisfied by the tag, but the Objective's framing ("a shared build artifact should track an audited version explicitly", "floating tag gap removed") overstates it: two consecutive builds of the same Dockerfile can pull different base bytes. opencode/codegraph/agent-browser/playwright/Go **are** properly version-pinned; only the base and `pnpm@latest` float.
**If Wrong:** Non-reproducible base layer; the exact critique leveled at `anomalyco:latest` still applies at the patch level.
**Action:** Relax the claim in docs, or pin the base by digest. (Consistent with claude/codex, which are also tag-pinned — so acceptable, but say so honestly.)

### Developers: "`corepack prepare pnpm@latest --activate` is fine (assumption 3)"
**Challenge:** In a plan that pins everything, pnpm floats to latest, and Node-24-era corepack has a known `Cannot find matching keyid` signature failure when its bundled keys lag npm's registry keys.
**Counter-Evidence:** Inherited verbatim from claude/codex (not a regression), and those are audited-working at their Node 24 pin — so low risk today. But a pnpm major or a corepack key-rotation could break it on a future rebuild, silently tied to F3's rolling base.
**If Wrong:** `corepack prepare` fails at build; fallback `npm i -g corepack` (noted in assumption 3) recovers.
**Action:** Monitor.

### End users: "`codegraph --version` exit 0 proves codegraph works on glibc (Criterion 5)"
**Challenge:** The musl failure was `exec: …/node: not found` (bundled-node). On glibc via `npm i -g`, codegraph uses system node, so `--version` will pass — but `--version` may not load its `better-sqlite3` native addon, the actual runtime surface. Same `--version ≠ functional` gap the prior redteam raised for agent-browser.
**Counter-Evidence:** glibc `better-sqlite3` ships standard prebuilds and `build-essential` is present, so functional risk is genuinely low — but the criterion is only shallowly verified.
**If Wrong:** codegraph launches yet fails on first real index operation; not caught by the build.
**Action:** Validate with one real codegraph operation (index a tiny repo), not only `--version`.

---

## Role-Specific Edge Cases & Failures

### Operators: opencode-ai postinstall / optional-dep resolution
**Trigger:** Build env with `--ignore-scripts` or `--omit=optional` (CI hardening, npmrc).
**Role Experience:** `opencode` bin symlink present but non-functional — the package's bin is `bin/opencode.exe` (a JS shim) + `postinstall: node ./postinstall.mjs`; the runnable binary is the optional dep `opencode-linux-x64`. Skip either and `opencode --version` breaks.
**Recovery:** Possible — in-build `opencode --version` catches it; curl `opencode.ai/install` fallback exists (assumption 1). Well-covered.
**Mitigation:** Keep the in-build smoke test; don't add `--ignore-scripts`/`--omit=optional` to the npm layer.

### Developers: agent-browser/playwright installed globally as root, browsers under `/home/agent`
**Trigger:** `HOME=/home/agent <tool> install` runs as root before `USER agent`; relies on `useradd` (prior layer) having created `/home/agent`.
**Role Experience:** Correct as ordered (useradd → agent-browser → playwright), matching codex/claude; chown steps follow. No defect — noted as verified-OK.
**Recovery:** N/A.
**Mitigation:** None needed.

---

## What's Hidden (Per Role)

**Omissions per role:**
- **Operators:** that the reference images' clean builds do **not** prove the `--with-deps`-after-purged-lists pattern works on a *minimal* base (F1). The plan cites codex/claude as proof of assumption 2 without noting their base already carries the libs.
- **Developers:** that `> Worktree: Yes` does not absorb the pre-existing dirty tree (F2); "handles this cleanly" is asserted, not true.
- **Security:** that `bookworm-slim` floats at the patch level (F3).

**Tradeoffs per role:**
- **Operators:** image size grows (Chrome-for-Testing + playwright Chromium vs one system chromium) — plan acknowledges this openly.
- **End users:** `--version` smoke tests chosen over functional tests for build speed — acknowledged for browsers, not for codegraph.

---

## Scale & Stress (Role Impact)

**At 10x (many rebuilds / CI matrix):**
- **Operators:** F3's rolling base + `pnpm@latest` mean N rebuilds can yield N subtly different images; no digest to bisect a regression against.
- **Developers:** each `--with-deps` re-runs `apt-get update` + full Chromium-lib install per build (no lists cached) — slower cold builds; acceptable but worth a layer-cache note.

**At 100x (broad adoption of the pushed image):**
- **Security:** an un-digest-pinned base distributed widely means "which Debian patch level is in the image everyone pulled?" is unanswerable from the Dockerfile alone.
- **End users:** any latent codegraph-native or agent-browser-browser issue that `--version` didn't catch surfaces across every consumer at once.

---

## Remediation

### Must Fix (Before Proceeding)
- **F1 apt-lists ordering** (affects: Operators, Developers) → move `rm -rf /var/lib/apt/lists/*` after the browser-install layers, or prepend `apt-get update` to the agent-browser step and to the pre-apt fallback → Verify with a real `bookworm-slim` build reaching both browser layers.
- **F2 dirty-tree vs worktree** (affects: Developers, Operators) → commit or discard the opencode `Dockerfile`/`README`/`run.ps1` M-edits to base first; re-derive Step 3/4 refs against the committed baseline; correct the Rollback section's "handles this cleanly" claim.

### Should Fix (Before Production)
- **F3 base pinning honesty** (affects: Security, Integrators) → pin base by digest, or reword the Objective/Criterion to admit `:bookworm-slim` still floats at patch level.
- **Codegraph functional check** (affects: End users) → add one real codegraph operation to the verification plan, not only `--version`.

### Monitor
- **F4 `pnpm@latest` / corepack keyid** (affects: Developers) → revisit if a rebuild fails at `corepack prepare`; `npm i -g corepack` fallback ready.
- **opencode-ai postinstall/optional-dep** (affects: Operators) → keep smoke test; never add `--ignore-scripts`/`--omit=optional`.

---

## Final Assessment

**Soundness:** Fixable
**Risk:** Medium
**Readiness:** Needs Work

**Per-Role Readiness:**
- **Operators:** Not Ready — F1 can block the first build and the documented fallback shares the defect.
- **Developers:** Needs Work — F2 must be resolved so incremental steps land on the intended baseline.
- **End users:** Ready with Fixes — core glibc thesis verified; add a functional codegraph check.
- **Security:** Ready with Caveats — pin/soften the base-tag claim (F3).
- **Integrators:** Ready — `run.ps1`/`build.ps1` interfaces unchanged (verified base-agnostic).

**Conditions for Approval:**
- [ ] apt lists present (or `apt-get update` runs) when `agent-browser install --with-deps` executes; fallback likewise (F1) — for Operators
- [ ] opencode M-edits committed/discarded to base; Step 3/4 refs re-derived; Rollback claim corrected (F2) — for Developers
- [ ] Base-tag pinning claim reconciled with reality (F3) — for Security

**No-Go If:**
- [ ] A real `bookworm-slim` build is not exercised end-to-end before merge (both browser layers must actually install libs from scratch) — impacts Operators, End users

---

## What's Solid (credit where due)

Verified true, not taken on faith:
- `opencode-ai@1.17.19` `optionalDependencies` includes `opencode-linux-x64: 1.17.19` (glibc) alongside musl/baseline variants → npm resolves the glibc bin on Debian x64. Core claim holds.
- NodeSource Node 24 ships corepack: claude/codex both do bare `corepack enable; corepack prepare pnpm@latest --activate` with **no** `npm i -g corepack` → assumption 3's Debian path is proven by working siblings (the Alpine "Node 24 no longer bundles corepack" note was `apk`-specific, not upstream).
- `debian:bookworm-slim` leaves uid 1000 free, and `useradd --uid 1000` fails loud on any collision anyway → agent-user creation is collision-safe.
- `prepare.ps1` is base-agnostic **and** the plan characterizes it correctly: it *does* rewrite opencode.json local-MCP `command` arrays Win→Linux over **every** element (lines 98-128 — `Convert-OpencodeWinPath`, `Rewrite-McpCommandElement`), handling the prior redteam's `command[1..]` (F2) and PS5.1 array-collapse (F3) concerns, and touching `permission`. Its config target (`/home/agent/.config/opencode`) is identical on Debian, so "no change needed" holds. (Aside: `prepare.ps1`'s line-4 header "no path rewriting" is stale vs. the code below it — but that file is out of scope for this swap.)
- Playwright's `--with-deps` self-runs `apt-get update` → that step is safe on slim regardless of F1.
- Node-purge step correctly omitted: `bookworm-slim` ships no node/nvm to collide with NodeSource (unlike the sandbox-templates bases codex/claude must purge).
