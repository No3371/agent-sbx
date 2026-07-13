# Memo: context-mode plugin hooks.json — stale Windows paths break Bash hooks on Linux/WSL2

> **Date:** 2026-07-13
> **Author:** agent
> **Source Type:** Issue
> **Origin:** Conversation — debugging `PreToolUse:Bash`/`PostToolUse:Bash` hook errors, user then said "memo-projex so I can escalate to my sandbox tool suite"

---

## Source

Every `Bash` tool call was throwing:
```
PreToolUse:Bash hook error — Failed with non-blocking status code: /bin/sh: 1: C:/Program Files/nodejs/node.exe: not found
PostToolUse:Bash hook error — Failed with non-blocking status code: /bin/sh: 1: C:/Program Files/nodejs/node.exe: not found
```

User asked "Why is there a hook error about C:/?" then, once root cause was found, said "memo-projex so I can escalate to my sandbox tool suite" — read as: capture the finding so it can be handed off/fixed outside this session.

## Context

Root cause, confirmed by reading the actual files (not guessed):

- `~/.claude/plugins/cache/context-mode/context-mode/1.0.169/hooks/hooks.json` has every hook command hardcoded to absolute Windows paths:
  `"C:/Program Files/nodejs/node.exe" "C:/Users/BA/.claude/plugins/cache/context-mode/context-mode/1.0.169/hooks/pretooluse.mjs"` (same pattern for posttooluse/precompact/userpromptsubmit/sessionstart/stop).
- This plugin ships with `${CLAUDE_PLUGIN_ROOT}` + bare `node` placeholders and self-normalizes to absolute paths on first boot (see `hooks/normalize-hooks.mjs`, fixes their #378/#369/#372). That normalization ran on a Windows machine (`C:/Users/BA/...`), baking in Windows-specific paths.
- The same `~/.claude` profile / plugin cache is now in use on this Linux/WSL2 host (`/home/agent`, `Linux 6.18.33.1-microsoft-standard-WSL2`), where neither `C:/Program Files/nodejs/node.exe` nor `C:/Users/BA/...` exist.
- The plugin's own self-heal (`context-mode-cache-heal.mjs`, wired as a `SessionStart` hook in `~/.claude/settings.json`, calls `normalizeHooksJsonOnly`) does NOT catch this case. `needsHookNormalization()` in `normalize-hooks.mjs:81` only re-triggers on two conditions: the literal `${CLAUDE_PLUGIN_ROOT}` placeholder still present, or a stale **plugin-version** segment in the cached path (their #604 fix, for auto-update carrying forward a previous version's absolute paths). Content that's already fully resolved — just resolved for the wrong OS/host — matches neither trigger, so the heal is a silent no-op. There's no host-mismatch detection (e.g. checking `process.platform`/`process.execPath` against what's embedded in the command string).
- Related, but distinct: `~/.claude/settings.json` permissions allowlist also has two entries in Git-Bash/MSYS path form referencing the same Windows user: `Bash(bash "/c/Users/BA/.claude/skills/projex/projex-commit.sh" *)` and `.../move-n-stage.sh`. Not yet confirmed to cause active errors (permission allowlist entries just fail to match rather than execute), but same root migration issue — profile carried from Windows without host-specific paths being re-resolved.

Was about to try deleting/re-extracting the plugin cache dir so the placeholder form comes back and self-heal re-resolves correctly for Linux, but user interrupted before that step to redirect into projex/memo capture instead.

## Context — what "escalate to sandbox tool suite" likely means

Not confirmed with user. Read as: user wants this finding available to act on from a different tool/environment (possibly editing `~/.claude` directly, or a different agent/sandbox) rather than having this session make the fix. Memo captures the diagnosis so no re-investigation is needed wherever it's picked up.

---

## Related Projex

- None yet — this is the first projex document in this session's investigation.
