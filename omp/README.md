# Custom OMP (oh-my-pi) sandbox template

OMP — binary name `omp`, config dir `~/.omp`, upstream
[`can1357/oh-my-pi`](https://github.com/can1357/oh-my-pi) — is a
multi-provider, TUI coding-agent CLI. Unlike the other suites here, the agent
is **not** installed from npm into a Debian base: `build.ps1` builds the
upstream repo into a local base image (`oh-my-pi/pi:dev`) and this suite's
`Dockerfile` layers on top of it (`FROM ${OMP_BASE}`). Adds:

- **bash, ca-certificates, curl, git, gnupg, jq, less, openssh-client,
  ripgrep, sudo, tini, tzdata** — the baseline a coding agent needs in a repo
- **Node 26** (via nvm) + npm, plus **pnpm** installed with the base image's
  `bun`. `bun`, `node`, `npm`, `npx` and `codegraph` are symlinked into
  `/usr/local/bin` so they resolve in the non-interactive, non-login shells an
  agent's shell tool actually spawns — nvm's shell-init never runs there.
- **codegraph**, **agent-browser** (browser automation; its Chrome-for-Testing
  browser is baked at build time via `agent-browser install --with-deps`),
  **Playwright** + chromium, and optional **Go / .NET SDK** toolchains
  (`python3` + pip + venv are unconditional)
- **rm-guard** — the real `rm` is shadowed in place so `/workspace/.git` cannot
  be deleted (see "rm-guard" below)
- Host `~/.omp/agent` and `~/.omp/plugins` staged by `prepare.ps1` with a
  filtered, incremental copy — no path rewriting is performed

The image runs as **root** and the agent's config tree lives at `/root/.omp`.
**The build bakes host provider credentials into the image** — read the warning
under "Auth" before you push or share one.

## Prerequisites

- **Windows** — build scripts are PowerShell 5.1; Linux/Mac not yet supported
- **PowerShell 5.1** — `pwsh` (PowerShell Core 7.x) has known encoding differences; use Windows PowerShell
- **podman** (or docker) — `build.ps1` defaults to podman, `run.ps1` to docker;
  `-Engine` overrides either
- **Network access to GitHub** — the base image is built from source on every
  `build.ps1` run

## Build

```powershell
./prepare.ps1                                             # stage host ~/.omp
./build.ps1 -Image docker.io/<user>/omp-custom:v1 -Push   # podman build + push
```

`build.ps1` runs `prepare.ps1` automatically unless `-SkipPrepare` is passed.

### Base image

`build.ps1` always runs

```powershell
<engine> build -t oh-my-pi/pi:dev "https://github.com/can1357/oh-my-pi.git#<OMPPin>"
```

before building this suite's `Dockerfile`, and there is no flag to skip it, so
every build re-checks upstream. `-OMPPin <ref>` selects a tag, branch or
commit; empty (the default) leaves the URL fragment blank so upstream's default
branch wins. The Dockerfile consumes the result through `ARG OMP_BASE` (default
`oh-my-pi/pi:dev`).

### Optional language features

Two toolchains toggle on/off; **both are ON by default**:

| Language | Install | Default |
|----------|---------|---------|
| `go`     | official tarball, pinned `GO_VERSION` (`1.26.3`)   | on |
| `dotnet` | `dotnet-sdk-$DOTNET_VERSION` (`10.0`) via packages.microsoft.com | on |

```powershell
./build.ps1 -Image omp-custom:v1 -Engine docker                     # both on (default)
./build.ps1 -Image omp-custom:v1 -Disable dotnet -Engine docker     # go only
./build.ps1 -Image omp-custom:v1 -Enable go -Engine docker          # go only (explicit)
```

`-Enable`/`-Disable` are mutually exclusive; an unknown selector is rejected
(`Unknown language 'python'. Supported: go, dotnet.`). **`python` is not a
toggle** — `python3`, `python3-pip` and `python3-venv` are installed
unconditionally. Nor are `node`/`bun`/`pnpm`: they are the agent's own runtime,
and codegraph, agent-browser and `run.ps1`'s `node_modules` reinstall all lean
on them. Go is pinned via `GO_VERSION`; the apt-sourced Python and .NET
packages track their streams and `pnpm@latest` floats, so those can drift
between rebuilds.

### agent-browser and codegraph

`codegraph` `1.3.0` (npm `@colbymchenry/codegraph`), `agent-browser` `0.31.1`
and `playwright` `1.61.1` are baked in at pinned versions. agent-browser's
**Chrome for Testing** browser is installed at build time via
`agent-browser install --with-deps`, and Playwright's chromium via
`playwright install --with-deps chromium`, so no runtime browser download is
needed.

Discovery-stub skills for both ship from this repo (`skills/`, Agent Skills
standard) so they survive whatever is in the host's `~/.omp/agent/skills`; the
agent-browser CLI serves its own always-current usage docs via
`agent-browser skills get core`. The codegraph stub does not currently reach
the agent's skills directory, so only the agent-browser stub is loaded — the
`codegraph` CLI is on `PATH` either way. `run.ps1` runs `codegraph init` on
first launch so the graph exists for the plain-CLI commands
(`codegraph explore`, `query`, `node`, `callers`, `callees`, `impact`,
`affected`).

OMP has an MCP client (`~/.omp/agent/mcp.json`, schema published by oh-my-pi),
so codegraph can also be driven as an MCP server (`codegraph serve --mcp`)
rather than as a bare CLI. `prepare.ps1` copies that file through without
rewriting it — see the caveats under "What `prepare.ps1` stages".

### rm-guard

`rm-guard/rm-guard.sh` is copied in and the real coreutils `rm` is replaced
with a symlink to it (the original is preserved at `/usr/bin/rm.real`). Any
operand resolving to `/workspace/.git`, to something inside it, or to an
ancestor of it is refused; everything else passes through unchanged. A
colon-separated `RM_GUARD_PROTECTED_PATHS` overrides the protected list. The
Dockerfile self-tests the guard at build time, so a regression fails the build
rather than silently shipping.

It is a guard against accidental deletion, not a security boundary — and
because this image runs as root, an agent that wants to can undo it. See the
header of `rm-guard/rm-guard.sh`.

## Run

From any project directory:

```powershell
# image must already be in the engine's local store (build.ps1, or `docker load <tar>`)
<repo>\omp\run.ps1 -Image omp-custom:v1 -Engine docker
```

Mounts the current directory as `/workspace` and launches `omp launch`
interactively under `tini`. The bootstrap reinstalls Linux-native
`node_modules` when they were masked, runs `codegraph init` unless
`.codegraph/` already exists (a codegraph failure there cannot block launch),
then `exec`s the agent.

The host timezone is forwarded as `TZ` when PowerShell can resolve an IANA
name. Windows PowerShell 5.1 has no IANA conversion, so under it the container
runs on UTC.

### Auth

> **The build bakes host provider credentials into the image.** OMP keeps
> credentials in SQLite (`agent.db`, tables `auth_credentials` /
> `auth_credential_blocks`), and `prepare.ps1`'s exclusion list matches
> *filenames* — `auth.json`, `*.token`, `*.key` and friends — so it does not
> catch them: `agent.db` and its `-wal` sidecar are staged and `COPY`ed in.
> Treat any image built here as a secret. Do not `-Push` it to a registry you
> do not control, and do not share an exported tar.

- `run.ps1` bind-mounts no credential file, so the exposure is in the image
  layers rather than at runtime.
- **Provider API key env vars set on the host are forwarded automatically.**
  `run.ps1` carries the full env-var catalog from OMP's provider docs
  (Anthropic, OpenAI, Bedrock, Azure OpenAI, Vertex, Cloudflare, OpenRouter,
  xAI, and the rest) plus `CURSOR_API_KEY` and the search-provider keys, and
  passes through whichever are set:

  ```powershell
  $env:ANTHROPIC_API_KEY = 'sk-ant-...'
  <repo>\omp\run.ps1 -Image omp-custom:v1 -Engine docker
  ```

  This authenticates without relying on whatever the staged `agent.db` happens
  to carry. It does not remove those baked credentials — only keeping
  `agent.db` out of the staging tree does that.
- `GOOGLE_APPLICATION_CREDENTIALS` is deliberately **not** forwarded — it points
  at a host file path that doesn't exist in the container; use
  `gcloud auth application-default login` inside the container instead, or
  bind-mount the key file yourself.

**Persistent state across `--rm`:**

- **Session history** — OMP organizes sessions under `~/.omp/agent/sessions/`
  by working directory, and the container's cwd is always `/workspace`, so a
  single shared volume would mix every project's history together. `run.ps1`
  mounts a **per-project named volume** there instead
  (`pi-sessions-<hash-of-workspace-path>`).
- **npm cache** — `pi-pm-cache` named volume (`/root/.npm`).
- **pnpm store** — `pi-pnpm-store-cache` named volume mounted at
  `/root/.pnpm-store`. `run.ps1` does not issue `pnpm config set store-dir`, so
  this volume only helps if pnpm's own default store resolves there (see
  "Notes").

