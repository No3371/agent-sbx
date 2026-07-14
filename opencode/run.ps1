# Run the baked opencode-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `opencode` interactively. Persists auth by bind-mounting the single host
# auth file (NOT the whole ~/.local/share/opencode dir, which would shadow
# the container's own state dirs).
#
# First run: authenticate once inside the container (`opencode auth login`);
# the token lands in the native host auth.json and persists. The native state
# directory is also mounted, so the selected model/variant follows into it.
#
# Persists across --rm: provider auth + model preferences (host
# ~/.local/share/opencode/auth.json + ~/.local/state/opencode), session history
# (project-local .opencode/opencode.db, opencode's SQLite store),
# and package-manager / opencode plugin caches (named volumes). When the host
# workspace has a node_modules, it is masked with a per-project named volume and
# Linux-native deps are reinstalled inside (host node_modules left untouched).
#
# SECURITY: .local/share/opencode/auth.json carries live provider credentials.
# Treat it like an SSH key — never commit or share it (any other
# process/container reading %USERPROFILE% can read the plaintext token). The project-local
# .opencode/opencode.db can hold conversation content — add `.opencode/` to the
# project's .gitignore if reusing this launcher outside this repo.

[CmdletBinding()]
param(
    [string]$Image     = 'opencode-custom:v1',
    [string]$Engine    = 'docker',
    [string]$Workspace = $PWD.Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command $Engine -ErrorAction SilentlyContinue)) {
    throw "$Engine not found on PATH"
}

# Host timezone -> container TZ, so logs/timestamps match the developer's
# clock instead of defaulting to UTC. TimeZoneInfo.Local.Id is already an IANA
# name on non-Windows PowerShell; TryConvertWindowsIdToIanaId (.NET 6+, i.e.
# pwsh 7+) converts Windows-style ids. ponytail: no conversion path on Windows
# PowerShell 5.1 (.NET Framework lacks that method) — falls back to $null and
# the container just keeps defaulting to UTC as it did before this change.
$tz = $null
try {
    $localId = [System.TimeZoneInfo]::Local.Id
    if ((Test-Path variable:IsWindows) -and -not $IsWindows) {
        # PS Core on Linux/macOS: Local.Id is already an IANA name.
        $tz = $localId
    } elseif ([System.TimeZoneInfo].GetMethod('TryConvertWindowsIdToIanaId')) {
        # Windows (PS Core 7+, .NET 6+): convert the Windows id to IANA.
        $iana = $null
        if ([System.TimeZoneInfo]::TryConvertWindowsIdToIanaId($localId, [ref]$iana)) { $tz = $iana }
    }
    # else: Windows PowerShell 5.1 — .NET Framework has no IANA conversion,
    # $tz stays $null and the container keeps defaulting to UTC as before.
} catch { }

# Map OpenCode's native host state: auth lives in data, while the selected
# model/variant lives in state/model.json. Keep auth as a file mount so the
# project-local session DB can remain separate.
$dataDir  = Join-Path $env:USERPROFILE '.local\share\opencode'
$authFile = Join-Path $dataDir 'auth.json'
$stateDir = Join-Path $env:USERPROFILE '.local\state\opencode'

# BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a UTF-8 BOM,
# which can make a strict JSON parser choke on `{}` before the first real
# write.
if (-not (Test-Path $dataDir))  { New-Item -ItemType Directory -Force $dataDir | Out-Null }
if (-not (Test-Path $authFile)) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($authFile, '{}', $utf8NoBom)
}
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force $stateDir | Out-Null }

# Project-local session history. opencode 1.17 stores all sessions in a single
# SQLite DB at ~/.local/share/opencode/opencode.db (verified against opencode
# 1.17.14 — NOT a per-project storage/ dir; the plan's assumption 4 was wrong).
# Bind-mount just that DB file (individual-path, like auth.json — never the
# whole share dir, which would shadow baked state and collide with the auth
# file-mount) into the project's .opencode/ so history travels with the project
# and survives --rm. A 0-byte file is a valid empty SQLite DB. The -wal/-shm
# sidecars live in the container and checkpoint into the .db on clean exit; a
# hard kill can lose the most recent uncommitted turn.
$historyDb     = Join-Path $Workspace '.opencode\opencode.db'
$historyParent = Split-Path $historyDb -Parent
if (-not (Test-Path $historyParent)) { New-Item -ItemType Directory -Force $historyParent | Out-Null }
if (-not (Test-Path $historyDb))     { [System.IO.File]::WriteAllBytes($historyDb, @()) }

