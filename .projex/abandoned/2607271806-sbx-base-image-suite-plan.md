# Shared Base Image Suite (`base/`) for Debian-Based Sandbox Templates

> **Status:** Ready
> **Reviewed:** 2026-08-02 — 2608022303-sbx-base-image-suite-review.md — Verdict: Abandon
> **Created:** 2026-07-27
> **Author:** agent (Claude)
> **Source:** Direct request ← F4 of 2607271757-prepare-build-run-optimization-eval.md
> **Related Projex:** 2607271757-prepare-build-run-optimization-eval.md | 2607271807-pi-cursor-base-migration-plan.md (consumer) | 2607271808-opencode-base-migration-plan.md (consumer)
> **Worktree:** Yes

---

## Summary

Create a new `base/` suite: one shared foundation image (`sbx-base`) holding everything the three debian-based suites (opencode | cursor | pi) currently each rebuild — apt baseline, Node 25, pnpm, codegraph/agent-browser/playwright + browsers, optional Go/Python, agent user, git config, rm-guard. Suites later `FROM` it (separate migration plans). Cuts cold-build time and image storage ~3× for the shared stack.

**Scope:** New files under `base/` only — no existing suite is touched by this plan.
**Estimated Changes:** 4 new files (`base/Dockerfile`, `base/build.ps1`, `base/rm-guard/rm-guard.sh`, `base/README.md`).

**Note (user decision, 2026-07-27):** multi-stage `COPY --from=golang` for Go was considered and dropped — the sandbox bakes the full Go dev environment, so the existing pinned-tarball install is kept verbatim.

---

## Objective

### Problem / Gap / Need

opencode/cursor/pi each `FROM debian:bookworm-slim` and independently install an identical stack (verified by side-by-side diff of the three Dockerfiles; layer bodies match modulo comments, plus 3 small divergences listed under Constraints). The browser layers (~1GB+) are stored 3× with zero layer sharing; cold builds run 3×; version pins (`CODEGRAPH_VERSION` etc.) are maintained in 3 places.

### Success Criteria

- [ ] `base/build.ps1` builds `sbx-base:v1` with podman, default args, exit 0
- [ ] In the built image: `node --version` = v25.x, `pnpm --version`, `codegraph --version` = 1.3.0, `agent-browser --version` = 0.31.1, `playwright --version` = 1.61.1, `go version` = 1.26.3, `python3 --version` all succeed as the `agent` user
- [ ] `base/build.ps1 -Disable go` builds; `go` absent in image
- [ ] rm-guard self-test passes during build (blocks `/workspace/.git` delete)
- [ ] Image ends `USER agent`, `WORKDIR /home/agent`, `ENTRYPOINT tini`
- [ ] No suite file modified

### Out of Scope

- Migrating any suite onto the base (2607271807 / 2607271808)
- claude/ and codex/ (extend `docker/sandbox-templates:*` — cannot share this base)
- Eval F1/F2 layer-reorder work inside pi/Dockerfile
- Cross-suite build.ps1 dedup (`common/` — eval F3)

---

## Context

### Current State

Each of opencode/cursor/pi/Dockerfile: `FROM debian:bookworm-slim` → monolithic apt+NodeSource+npm layer → agent user → agent-browser `--with-deps` → playwright chromium → optional Go (tarball) → optional Python (apt) → git system config → rm-guard install+self-test → `USER agent`. Shared blocks are copy-identical modulo comments; `rm-guard.sh` is md5-identical across the three suites.

### Key Files

| File | Role | Change Summary |
|------|------|----------------|
| `base/Dockerfile` | new — shared foundation image | Extraction of the common layers, 3 deliberate deltas (see Constraints) |
| `base/build.ps1` | new — build driver | pi/build.ps1 minus the prepare stage; keeps Tar/Retag/Load/Push + language selectors |
| `base/rm-guard/rm-guard.sh` | new — copy of the suites' identical guard | Byte-for-byte copy of `pi/rm-guard/rm-guard.sh` |
| `base/README.md` | new — suite doc | Contract: what the base provides, how consumers build on it |

### Dependencies

- **Requires:** nothing (self-contained)
- **Blocks:** 2607271807-pi-cursor-base-migration-plan.md, 2607271808-opencode-base-migration-plan.md

### Constraints

