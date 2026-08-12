FROM node:25-bookworm-slim

USER root

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    PATH=/usr/local/share/npm-global/bin:$PATH \
    BASH_ENV=/etc/sandbox-persistent.sh

ARG CODEGRAPH_VERSION=1.3.0
ARG AGENT_BROWSER_VERSION=0.31.1
ARG PLAYWRIGHT_VERSION=1.61.1
# packages.microsoft.com's apt versions always carry this literal "-1.deb"
# packaging suffix (e.g. 7.6.4-1.deb) — appended where the ARG is consumed.
ARG PWSH_VERSION=7.6.4

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        apt-transport-https ca-certificates curl git jq less openssh-client procps ripgrep tini tzdata \
        python3 build-essential; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    touch /etc/sandbox-persistent.sh; \
    chmod 0644 /etc/sandbox-persistent.sh; \
    printf '%s\n' \
        'export PATH=/usr/local/share/npm-global/bin:$PATH' \
        'if [ -f /etc/sandbox-persistent.sh ]; then . /etc/sandbox-persistent.sh; fi' \
        'export BASH_ENV=/etc/sandbox-persistent.sh' \
        > /etc/profile.d/sandbox-persistent.sh; \
    cp /etc/profile.d/sandbox-persistent.sh /root/.bashrc

RUN set -eux; \
    npm config set update-notifier false; \
    npm install -g @openai/codex "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" "agent-browser@${AGENT_BROWSER_VERSION}" "playwright@${PLAYWRIGHT_VERSION}"; \
    node --version; npm --version; codex --version; codegraph --version; agent-browser --version; playwright --version

RUN agent-browser install --with-deps
RUN playwright install --with-deps chromium

# PowerShell (pwsh) via Microsoft's official apt repo — apt/dpkg verify the
# repo's GPG-signed metadata directly, and the powershell package's own
# Depends pulls in whichever libicu Debian ships, so no manual checksum or
# ICU pin is needed. Placed after the browser installs so bumping
# PWSH_VERSION doesn't invalidate those expensive layers.
RUN set -eux; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL "https://packages.microsoft.com/config/debian/$(. /etc/os-release && echo "$VERSION_ID")/packages-microsoft-prod.deb" \
        -o /tmp/packages-microsoft-prod.deb; \
    dpkg -i /tmp/packages-microsoft-prod.deb; \
    rm -f /tmp/packages-microsoft-prod.deb; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "powershell=${PWSH_VERSION}-1.deb"; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    pwsh --version

RUN git config --system --add safe.directory '*' \
 && git config --system core.autocrlf input \
 && git config --system user.name 'agent' \
 && git config --system user.email 'agent@sandbox.local'

COPY rm-guard/rm-guard.sh /usr/local/libexec/rm-guard.sh
RUN set -eux; \
    chmod 0755 /usr/local/libexec/rm-guard.sh; \
    real_rm="$(readlink -f "$(command -v rm)")"; \
    cp "$real_rm" /usr/bin/rm.real; \
    ln -sf /usr/local/libexec/rm-guard.sh "$real_rm"; \
    rm --version >/dev/null; \
    mkdir -p /workspace/.git && echo test > /workspace/.git/HEAD; \
    if rm -rf /workspace/.git 2>/dev/null; then echo "ERROR: rm-guard did not block direct delete of /workspace/.git"; exit 1; fi; \
    [ -f /workspace/.git/HEAD ] || { echo "ERROR: /workspace/.git/HEAD missing after a supposedly-blocked delete"; exit 1; }; \
    if rm -rf /workspace 2>/dev/null; then echo "ERROR: rm-guard did not block ancestor delete of /workspace"; exit 1; fi; \
    [ -f /workspace/.git/HEAD ] || { echo "ERROR: /workspace/.git/HEAD missing after a supposedly-blocked ancestor delete"; exit 1; }; \
    touch /tmp/rm-guard-selftest && rm -f /tmp/rm-guard-selftest; \
    [ ! -e /tmp/rm-guard-selftest ] || { echo "ERROR: rm-guard blocked an unprotected delete"; exit 1; }; \
    /usr/bin/rm.real -rf /workspace

COPY context/.codex/config.toml /root/.codex/config.toml
COPY context/.codex/AGENTS.md /root/.codex/AGENTS.md
COPY context/.codex/skills/ /root/.codex/skills/
COPY skills/agent-browser/ /root/.codex/skills/agent-browser/
COPY context/.codex/vendor_imports/ /root/.codex/vendor_imports/
COPY context/.agents/skills/ /root/.agents/skills/

# Host-derived package metadata is inspected and installed only as this no-login
# user. Lifecycle scripts remain disabled; root copies the resulting files only.
COPY context/.codex/plugins/ /opt/codex-plugin-build/plugins/
COPY context/.codex/staged-input-inventory.json /opt/codex-plugin-build/staged-input-inventory.json
RUN set -eux; \
    useradd --system --create-home --shell /usr/sbin/nologin pluginbuild; \
    chown -R pluginbuild:pluginbuild /opt/codex-plugin-build; \
    test -s /opt/codex-plugin-build/staged-input-inventory.json; \
    su -s /bin/sh pluginbuild -c 'set -eu; for d in $(find /opt/codex-plugin-build/plugins/cache -maxdepth 8 -name package.json -printf "%h\\n"); do echo "[build] npm install (scripts disabled): $d"; (cd "$d" && npm install --ignore-scripts --no-audit --no-fund); done'; \
    mkdir -p /root/.codex/plugins; \
    cp -a /opt/codex-plugin-build/plugins/. /root/.codex/plugins/; \
    test ! -e /root/.codex/plugins/cache/host-lifecycle-marker; \
    { \
      sha256sum /usr/local/libexec/rm-guard.sh /etc/profile.d/sandbox-persistent.sh /root/.bashrc /root/.codex/staged-input-inventory.json; \
      find /root/.codex/plugins/cache -type f -name package.json -print0 | sort -z | xargs -0 -r sha256sum; \
    } > /root/.codex/critical-hashes.sha256; \
    rm -rf /opt/codex-plugin-build

USER root
WORKDIR /workspace

ENTRYPOINT ["tini", "--"]
CMD ["codex", "--dangerously-bypass-approvals-and-sandbox"]
