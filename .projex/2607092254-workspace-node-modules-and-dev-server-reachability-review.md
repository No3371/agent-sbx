# Review: Workspace node_modules Contamination + Dev-Server Reachability

> **Review Date:** 2026-07-09
> **Reviewer:** Claude (Opus 4.8) — via review-projex
> **Reviewed Projex:** 2607092240-workspace-node-modules-and-dev-server-reachability-proposal.md
> **Original Date:** 2026-07-09 (same day)
> **Time Since Creation:** ~14 min (proposal drafted by subagent, then refined directly by orchestrator; review requested to validate the un-workflowed refinement before Plan)

---

## Review Summary

**Verdict:** Needs Modification

Problem is real, current, and correctly diagnosed; all cited file/line refs verified accurate; the dev-server-reachability half (P1) is sound and plan-ready as-is. But the orchestrator's refinement to **Option A** (cp -a seed + `npm install && npm rebuild` + named per-project volume) was applied to Option A's description + risk table **only** — the **Recommended Approach** and **Open Questions** sections still carry the pre-refinement design (anonymous empty mask, named-volume deferred). Document now contradicts itself on the two central node_modules design decisions. Additionally the refined seed mechanism is more complex than, and not backed by, this repo's own precedent — which does the simpler from-empty `npm install`. Reconcile before Plan.

---

## Timeline Analysis

### When Authored
- Created: 2026-07-09, Status: Draft
- Two-stage authoring: subagent draft (repo-grounded) → orchestrator refinement of Option A (seed/rebuild/named-volume/pnpm caveat) without a workflow pass. Review specifically targets the un-vetted refinement.

### What Changed Since
| Area | Then | Now | Impact |
|------|------|-----|--------|
| Codebase | run.ps1 + Dockerfiles as cited | Identical (same-day) — verified unchanged | No drift; refs current |
| Design | subagent's anon-empty-mask recommendation | orchestrator's seed+named-volume Option A | Doc internally split — see Validity |

### Related Events
- `2607060232-run-images-without-sbx-eval.md` — established the run.ps1 no-sbx launcher this builds on. Still current.
- Plugin `node_modules` precedent (Dockerfiles) — live and verified (see Accuracy).

---

## Status Quo Assessment

### Current State (independently verified)
- **Mount model** `claude/run.ps1:94-101`: `$runArgs = @('run','-it','--rm','-v',"${Workspace}:/workspace",'-w','/workspace', <+3 individual-file -v mounts>)`. Confirmed total `/workspace` bind-mount. Full arg assembly runs 94-104. ✓
- **No `-p` / publish** anywhere in any run.ps1 — grep across all three returns only a codex comment explaining why it does NOT publish port 1455. Claim "publishes no ports" holds. ✓
- **Precedent** `claude/Dockerfile:144-154` (comment 144-149, `RUN`+loop 150-154): `prepare.ps1` skips `node_modules/` from plugins; container loops package.json dirs and runs `npm install --no-audit --no-fund`. Mirrored: `Dockerfile.slim:131-140`, `codex/Dockerfile:79-89`. ✓
- **build-essential present** in claude/codex/slim Dockerfiles → node-gyp source-compile fallback available in-container. Supports the reinstall path's viability. (opencode Dockerfile: not confirmed to carry build-essential — see gap.)
- `$Workspace = $PWD.Path` is the only project identifier run.ps1 holds.

### Drift from Projex Assumptions
| Assumption | Original | Current Reality | Drift |
|------------|----------|-----------------|-------|
| Cited line refs | run.ps1:94-101/94-104, Dockerfile:145-154, slim:131-140, codex:85-89 | All verified accurate (±1 line on comment starts) | None |
| Precedent = the same fix | "skip + reinstall node_modules" | TRUE, but precedent is **from-empty** `npm install`, NOT cp -a seed + install&&rebuild | Minor — refined Option A exceeds precedent |
| In-container toolchain | "Node 24 + npm + pnpm baked" | TRUE + build-essential; not verified for opencode | Minor |

