# Migrate pi/ and cursor/ onto the Shared Base Image

> **Status:** Ready
> **Created:** 2026-07-27
> **Author:** agent (Claude)
> **Source:** Direct request ← F4 of 2607271757-prepare-build-run-optimization-eval.md
> **Related Projex:** 2607271806-sbx-base-image-suite-plan.md (provider) | 2607271808-opencode-base-migration-plan.md (sibling, opencode scope) | 2607271757-prepare-build-run-optimization-eval.md
> **Worktree:** Yes

---

## Summary

Rebase `pi/Dockerfile` and `cursor/Dockerfile` from `debian:bookworm-slim` onto `localhost/sbx-base:v1` (built per 2607271806): delete all shared layers (apt/Node/tools/browsers/Go/Python/git-config/rm-guard/user), keep only agent install + config bake. Update both `build.ps1` to require the base image and drop language selectors. Delete both suites' now-unused `rm-guard/` dirs.

**Scope:** `pi/` + `cursor/` only (both root-projex-governed). opencode is the sibling plan (own scope).
**Estimated Changes:** 6 files edited (2 Dockerfiles, 2 build.ps1, 2 READMEs), 2 dirs deleted (rm-guard ×2).

---

## Objective

### Problem / Gap / Need

Both suites duplicate the entire shared stack the base now provides (eval F4): browser layers stored per-suite, cold builds repeat ~everything, pins maintained per-suite.

### Success Criteria

- [ ] `pi/build.ps1` and `cursor/build.ps1` build successfully against `localhost/sbx-base:v1`
- [ ] pi image: `pi --version` OK as agent; 4 pi packages present (`ls ~/.pi/agent/npm`); skills stubs present
- [ ] cursor image: `agent --version` OK; `~/.cursor` context present
- [ ] Both images: rm-guard still blocks `/workspace/.git` delete (inherited from base); `go version` + `python3 --version` OK (inherited)
- [ ] `podman history` on each suite image shows base layers shared (same layer IDs as sbx-base)
- [ ] Building either suite with `-Enable`/`-Disable` fails with a message pointing at `base/build.ps1`
- [ ] Missing base image → build fails fast with actionable message (not mid-Dockerfile)

### Out of Scope

- opencode migration (2607271808 — its own projex scope)
- Eval F1/F2 reorder inside pi (installs-before-COPY) — migration is behavior-preserving; layer order within the suite remainder is kept as-is
- run.ps1 / prepare.ps1 (unaffected: image contract — user/paths/tools — unchanged)
- claude/codex

---

## Context

### Current State

- `pi/Dockerfile:52-192` = shared stack (now in base) + pi-specific: npm install of pi in layer 1 (`pi/Dockerfile:97-98`), context COPY :196, 4 × `pi install` :209-212, skills stubs :216,221, `CMD ["pi"]`.
- `cursor/Dockerfile:30-155` = shared stack; cursor-specific: installer as agent user :166-167, `ENV PATH` :169, context COPY :171, skills stub :175, `CMD ["agent"]`.
- Both `build.ps1` identical machinery; `-Supported @('go','python')` at line 76.
- Working tree note: `pi/README.md` + `pi/run.ps1` are dirty on main (unrelated edits) — worktree mode isolates this plan from them; run.ps1 is untouched by this plan anyway.

### Key Files

| File | Role | Change Summary |
|------|------|----------------|
| `pi/Dockerfile` | pi suite image | `FROM ${BASE_IMAGE}`; delete shared layers; keep pi install + config/package layers |
| `cursor/Dockerfile` | cursor suite image | same shape; keep installer/context layers |
| `pi/build.ps1`, `cursor/build.ps1` | build drivers | +`-BaseImage` param + existence pre-check + `--build-arg BASE_IMAGE`; selectors → error pointing at base |
| `pi/rm-guard/`, `cursor/rm-guard/` | now provided by base | delete (del-n-stage) |
| `pi/README.md`, `cursor/README.md` | docs | Prerequisites += base image; Build section reworked; optional-languages section → pointer to base/README.md |