# Shared package-manager + opencode plugin caches (named volumes, per-suite).
# Namespaced with an `opencode-` prefix so this Alpine/musl store never shares a
# volume with the claude template's Debian/glibc store for the same name
# (redteam F4). Fresh named volumes mount root:root; chown every one the non-root
# agent writes to — npm cache (~/.npm), pnpm store, opencode's Bun plugin cache
# (~/.cache/opencode) — each launch (redteam F5). Unlike claude, this image does
# not pre-warm ~/.npm, so a fresh opencode-pm-cache volume is root:root and npm
# install fails without this chown. pnpm otherwise defaults its store into
# /workspace, so relocate it to the HOME volume. corepack/pnpm baked in (Step 2).
# `/home/agent/.cache` itself is also chowned: nothing creates that directory at
# build time, so mounting a volume onto the nested `.cache/opencode` path makes
# Docker auto-create the missing parent as root:root before the container starts
# (a Docker mount-point quirk, independent of the image's own user setup — this
# is the only one of the three suites that mounts anything under `.cache/`, so
# it's the only one exposed to it). F5's chown covered the volume leaf but not
# this parent, so corepack (which caches to the sibling `~/.cache/node/corepack`
# on first pnpm-version fetch) hit EACCES trying to `mkdir` under the root-owned
# parent. Chowning the parent (non-recursive — the leaf keeps its own chown) is
# enough: agent can then create any sibling under `.cache` itself.
$pmSetup = "sudo chown agent:agent /home/agent/.cache /home/agent/.npm /home/agent/.pnpm-store /home/agent/.cache/opencode 2>/dev/null; corepack pnpm config set store-dir /home/agent/.pnpm-store 2>/dev/null || true;"

# node_modules boundary: a host (Windows) node_modules bind-mounted into the
# Linux container carries win32-native binaries that crash here. Only when the
# host actually has one do we mask it with a per-project NAMED volume (empty on
# first run) and install Linux-native deps inside — namespaced `opencode-nmvol-`
# so it never shares the claude template's musl-vs-glibc volume for the same
# workspace (redteam F4). A fresh named volume mounts root:root while we run as
# agent, so chown it before the empty-check. Absent -> plain bind-mount.
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
$nmInstall = ""
if ($maskNodeModules) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash  = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "opencode-nmvol-$hash"
    $nmInstall = "sudo chown agent:agent /workspace/node_modules; if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then corepack pnpm install || pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi;"
}

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', ("{0}:/home/agent/.local/share/opencode/auth.json" -f $authFile),
    '-v', ("{0}:/home/agent/.local/state/opencode" -f $stateDir),
    '-v', ("{0}:/home/agent/.local/share/opencode/opencode.db" -f $historyDb),
    '-v', 'opencode-cache:/home/agent/.cache/opencode',
    '-v', 'opencode-pm-cache:/home/agent/.npm',
    '-v', 'opencode-pnpm-store-cache:/home/agent/.pnpm-store'
)
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
if ($tz) { $runArgs += @('-e', "TZ=$tz") }

# codegraph install wires the MCP server into opencode's config; codegraph
# init builds the /workspace graph on first run (guarded by .codegraph/ so it
# doesn't re-index every launch — auto-sync keeps it fresh after that).
# `;` not `&&`: a codegraph hiccup (e.g. no network) must not block opencode.
$bootstrap = "$pmSetup $nmInstall " +
             "codegraph install --yes --target=opencode --location=global; " +
             "test -d .codegraph || codegraph init; " +
             "exec opencode"
$runArgs += @($Image, 'sh', '-lc', $bootstrap)

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
