# Custom Pi sandbox template

Built on `debian:bookworm-slim` (glibc); [Pi](https://pi.dev) (binary name `pi`,
npm package `@earendil-works/pi-coding-agent`) is a multi-provider, TUI coding-agent
CLI installed at build time via:

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

Unlike `cursor-agent`, pi **is** a Node program — Node isn't just a shared-tooling
dependency here, it's pi's own runtime (`engines.node: ">=22.19.0"`, satisfied by
NodeSource Node 25). Adds:

- **git, bash, curl, jq, ripgrep, openssh-client, sudo, tini** — the baseline a
  coding agent needs (ripgrep is included because upstream pi's own reference
  `Dockerfile.pi` installs it alongside git/bash/ca-certificates)
- A non-root **agent** user (uid 1000), matching the
  `claude/`/`opencode/`/`cursor/`/`codex/` templates
- Host `~/.pi/agent` (`settings.json`, `AGENTS.md`/`SYSTEM.md`, `extensions/`,
  `skills/`, `themes/`, `prompts/`) copied in by `prepare.ps1` with a filtered
  recursive copy — **no path rewriting needed at all**, unlike opencode/cursor,
  because pi has no MCP config to rewrite (see "No MCP" below)
- **Node 25** (NodeSource) + npm — pi's own runtime, also drives the
  `run.ps1` node_modules reinstall
- **codegraph**, **agent-browser** (browser automation; its Chrome-for-Testing
  browser is baked at build time via `agent-browser install --with-deps`), and
  optional **Go / Python** toolchains

No `docker/sandbox-templates:pi` base exists, so like `opencode/`/`cursor/` (and
unlike `claude/`/`codex/`) there's no sbx integration here — this is the
plain-docker path only, run via `run.ps1`. No credentials are baked into the
image; see "Auth" below for how `run.ps1` handles login.

## Install audit

`@earendil-works/pi-coding-agent` was run through this repo's install-auditor
before being added — **APPROVED**, pinned to `0.80.9` (condition: `>=0.78.1`; four
GHSA advisories exist against earlier versions, all fixed by 0.78.1/0.79.0, all
predating this pin). See
[`.projex/2607171400-pi-coding-agent-install-audit.md`](../.projex/2607171400-pi-coding-agent-install-audit.md).

## No MCP

Pi deliberately ships no MCP client (from pi's own README: *"No MCP. Build CLI
tools with READMEs, or build an extension that adds MCP support."*). Two
consequences for this image:

- **No config rewrite in `prepare.ps1`.** opencode's `opencode.json` and
  Cursor's `mcp.json` both need Windows-path rewriting for local MCP server
  `command` values; pi has no equivalent file, so `prepare.ps1` here is a plain
  filtered copy.
- **codegraph is wired up as a skill, not an MCP server.** codegraph's own
  installer (`codegraph install --target=...`) doesn't support `pi` as a target
  anyway (its supported list is Claude Code, Cursor, Codex CLI, opencode,
  Hermes Agent, Gemini CLI, Antigravity IDE, Kiro) — so this image bakes the
  `codegraph` CLI plus a discovery-stub skill
  (`~/.pi/agent/skills/codegraph/SKILL.md`) documenting the plain-CLI commands
  (`codegraph explore`, `query`, `node`, `callers`, `callees`, `impact`,
  `affected`) instead. `run.ps1` still runs `codegraph init` on first launch so
  the graph exists for those commands to query.

## Prerequisites

- **Windows** — build scripts are PowerShell 5.1; Linux/Mac not yet supported
- **PowerShell 5.1** — `pwsh` (PowerShell Core 7.x) has known encoding differences; use Windows PowerShell
- **podman** (or docker) — pass `-Engine docker` to use Docker instead

## Build

```powershell
./prepare.ps1                                            # stage host ~/.pi/agent
./build.ps1 -Image docker.io/<user>/pi-custom:v1 -Push   # podman build + push
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
./build.ps1 -Image pi-custom:v1 -Engine docker              # both on (default)
./build.ps1 -Image pi-custom:v1 -Disable python -Engine docker  # go only
./build.ps1 -Image pi-custom:v1 -Enable go -Engine docker       # go only (explicit)
```

`-Enable`/`-Disable` are mutually exclusive; an unknown selector is rejected.
`node` is **not** a toggle — it's pi's own runtime as well as a baseline
dependency for codegraph/agent-browser/playwright. No `pnpm` is baked in here
(mirrors `cursor/`/`codex/`, not `opencode/`) — run pnpm-lockfile projects in
the `claude`/`opencode` images.

### agent-browser and codegraph

Both are baked from npm as plain CLI tools (see "No MCP" above for why neither
is wired in as an MCP server here). `agent-browser`'s **Chrome for Testing**
browser is installed at build time via `agent-browser install --with-deps` — so
no runtime browser download is needed. Discovery-stub skills ship at
`~/.pi/agent/skills/agent-browser/SKILL.md` and
`~/.pi/agent/skills/codegraph/SKILL.md` (Agent Skills standard, pi's global
skill directory); the agent-browser CLI serves its own up-to-date usage docs
via `agent-browser skills get core`.

## Run

From any project directory:

```powershell
# image must already be in the engine's local store (build.ps1, or `docker load <tar>`)
<repo>\pi\run.ps1 -Image pi-custom:v1 -Engine docker
```

Mounts the current directory as `/workspace` and launches `pi` interactively.

### Auth

Pi's on-disk credential store is well-documented (`~/.pi/agent/auth.json`,
created with `0600` permissions) — unlike Cursor CLI's undocumented storage, so
this launcher follows opencode's precedent rather than codex's/cursor's
fresh-login-per-run approach:

