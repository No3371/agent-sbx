# Custom Codex CLI sandbox template
#   - Node 24 LTS (upgrades base Node 20)
#   - @openai/codex pre-installed in base
#   - Host ~/.codex/{config.toml,AGENTS.md,skills/,vendor_imports/skills/}
#     staged by prepare.ps1 (Win paths rewritten, Win/marketplace/project sections stripped)
#
# sbx supplies host OAuth + auth at runtime; nothing credential-related is baked.
# Build context expects ./context/.codex/{...} populated by prepare.ps1.

FROM docker/sandbox-templates:codex

USER root

ARG NODE_MAJOR=24
# Pinned, not @latest — a shared build artifact should track an audited
# version explicitly (see .projex/2607081900-codegraph-integration-audit.md).
ARG CODEGRAPH_VERSION=1.3.0
# agent-browser: browser automation CLI for agents (github.com/vercel-labs/agent-browser).
# Pinned for the same reason as codegraph above.
ARG AGENT_BROWSER_VERSION=0.31.1
# Playwright: baked so JS/TS/Node projects that use it for browser testing don't
# hit a cold `playwright install` mid-task. Pinned for the same reason as above.
ARG PLAYWRIGHT_VERSION=1.61.1

# Upgrade Node 20 (base) → Node 24 via NodeSource. Purge existing apt/nvm Node
# first to prevent dual-binary PATH confusion (same rationale as claude/ variant).
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg apt-transport-https; \
    apt-get purge -y nodejs || true; \
    rm -rf /home/agent/.nvm /usr/local/bin/node /usr/local/bin/npm \
           /usr/local/bin/npx /usr/local/lib/node_modules; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs python3 build-essential; \
    # codegraph: semantic code-intelligence MCP server for agents.
    # agent-browser: browser automation CLI for agents (Chrome via CDP).
    # playwright: browser test automation library.
    npm install -g "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" "agent-browser@${AGENT_BROWSER_VERSION}" "playwright@${PLAYWRIGHT_VERSION}"; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    node --version | grep -E "^v24\." \
        || { echo "ERROR: expected Node 24, got $(node --version)"; exit 1; }; \
    codegraph --version; agent-browser --version; playwright --version

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

# sbx bind-mounts /workspace with the host's ownership, tripping git's
# dubious-ownership guard; and a fresh container has no git identity, so the
# agent's first commit fails until one is set. System config is the
# lowest-precedence layer, so any user/global config set later still wins.
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

COPY --chown=agent:agent context/.codex/config.toml        /home/agent/.codex/config.toml
COPY --chown=agent:agent context/.codex/AGENTS.md          /home/agent/.codex/AGENTS.md
COPY --chown=agent:agent context/.codex/skills/            /home/agent/.codex/skills/
# agent-browser discovery stub — Dockerfile-owned (not host-synced), so it
# survives regardless of what's on the host's ~/.codex/skills.
COPY --chown=agent:agent skills/agent-browser/             /home/agent/.codex/skills/agent-browser/
COPY --chown=agent:agent context/.codex/vendor_imports/    /home/agent/.codex/vendor_imports/

# Installed plugin bundles (context-mode, ponytail, bundled browser/chrome,
# etc.) referenced by config.toml's [plugins.*] entries.
COPY --chown=agent:agent context/.codex/plugins/           /home/agent/.codex/plugins/

# prepare.ps1 skips node_modules/ from plugins/cache/ (it's built on the
# host — Windows — and native .node addons like context-mode's better-sqlite3
# won't load in this Linux container). Reinstall for every plugin dir that
# ships a package.json so native deps get rebuilt for Linux instead of
# silently missing. build-essential (above) covers node-gyp compilation for
# any addon without a prebuilt Linux binary.
RUN set -eux; \
    for d in $(find /home/agent/.codex/plugins/cache -maxdepth 8 -name package.json -printf '%h\n'); do \
        echo "[build] npm install: $d"; \
        (cd "$d" && npm install --no-audit --no-fund); \
    done

CMD ["codex", "--dangerously-bypass-approvals-and-sandbox"]
