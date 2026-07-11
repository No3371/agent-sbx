# Custom OpenCode sandbox template

Extends `ghcr.io/anomalyco/opencode` (Alpine + the `opencode` binary only, runs
as root) with:

- **git, bash, curl, jq, openssh-client, sudo, tini** — the baseline a coding
  agent needs to work in a repo (the base image ships only `opencode` and
  `ripgrep`)
- A non-root **agent** user (uid 1000), matching the `claude/`/`codex/`
  templates
- Host `~/.config/opencode` (`opencode.json`, `AGENTS.md`, `plugin/`,
  `skills/`, vendored plugin repos, ...) copied in by `prepare.ps1` with a
  filtered recursive copy. The one rewrite it does (much lighter than
  claude/codex): local `mcp` server `command` arrays in `opencode.json` have
  their Windows paths mapped to Linux, and servers with no Linux mapping are
  dropped (see "opencode.json MCP rewrite" below). `.git/`/`.github/`/
  `node_modules/` dirs and files matching known credential patterns are skipped.
- **codegraph**, **agent-browser** (browser automation via system Chromium),
  **Node.js + npm + pnpm** (agent-browser's install channel; also drives the
  `run.ps1` node_modules reinstall), and optional **Go / Python** toolchains

No `docker/sandbox-templates:opencode` base exists, so unlike `claude/` and
`codex/` there's no sbx integration here — this is the plain-docker path only,
run via `run.ps1`. Host auth (`~/.local/share/opencode/auth.json`) is
bind-mounted at runtime; nothing credential-related is baked into the image.

## Prerequisites

- **Windows** — build scripts are PowerShell 5.1; Linux/Mac not yet supported
- **PowerShell 5.1** — `pwsh` (PowerShell Core 7.x) has known encoding differences; use Windows PowerShell
- **podman** (or docker) — pass `-Engine docker` to use Docker instead

## Build

```powershell
./prepare.ps1                                                    # stage host ~/.config/opencode
./build.ps1 -Image docker.io/<user>/opencode-custom:v1 -Push     # podman build + push
```

`build.ps1` runs `prepare.ps1` automatically unless `-SkipPrepare` is passed,
and defaults to `-Engine podman`. Pass `-Engine docker` to use Docker.

### Optional language features

Two Alpine-native (musl) toolchains toggle on/off; **both are ON by default**:

| Language | apk packages | Default |
|----------|--------------|---------|
| `go`     | `go`                | on |
| `python` | `python3`, `py3-pip` | on |

```powershell
./build.ps1 -Image opencode-custom:v1 -Engine docker              # both on (default)
./build.ps1 -Image opencode-custom:v1 -Disable python -Engine docker  # go only
./build.ps1 -Image opencode-custom:v1 -Enable go -Engine docker       # go only (explicit)
```

`-Enable`/`-Disable` are mutually exclusive; an unknown selector is rejected
(`Unknown language 'dotnet'. Supported: go, python.`). **`.NET` is excluded** —
Alpine ships `dotnet*-sdk` only in edge/community and musl .NET is niche; add it
later if needed. `node` is **not** a toggle — it's a baseline dependency
(agent-browser + the run.ps1 reinstall path). apk toolchain versions are not
pinned (Alpine has no stable per-version pin story here), so they can drift
between rebuilds like the floating base tag.

### agent-browser

`agent-browser` (browser automation CLI for agents) is baked from npm and wired
to Alpine's **system Chromium** via `AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium`.
`agent-browser install` is intentionally **not** run — it would download a glibc
Chrome-for-Testing that cannot run on this musl base. A discovery-stub skill
ships at `~/.config/opencode/skills/agent-browser/SKILL.md`; the CLI serves its
own up-to-date usage docs via `agent-browser skills get core`.

## Run

From any project directory:

```powershell
# image must already be in the engine's local store (build.ps1, or `docker load <tar>`)
<repo>\opencode\run.ps1 -Image opencode-custom:v1 -Engine docker
```

Mounts the current directory as `/workspace` and launches `opencode`
interactively. First run only: authenticate inside the container
(`opencode auth login`) — the token persists to
`%USERPROFILE%\.opencode-docker\auth.json` and survives future runs.

**Persistent state across `--rm`:**

