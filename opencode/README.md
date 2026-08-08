# Custom OpenCode sandbox template

Built on `debian:bookworm-slim` (glibc); the `opencode` CLI is installed at
build time via `npm i -g opencode-ai@<pinned>` (no dependency on a third-party
pre-baked image). Adds:

- **git, bash, curl, jq, openssh-client, sudo, tini** — the baseline a coding
  agent needs to work in a repo
- A non-root **agent** user (uid 1000), matching the `claude/`/`codex/`
  templates
- Host `~/.config/opencode` (`opencode.json`, `AGENTS.md`, `plugin/`,
  `skills/`, vendored plugin repos, ...) **and** `~/.agents/skills` (the
  cross-agent skills standard — opencode auto-loads
  `~/.agents/skills/<name>/SKILL.md`) staged by `prepare.ps1` with the
  incremental robocopy `/MIR` system shared with `claude/`/`codex/`. The one
  rewrite it does (much lighter than claude/codex): local `mcp` server
  `command` arrays in `opencode.json` have their Windows paths mapped to
  Linux, and servers with no Linux mapping are dropped (see "opencode.json
  MCP rewrite" below). `.git/`/`.github/`/`node_modules/` dirs and files
  matching known credential patterns are skipped.
- **Node 25** (NodeSource) **+ npm + pnpm** (global npm install) — opencode's
  install channel; also drives the `run.ps1` node_modules reinstall
- **codegraph**, **agent-browser** (browser automation; its Chrome-for-Testing
  browser is baked at build time via `agent-browser install --with-deps`,
  standard glibc flow), and optional **Go / Python** toolchains

No `docker/sandbox-templates:opencode` base exists, so unlike `claude/` and
`codex/` there's no sbx integration here — this is the plain-docker path only,
run via `run.ps1`. Host auth (`~/.local/share/opencode/auth.json`) and state
(`~/.local/state/opencode`, including the selected model) are bind-mounted at
runtime; nothing credential-related is baked into the image.

## Prerequisites

- **Windows** — build scripts are PowerShell 5.1; Linux/Mac not yet supported
- **PowerShell 5.1** — `pwsh` (PowerShell Core 7.x) has known encoding differences; use Windows PowerShell
- **podman** (or docker) — pass `-Engine docker` to use Docker instead

## Build

```powershell
./prepare.ps1                                                    # stage host ~/.config/opencode
./build.ps1 -Image opencode-custom:v1                             # podman build
```

`build.ps1` runs `prepare.ps1` automatically unless `-SkipPrepare` is passed,
and defaults to `-Engine podman`. Pass `-Engine docker` to use Docker.
The image lands directly in the engine's local store — `-Tar`/`-Retag`/
`-LoadToDocker`/`-LoadToPodman` are only for moving it to the *other*
engine's store (Docker and Podman don't share one) or to another machine.

### Optional language features

Two toolchains toggle on/off; **both are ON by default**:

| Language | Install | Default |
|----------|---------|---------|
| `go`     | official tarball, pinned `GO_VERSION`          | on |
| `python` | `python3`, `python3-pip`, `python3-venv` (apt) | on |

> **Note on `python`:** the NodeSource `nodejs` package (Node 24) depends on
> `python3`, so a bare `python3` interpreter is **always present** regardless of
> the toggle. `-Disable python` therefore controls only the Python *dev stack*
> (`python3-pip` + `python3-venv` are omitted), not the interpreter itself.
> (On the prior Alpine base `apk add nodejs` pulled no python, so the toggle
> removed it entirely — this is a Debian/NodeSource difference.)

```powershell
./build.ps1 -Image opencode-custom:v1 -Engine docker              # both on (default)
./build.ps1 -Image opencode-custom:v1 -Disable python -Engine docker  # go only
./build.ps1 -Image opencode-custom:v1 -Enable go -Engine docker       # go only (explicit)
```

