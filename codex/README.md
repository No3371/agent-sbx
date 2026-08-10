# Custom Codex CLI sandbox

Builds `codex-custom:v1` from `node:25-bookworm-slim` with Codex CLI, Node 25,
Python 3, CodeGraph, agent-browser, Playwright, and Chromium. The container runs
as **root**, uses `/root/.codex`, and works in `/workspace`.

`rm-guard` only prevents common accidental deletion of workspace Git metadata. It
is not privilege isolation: root plus Codex approval bypass is for a dedicated,
trusted local sandbox only.

## Support and prerequisites

- **Docker Desktop on Windows** is the sole release-supported engine/platform.
- **Windows PowerShell 5.1** and `robocopy.exe` are required for preparation.
- Podman fake-argv behavior may be exercised by maintainers, but Podman is not a
  supported or documented release path until it has its own live validation row.
- Staged host inputs are trusted local payloads. Filename filters reduce obvious
  accidental inclusion; they do not prove arbitrary content is secret-free.

## Build

```powershell
./build.ps1 -Image codex-custom:v1
```

`build.ps1` uses Docker and the canonical `Dockerfile` by default. It runs
`prepare.ps1` unless `-SkipPrepare` is supplied. `-Tar`, `-Retag`,
`-LoadToDocker`, and `-LoadToPodman` preserve their existing transfer-only
semantics; the default remains local-only and no image is pushed.

Preparation accepts isolated fixture inputs when needed:

```powershell
./build.ps1 -Image codex-custom:v1 `
  -HostCodexDir C:\fixture\.codex `
  -HostAgentsSkillsDir C:\fixture\.agents\skills `
  -Destination C:\fixture\context\.codex `
  -SkillsDestination C:\fixture\context\.agents\skills
```

## Run

From any workspace:

```powershell
<repo>\codex\run.ps1 -Image codex-custom:v1
```

The launcher binds only the workspace and package caches, opens an interactive
container at `/workspace`, performs fresh `codex login --device-auth`, then
starts `codex --dangerously-bypass-approvals-and-sandbox`. It mounts no host
Codex auth, history, sessions, logs, SQLite state, config, or secret environment
variables. GPU support remains `-GPU`; timezone mapping remains automatic.

CodeGraph install/index initialization is intentionally non-blocking. A visible
launcher warning precedes the privileged TUI if either fails.

## Dependency caches

When a host workspace has `node_modules`, it is masked with
`codex-nmvol-<workspace-hash>-<lock-hash>`. A changed lockfile selects a fresh
volume. The Node-25 npm cache is `codex-pm-cache-node25` at `/root/.npm`.
Root writes new volumes directly; no `sudo`, `chown`, or user namespace remap is
performed. Legacy `nmvol-*` and `pm-cache` volumes are not automatically
removed; operators may prune only explicitly selected old volumes.

The existing npm/yarn/corepack selection remains unchanged. pnpm still is not
baked into this image.

## Staged build inputs

`prepare.ps1` writes ignored generated context only:

```text
codex/
├── context/.codex/
│   ├── config.toml
│   ├── AGENTS.md
│   ├── skills/
│   ├── vendor_imports/skills/
│   ├── plugins/cache/
│   └── staged-input-inventory.json
└── context/.agents/skills/
```

The filtered Codex input includes `config.toml`, `AGENTS.md`, `skills/`,
`vendor_imports/skills/`, and `plugins/cache/`; it never whole-tree mirrors
`~/.codex`. Shared `~/.agents/skills` is mirrored separately. Missing optional
skill trees create deterministic `.keep` placeholders; missing `AGENTS.md`
creates Codex's empty stub.

Before mutation, preparation canonicalizes inputs/destinations and rejects roots,
source/destination ancestry or overlap, generated-envelope escapes, malformed or
duplicate canonical skills, and reparse traversal. Its marker gates stale cleanup.
It removes stale `.git`, `.github`, `node_modules`, and credential-pattern files,
normalizes staged `.sh` CRLF to LF, and records only relative path, SHA-256,
package name/version, and lifecycle-script-key inventory data. It never prints
source absolute paths or staged file content.

Plugin dependency installation uses a no-login `pluginbuild` user with
`npm install --ignore-scripts`; host-derived lifecycle scripts never receive root
authority. The image records critical hashes after that phase.

## Config transformation

Top-level settings, kept plugin entries, and MCP server entries remain. Windows
paths in MCP `command` values are reduced to their bare executable name; `args`
remain unchanged. `[windows]`, `[projects.*]`, host `[marketplaces.*]`, and
plugins belonging to dropped `openai-primary-runtime` are removed. Non-bundled
staged plugin marketplaces are regenerated under `/root/.codex/plugins/cache/...`.

## Operational boundaries

- Device auth and all container runtime state are ephemeral per launch.
- Browser binaries are baked during image build for offline runtime use.
- The base image tag and unpinned Codex package remain mutable; pin a base digest
  and package version if reproducibility is required.
- Root privilege, trusted staged payloads, and approval bypass require a dedicated
  local environment. Do not treat this suite as multi-tenant or least-privilege.