Deliberate deltas vs the per-suite originals (each is a decision, not drift):
1. **ripgrep in apt baseline** — today pi-only (upstream-pi precedent). Included for all: tiny, universally useful.
2. **pnpm pinned + present for all** — today `pnpm@latest` in pi/opencode, absent in cursor (eval F5: only unpinned install in the repo). Base pins via `ARG PNPM_VERSION`; cursor gains pnpm (harmless — its run.ps1 pattern already assumes pm tooling availability via base tools).
3. **`--ignore-scripts` for the npm tool trio** — today pi does this, opencode/cursor don't. Adopted: pi proves the same three packages at the same versions work installed this way (its build's version checks pass), and it's the safer supply-chain default. Browser downloads happen in the later explicit `agent-browser install` / `playwright install` layers regardless.
4. **apt-list cleanup appended to both browser layers** (eval F5 fix — free while authoring fresh).
5. **Layer 1 split in two** (apt+Node vs npm tools) per eval F2 — tool-version bumps no longer re-run apt/NodeSource.

### Assumptions

- `pnpm` pinned version: resolve current stable at execution (`npm view pnpm version`), record in ARG + walkthrough. Latest-stable is acceptable — no audit exists for pnpm today either.
- Engine default remains podman; docker path exercised only via consumers' `-BaseImage` override (see migration plans).
- `tini` from apt (as today) — ENTRYPOINT carried by base; consumers only set `CMD`.

### Impact Analysis

- **Direct:** new `base/` dir only.
- **Adjacent:** none until migration plans run.
- **Downstream:** migration plans depend on the exact contract below (image name, user, WORKDIR, tool paths, ENTRYPOINT). Changing those later means revising both consumer plans.

---

## Implementation

### Overview

Author the four files. The Dockerfile is an extraction: shared layer bodies are taken verbatim from the current suites (pi/Dockerfile:83-192 as reference copy, cross-checked against opencode/cursor) with the five deliberate deltas above.

### Step 1: `base/rm-guard/rm-guard.sh`

**Objective:** stage the shared guard script inside the new suite.
**Confidence:** High
**Depends on:** None

**Changes:** byte-for-byte copy of `pi/rm-guard/rm-guard.sh` (md5 `910b41a6…` — identical in all three suites; verify hash equality after copy).

**Verification:** `md5sum base/rm-guard/rm-guard.sh pi/rm-guard/rm-guard.sh` — equal.
**If this fails:** re-copy; nothing else depends on partial state.

### Step 2: `base/Dockerfile`

**Objective:** the shared foundation image.
**Confidence:** High (all blocks proven in 3 existing builds; only the layer split and cleanups are new)
**Depends on:** Step 1

**Changes:** new file:

```dockerfile
# sbx-base — shared foundation for the debian-based suites (opencode, cursor, pi).
# Everything here was previously duplicated in each suite's Dockerfile; the
# suites now only add their agent + config on top. claude/codex do NOT consume
# this (they must extend docker/sandbox-templates:*).
#
# Deliberate deltas vs the historical per-suite copies:
#   ripgrep for all | pnpm pinned + for all | npm trio with --ignore-scripts |
#   apt-list cleanup in browser layers | apt/Node layer split from npm-tools layer.

FROM debian:bookworm-slim

USER root

ARG NODE_MAJOR=25
ARG PNPM_VERSION=<pin at execution: npm view pnpm version>
# Pinned per .projex/2607081900-codegraph-integration-audit.md
ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
ARG GO_VERSION=1.26.3
ARG INSTALL_GO=1
ARG INSTALL_PYTHON=1

# Apt baseline + Node 25 (NodeSource). Changes ~never — kept separate from the
# npm-tools layer below so tool-version bumps don't re-run apt/NodeSource.
RUN set -eux; \
    for flag in "$INSTALL_GO" "$INSTALL_PYTHON"; do case "$flag" in 0|1) ;; *) echo "INSTALL_* must be 0 or 1" >&2; exit 1 ;; esac; done; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash ca-certificates curl git gnupg jq less openssh-client ripgrep sudo tini tzdata apt-transport-https; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs build-essential; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    node --version | grep -E "^v25\." || { echo "ERROR: expected Node 25, got $(node --version)"; exit 1; }

# Shared npm dev tools. --ignore-scripts: proven by pi's identical trio install;
# browser payloads come from the explicit install layers below, not postinstall.
RUN set -eux; \
    npm install -g "pnpm@${PNPM_VERSION}"; \
    npm install -g --ignore-scripts \
        "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" \
        "agent-browser@${AGENT_BROWSER_VERSION}" \
        "playwright@${PLAYWRIGHT_VERSION}"; \
    codegraph --version; agent-browser --version; playwright --version; pnpm --version

# Non-root agent user (uid 1000). NOPASSWD sudo for run.ps1 volume-chown bootstrap.
RUN useradd --create-home --uid 1000 --shell /bin/bash agent \
 && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
 && chmod 0440 /etc/sudoers.d/agent

# agent-browser: Chrome for Testing + system libs. HOME override lands Chrome in
# the agent's home so it isn't re-downloaded after USER agent.
RUN apt-get update \
 && HOME=/home/agent agent-browser install --with-deps \
 && chown -R agent:agent /home/agent/.agent-browser \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Playwright Chromium + system libs, baked so first `playwright install` isn't
# cold. Runs as root with HOME=/home/agent — chown .cache back to agent.
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Optional Go (official tarball, pinned — apt's golang lags upstream). Full dev
# env baked; multi-stage COPY --from=golang was considered and dropped (user
# decision 2026-07-27 — toolchain, not artifact, is the deliverable).
RUN set -eux; \
    if [ "$INSTALL_GO" = "1" ]; then \
        arch="$(dpkg --print-architecture)"; \
        case "$arch" in \
            amd64) go_arch=amd64 ;; \
            arm64) go_arch=arm64 ;; \
            *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
        esac; \
        curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz" -o /tmp/go.tar.gz; \
        rm -rf /usr/local/go; \
        tar -C /usr/local -xzf /tmp/go.tar.gz; \
        rm -f /tmp/go.tar.gz; \
        ln -sf /usr/local/go/bin/go /usr/local/bin/go; \
        ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt; \
        go version; \
    fi

# Optional Python (apt).
RUN set -eux; \
    if [ "$INSTALL_PYTHON" = "1" ]; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3 python3-pip python3-venv; \
        python3 --version; pip3 --version; \
        apt-get clean; \
        rm -rf /var/lib/apt/lists/*; \
    fi

# Bind-mount ownership + fresh-container git identity. System config is
# lowest-precedence; user/global config set later still wins.
RUN git config --system --add safe.directory '*' \
 && git config --system core.autocrlf input \
 && git config --system user.name 'agent' \
 && git config --system user.email 'agent@sandbox.local'

# rm-guard: shadow coreutils rm; refuses /workspace/.git removal. See
# rm-guard/rm-guard.sh. Self-test fakes /workspace (runtime bind mount).
COPY rm-guard/rm-guard.sh /usr/local/libexec/rm-guard.sh
RUN set -eux; \
    chmod 0755 /usr/local/libexec/rm-guard.sh; \
    real_rm="$(readlink -f "$(command -v rm)")"; \
    cp "$real_rm" /usr/bin/rm.real; \
    ln -sf /usr/local/libexec/rm-guard.sh "$real_rm"; \
    rm --version >/dev/null; \
    mkdir -p /workspace/.git && echo test > /workspace/.git/HEAD; \
    if rm -rf /workspace/.git 2>/dev/null; then echo "ERROR: rm-guard did not block direct delete of /workspace/.git"; exit 1; fi; \
    [ -f /workspace/.git/HEAD ] || { echo "ERROR: /workspace/.git/HEAD missing after a supposedly-blocked delete"; exit 1; }; \
    if rm -rf /workspace 2>/dev/null; then echo "ERROR: rm-guard did not block ancestor delete of /workspace"; exit 1; fi; \
    [ -f /workspace/.git/HEAD ] || { echo "ERROR: /workspace/.git/HEAD missing after a supposedly-blocked ancestor delete"; exit 1; }; \
    touch /tmp/rm-guard-selftest && rm -f /tmp/rm-guard-selftest; \
    [ ! -e /tmp/rm-guard-selftest ] || { echo "ERROR: rm-guard blocked an unprotected delete"; exit 1; }; \
    /usr/bin/rm.real -rf /workspace

USER agent
WORKDIR /home/agent

ENTRYPOINT ["tini", "--"]
# Consumers override CMD with their agent binary; bash for standalone debugging.
CMD ["bash"]
```

**Rationale:** verbatim extraction maximizes behavior preservation; the five deltas are individually justified (Constraints) and individually revertible.
**Verification:** Step 5 build.
**If this fails:** file is new — delete; no rollback dependencies.