---

## Validity Assessment

### Problems Stated
| Problem | Still Valid? | Notes |
|---------|--------------|-------|
| Host (Win) node_modules native binaries fail on Linux container | Yes | Mechanism sound; repo's own better-sqlite3 precedent independently confirms |
| No port publish + `127.0.0.1` bind → host can't reach dev server | Yes | Verified: zero `-p` in any run.ps1 |

### Approach Proposed
| Aspect | Still Valid? | Notes |
|--------|--------------|-------|
| P1 (`-Ports` publish + `0.0.0.0` doc) | Yes | Clean, opt-in, precedent-consistent, plan-ready |
| A — mask `/workspace/node_modules` | Yes | Core idea sound (direct analogue of plugin precedent) |
| A — cp -a seed + `npm install && npm rebuild` | **Partial** | Directionally correct, but see Challenge 2; not precedent-backed; simpler from-empty install exists |
| A — named volume keyed per-project | Yes, workable | Keying scheme concrete (Challenge 4) — but contradicts Recommended Approach |
| B (baked convention doc) | Yes | Low-risk connective tissue |
| C (auto rm -rf) | Correctly rejected | Destructive to bind-mounted host state |

### Prerequisites/Dependencies
| Dependency | Status | Impact |
|------------|--------|--------|
| run.ps1 no-sbx launcher (2607060232) | Met | Mount semantics under repo control |
| In-container npm/pnpm + build-essential | Met (claude/codex/slim) | Reinstall path viable; verify opencode |
| Network at first in-container install | Assumed | Acknowledged ("offline-permitting"); prebuilt fetch needs net, else source-compiles |

---

## Completeness Assessment

### Coverage Gaps
- **yarn not addressed.** pnpm caveat present, but yarn absent. yarn classic (v1): node_modules ≈ npm, mask+install works. yarn **Berry/PnP** (v2+): **no node_modules at all** — deps in `.yarn/cache` (zips) resolved via `.pnp.cjs`; native deps in `.yarn/unplugged`. Mask over `/workspace/node_modules` is a **no-op** for PnP, and Windows-built `.yarn/unplugged` natives stay broken. Different failure mode the mask doesn't touch. Speculative for this repo (yarn not baked; concrete case is npm/Vite) — needs a one-line caveat, not a feature.
- **opencode toolchain** not confirmed (build-essential). If opencode is expected to in-container-reinstall native deps, verify or the reinstall silently source-fails.

### Scope Expansion Candidates
- None required now. Monorepo/pnpm/yarn all correctly deferred to doc-caveat per ponytail; don't build globbing/multi-pkgmgr engines on day one.

---

## Accuracy Assessment

### Technical Content
| Content | Status | Issue |
|---------|--------|-------|
| `claude/run.ps1:94-101` mount model | Accurate | Exact — `$runArgs` block 94-101 |
| `claude/run.ps1:94-104` (appendix) | Accurate | Full arg assembly through 104; two spans cited, both correct |
| "no `-p` publish anywhere" | Accurate | Verified across 3 launchers |
| `claude/Dockerfile:145-154` precedent | Accurate | Comment actually 144; substance 144-154. Quote matches |
| `Dockerfile.slim:131-140`, `codex/Dockerfile:85-89` | Accurate | Verified |
| "Node 24 + npm + pnpm baked (`Dockerfile:57-58`)" | Accurate | corepack/pnpm at 57-58 |
| Precedent = "reinstall so native deps rebuilt for Linux" | Accurate but **narrower than used** | Precedent does from-**empty** `npm install`; NOT cp -a seed + rebuild. Refined Option A extends beyond what precedent validates |
| Verbatim error string | **Flag** | `node_modules\rolldown\...binding-BxaeY8HI.mjs ... Node.js v25.2.1` — backslash paths + Node **v25** indicate a **host (Windows)** capture; container runs Linux Node **24**, forward slashes. Error illustrates the mechanism but is not clean evidence of the *in-container* failure. Mechanism still sound via better-sqlite3 precedent |

