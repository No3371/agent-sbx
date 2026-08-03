# Custom Claude Code sandbox template

Builds a self-contained Claude Code image from official `node:25-bookworm-slim` with:

- **Claude Code**, **Node 25**, **pnpm**, **CodeGraph**, **agent-browser**, and **Playwright + Chromium**
- Optional **.NET SDK 10**, **Go**, and **Python 3**
- Host `~/.claude/{settings.json, skills, agents, tools, commands, hooks}` staged with Windows paths rewritten to Linux equivalents
- In-repo `rm-guard` accident protection for `/workspace/.git`; this is not a security boundary because `agent` retains passwordless sudo

OAuth is bind-mounted by `run.ps1`; credentials, sessions, and history are not baked into the image.

## Prerequisites

- **Windows** — build scripts are PowerShell 5.1; Linux/Mac not yet supported
- **PowerShell 5.1** — `pwsh` (PowerShell Core 7.x) has known encoding differences; use Windows PowerShell
- **docker** (or podman) — default workflow uses Docker directly; pass `-Engine podman` to use Podman instead

## Build

The canonical `Dockerfile` builds directly from the official Node slim base:

```powershell
./prepare.ps1                                                # stage host .claude payload
./build.ps1 -Image cc-custom:v1 -Tar ./cc-custom -Engine docker -LoadToDocker
```

`build.ps1` uses `Dockerfile` by default; no `-Dockerfile` override is required.

### Claude Code freshness

Claude Code is installed unpinned and re-resolved on every canonical `Dockerfile` build:
`build.ps1` feeds `--build-arg CLAUDE_CODE_CACHEBUST=<epoch>` so the layer cannot
go stale. Without it, `npm install -g @anthropic-ai/claude-code` resolves "latest"
the first time the layer is built and then hits the Docker cache indefinitely —
the image silently keeps shipping whatever version was current that day.

That layer sits after the agent-browser and Playwright browser downloads, so
re-resolving costs one npm install rather than a Chrome/Chromium re-download.

```powershell
./build.ps1 -Image cc-custom:v1 -CachedClaude    # reuse the cached layer, faster rebuild
```


### Optional language features

Claude selects `go`, `dotnet`, and `python`; all three are installed by default.
Use exactly one selector: `-Enable` is a whitelist and `-Disable` is a blacklist.
Names are case-insensitive; blank, unknown, or duplicate names fail before preparation or build.

```powershell
./build.ps1 -Image claude-custom:go -Enable go
./build.ps1 -Image claude-custom:no-dotnet -Disable dotnet
```

Node, pnpm, CodeGraph, agent-browser, compilers, and system tools are shared
requirements and cannot be selected.

## Run

Direct Docker/Podman launch (Windows 10+) — from any project directory:

```powershell
# image must already be in the engine's local store (build.ps1, or `docker load <tar>`)
<repo>\claude\run.ps1 -Image cc-custom:v1 -Engine docker
```

Mounts the current directory as `/workspace` and launches `claude` interactively.

The wrapper bind-mounts host OAuth from `%USERPROFILE%\.claude\.credentials.json`
read-write, so the container uses the same subscription-backed account as host
Claude Code *and* can refresh the token in place during a long session. Run
`/login` on the host first if that file does not exist.

`~/.claude.json` is **not** shared — the container gets a per-run throwaway copy
seeded with just the OAuth identity and MCP servers, so it cannot overwrite the
host's trusted-repo registry. Avoid leaving host Claude Code running beside a
long container session: refresh tokens are single-use, so whichever instance
refreshes first leaves the other needing `/login`.

Conversation history (session transcripts + auto memory) persists in the
project itself: `run.ps1` bind-mounts `<workspace>\.claude\projects` onto
`/home/agent/.claude/projects` in the container, so history travels with the
project instead of living only in the host's global `~/.claude`.

### GPU

Pass `-GPU` to expose all host GPUs to the container (`--gpus all`). Docker or
Podman must already have its GPU runtime configured.

