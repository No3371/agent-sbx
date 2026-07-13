# Run baked images without sbx — Plan

> **Status:** Complete (code delivered and verified byte-for-byte against spec) — Runtime: Unverified (no live container test performed)
> **Created:** 2026-07-06
> **Completed:** 2026-07-06
> **Author:** developer@3371.online (agent-drafted)
> **Source:** `2607060232-run-images-without-sbx-eval.md` (accepted direction — §10 Primary recommendation)
> **Related Projex:** `2607060232-run-images-without-sbx-eval.md`, `2607060240-run-images-without-sbx-redteam.md` — Should-Fix + Conditions-for-Approval items `[PATCHED]` via `2607060700-run-images-redteam-fixes-patch.md`; audited via `2607061500-run-images-without-sbx-audit.md` (Verdict: Accept with Conditions)
> **Walkthrough:** `2607061530-run-images-without-sbx-walkthrough.md`
> **Worktree:** Yes

---

## Summary

Add a thin `run.ps1` wrapper per template (`claude/run.ps1`, `codex/run.ps1`) that launches the already-baked image via `docker|podman run` — mounting the caller's cwd as `/workspace`, bind-mounting individual host state/credential files for OAuth+session persistence (without shadowing baked `~/.claude` content), and dropping into the agent interactively. Replaces sbx as the launcher on Win10. Update both READMEs' `## Run` sections.

**Scope:** Two new `run.ps1` scripts + two README `## Run` edits. No Dockerfile/prepare.ps1/build.ps1 changes.
**Estimated Changes:** 4 files (2 new scripts, 2 README edits).

---

## Objective

### Problem / Gap / Need

`sbx` dropped Windows 10 support; the user won't upgrade the OS. The baked `cc-custom` / `codex-custom` images need a new launcher that reproduces sbx's runtime jobs (eval §5.1): (1) mount cwd as workspace, (2) OAuth + session persistence, (3) launch the agent interactively in the container. The settings-baseline rewrite sbx did is **not needed** without sbx (eval F2). All remaining jobs are stock `docker run` flags.

### Success Criteria

> **Left unchecked intentionally.** None of the 6 items below were exercised against a live container (no correctly-tagged image locally, no podman on PATH, agent cannot perform interactive OAuth). Each is marked "Not Verified — requires live image, deferred to first real use" in `2607061530-run-images-without-sbx-walkthrough.md` § Success Criteria Verification. Check these off only after a human runs the Verification Plan's manual checks below.

- [ ] From an arbitrary project dir on Win10, `<template>/run.ps1` mounts that dir as `/workspace` and starts the container with workdir `/workspace`.
- [ ] `claude` (resp. `codex`) launches interactively inside the container against the mounted workspace.
- [ ] A file created by the agent in `/workspace` appears in the host cwd (bind-mount is agent-writable).
- [ ] A login performed in run #1 persists into run #2 without re-authenticating (two consecutive `run.ps1` invocations from the same dir).
- [ ] Baked skills/agents/tools/settings remain visible inside the container (no `~/.claude` / `~/.codex` shadowing).
- [ ] `run.ps1 -Engine docker` and `-Engine podman` both work, mirroring `build.ps1`'s param convention.

### Out of Scope