### Factual Content
- "install reconciles per-platform optionalDependencies; rebuild forces postinstall/native-fetch re-run" — see Challenge 2. `npm rebuild` claim is **correct** for node-gyp/compile packages; **partial** for prebuilt-binary packages (better-sqlite3/sharp-classic) where re-fetch-vs-skip is version-dependent.

---

## Challenge Questions

### Challenge 1: Does the refined Option A match what the doc actually recommends?
**Evidence for projex position:** Option A description + risk table (rows: seed cost, pnpm dangling links, named-volume bleed) all describe seed + `install && rebuild` + **named** volume.

**Evidence against:** Recommended Approach (L99-106) says *"A (top-level **anonymous-volume** mask)"*, *"Start with the single top-level `-v /workspace/node_modules` **anonymous mask**"*, *"Add persistence (**named volume**) only if repeated per-run reinstalls actually bite."* Open Questions (L145) still asks *"Anonymous vs named?"*; L144 asks *"default-on vs opt-in?"* — both unresolved. The rationale line still says "ship the single-mask 80% case."

**Assessment:** **Internal contradiction — the primary finding.** Refinement updated Option A's local description but not the section that picks the winner. Two incompatible mechanisms coexist: (a) empty anonymous mask + reinstall-each-run vs (b) cp -a seed + named per-project volume + install&&rebuild. A Plan can't derive exact run.ps1 edits without knowing which. **Must reconcile.**

