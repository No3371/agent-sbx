# Patch: Claude Host State Isolation

> **Status:** Complete (Success)
> **Date:** 2026-07-28
> **Author:** Claude Opus 5
> **Directive:** "Does the claude suite mutate or share host state? Because somehow this host claude code app keep forgetting state like trusted repos and I'm getting suspicious"
> **Source Plan:** Direct
> **Result:** Success

---

## Summary

`claude/run.ps1` bind-mounted the host's live `~/.claude.json` read-write into every container. Claude Code rewrites that file wholesale from an in-memory snapshot taken at startup, so host app + container were two writers racing one file — last flush wins, the loser's state erased silently. Casualty: the trusted-repo registry (`projects[<path>].hasTrustDialogAccepted`). Fixed by mounting a per-run throwaway copy seeded with only the auth/MCP fields the container needs, and demoting the credentials mount to `:ro`.

---

## Diagnosis

**Symptom:** host Claude Code repeatedly forgetting trusted repos.

**Mechanism:** `~/.claude.json` is not a session file — it is the global registry: `projects[<path>].hasTrustDialogAccepted` | onboarding flags | model caches | `mcpServers`. Claude Code loads it at startup and writes the whole file back on change. Two instances sharing it cannot merge; they overwrite.

**Live evidence at diagnosis time:**

| Fact | Value |
|---|---|
| Container | `goofy_jemison`, `cc-custom:v1`, up 17h (started Jul 27 02:03) |
| Its workspace | `S:\Repos\5d-advanced-wars` |
| Mount | `C:\Users\BA\.claude.json -> /home/agent/.claude.json  RW=true` |
| Container Claude Code | 2.1.210 |
| Host Claude Code | 2.1.220 (schema skew widens the stomp) |

Collapse trail in `~/.claude/backups/`:

```
18:23:12   39,404 bytes
18:28:35   39,781
18:30:57   39,902
18:40:27    1,074   <- projects: {} ; only mcpServers/userID/pluginUsage/cachedExtraUsageDisabledReason survive
18:41:30   34,439   (host app rebuilding from scratch)
```

**Confirming divergence:** `~/.claude.json` listed 1 project while `~/.claude/projects/` held 13 history dirs. History survived, trust registry zeroed — the exact reported symptom.

**Why the mount existed** (git archaeology, not history persistence):

- `ab1c603` — birth. Creds deliberately isolated to `~/.claude-docker/.credentials.json`; container ran its own `/login`. But `.claude.json` pointed at the host's real file from day one, pre-created as `{}` and treated as container scratch. Original sin.
- `b2e8f49` — isolation dropped on purpose: `Persists OAuth` → `Reuses host OAuth`, creds repointed to `~/.claude/.credentials.json`. Both files now live shared state.
- `92e0722` — added project-local history mount; its own header comment states history lives in `~/.claude/projects/`, **"NOT in .claude.json."** From here the `.claude.json` mount had no remaining justification beyond `oauthAccount`.

Build path is clean — `prepare.ps1` and `sync-context.ps1` only read `$HostClaudeDir`.

---

## Changes

### Container config: shared file → per-run copy

**File:** `claude/run.ps1`
**Change Type:** Modified

**What Changed:**

- `$claudeJson` → `$hostClaudeJson` (source only, never a mount target)
- New per-run copy at `$env:TEMP\cc-custom-claude-<12-hex-guid>.json`, seeded from the host file with `oauthAccount` | `userID` | `firstStartTime` | `mcpServers`, plus `hasCompletedOnboarding` and a pre-accepted `/workspace` trust entry
- Mount source swapped to the copy; removed the pre-create-host-file-as-`{}` branch
- Wrapped the engine invocation in `try/finally`; `Remove-Item` the copy on exit, Ctrl-C, or engine failure
- Unparseable host config → `Write-Warning` + empty seed, not fatal

**Why:**
Container writes freely to a file that dies with the run. Host file is never opened for write. Workspace is always `/workspace`, so the trust entry is seeded once per run — a fresh copy would otherwise prompt every launch.

Deliberately **not** copied: `projects` (host trust registry + per-project `allowedTools`), caches, migration flags. The container has no use for the host's other repos, so it no longer sees them — a privacy improvement beyond the corruption fix.

### Credentials: read-write → read-only

**File:** `claude/run.ps1`

**What Changed:** `-v <creds>:/home/agent/.claude/.credentials.json` → same path with `:ro`.

**Why:** Same class of bug on a second file. Two instances racing OAuth refresh-token rotation can invalidate each other's session, forcing host re-login.

**Tradeoff (accepted):** the container cannot persist a refreshed token, so a very long container session may need a restart rather than refreshing in place. Deliberate — a container must not be able to log the host out.

### Documentation

**File:** `claude/run.ps1` (header)

Added `HOST STATE ISOLATION` block recording the failure mode, the observed byte-level evidence, and the `:ro` tradeoff, so the next person does not "helpfully" restore the mount.

---

## Verification

**Method:** AST parse | end-to-end run against a stub engine capturing real argv + seed | live container write test against `cc-custom:v1`.

**Result:**

```
parse: OK

-v C:\Users\BA\AppData\Local\Temp\cc-custom-claude-41949bf638eb.json:/home/agent/.claude.json
-v C:\Users\BA\.claude\.credentials.json:/home/agent/.claude/.credentials.json:ro

seed keys: oauthAccount, userID, firstStartTime, mcpServers, hasCompletedOnboarding, projects
/workspace: {"hasTrustDialogAccepted":true,"projectOnboardingSeenCount":1,...}
host project paths present: 0
BOM-free: True
temp copy cleaned up: True    stray copies left: 0

# container write test
[copy]  write OK
[creds] write BLOCKED (read-only) OK
        sh: 1: cannot create /home/agent/.claude/.credentials.json: Read-only file system
mounted copy received the write: True
host .claude.json contains CLOBBERED marker: False
host .claude.json: 37,197 bytes, 29 keys, projects intact
```

**Note on a confound:** the host file's hash *did* change across the container test. Not the container — the host file carried no `CLOBBERED` marker, kept all 29 keys, and gained `S:\Repos\custom-sbx-templates` because the diagnosing session was itself running in that repo. Host app writing normally.

**Status:** PASS

---

## Impact on Related Projex

| Document | Relationship | Update Made |
|----------|-------------|-------------|
| — | No existing projex covered the host-mount design | None; this patch is the record |

---

## Notes

**Not done — user deferred:** "I'll rebuild it later." Two items left with the user:

1. The 17h `goofy_jemison` container is still running with live work and the **old** mount. It keeps clobbering until stopped. The fix only applies to containers launched after this commit.
2. `~/.claude/backups/.claude.json.backup.1785234684643` (18:30:57, 39,902 bytes) is the last intact trust list. Restoring overwrites anything the host learned since 18:41.

**Unverified assumption:** the seed carries enough for Claude Code to consider itself logged in. Backed by `ab1c603` starting from literal `{}` successfully, and by `oauthAccount` + mounted credentials being the documented pairing — but not exercised against a live `/login` check, since that needs an interactive container run. If a launch prompts for login, add fields to the seed rather than restoring the host mount.

**Same class, other suites — not patched, scope guard:**

- `codex`, `cursor` — clean, mount nothing from host `$HOME`.
- `pi` — `~/.pi/agent/auth.json` RW; sessions in a named volume. Narrower (auth only, no global registry) but same RW-auth exposure.
- `opencode` — `~/.local/state/opencode` (whole dir) + `opencode.db` + `auth.json`, all RW. **Closest parallel to the bug fixed here** and the best candidate for a follow-up patch.
