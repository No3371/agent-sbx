# Migrate opencode/ onto the Shared Base Image

> **Status:** Ready
> **Created:** 2026-07-27
> **Author:** agent (Claude)
> **Source:** Direct request ← F4 of 2607271757-prepare-build-run-optimization-eval.md (root .projex)
> **Related Projex:** 2607271806-sbx-base-image-suite-plan.md (provider, root .projex) | 2607271807-pi-cursor-base-migration-plan.md (sibling, root .projex)
> **Worktree:** Yes

---

## Summary

Rebase `opencode/Dockerfile` from `debian:bookworm-slim` onto `localhost/sbx-base:v1` (contract: 2607271806): delete the shared layers, keep only the opencode install + config bake. Wire `-BaseImage` through `opencode/build.ps1`, drop language selectors, delete `opencode/rm-guard/`. Split from the pi/cursor sibling plan solely because `opencode/` is its own projex scope.

**Scope:** `opencode/` only.
**Estimated Changes:** 3 files edited (Dockerfile, build.ps1, README.md), 1 dir deleted (rm-guard/).

---

## Objective

### Problem / Gap / Need

opencode duplicates the entire shared stack now provided by the base (eval F4, root .projex): browser layers stored per-suite, cold builds repeat everything, pins maintained locally.

### Success Criteria

- [ ] `opencode/build.ps1` builds against `localhost/sbx-base:v1`
- [ ] Image: `opencode --version` = 1.18.3 as agent; `~/.config/opencode` context + agent-browser skill stub present
- [ ] Inherited: `go version`, `python3 --version`, `codegraph --version` OK; rm-guard blocks `/workspace/.git` delete
- [ ] `podman history` shows base layer IDs shared
- [ ] `-Enable`/`-Disable` → error pointing at `base/build.ps1`; missing base → fail-fast actionable error

### Out of Scope

- Base image itself (2607271806) | pi/cursor (2607271807) | opencode run.ps1/prepare.ps1 (image contract unchanged) | claude/codex

---

## Context

### Current State

`opencode/Dockerfile:20-160` = shared stack (identical modulo comments to pi/cursor — verified by diff during eval research). opencode-specific: `opencode-ai@${OPENCODE_VERSION}` npm-installed in layer 1 (`opencode/Dockerfile:56-57`, WITHOUT `--ignore-scripts`), context COPY :163, skills stub :167, `CMD ["opencode"]` :170. `build.ps1:76` `-Supported @('go','python')`.

### Key Files

| File | Role | Change Summary |
|------|------|----------------|
| `opencode/Dockerfile` | suite image | `FROM ${BASE_IMAGE}`; keep opencode install + config layers only |
| `opencode/build.ps1` | build driver | +`-BaseImage` + existence pre-check + `--build-arg BASE_IMAGE`; selectors → base-pointer error |
| `opencode/rm-guard/` | provided by base now | delete (del-n-stage) |
| `opencode/README.md` | docs | Prerequisites += base; languages section → pointer to base/README.md |

### Dependencies

- **Requires:** 2607271806 executed (`localhost/sbx-base:v1` available; contract: ends `USER agent`, `WORKDIR /home/agent`, `ENTRYPOINT tini`; Node/pnpm/tool trio/Go/Python/git-config/rm-guard baked).
- **Blocks:** nothing.

### Constraints

- Behavior-preserving; `OPENCODE_VERSION=1.18.3` pin kept.
- opencode install keeps today's script-execution behavior (no `--ignore-scripts` — only the base's tool trio adopted that; do not silently change the agent install).

### Assumptions

- `FROM localhost/sbx-base:v1` resolves in podman local store; docker engine uses bare `sbx-base:v1` default (same engine-conditional as sibling plan).
- `npm install -g opencode-ai` behaves identically when run in its own layer FROM the base (root, same npm) as it did inside the old combined layer.
- `grep -rn "rm-guard" opencode/` at execution shows only Dockerfile + dir + README prose.

### Impact Analysis

- **Direct:** the 4 paths above.
- **Adjacent:** opencode run.ps1 bootstrap (chown/sudo/pnpm/codegraph) — all inherited unchanged.
- **Downstream:** none; tar/retag/load flows unchanged.

---

## Implementation

### Overview

Same migration shape as the sibling plan's pi step, adapted to opencode's layout. Single-suite, 4 steps.

### Step 1: `opencode/Dockerfile` onto base

**Objective:** opencode image = base + opencode.
**Confidence:** High
**Depends on:** None

**Files:** `opencode/Dockerfile`

**Changes:**