### Challenge 2: Does `cp -a` seed + `npm install && npm rebuild` actually reconcile platform-mismatched deps — better than the simpler from-empty install?
**Evidence for:** `npm install` evaluates `os`/`cpu` on optionalDependencies → installs linux optional dep, omits win32 (fixes rollup/esbuild/rolldown class). `npm rebuild` **does** re-run preinstall/install/postinstall + node-gyp for present packages (verified vs npm's documented behavior) → the postinstall/native claim is correct for compile-from-source packages. build-essential present → source fallback works.

**Evidence against:**
- Installing **on top of** a foreign-platform-populated node_modules is the exact scenario of npm's long-tail optional-deps bug class (`Cannot find module @rollup/rollup-linux-x64-gnu`); from-empty install sidesteps it. Precedent uses from-empty.
- For **prebuilt-binary** packages (better-sqlite3, sharp-classic), `npm rebuild` runs the install script but whether prebuild-install/node-pre-gyp **re-fetches** the Linux binary or **short-circuits** on the copied foreign `build/Release/*.node` is package/version-dependent. If it skips and doesn't fall through to node-gyp, the win32 binary survives.
- **Cost inversion:** `cp -a` of a large node_modules across the Docker-Desktop-for-Windows bind boundary (9p/virtiofs, hundreds of thousands of tiny files — the pathological case) is plausibly **slower** than a clean `npm install` from cache/registry. The "much cheaper — only mismatched natives touch network" pro may be net-negative on the actual host FS. Risk table rates this Med/Low; real impact likely higher.

**Assessment:** Mechanism directionally sound, `rebuild` claim substantively correct, but the seed adds complexity + a cross-boundary copy cost to dodge a re-download the named volume already makes one-time. The **precedent-backed** `rm -rf node_modules && npm install` (from empty) is more reliable and is what this repo already does. Recommend: default to from-empty reinstall; treat seed as an optional optimization to prove out, not the baseline.

### Challenge 3: Is the pnpm caveat sufficient; does yarn need coverage?
**Evidence for:** pnpm caveat (skip copy, run `pnpm install`) is correct — pnpm node_modules is symlinks into `.pnpm/` virtual store; cp -a would carry Windows natives + risk dangling links; fresh `pnpm install` re-links cheaply.

**Evidence against:** yarn entirely absent. Berry/PnP has no node_modules → mask is a no-op, `.yarn/unplugged` natives unfixed. Classic v1 works like npm.

**Assessment:** pnpm caveat adequate. yarn is a **completeness gap** — but speculative (not baked, not the concrete case). Add one-line caveat; do not build for it.

### Challenge 4: Is the named-volume-keyed-per-project scheme concretely workable from what run.ps1 knows?
**Evidence for:** run.ps1 has `$Workspace = $PWD.Path` — stable, unique per project.

**Evidence against:** Docker volume names must match `[a-zA-Z0-9][a-zA-Z0-9_.-]+`; a Windows path (`S:\Repos\foo`, `:` + `\`) is not a legal volume name → must hash/sanitize.

**Assessment:** **Workable, not blocking.** Trivial: `nmvol-<short-SHA($Workspace)>` (PowerShell `Get-FileHash`/SHA over the path string). Proposal says "keyed off workspace path" without the sanitization step — Plan can fill this; not an open blocker.

---

## Value Assessment

| Aspect | Original Value | Current Value | Change |
|--------|----------------|---------------|--------|
| Problem significance | High (blocks any Node/Vite app in-container) | High | None |
| Solution benefit — P1 reachability | High | High | None |
| Solution benefit — A node_modules | High | High (once mechanism decided) | None |
| Implementation cost | Low-Med | Low-Med, +risk if seed path chosen over from-empty | Slight ↑ |

**Value Verdict:** Still valuable. Problem is live and correctly framed; only the node_modules *mechanism selection* and doc self-consistency need settling.

---

## Recommendations

### Required Changes (before Plan)
1. **Reconcile the contradiction.** Make Recommended Approach + Open Questions agree with the intended Option A. Decide explicitly: (a) empty anonymous mask + reinstall vs (b) cp -a seed + named volume; and default-on vs opt-in. State one as the recommendation.
2. **Justify seed vs from-empty**, or drop the seed to baseline. Given the precedent (from-empty `npm install`) + the Windows bind-copy cost, recommend from-empty reinstall as default; seed as optional optimization to validate later.

### Suggested Improvements (Plan can own)
1. One-line yarn caveat (classic ≈ npm; Berry/PnP mask is no-op, needs `yarn install` for `.yarn/unplugged`).
2. Named-volume keying detail: hash `$Workspace` → sanitized volume name.
3. Verify opencode Dockerfile carries build-essential (or note reinstall may source-fail there).
4. Soften the flagship error citation — note it's a host-side capture illustrating the mechanism; the in-container failure is asserted from the same mechanism + better-sqlite3 precedent.

### Action Items
- [ ] Orchestrator/author: reconcile Recommended Approach ↔ Option A (Req #1)
- [ ] Decide seed-vs-empty + anon-vs-named defaults (Req #2)
- [ ] Then hand to plan-projex

### Next Review
- After reconciliation, or at Plan drafting.

---

## Appendix

### Independent Observations (pre-proposal-read)
- All three run.ps1: total `/workspace` bind-mount, no `-p`, individual-file state mounts. Confirmed independently.
- Dockerfiles already skip+reinstall plugin node_modules via from-**empty** `npm install --no-audit --no-fund`; build-essential present for node-gyp fallback. This is the genuine, working precedent — and it does NOT use a cp -a seed or `npm rebuild`.
- run.ps1 knows only `$PWD.Path` as project id.

### Plan-Readiness Verdict
**Not as-is.** Reachability half (P1) is plan-ready and could split out immediately. node_modules half (A) has one blocking doc contradiction (core mechanism undecided) + a mechanism-selection call that the proposal — not the plan — should make. Both are small edits (~one section reconcile), not a redesign. Once Recommended Approach is self-consistent and seed-vs-empty is decided, ready for plan-projex.

### Related Projex Status
- 2607092240-…-proposal.md — Draft; this review's target. Needs Modification.
- 2607060232-run-images-without-sbx-eval.md — current; dependency met.
- 2607071030-sandbox-permission-user-issues-memo.md — sibling class; unaffected.
