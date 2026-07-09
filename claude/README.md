# Custom Claude Code sandbox template

Extends `docker/sandbox-templates:claude-code` with:

- **Node 24 LTS** + **pnpm** via corepack
- **.NET SDK 10**
- Host `~/.claude/{settings.json, skills, agents, tools, commands, hooks}` mapped into the sandbox (Win paths rewritten to Linux equivalents)

sbx manages OAuth + `~/.claude.json` (sessions, history, plugins, projects) — none of that is baked here.

## Prerequisites

- **Windows** — build scripts are PowerShell 5.1; Linux/Mac not yet supported
- **PowerShell 5.1** — `pwsh` (PowerShell Core 7.x) has known encoding differences; use Windows PowerShell
- **docker** (or podman) — this template's default workflow is non-sbx + Docker; pass `-Engine podman` to use podman instead

## Build

Default path is non-sbx: `Dockerfile.slim` (Node slim base, no sbx dependency) built and loaded straight into Docker.

```powershell
./prepare.ps1                                                # stage host .claude payload
./build.ps1 -Image cc-custom:v1 -Tar ./cc-custom -Engine docker -LoadToDocker
```

`build.ps1` defaults to `-Dockerfile Dockerfile.slim`. The original `Dockerfile` (full `docker/sandbox-templates:claude-code`
base, for sbx use) is still there — pass `-Dockerfile Dockerfile` to build that one instead:

```powershell
./build.ps1 -Image docker.io/<user>/cc-custom:v1 -Dockerfile Dockerfile -Push   # sbx variant, podman build + push
```

## Run

Without sbx (Win10) — from any project directory:

```powershell
# image must already be in the engine's local store (build.ps1, or `docker load <tar>`)
<repo>\claude\run.ps1 -Image cc-custom:v1 -Engine docker
```

Mounts the current directory as `/workspace` and launches `claude` interactively.
The wrapper bind-mounts host OAuth from `%USERPROFILE%\.claude\.credentials.json`
so the container uses the same subscription-backed account as host Claude Code.
Run `/login` on the host first if that file does not exist. Project/session
metadata persists via `%USERPROFILE%\.claude.json`.

Conversation history (session transcripts + auto memory) persists in the
project itself: `run.ps1` bind-mounts `<workspace>\.claude\projects` onto
`/home/agent/.claude/projects` in the container, so history travels with the
project instead of living only in the host's global `~/.claude`.

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

Legacy sbx path (requires sbx + Win11):

```powershell
sbx run --template docker.io/<user>/cc-custom:v1 claude
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
- **pnpm** — supported via corepack. Its store is relocated out of the workspace
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
custom_sbx/
├── Dockerfile.slim                   # default: non-sbx, Node slim base
├── Dockerfile                        # legacy: sbx, docker/sandbox-templates base
├── prepare.ps1                       # stages + rewrites host config
├── build.ps1                         # docker/podman build + push
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
- Base image tag (`docker/sandbox-templates:claude-code`) is floating — rebuilds on
  different dates may pull a different base. Pin to a digest for fully reproducible
  builds.