- **`run.ps1` bind-mounts the single host `~/.pi/agent/auth.json` file** (not
  the whole `~/.pi/agent` dir, which would shadow the image's baked
  settings/extensions/skills). First run: use `/login` in interactive mode
  (subscription OAuth) or set a provider API key — either way the credential
  lands in the mounted file and persists across `--rm`.
- **Provider API key env vars set on the host are forwarded automatically** —
  `run.ps1` checks the full list from pi's `docs/providers.md` (Anthropic,
  OpenAI, Bedrock, Azure OpenAI, Cloudflare, OpenRouter, xAI, and the rest of
  the built-in catalog) and passes through whichever are set, e.g.:

  ```powershell
  $env:ANTHROPIC_API_KEY = 'sk-ant-...'
  <repo>\pi\run.ps1 -Image pi-custom:v1 -Engine docker
  ```

  `GOOGLE_APPLICATION_CREDENTIALS` is deliberately **not** forwarded — it
  points at a host file path that doesn't exist in the container; use
  `gcloud auth application-default login` inside the container instead, or
  bind-mount the key file yourself.

**Persistent state across `--rm`:**

- **Auth** — host `~/.pi/agent/auth.json`, as above.
- **Session history** — pi stores sessions under `~/.pi/agent/sessions/`,
  organized by working directory. Because the container's cwd is always
  `/workspace` no matter which host project is mounted, a single shared volume
  would mix every project's history together — so `run.ps1` uses a
  **per-project named volume** (`pi-sessions-<hash-of-workspace-path>`)
  instead, the same hashing technique used for `node_modules` masking below.
- **npm cache** — `pi-pm-cache` named volume (`~/.npm`).
- **Not persisted:** `trust.json` (project-trust decisions) and
  `models-store.json` (a refreshable model-catalog cache) — both regenerate
  cheaply; a fresh container just re-asks the project-trust prompt once and
  re-fetches model catalogs on demand.

**`node_modules` masking:** if the host workspace has a `node_modules`, it is
masked with a per-project named volume (`pi-nmvol-<hash>`) and Linux-native
deps are reinstalled inside the container (`npm`/`yarn` per lockfile; a
`pnpm-lock.yaml` project errors visibly — no pnpm baked in here). The host's
`node_modules` (with its win32-native binaries) is left untouched.

**Security:** `~/.pi/agent/auth.json` carries live provider credentials (API
keys and/or OAuth tokens). Treat it like an SSH key — never commit or share it.

Use from any project dir without retyping the repo path — add to your
PowerShell profile (`$PROFILE`):

```powershell
function pirun { & "<repo-path>\pi\run.ps1" @args }
```

Then just run `pirun` from any project directory.

## Layout

```
pi/
├── Dockerfile
├── prepare.ps1                       # stages host ~/.pi/agent (filtered copy, no rewrite needed)
├── build.ps1
├── run.ps1
├── retag-tar.ps1
├── .dockerignore
├── skills/
│   ├── agent-browser/SKILL.md        # repo-owned discovery stub, baked into image
│   └── codegraph/SKILL.md            # repo-owned discovery stub (no MCP -> plain CLI skill)
└── context/
    └── .pi/agent/                    # generated by prepare.ps1
```

## What `prepare.ps1` excludes (never staged)

- `auth.json`, `trust.json`, `models-store.json` — credentials, host-specific
  project-trust decisions, and a refreshable model-catalog cache; `auth.json`
  is bind-mounted at runtime instead (see "Auth" above), the other two just
  regenerate inside the container
- `sessions/` — session history; bind-mounted per-project at runtime instead
  (see "Persistent state" above) so a baked copy doesn't freeze host history
  into every image
- `git/`, `npm/` — pi's own installed-package directories (from `pi install`);
  host-built, may carry native binaries that won't load in the Linux
  container, and trivially reinstalled with `pi install` if needed
- `tmp/` — pi's scratch directory for temporary extension installs; ephemeral
- `.git/`, `.github/`, `node_modules/` dirs anywhere in the tree (e.g. vendored
  extension/skill repos)
- Files matching known credential patterns (`*.key`, `*.pem`, `*.token`,
  `*.credentials`, `secrets.json`, `*.p12`, `*.pfx`, `token.json`, `auth.json`)
  — defense in depth

Everything else (`settings.json`, `AGENTS.md`/`SYSTEM.md`/`APPEND_SYSTEM.md`,
`extensions/`, `skills/`, `themes/`, `prompts/`, ...) is copied through
unchanged — no rewriting, since there's no MCP config or host-path-bearing
schema in any of these files.

## Notes

- Base is an official **named** tag (`debian:bookworm-slim`), not
  digest-pinned — it's still a rolling tag, so a rebuild on a different date
  can pull a different patch level. Same honest caveat as `opencode/`/`cursor/`.
- **`pi` is pinned** (`PI_VERSION` build arg, default `0.80.9`) per the install
  audit above — re-audit on a future major/minor bump, same policy already
  applied to `codegraph`/`opencode-ai` in this repo.
- Pi self-updates by default (`pi update --self`) once running, and checks
  `pi.dev` for a newer version on startup unless disabled
  (`PI_SKIP_VERSION_CHECK=1` / `--offline` / `PI_OFFLINE=1`, all forwarded by
  `run.ps1` if set on the host) — the baked binary in the image stays at the
  pinned version regardless of what a running container checks for.
- `$Destination` is recreated clean on each `prepare.ps1` run — there is no incremental staging.
