# Custom Claude Code sandbox template
#   - Node 25 + pnpm (global npm install)
#   - .NET SDK 10 (latest)
#   - Go (official tarball, pinned via GO_VERSION)
#   - Python 3 + pip + venv (apt)
#   - Host .claude skills / agents / tools / commands / hooks / plugins /
#     settings.json mapped into the sandbox (paths rewritten Win → Linux by
#     prepare.ps1)
#
# sbx supplies host OAuth + ~/.claude.json itself; this template does not bake
# credentials, sessions, history, or plugin install state.
#
# Build context expects ./context/.claude/{settings.json,skills,agents,tools,
# commands,hooks,plugins} populated by prepare.ps1.

FROM docker/sandbox-templates:claude-code

# -------- system packages: Node 25 + optional .NET, Go, Python --------
USER root

ARG NODE_MAJOR=25
ARG DOTNET_CHANNEL=10.0
ARG GO_VERSION=1.26.3
ARG INSTALL_GO=1
ARG INSTALL_DOTNET=1
ARG INSTALL_PYTHON=1
# Pinned, not @latest — a shared build artifact should track an audited
# version explicitly (see .projex/2607081900-codegraph-integration-audit.md).
ARG CODEGRAPH_VERSION=1.3.0
# agent-browser: browser automation CLI for agents (github.com/vercel-labs/agent-browser).
# Pinned for the same reason as codegraph above.
ARG AGENT_BROWSER_VERSION=0.31.1
# Playwright: baked so JS/TS/Node projects that use it for browser testing don't
# hit a cold `playwright install` mid-task. Pinned for the same reason as above.
ARG PLAYWRIGHT_VERSION=1.61.1

# Remove any Node shipped by the base image (nvm or apt) before installing
# NodeSource Node 25. Without purging first, two `node` binaries can land on
# PATH (apt's /usr/bin/node vs nvm's /home/agent/.nvm/...) and the agent shell
# may resolve the older one, making `pnpm` shims invisible to the agent.
RUN set -eux; \
    for flag in "$INSTALL_GO" "$INSTALL_DOTNET" "$INSTALL_PYTHON"; do case "$flag" in 0|1) ;; *) echo "INSTALL_* must be 0 or 1" >&2; exit 1 ;; esac; done; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg apt-transport-https; \
    # Purge any apt-managed nodejs first (ignore error if not installed)
    apt-get purge -y nodejs || true; \
    # Remove nvm-managed Node that the base image may have installed for agent
    rm -rf /home/agent/.nvm /usr/local/bin/node /usr/local/bin/npm \
           /usr/local/bin/npx /usr/local/lib/node_modules; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs build-essential; \
    npm install -g pnpm@latest; \
    # codegraph: semantic code-intelligence MCP server for agents.
    # agent-browser: browser automation CLI for agents (Chrome via CDP).
    # playwright: browser test automation library.
    npm install -g "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" "agent-browser@${AGENT_BROWSER_VERSION}" "playwright@${PLAYWRIGHT_VERSION}"; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    # Verify root-shell versions
    node --version; npm --version; pnpm --version; codegraph --version; agent-browser --version; playwright --version

RUN set -eux; \
    if [ "$INSTALL_DOTNET" = "1" ]; then \
        install -d -m 0755 /etc/apt/keyrings; \
        curl -fsSL "https://packages.microsoft.com/config/ubuntu/$(. /etc/os-release && echo "$VERSION_ID")/packages-microsoft-prod.deb" -o /tmp/packages-microsoft-prod.deb; \
        dpkg -i /tmp/packages-microsoft-prod.deb; \
        rm -f /tmp/packages-microsoft-prod.deb; \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends dotnet-sdk-${DOTNET_CHANNEL}; \
        dotnet --version; \
    fi; \
    if [ "$INSTALL_PYTHON" = "1" ]; then \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3 python3-pip python3-venv; \
        python3 --version; pip3 --version; \
    fi; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# agent-browser install: downloads Chrome for Testing + installs Linux system
# libs (--with-deps, needs root/apt). HOME is overridden to the agent's home
# so Chrome and config land there directly instead of under /root, avoiding a
# second download once we drop to USER agent below.
RUN HOME=/home/agent agent-browser install --with-deps \
 && chown -R agent:agent /home/agent/.agent-browser

# Playwright's own Chromium build + Linux system libs (--with-deps, needs
# root/apt), baked at build time rather than left for a project's first
# `playwright install` to do cold. HOME override lands it in the agent's cache
# instead of /root, avoiding a second download after USER agent below.
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache/ms-playwright

# -------- Go (official tarball, pinned) --------
# apt's golang-go lags upstream by months; pull the official linux-amd64 tarball
# instead. Installs to /usr/local/go, symlinks binaries into /usr/local/bin so
# they're on PATH for every shell context (including sbx's stripped exec env).
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

# Confirm Node 25 and pnpm are visible from the agent shell (not masked by nvm).
RUN su - agent -c 'node --version && npm --version && pnpm --version' \
 && su - agent -c 'node --version' | grep -E "^v25\." \
 || { echo "ERROR: agent shell resolves wrong node (expected v25.x)"; exit 1; }