- Dockerfile, `prepare.ps1`, `build.ps1`, `retag-tar.ps1` changes.
- Retiring `merge-claude-settings.sh` (eval: leave it — cheap idempotent no-op preserving sbx compatibility).
- Auto-`docker load` of the image tar inside the wrapper (eval "Long-term" opportunity — deferred; the wrapper assumes the image is already in the engine's local store).
- The uncommitted `claude/prepare.ps1`, `codex/prepare.ps1`, and untracked `claude/sbx-cc-custom` (human's own in-progress work — not touched by this plan).
- Compose / devcontainer / any new dependency.

---

## Context

### Current State

- Images run as `USER agent`, `WORKDIR /home/agent`; base entrypoint (tini + base CMD) auto-launches the agent (`claude/Dockerfile:154-157`). Passing an explicit command (`claude` / `codex`) overrides the CMD and is the robust choice.
- Baked content lives under `/home/agent/.claude/{skills,agents,tools,commands,hooks,settings.json,plugins}` (`claude/Dockerfile:90-116`) and `/home/agent/.codex/{config.toml,AGENTS.md,skills,vendor_imports}` (`codex/Dockerfile:47-50`). Mounting the **whole** `~/.claude` or `~/.codex` dir as a volume would shadow this — so only individual host files are bind-mounted (eval §5.3).
- The settings merge hook fires from the base image's `/etc/sandbox-persistent.sh` (`BASH_ENV`/`CLAUDE_ENV_FILE`), independent of sbx (`claude/Dockerfile:125-136`) — baked config works with no sbx.
- `build.ps1` establishes the convention `run.ps1` mirrors: `[string]$Engine = 'podman'`; `Get-Command $Engine` presence check; `$root = $PSScriptRoot`; `$ErrorActionPreference = 'Stop'`; `& $Engine @args` splatting (`claude/build.ps1:27,32-33,46-48`).

### Key Files

| File | Role | Change Summary |
|------|------|----------------|
| `claude/run.ps1` | New launcher for cc-custom | Create — `docker|podman run` wrapper (workspace + `.claude.json` + creds file mounts, interactive `claude`) |
| `codex/run.ps1` | New launcher for codex-custom | Create — same shape, `~/.codex/auth.json` mount, interactive `codex` |
| `claude/README.md` | Docs | Replace `## Run` sbx command with `run.ps1` usage (+ first-run login note) |
| `codex/README.md` | Docs | Replace `## Run` sbx command with `run.ps1` usage (+ first-run login note) |

### Dependencies

- **Requires:** A built image already present in the target engine's local store (`build.ps1` output, or `docker load <tar>`). Docker Desktop or podman on PATH.
- **Blocks:** Nothing.

### Constraints

- Windows 10, **PowerShell 5.1** — match `build.ps1`/`prepare.ps1` style (no PS7-only syntax; no `??`/`?:`; arrays + splatting only, as build.ps1 does).
- Mounts must target under `/home/agent` and be agent-writable.
- Interactive TTY: `run -it`; run under Windows Terminal.

### Assumptions

> Verify these **early during execution** (eval §11 Open Questions) — first-run checks, not blockers to re-litigate.

- **A1 (creds file, not keychain):** Claude Code inside this Linux container writes OAuth to a bind-mountable file (`~/.claude/.credentials.json`), not an OS keychain. Verify: run once, `/login`, check whether the host-side mounted creds file gets populated. If keychain-only → fall back to a named volume seeded from the image once (eval §5.3 resolution 2 / §8).
- **A2 (cwd writable):** The bind-mounted host cwd is writable by the container `agent` uid under Docker Desktop without extra flags. Verify: agent creates a file in `/workspace`, confirm it lands on host. If podman-rootless mismatch → add `--userns=keep-id` (podman only; the calibration knob).
- **A3 (codex auth path):** Codex persists OAuth to `~/.codex/auth.json`. Verify: `codex` login, check host file populated. Same mount pattern, different path.
- **A4 (settings merge):** `merge-claude-settings.sh` stays as an intentional no-op in the no-sbx path (nothing clobbers `settings.json`, so the merge is idempotent). Not modified by this plan — noted for the reader.
- **A5 (single creds file):** Mounting `~/.claude/.credentials.json` as an individual host file does **not** shadow sibling baked files under `~/.claude/` (host-file bind-mounts mount only that path). Docker/podman create a *directory* at the bind source if it is absent — so the wrapper pre-creates an empty file there first.

### Impact Analysis

- **Direct:** `claude/run.ps1`, `codex/run.ps1` (new); `claude/README.md`, `codex/README.md` `## Run` sections.
- **Adjacent:** None — no existing script imports or is imported by `run.ps1`; it only reuses the same `-Engine` convention.
- **Downstream:** Users switch from `sbx run --template …` to `./run.ps1`. sbx path still functional (build.ps1 `-LoadToSbx` untouched).

---

## Implementation

### Overview

Two near-identical wrappers, one per template, each self-contained (no shared module — matches the per-template `build.ps1`/`prepare.ps1`/`retag-tar.ps1` layout already in the repo). Each: validate engine present → pre-create host state files/dir → assemble mount args → `& $Engine run -it --rm …`. Then two README edits.

### Step 1: `claude/run.ps1`

**Objective:** Launch cc-custom with workspace + persisted Claude state, interactively.
**Confidence:** High (mounts/flags), Medium (exact creds path — gated by A1).
**Depends on:** None.

**Files:**
- `claude/run.ps1` (new)

**Changes:**

```powershell
# Run the baked cc-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `claude` interactively. Persists OAuth + session state across runs by
# bind-mounting individual host files (NOT the whole ~/.claude dir, which
# would shadow the image's baked skills/agents/settings).
#
# First run: inside the container run `/login` once. The OAuth token is
# written to the mounted credentials file on the host and persists to
# future runs. See .projex eval 2607060232 for the rationale.
#
# SECURITY: ~/.claude.json and .claude-docker/.credentials.json carry live
# OAuth/session tokens once populated. Treat them like SSH keys — never
# commit, never share the .claude-docker directory (any other process/
# container reading %USERPROFILE% can read the plaintext token).

[CmdletBinding()]
param(
    [string]$Image     = 'cc-custom:v1',
    [string]$Engine    = 'docker',
    [string]$Workspace = $PWD.Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command $Engine -ErrorAction SilentlyContinue)) {
    throw "$Engine not found on PATH"
}

# Host-side persisted state. Bind-mounted as individual files so sibling
# baked files under /home/agent/.claude are NOT shadowed.
$claudeJson  = Join-Path $env:USERPROFILE '.claude.json'
$credsDir    = Join-Path $env:USERPROFILE '.claude-docker'
$credsFile   = Join-Path $credsDir '.credentials.json'

# Pre-create the host files so the engine bind-mounts them as files, not as
# freshly-created empty directories (Docker creates a dir if the source path
# is absent). BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a
# UTF-8 BOM, which can make a strict JSON parser choke on `{}` before the
# first real write.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
if (-not (Test-Path $claudeJson)) { [System.IO.File]::WriteAllText($claudeJson, '{}', $utf8NoBom) }
if (-not (Test-Path $credsDir))   { New-Item -ItemType Directory -Force $credsDir | Out-Null }
if (-not (Test-Path $credsFile))  { [System.IO.File]::WriteAllText($credsFile, '{}', $utf8NoBom) }

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', ("{0}:/home/agent/.claude.json" -f $claudeJson),
    '-v', ("{0}:/home/agent/.claude/.credentials.json" -f $credsFile)
)
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
$runArgs += @($Image, 'claude')

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
```

**Rationale:** Mirrors `build.ps1` param/validation style. Individual-file mounts avoid the whole-dir shadow (eval F4, §5.3). Pre-creating host files prevents Docker from materializing a directory at the bind source, using a BOM-less write so a strict in-container JSON parser never sees a BOM-prefixed `{}` (redteam Finding: PS5.1 `Set-Content -Encoding utf8` BOM risk). Explicit `claude` command overrides base CMD deterministically. `--userns=keep-id` now wired conditionally for `-Engine podman` instead of left as a manual "if this fails" fallback (redteam edge case: podman-rootless uid mismatch).

**Verification:** From a scratch dir `mkdir demo; cd demo; <repo>\claude\run.ps1 -Engine docker`. Container opens on `/workspace`; `ls` shows demo's contents; baked skills visible (check `~/.claude/skills` in-container). Create a file in-container, confirm it appears on host (A2). `/login`, exit, re-run — no re-auth (A1).

**If this fails:** Delete `claude/run.ps1`. If creds don't persist (A1 keychain) → switch the creds mount to a named volume seeded from the image once (eval §8); `--userns=keep-id` is already wired for `-Engine podman`, so if A2 still fails under podman, investigate further rather than hand-editing the flag in.

---

### Step 2: `codex/run.ps1`

**Objective:** Launch codex-custom with workspace + persisted Codex auth, interactively.
**Confidence:** High (mounts), Medium (auth path — gated by A3).
**Depends on:** None (independent of Step 1).

**Files:**
- `codex/run.ps1` (new)

**Changes:**

```powershell
# Run the baked codex-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `codex` interactively. Persists OAuth by bind-mounting the single host
# auth file (NOT the whole ~/.codex dir, which would shadow the baked
# config.toml / skills / vendor_imports).
#
# First run: authenticate once inside the container; the token lands in the
# mounted auth.json on the host and persists. See .projex eval 2607060232.
#
# SECURITY: .codex-docker/auth.json carries a live OAuth token once
# populated. Treat it like an SSH key — never commit, never share the
# .codex-docker directory (any other process/container reading
# %USERPROFILE% can read the plaintext token).

[CmdletBinding()]
param(
    [string]$Image     = 'codex-custom:v1',
    [string]$Engine    = 'docker',
    [string]$Workspace = $PWD.Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command $Engine -ErrorAction SilentlyContinue)) {
    throw "$Engine not found on PATH"
}

# Host-side persisted auth, bind-mounted as a single file so the baked
# ~/.codex contents are not shadowed.
$codexDir  = Join-Path $env:USERPROFILE '.codex-docker'
$authFile  = Join-Path $codexDir 'auth.json'

# BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a UTF-8 BOM,
# which can make a strict JSON parser choke on `{}` before the first real
# write.
if (-not (Test-Path $codexDir))  { New-Item -ItemType Directory -Force $codexDir | Out-Null }
if (-not (Test-Path $authFile))  {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($authFile, '{}', $utf8NoBom)
}

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', ("{0}:/home/agent/.codex/auth.json" -f $authFile)
)
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
$runArgs += @($Image, 'codex')

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
```

**Rationale:** Same shape as Step 1. `~/.codex/auth.json` is the file `prepare.ps1` explicitly excludes as "credentials; sbx manages auth at runtime" (`codex/README.md:87`) — so mounting exactly that file supplies what the image intentionally omits. Whole-dir mount avoided to preserve baked `config.toml`/`skills`/`vendor_imports`. `--userns=keep-id` wired conditionally for `-Engine podman` (redteam edge case: podman-rootless uid mismatch), and the auth file write is BOM-less for the same reason as Step 1 (redteam: PS5.1 BOM risk).

**Verification:** `<repo>\codex\run.ps1 -Engine docker` from a scratch dir. `codex` launches on `/workspace`; baked `config.toml` in effect. Authenticate, exit, re-run — no re-auth (A3). Confirm host `~/.codex-docker/auth.json` populated.

**If this fails:** Delete `codex/run.ps1`. If A3 wrong (different auth path) → adjust the container-side mount target to Codex's actual auth location observed on first run. `--userns=keep-id` is already wired for `-Engine podman`.

---

### Step 3: Update `claude/README.md` `## Run`

**Objective:** Document the no-sbx run path.
**Confidence:** High.
**Depends on:** Step 1.

**Files:**
- `claude/README.md`

**Changes:** Replace the `## Run` section (currently the sbx-only block at lines 27-31) with:

```markdown
## Run

Without sbx (Win10) — from any project directory:

    # image must already be in the engine's local store (build.ps1, or `docker load <tar>`)
    <repo>\claude\run.ps1 -Image cc-custom:v1 -Engine docker

Mounts the current directory as `/workspace` and launches `claude` interactively.
First run only: type `/login` inside the container — the OAuth token persists to
`%USERPROFILE%\.claude-docker\.credentials.json` and survives future runs.
Session/history state persists via `%USERPROFILE%\.claude.json`.

**Security:** `.claude.json` and `.claude-docker\.credentials.json` carry live
OAuth/session tokens once populated. Treat them like SSH keys — never commit,
never share the `.claude-docker` directory.

Use from any project dir without retyping the repo path — add to your
PowerShell profile (`$PROFILE`):

    function ccrun { & "<repo-path>\claude\run.ps1" @args }

Then just run `ccrun` from any project directory.

Legacy sbx path (requires sbx + Win11):

    sbx run --template docker.io/<user>/cc-custom:v1 claude
```

(Use fenced ```powershell blocks in the actual edit; indented form shown here to avoid nested-fence ambiguity in this plan.)

**Rationale:** No-sbx path is now primary; sbx kept as clearly-labelled legacy so the doc still serves anyone on a supported OS. Security note addresses redteam Finding 1 (credential files are durable, unscoped host secrets). Profile-function snippet addresses redteam Finding 2 (stated goal "use in any project" wasn't actually achieved by a repo-relative script needing the full path typed every invocation).

**Verification:** `## Run` shows `run.ps1` first with the login note; sbx command retained under "Legacy".

**If this fails:** Revert the `## Run` section to the original sbx-only block.

---

### Step 4: Update `codex/README.md` `## Run`

**Objective:** Document the no-sbx run path for codex.
**Confidence:** High.
**Depends on:** Step 2.

**Files:**
- `codex/README.md`

**Changes:** Replace the `## Run` section (currently the sbx-only block at lines 26-30) with:

```markdown
## Run

Without sbx (Win10) — from any project directory:

    # image must already be in the engine's local store (build.ps1, or `docker load <tar>`)
    <repo>\codex\run.ps1 -Image codex-custom:v1 -Engine docker

Mounts the current directory as `/workspace` and launches `codex` interactively.
First run only: authenticate inside the container — the token persists to
`%USERPROFILE%\.codex-docker\auth.json` and survives future runs.

**Security:** `.codex-docker\auth.json` carries a live OAuth token once
populated. Treat it like an SSH key — never commit, never share the
`.codex-docker` directory.

Use from any project dir without retyping the repo path — add to your
PowerShell profile (`$PROFILE`):

    function codexrun { & "<repo-path>\codex\run.ps1" @args }

Then just run `codexrun` from any project directory.

Legacy sbx path (requires sbx + Win11):

    sbx run --template docker.io/<user>/codex-custom:v1 codex
```

(Use fenced ```powershell blocks in the actual edit; indented form shown here to avoid nested-fence ambiguity.)

**Rationale:** Mirrors Step 3 for the codex template. Security note addresses redteam Finding 1; profile-function snippet addresses redteam Finding 2 (distribution gap — "any project" wasn't achieved without an alias).

**Verification:** `## Run` shows `run.ps1` first + auth note; sbx command retained under "Legacy".

**If this fails:** Revert to original sbx-only block.

---

## Verification Plan

> Per-step verification confirms each change in isolation. This confirms end-to-end.

> **First-run discipline (redteam No-Go If):** Verify A1 (creds file vs keychain), A2 (cwd writability), and A3 (codex auth path) **one at a time**, not batch-executed together — `--rm` discards container state on exit, so a compound failure across multiple unverified assumptions at once is hard to diagnose blind.

### Automated Checks
- [ ] Parse-check both scripts under PS5.1 without launching: run with a bogus engine, e.g. `powershell -NoProfile -File claude\run.ps1 -Engine __nope__` — must hit the `throw "$Engine not found on PATH"` (proves the file parses and validation fires). Same for `codex\run.ps1`.

### Manual Verification
- [ ] From `mkdir demo; cd demo`, run `claude\run.ps1 -Engine docker`: container opens on `/workspace`, `ls` shows demo contents, baked skills present.
- [ ] Agent writes a file in `/workspace` → appears in host `demo\` (A2).
- [ ] `/login` in run #1 → exit → run #2 from same dir: no re-auth (A1).
- [ ] Repeat with `codex\run.ps1` (A3).
- [ ] Confirm baked `~/.claude/skills` (resp. `~/.codex/config.toml`) not shadowed.

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected Result |
|-----------|---------------|-----------------|
| cwd mounted as workspace | `pwd` in container | `/workspace`; contents match host cwd |
| Agent interactive in workspace | Launch, run a command | `claude`/`codex` TUI responds |
| Workspace writable | Create file in-container | File appears on host |
| Login persists | Two consecutive runs | No re-auth on run #2 |
| Baked content intact | `ls ~/.claude/skills` in-container | Baked skills listed |
| `-Engine` both work | Run with `docker` and `podman` | Both launch |

---

## Rollback Plan

Per-step rollback noted above. Full abandon:

1. Delete `claude/run.ps1` and `codex/run.ps1` (and unstage if staged).
2. Restore original `## Run` sections in `claude/README.md` and `codex/README.md`.
3. No image/Dockerfile state changed — nothing else to undo.

---

## Notes

### Risks
- **OAuth in keychain, not file (A1):** Low–Med likelihood. Mitigation: named-volume seed (eval §8). First-run check settles it in ~2 min.
- **podman-rootless uid mismatch (A2):** Low under Docker Desktop. Mitigation: `--userns=keep-id`, now wired conditionally in `$runArgs` when `-Engine podman` `[PATCHED — see 2607060700-run-images-redteam-fixes-patch.md]`, not left as a manual fallback.
- **Codex auth path differs (A3):** Med. Mitigation: observe actual path on first login, adjust mount target.
- **PS5.1 quoting of paths with spaces:** Paths passed as single array elements to `& $Engine @runArgs`, so spaces survive without manual quoting — identical to `build.ps1`'s splatting.
- **PS5.1 `Set-Content -Encoding utf8` BOM prefix:** Fixed — host state files now written via `[System.IO.File]::WriteAllText(..., UTF8Encoding($false))` for BOM-less `{}` `[PATCHED — see 2607060700-run-images-redteam-fixes-patch.md]`.
- **Credential file exposure (host plaintext token, readable by any co-located process):** Documented — security note added to both READMEs and script header comments `[PATCHED — see 2607060700-run-images-redteam-fixes-patch.md]`. Not further hardened (e.g., no ACL tightening) — accepted as bounded risk for personal single-user tooling per redteam Final Assessment.
- **"Any project" distribution gap:** Addressed — PowerShell profile alias/function snippet added to both READMEs `[PATCHED — see 2607060700-run-images-redteam-fixes-patch.md]`.

### Open Questions
- [ ] None blocking — all four eval open questions are folded into Assumptions A1–A4 as first-run verifications, not pre-execution blockers.