```dockerfile
// Before (structure): FROM debian:bookworm-slim / USER root / ARGs ×8
// RUN <apt+NodeSource+node+build-essential+pnpm + npm -g opencode/codegraph/agent-browser/playwright>  # :43-66
// RUN <useradd> / <agent-browser> / <playwright> / <Go> / <Python> / <git config> / <rm-guard>          # :70-158
// USER agent / WORKDIR / COPY context + skills stub / ENTRYPOINT / CMD ["opencode"]

// After:
ARG BASE_IMAGE=localhost/sbx-base:v1
FROM ${BASE_IMAGE}
# base provides Node25, pnpm, codegraph/agent-browser/playwright(+browsers),
# optional Go/Python, agent user, git config, rm-guard, tini ENTRYPOINT.
# See base/README.md.

USER root
ARG OPENCODE_VERSION=1.18.3
# No --ignore-scripts: preserves the historical install behavior for the agent
# binary itself (only the base's shared tool trio adopted --ignore-scripts).
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
 && opencode --version

USER agent
WORKDIR /home/agent

COPY --chown=agent:agent context/.config/opencode/ /home/agent/.config/opencode/
COPY --chown=agent:agent skills/agent-browser/ /home/agent/.config/opencode/skills/agent-browser/

CMD ["opencode"]
```

Preserve today's suite-specific comments around the context COPY/skills stub; drop shared-stack comments with their layers. ENTRYPOINT inherited.

**Verification:** Step 4.
**If this fails:** `git checkout -- opencode/Dockerfile`.

### Step 2: `opencode/build.ps1` wiring

**Objective:** base-aware driver.
**Confidence:** High
**Depends on:** Step 1

**Files:** `opencode/build.ps1`

**Changes:** identical to sibling plan Step 3 (see 2607271807 for the exact three code blocks):
1. `[string]$BaseImage = ''` param;
2. engine-conditional default (`docker` → `sbx-base:v1`, else `localhost/sbx-base:v1`) + `image inspect` fail-fast throw;
3. selectors (`-Enable`/`-Disable` bound) → `throw 'Optional languages are baked into the shared base image - use ../base/build.ps1 -Enable/-Disable and rebuild the base instead.'`; remove `Resolve-LanguageSelection` function + call + `INSTALL_*` build-arg loop + `optional languages:` echo;
4. `$buildArgs += @('--build-arg', "BASE_IMAGE=$BaseImage")`.

**Verification:** selector misuse + missing-base errors fire; normal build passes the arg.
**If this fails:** `git checkout -- opencode/build.ps1`.

### Step 3: delete rm-guard + README

**Objective:** remove dead files; document prerequisite.
**Confidence:** High
**Depends on:** Steps 1-2

**Files:** `opencode/rm-guard/rm-guard.sh` (delete), `opencode/README.md` (edit)

**Changes:** `grep -rn "rm-guard" opencode/` first (expect Dockerfile-was + README prose only) → `del-n-stage`. README: Prerequisites += base image build step; `-BaseImage` documented; optional-languages body → pointer to `base/README.md`; rm-guard mention → "provided by the shared base".

**Verification:** grep clean; deletions staged.
**If this fails:** `git checkout --` restores.

### Step 4: build + smoke

**Objective:** parity proof.
**Confidence:** Medium
**Depends on:** Steps 1-3

**Changes:** none (execution):

```powershell
./opencode/build.ps1 -Image opencode-custom:v1
podman run --rm localhost/opencode-custom:v1 sh -lc 'opencode --version; ls ~/.config/opencode; go version; python3 --version; codegraph --version; whoami'
podman history localhost/opencode-custom:v1 | head
```

Plus rm-guard runtime check against a bind-mounted scratch git dir → blocked.

**Verification:** all pass; base layer IDs shared.
**If this fails:** divergent item → fix in suite remainder here, or base contract via revise of 2607271806.

---

## Verification Plan

### Automated Checks
- [ ] Build exits 0 against base
- [ ] Smoke matrix passes
- [ ] Designed errors fire (selectors, missing base)

### Manual Verification
- [ ] `podman history` layer sharing
- [ ] `git status`: only the 4 intended paths

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected |
|-----------|--------------|----------|
| Behavior parity | Step 4 smoke | tool availability identical to pre-migration |
| Layer sharing | podman history | base layer IDs present |
| Guardrails | rm-guard check | delete blocked |

---

## Rollback Plan

Worktree branch — abandon via `projex-abandon`. Post-merge: revert the squash commit; suite rebuilds standalone.

---

## Notes

### Risks
- Same as sibling plan: docker-engine FROM name resolution (escape hatch: `-BaseImage`); hidden reliance on a deleted layer's side effect (smoke matrix + fix-forward).

### Open Questions
- [ ] none
