# Custom Pi sandbox template
#   - Base: debian:bookworm-slim (glibc) — same rationale as opencode/cursor: no
#     docker/sandbox-templates:pi base exists, so this is the plain-docker path,
#     not an sbx extension (unlike claude/codex).
#   - pi (binary name: `pi`, npm package `@earendil-works/pi-coding-agent`) is a
#     Node/npm program — unlike cursor-agent, Node IS its runtime, not just a
#     shared-tooling dependency. Installed at BUILD TIME via
#     `npm install -g --ignore-scripts`, pinned (see
#     .projex/2607171400-pi-coding-agent-install-audit.md — approved, pin >=0.78.1;
#     all 4 known GHSA advisories are fixed by 0.78.1/0.79.0, predating this pin).
#   - Node 25 (NodeSource) satisfies pi's own `engines.node: ">=22.19.0"`; also
#     drives the shared dev-tool trio (codegraph, agent-browser, playwright),
#     same as opencode/cursor. pnpm is installed globally via npm (mirrors
#     claude/opencode's npm-installed-pnpm, drop-corepack convention), so
#     pnpm-lockfile projects reinstall Linux-native deps in run.ps1 same as
#     npm/yarn ones.
#   - No MCP: pi deliberately ships no MCP client (see pi's own README — "No MCP.
#     Build CLI tools with READMEs, or build an extension that adds MCP
#     support"). codegraph is therefore baked as a plain CLI tool plus a
#     discovery-stub skill (skills/codegraph/), NOT wired in via
#     `codegraph install --target=pi` — pi isn't in codegraph's supported
#     --target list (Claude Code, Cursor, Codex CLI, opencode, Hermes Agent,
#     Gemini CLI, Antigravity IDE, Kiro) and has no MCP config file to wire into.
#   - Non-root "agent" user (uid 1000), matching the claude/opencode/cursor/codex templates.
#   - Host ~/.pi/agent (settings.json, AGENTS.md/SYSTEM.md, extensions/, skills/,
#     themes/, prompts/) staged by prepare.ps1 — a filtered recursive copy, no
#     path rewriting needed (no MCP config = no command-array Win->Linux rewrite,
#     unlike opencode/cursor). auth.json/trust.json/models-store.json/sessions/
#     git/npm are excluded — see prepare.ps1 header and run.ps1 for how those are
#     handled instead (bind-mounted at runtime, not baked).
#   - Four pi packages are installed at BUILD TIME via `pi install npm:...`,
#     each pinned per its own audit in .projex/ (2607171500 pi-subagents,
#     2607171501 pi-cursor-sdk, 2607171502 pi-web-access, 2607171503
#     context-mode) — all APPROVED. This mirrors claude/'s build-time-install
#     precedent for context-mode (see claude/.projex/2607100235-*-pilot-plan.md
#     and its closed patch): install fresh in-container instead of vendoring a
#     host copy, so paths/native-module builds are Linux-native from the start.
#     pi has no separate "marketplace" concept (unlike Claude Code plugins), so
#     this is simpler than the claude/ pilot — one `pi install npm:pkg@version`
#     per package, no registry-file surgery needed. context-mode's
#     `better-sqlite3` native dependency rebuilds against this layer's
#     build-essential + python3 (present from the baseline/optional-Python
#     layers below), same requirement claude/Dockerfile already solves for the
#     same package.
#
# No credentials are baked into the image. run.ps1 bind-mounts the host
# ~/.pi/agent/auth.json (like opencode's auth.json) and forwards whichever
# provider API-key env vars are set on the host.
#
# Build context expects ./context/.pi/agent populated by prepare.ps1.

FROM debian:bookworm-slim

USER root

ARG NODE_MAJOR=25
# Pinned per .projex/2607171400-pi-coding-agent-install-audit.md (APPROVED,
# condition: >=0.78.1 — all 4 known GHSA advisories fixed by 0.78.1/0.79.0).
ARG PI_VERSION=0.80.9
# Pinned for the same reason as the other suites (see
# .projex/2607081900-codegraph-integration-audit.md): a shared build artifact
# tracks an audited version explicitly, not @latest.
ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
ARG GO_VERSION=1.26.3
ARG INSTALL_GO=1
ARG INSTALL_PYTHON=1

# Pi packages, pinned per their audits in .projex/ (all APPROVED, 2026-07-17):
#   2607171500-pi-subagents-install-audit.md
#   2607171501-pi-cursor-sdk-install-audit.md
#   2607171502-pi-web-access-install-audit.md
#   2607171503-context-mode-pi-package-install-audit.md
ARG PI_SUBAGENTS_VERSION=0.14.1
ARG PI_CURSOR_SDK_VERSION=0.1.59
ARG PI_WEB_ACCESS_VERSION=0.13.0
ARG CONTEXT_MODE_VERSION=1.0.169

