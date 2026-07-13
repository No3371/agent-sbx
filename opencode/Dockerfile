# Custom OpenCode sandbox template
#   - Base: ghcr.io/anomalyco/opencode (Alpine + opencode binary only, runs as root)
#   - Adds git/bash/curl/jq/openssh/sudo/tini — the baseline a coding agent needs
#     to actually work in a repo, plus a non-root "agent" user matching the
#     claude/codex templates
#   - Host ~/.config/opencode (opencode.json, AGENTS.md, plugin/, skills/, ...)
#     copied in as-is by prepare.ps1 — no rewriting, unlike claude/codex
#
# No docker/sandbox-templates:opencode base exists (unlike claude/codex), so
# there's no sbx integration here — this is the plain-docker path, run via
# run.ps1. Host auth (~/.local/share/opencode/auth.json) is bind-mounted at
# runtime by run.ps1; nothing credential-related is baked into the image.
#
# Build context expects ./context/.config/opencode populated by prepare.ps1.

FROM ghcr.io/anomalyco/opencode

RUN apk add --no-cache bash ca-certificates curl git jq less openssh-client sudo tini tzdata

# Optional language toolchains (Alpine-native, musl). The claude image's
# apt/Go-tarball path does not apply here; apk go/python3 are musl-built and
# come from the base's already-enabled main/community repos (Alpine 3.24).
# Toggled by build.ps1 -Enable/-Disable via INSTALL_* build-args (default on).
# ponytail: apk versions left unpinned — Alpine has no stable per-version pin
# story for these the way the tarball/apt path did; documented drift (see
# plan Notes / redteam Finding 8).
ARG INSTALL_GO=1
ARG INSTALL_PYTHON=1
RUN set -eux; \
    for flag in "$INSTALL_GO" "$INSTALL_PYTHON"; do case "$flag" in 0|1) ;; *) echo "INSTALL_* must be 0 or 1" >&2; exit 1 ;; esac; done; \
    if [ "$INSTALL_GO" = "1" ]; then apk add --no-cache go && go version; fi; \
    if [ "$INSTALL_PYTHON" = "1" ]; then apk add --no-cache python3 py3-pip && python3 --version; fi

# agent-browser: browser automation CLI for agents (github.com/vercel-labs/agent-browser).
# codegraph: semantic code-intelligence MCP server for agents. Both are pinned,
# not @latest, matching the claude/codex images. Alpine has no Node in the base,
# so add nodejs/npm as the install channel — which also makes node baseline for
# run.ps1's node_modules reinstall path. Node 24 no longer bundles corepack, so
# install it explicitly + activate pnpm (run.ps1's pnpm branch depends on it).
# The daemon needs a browser:
# `agent-browser install` would fetch Chrome for Testing (glibc) which will NOT
# run on musl — install Alpine's musl-native Chromium instead and point
# agent-browser at it via AGENT_BROWSER_EXECUTABLE_PATH (/usr/bin/chromium,
# verified). The `--version` smoke test fails the build here if a release ships
# a glibc-only binary (assumption 1 — verified musl-OK at authoring time).
# Playwright, same musl problem: `playwright install chromium` fetches a
# glibc-only build that won't run here. PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD skips
# that fetch; the `playwright` package itself still installs so JS/TS/Node
# projects can `require('playwright')`. A project that needs to actually
# launch a browser must point it at the musl-native /usr/bin/chromium already
# installed below, e.g. `chromium.launch({ executablePath: '/usr/bin/chromium' })`.
ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
RUN apk add --no-cache nodejs npm chromium \
 && npm install -g corepack \
 && corepack enable \
 && corepack prepare pnpm@latest --activate \
 && npm install -g "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" "agent-browser@${AGENT_BROWSER_VERSION}" "playwright@${PLAYWRIGHT_VERSION}" \
 && ln -sf "$(command -v node)" "$(npm root -g)/@colbymchenry/codegraph/node_modules/@colbymchenry/codegraph-linux-x64/node" \
 && node --version && npm --version && pnpm --version && codegraph --version && agent-browser --version && playwright --version

# sbx/host bind-mounts can leave /workspace owned differently than the agent
# user, tripping git's dubious-ownership guard; and a fresh container has no
# git identity, so the agent's first commit fails until one is set. System
# config is the lowest-precedence layer, so any user/global config set later
# still wins.
RUN git config --system --add safe.directory '*' \
 && git config --system core.autocrlf input \
 && git config --system user.name 'agent' \
 && git config --system user.email 'agent@sandbox.local'

RUN adduser -D -u 1000 -s /bin/bash agent \
 && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
 && chmod 0440 /etc/sudoers.d/agent \
 && mkdir -p /home/agent/.local/share/opencode /home/agent/.local/state/opencode \
 && chown -R agent:agent /home/agent

USER agent
WORKDIR /home/agent

COPY --chown=agent:agent context/.config/opencode/ /home/agent/.config/opencode/

# agent-browser discovery stub — repo-owned (not host-synced), survives whatever
# is in the host's ~/.config/opencode/skills. opencode global skill location.
COPY --chown=agent:agent skills/agent-browser/ /home/agent/.config/opencode/skills/agent-browser/

ENTRYPOINT ["tini", "--"]
CMD ["opencode"]