**Security:** `.claude.json`, `.claude\.credentials.json`, and the project's
`.claude\projects\` history folder can carry live OAuth tokens or sensitive
conversation content once populated. Treat them like SSH keys — never commit
or share them.

Use from any project dir without retyping the repo path — add to your
PowerShell profile (`$PROFILE`):

```powershell
function ccrun { & "<repo-path>\claude\run.ps1" @args }
```

Then just run `ccrun` from any project directory.

Background-agent worktree isolation is disabled by default (the launcher merges
`worktree.bgIsolation: "none"` into the container's settings.json at launch).
Pass `-EnableBgIsolation` to retain the baked Claude Code setting instead:

```powershell
ccrun -EnableBgIsolation
```

Default launch is `--permission-mode auto --allow-dangerously-skip-permissions`:
starts in auto mode (classifier reviews Bash/network, file edits auto-approve),
with full bypass added to the Shift+Tab mode cycle so you can toggle into/out
of it mid-session without restarting the container. Pass
`-DangerouslySkipPermissions` to start directly in bypass instead (skips auto
mode from the first prompt) — the container remains the blast-radius boundary
either way:

```powershell
ccrun -DangerouslySkipPermissions
```


## Workspace `node_modules` (Windows host)

If your project already has a `node_modules/` on the host (Windows), `run.ps1`
masks it with a per-project Docker volume and installs Linux-native deps inside
the container on first launch — a Windows `node_modules` carries win32 bundler
binaries (rollup/esbuild/rolldown) that crash on Linux (`You installed esbuild
for another platform`, `binding-*.mjs command failed: vite`).

- **Shared package-manager cache** — the npm cache (`pm-cache` volume) and pnpm
  store (`pnpm-store-cache` volume) are shared across *every* project and
  container of this suite. Only the very first install ever pays real network
  cost; every later project's first install pulls tarballs from the local cache
  volume, so it is fast. `node_modules` looking empty at the very start of the
  first masked run is expected (mask, pre-install).
- **No host `node_modules`?** node_modules behavior is unchanged (deps install
  straight into the bind-mount as before); the shared caches still apply.
- **Per-project volume** — masked deps persist in a named volume
  (`nmvol-<hash>`, keyed by workspace path) across `--rm` runs; the second run
  reuses it with no reinstall.
- **pnpm** — installed globally via npm. Its store is relocated out of the workspace
  (default `/workspace/.pnpm-store` would pollute the host repo) to the shared
  `pnpm-store-cache` volume via `pnpm config set store-dir`.
- **yarn Berry/PnP** — no `node_modules` to mask; masking is a no-op. Run
  `yarn install` inside the container yourself if `.yarn/unplugged` natives break.
- **Monorepos / nested `node_modules`** — only the top-level dir is masked.
  Reinstall per-package inside the container where nested `node_modules` carry
  win32 natives.
- **opencode image** — has no Node toolchain; masking/caching are disabled there.
  Run Node/Vite apps in the claude or codex image.
- **Host IDE** keeps its own host `node_modules` (unaffected by the container's
  volume — they diverge by design).

Prune the volumes if they accumulate: `docker volume ls -q --filter name=nmvol-`
(per-project), plus the shared `pm-cache` / `pnpm-store-cache`.

## Layout

```
claude/
├── Dockerfile                        # canonical self-built Node slim image
├── prepare.ps1                       # stages + rewrites host config
├── build.ps1                         # docker/podman build + export/load
├── .dockerignore
└── context/
    ├── .claude/                      # generated by prepare.ps1
    │   ├── settings.json             # host file w/ Win paths rewritten
    │   ├── skills/ agents/ tools/ commands/ hooks/
    └── scripts/
        └── merge-claude-settings.sh
```

## Path rewriting

`prepare.ps1` rewrites in `settings.json` hook commands:

| From | To |
|---|---|
| `"C:/Program Files/nodejs/node.exe"` | `node` |
| `C:/Users/<anyone>/.claude/...` | `/home/agent/.claude/...` |
| Backslashes | Forward slashes |

It also drops the Windows-only `statusLine` (relies on bash globbing of a `/c/...` plugin dir).

## Notes

- Empty host dirs are staged as empty so the Dockerfile `COPY` shape is stable.
- `.projex/closed/` contains completed project documents (design plans, walkthroughs).
  Active development notes are not committed. See `SECURITY.md` for the responsible
  disclosure path.
- Base image tag (`node:25-bookworm-slim`) is mutable; pin to a digest for fully
  reproducible builds.
