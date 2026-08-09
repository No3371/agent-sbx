
FROM node:25-bookworm-slim

USER root

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    PATH=/usr/local/share/npm-global/bin:/home/agent/.local/bin:$PATH \
    BASH_ENV=/etc/sandbox-persistent.sh

# Pin the audited version for reproducible shared builds.
ARG CODEGRAPH_VERSION=1.3.0
# Pinned alongside CodeGraph so browser automation is reproducible.
ARG AGENT_BROWSER_VERSION=0.31.1
# Playwright: browser test automation library, baked with Chromium for offline use.
ARG PLAYWRIGHT_VERSION=1.61.1

# Core tools plus native build tooling required by plugin dependencies.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl git jq less openssh-client procps ripgrep sudo tini tzdata \
        python3 build-essential; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# node:*-slim already has UID 1000 as user `node`; rename it so
# /home/agent paths match run.ps1 mounts and baked config.
RUN set -eux; \
    if id node >/dev/null 2>&1; then \
        usermod --login agent --home /home/agent --move-home --shell /bin/bash node; \
        groupmod --new-name agent node; \
    else \
        useradd --create-home --uid 1000 --shell /bin/bash agent; \
    fi; \
    usermod -aG sudo agent; \
    echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent; \
    chmod 0440 /etc/sudoers.d/agent; \
    mkdir -p /home/agent/.local/bin /home/agent/.local/share /home/agent/.local/state \
             /home/agent/.codex /usr/local/share/npm-global; \
    chown -R agent:agent /home/agent; \
    touch /etc/sandbox-persistent.sh; \
    chmod 0644 /etc/sandbox-persistent.sh; \
    printf '%s\n' \
        'export PATH=/usr/local/share/npm-global/bin:/home/agent/.local/bin:$PATH' \
        'if [ -f /etc/sandbox-persistent.sh ]; then . /etc/sandbox-persistent.sh; fi' \
        'export BASH_ENV=/etc/sandbox-persistent.sh' \
        > /etc/profile.d/sandbox-persistent.sh; \
    printf '%s\n' \
        'export PATH=/usr/local/share/npm-global/bin:/home/agent/.local/bin:$PATH' \
        'if [ -f /etc/sandbox-persistent.sh ]; then . /etc/sandbox-persistent.sh; fi' \
        'export BASH_ENV=/etc/sandbox-persistent.sh' \
        > /home/agent/.bashrc; \
    chown agent:agent /home/agent/.bashrc

RUN set -eux; \
    npm config set update-notifier false; \
    npm install -g @openai/codex "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" "agent-browser@${AGENT_BROWSER_VERSION}" "playwright@${PLAYWRIGHT_VERSION}"; \
    ln -sf /usr/local/share/npm-global/bin/codex /home/agent/.local/bin/codex; \
    ln -sf /usr/local/share/npm-global/bin/codegraph /home/agent/.local/bin/codegraph; \
    ln -sf /usr/local/share/npm-global/bin/agent-browser /home/agent/.local/bin/agent-browser; \
    ln -sf /usr/local/share/npm-global/bin/playwright /home/agent/.local/bin/playwright; \
    chown -h agent:agent /home/agent/.local/bin/codex /home/agent/.local/bin/codegraph /home/agent/.local/bin/agent-browser /home/agent/.local/bin/playwright; \
    node --version; npm --version; codex --version; codegraph --version; agent-browser --version; playwright --version

RUN HOME=/home/agent agent-browser install --with-deps \
 && chown -R agent:agent /home/agent/.agent-browser

# Playwright's own Chromium build + Linux system libs. HOME override lands it
# in the agent's cache instead of /root and avoids a runtime download.
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache/ms-playwright

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

COPY --chown=agent:agent context/.codex/config.toml        /home/agent/.codex/config.toml
COPY --chown=agent:agent context/.codex/AGENTS.md          /home/agent/.codex/AGENTS.md
COPY --chown=agent:agent context/.codex/skills/            /home/agent/.codex/skills/
COPY --chown=agent:agent skills/agent-browser/             /home/agent/.codex/skills/agent-browser/
COPY --chown=agent:agent context/.codex/vendor_imports/    /home/agent/.codex/vendor_imports/
COPY --chown=agent:agent context/.codex/plugins/           /home/agent/.codex/plugins/

RUN set -eux; \
    for d in $(find /home/agent/.codex/plugins/cache -maxdepth 8 -name package.json -printf '%h\n'); do \
        echo "[build] npm install: $d"; \
        (cd "$d" && npm install --no-audit --no-fund); \
    done

ENTRYPOINT ["tini", "--"]
CMD ["codex", "--dangerously-bypass-approvals-and-sandbox"]
