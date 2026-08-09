#!/usr/bin/env bash
# Merge baked settings over sbx-managed ~/.claude/settings.json. The
# BASH_ENV/CLAUDE_ENV_FILE hook sources this script; it uses jq and skips the
# merge when `extraKnownMarketplaces` is already present.

BAKE_SETTINGS="/home/agent/.claude-bake/settings.local.json"
TARGET_SETTINGS="/home/agent/.claude/settings.json"

# Only run if the baked settings file exists (may be absent in base builds).
if [ ! -f "$BAKE_SETTINGS" ]; then
    return 0 2>/dev/null || exit 0
fi

# Idempotency probe: skip if already merged.
if jq -e '.extraKnownMarketplaces' "$TARGET_SETTINGS" >/dev/null 2>&1; then
    return 0 2>/dev/null || exit 0
fi

# Merge: bake settings win on conflict.
MERGED=$(jq -s '.[0] * .[1]' "$TARGET_SETTINGS" "$BAKE_SETTINGS")
echo "$MERGED" > "$TARGET_SETTINGS"