# Baseline coding-agent tools + Node 25 via NodeSource. ripgrep is included
# because upstream pi's own reference Dockerfile.pi installs it alongside
# git/bash/ca-certificates — pi's built-in tools/extensions can shell out to it.
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
    npm install -g pnpm@latest; \
    npm install -g --ignore-scripts \
        "@earendil-works/pi-coding-agent@${PI_VERSION}" \
        "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" \
        "agent-browser@${AGENT_BROWSER_VERSION}" \
        "playwright@${PLAYWRIGHT_VERSION}"; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    node --version | grep -E "^v25\." || { echo "ERROR: expected Node 25, got $(node --version)"; exit 1; }; \
    pi --version; codegraph --version; agent-browser --version; playwright --version; pnpm --version

# Non-root agent user (uid 1000), matching claude/opencode/cursor/codex.
# bookworm-slim leaves uid 1000 free (no `node`-image squatter). NOPASSWD sudo
# for run.ps1's volume-chown bootstrap.
RUN useradd --create-home --uid 1000 --shell /bin/bash agent \
 && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
 && chmod 0440 /etc/sudoers.d/agent

# agent-browser install: Chrome for Testing + Linux system libs (--with-deps,
# needs root/apt). Layer 1 purged /var/lib/apt/lists/*, and bookworm-slim ships
# NONE of Chromium's runtime libs — so refresh apt lists here before --with-deps.
# HOME override lands Chrome in the agent's home so it isn't re-downloaded after
# USER agent.
RUN apt-get update \
 && HOME=/home/agent agent-browser install --with-deps \
 && chown -R agent:agent /home/agent/.agent-browser

# Playwright's own Chromium + Linux system libs, baked at build time so a
# project's first `playwright install` isn't cold. Runs as root with
# HOME=/home/agent, creating /home/agent/.cache root:root — chown it back to
# agent, or pi (Node) can't mkdir ~/.cache or ~/.pi/agent on first run as the
# agent user.
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache

# Optional Go (official tarball, pinned — apt's golang lags upstream; mirrors
# claude/opencode/cursor). Installs to /usr/local/go, symlinks onto PATH.
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

# rm-guard: shadow the real coreutils `rm` in place with an in-repo wrapper
# (rm-guard/rm-guard.sh) that refuses to remove /workspace/.git (or anything
# inside/above it) and passes every other invocation straight through
# unchanged. Not a `~/.bashrc` alias — bash doesn't expand aliases in the
# non-interactive shells the agent's shell tool actually uses, so an alias
# would silently never fire for the one case this exists to cover.
COPY rm-guard/rm-guard.sh /usr/local/libexec/rm-guard.sh
RUN set -eux; \
    chmod 0755 /usr/local/libexec/rm-guard.sh; \
    real_rm="$(readlink -f "$(command -v rm)")"; \
    cp "$real_rm" /usr/bin/rm.real; \
    ln -sf /usr/local/libexec/rm-guard.sh "$real_rm"; \
    rm --version >/dev/null; \
    # Self-test: /workspace doesn't exist yet at build time (it's a runtime
    # bind mount), so fake one up here to actually exercise the guard rather
    # than have "path not found" masquerade as "blocked".
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

COPY --chown=agent:agent context/.pi/agent/ /home/agent/.pi/agent/

# Build-time pi package installs (see .projex audits referenced above). Global
# installs (no -l), landing in ~/.pi/agent/npm/ — a sibling of the COPY above,
# which prepare.ps1 always excludes from the host-staged tree, so there is no
# collision between the baked config and these in-container installs. Each
# `pi install` is its own `RUN` so a failure in one package is isolated and
# diagnosable in the build log rather than aborting the others.
#
# context-mode has a `postinstall` script (self-heal/config-repair, per its own
# repo) and a `better-sqlite3` native dependency — review this layer's build
# output on first build, same caution this repo already applies to the
# identical package's build-time install in claude/Dockerfile.
RUN pi install "npm:@tintinweb/pi-subagents@${PI_SUBAGENTS_VERSION}"
RUN pi install "npm:pi-cursor-sdk@${PI_CURSOR_SDK_VERSION}"
RUN pi install "npm:pi-web-access@${PI_WEB_ACCESS_VERSION}"
RUN pi install "npm:context-mode@${CONTEXT_MODE_VERSION}"

# agent-browser discovery stub — repo-owned (not host-synced), survives
# whatever is in the host's ~/.pi/agent/skills. Agent Skills standard location.
COPY --chown=agent:agent skills/agent-browser/ /home/agent/.pi/agent/skills/agent-browser/

# codegraph discovery stub — pi has no MCP client, so codegraph is wired up as
# a plain CLI + skill instead of via `codegraph install --target=pi` (pi is not
# a supported codegraph target anyway). See skills/codegraph/SKILL.md.
COPY --chown=agent:agent skills/codegraph/ /home/agent/.pi/agent/skills/codegraph/

ENTRYPOINT ["tini", "--"]
CMD ["pi"]
