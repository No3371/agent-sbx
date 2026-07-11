# Port Claude suite features → OpenCode suite

> **Status:** In Progress
> **Created:** 2026-07-11
> **Author:** agent (opus)
> **Source:** Direct request (orchestrate-projex) — "Port from claude suite to opencode suite"
> **Related Projex:** 2607081900-codegraph-integration-audit.md | 2607100834-language-build-feature-flags-audit.md | 2607100805-language-build-feature-flags-redteam.md
> **Worktree:** Yes

---

## Summary

Port four capabilities from the `claude/` template suite to the `opencode/` suite, each **adapted to opencode's Alpine base + config/state schema** rather than copied verbatim: (2) language/feature build toggles, (3) agent-browser, (4) prepare.ps1 Win→Linux config transformation, (5) run.ps1 persistent state. Part (1) is a no-op: opencode has no sbx integration and no slim variant — **do not create `opencode/Dockerfile.slim`**.

**Scope:** `opencode/` only — `Dockerfile`, `build.ps1`, `prepare.ps1`, `run.ps1`, new `skills/agent-browser/SKILL.md`, `README.md`. One projex scope.
**Estimated Changes:** 5 files edited, 1 file created; ~4 implementation steps.

---

## Objective

### Problem / Gap / Need

`opencode/` was scaffolded as a minimal Alpine template. Four capabilities the `claude/` suite has are absent or stubbed:

- **build.ps1** accepts `-Enable`/`-Disable` but passes `-Supported @()` → any value is rejected; no language actually toggles (CLI-parity stub only).
- **Dockerfile** installs only codegraph; no agent-browser; no optional language installs.
- **prepare.ps1** does a plain filtered copy of `~/.config/opencode` — no Win→Linux path rewriting of `opencode.json`.
- **run.ps1** persists only `auth.json` — no session history, no package-manager caches, no host-`node_modules` masking.

Claude's implementations assume Debian + Node-always-present + Claude's `settings.json` schema (`mcpServers`/`hooks`/`statusLine`). opencode is Alpine/musl, ships no Node, uses Bun internally, and its `opencode.json` schema differs. A faithful port must **re-derive each feature against opencode's actual substrate**, not translate Claude's line-for-line.

### Success Criteria

- [ ] `opencode/Dockerfile.slim` does **not** exist (part 1 — explicit non-goal, asserted).
- [ ] `build.ps1 -Enable go` / `-Disable python` are accepted and change what the image installs; no selectors = default set installed; unknown language rejected with the supported list.
- [ ] Built image has `go` and `python3` present when enabled, absent when disabled; `node`, `codegraph`, `agent-browser` always present.
- [ ] `agent-browser --version` succeeds inside the built image, and `agent-browser` resolves a working browser (system Chromium) without downloading Chrome-for-Testing.
- [ ] A discovery-stub skill for agent-browser is loadable by opencode (present at `~/.config/opencode/skills/agent-browser/SKILL.md`).
- [ ] `prepare.ps1` rewrites Windows paths in local `mcp` server `command` arrays of a staged `opencode.json`, drops servers with no Linux mapping (warning), writes back BOM-less valid JSON; a host `opencode.json` with no MCP servers passes through unchanged.
- [ ] `run.ps1` persists opencode session history across `--rm` in a project-local dir, mounts an opencode plugin/npm cache volume, and masks a host `node_modules` (reinstalling Linux-native deps) only when one is present.
- [ ] `README.md` reflects the toggle set, agent-browser, and run-state behavior.

### Out of Scope

