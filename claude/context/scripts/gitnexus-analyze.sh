#!/usr/bin/env bash
# gitnexus-analyze.sh
# Runs `gitnexus analyze` once per workspace on SessionStart.
# Writes a marker at <workspace>/.gitnexus/.analyzed to skip re-runs.
# Delete the marker to force re-analysis.
set -euo pipefail

WORKSPACE="${CLAUDE_WORKSPACE:-$(pwd)}"
MARKER="${WORKSPACE}/.gitnexus/.analyzed"

if [[ -f "$MARKER" ]]; then
    exit 0
fi

mkdir -p "$(dirname "$MARKER")"
# Run in background so SessionStart is not blocked.
(gitnexus analyze --dir "$WORKSPACE" && touch "$MARKER") &
disown
