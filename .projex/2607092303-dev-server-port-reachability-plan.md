# Dev-Server Port Reachability (`-Ports` + `0.0.0.0` convention)

> **Status:** Ready
> **Created:** 2026-07-09
> **Author:** Claude (Opus 4.8) — via plan-projex
> **Source:** 2607092240-workspace-node-modules-and-dev-server-reachability-proposal.md (Accepted) — Recommended Approach P1
> **Related Projex:** 2607092303-workspace-node-modules-boundary-plan.md (sibling — the other half of the same proposal, independent, no ordering dep) | 2607092254-workspace-node-modules-and-dev-server-reachability-review.md (review: "P1 is plan-ready, could split out immediately") | 2607060232-run-images-without-sbx-eval.md (run.ps1 mount/launch model this builds on)
> **Worktree:** Yes

---

## Summary

Add an opt-in `-Ports` param to all three `run.ps1` launchers that publishes container ports to host loopback (`-p 127.0.0.1:<port>:<port>`), plus a documented `--host 0.0.0.0` convention so a dev server run inside the container is reachable from the host browser. Pure `run.ps1` + README change; no Dockerfile edits.

**Scope:** `-Ports` param + `-p` publish flag + `0.0.0.0` reminder in `claude/run.ps1`, `codex/run.ps1`, `opencode/run.ps1`; a "Dev-server reachability" doc section in the three `README.md`.
**Estimated Changes:** 6 files (3 `run.ps1`, 3 `README.md`), 1 new param + 1 loop + 1 Write-Host per launcher.

---

## Objective

### Problem / Gap / Need

`run.ps1` publishes no ports (`grep` for `-p` across all three launchers returns only a codex comment explaining why it does *not* publish 1455). A dev server started inside the container is unreachable from the host browser on two counts: (1) no Docker port publish, and (2) apps default to binding `127.0.0.1`, the container's own loopback. The launcher can fix (1) and document (2) — it cannot force the app's bind address.

### Success Criteria

- [ ] Each `run.ps1` accepts `-Ports <int[]>` and appends `-p 127.0.0.1:<port>:<port>` per value.
- [ ] Default behavior unchanged when `-Ports` is omitted (empty array → no `-p` flags).
- [ ] Publishing is host-loopback only (`127.0.0.1:` on the host side), never `0.0.0.0:` — port stays off the LAN.
- [ ] When `-Ports` is passed, the launcher prints a one-line reminder to bind the dev server to `0.0.0.0`.
- [ ] Each `README.md` documents `-Ports` usage + the `0.0.0.0` requirement.
- [ ] End-to-end: `run.ps1 -Ports 5173` + an in-container server on `0.0.0.0:5173` → host reaches `http://127.0.0.1:5173`.

### Out of Scope