- `opencode/Dockerfile.slim` and any sbx-integration path (none exists for opencode).
- `.NET` language toggle — Alpine ships `dotnet*-sdk` in **edge/community only** (musl .NET is niche); excluded from the default supported set. Add later if requested.
- Porting Claude's `hooks` / `statusLine` / `skipAutoPermissionPrompt` transforms — **opencode.json has no such fields** (opencode hooks = plugin `.js` files, not shell commands in config; no statusline-command concept). Nothing to port; asserted in Step 3.
- Claude's `settings.local.json` / `merge-*.sh` / sbx-baseline-clobber machinery — sbx-only, N/A for the plain-docker opencode path.
- Baking/merging a project-root opencode config — opencode reads project `opencode.json` from the bind-mounted `/workspace` at runtime; no bake-time merge needed.

---

## Context

### Current State

- **Base:** `ghcr.io/anomalyco/opencode` — Alpine, runs as root, ships `opencode` (+ripgrep) only. **No Node.** opencode runs plugins via its **own bundled Bun** (npm plugins cached at `~/.cache/opencode/node_modules/`), which is why the base needs no system Node.
- **codegraph** installed via self-contained bundle installer (`curl … install.sh | sh`), pinned `ARG CODEGRAPH_VERSION=v1.3.0` — not npm.
- Non-root `agent` user (uid 1000); `mkdir -p ~/.local/share/opencode ~/.local/state/opencode`; `COPY context/.config/opencode/ → ~/.config/opencode/`.
- **opencode config schema** (from opencode.ai/docs): MCP under key `mcp` (not `mcpServers`); each server `type: "local"|"remote"`; **local `command` is an ARRAY** (`["npx","-y","pkg"]`) with optional `environment`/`cwd`/`enabled`. No `hooks`, no `statusLine`, no `skipAutoPermissionPrompt`.
- **opencode skill discovery:** global skills at `~/.config/opencode/skills/<name>/SKILL.md` (also `~/.claude/skills/…` compatible).
- **opencode auth:** `~/.local/share/opencode/auth.json` (single file, bind-mounted by run.ps1). Session/history storage lives under `~/.local/share/opencode/` (storage subtree) — **exact subdir verified in Step 4**.
- **agent-browser** (`vercel-labs/agent-browser`): a native **Rust** daemon distributed via `npm i -g agent-browser`; `agent-browser install` downloads **Chrome for Testing (glibc)** — will not run on Alpine/musl. Supports a system browser via `AGENT_BROWSER_EXECUTABLE_PATH=/path/to/chromium` (or `--executable-path`). "No Node.js required for the daemon" at runtime; npm is the install channel.

### Key Files

| File | Role | Change Summary |
|------|------|----------------|
| `opencode/Dockerfile` | Image build | Add language-toggle ARGs + conditional apk installs; add node/npm/chromium + agent-browser + skill-stub COPY + `AGENT_BROWSER_EXECUTABLE_PATH` |
| `opencode/build.ps1` | Build driver | `-Supported @('go','python')`; add `--build-arg INSTALL_*` loop; fix "optional languages" echo |
| `opencode/prepare.ps1` | Host→context staging | Add opencode.json `mcp` local-command Win→Linux rewrite + drop-unmappable pass |
| `opencode/run.ps1` | Plain-docker launcher | Add project-local history mount, opencode-cache volume, pm caches, host node_modules mask |
| `opencode/skills/agent-browser/SKILL.md` | Discovery stub (new, repo-owned) | Adapted from `claude/skills/agent-browser/SKILL.md` |
| `opencode/README.md` | Docs | Reflect toggles / agent-browser / run-state |

### Dependencies

- **Requires:** podman/docker to build; network at build (apk, npm, chromium, codegraph, agent-browser). Nothing blocks planning.
- **Blocks:** nothing downstream.

### Constraints

- **musl/Alpine, not glibc/Debian** — Claude's apt/NodeSource/Go-tarball/Chrome-for-Testing paths do not apply. Use `apk` musl-native packages and system Chromium.
- Preserve existing conventions: pinned versions via `ARG` (not `@latest`), BOM-less JSON writes (.NET `UTF8Encoding $false`), `;`-not-`&&` for non-blocking bootstrap in run.ps1, system-level git config as lowest-precedence layer.
- run.ps1 must not shadow baked config: bind-mount **individual** state paths, never the whole `~/.local/share/opencode` dir (would collide with the `auth.json` file-mount).

