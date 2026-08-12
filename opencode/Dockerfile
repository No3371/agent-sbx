# OpenCode sandbox built on Debian/glibc with pinned npm tooling. prepare.ps1
# stages OpenCode and cross-agent configuration into the build context and
# rewrites Windows MCP paths. run.ps1 bind-mounts host authentication at run
# time; credentials are never baked into the image.

FROM debian:bookworm-slim

USER root

ARG NODE_MAJOR=25
# Installed at build time (glibc opencode-linux-x64 via npm). Pinned, not
# @latest — a shared build artifact tracks an audited version explicitly.
ARG OPENCODE_VERSION=1.18.15
# Pinned for the same reason (see 2607081900-codegraph-integration-audit.md).
ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
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
        bash ca-certificates curl git gnupg jq less openssh-client sudo tini tzdata apt-transport-https; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs build-essential; \
    npm install -g pnpm@latest; \
    npm install -g \
        "opencode-ai@${OPENCODE_VERSION}" \
        "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" \
        "agent-browser@${AGENT_BROWSER_VERSION}" \
        "playwright@${PLAYWRIGHT_VERSION}"; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    node --version | grep -E "^v25\." || { echo "ERROR: expected Node 25, got $(node --version)"; exit 1; }; \
    opencode --version; codegraph --version; agent-browser --version; playwright --version

# Non-root agent user (uid 1000), matching claude/codex. bookworm-slim leaves
# uid 1000 free (no `node`-image squatter). NOPASSWD sudo for run.ps1's
# volume-chown bootstrap.
RUN useradd --create-home --uid 1000 --shell /bin/bash agent \
 && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
 && chmod 0440 /etc/sudoers.d/agent \
 && mkdir -p /home/agent/.local/share/opencode /home/agent/.local/state/opencode \
 && chown -R agent:agent /home/agent

# Refresh apt metadata for Chrome's system dependencies, then install Chrome
# into the agent's home and restore agent ownership.
RUN apt-get update \
 && HOME=/home/agent agent-browser install --with-deps \
 && chown -R agent:agent /home/agent/.agent-browser

# Playwright runs as root and creates an agent-home cache; restore ownership so
# OpenCode can create its own cache as the agent user.
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache

# Optional pinned Go from the official tarball because apt lags upstream.
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

# Bind-mounts can leave /workspace owned differently than agent (git's
# dubious-ownership guard), and a fresh container has no git identity. System
# config is lowest-precedence, so any user/global config set later still wins.
RUN git config --system --add safe.directory '*' \
 && git config --system core.autocrlf input \
 && git config --system user.name 'agent' \
 && git config --system user.email 'agent@sandbox.local'

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

USER agent
WORKDIR /home/agent

COPY --chown=agent:agent context/.config/opencode/ /home/agent/.config/opencode/

# agent-browser discovery stub — repo-owned (not host-synced), survives whatever
# is in the host's ~/.config/opencode/skills. opencode global skill location.
COPY --chown=agent:agent skills/agent-browser/ /home/agent/.config/opencode/skills/agent-browser/

# Cross-agent skills standard: opencode also auto-loads
# ~/.agents/skills/<name>/SKILL.md. Staged from host ~/.agents/skills by
# prepare.ps1.
COPY --chown=agent:agent context/.agents/skills/ /home/agent/.agents/skills/

ENTRYPOINT ["tini", "--"]
CMD ["opencode"]