### Step 3: `base/build.ps1`

**Objective:** build driver for the base image.
**Confidence:** High
**Depends on:** Step 2

**Changes:** copy `pi/build.ps1`, then:
- Header comment → base suite wording.
- Remove params `-SkipPrepare`, `-HostPiDir`, `-Destination`; remove the whole `if (-not $SkipPrepare) { … prepare.ps1 … }` block (base has no host context to stage).
- `-Image` default: `[string]$Image = 'sbx-base:v1'` (no longer Mandatory — base has one canonical name; `-Push` users pass a qualified name explicitly).
- Keep `Resolve-LanguageSelection` with `-Supported @('go','python')` — selectors now live HERE for all consumers.
- Keep `-Tar/-Retag/-LoadToDocker/-LoadToPodman/-Push` machinery unchanged (needed to move the base into Docker's store for docker-engine consumers).
- Final hint lines → `Next: consume via <suite>/build.ps1 (FROM localhost/sbx-base:v1)`.

**Rationale:** same UX as every other suite's build script; language choice moves to the only image that still contains language layers.
**Verification:** `pwsh -NoProfile -Command "& ./base/build.ps1 -?"` parses; Step 5 executes it.
**If this fails:** file is new — delete.

### Step 4: `base/README.md`

**Objective:** document the contract consumers rely on.
**Confidence:** High
**Depends on:** Steps 2-3

**Changes:** new file covering: what the base provides (tool list + versions table mirroring the ARGs) | the consumer contract (image name `localhost/sbx-base:v1`; podman stores bare-name builds under `localhost/`; ends `USER agent`, `WORKDIR /home/agent`, `ENTRYPOINT tini`, `CMD bash`; consumers set `CMD`, may `USER root` temporarily for root installs) | build instructions incl. `-Enable/-Disable go|python` | docker-engine path (`-Tar x -LoadToDocker` or build with `-Engine docker`) | the five deliberate deltas | pointer to the two migration plans.

**Verification:** proofread against Dockerfile ARGs — versions table matches.
**If this fails:** doc-only; fix in place.

### Step 5: Build verification

**Objective:** prove the image and its toggles.
**Confidence:** Medium (first real build of the extraction; browser layers are network-heavy)
**Depends on:** Steps 1-4

**Changes:** none (execution only):

```powershell
./base/build.ps1                             # default: go+python on
podman run --rm localhost/sbx-base:v1 sh -lc 'node --version; pnpm --version; codegraph --version; agent-browser --version; playwright --version; go version; python3 --version; whoami; pwd'
./base/build.ps1 -Image sbx-base:nogo-test -Disable go
podman run --rm localhost/sbx-base:nogo-test sh -lc '! command -v go && echo GO-ABSENT-OK'
podman rmi localhost/sbx-base:nogo-test
```

**Verification:** all version checks succeed as `agent` in `/home/agent`; nogo variant lacks `go`.
**If this fails:** diagnose failing layer against the originating suite's identical layer (which builds today); fix Dockerfile; `-NoCache` only for the failing layer's inputs.

---

## Verification Plan

### Automated Checks
- [ ] Step 5 default build exits 0; rm-guard self-test passed within it
- [ ] In-container tool matrix (Step 5 run line) all succeed
- [ ] `-Disable go` variant builds and lacks `go`

### Manual Verification
- [ ] `git status` shows only new `base/` files — no suite modified
- [ ] README versions table == Dockerfile ARGs

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected |
|-----------|--------------|----------|
| Base builds | Step 5 | exit 0 |
| Tool matrix | in-container run | all versions print |
| Language toggle | nogo build | `go` absent |
| Contract surface | `podman inspect` Config | User=agent, WorkingDir=/home/agent, Entrypoint=tini |

---

## Rollback Plan

All-new files; abandoning = delete `base/` and `podman rmi localhost/sbx-base:v1`. No suite behavior can regress — nothing existing is touched.

---

## Notes

### Risks
- **pnpm pin unknown until execution:** resolve then; record in walkthrough. Mitigation: any current stable works — nothing in the base depends on a pnpm feature.
- **`--ignore-scripts` delta surprises opencode/cursor tooling later:** trio is identical to pi's proven install; caught in migration-plan smoke tests, and delta #3 is independently revertible.
- **Base image drifts from suite expectations before migrations run:** migrations reference this plan's contract section; execute them soon after.

### Open Questions
- [ ] none
