# Custom Cursor CLI sandbox template
#   - Base: debian:bookworm-slim (glibc) — same rationale as opencode/: no
#     docker/sandbox-templates:cursor base exists, so this is the plain-docker
#     path, not an sbx extension (unlike claude/codex).
#   - cursor-agent (binary name: `agent`) installed at BUILD TIME via the
#     official installer (curl https://cursor.com/install -fsS | bash), run as
#     the "agent" user so it lands directly in $HOME/.local/{bin,share}. It is
#     a self-contained native binary — Node is NOT required to run it (unlike
#     opencode, which IS a Node/Bun program). Node here exists only for the
#     shared dev-tool trio (codegraph, agent-browser, playwright), same as the
#     other two suites.
#   - The installer has no version-pin knob (see prepare.ps1-adjacent notes in
#     README "Notes") — every build fetches whatever `cursor.com/install`
#     currently resolves to. Honest, unpinned, by design of the upstream script.
#   - Node 25 (NodeSource); no pnpm baked in (mirrors codex/, not opencode/) —
#     cursor-agent itself has no Node/npm dependency, so there is no
#     first-class reason to carry a package manager beyond plain npm here.
#   - Non-root "agent" user (uid 1000), matching the claude/opencode/codex templates.
#   - Host ~/.cursor/{cli-config.json,mcp.json} staged by prepare.ps1
#     (mcp.json local server `command` strings: Win paths → Linux/bare name).
#
# No credentials are baked into the image. `agent login`'s on-disk storage
# location isn't documented upstream, so — mirroring codex/'s documented
# decision (see codex/run.ps1 header) rather than guessing a path to bind-mount
# — run.ps1 authenticates fresh inside each ephemeral container (device-style
# browser login, or CURSOR_API_KEY passthrough for headless use).
#
# Build context expects ./context/.cursor populated by prepare.ps1.

FROM debian:bookworm-slim

USER root

ARG NODE_MAJOR=25
# Pinned for the same reason as the other suites (see
# .projex/2607081900-codegraph-integration-audit.md): a shared build artifact
# tracks an audited version explicitly, not @latest.
ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
ARG GO_VERSION=1.26.3
ARG INSTALL_GO=1
ARG INSTALL_PYTHON=1

# Baseline coding-agent tools + Node 25 via NodeSource (mirrors opencode/).
# Node is only needed here for codegraph/agent-browser/playwright — cursor-agent
# itself is installed later (as the agent user, via the official installer) and
# does not depend on this Node toolchain.
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
    npm install -g \
        "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" \
        "agent-browser@${AGENT_BROWSER_VERSION}" \
        "playwright@${PLAYWRIGHT_VERSION}"; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    node --version | grep -E "^v25\." || { echo "ERROR: expected Node 25, got $(node --version)"; exit 1; }; \
    codegraph --version; agent-browser --version; playwright --version

# Non-root agent user (uid 1000), matching claude/opencode/codex. bookworm-slim
# leaves uid 1000 free (no `node`-image squatter). NOPASSWD sudo for run.ps1's
# volume-chown bootstrap.
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
# agent, or the later cursor-agent installer (also HOME=/home/agent, but as
# USER agent) can't write its own state under ~/.local.
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache

# Optional Go (official tarball, pinned — apt's golang lags upstream; mirrors
# claude/opencode). Installs to /usr/local/go, symlinks onto PATH.
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

# Official installer (verbatim command the user runs on a real machine). Runs
# as the agent user so $HOME resolves to /home/agent and everything lands
# owned by agent directly — no separate chown needed. Not version-pinned: the
# script always resolves to whatever cursor.com/install currently serves (see
# README "Notes"). Verified immediately so a broken install fails the build,
# not the first container run.
RUN curl -fsS https://cursor.com/install | bash \
 && ~/.local/bin/agent --version

ENV PATH="/home/agent/.local/bin:${PATH}"

COPY --chown=agent:agent context/.cursor/ /home/agent/.cursor/

# agent-browser discovery stub — repo-owned (not host-synced), survives
# whatever is in the host's ~/.cursor/skills. Cursor's global skill location.
COPY --chown=agent:agent skills/agent-browser/ /home/agent/.cursor/skills/agent-browser/

ENTRYPOINT ["tini", "--"]
CMD ["agent"]
