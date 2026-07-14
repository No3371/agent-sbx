# Swap OpenCode base → glibc, install opencode at build time

> **Status:** In Progress
> **Created:** 2026-07-14
> **Author:** agent (opus)
> **Source:** Direct request — "Follow the pattern of claude/codex suite, replace opencode official image with a base image with better compatibility and install opencode at build time"
> **Related Projex:** 2607110159-opencode-suite-port-plan.md | 2607110210-opencode-suite-port-plan-redteam.md | 2607111343-opencode-suite-port-audit.md | 2607081900-codegraph-integration-audit.md | 2607100834-language-build-feature-flags-audit.md
> **Worktree:** Yes

---

## Summary

Replace `opencode/Dockerfile`'s base — `ghcr.io/anomalyco/opencode` (third-party, Alpine/musl, binary-only, floating `:latest`) — with `debian:bookworm-slim` (glibc), and install the `opencode` CLI itself at build time via `npm i -g opencode-ai@<pinned>`. Mirrors the claude/codex pattern: standard glibc Debian base + NodeSource Node 24 + agent tooling installed by Dockerfile RUN steps. glibc reverses every musl workaround the prior port (2607110159) was forced to carry — agent-browser and playwright get their standard `install --with-deps` flow, codegraph drops its symlink hack, and the pre-existing musl codegraph blocker (`node: not found`) is resolved.

**Scope:** `opencode/` only — `Dockerfile` (rewrite), `skills/agent-browser/SKILL.md` (1 line), `run.ps1` (stale comments), `README.md`. One projex scope.
**Estimated Changes:** 4 files edited; Dockerfile is a near-total rewrite; the other three are small.

---

## Objective

### Problem / Gap / Need

`opencode/Dockerfile` starts `FROM ghcr.io/anomalyco/opencode`:

- **Third-party, binary-only base** — ships only the `opencode` binary + ripgrep, runs as root, Alpine/musl. Everything else (Node, git, agent tooling, language runtimes) is layered on top.
- **Floating, unaudited third-party tag** — pinned as `:latest` on a binary-only third-party image. README documents this as a known gap. The swap moves onto an official, named base tag (`debian:bookworm-slim`) — the same tag-pinning convention claude/codex use. This is a real improvement (off an unaudited third-party `:latest`) but *not* full reproducibility: `bookworm-slim` is itself a rolling tag, still not digest-pinned, so the base layer can drift at the patch level between rebuilds. Only the agent tooling (opencode/codegraph/agent-browser/playwright/Go) is truly version-pinned.
- **musl forces workarounds** — the prior port (2607110159) had to: point agent-browser at Alpine system Chromium via `AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium` (because `agent-browser install` fetches glibc Chrome-for-Testing that won't exec on musl); set `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` (same reason); symlink system node over codegraph's bundled glibc node. The codegraph glibc binary never ran on musl at all (`exec: …/node: not found`, exit 127), leaving that port's "codegraph always present" criterion unverifiable end-to-end (2607111343 audit, independently reproduced).

claude/codex avoid all of this by building on the official `docker/sandbox-templates:{claude-code,codex}` — Debian/glibc bases where every tool installs the standard way. There is **no** `docker/sandbox-templates:opencode` equivalent. "Follow the claude/codex pattern" therefore means: adopt a standard, well-supported glibc base (`debian:bookworm-slim`) and install the `opencode` CLI via its documented npm channel (`opencode-ai`) at build time — not point at a nonexistent official opencode image.

### Success Criteria

- [ ] `opencode/Dockerfile` no longer references `ghcr.io/anomalyco/opencode`; base is `debian:bookworm-slim` (glibc) — an official, named tag, off the unaudited third-party `:latest` binary-only image. (Honest caveat: `bookworm-slim` is itself a rolling tag, *not* digest-pinned — so the base still drifts at the patch level between rebuilds; this matches claude/codex's own tag-pinning convention, it is not full reproducibility. The agent tooling — opencode/codegraph/agent-browser/playwright/Go — *is* truly version-pinned via ARG.)
- [ ] `opencode` CLI is installed at build time via `npm i -g opencode-ai@${OPENCODE_VERSION}` (pinned ARG); `opencode --version` succeeds in the built image.
- [ ] No musl workaround survives: `AGENT_BROWSER_EXECUTABLE_PATH`, `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD`, the `apk add chromium`, and the codegraph `ln -sf … node` symlink hack are all gone.
- [ ] agent-browser and playwright use the standard glibc flow (`agent-browser install --with-deps`, `playwright install --with-deps chromium`), matching claude/codex; both `--version` pass in-build.
- [ ] codegraph installed via plain `npm i -g` (no symlink hack) and `codegraph --version` succeeds — the prior port's musl codegraph blocker resolved.
- [ ] Node 24 (NodeSource) + pnpm-via-corepack present; non-root `agent` user (uid 1000) with NOPASSWD sudo, matching claude/codex.
- [ ] `go`/`python` build toggles still work via the existing `build.ps1 -Enable/-Disable` → `INSTALL_*` build-args (now apt/tarball installs instead of apk); default = both on.
- [ ] `skills/agent-browser/SKILL.md`, `run.ps1` comments, and `README.md` carry no stale Alpine/musl/`AGENT_BROWSER_EXECUTABLE_PATH` claims; README's "floating tag" gap note is removed (now pinned).

### Out of Scope

- **`prepare.ps1`** — its opencode.json MCP Win→Linux path rewrite is base-agnostic (config lives at `~/.config/opencode` on both Alpine and Debian). No change.
- **`build.ps1` toggle mechanism** — passes `INSTALL_GO`/`INSTALL_PYTHON` build-args; the Dockerfile keeps those ARG names, so the driver is unchanged. Only a stale-comment scan (Step 3).
- **Adding a `.NET` toggle** — the prior port excluded .NET because Alpine musl .NET is niche; glibc removes that reason, but adding it is feature expansion beyond this base swap. Noted as future (Notes), not implemented.
- **sbx integration / `Dockerfile.slim`** — none exists for opencode; this stays the plain-docker path. Unchanged.
- **run.ps1 functional logic** (history mount, cache volumes, node_modules mask) — base-agnostic; the paths (`~/.npm`, `~/.pnpm-store`, `~/.cache/opencode`, `~/.local/share/opencode`) exist identically on Debian. Comment-only touch (Step 3).

---

## Context

### Current State

`opencode/Dockerfile` (current working-tree state — note: already carries uncommitted `M` edits vs HEAD from an *unrelated* in-flight Alpine change; **resolve per Step 0 (Pre-Execution) before branching** — worktree-from-HEAD does not absorb them):

- `FROM ghcr.io/anomalyco/opencode` (Alpine 3.24, root, opencode binary only).
- `apk add` baseline (bash, curl, git, jq, openssh-client, sudo, tini, tzdata, …).
- `INSTALL_GO`/`INSTALL_PYTHON` ARGs → conditional `apk add go` / `apk add python3 py3-pip`.
- Node/tooling: `apk add nodejs npm chromium`; `npm i -g corepack`; `corepack enable`; codegraph + agent-browser + playwright via npm; **codegraph symlink hack** (`ln -sf "$(command -v node)" …/codegraph-linux-x64/node`); ENV `AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium` + `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`.
- `adduser -D -u 1000 … agent` (busybox); NOPASSWD sudo; git system config; COPY context + agent-browser skill stub; `ENTRYPOINT ["tini","--"]` / `CMD ["opencode"]`.

**Reference pattern — `codex/Dockerfile`** (the closest analog: Debian base, Node 24 via NodeSource, npm-installed agent tooling, `agent-browser install --with-deps`, `playwright install --with-deps chromium`, HOME-override + chown, git system config). `claude/Dockerfile` adds the Go-official-tarball block (pinned `GO_VERSION`) and python-via-apt this plan reuses.

**opencode install channel** (opencode.ai/docs): documented via install script (`curl … | bash`), Homebrew, and **npm (`opencode-ai`)**. npm chosen — pinnable via ARG (matches suite convention) and Node is already baseline. `opencode-ai@1.17.19` (latest at authoring) publishes per-platform optional deps including `opencode-linux-x64` (glibc) — so on a glibc Debian x64 base npm resolves the glibc binary natively.

### Key Files

| File | Role | Change Summary |
|------|------|----------------|
| `opencode/Dockerfile` | Image build | Base → `debian:bookworm-slim`; install opencode via npm; NodeSource Node 24; create agent user (Debian); standard glibc agent-browser/playwright/codegraph installs; go-tarball + python-apt toggles; drop all musl workarounds |
| `opencode/skills/agent-browser/SKILL.md` | Discovery stub | Line 12: musl/system-Chromium note → glibc baked-Chrome-for-Testing note |
| `opencode/run.ps1` | Plain-docker launcher | Comment-only: "Alpine/musl store" framing (lines ~91-92, ~105) now stale — both suites glibc |
| `opencode/README.md` | Docs | New base description; toggle table (apk→apt/tarball); agent-browser standard install; remove musl caveats; drop floating-tag gap note (now pinned) |

### Dependencies

- **Requires:** podman/docker; build-time network (deb.nodesource.com, npm registry, go.dev, Chrome-for-Testing + playwright CDN, packages for `--with-deps`). Nothing blocks planning.
- **Blocks:** nothing downstream.

### Constraints

- **glibc/Debian now** — use apt + NodeSource + Go-tarball + Chrome-for-Testing (the claude/codex paths), *not* apk/system-Chromium. This is the reverse of the prior port's musl adaptation.
- Preserve suite conventions: pinned tool versions via `ARG` (opencode/codegraph/agent-browser/playwright/Go — never `@latest`), an official named base tag (`debian:bookworm-slim`; note it still floats at patch level, and `pnpm@latest` via corepack floats — both consistent with claude/codex, neither is digest-pinned), non-root `agent` uid 1000 + NOPASSWD sudo, system-level git config as lowest-precedence layer, `tini` entrypoint + `opencode` CMD.
- `debian:bookworm-slim` has no uid-1000 user (unlike `node:*` images, whose `node` user squats uid 1000) — so `useradd --uid 1000 agent` is collision-free. This is a reason to prefer plain Debian + NodeSource over a `node:` base image.
- Keep `run.ps1`/`build.ps1`/`prepare.ps1` functional behavior unchanged — this is a base swap, not a rework of the runtime scripts.

### Assumptions (verify early during execution)

1. **`opencode-ai` npm install yields a runnable glibc binary on `debian:bookworm-slim`.** Verified structurally: package publishes `opencode-linux-x64` optional dep (glibc). Confirm with in-build `opencode --version`. Fallback: the `curl -fsSL https://opencode.ai/install | bash` script (also glibc) if the npm bin wrapper misbehaves.
2. **`agent-browser install --with-deps` and `playwright install --with-deps chromium` succeed on `bookworm-slim`.** They succeed on the sandbox-templates Debian base (claude/codex, audited); `--with-deps` apt-installs missing libs. `bookworm-slim` is thinner but `--with-deps` covers it — **provided apt lists are present when it runs.** Layer 1 purges `/var/lib/apt/lists/*`, and unlike the full sandbox-templates bases (which pre-ship Chromium's libs, so their same-position purge is harmless), slim installs those libs from scratch. Sub-check: agent-browser runs *first*, and whether it self-`apt-get update`s is undocumented — so its RUN layer prepends `apt-get update` (playwright's installer self-refreshes, verified). Fallback: pre-apt the known Chromium lib set, *prefixed with `apt-get update`*, if `--with-deps` misses one. Verify on an actual `bookworm-slim` build reaching both browser layers, not by analogy to the full-base images.
3. **NodeSource Node 24 on bookworm ships corepack** (claude/codex rely on `corepack enable` + `corepack prepare pnpm@latest --activate`). If a corepack deprecation/removal bites, fall back to `npm i -g corepack` (what the Alpine Dockerfile did).
4. **Go tarball `GO_VERSION=1.26.3` + apt `python3`/`python3-pip`/`python3-venv` install on bookworm** — identical to claude/, already proven there.

### Impact Analysis

- **Direct:** the 4 files above; Dockerfile is the substantive change.
- **Adjacent:** `build.ps1` (toggle driver) and `prepare.ps1` (config staging) unchanged — verified base-agnostic. `run.ps1` functional logic unchanged.
- **Downstream:** image contents change substantially (Debian vs Alpine, +opencode baked, standard Chrome/playwright browsers). Consumers rebuild. `run.ps1`/`build.ps1` interfaces unchanged (backward-compatible). Image size likely grows (Chrome-for-Testing + playwright Chromium vs single system chromium) — accepted, matches claude/codex footprint.

---

## Implementation

### Overview

One substantive edit (Dockerfile rewrite) + three small follow-ups (skill line, run.ps1 comments, README). Step 1 is the hub; Steps 2-4 describe/document the swapped base and can follow in any order after it.

---

### Step 0 (Pre-Execution): resolve the pre-existing dirty tree, THEN branch

**Objective:** Get the base branch to a committed baseline that matches the file bytes Steps 3/4 reference — before creating the worktree/ephemeral branch.
**Confidence:** High
**Depends on:** None (must run first)

**Why:** The working tree currently has uncommitted `M` edits on `opencode/Dockerfile`/`README.md`/`run.ps1` (51+/40− vs HEAD), an *unrelated* in-flight Alpine change (still `apk`/musl/`AGENT_BROWSER_EXECUTABLE_PATH`) that this rewrite obsoletes. `> Worktree: Yes` branches from committed **HEAD**, which lacks those lines — so Steps 3/4's line/text references (authored against the dirty tree) won't match the execution branch, and the stranded edits become dead diffs against a Debian file after merge. SKILL.md already requires the plan be committed to base before execution; extend that to any working state the incremental steps depend on.

**Changes:**
1. Decide on the uncommitted `opencode/` edits: **discard** them (`git checkout -- opencode/Dockerfile opencode/README.md opencode/run.ps1`) since this rewrite supersedes them — or commit them to base first if any fragment is worth preserving independently.
2. Confirm clean: `git diff --stat HEAD -- opencode/` → empty for those three files.
3. **Re-derive Steps 3/4's line/text references against this committed baseline** — the `run.ps1` "~lines 91-92, ~105" and README "floating tag ~lines 170-174" offsets were read off the dirty tree; re-locate them (by text, not line number) on the now-clean file before editing.
4. Then create the worktree/branch and proceed to Step 1.

**Rationale:** Worktree isolation guards against *new* changes during execution, not against stale uncommitted state predating it. Resolving it up front is the only clean path.

**If this fails:** N/A — this is the setup that prevents the failure; if the edits turn out to be needed, commit them to a side branch before discarding from base.

---

### Step 1: Dockerfile — swap base to glibc, install opencode at build time

**Objective:** `debian:bookworm-slim` base; opencode + agent tooling installed the standard glibc way; all musl workarounds removed; toggles preserved.
**Confidence:** High (proven claude/codex patterns; glibc opencode binary confirmed to exist)
**Depends on:** None

**Files:** `opencode/Dockerfile`

**Changes:** replace the file wholesale. Target:

```dockerfile
# Custom OpenCode sandbox template
#   - Base: debian:bookworm-slim (glibc) — replaces ghcr.io/anomalyco/opencode
#     (third-party, Alpine/musl, binary-only, floating :latest). glibc lets
#     agent-browser / playwright / codegraph use their standard prebuilt
#     (glibc) binaries — none of the prior port's musl workarounds are needed.
#   - opencode installed at BUILD TIME via npm (opencode-ai), pinned — no more
#     dependency on a third-party pre-baked image.
#   - Node 24 (NodeSource) + pnpm via corepack; non-root "agent" user (uid 1000)
#     matching the claude/codex templates.
#   - Host ~/.config/opencode (opencode.json, AGENTS.md, plugin/, skills/, ...)
#     staged by prepare.ps1 (opencode.json MCP command arrays: Win paths → Linux).
#
# No docker/sandbox-templates:opencode base exists (unlike claude/codex), so
# there's no sbx integration here — this is the plain-docker path, run via
# run.ps1. Host auth (~/.local/share/opencode/auth.json) is bind-mounted at
# runtime by run.ps1; nothing credential-related is baked into the image.
#
# Build context expects ./context/.config/opencode populated by prepare.ps1.

FROM debian:bookworm-slim

USER root

ARG NODE_MAJOR=24
# Installed at build time (glibc opencode-linux-x64 via npm). Pinned, not
# @latest — a shared build artifact tracks an audited version explicitly.
ARG OPENCODE_VERSION=1.17.19
# Pinned for the same reason (see 2607081900-codegraph-integration-audit.md).
ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
ARG GO_VERSION=1.26.3
ARG INSTALL_GO=1
ARG INSTALL_PYTHON=1

# Baseline coding-agent tools + Node 24 via NodeSource (mirrors codex/). Install
# opencode + agent tooling in the same layer. On glibc every one of these is a
# stock npm install — no musl symlink/env workaround (contrast the Alpine base).
RUN set -eux; \
    for flag in "$INSTALL_GO" "$INSTALL_PYTHON"; do case "$flag" in 0|1) ;; *) echo "INSTALL_* must be 0 or 1" >&2; exit 1 ;; esac; done; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash ca-certificates curl git gnupg jq less openssh-client sudo tini tzdata apt-transport-https; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs build-essential; \
    corepack enable; \
    corepack prepare pnpm@latest --activate; \
    npm install -g \
        "opencode-ai@${OPENCODE_VERSION}" \
        "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" \
        "agent-browser@${AGENT_BROWSER_VERSION}" \
        "playwright@${PLAYWRIGHT_VERSION}"; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    node --version | grep -E "^v24\." || { echo "ERROR: expected Node 24, got $(node --version)"; exit 1; }; \
    opencode --version; codegraph --version; agent-browser --version; playwright --version

# Non-root agent user (uid 1000), matching claude/codex. bookworm-slim leaves
# uid 1000 free (no `node`-image squatter). NOPASSWD sudo for run.ps1's
# volume-chown bootstrap.
RUN useradd --create-home --uid 1000 --shell /bin/bash agent \
 && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
 && chmod 0440 /etc/sudoers.d/agent \
 && mkdir -p /home/agent/.local/share/opencode /home/agent/.local/state/opencode \
 && chown -R agent:agent /home/agent

# agent-browser install: Chrome for Testing + Linux system libs (--with-deps,
# needs root/apt). Layer 1 purged /var/lib/apt/lists/*, and bookworm-slim ships
# NONE of Chromium's runtime libs — so refresh apt lists here before --with-deps.
# agent-browser runs first and its self-apt-update behavior is undocumented, so
# don't rely on it (playwright's installer self-runs apt-get update; this one may
# not). HOME override lands Chrome in the agent's home so it isn't re-downloaded
# after USER agent. (glibc → the standard flow works; the Alpine base had to skip
# this and point at system Chromium instead.)
RUN apt-get update \
 && HOME=/home/agent agent-browser install --with-deps \
 && chown -R agent:agent /home/agent/.agent-browser

# Playwright's own Chromium + Linux system libs, baked at build time so a
# project's first `playwright install` isn't cold.
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache/ms-playwright

# Optional Go (official tarball, pinned — apt's golang lags upstream; mirrors
# claude/). Installs to /usr/local/go, symlinks onto PATH.
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

# Bind-mounts can leave /workspace owned differently than agent (git's
# dubious-ownership guard), and a fresh container has no git identity. System
# config is lowest-precedence, so any user/global config set later still wins.
RUN git config --system --add safe.directory '*' \
 && git config --system core.autocrlf input \
 && git config --system user.name 'agent' \
 && git config --system user.email 'agent@sandbox.local'

USER agent
WORKDIR /home/agent

COPY --chown=agent:agent context/.config/opencode/ /home/agent/.config/opencode/

# agent-browser discovery stub — repo-owned (not host-synced), survives whatever
# is in the host's ~/.config/opencode/skills. opencode global skill location.
COPY --chown=agent:agent skills/agent-browser/ /home/agent/.config/opencode/skills/agent-browser/

ENTRYPOINT ["tini", "--"]
CMD ["opencode"]
```

**Rationale:**
- **`debian:bookworm-slim`** is the honest "follow the claude/codex pattern" choice given no `docker/sandbox-templates:opencode` exists: a standard, well-supported glibc base, then build up with NodeSource Node 24 exactly as codex/ does. Rejected alternatives: a `node:24-*` image (squats uid 1000 with its `node` user, colliding with the required `agent` uid); reusing `docker/sandbox-templates:codex`/`:claude-code` (bakes the wrong agent + sbx machinery opencode doesn't use — semantically wrong).
- **opencode via `npm i -g opencode-ai@<pinned>`** — the documented Node channel, pinnable via ARG (suite convention), and Node is baseline anyway. glibc base → npm resolves `opencode-linux-x64` (glibc), which runs natively.
- **Every musl workaround dropped** — no `chromium` apt package, no `AGENT_BROWSER_EXECUTABLE_PATH`, no `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD`, no codegraph `ln -sf` node symlink. On glibc, `agent-browser install --with-deps` / `playwright install --with-deps chromium` / plain codegraph npm all work — resolving the prior port's `node: not found` codegraph blocker (2607111343 audit).
- **apt lists refreshed before the agent-browser layer** — layer 1 ends with `rm -rf /var/lib/apt/lists/*`, but `bookworm-slim` ships none of Chromium's runtime libs (unlike the *full* sandbox-templates bases codex/claude build on, which already carry them — so their same-position purge is harmless). agent-browser runs first with an empty apt cache; `apt-get install <lib>` for a *missing* package fails against purged lists, and agent-browser's self-`apt-get update` behavior is undocumented. So the agent-browser RUN layer prepends `apt-get update`. playwright's installer self-runs `apt-get update` (verified), so its layer needs no prepend.
- **`build.ps1` untouched** — it sets `INSTALL_GO`/`INSTALL_PYTHON`; the Dockerfile keeps those ARG names, so the toggle contract holds while the install commands move apk→apt/tarball.

**Verification:**
- `./build.ps1 -Image opencode-custom:v1 -Engine docker` builds clean on an actual `bookworm-slim` base (not by analogy to the full sandbox-templates bases) — the build must reach and pass *both* browser layers (`agent-browser install --with-deps`, then `playwright install --with-deps chromium`), proving the agent-browser layer's `apt-get update` restores the lists layer 1 purged so `--with-deps` can install Chromium's runtime libs from scratch. In-build smoke tests (`opencode --version`, `codegraph --version`, `agent-browser --version`, `playwright --version`, Node-24 grep) all pass.
- `docker run --rm opencode-custom:v1 sh -lc 'cat /etc/os-release | head -1; opencode --version; node --version; go version; python3 --version; agent-browser --version; playwright --version; id agent'` → Debian bookworm, opencode present, Node v24, go/python present (default set), agent uid 1000.
- `grep -RiE 'anomalyco|AGENT_BROWSER_EXECUTABLE_PATH|PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD|apk |ln -sf.*codegraph' opencode/Dockerfile` → no matches.
- `./build.ps1 -Disable python -Engine docker` → python3 absent, go present; `-Enable dotnet` → still rejected (`Unknown language 'dotnet'. Supported: go, python.`).

**If this fails:** revert `opencode/Dockerfile` to its prior (Alpine) content — `git checkout -- opencode/Dockerfile`. If only assumption 1 fails (opencode npm bin), swap that one install to the `curl … opencode.ai/install | bash` script and keep the rest. If assumption 2 fails, pre-apt the missing Chromium libs before the `install --with-deps` calls — prefixed with `apt-get update` (layer 1 purged the lists, so a bare `apt-get install` fails against an empty cache).

---

### Step 2: agent-browser skill stub — drop the musl note

**Objective:** The discovery stub's build-note must describe the glibc baked-browser flow, not the Alpine system-Chromium workaround.
**Confidence:** High
**Depends on:** Step 1

**Files:** `opencode/skills/agent-browser/SKILL.md`

**Changes:** replace line 12:

```
// Before:
This image bakes agent-browser (via npm) and Alpine's system Chromium; `AGENT_BROWSER_EXECUTABLE_PATH` already points the daemon at `/usr/bin/chromium`, so no `agent-browser install` (which would fetch a glibc Chrome-for-Testing that cannot run on this musl base) is needed.

// After:
This image bakes agent-browser and its Chrome-for-Testing browser at build time (`agent-browser install --with-deps`, standard glibc flow), so no runtime browser download is needed.
```

**Rationale:** Base is glibc now; `agent-browser install` runs the normal way (Step 1), so the system-Chromium / `AGENT_BROWSER_EXECUTABLE_PATH` framing is false. Body of the stub (usage, `skills get core`, agent list incl. opencode) is host-agnostic — leave it.

**Verification:** `grep -iE 'musl|/usr/bin/chromium|AGENT_BROWSER_EXECUTABLE_PATH' opencode/skills/agent-browser/SKILL.md` → no matches.

**If this fails:** docs-only; `git checkout --` the file.

---

### Step 3: run.ps1 comments + build.ps1 stale-comment scan

**Objective:** Remove stale Alpine/musl framing from comments in the runtime scripts. No functional change.
**Confidence:** High
**Depends on:** Step 1

**Files:** `opencode/run.ps1` (and a scan of `opencode/build.ps1`)

**Changes — run.ps1:** the volume-namespacing comments (~lines 91-92 and ~105 — offsets read off the pre-existing dirty tree; locate by text against the Step-0 committed baseline, not by line number) justify the `opencode-` prefix as keeping "this **Alpine/musl** store" from sharing the "claude template's **Debian/glibc** store". Both suites are glibc now, so the musl-vs-glibc contrast is stale. Reword to: namespacing keeps each suite's caches/volumes isolated (still desirable — independent lifecycles), without the false musl-vs-glibc rationale. Functional logic (`$pmSetup` chowns, `--userns=keep-id`, node_modules mask, SQLite history mount) is unchanged.

**Changes — build.ps1:** grep for `Alpine`/`musl`/`apk`; if any stale comment exists (e.g. an "Alpine-native" note on the language toggle), reword to reflect apt/tarball. If none, no edit.

**Rationale:** Correctness of in-repo comments; nothing behavioral. Namespacing survives on its own merit (per-suite isolation) even though the original musl reason is gone.

**Verification:** `grep -RiE 'Alpine|musl' opencode/run.ps1 opencode/build.ps1` → no stale/misleading hits (a comment explicitly noting the *former* Alpine base for history is acceptable if phrased as past state). Scripts still run: `./run.ps1` in a scratch dir launches without error.

**If this fails:** comment-only; `git checkout --` the file(s).

---

### Step 4: README.md — reflect the new base

**Objective:** Docs describe the glibc Debian base, build-time opencode install, apt/tarball toggles, standard agent-browser, and drop the resolved floating-tag gap.
**Confidence:** High
**Depends on:** Steps 1-3

**Files:** `opencode/README.md`

**Changes:**
- Opening "Extends `ghcr.io/anomalyco/opencode` (Alpine …)" → "Built on `debian:bookworm-slim` (glibc); the `opencode` CLI is installed at build time via `npm i -g opencode-ai@<pinned>`." Update the base/added-tools bullets (apt baseline, not apk; Chrome-for-Testing via `agent-browser install`, not system Chromium).
- "Optional language features" table: `apk packages` column → apt/tarball (go = official tarball pinned `GO_VERSION`; python = `python3`/`python3-pip`/`python3-venv` apt). Update the surrounding "Alpine-native (musl)" prose. Optionally note `.NET` is now *feasible* on glibc but not yet added (see Notes).
- agent-browser section: remove `AGENT_BROWSER_EXECUTABLE_PATH`/system-Chromium/musl caveats; describe the standard baked Chrome-for-Testing.
- **Remove the "floating `:latest` tag" known-gap note** (~lines 170-174 — offsets read off the pre-existing dirty tree; locate by text against the Step-0 committed baseline) — base moves off the unaudited third-party `:latest` onto an official pinned tag and opencode is pinned via `OPENCODE_VERSION`. (Note honestly that `debian:bookworm-slim` is itself a rolling tag, still not digest-pinned — see F3 wording in Objective.)
- If the README mentions the codegraph symlink hack or the musl codegraph caveat, remove it (resolved).

**Rationale:** Prevent doc drift; the base swap changes nearly every environmental claim the README makes.

**Verification:** `grep -RiE 'anomalyco|Alpine|musl|floating|:latest|AGENT_BROWSER_EXECUTABLE_PATH' opencode/README.md` → only intentional historical references (if any), no stale current-state claims. Toggle table matches Step 1's installs.

**If this fails:** docs-only; revert freely.

---

## Verification Plan

### Automated Checks
- [ ] `./build.ps1 -Image opencode-custom:v1 -Engine docker` builds clean; in-build `opencode/codegraph/agent-browser/playwright --version` + Node-24 grep pass.
- [ ] `./build.ps1 -Disable python` and `-Enable go` both build; `-Enable dotnet` rejected with the supported list.
- [ ] `grep -RiE 'anomalyco|AGENT_BROWSER_EXECUTABLE_PATH|PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD|apk ' opencode/Dockerfile` → empty.

### Manual Verification
- [ ] `docker run --rm opencode-custom:v1 sh -lc 'head -1 /etc/os-release; opencode --version; node --version; go version; python3 --version; agent-browser --version; playwright --version; id agent'` reflects Debian + pinned opencode + Node 24 + enabled toggles + agent uid 1000.
- [ ] **codegraph functional check (not just `--version`)** — run one real codegraph operation against a tiny throwaway repo inside the container, e.g. `docker run --rm opencode-custom:v1 sh -lc 'mkdir -p /tmp/cg && cd /tmp/cg && git init -q && printf "def f(): pass\n" > a.py && git add -A && git commit -qm init && codegraph index . && echo CODEGRAPH_OK'`. `--version` alone doesn't load the native `better-sqlite3` addon; an actual index does. Expected: exits 0, `CODEGRAPH_OK` prints, no native-module load error. (Functional risk is low — glibc `better-sqlite3` ships standard prebuilds and `build-essential` is present — but `--version` shallow-verifies only.)
- [ ] `./run.ps1` in a Node project dir → node_modules masked/reinstalled, session history persists across `--rm` (the prior port's criterion, now testable end-to-end since codegraph no longer breaks the build).
- [ ] prepare.ps1 unchanged and still stages `~/.config/opencode` correctly (no regression).

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected Result |
|-----------|---------------|-----------------|
| Base swapped, pinned | `head opencode/Dockerfile` | `FROM debian:bookworm-slim`, no `anomalyco`/`:latest` |
| opencode built-time install | in-build + runtime `opencode --version` | pinned version prints |
| Musl workarounds gone | grep Dockerfile | no `AGENT_BROWSER_EXECUTABLE_PATH`/`PLAYWRIGHT_SKIP…`/chromium apk/symlink |
| codegraph works on glibc | in-build `codegraph --version` **+ `codegraph index` on a tiny throwaway repo** (exercises native `better-sqlite3`) | both exit 0 (blocker resolved, native path loads) |
| Toggles preserved | build `-Disable python` | python3 absent, go present |
| Docs current | grep README | no stale Alpine/floating-tag claims |

---

## Rollback Plan

Per-step rollback noted above. Full abandon: `git checkout -- opencode/Dockerfile opencode/skills/agent-browser/SKILL.md opencode/run.ps1 opencode/README.md`. Restores the Alpine base template; no external state to unwind (images/volumes disposable).

**Pre-existing dirty state — resolve BEFORE execution, not via rollback.** The working tree carries uncommitted `M` edits on `Dockerfile`/`README.md`/`run.ps1` (51+/40− vs HEAD) that are an *unrelated* in-flight Alpine change (still `apk`/musl/`AGENT_BROWSER_EXECUTABLE_PATH`), obsoleted by this rewrite. Worktree mode does **not** absorb them cleanly: it branches from committed **HEAD**, so those lines aren't on the execution branch, and after this plan merges they linger in the main tree as dead diffs against a Debian file. Worktree isolation protects against *new* changes made during execution — not against stale uncommitted state predating it. So the executor must commit-or-discard those specific edits to base first (see Pre-Execution below); this section is only for unwinding *this plan's* own changes.

---

## Revision Log

- **2026-07-14:** Applied redteam Must-Fix + small Should-Fix items — trigger: `2607141745-opencode-glibc-base-swap-redteam.md` (Verdict: Fix Issues).
  - **F1** (apt lists purged before `--with-deps` on a slim base): agent-browser RUN layer now prepends `apt-get update` (layer 1 purges `/var/lib/apt/lists/*`; agent-browser runs first, self-update undocumented; playwright self-refreshes). Updated Step 1 Dockerfile target, rationale (new bullet), assumption 2, Step 1 "If this fails" fallback, Step 1 verification (must exercise both browser layers on a real slim build), and Risks mitigation — all now specify `apt-get update` before any pre-apt.
  - **F2** (worktree-from-HEAD vs pre-existing dirty tree): added **Step 0 (Pre-Execution)** to commit-or-discard the unrelated `opencode/` `M`-edits to base and re-derive Step 3/4 refs against the committed baseline; annotated Step 3/4 line refs as dirty-tree offsets (locate by text); corrected the Rollback section's false "worktree handles this cleanly" claim; pointed the Current State note at Step 0.
  - **F3** (base-pinning honesty): reworded Objective floating-tag bullet, Success Criterion, and Constraints to state `debian:bookworm-slim` is an official *named* tag off an unaudited third-party `:latest`, but still a rolling, non-digest-pinned tag (patch-level drift) — only the agent tooling is truly version-pinned.
  - **Codegraph functional check:** added a real `codegraph index` on a throwaway repo to Manual Verification + the acceptance table (exercises the native `better-sqlite3` path, which `--version` doesn't).

## Notes

### Risks
- **`agent-browser install --with-deps` / `playwright install --with-deps chromium` on `bookworm-slim`** (assumption 2): slim is thinner than the sandbox-templates base; `--with-deps` should cover missing libs but may need a pre-apt of one or two. **Layer 1 purges apt lists, so the agent-browser layer prepends `apt-get update`** (it runs first; its self-update behavior is undocumented — playwright self-refreshes). Mitigation: pre-apt the known Chromium lib set (prefixed with `apt-get update`) if a `--with-deps` gap surfaces. Primary redteam target — verify on a real slim build, not by analogy to the full-base images.
- **corepack availability on NodeSource Node 24** (assumption 3): deprecation could break `corepack enable`. Mitigation: `npm i -g corepack` fallback (what the Alpine Dockerfile did).
- **opencode npm bin wrapper** (assumption 1): the `opencode-ai` main package dispatches to the platform optional dep; if resolution misfires under `npm i -g`, fall back to the `curl … opencode.ai/install | bash` script (also glibc).
- **Image size growth**: Chrome-for-Testing + playwright Chromium (two full browsers) vs the Alpine single system chromium. Accepted — matches claude/codex; no slim variant exists to keep lean.

### Future (out of scope here)
- **`.NET` toggle** now feasible: the prior port excluded it solely because Alpine musl .NET is niche (2607110159 Out of Scope). On glibc, claude's `dotnet-sdk` apt path applies directly — add an `INSTALL_DOTNET` toggle + `-Supported @('go','python','dotnet')` in build.ps1 if requested.
- **agent-browser toggle (F7)** and **apt version pinning of python (F8)** carried from the prior port's redteam remain low-priority deferrals; unaffected by this swap.

### Open Questions
- None blocking. All four assumptions have documented fallbacks that degrade gracefully.

---

## Split Decision

**Verdict:** `No split — single scope, within size budget.`

All files live in the one `opencode/` projex scope (no cross-scope, cross-repo, or upstream/downstream mix → no mandatory split). Four steps, one substantive (Dockerfile) with three small documentation/comment followers tightly coupled to it (they describe the swapped base). Under the size heuristic (≤5 steps, well under 500 lines / 50 KB of change). Keep as one plan.