- Default/auto port publishing (proposal Option P2 — rejected: collision-prone).
- Forcing `--host 0.0.0.0` from the launcher (impossible — it's the downstream app's own flag).
- Baked agent skill for the convention — README + launch-time reminder is the chosen doc channel (proposal Open Q #4, resolved toward README; a baked skill would require a new Dockerfile `COPY`, which the no-Dockerfile-change constraint forbids). See Notes.
- The `node_modules` boundary mechanism — sibling plan `2607092303-workspace-node-modules-boundary-plan.md`.

---

## Context

### Current State

All three launchers assemble a `$runArgs` array (`run -it --rm -v <ws>:/workspace -w /workspace ...`), then conditionally append `--userns=keep-id` (podman) and `-e TZ=...`, then the image + command. Param blocks are identical in shape:

```powershell
param(
    [string]$Image     = '<img>:v1',
    [string]$Engine    = 'docker',
    [string]$Workspace = $PWD.Path
)
```

No `-p` anywhere. `claude/run.ps1` ends with a direct CMD (`claude --permission-mode auto`); `codex`/`opencode` end with a `sh -lc` bootstrap string. The `-p` flags are independent of the command form — they attach to `docker run` args before the image, so all three take the identical insertion.

### Key Files

| File | Role | Change Summary |
|------|------|----------------|
| `claude/run.ps1` | Launcher | Add `-Ports` param, `-p` loop, `0.0.0.0` reminder |
| `codex/run.ps1` | Launcher | Same |
| `opencode/run.ps1` | Launcher | Same |
| `claude/README.md` | Docs | Add "Dev-server reachability" section under `## Run` |
| `codex/README.md` | Docs | Same |
| `opencode/README.md` | Docs | Same |

### Dependencies

- **Requires:** run.ps1 no-sbx launcher (`2607060232-run-images-without-sbx-eval.md`) — met, is the current default.
- **Blocks:** nothing. Independent of the sibling node_modules plan (can execute in either order).

### Constraints

- No Dockerfile changes (task constraint). Honored — `-p` is a pure `docker run` runtime flag.
- Host-side publish address must be `127.0.0.1:`, not `0.0.0.0:` (keep port off LAN).

### Assumptions

- Docker/podman `-p 127.0.0.1:H:C` binds host loopback only — standard, verify with one published port.
- `[int[]]$Ports = @()` default binds an empty array so the `foreach` is a no-op when omitted.

### Impact Analysis

- **Direct:** 3 `run.ps1`, 3 `README.md`.
- **Adjacent:** none — new param is additive, default path unchanged.
- **Downstream:** users who want reachable dev servers pass `-Ports` and set their app's `--host 0.0.0.0`.

---

## Implementation

### Overview

One additive param + one publish loop + one reminder line per launcher, at the identical structural point (after the `-e TZ` conditional, before the image is appended to `$runArgs`). Then a short README section per launcher.

### Step 1: Add `-Ports` publish + `0.0.0.0` reminder to all three `run.ps1`

**Objective:** Opt-in host-loopback port publishing with a bind-address reminder.
**Confidence:** High
**Depends on:** None

**Files:** `claude/run.ps1`, `codex/run.ps1`, `opencode/run.ps1`

**Changes (identical per file):**

1. Add to the `param(...)` block (after `$Workspace`):

```powershell
    [string]$Workspace = $PWD.Path,
    [int[]]$Ports      = @()
```

2. Immediately after the timezone conditional line `if ($tz) { $runArgs += @('-e', "TZ=$tz") }` and **before** the image/command is appended to `$runArgs`, insert:

```powershell
# Opt-in dev-server port publishing. Host side pinned to 127.0.0.1 so the port
# is reachable from the host browser but never exposed on the LAN. The app's
# own dev server must bind 0.0.0.0 inside the container (e.g. vite --host
# 0.0.0.0) — the launcher can publish the port but can't set the app's bind
# address.
foreach ($p in $Ports) { $runArgs += @('-p', "127.0.0.1:${p}:${p}") }
if ($Ports) {
    Write-Host "==> Publishing to host loopback: $($Ports -join ', '). Bind your dev server to 0.0.0.0 (e.g. 'vite --host 0.0.0.0'), NOT 127.0.0.1, or the host can't reach it."
}
```

**Rationale:** Insertion point is shared by all three because `-p` attaches to `docker run` args regardless of whether the launcher ends in a direct CMD (claude) or a `sh -lc` bootstrap (codex/opencode). `[int[]]` gives free multi-value + type validation (`-Ports 5173,3000`). Loopback host-bind matches the proposal's safer default (Open Q #3).

**Verification:**
- `pwsh -File claude/run.ps1 -Ports 5173 -WhatIf`-equivalent: run with a throwaway image name and read the echoed `==> docker run ...` line — confirm `-p 127.0.0.1:5173:5173` present.
- Omit `-Ports` → echoed command has no `-p`.
- `-Ports 5173,3000` → two `-p` flags.

**If this fails:** Revert the param + inserted block per file (additive, isolated).

---

### Step 2: Document `-Ports` + `0.0.0.0` in the three READMEs

**Objective:** Tell the user both halves are required (publish flag + app bind address).
**Confidence:** High
**Depends on:** Step 1

**Files:** `claude/README.md`, `codex/README.md`, `opencode/README.md`

**Changes:** Insert a new section immediately after the `## Run` section (before the next `##` header — `## Layout`/`## Notes`). Content (adjust the image name per launcher):

```markdown
## Dev-server reachability

A dev server started inside the container is only reachable from the host if
**both** sides are set:

1. **Publish the port** — pass `-Ports`, host-loopback only:
   ```powershell
   <repo>\claude\run.ps1 -Ports 5173          # one port
   <repo>\claude\run.ps1 -Ports 5173,3000     # several
   ```
   Publishes `-p 127.0.0.1:<port>:<port>` (reachable from this machine's
   browser, not the LAN).

2. **Bind the app to `0.0.0.0`** — inside the container, start the dev server
   on `0.0.0.0`, not `127.0.0.1` (its own flag/config, the launcher can't set
   it): `vite --host 0.0.0.0`, `next -H 0.0.0.0`, `webpack serve --host 0.0.0.0`.

Miss either and you get connection-refused. Then open `http://127.0.0.1:<port>`.
```

**Rationale:** The two-sided requirement is the top failure mode; leading with it prevents the "passed `-Ports`, still refused" trap.

**Verification:** Render/read each README — section present under `## Run`, image name correct per launcher.

**If this fails:** Revert the README additions (docs-only).

---

## Verification Plan

### Automated Checks
- [ ] `run.ps1 -Ports 5173` echoes `-p 127.0.0.1:5173:5173`; no `-Ports` → no `-p`.
- [ ] PowerShell parses each edited `run.ps1` without error (`pwsh -NoProfile -Command "& { . ./claude/run.ps1 }"` fails only on the docker exec, not on parse — or lint via AST).

### Manual Verification
- [ ] End-to-end: build/pull an image, `run.ps1 -Ports 5173`, inside container `python3 -m http.server 5173 --bind 0.0.0.0` (proxy for a dev server), confirm host `curl http://127.0.0.1:5173` succeeds.
- [ ] Same with `--bind 127.0.0.1` inside → host connection refused (confirms the `0.0.0.0` requirement is real).

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected Result |
|-----------|---------------|-----------------|
| `-Ports` publishes loopback | Echoed run command | `-p 127.0.0.1:5173:5173` |
| Default unchanged | Run without `-Ports` | No `-p` in command |
| `0.0.0.0` reminder | Run with `-Ports` | Reminder line printed |
| Docs cover both sides | Read READMEs | Section present ×3 |

---

## Rollback Plan

1. Revert the param + inserted block in each `run.ps1` (additive, no shared state).
2. Revert the README sections.

Both are isolated, non-behavioral-by-default changes; reverting is a clean diff removal.

---

## Notes

### Risks
- User passes `-Ports` but app still binds `127.0.0.1`: Low — self-evident failure (connection refused) + the printed reminder + README.
- Port already in use on host: Docker errors clearly at run; not the launcher's concern.

### Deviations from proposal
- **Doc channel: README + launch-time `Write-Host`, not a baked agent skill.** Proposal Open Q #4 left "baked skill vs README note" unresolved. Research showed a Dockerfile-owned baked skill (the `skills/agent-browser/` pattern) requires a new `COPY` line in each Dockerfile — which the plan's no-Dockerfile-change constraint forbids. README + a launch reminder delivers the convention to the human launching without expanding scope into Dockerfiles. If a baked, agent-triggerable skill is later wanted, that is a separate Dockerfile-touching plan.

### Open Questions
- None.