**`node_modules` masking:** if the host workspace has a `node_modules`, it is
masked with a per-project named volume (`pi-nmvol-<hash>`) and Linux-native
deps are reinstalled inside the container (`pnpm`/`yarn`/`npm` per lockfile).
The host's `node_modules` (with its win32-native binaries) is left untouched.
The `pi-` prefix keeps these volumes off the `claude/`/`opencode/`/`cursor/`/
`codex/` suites' volumes for the same workspace.

Use from any project dir without retyping the repo path — add to your
PowerShell profile (`$PROFILE`):

```powershell
function omprun { & "<repo-path>\omp\run.ps1" @args }
```

Then just run `omprun` from any project directory.

## Layout

```
omp/
├── Dockerfile
├── prepare.ps1                       # stages host ~/.omp/{agent,plugins} (incremental, no rewrite)
├── build.ps1                         # builds the oh-my-pi base, then this image
├── run.ps1
├── retag-tar.ps1
├── .dockerignore
├── rm-guard/
│   └── rm-guard.sh                   # shadows coreutils `rm`, protects /workspace/.git
├── skills/
│   ├── agent-browser/SKILL.md        # repo-owned discovery stub, baked into image
│   └── codegraph/SKILL.md            # repo-owned discovery stub
└── context/
    └── .omp/{agent,plugins}/         # generated by prepare.ps1
```

