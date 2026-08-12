# Pi sandbox built on Debian/glibc with pinned npm tooling. prepare.ps1 stages
# Pi and cross-agent configuration while excluding credentials. run.ps1 mounts
# host authentication at run time; credentials are never baked into the image.

FROM debian:bookworm-slim

USER root

ARG NODE_MAJOR=25
ARG PI_VERSION=0.84.1
# Pin the audited adapter version and re-audit before upgrading it.
ARG PI_MCP_ADAPTER_VERSION=2.21.1
ARG PI_SUBAGENTS_VERSION=0.14.3
ARG PI_LENS_VERSION=3.8.74
# Pinned for the same reason (see 2607081900-codegraph-integration-audit.md).
ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
ARG CONTEXT_MODE_VERSION=1.0.169
ARG GO_VERSION=1.26.3
ARG INSTALL_GO=1
ARG INSTALL_PYTHON=1
# packages.microsoft.com's apt versions always carry this literal "-1.deb"
# packaging suffix (e.g. 7.6.4-1.deb) — appended where the ARG is consumed.
ARG PWSH_VERSION=7.6.4
ARG INSTALL_PWSH=1

# Install Node 25 through NodeSource and stock npm packages on glibc. Install
# pnpm directly because Node 25 no longer bundles corepack.
RUN set -eux; \
    for flag in "$INSTALL_GO" "$INSTALL_PYTHON" "$INSTALL_PWSH"; do case "$flag" in 0|1) ;; *) echo "INSTALL_* must be 0 or 1" >&2; exit 1 ;; esac; done; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash ca-certificates curl ripgrep git gnupg jq less openssh-client sudo tini tzdata apt-transport-https; \
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
    pi --version; codegraph --version; agent-browser --version; playwright --version

# agent-browser install: Chrome for Testing + Linux system libs (--with-deps);
# installs into /root, which is also the runtime user's home — no ownership
# fixup needed.
RUN apt-get update \
 && agent-browser install --with-deps \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN playwright install --with-deps chromium

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

# Optional PowerShell (pwsh) via Microsoft's official apt repo — apt/dpkg
# verify the repo's GPG-signed metadata directly, and the powershell
# package's own Depends pulls in whichever libicu Debian ships, so no manual
# checksum or ICU pin is needed.
RUN set -eux; \
    if [ "$INSTALL_PWSH" = "1" ]; then \
        curl -fsSL "https://packages.microsoft.com/config/debian/$(. /etc/os-release && echo "$VERSION_ID")/packages-microsoft-prod.deb" \
            -o /tmp/packages-microsoft-prod.deb; \
        dpkg -i /tmp/packages-microsoft-prod.deb; \
        rm -f /tmp/packages-microsoft-prod.deb; \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "powershell=${PWSH_VERSION}-1.deb"; \
        apt-get clean; \
        rm -rf /var/lib/apt/lists/*; \
        pwsh --version; \
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

# Bind-mounts can leave /workspace owned differently than the container user
# (git's dubious-ownership guard), and a fresh container has no git identity. System
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

COPY context/.pi/ /root/.pi/
COPY context/.pi-lens/ /root/.pi-lens/

# Cross-agent skills standard: pi auto-loads ~/.agents/skills (global, always
# trusted — unlike project-local .agents/skills, which is trust-gated). Staged
# from host ~/.agents/skills by prepare.ps1.
COPY context/.agents/skills/ /root/.agents/skills/

# Pi needs the MCP adapter for MCP support. Install it after copying host context
# so registration is not overwritten. This container has no OS credential store,
# so MCP OAuth fails closed; use bearer or runtime environment authentication.
RUN pi install "npm:pi-mcp-adapter@${PI_MCP_ADAPTER_VERSION}"
RUN pi install "npm:context-mode@${CONTEXT_MODE_VERSION}"
RUN pi install "npm:@tintinweb/pi-subagents@${PI_SUBAGENTS_VERSION}"
RUN pi install "npm:pi-lens@${PI_LENS_VERSION}"

# Configure codegraph through the MCP bridge because its installer has no Pi
# target. Preserve a host-staged entry when present and use lazy-keep-alive to
# avoid startup and repeated reconnect costs. Strict jq rejects non-JSON input.
RUN set -eux; \
    cfg=/root/.pi/agent/mcp.json; \
    entry='{"command":"codegraph","args":["serve","--mcp"],"lifecycle":"lazy-keep-alive"}'; \
    mkdir -p /root/.pi/agent; \
    if [ -f "$cfg" ]; then \
        jq --argjson e "$entry" '.mcpServers = (.mcpServers // {}) | .mcpServers.codegraph = (.mcpServers.codegraph // $e)' "$cfg" > "$cfg.tmp"; \
        mv "$cfg.tmp" "$cfg"; \
    else \
        printf '{"mcpServers":{"codegraph":%s}}\n' "$entry" > "$cfg"; \
    fi; \
    jq -e '.mcpServers.codegraph' "$cfg" >/dev/null

# agent-browser discovery stub — repo-owned (not host-synced), survives
# whatever is in the host's ~/.pi skills. pi global skill location.
COPY skills/agent-browser/ /root/.pi/agent/skills/agent-browser/

WORKDIR /workspace
# tini as PID 1 (zombie reaping, signal forwarding — pi spawns shell tools and
# Chromium subprocesses) with pi as the default command, so a bare
# `docker run <image> [args]` still behaves like the pi CLI. run.ps1 overrides
# the entrypoint to run its bootstrap shell under the same tini.
ENTRYPOINT ["tini", "--", "pi"]
