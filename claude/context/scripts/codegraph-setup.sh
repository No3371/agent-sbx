#!/usr/bin/env bash
# Wire codegraph at runtime because run.ps1's ~/.claude.json mount shadows the
# baked configuration. Installation is idempotent; graph initialization runs
# once per project when .codegraph/ is absent.

command -v codegraph >/dev/null 2>&1 || return 0 2>/dev/null || exit 0

# run.ps1 bind-mounts ~/.claude.json as a file. CodeGraph's installer writes
# atomically (tmp + rename), but Docker cannot rename over a file mount (EBUSY).
# Update just its MCP entry in place first; the installer then leaves that file
# alone and still installs its settings and instructions.
if ! node - "$HOME/.claude.json" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
let config = {};

if (fs.existsSync(file)) {
    try {
        config = JSON.parse(fs.readFileSync(file, 'utf8') || '{}');
    } catch (error) {
        console.error(`CodeGraph: cannot parse ${file}: ${error.message}`);
        process.exit(1);
    }
}

config.mcpServers ??= {};
config.mcpServers.codegraph = {
    type: 'stdio',
    command: 'codegraph',
    args: ['serve', '--mcp'],
};

const fd = fs.openSync(file, fs.existsSync(file) ? 'r+' : 'w');
try {
    fs.ftruncateSync(fd, 0);
    fs.writeFileSync(fd, `${JSON.stringify(config, null, 2)}\n`);
    fs.fsyncSync(fd);
} finally {
    fs.closeSync(fd);
}
NODE
then
    echo "CodeGraph MCP registration failed; see the error above." >&2
    return 0 2>/dev/null || exit 0
fi

codegraph install --yes --target=claude --location=global >/tmp/codegraph-install.log 2>&1

if [ -d /workspace ] && [ ! -d /workspace/.codegraph ]; then
    (cd /workspace && codegraph init) >/tmp/codegraph-init.log 2>&1
fi
