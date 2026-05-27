# Custom Claude Code sandbox template
#   - Latest Node (24 LTS) + pnpm via corepack
#   - .NET SDK 10 (latest)
#   - Go (official tarball, pinned via GO_VERSION)
#   - Python 3 + pip + venv (apt)
#   - Host .claude skills / agents / tools / commands / hooks / plugins /
#     settings.json mapped into the sandbox (paths rewritten Win → Linux by
#     prepare.ps1)
#   - SessionStart hook runs `npx gitnexus analyze` on the workspace
#
# sbx supplies host OAuth + ~/.claude.json itself; this template does not bake
# credentials, sessions, history, or plugin install state.
#
# Build context expects ./context/.claude/{settings.json,skills,agents,tools,
# commands,hooks,plugins} populated by prepare.ps1.

FROM docker/sandbox-templates:claude-code

# -------- system packages: Node 24 + .NET 10 + Go + Python --------
USER root

ARG NODE_MAJOR=24
ARG DOTNET_CHANNEL=10.0
ARG GO_VERSION=1.26.3

# Remove any Node shipped by the base image (nvm or apt) before installing
# NodeSource Node 24. Without purging first, two `node` binaries can land on
# PATH (apt's /usr/bin/node vs nvm's /home/agent/.nvm/...) and the agent shell
# may resolve the older one, making `pnpm` shims invisible to the agent.
RUN set -eux; \
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
    curl -fsSL "https://packages.microsoft.com/config/ubuntu/$(. /etc/os-release && echo "$VERSION_ID")/packages-microsoft-prod.deb" \
        -o /tmp/packages-microsoft-prod.deb; \
    dpkg -i /tmp/packages-microsoft-prod.deb; \
    rm -f /tmp/packages-microsoft-prod.deb; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs dotnet-sdk-${DOTNET_CHANNEL} \
        python3 python3-pip python3-venv; \
    corepack enable; \
    corepack prepare pnpm@latest --activate; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    # Verify root-shell versions
    node --version; npm --version; pnpm --version; dotnet --version; \
    python3 --version; pip3 --version

# -------- Go (official tarball, pinned) --------
# apt's golang-go lags upstream by months; pull the official linux-amd64 tarball
# instead. Installs to /usr/local/go, symlinks binaries into /usr/local/bin so
# they're on PATH for every shell context (including sbx's stripped exec env).
RUN set -eux; \
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
    ln -sf /usr/local/go/bin/go    /usr/local/bin/go; \
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt; \
    go version

# Confirm Node 24 and pnpm are visible from the agent shell (not masked by nvm).
RUN su - agent -c 'node --version && npm --version && pnpm --version' \
 && su - agent -c 'node --version' | grep -E "^v24\." \
 || { echo "ERROR: agent shell resolves wrong node (expected v24.x)"; exit 1; }

# -------- agent-level config --------
USER agent
WORKDIR /home/agent

# User customizations (skills/agents/tools/commands). prepare.ps1 creates
# empty placeholders for any that don't exist on host so COPY is stable.
COPY --chown=agent:agent context/.claude/skills/    /home/agent/.claude/skills/
COPY --chown=agent:agent context/.claude/agents/    /home/agent/.claude/agents/
COPY --chown=agent:agent context/.claude/tools/     /home/agent/.claude/tools/
COPY --chown=agent:agent context/.claude/commands/  /home/agent/.claude/commands/

# Host settings (rewritten by prepare.ps1: Win paths → Linux paths,
# statusLine rewritten (Win node path → bare node), gitnexus-analyze SessionStart
# hook injected) and hooks.
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

# Workspace-analyze script lives in the hook payload dir alongside host hooks
# so settings.json path references resolve uniformly.
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
 && chmod 0644 /etc/sandbox-persistent.sh
USER agent

# Install gitnexus globally so it's available without an npx download at first
# session-start. Pin version: update this when upgrading intentionally.
#
# Base image configures npm prefix to /usr/local/share/npm-global; that bin dir
# is on the interactive-login PATH but NOT on minimal-exec PATH (sbx may launch
# with a stripped env). Symlink into /usr/local/bin so the binary is findable
# from any shell context.
USER root
ARG GITNEXUS_VERSION=1.6.5
RUN npm config set update-notifier false \
 && npm install -g gitnexus@${GITNEXUS_VERSION} \
 && ln -sf /usr/local/share/npm-global/bin/gitnexus /usr/local/bin/gitnexus \
 && /usr/local/bin/gitnexus --version
USER agent

# Base image entrypoint (tini + base CMD) launches claude-code. The baked
# settings merge fires from /etc/sandbox-persistent.sh on every bash/claude
# spawn (see merge-claude-settings.sh), so the sbx case where the container
# CMD is replaced and claude is spawned via container-exec is covered.
