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

# codegraph: semantic code-intelligence MCP server for agents (see
# .projex/2607081900-codegraph-integration-audit.md). No Node in this Alpine
# base, so use the self-contained bundle installer instead of npm; pinned,
# not @latest, matching the claude/codex images. Installed system-wide (not
# $HOME, which is /root here) so the agent user picks it up too.
ARG CODEGRAPH_VERSION=v1.3.0
RUN CODEGRAPH_VERSION=${CODEGRAPH_VERSION} CODEGRAPH_INSTALL_DIR=/opt/codegraph CODEGRAPH_BIN_DIR=/usr/local/bin \
    sh -c 'curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh' \
 && codegraph --version

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

ENTRYPOINT ["tini", "--"]
CMD ["opencode"]
