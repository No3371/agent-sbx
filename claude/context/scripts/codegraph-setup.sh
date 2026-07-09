#!/usr/bin/env bash
# codegraph-setup.sh
#
# Wires the codegraph MCP server into ~/.claude.json and builds the project's
# graph on first run. Runs on every claude launch (same CLAUDE_ENV_FILE /
# BASH_ENV hook as merge-claude-settings.sh) because run.ps1 bind-mounts the
# host's own ~/.claude.json over the image-baked one, so any wiring done at
# build time would be shadowed — this has to happen at runtime instead.
#
# `codegraph install` rewrites the same mcpServers entry every time (cheap,
# idempotent); `codegraph init` only runs once per project, guarded by the
# presence of .codegraph/ (auto-sync keeps it fresh after that).

command -v codegraph >/dev/null 2>&1 || return 0 2>/dev/null || exit 0

codegraph install --yes --target=claude --location=global >/tmp/codegraph-install.log 2>&1

if [ -d /workspace ] && [ ! -d /workspace/.codegraph ]; then
    (cd /workspace && codegraph init) >/tmp/codegraph-init.log 2>&1
fi