## What `prepare.ps1` stages

`prepare.ps1 -HostOMPDir <path> -Destination <path>` mirrors exactly two
directories — `~/.omp/agent` and `~/.omp/plugins` — into
`context/.omp/{agent,plugins}`. There is **no** rewriting step: unlike
`opencode/`'s `opencode.json` or `cursor/`'s `mcp.json`, nothing here is
path-mapped from Windows to Linux.

Staging is **incremental**, via `robocopy /MIR`: files are compared on size +
write time and only differences transfer, while `/MIR` purges destination
entries whose source is gone. Robocopy exit codes below 8 are success; 8+
throws.

Never staged:

- Files matching known credential patterns at any depth — `auth.json`,
  `*.credentials`, `.credentials`, `*.token`, `.token`, `token.json`, `.auth`,
  `secrets.json`, `*.key`, `*.pem`, `*.p12`, `*.pfx`. A destination-side sweep
  also deletes any such file already sitting in the staging tree, warning as it
  goes.
- `.git/`, `.github/`, `node_modules/` dirs anywhere in the tree — host-built
  `node_modules` may carry win32-native `.node` addons that won't load in the
  Linux container.

Everything else is copied through unchanged, including `config.yml`,
`mcp.json`, `last-changelog-version`, OMP's SQLite state (`agent.db`,
`history.db`, `models.db` and any `-wal`/`-shm` sidecars), `sessions/` and
`terminal-sessions/`. Host `*.sh` files are normalized CRLF → LF afterwards
(bash rejects a `\r` in a shebang), and a `.keep` placeholder is written into
each stage dir so the Dockerfile `COPY` shape stays stable when the host has no
such directory.

Consequences worth knowing before you build:

- **`agent.db` carries provider credentials** — see the warning under "Auth".
  The `.db` files themselves look empty (4 KB) because the real content sits in
  the `-wal` sidecars, which are staged alongside them.
- **`sessions/`, `terminal-sessions/` and `history.db` are staged**, so host
  conversation content is baked into the image. `run.ps1` masks
  `/root/.omp/agent/sessions` with a per-project volume at runtime, but the
  baked copy is still in the image layers.
- **`mcp.json` is baked unchanged**, so any host `C:\Users\...` server path in
  it — such as the one for `context-mode` — does not resolve in the container
  and that server fails to start.

## Notes

- **Base image is not pinned by default.** `-OMPPin` is empty out of the box, so
  a rebuild on a different day can produce a different agent. Everything this
  suite installs on top (`codegraph`, `agent-browser`, `playwright`, Go, .NET)
  is pinned via `ARG`; `pnpm@latest` and the apt-sourced Python/.NET packages
  float.
- **The image runs as root.** The agent's home is `/root`, and the Dockerfile
  never switches to a non-root user the way `claude/`/`codex/`/`opencode/`/
  `cursor/` do. rm-guard's one piece of tamper-resistance (an agent cannot
  re-point `rm` back at `rm.real`) assumes `/usr/bin` is root-owned and the
  agent is not, which does not hold here.
- `.dockerignore` excludes `*.tar`, `pi-custom`, `*-custom`, editor noise and
  `.git/`. An image export written into this directory under any other name
  (`build.ps1 -Tar <name>`), and the `.codegraph/` daemon state, are **not**
  excluded — either can make the build context enormous.
- `run.ps1` mounts the pnpm-store volume but does not perform the store
  relocation (`pnpm config set store-dir`) that `claude/`/`opencode/` do.
- **`build.ps1 -HostPiDir` does not work.** It forwards a `-HostPiDir` argument
  to `prepare.ps1`, whose parameter is `-HostOMPDir` (default
  `%USERPROFILE%\.omp`), so any non-default value throws. Invoke `prepare.ps1`
  directly if you need a non-default host dir.
- [`../.projex/`](../.projex) carries this repo's project documents — plans,
  evaluations and audits at the top level, finished work under
  [`closed/`](../.projex/closed).
