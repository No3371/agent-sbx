# Self-built Claude Code image
#   - Starts from official Node 25 bookworm-slim
#   - Installs Claude Code, pnpm, and optional Python 3, Go, and .NET SDK
#   - Recreates only the agent user/env pieces needed by run.ps1
#   - Host OAuth is bind-mounted by run.ps1; no credentials are baked

FROM node:25-bookworm-slim

USER root

ARG GO_VERSION=1.26.3
ARG DOTNET_CHANNEL=10.0
ARG INSTALL_GO=1
ARG INSTALL_DOTNET=1
ARG INSTALL_PYTHON=1

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    PATH=/usr/local/share/npm-global/bin:/home/agent/.local/bin:$PATH \
    BASH_ENV=/etc/sandbox-persistent.sh \
    CLAUDE_ENV_FILE=/etc/sandbox-persistent.sh

# Core tools only. Deliberately omits heavyweight extras like Docker CLI,
# Java, man-db, Ubuntu dev bundles, and clipboard bridge.
RUN set -eux; \
    for flag in "$INSTALL_GO" "$INSTALL_DOTNET" "$INSTALL_PYTHON"; do case "$flag" in 0|1) ;; *) echo "INSTALL_* must be 0 or 1" >&2; exit 1 ;; esac; done; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        apt-transport-https build-essential ca-certificates curl git gnupg jq less openssh-client \
        procps ripgrep sudo tini tzdata unzip; \
    if [ "$INSTALL_DOTNET" = "1" ]; then \
        install -d -m 0755 /etc/apt/keyrings; \
        curl -fsSL "https://packages.microsoft.com/config/debian/$(. /etc/os-release && echo "$VERSION_ID")/packages-microsoft-prod.deb" \
            -o /tmp/packages-microsoft-prod.deb; \
        dpkg -i /tmp/packages-microsoft-prod.deb; \
        rm -f /tmp/packages-microsoft-prod.deb; \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends dotnet-sdk-${DOTNET_CHANNEL}; \
    fi; \
    if [ "$INSTALL_PYTHON" = "1" ]; then \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3 python3-pip python3-venv; \
    fi; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Non-root agent user with the same home path expected by the current template.
RUN set -eux; \
    if id node >/dev/null 2>&1; then \
        usermod --login agent --home /home/agent --move-home --shell /bin/bash node; \
        groupmod --new-name agent node; \
    else \
        useradd --create-home --uid 1000 --shell /bin/bash agent; \
    fi; \
    usermod -aG sudo agent; \
    echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent; \
    chmod 0440 /etc/sudoers.d/agent; \
    mkdir -p /home/agent/.local/bin /home/agent/.local/share /home/agent/.local/state \
             /home/agent/.claude /home/agent/.claude-bake /usr/local/share/npm-global; \
    chown -R agent:agent /home/agent; \
    touch /etc/sandbox-persistent.sh; \
    chmod 0644 /etc/sandbox-persistent.sh; \
    printf '%s\n' \
        'export PATH=/usr/local/share/npm-global/bin:/home/agent/.local/bin:$PATH' \
        'if [ -f /etc/sandbox-persistent.sh ]; then . /etc/sandbox-persistent.sh; fi' \
        'export BASH_ENV=/etc/sandbox-persistent.sh' \
        > /etc/profile.d/sandbox-persistent.sh; \
    printf '%s\n' \
        'export PATH=/usr/local/share/npm-global/bin:/home/agent/.local/bin:$PATH' \
        'if [ -f /etc/sandbox-persistent.sh ]; then . /etc/sandbox-persistent.sh; fi' \
        'export BASH_ENV=/etc/sandbox-persistent.sh' \
        > /home/agent/.bashrc; \
    chown agent:agent /home/agent/.bashrc

# run.ps1 bind-mounts /workspace with the host's ownership, tripping git's
# dubious-ownership guard; and a fresh container has no git identity, so the
# agent's first commit fails until one is set. System config is the
# lowest-precedence layer, so any user/global config set later still wins.
RUN git config --system --add safe.directory '*' \
 && git config --system core.autocrlf input \
 && git config --system user.name 'agent' \
 && git config --system user.email 'agent@sandbox.local'

# Go official tarball, pinned.
RUN set -eux; \
    if [ "$INSTALL_GO" = "1" ]; then \
        arch="$(dpkg --print-architecture)"; \
        case "$arch" in \
            amd64) go_arch=amd64 ;; \
            arm64) go_arch=arm64 ;; \
            *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
        esac; \
        curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz" -o /tmp/go.tar.gz; \
        tar -C /usr/local -xzf /tmp/go.tar.gz; \
        rm -f /tmp/go.tar.gz; \
        ln -sf /usr/local/go/bin/go /usr/local/bin/go; \
        ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt; \
    fi