# sbx bind-mounts /workspace with the host's ownership, tripping git's
# dubious-ownership guard; and a fresh container has no git identity, so the
# agent's first commit fails until one is set. System config is the
# lowest-precedence layer, so any user/global config set later still wins.
RUN git config --system --add safe.directory '*' \
 && git config --system core.autocrlf input \
 && git config --system user.name 'agent' \
 && git config --system user.email 'agent@sandbox.local'

# -------- agent-level config --------
USER agent
WORKDIR /home/agent

# User customizations (skills/agents/tools/commands). prepare.ps1 creates
# empty placeholders for any that don't exist on host so COPY is stable.
COPY --chown=agent:agent context/.claude/skills/    /home/agent/.claude/skills/
# agent-browser discovery stub — Dockerfile-owned (not host-synced), so it
# survives regardless of what's on the host's ~/.claude/skills.
COPY --chown=agent:agent skills/agent-browser/      /home/agent/.claude/skills/agent-browser/
COPY --chown=agent:agent context/.claude/agents/    /home/agent/.claude/agents/
COPY --chown=agent:agent context/.claude/tools/     /home/agent/.claude/tools/
COPY --chown=agent:agent context/.claude/commands/  /home/agent/.claude/commands/

# Host settings (rewritten by prepare.ps1: Win paths → Linux paths,
# statusLine rewritten (Win node path → bare node) and hooks.
#
# settings.json lands at user level; sbx rewrites it with its own auth/permissions
# baseline at sandbox boot, clobbering the baked content. To survive that, an
# identical copy is stashed at /home/agent/.claude-bake/settings.local.json and
# merged back on top of sbx's baseline by merge-claude-settings.sh, sourced
# from /etc/sandbox-persistent.sh (the base image's BASH_ENV / CLAUDE_ENV_FILE
# hook, empty in the base, intended for runtime env setup).
#
# sbx replaces the container CMD with a sleep sentinel and invokes claude via
# container-exec — so a CMD-wrapper approach never runs. The BASH_ENV hook fires
# for every non-interactive bash invocation; CLAUDE_ENV_FILE is consulted by
# claude itself. Either path triggers our merge before settings.json is read.
COPY --chown=agent:agent context/.claude/settings.json       /home/agent/.claude/settings.json
COPY --chown=agent:agent context/.claude/settings.local.json /home/agent/.claude-bake/settings.local.json
COPY --chown=agent:agent context/.claude/hooks/              /home/agent/.claude/hooks/

# Plugins payload (marketplaces + installed plugin assets). settings.json
# `enabledPlugins` is preserved by prepare.ps1 so this stays wired up.
COPY --chown=agent:agent context/.claude/plugins/      /home/agent/.claude/plugins/

# Build-time install pilot (see .projex/2607100235-context-mode-build-time-install-pilot-plan.md).
# prepare.ps1 strips context-mode's host-vendored payload + registry entries, so it is
# installed fresh here against the container's own Linux filesystem — no host-baked paths
# to rewrite. Public GitHub marketplace, no auth. Runs BEFORE the npm loop below so
# context-mode's better-sqlite3 gets rebuilt for Linux by that same loop.
RUN set -eux; \
    claude plugin marketplace add mksglu/context-mode; \
    claude plugin install context-mode@context-mode --scope user

# prepare.ps1 skips node_modules/ from plugins/ (it's built on the host —
# Windows — and native .node addons like context-mode's better-sqlite3 won't
# load in this Linux container). Reinstall for every plugin/marketplace dir
# that ships a package.json so native deps get rebuilt for Linux instead of
# silently missing. build-essential (above) covers node-gyp compilation for
# any addon without a prebuilt Linux binary.
RUN set -eux; \
    for d in $(find /home/agent/.claude/plugins -maxdepth 8 -name package.json -printf '%h\n'); do \
        echo "[build] npm install: $d"; \
        (cd "$d" && npm install --no-audit --no-fund); \
    done

COPY --chown=agent:agent context/scripts/ /home/agent/.local/bin/

RUN chmod +x /home/agent/.local/bin/*.sh \
 && find /home/agent/.claude/hooks -type f \( -name '*.sh' -o -name '*.mjs' -o -name '*.cjs' \) -exec chmod +x {} +

# Wire merge-claude-settings.sh into /etc/sandbox-persistent.sh so it runs
# before any non-interactive bash invocation (BASH_ENV) and before claude
# itself reads settings (CLAUDE_ENV_FILE) — both point at this file in the base
# image. See merge-claude-settings.sh header for the full rationale.
#
# The merge requires `jq` (present in base image) and is idempotent under
# repeated invocations (probe-skips if `extraKnownMarketplaces` is already
# present in the target), so the constant-fire cost is negligible.
USER root
RUN printf '\n# Restore baked claude settings after sbx baseline overwrite.\nsource /home/agent/.local/bin/merge-claude-settings.sh\n' \
        >> /etc/sandbox-persistent.sh \
 && printf '\n# Wire codegraph into this agent + build/refresh the /workspace graph.\nsource /home/agent/.local/bin/codegraph-setup.sh\n' \
        >> /etc/sandbox-persistent.sh \
 && chmod 0644 /etc/sandbox-persistent.sh
USER agent

# Base image entrypoint (tini + base CMD) launches claude-code. The baked
# settings merge fires from /etc/sandbox-persistent.sh on every bash/claude
# spawn (see merge-claude-settings.sh), so the sbx case where the container
# CMD is replaced and claude is spawned via container-exec is covered.
