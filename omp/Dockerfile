# Build context expects ./context/.omp/agent populated by prepare.ps1.

ARG OMP_BASE=oh-my-pi/pi:dev
FROM ${OMP_BASE}

USER root

ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
ARG INSTALL_GO=1
ARG GO_VERSION=1.26.3
ARG INSTALL_DOTNET=1
ARG DOTNET_VERSION=10.0

ARG CONTEXT_MODE_VERSION=1.0.169

RUN set -eux; \
    for flag in "$INSTALL_GO" "$INSTALL_DOTNET"; do case "$flag" in 0|1) ;; *) echo "INSTALL_* must be 0 or 1" >&2; exit 1 ;; esac; done; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash ca-certificates curl git gnupg jq less openssh-client ripgrep sudo tini tzdata apt-transport-https; \
    install -d -m 0755 /etc/apt/keyrings; \
    apt-get update; \
    # Download and install nvm:
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh" | bash; \
    # in lieu of restarting the shell
    . "$HOME/.nvm/nvm.sh"; \
    # Download and install Node.js:
    nvm install 26; \
    # Verify the Node.js version:
    node -v; \
    # Verify npm version:
    npm -v; \
    npm i -g --ignore-scripts "@colbymchenry/codegraph@${CODEGRAPH_VERSION}"; \
    for cmd in bun node npm npx codegraph; do \
        ln -sf "$(command -v "$cmd")" "/usr/local/bin/$cmd"; \
    done; \
    bun install -g pnpm@latest; \
    bun install -g --ignore-scripts \
        "agent-browser@${AGENT_BROWSER_VERSION}" \
        "playwright@${PLAYWRIGHT_VERSION}"; \
    bun pm -g untrusted; \
    bun pm -g trust agent-browser; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    omp --version; codegraph --version; agent-browser --version; playwright --version; (cd /tmp && pnpm --version);

RUN apt-get update \
 && agent-browser install --with-deps

RUN playwright install --with-deps chromium

# Optional Go (official tarball, pinned — apt's golang lags upstream; mirrors
# claude/opencode/cursor). Installs to /usr/local/go, symlinks onto PATH.
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

RUN set -eux; \
apt-get update; \
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3 python3-pip python3-venv; \
python3 --version; pip3 --version; \
apt-get clean; \
rm -rf /var/lib/apt/lists/*;

ENV PATH="/usr/local/sbin:/usr/sbin:/sbin:${PATH}"
# Optional Dotnet SDK (apt)
RUN set -eux; \
    if [ "$INSTALL_DOTNET" = "1" ]; then \
        curl -fsSL \
            https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb \
            -o /tmp/packages-microsoft-prod.deb; \
        dpkg -i /tmp/packages-microsoft-prod.deb; \
        rm /tmp/packages-microsoft-prod.deb; \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            "dotnet-sdk-${DOTNET_VERSION}"; \
        rm -rf /var/lib/apt/lists/*; \
        dotnet --info; \
    fi


RUN git config --system core.autocrlf input \
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

COPY context/.omp/agent /root/.omp/agent
COPY context/.omp/plugins /root/.omp/plugins

# prepare.ps1 skips node_modules/ from plugins/ (built on the host — Windows
# — native .node addons like context-mode's better-sqlite3 won't load in this
# Linux container).
RUN set -eux; \
    cd /root/.omp/plugins; \
    omp plugin install $(jq -r '.dependencies | to_entries[] | "\(.key)@\(.value)"' package.json)

# Discovery stubs for the CLIs baked above — repo-owned (not host-synced), so
# they survive whatever is in the host's ~/.omp/agent/skills. Agent Skills
# standard location; everything under skills/ ships, so a new stub needs no
# Dockerfile change. codegraph is wired as a plain CLI + skill rather than over
# MCP because `codegraph install` has no omp target. See skills/*/SKILL.md.
COPY skills/ /root/.omp/agent/skills/

CMD ["launch"]
