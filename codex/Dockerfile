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
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    node --version | grep -E "^v24\." \
        || { echo "ERROR: expected Node 24, got $(node --version)"; exit 1; }

USER agent
WORKDIR /home/agent

COPY --chown=agent:agent context/.codex/config.toml        /home/agent/.codex/config.toml
COPY --chown=agent:agent context/.codex/AGENTS.md          /home/agent/.codex/AGENTS.md
COPY --chown=agent:agent context/.codex/skills/            /home/agent/.codex/skills/
COPY --chown=agent:agent context/.codex/vendor_imports/    /home/agent/.codex/vendor_imports/