# Bake pnpm plus pinned codegraph, agent-browser, and Playwright tooling for
# reproducible, offline use. Claude Code remains separate because it is unpinned.
ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
RUN set -eux; \
    npm config set update-notifier false; \
    npm install -g pnpm@latest; \
    npm install -g "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" "agent-browser@${AGENT_BROWSER_VERSION}" "playwright@${PLAYWRIGHT_VERSION}"; \
    ln -sf /usr/local/share/npm-global/bin/codegraph /home/agent/.local/bin/codegraph; \
    ln -sf /usr/local/share/npm-global/bin/agent-browser /home/agent/.local/bin/agent-browser; \
    ln -sf /usr/local/share/npm-global/bin/playwright /home/agent/.local/bin/playwright; \
    chown -h agent:agent /home/agent/.local/bin/codegraph /home/agent/.local/bin/agent-browser /home/agent/.local/bin/playwright; \
    node --version; npm --version; pnpm --version; codegraph --version; agent-browser --version; playwright --version

# agent-browser install: downloads Chrome for Testing + installs Linux system
# libs (--with-deps, needs root/apt). HOME override writes Chrome/config
# straight into the agent's home instead of /root, so no second download is
# needed after the USER agent switch below.
RUN HOME=/home/agent agent-browser install --with-deps \
 && chown -R agent:agent /home/agent/.agent-browser

# Install Chromium and its system libraries into the agent-owned cache.
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache/ms-playwright

# rm-guard protects /workspace/.git and related paths by replacing `rm`;
# non-interactive agent shells do not expand aliases.
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

# Claude Code is intentionally unpinned; changing CLAUDE_CODE_CACHEBUST forces
# Docker to resolve the current release. Keep this layer after the expensive
# browser installs so refreshing Claude Code does not invalidate them.
ARG CLAUDE_CODE_CACHEBUST=0
RUN set -eux; \
    echo "claude-code cachebust: ${CLAUDE_CODE_CACHEBUST}"; \
    npm install -g @anthropic-ai/claude-code; \
    ln -sf /usr/local/share/npm-global/bin/claude /home/agent/.local/bin/claude; \
    chown -h agent:agent /home/agent/.local/bin/claude; \
    claude --version

USER agent
WORKDIR /home/agent

COPY --chown=agent:agent context/.claude/skills/    /home/agent/.claude/skills/
# agent-browser discovery stub — Dockerfile-owned (not host-synced), so it
# survives regardless of what's on the host's ~/.claude/skills.
COPY --chown=agent:agent skills/agent-browser/      /home/agent/.claude/skills/agent-browser/
COPY --chown=agent:agent context/.claude/agents/    /home/agent/.claude/agents/
COPY --chown=agent:agent context/.claude/tools/     /home/agent/.claude/tools/
COPY --chown=agent:agent context/.claude/commands/  /home/agent/.claude/commands/
COPY --chown=agent:agent context/.claude/settings.json       /home/agent/.claude/settings.json
COPY --chown=agent:agent context/.claude/settings.local.json /home/agent/.claude-bake/settings.local.json
COPY --chown=agent:agent context/.claude/hooks/              /home/agent/.claude/hooks/
COPY --chown=agent:agent context/.claude/plugins/            /home/agent/.claude/plugins/

RUN set -eux; \
    claude plugin marketplace add mksglu/context-mode; \
    claude plugin install context-mode@context-mode --scope user

COPY --chown=agent:agent context/scripts/                    /home/agent/.local/bin/

# prepare.ps1 skips node_modules/ from plugins/ (built on the host — Windows
# — native .node addons like context-mode's better-sqlite3 won't load in this
# Linux container). Reinstall for every plugin/marketplace dir that ships a
# package.json so native deps get rebuilt for Linux. build-essential (above)
# covers node-gyp compilation for any addon without a prebuilt Linux binary.
RUN set -eux; \
    for d in $(find /home/agent/.claude/plugins -maxdepth 8 -name package.json -printf '%h\n'); do \
        echo "[build] npm install: $d"; \
        (cd "$d" && npm install --no-audit --no-fund); \
    done

USER root
RUN chmod +x /home/agent/.local/bin/*.sh \
 && find /home/agent/.claude/hooks -type f \( -name '*.sh' -o -name '*.mjs' -o -name '*.cjs' \) -exec chmod +x {} + \
 && printf '\n# Restore baked claude settings after runtime baseline overwrite.\n. /home/agent/.local/bin/merge-claude-settings.sh\n' \
        >> /etc/sandbox-persistent.sh \
 && printf '\n# Wire codegraph into this agent + build/refresh the /workspace graph.\n. /home/agent/.local/bin/codegraph-setup.sh\n' \
        >> /etc/sandbox-persistent.sh
USER agent

ENTRYPOINT ["tini", "--"]
CMD ["claude"]