### Dependencies

- **Requires:** 2607271806 executed — `localhost/sbx-base:v1` buildable and its contract stable (ends `USER agent`, `WORKDIR /home/agent`, `ENTRYPOINT tini`, tools on PATH).
- **Blocks:** nothing.

### Constraints

- Behavior-preserving: final image contents must be functionally identical to today's (same tools, same paths, same user model) — only provenance of layers changes.
- pi's npm install keeps `--ignore-scripts` + `PI_VERSION=0.80.9` pin (audit 2607171400); pi package pins unchanged (audits 2607171500-03).
- cursor's installer stays unpinned-by-design (documented in its README "Notes").

### Assumptions

- Base name resolution: with podman, `FROM localhost/sbx-base:v1` hits the local store. With `-Engine docker`, default `-BaseImage` becomes `sbx-base:v1` (docker's local-name resolution; no `localhost/` prefix). Verify both on first build.
- `npm install -g` of pi works FROM the base (root, npm present) exactly as it did in layer 1 today.
- Deleting suite rm-guard dirs breaks nothing else: `grep -r rm-guard <suite>/` shows only Dockerfile + the dir itself (verify at execution).

### Impact Analysis

- **Direct:** the 6 files + 2 dirs above.
- **Adjacent:** run.ps1 bootstrap expects sudo/agent/pnpm/codegraph — all inherited from base unchanged.
- **Downstream:** `.dockerignore` untouched (context/ still suite-local). Tar/retag/load flows unchanged.

---

## Implementation

### Overview

Per suite: rewrite Dockerfile head to consume base, delete shared blocks, wire `BASE_IMAGE` through build.ps1, delete rm-guard dir, update README. pi first (richer suite), cursor second (simpler), then joint verification.

### Step 1: `pi/Dockerfile` onto base

**Objective:** pi image = base + pi.
**Confidence:** High
**Depends on:** None (base exists per plan dependency)

**Files:** `pi/Dockerfile`

**Changes:**

```dockerfile
// Before (structure):
FROM debian:bookworm-slim
USER root
ARG NODE_MAJOR=25 / PI_VERSION=0.80.9 / CODEGRAPH_VERSION / AGENT_BROWSER_VERSION /
    PLAYWRIGHT_VERSION / GO_VERSION / INSTALL_GO / INSTALL_PYTHON / PI_*_VERSION ×4 / CONTEXT_MODE_VERSION
RUN <apt+NodeSource+node+build-essential+pnpm + npm -g pi/codegraph/agent-browser/playwright>   # :83-105
RUN <useradd agent>                                                                             # :110-112
RUN <agent-browser install>                                                                     # :119-121
RUN <playwright install chromium>                                                               # :128-129
RUN <optional Go> / RUN <optional Python>                                                       # :133-158
RUN <git config> / COPY+RUN <rm-guard>                                                          # :163-191
USER agent / WORKDIR /home/agent
COPY context/.pi/agent/ … / RUN pi install ×4 / COPY skills ×2
ENTRYPOINT tini / CMD ["pi"]

// After:
ARG BASE_IMAGE=localhost/sbx-base:v1
FROM ${BASE_IMAGE}
# base provides: Node25, pnpm, codegraph/agent-browser/playwright(+browsers),
# optional Go/Python, agent user, git config, rm-guard, tini ENTRYPOINT.
# See base/README.md and .projex/2607271806-sbx-base-image-suite-plan.md.

USER root
# Pinned per .projex/2607171400-pi-coding-agent-install-audit.md (>=0.78.1).
ARG PI_VERSION=0.80.9
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" \
 && pi --version

ARG PI_SUBAGENTS_VERSION=0.14.1
ARG PI_CURSOR_SDK_VERSION=0.1.59
ARG PI_WEB_ACCESS_VERSION=0.13.0
ARG CONTEXT_MODE_VERSION=1.0.169

USER agent
WORKDIR /home/agent

COPY --chown=agent:agent context/.pi/agent/ /home/agent/.pi/agent/
RUN pi install "npm:@tintinweb/pi-subagents@${PI_SUBAGENTS_VERSION}"
RUN pi install "npm:pi-cursor-sdk@${PI_CURSOR_SDK_VERSION}"
RUN pi install "npm:pi-web-access@${PI_WEB_ACCESS_VERSION}"
RUN pi install "npm:context-mode@${CONTEXT_MODE_VERSION}"
COPY --chown=agent:agent skills/agent-browser/ /home/agent/.pi/agent/skills/agent-browser/
COPY --chown=agent:agent skills/codegraph/    /home/agent/.pi/agent/skills/codegraph/

CMD ["pi"]
```

Preserve the suite-specific explanatory comments from today's :196-221 region (COPY/pi-install rationale, no-MCP note) — only the shared-stack comments/layers go. ENTRYPOINT not restated (inherited).

**Rationale:** minimal remainder; layer order within the remainder unchanged (F1 reorder is out of scope).
**Verification:** Step 5.
**If this fails:** `git checkout -- pi/Dockerfile` (worktree branch).

### Step 2: `cursor/Dockerfile` onto base

**Objective:** cursor image = base + cursor-agent.
**Confidence:** High
**Depends on:** None

**Files:** `cursor/Dockerfile`

**Changes:**

```dockerfile
// Before: FROM debian:bookworm-slim … <same shared stack, :30-155> … USER agent / WORKDIR
RUN curl -fsS https://cursor.com/install | bash && ~/.local/bin/agent --version   # :166-167
ENV PATH="/home/agent/.local/bin:${PATH}"
COPY context/.cursor/ + skills stub / ENTRYPOINT / CMD ["agent"]

// After:
ARG BASE_IMAGE=localhost/sbx-base:v1
FROM ${BASE_IMAGE}
# base contract: see base/README.md. Ends USER agent, WORKDIR /home/agent —
# exactly what the installer below needs ($HOME=/home/agent, no chown).

RUN curl -fsS https://cursor.com/install | bash \
 && ~/.local/bin/agent --version

ENV PATH="/home/agent/.local/bin:${PATH}"

COPY --chown=agent:agent context/.cursor/ /home/agent/.cursor/
COPY --chown=agent:agent skills/agent-browser/ /home/agent/.cursor/skills/agent-browser/

CMD ["agent"]
```

Keep the installer's existing comment block (:161-165). No `USER root` needed anywhere.

**Rationale:** cursor is the cleanest consumer — agent-user installer meets the base's ending state directly.
**Verification:** Step 5.
**If this fails:** `git checkout -- cursor/Dockerfile`.

### Step 3: build.ps1 wiring (both suites)

**Objective:** base-aware build drivers.
**Confidence:** High
**Depends on:** Steps 1-2

**Files:** `pi/build.ps1`, `cursor/build.ps1`

**Changes (identical edit in both, modulo suite name in messages):**

1. Add param: `[string]$BaseImage = ''  # default resolved per -Engine below`
2. After engine PATH check, insert:

```powershell
# Resolve + verify the shared base image (see base/README.md).
if (-not $BaseImage) {
    $BaseImage = if ($Engine -eq 'docker') { 'sbx-base:v1' } else { 'localhost/sbx-base:v1' }
}
& $Engine image inspect $BaseImage *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Base image '$BaseImage' not found in $Engine. Build it first: ../base/build.ps1 [-Engine $Engine], or pass -BaseImage."
}
```

3. Replace the `Resolve-LanguageSelection` call (line 76) and its function + the `INSTALL_*` build-arg loop + the `optional languages:` echo with:

```powershell
if ($PSBoundParameters.ContainsKey('Enable') -or $PSBoundParameters.ContainsKey('Disable')) {
    throw 'Optional languages are baked into the shared base image - use ../base/build.ps1 -Enable/-Disable and rebuild the base instead.'
}
```

Keep the `-Enable`/`-Disable` params declared (discoverability of the error).

4. Add to `$buildArgs` (where the INSTALL_* loop was): `$buildArgs += @('--build-arg', "BASE_IMAGE=$BaseImage")`

**Rationale:** fail-fast beats a mid-build FROM error; engine-conditional default handles podman's `localhost/` store prefix vs docker's bare local names.
**Verification:** `./pi/build.ps1 -Enable go` → base-pointer error; missing base → actionable error; normal build passes BASE_IMAGE.
**If this fails:** `git checkout -- <suite>/build.ps1`.

### Step 4: delete rm-guard dirs + README updates

**Objective:** remove now-dead files; document the new prerequisite.
**Confidence:** High
**Depends on:** Steps 1-3

**Files:** `pi/rm-guard/rm-guard.sh`, `cursor/rm-guard/rm-guard.sh` (delete); `pi/README.md`, `cursor/README.md` (edit)

**Changes:**
- Verify no other references first: `grep -rn "rm-guard" pi/ cursor/` → expect only README mentions (update wording to "provided by the shared base — see base/README.md") — then `del-n-stage` both `rm-guard/rm-guard.sh` files.
- READMEs: Prerequisites section += "shared base image (`../base/build.ps1`) built into the engine's local store"; Build section: note `-BaseImage` override + engine-default names; replace "Optional language features" body with pointer to `base/README.md`; pi/README's dirty working-tree edits are preserved (worktree merge at close).

**Verification:** `grep -rn "rm-guard" pi/ cursor/` → README prose only; `git status` shows the deletions staged.
**If this fails:** `git checkout -- <paths>` restores.

### Step 5: build + smoke both suites

**Objective:** prove parity with today's images.
**Confidence:** Medium (first consumer builds)
**Depends on:** Steps 1-4

**Changes:** none (execution):

```powershell
./base/build.ps1                                        # ensure base present
./pi/build.ps1     -Image pi-custom:v1
./cursor/build.ps1 -Image cursor-custom:v1
podman run --rm localhost/pi-custom:v1 sh -lc 'pi --version; ls ~/.pi/agent/npm; ls ~/.pi/agent/skills; go version; python3 --version; mkdir -p /tmp/w/.git && cd /tmp/w && echo h > .git/HEAD; whoami'
podman run --rm localhost/cursor-custom:v1 sh -lc 'agent --version; ls ~/.cursor; go version; codegraph --version'
podman history localhost/pi-custom:v1 | head          # shared layer IDs vs sbx-base
```

Plus rm-guard runtime check in one suite container: `rm -rf /workspace/.git` against a bind-mounted scratch git dir → blocked.

**Verification:** all checks pass; history shows base layers reused.
**If this fails:** the failing binary/path identifies which contract item diverged — fix in base (revise 2607271806 via revise-projex) or in the suite remainder here.

---

## Verification Plan

### Automated Checks
- [ ] Both suite builds exit 0 against the base
- [ ] Smoke matrices (Step 5) pass
- [ ] Selector misuse + missing-base produce the designed errors

### Manual Verification
- [ ] `podman history` layer sharing confirmed
- [ ] `git status`: only the 8 intended paths changed
- [ ] pi's unrelated dirty README/run.ps1 edits on main untouched

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected |
|-----------|--------------|----------|
| Behavior parity | Step 5 smoke | identical tool availability vs pre-migration image |
| Layer sharing | podman history | base layer IDs present in both suite images |
| Guardrails intact | rm-guard runtime check | delete blocked |
| Fail-fast UX | build without base | actionable throw |

---

## Rollback Plan

Worktree branch — abandon via `projex-abandon`. Post-merge revert: `git revert` the squash commit; suite images rebuild standalone from the reverted Dockerfiles (base image can stay in the store harmlessly).

---

## Notes

### Risks
- **docker-engine FROM resolution differs** (localhost/ prefix): mitigated by engine-conditional default + `-BaseImage` escape hatch; verify on first docker build.
- **Hidden reliance on a deleted shared-layer side effect** (e.g. a path only created by a removed RUN): smoke matrix covers tool paths; anything missed → fix-forward in base contract.

### Open Questions
- [ ] none
