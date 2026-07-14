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
# project's first `playwright install` isn't cold. `playwright install` runs as
# root with HOME=/home/agent, so it creates /home/agent/.cache owned by
# root:root — chown the whole .cache (parent + ms-playwright) back to agent, or
# opencode (Bun) can't mkdir ~/.cache/opencode on first run as the agent user
# (bare `docker run`; run.ps1's $pmSetup also chowns .cache, but the image must
# stand on its own).
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache

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