- **Session history** — opencode stores all sessions in a single SQLite DB
  (`~/.local/share/opencode/opencode.db`). `run.ps1` bind-mounts that DB file
  into a **project-local** `.opencode\opencode.db`, so history travels with the
  project and survives `--rm`. (A hard kill can lose the most recent uncommitted
  turn — the `-wal` sidecar only checkpoints on clean exit.)
- **Caches** — named volumes persist across runs: `opencode-cache`
  (`~/.cache/opencode`, Bun-installed plugins), `opencode-pm-cache` (`~/.npm`),
  `opencode-pnpm-store-cache` (`~/.pnpm-store`). Names are `opencode-`-prefixed
  so they never collide with the `claude/` template's glibc caches on the same
  host.
- **`node_modules` masking** — if the host workspace has a `node_modules`, it is
  masked with a per-project named volume (`opencode-nmvol-<hash>`) and
  Linux-native deps are reinstalled inside the container (`pnpm`/`yarn`/`npm`
  per lockfile). The host's `node_modules` (with its win32-native binaries) is
  left untouched. No `node_modules` on the host → plain bind-mount, no reinstall.

**Security:** `.opencode-docker\auth.json` carries live provider credentials
once populated. Treat it like an SSH key — never commit, never share the
`.opencode-docker` directory. The project-local `.opencode\opencode.db` can hold
conversation content — add `.opencode/` to the project's `.gitignore` if reusing
this launcher outside this repo.

Use from any project dir without retyping the repo path — add to your
PowerShell profile (`$PROFILE`):

```powershell
function ocrun { & "<repo-path>\opencode\run.ps1" @args }
```

Then just run `ocrun` from any project directory.

## Layout

```
opencode/
├── Dockerfile
├── prepare.ps1                       # stages host ~/.config/opencode (+ MCP rewrite)
├── build.ps1
├── run.ps1
├── retag-tar.ps1
├── .dockerignore
├── skills/
│   └── agent-browser/SKILL.md        # repo-owned discovery stub, baked into image
└── context/
    └── .config/opencode/            # generated by prepare.ps1
```

## What `prepare.ps1` excludes (never staged)

- `.git/`, `.github/` dirs anywhere in the tree (e.g. vendored plugin repos cloned under `skills/`)
- `node_modules/` dirs anywhere in the tree — built on the host (Windows); any native `.node` addons inside won't load in the Linux container, so baking them in is dead weight at best, silently broken at worst. Not reinstalled for Linux at build time — a plugin with an npm dependency needs that added separately.
- Files matching known credential patterns (`*.key`, `*.pem`, `*.token`, `*.credentials`, `secrets.json`, `*.p12`, `*.pfx`, `token.json`, `auth.json`) — defense in depth; opencode's real auth lives in `~/.local/share/opencode/auth.json`, which is bind-mounted at runtime instead, not baked

Everything else (`opencode.json`, `AGENTS.md`, `plugin/`, `skills/`,
lockfiles, ...) is copied through — unchanged except for the opencode.json MCP
rewrite below.

### opencode.json MCP rewrite

Local `mcp` servers in `opencode.json` use a `command` **array**
(`["npx","-y","pkg"]`). Windows paths in those arrays don't exist in the Linux
container, so `prepare.ps1`:

- rewrites **every** element of each local server's `command` (npx-cache
  `.cmd` shims → bare tool name; `node.exe`/git-bash/WSL node paths → `node`;
  `%USERPROFILE%\.config\opencode\...` → `/home/agent/.config/opencode/...`),
- **drops** any local server still holding a `C:\...`-style path after
  rewriting (with a warning) — a broken server is worse than a missing one,
- leaves `remote` servers untouched, writes back **BOM-less** valid JSON, and
  skips the rewrite (with a warning) if `opencode.json` is JSONC (has comments).

If `opencode.json` has a `permission` block, `prepare.ps1` **warns** (it is baked
as-is, not stripped) so you can review the auto-approval posture before `-Push`.

## Notes

- Base image tag (`ghcr.io/anomalyco/opencode`) is floating (`:latest`) —
  rebuilds on different dates may pull a different base. Pin to a digest for
  fully reproducible builds.
- `$Destination` is recreated clean on each `prepare.ps1` run — there is no incremental staging.