### Assumptions (verify early during execution)

1. **agent-browser has a runnable musl/Alpine build.** Its npm package pulls a prebuilt Rust binary; if that binary is glibc-only it won't exec on Alpine. Verified by a build-time `agent-browser --version` smoke test (Step 2). Fallback: `apk add gcompat` (glibc-compat shim); if still broken, agent-browser is documented unsupported on this base and the Step is reduced to skill-stub only.
2. **System Chromium satisfies agent-browser** via `AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium` (Alpine `chromium` package installs to `/usr/bin/chromium`). Verify the exact binary path from the installed package.
3. **`go` and `python3`+`py3-pip` exist in the base image's apk repos** without enabling edge. Verify against the base's `/etc/alpine-release` + `apk search`.
4. **opencode session/history storage path** under `~/.local/share/opencode/` (expected `storage/`), and that with a fixed `/workspace` mount the project key is stable across runs (mirroring claude's `-workspace` encoding). Verify by inspecting a container's `~/.local/share/opencode/` after one real session before wiring the mount.
5. **node is required baseline** (agent-browser install channel + generally useful); it is therefore NOT a language toggle.

### Impact Analysis

- **Direct:** the 6 files above.
- **Adjacent:** `retag-tar.ps1` unaffected (build.ps1 tar/retag path untouched). codegraph install untouched.
- **Downstream:** image size grows (node/npm/chromium/agent-browser). Consumers rebuild; no interface break (`run.ps1`/`build.ps1` flags are additive/backward-compatible — default build set = go+python ON).

---

## Implementation

### Overview

Four edits + one new file. Steps are independent in intent but **share two files** — Dockerfile (Steps 1+2) and (none other overlap) — so execute in listed order to keep diffs clean. Each step is individually verifiable by building or by running the script against a fixture.

---

### Step 1: Language toggles — build.ps1 + Dockerfile

**Objective:** `-Enable`/`-Disable` actually toggle Alpine-native optional languages (`go`, `python`).
**Confidence:** High
**Depends on:** None

**Files:** `opencode/build.ps1`, `opencode/Dockerfile`

**Changes — build.ps1:**

```powershell
# Before (line 76):
$enabledLanguages = Resolve-LanguageSelection -Enable $Enable -Disable $Disable -Supported @() -EnableSpecified ($PSBoundParameters.ContainsKey('Enable')) -DisableSpecified ($PSBoundParameters.ContainsKey('Disable'))

# After:
$enabledLanguages = Resolve-LanguageSelection -Enable $Enable -Disable $Disable -Supported @('go','python') -EnableSpecified ($PSBoundParameters.ContainsKey('Enable')) -DisableSpecified ($PSBoundParameters.ContainsKey('Disable'))
```

```powershell
# Before (lines 100-104):
$buildArgs = @('build', '-t', $Image, '-f', $dockerfilePath)
if ($NoCache) { $buildArgs += '--no-cache' }
$buildArgs += $root

Write-Host '==> optional languages: none; no optional language features'

# After:
$buildArgs = @('build', '-t', $Image, '-f', $dockerfilePath)
foreach ($language in @('go','python')) {
    $buildArgs += '--build-arg'
    $buildArgs += "INSTALL_$($language.ToUpperInvariant())=$([int]($language -in $enabledLanguages))"
}
if ($NoCache) { $buildArgs += '--no-cache' }
$buildArgs += $root

Write-Host "==> optional languages: $(if ($enabledLanguages) { $enabledLanguages -join ', ' } else { 'none' })"
```

**Changes — Dockerfile** (add ARGs after `FROM`, and a conditional install block; keep `USER root` context — base is already root):

```dockerfile
# After FROM line, before codegraph block:
ARG INSTALL_GO=1
ARG INSTALL_PYTHON=1

# Optional language toolchains (Alpine-native, musl). apt/Go-tarball path from
# the claude image does not apply here; apk go/python3 are musl-built.
RUN set -eux; \
    for flag in "$INSTALL_GO" "$INSTALL_PYTHON"; do case "$flag" in 0|1) ;; *) echo "INSTALL_* must be 0 or 1" >&2; exit 1 ;; esac; done; \
    if [ "$INSTALL_GO" = "1" ]; then apk add --no-cache go && go version; fi; \
    if [ "$INSTALL_PYTHON" = "1" ]; then apk add --no-cache python3 py3-pip && python3 --version; fi
```

**Rationale:** Mirrors claude's `-Supported`/build-arg pattern (interface parity) but with the **Alpine-feasible** set. `go`/`python3` are single-package musl-native apk installs — no NodeSource/tarball ceremony. `.NET` deliberately excluded (edge-only; see Out of Scope). `node` is baseline (Step 2), not a toggle.

**Verification:** `./build.ps1 -Image opencode-custom:v1 -Disable python -Engine docker` → build echoes `optional languages: go`; `docker run --rm opencode-custom:v1 sh -lc 'go version; python3 --version'` → go present, python3 absent. `-Enable dotnet` → rejected: "Unknown language 'dotnet'. Supported: go, python."

**If this fails:** revert both files; `-Supported @()` restores the inert stub.

---

### Step 2: agent-browser — Dockerfile + skill stub

**Objective:** Bake agent-browser adapted to Alpine (system Chromium, no glibc Chrome download) + a discovery-stub skill at opencode's native location.
**Confidence:** Medium (assumption 1 — musl binary — verified at build)
**Depends on:** None (independent of Step 1; both edit Dockerfile — apply after Step 1's block)

**Files:** `opencode/Dockerfile`, `opencode/skills/agent-browser/SKILL.md` (new)

**Changes — Dockerfile** (add near codegraph, before `USER agent`):

```dockerfile
# agent-browser: browser automation CLI for agents (github.com/vercel-labs/agent-browser).
# Distributed via npm (native Rust daemon); pinned like codegraph. Alpine has no
# Node in the base, so add nodejs/npm as the install channel. The daemon needs a
# browser: `agent-browser install` would fetch Chrome for Testing (glibc) which
# will NOT run on musl — install Alpine's musl-native Chromium instead and point
# agent-browser at it via AGENT_BROWSER_EXECUTABLE_PATH. Smoke-test the binary so
# a musl-incompatible release fails the build here, not at runtime.
ARG AGENT_BROWSER_VERSION=0.31.1
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium
RUN apk add --no-cache nodejs npm chromium \
 && npm install -g "agent-browser@${AGENT_BROWSER_VERSION}" \
 && agent-browser --version
```

Add a COPY after the existing `COPY context/.config/opencode/` line (so the repo-owned stub is not overwritten by host-synced skills):

```dockerfile
# agent-browser discovery stub — repo-owned (not host-synced), survives whatever
# is in the host's ~/.config/opencode/skills. opencode global skill location.
COPY --chown=agent:agent skills/agent-browser/ /home/agent/.config/opencode/skills/agent-browser/
```

**Changes — new file `opencode/skills/agent-browser/SKILL.md`:** adapt `claude/skills/agent-browser/SKILL.md`; drop Claude-specific `~/.claude/skills` framing; keep the "what it is / start here / when to load specialized skills" body (agent-browser CLI usage is host-agnostic). No need to mention `AGENT_BROWSER_EXECUTABLE_PATH` (set via image ENV).

**Rationale:** npm is agent-browser's only documented install channel, so nodejs/npm become baseline. `agent-browser install` is intentionally NOT run — it downloads a glibc Chrome and apt deps, both wrong for Alpine. System Chromium + the documented `AGENT_BROWSER_EXECUTABLE_PATH` env is the Alpine-correct wiring. The `--version` smoke test surfaces assumption 1 at build time.

**Verification:** build succeeds (binary runs → musl OK). `docker run --rm opencode-custom:v1 sh -lc 'agent-browser --version && echo $AGENT_BROWSER_EXECUTABLE_PATH && ls -l /usr/bin/chromium'`. Skill file present at `~/.config/opencode/skills/agent-browser/SKILL.md`.

**If this fails:** if `agent-browser --version` fails at build → add `apk add --no-cache gcompat` before the npm install and retry. If still failing → reduce this Step to the skill-stub COPY only, mark agent-browser unsupported-on-Alpine in README, and record it as a follow-up (do not block the other steps).

---

### Step 3: prepare.ps1 — opencode.json Win→Linux MCP rewrite

**Objective:** Rewrite Windows paths in local `mcp` server `command` arrays; drop servers with no Linux mapping. (Claude's hooks/statusLine/skipAutoPermissionPrompt have no opencode analog — asserted, not ported.)
**Confidence:** High
**Depends on:** None

**Files:** `opencode/prepare.ps1`

**Changes:** after the CRLF-normalization block and before the final credential scan, add an opencode.json transform. Load `<Destination>/opencode.json` (or `.jsonc`) if present; for each `mcp.<name>` where `type -eq 'local'` and `command` is an array, rewrite `command[0]` Win→Linux (reuse claude's rewrite heuristics: npx-cache/`.cmd` shims → bare tool name; git-bash/node absolute paths → bare `node`); if `command[0]` still matches `^[A-Za-z]:[/\\]` after rewrite, drop the server with `Write-Warning`. Write back BOM-less via `[System.IO.File]::WriteAllText(..., UTF8Encoding($false))`. JSONC: if the file has comments, skip rewrite with a warning (don't corrupt it) — or parse leniently only if trivially safe.

```powershell
# Sketch (place before the credential-pattern scan, ~line 98):
$ocJson = Join-Path $Destination 'opencode.json'
if (Test-Path $ocJson) {
    $raw = [System.IO.File]::ReadAllText($ocJson)
    try { $cfg = $raw | ConvertFrom-Json } catch { $cfg = $null; Write-Warning "[prepare] opencode.json not plain JSON (JSONC?) — skipping MCP rewrite" }
    if ($cfg -and $cfg.PSObject.Properties['mcp']) {
        $dropped = [System.Collections.Generic.List[string]]::new()
        foreach ($name in @($cfg.mcp.PSObject.Properties.Name)) {
            $srv = $cfg.mcp.$name
            if ($srv.type -eq 'local' -and $srv.command -is [System.Array] -and $srv.command.Count -gt 0) {
                $orig = $srv.command[0]
                $srv.command[0] = Rewrite-McpCommand $orig     # reuse claude's rewrite rules, ported here
                if ($srv.command[0] -match '^[A-Za-z]:[/\\]') {
                    Write-Warning "[prepare] mcp.${name}: dropping — no Linux mapping for: $orig"
                    $dropped.Add($name)
                } elseif ($srv.command[0] -ne $orig) {
                    Write-Host "[prepare] mcp.${name}: rewrote command[0] -> $($srv.command[0])"
                }
            }
        }
        foreach ($d in $dropped) { $cfg.mcp.PSObject.Properties.Remove($d) }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($ocJson, ($cfg | ConvertTo-Json -Depth 20), $utf8NoBom)
    }
}
```

**Rationale:** opencode.json's only host-path-bearing, config-embedded surface is local MCP `command` arrays (vs Claude's three surfaces). This is the honest 1:1 adaptation. Hooks (plugin `.js`), statusline (none), and `skipAutoPermissionPrompt` (none) have no target — porting them would be inventing schema opencode ignores. `Rewrite-McpCommand` is a small helper carrying claude's proven Win→Linux command rules; define it once in prepare.ps1.

**Verification:** fixture `opencode.json` with one local server whose `command[0]` is `C:\Users\me\AppData\...\npx.cmd` and one remote server → run prepare.ps1 → local command rewritten to `npx` (or server dropped if unmappable), remote untouched, output is BOM-less valid JSON (`Get-Content -Encoding Byte | select -first 3` ≠ `EF BB BF`). Fixture with no `mcp` key → file byte-identical or cleanly re-serialized, no crash.

**If this fails:** revert prepare.ps1; staging falls back to plain copy (current behavior) — MCP servers with Windows paths simply won't resolve in-container (pre-port status quo), no regression.

---

### Step 4: run.ps1 — persistent state (history, caches, node_modules mask)

**Objective:** Port claude's state handling adapted to opencode's layout: project-local session history, an opencode plugin/npm cache volume, pm caches, and host-`node_modules` masking.
**Confidence:** Medium (assumption 4 — storage subdir — verified before wiring)
**Depends on:** None

**Files:** `opencode/run.ps1`

**Changes:** keep the existing `auth.json` file-mount. Add, mirroring `claude/run.ps1` (lines 90-133):

1. **Project-local history** — bind-mount `<Workspace>\.opencode\history` (host, pre-created) → opencode's session storage dir (**verified path**, expected `/home/agent/.local/share/opencode/storage`). Individual-path mount so it doesn't shadow the `auth.json` file-mount or baked `~/.config/opencode`.
2. **opencode cache volume** — `-v opencode-cache:/home/agent/.cache/opencode` (persists Bun-installed plugin `node_modules` across `--rm` — opencode's analog of claude's `pm-cache`).
3. **pm caches** — `-v pm-cache:/home/agent/.npm -v pnpm-store-cache:/home/agent/.pnpm-store` + the `$pmSetup` `store-dir` line (needed by the node_modules reinstall path; node is baseline now).
4. **node_modules mask** — port claude's `$maskNodeModules` block verbatim (per-project SHA-named volume + `chown` + empty-check + `pnpm/yarn/npm install`). Guard `sudo`: agent has NOPASSWD sudo (Dockerfile) — OK.

Compose into the `sh -lc` bootstrap **before** `exec opencode`, keeping the existing codegraph bootstrap (`codegraph install …; test -d .codegraph || codegraph init;`):

```powershell
# bootstrap becomes:
$bootstrap = "$pmSetup $nmInstall " +
             "codegraph install --yes --target=opencode --location=global; " +
             "test -d .codegraph || codegraph init; " +
             "exec opencode"
```

Add the `$historyDir`, `$maskNodeModules`/`$nmInstall`/`$nmVol` (SHA-12 of lowercased workspace), and `$pmSetup` blocks copied from claude/run.ps1; append the volume args to `$runArgs`; keep `--userns=keep-id` (podman) and `TZ` logic. Update the header comment + SECURITY note (history dir may hold conversation content — cover via `.gitignore`).

**Rationale:** Direct structural port; the only opencode-specific deltas are the **destination paths** (`~/.local/share/opencode/storage` vs `~/.claude/projects`; add `~/.cache/opencode` for Bun plugin installs). node_modules masking still applies — a Node *project* in `/workspace` has the same win32-native-binary problem regardless of which agent drives it. codegraph bootstrap preserved.

**Verification:** `./run.ps1` in a Node project dir with a host `node_modules` → console prints the mask+reinstall line, container gets Linux deps, host `node_modules` untouched. Start a session, exit, re-run → prior session visible (history persisted). `docker volume ls` shows `opencode-cache`, `pm-cache`, `pnpm-store-cache`, `nmvol-<hash>`. Dir without `node_modules` → plain bind-mount, no reinstall.

**If this fails:** revert run.ps1 to the auth-only launcher (current behavior). History/caches simply don't persist (pre-port status quo).

---

### Step 5: README.md

**Objective:** Document the toggle set (`go`/`python`, `.NET` excluded + why), agent-browser (system Chromium, `AGENT_BROWSER_EXECUTABLE_PATH`), and run.ps1 state behavior.
**Confidence:** High
**Depends on:** Steps 1-4

**Files:** `opencode/README.md`

**Changes:** update "Optional language features" (real set now), add an agent-browser note, extend the Run section with history/caches/node_modules-mask behavior, mirroring the depth of `claude/README.md`.

**Verification:** README matches shipped flags/behavior; no stale "no optional language features" claim.

**If this fails:** docs-only; revert freely.

---

## Verification Plan

### Automated Checks
- [ ] `./build.ps1 -Image opencode-custom:v1 -Engine docker` (default set) builds clean; `agent-browser --version` passes in-build.
- [ ] `./build.ps1 -Disable python` and `-Enable go` both build; unknown language rejected.
- [ ] `pwsh -File prepare.ps1` against fixtures (with-MCP, no-MCP, JSONC) — no crash, BOM-less output.

### Manual Verification
- [ ] `docker run --rm … sh -lc 'go version; python3 --version; node --version; codegraph --version; agent-browser --version; ls ~/.config/opencode/skills/agent-browser'` reflects the enabled set.
- [ ] `./run.ps1` twice in a Node project → history persists, node_modules masked, caches as volumes.
- [ ] `opencode/Dockerfile.slim` absent.

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected Result |
|-----------|---------------|-----------------|
| Toggles work | build with `-Disable python`, inspect image | python3 absent, go present |
| agent-browser on Alpine | in-build `--version` + runtime browser resolve | exits 0, uses `/usr/bin/chromium` |
| MCP rewrite | prepare.ps1 on fixture | Win command[0] rewritten/dropped, BOM-less |
| State persists | run.ps1 ×2 | session history survives `--rm` |
| No slim | `ls opencode/` | no `Dockerfile.slim` |

---

## Rollback Plan

Per-step rollback noted above. Full abandon: `git checkout -- opencode/Dockerfile opencode/build.ps1 opencode/prepare.ps1 opencode/run.ps1 opencode/README.md && rm -rf opencode/skills`. Restores the minimal template; no external state to unwind (image/volumes are disposable).

---

## Notes

### Risks
- **agent-browser musl incompatibility** (assumption 1): the prebuilt Rust binary may be glibc-only. Mitigation: build-time smoke test + `gcompat` fallback + documented skill-stub-only degradation. **Primary redteam target.**
- **opencode storage path** (assumption 4): if opencode keys sessions by something other than a stable `/workspace`-derived project id, the fixed history mount won't reload prior sessions. Mitigation: verify the actual `~/.local/share/opencode/` tree from a real run before wiring.
- **apk repo availability** (assumption 3): `go`/`py3-pip` must be in the base's pinned Alpine repos. Mitigation: verify `apk search` against the base image's Alpine version early in Step 1.
- **Image size growth**: node+npm+chromium+agent-browser add substantial layers. Accepted (matches claude's footprint intent); no slim variant to keep lean.

### Open Questions
- None blocking. All four verify-early assumptions have documented fallbacks that degrade gracefully rather than block.

---

## Split Decision

**Verdict:** `No split — heuristic (5 steps) tripped but steps are tightly coupled through shared files and a single scope.`

Rationale: all files live in the one `opencode/` projex scope (no cross-scope, no cross-repo, no upstream/downstream mix → no mandatory split). Steps 1 and 2 both edit `Dockerfile`; splitting would produce sibling plans making concurrent edits to the same file (merge hazard) for no isolation benefit. The human scoped this explicitly as a single plan → single redteam pair. Size is moderate (5 focused steps, one new small file). Keep as one plan.