`-Enable`/`-Disable` are mutually exclusive; an unknown selector is rejected
(`Unknown language 'dotnet'. Supported: go, python.`). **`.NET` is not yet a
toggle** — the prior Alpine base excluded it because musl .NET is niche; on this
glibc base claude's `dotnet-sdk` apt path would apply directly, so it is now
feasible (see Notes) but out of scope for this base swap. `node` is **not** a
toggle — it's a baseline dependency (opencode + agent-browser + the run.ps1
reinstall path). Go is pinned via `GO_VERSION`; the python apt packages are
unpinned (they track bookworm's stream) and `pnpm@latest` (global npm install)
floats, so those can drift between rebuilds.

### agent-browser

`agent-browser` (browser automation CLI for agents) is baked from npm, and its
**Chrome for Testing** browser is installed at build time via
`agent-browser install --with-deps` (the standard glibc flow) — so no runtime
browser download is needed. A discovery-stub skill ships at
`~/.config/opencode/skills/agent-browser/SKILL.md`; the CLI serves its own
up-to-date usage docs via `agent-browser skills get core`.

## Run

From any project directory:

```powershell
# image must already be in the engine's local store (build.ps1, or `docker load <tar>`)
<repo>\opencode\run.ps1 -Image opencode-custom:v1 -Engine docker
```

Mounts the current directory as `/workspace` and launches `opencode`
interactively. It uses your native OpenCode login from
`%USERPROFILE%\.local\share\opencode\auth.json`; first run only, authenticate
inside the container (`opencode auth login`) if that file is absent. Your saved
model selection also follows from `%USERPROFILE%\.local\state\opencode`.

### GPU

Pass `-GPU` to expose all host GPUs to the container (`--gpus all`). Docker or
Podman must already have its GPU runtime configured.

**Persistent state across `--rm`:**

- **Session history** — opencode stores all sessions in a single SQLite DB
  (`~/.local/share/opencode/opencode.db`). `run.ps1` bind-mounts that DB file
  into a **project-local** `.opencode\opencode.db`, so history travels with the
  project and survives `--rm`. (A hard kill can lose the most recent uncommitted
  turn — the `-wal` sidecar only checkpoints on clean exit.)
- **OpenCode preferences** — the native host state directory
  (`~/.local/state/opencode`) is mounted, preserving the selected model and
  variant; the native host `auth.json` is mounted as a single credential file.
- **Caches** — named volumes persist across runs: `opencode-cache`
  (`~/.cache/opencode`, Bun-installed plugins), `opencode-pm-cache` (`~/.npm`),
  `opencode-pnpm-store-cache` (`~/.pnpm-store`). Names are `opencode-`-prefixed
  so they never collide with the `claude/` template's caches on the same host
  (per-suite isolation — independent lifecycles).
- **`node_modules` masking** — if the host workspace has a `node_modules`, it is
  masked with a per-project named volume (`opencode-nmvol-<hash>`) and
  Linux-native deps are reinstalled inside the container (`pnpm`/`yarn`/`npm`
  per lockfile). The host's `node_modules` (with its win32-native binaries) is
  left untouched. No `node_modules` on the host → plain bind-mount, no reinstall.

**Security:** `.local\share\opencode\auth.json` carries live provider
credentials. Treat it like an SSH key — never commit or share it. The
project-local `.opencode\opencode.db` can hold conversation content — add
`.opencode/` to the project's `.gitignore` if reusing this launcher outside this
repo.

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
├── prepare.ps1                       # stages host ~/.config/opencode + ~/.agents/skills (+ MCP rewrite)
├── build.ps1
├── run.ps1
├── retag-tar.ps1
├── .dockerignore
├── skills/
│   └── agent-browser/SKILL.md        # repo-owned discovery stub, baked into image
└── context/
    ├── .config/opencode/            # generated by prepare.ps1
    └── .agents/skills/              # generated by prepare.ps1 (cross-agent skills)
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
as-is, not stripped) so you can review the auto-approval posture before build/export.

## Notes

- Base is now an official **named** tag (`debian:bookworm-slim`), off the prior
  unaudited third-party `:latest`. Agent tooling (opencode, codegraph,
  agent-browser, playwright, Go) is version-pinned via `ARG`. Honest caveat:
  `bookworm-slim` is itself a rolling tag (not digest-pinned), and `pnpm@latest`
  (global npm install) floats — so the base and pnpm can still drift at the patch level
  between rebuilds. Pin the base to a digest for fully reproducible builds.
- Staging is incremental (robocopy `/MIR`, same system as `claude/`/`codex/`):
  an unchanged host tree costs a stat sweep, and entries deleted on the host are
  purged from the stage. Files the script rewrites or normalizes after copying
  (`opencode.json`, CRLF `.sh` files) re-copy and re-process on every run.
