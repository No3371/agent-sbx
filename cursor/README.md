# Custom Cursor CLI sandbox template

Built on `debian:bookworm-slim` (glibc); the Cursor CLI (binary name `agent`,
package `cursor-agent`) is installed at build time via the official installer:

```bash
curl https://cursor.com/install -fsS | bash
```

run as the non-root `agent` user so it lands directly under
`/home/agent/.local/{bin,share}`. Adds:

- **git, bash, curl, jq, openssh-client, sudo, tini** — the baseline a coding
  agent needs to work in a repo
- A non-root **agent** user (uid 1000), matching the `claude/`/`opencode/`/`codex/` templates
- Host `~/.cursor/{cli-config.json,mcp.json}` copied in by `prepare.ps1` — an
  **allowlist**, not a filtered recursive copy (see "What `prepare.ps1`
  stages" below for why)
- **Node 25** (NodeSource) + npm — not needed by `agent` itself (it's a
  self-contained native binary), only by the shared dev-tool trio below
- **codegraph**, **agent-browser** (browser automation; its Chrome-for-Testing
  browser is baked at build time via `agent-browser install --with-deps`), and
  optional **Go / Python** toolchains

No `docker/sandbox-templates:cursor` base exists, so like `opencode/` (and
unlike `claude/`/`codex/`) there's no sbx integration here — this is the
plain-docker path only, run via `run.ps1`. No credentials are baked into the
image; see "Auth" below for how `run.ps1` handles login.

## Prerequisites

- **Windows** — build scripts are PowerShell 5.1; Linux/Mac not yet supported
- **PowerShell 5.1** — `pwsh` (PowerShell Core 7.x) has known encoding differences; use Windows PowerShell
- **podman** (or docker) — pass `-Engine docker` to use Docker instead

## Build

```powershell
./prepare.ps1                                                 # stage host ~/.cursor
./build.ps1 -Image docker.io/<user>/cursor-custom:v1 -Push    # podman build + push
```

`build.ps1` runs `prepare.ps1` automatically unless `-SkipPrepare` is passed,
and defaults to `-Engine podman`. Pass `-Engine docker` to use Docker.

### Optional language features

Two toolchains toggle on/off; **both are ON by default**:

| Language | Install | Default |
|----------|---------|---------|
| `go`     | official tarball, pinned `GO_VERSION`          | on |
| `python` | `python3`, `python3-pip`, `python3-venv` (apt) | on |

```powershell
./build.ps1 -Image cursor-custom:v1 -Engine docker              # both on (default)
./build.ps1 -Image cursor-custom:v1 -Disable python -Engine docker  # go only
./build.ps1 -Image cursor-custom:v1 -Enable go -Engine docker       # go only (explicit)
```

`-Enable`/`-Disable` are mutually exclusive; an unknown selector is rejected.
`node` is **not** a toggle — it's a baseline dependency for codegraph /
agent-browser / playwright, not for `agent` itself (which needs no Node
runtime at all). No `pnpm` is baked in here (mirrors `codex/`, not
`opencode/`) — run pnpm-lockfile projects in the `claude`/`opencode` images.

### agent-browser

`agent-browser` (browser automation CLI for agents) is baked from npm, and its
**Chrome for Testing** browser is installed at build time via
`agent-browser install --with-deps` — so no runtime browser download is
needed. A discovery-stub skill ships at `~/.cursor/skills/agent-browser/SKILL.md`
(Cursor's global skill directory); the CLI serves its own up-to-date usage
docs via `agent-browser skills get core`.

## Run

From any project directory:

```powershell
# image must already be in the engine's local store (build.ps1, or `docker load <tar>`)
<repo>\cursor\run.ps1 -Image cursor-custom:v1 -Engine docker
```

Mounts the current directory as `/workspace` and launches `agent`
interactively.

### Auth

Cursor CLI's on-disk auth storage location isn't documented upstream (unlike
opencode's `~/.local/share/opencode/auth.json`), so — mirroring `codex/`'s
deliberate decision not to guess and bind-mount a credential path (see its
`run.ps1` header + `.projex/2607060232...`) — `run.ps1` authenticates fresh
inside each ephemeral container rather than persisting anything host-side:

- **`CURSOR_API_KEY` set on the host** — passed straight through to the
  container; `agent` picks it up on its own (Cursor's documented headless/CI
  auth path), and `run.ps1` skips the login step entirely.
- **Otherwise** — `NO_OPEN_BROWSER=1 agent login` runs inside the container on
  every launch, printing a URL to complete browser auth manually (there's no
  browser inside the container to open it for you).

No session history, model prefs, or auth token persist across `--rm` — every
run starts from the login step. If that friction becomes a problem, revisit
once Cursor documents where `agent login` actually writes its credentials.

**Persistent state across `--rm`:** only the npm cache (`cursor-pm-cache`
named volume, `~/.npm`) — the one piece of state here with a clearly
documented, stable location.

**`node_modules` masking:** if the host workspace has a `node_modules`, it is
masked with a per-project named volume (`cursor-nmvol-<hash>`) and
Linux-native deps are reinstalled inside the container (`npm`/`yarn` per
lockfile; a `pnpm-lock.yaml` project errors visibly — no pnpm baked in here).
The host's `node_modules` (with its win32-native binaries) is left untouched.

Use from any project dir without retyping the repo path — add to your
PowerShell profile (`$PROFILE`):

```powershell
function cursorrun { & "<repo-path>\cursor\run.ps1" @args }
```

Then just run `cursorrun` from any project directory.

## Layout

```
cursor/
├── Dockerfile
├── prepare.ps1                       # stages host ~/.cursor (allowlist + MCP rewrite)
├── build.ps1
├── run.ps1
├── retag-tar.ps1
├── .dockerignore
├── skills/
│   └── agent-browser/SKILL.md        # repo-owned discovery stub, baked into image
└── context/
    └── .cursor/                      # generated by prepare.ps1
```

## What `prepare.ps1` stages

Unlike `opencode/`'s filtered-recursive copy of `~/.config/opencode`, this is
an **allowlist** — the same choice `codex/prepare.ps1` made for `~/.codex`.
`~/.cursor` is shared with the Cursor *editor*, not CLI-only like opencode's
config dir, so on a real dev machine it's expected to also hold IDE-scale
state (chat/session databases, extension caches, telemetry/machine IDs,
indexes, possibly MCP OAuth tokens) that has no business in a baked image and
that a blanket recursive copy would silently vacuum up. Only two files are
staged, both host-scoped globally:

| File | Handling |
|---|---|
| `cli-config.json` | copied as-is — schema (`editor`, `permissions.allow/deny`, `model`, `display.*`, `sandbox.*`, `network.*`, `attribution.*`, ...) has no host-path or credential fields |
| `mcp.json` | local server `command` strings rewritten Win → Linux/bare name (same `mcpServers.<name>.{command,args,env}` schema Claude Desktop/Code use); a server whose command still holds a `C:\...`-style path after rewrite is dropped with a warning; `url`-based remote servers pass through untouched |

Project-level config (`<project>/.cursor/cli.json`), rules (`.cursor/rules/`),
and per-project `AGENTS.md`/`CLAUDE.md` are **not** baked — the CLI reads
those from the mounted `/workspace` at runtime, same as any other project file.

Everything else under `~/.cursor` (session state, extension data, etc.) is
never touched by `prepare.ps1` — if you need something else from that
directory baked in, add it to the allowlist deliberately rather than widening
the copy.

### What's excluded, always

Files matching known credential patterns (`*.key`, `*.pem`, `*.token`,
`*.credentials`, `secrets.json`, `*.p12`, `*.pfx`, `token.json`, `auth.json`)
are never staged, even though the two allowlisted files don't match any of
these patterns — defense in depth, and a final scan over the staged tree
removes any unexpected match.

## Notes

- Base is an official **named** tag (`debian:bookworm-slim`), not
  digest-pinned — it's still a rolling tag, so a rebuild on a different date
  can pull a different patch level. Same honest caveat as `opencode/`.
- **`agent` itself is intentionally unpinned.** The official installer
  (`curl https://cursor.com/install -fsS | bash`) has no version-pin knob —
  the script embeds a fixed version string internally and always resolves to
  whatever `cursor.com/install` currently serves, unlike the npm-pinned
  `CODEGRAPH_VERSION`/`AGENT_BROWSER_VERSION`/`PLAYWRIGHT_VERSION` ARGs. Cursor
  CLI also self-updates by default (`agent update`) once running. If exact
  reproducibility matters more than always-current, pin by downloading a
  specific `https://downloads.cursor.com/lab/<version>/<os>/<arch>/agent-cli-package.tar.gz`
  directly instead of running the installer script — not done here because
  the task called for the installer command verbatim.
- `$Destination` is recreated clean on each `prepare.ps1` run — there is no incremental staging.
