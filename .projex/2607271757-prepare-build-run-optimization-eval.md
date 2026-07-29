# Prepare/Build/Run Pipeline Optimization — Evaluation

> **Status:** Complete
> **Created:** 2026-07-27
> **Author:** agent (Claude)
> **Subject:** prepare.ps1 → build.ps1 (Dockerfile) → run.ps1 pipeline across all 5 suites (claude | codex | opencode | cursor | pi)
> **Type:** Status Quo
> **Tier:** Standard
> **Lenses:** Constraint Mapping, Sensitivity
> **Related:** 2607171400-pi-coding-agent-install-audit.md | 2607081900-codegraph-integration-audit.md | F4 → 2607271806-sbx-base-image-suite-plan.md + 2607271807-pi-cursor-base-migration-plan.md + 2607271808-opencode-base-migration-plan.md

## Executive Summary

Evaluated the 3-stage pipeline for optimization: iteration speed (rebuild after a config/version tweak), cold-build cost, image size, run startup, and maintenance burden. Biggest wins, in order: (1) **Dockerfile layer restructure in pi/** — pi-package installs sit *after* the host-context COPY, so every host-config re-stage invalidates 4 network-install layers; monolithic layer 1 makes a `PI_VERSION` bump re-run apt + NodeSource + all npm tools. (2) **Cross-suite script dedup** — the five `build.ps1` are functionally identical (only suite-name strings + CRLF noise differ; opencode's "324-line diff" is pure CRLF), `retag-tar.ps1` is 5 verbatim copies; drift is already visible. (3) **Shared base image for the 3 debian-based suites** (opencode/cursor/pi) — Node, codegraph, agent-browser+Chrome, playwright+Chromium, Go, Python are rebuilt and stored ×3 with no shared layers. (4) Smaller: un-cleaned apt lists in 2 layers (image size), unpinned `pnpm@latest`, runtime bootstrap steps bakeable at build time.

## Scope

**Questions:** Where does the pipeline waste time/disk on (a) incremental rebuilds, (b) cold builds, (c) container startup, (d) maintenance?
**Criteria:** rebuild latency after common changes | cold-build time | image/disk size | startup latency | script maintainability.
**Out of scope:** security posture (covered by install audits), sbx-based suites' base-image choice (claude/codex extend `docker/sandbox-templates` — fixed constraint), functional changes to what gets baked.

## Context

Repo: 5 sandbox template suites, each with `prepare.ps1` (stage host config → `context/`), `build.ps1` (podman/docker build + tar/retag/load/push), `run.ps1` (bind-mounts, volumes, env forwarding, bootstrap), `retag-tar.ps1`, `Dockerfile`.

Script sizes: prepare 135–573 lines (varies legitimately — claude does plugin surgery) | build 157–161 (near-identical) | run 92–172 (structurally similar) | retag-tar 69×5 (identical).
Context sizes staged: claude 39M | codex 61M | opencode 1.9M | cursor 2K | pi ~0.
`.dockerignore` present in all 5, correctly excludes `*.tar` / output dirs — build-context bloat already handled. ✓

## Findings

### F1 — pi/Dockerfile: pi-package layers invalidated by every config change — **High confidence, highest-value fix**

[Dockerfile:196](pi/Dockerfile:196) `COPY context/.pi/agent/` precedes the 4 `RUN pi install npm:...` layers ([Dockerfile:209-212](pi/Dockerfile:209)). `prepare.ps1` re-stages the live host `~/.pi/agent` on every build — any settings/skill/extension tweak changes COPY content → cache-busts all 4 network installs (npm downloads + `better-sqlite3` native compile for context-mode).

**Fix:** reorder — run the 4 `pi install` layers first (empty `~/.pi/agent`), then COPY host context. No collision: prepare always excludes `npm/` from staging (the Dockerfile comment at :199-203 already documents this non-overlap), and COPY merges rather than replaces. **Verify:** `pi install` works with no prior config (Medium confidence it does — it creates its own tree; test one build).
**Payoff:** config-only rebuild drops from 4 network/compile layers to a pure COPY.

### F2 — pi/Dockerfile: monolithic first layer — **High confidence**

[Dockerfile:83-105](pi/Dockerfile:83): one RUN = apt baseline + NodeSource keyring/repo + nodejs + build-essential + pnpm + 4 npm globals (pi, codegraph, agent-browser, playwright). `PI_VERSION` is referenced in this layer, so a pi version bump (frequent — pi releases often) re-runs *everything* including apt and Node.

**Fix:** split into 3 layers by change frequency: (1) apt baseline + NodeSource + nodejs + build-essential (changes ~never), (2) shared tool trio + pnpm (changes on audit refresh), (3) `pi` itself (changes most). Layer-per-concern also mirrors what the suite already does for pi packages ("each `pi install` its own RUN").
**Payoff:** pi bump rebuild ≈ one npm install instead of full cold build. Sensitivity: this is the assumption that most changes the day-to-day experience — pi is the fastest-moving pinned dep in the file.

### F3 — Cross-suite duplication: build/retag are 1 script ×5 — **High confidence**

- `build.ps1`: functionally identical across all 5; real deltas are suite-name strings in comments/errors + prepare param names (`-HostPiDir` vs `-HostOpencodeDir` …) + per-suite `-Supported` language list. opencode's apparent 324-line diff vs pi is **pure CRLF** (opencode = CRLF, pi = LF).
- `retag-tar.ps1`: opencode/cursor byte-identical to pi; claude/codex differ only in line-endings/whitespace.
- Fixes/features added to one copy (e.g. pi's single-quote-injection guard, `-LoadToPodman`) must be hand-ported ×5 — CRLF drift shows this is already not happening cleanly.

**Fix:** hoist to `common/build.ps1` + `common/retag-tar.ps1`, parameterized by a small per-suite manifest (image default, supported languages, prepare-param mapping) or thin per-suite shims that dot-source common. `run.ps1`/`prepare.ps1` stay per-suite (legitimately divergent), but their shared blocks (SHA-256 workspace hashing, node_modules masking, TZ detection, env-forward loop, credential-pattern scan) could move to a dot-sourced `common/lib.ps1`.
**Payoff:** maintenance ÷5; eliminates drift class of bugs. Also normalize line endings via `.gitattributes` (`*.ps1 text eol=lf` or crlf — just pick one).

### F4 — No shared base image among debian-based suites — **High confidence, biggest disk/cold-build lever**

opencode, cursor, pi all start `FROM debian:bookworm-slim` and independently install: Node 25 + build-essential, pnpm, codegraph, agent-browser + Chrome-for-Testing + its apt libs, playwright + Chromium + its apt libs, Go tarball, Python. The browser layers alone are the heavyweight (~1GB+ per image); stored ×3 with zero layer sharing, rebuilt ×3 on cold builds.

**Fix:** one `sbx-shared-base:node25` image (baseline apt + Node + tool trio + browsers + optional Go/Python), the 3 suites `FROM` it and add only their agent + config. claude/codex can't join (must extend `docker/sandbox-templates:*`) but already share layers with their own base.
**Trade-off:** adds a build-order dependency + a place to version the base; language ARGs must live in the base or become base variants. Worth it at 3 consumers.

### F5 — Image-size leaks: apt lists not cleaned in 2 layers — **High confidence, small**

[pi/Dockerfile:119-121](pi/Dockerfile:119) (agent-browser `--with-deps`) runs `apt-get update` and never `rm -rf /var/lib/apt/lists/*`; the playwright layer ([:128](pi/Dockerfile:128)) inherits/creates list state too. ~40–60MB of dead weight per un-cleaned layer. Same pattern likely in the sibling Dockerfiles (claude has the same layer sequence at :91/:98 — verify others). Also `npm install -g pnpm@latest` ([:96](pi/Dockerfile:96)) is the only unpinned install in an otherwise everything-pinned file — reproducibility inconsistency, not size.

**Fix:** append cleanup to both layers; pin `pnpm@<version>` alongside the other ARGs.

### F6 — BuildKit cache mounts unused — **Medium confidence (podman version dependent)**

Cold rebuilds re-download: apt packages, npm tarballs, Go tarball (~70MB), Chrome/Chromium. `--mount=type=cache` on `/var/cache/apt`, npm cache, and a download dir would make cache-busted rebuilds mostly-local. Podman ≥4 supports BuildKit-style cache mounts via buildah. Lower priority if F1/F2/F4 land (cache-busting becomes rarer).

### F7 — prepare.ps1: 3 full tree walks + per-file recursive copy — **Medium confidence, low stakes** — **[PATCHED — claude/ only]**

> **Patched:** `2607291244-incremental-context-staging-patch.md` — claude/prepare.ps1 converted to `robocopy /MIR`. Magnitude now measured, not structural: cold 22.7s → 3.3s, warm (unchanged tree) 2.1s, output byte-identical (2351 files, 0 manifest diffs). "Low stakes" was wrong — the per-file `Copy-Item` loop was the whole cost. `codex/prepare.ps1` (61M, the larger suite) still open.

[pi/prepare.ps1](pi/prepare.ps1): walk 1 = recursive per-file `Copy-ItemFiltered`; walk 2 = CRLF normalize ([:107](pi/prepare.ps1:107)); walk 3 = credential rescan ([:117](pi/prepare.ps1:117)). For pi/cursor (tiny trees) irrelevant; for claude (39M) / codex (61M) with thousands of small files, `robocopy /MIR /XD ... /XF ...` for the copy + one combined post-walk would cut prepare from tens of seconds to seconds. Only worth doing in the big suites, and only if prepare latency actually annoys (unmeasured — Low confidence on magnitude).

### F8 — run.ps1 startup: bakeable bootstrap steps — **High confidence, small**

Every container start runs `sudo chown` ×3 + `pnpm config set store-dir` ([pi/run.ps1:158](pi/run.ps1:158)). The pnpm store-dir is static — bake `ENV PNPM_HOME`/`pnpm config set store-dir` (or a system `.npmrc`) into the image as the agent user; drop from bootstrap. Chowns must stay (fresh named volumes mount root:root) but could be guarded (`[ -O dir ] ||`) to skip sudo on warm volumes. `codegraph init` on a cold workspace blocks pi startup for the graph build; `;`-chaining already tolerates failure — consider backgrounding it (`codegraph init >/dev/null 2>&1 &`) so first launch isn't gated on it. Minor code cleanup: sessions-hash and nm-hash blocks duplicate the same SHA-256-of-workspace computation ([:81](pi/run.ps1:81), [:96](pi/run.ps1:96)) — one helper.

### F9 — Tar → retag → load chain has a cheaper shape — **Medium confidence**

`retag-tar.ps1` exists only because `podman save` of a bare name writes `localhost/<image>` into the manifest, and fixing it costs a transient alpine container rewriting a multi-GB tar. Cheaper: `podman tag <image> docker.io/library/<image>` (or any qualified name) *before* save, and save the qualified ref — manifest comes out clean, retag-tar becomes dead code. **Verify** the qualified-save behavior on the podman version in use before deleting the script.

## Evidence Log

| # | Finding | Source | Type | Conf |
|---|---------|--------|------|------|
| 1 | COPY precedes pi-install layers | pi/Dockerfile:196,209-212 | Primary | H |
| 2 | Monolithic layer 1 uses PI_VERSION | pi/Dockerfile:83-105 | Primary | H |
| 3 | build.ps1 diffs = names only; opencode delta = CRLF (`file` shows CRLF vs LF) | `diff -w`, `file` output | Primary | H |
| 4 | retag-tar: 2 identical, 2 whitespace-only vs pi | `diff` output | Primary | H |
| 5 | 3 suites FROM bookworm-slim, same tool stack | pi/Dockerfile:52, cursor/opencode Dockerfile headers | Primary | H |
| 6 | apt lists not purged in browser layers | pi/Dockerfile:119-129 | Primary | H |
| 7 | pnpm unpinned | pi/Dockerfile:96 | Primary | H |
| 8 | prepare = 3 tree walks | pi/prepare.ps1:51-132 | Primary | H |
| 9 | .dockerignore excludes tars in all suites | pi/.dockerignore + ls | Primary | H |
| 10 | per-start pnpm config + chowns | pi/run.ps1:158 | Primary | H |
| 11 | pi install works on empty config dir | not yet tested | — | M (assumption) |

## Criteria Assessment

| Criterion | Score | Levers |
|-----------|-------|--------|
| Incremental rebuild latency | **Weak** | F1 + F2 fix the two dominant cache-bust paths |
| Cold-build time | Adequate | F4 (shared base), F6 (cache mounts) |
| Image/disk size | Adequate | F5 (apt lists), F4 (layer sharing ×3) |
| Startup latency | Adequate | F8 — already mostly one-time-per-volume costs |
| Maintainability | **Weak** | F3 — ×5 copies with observed drift |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `pi install` fails without staged config (F1 reorder) | Low | Low | test one build; fallback: COPY a minimal settings.json first |
| Shared base image (F4) version skew vs per-suite audits | Med | Med | keep pinned ARGs in base; suites pin base tag |
| Script dedup (F3) breaks a suite-specific edge case | Low | Med | shims + run each suite's build once post-refactor |
| Qualified-tag save (F9) behaves differently across podman versions | Med | Low | keep retag-tar until verified |

## Recommendations

**Immediate (pi-local, low risk):**
1. F1 — reorder pi installs before host-context COPY (verify empty-config install).
2. F2 — split layer 1 by change frequency.
3. F5 — apt-list cleanup ×2 layers; pin pnpm.

**Short-term (repo-wide):**
4. F3 — hoist build/retag to `common/`, add `.gitattributes` line-ending policy, extract shared run/prepare helpers to `common/lib.ps1`.
5. F8 — bake pnpm store-dir; guard chowns; consider backgrounding `codegraph init`.

**Longer-term:**
6. F4 — shared debian base image for opencode/cursor/pi.
7. F6/F7/F9 — cache mounts, prepare single-pass for claude/codex, retag-via-tag-before-save. Do only if the pain is felt after 1–6.

## Open Questions

- [ ] Does `pi install` succeed in an image with an empty `~/.pi/agent`? (gates F1)
- [ ] Podman version in use — cache-mount support (F6) and qualified-name save behavior (F9)?
- [ ] Actual measured build times per suite (all magnitude claims here are structural, not benchmarked)?
- [ ] Do the other 4 Dockerfiles share F5's un-cleaned apt-list layers? (claude has same layer shape — likely yes)

## Appendix

**Method:** primary-source read of all 3 pi scripts + pi/Dockerfile; structural scan of claude/Dockerfile; cross-suite `diff`/`wc`/`file` comparison; no builds executed, no timing measured. Constraint Mapping lens drove F4 (which constraints are real — sbx base for claude/codex — vs incidental — no shared base for the debian trio). Sensitivity lens drove F1/F2 prioritization (what change frequency dominates cache behavior).
**Dissent:** the ×5 copy layout has a real upside — each suite is fully self-contained and copy-paste bootstrappable; dedup (F3) trades that for a `common/` dependency. If self-containment is a deliberate design value, do F3 as thin shims, not full extraction.
