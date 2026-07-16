# Run the baked cursor-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `agent` (Cursor CLI) interactively.
#
# No host credential bind-mount: cursor-agent's on-disk auth storage location
# isn't documented upstream (unlike opencode's clearly-documented
# ~/.local/share/opencode/auth.json), and guessing wrong here risks the same
# partial-write footgun codex/run.ps1 hit and deliberately avoided (see its
# header comment + .projex eval 2607060232). So auth is handled fresh per run:
#   - CURSOR_API_KEY set on the host -> passed through, no login step at all
#     (this is Cursor's own documented headless/CI auth path)
#   - otherwise -> `NO_OPEN_BROWSER=1 agent login` runs inside the container,
#     printing a URL to complete browser auth on the host manually each launch
#
# Session history / prefs are NOT persisted across --rm by this launcher
# (nothing host-side to bind-mount for them is documented either). Only the
# npm cache is a named volume, since npm is the one shared, well-understood
# piece of persistent state here.

[CmdletBinding()]
param(
    [string]$Image     = 'cursor-custom:v1',
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
# pwsh 7+) converts Windows-style ids. No conversion path on Windows
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

# node_modules boundary: a host (Windows) node_modules bind-mounted into the
# Linux container carries win32-native bundler binaries (rollup/esbuild/
# rolldown) that crash here. Only when the host actually has one do we mask it
# with a per-project NAMED volume (empty on first run) and install
# Linux-native deps inside — namespaced `cursor-nmvol-` so it never shares the
# claude/opencode/codex templates' volume for the same workspace (per-suite
# isolation). A fresh named volume mounts root:root while we run as agent, so
# chown it before the empty-check. Absent -> plain bind-mount.
# pnpm not baked here (mirrors codex/, not opencode/) -> pnpm projects belong
# in the claude/opencode images (the pnpm branch errors visibly; documented caveat).
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
$nmInstall = ""
if ($maskNodeModules) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash  = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "cursor-nmvol-$hash"
    $nmInstall = "sudo chown agent:agent /workspace/node_modules; if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then corepack pnpm install || pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi; "
}

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', 'cursor-pm-cache:/home/agent/.npm'
)
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
if ($tz) { $runArgs += @('-e', "TZ=$tz") }

# Pass the host's CURSOR_API_KEY through untouched if set — Cursor's own
# documented headless/CI auth path (see README "Auth"). Never bake a value
# into the image; only forwarded at `docker run` time.
$hasApiKey = -not [string]::IsNullOrEmpty($env:CURSOR_API_KEY)
if ($hasApiKey) { $runArgs += @('-e', "CURSOR_API_KEY=$($env:CURSOR_API_KEY)") }

# codegraph install wires the MCP server into ~/.cursor/mcp.json; codegraph
# init builds the /workspace graph on first run (guarded by .codegraph/ so it
# doesn't re-index every launch — auto-sync keeps it fresh after that).
# `;` not `&&`: a codegraph hiccup (e.g. no network) must not block agent.
#
# Auth: skip `agent login` entirely when CURSOR_API_KEY is present (the CLI
# picks it up on its own); otherwise log in fresh each run with
# NO_OPEN_BROWSER=1 so it prints a URL instead of trying to open a browser
# that doesn't exist inside the container.
$loginStep = if ($hasApiKey) { "echo '[run] CURSOR_API_KEY set — skipping agent login'; " } else { "NO_OPEN_BROWSER=1 agent login; " }
$bootstrap = $nmInstall +
             "codegraph install --yes --target=cursor --location=global; " +
             "test -d .codegraph || codegraph init; " +
             $loginStep +
             "exec agent"
$runArgs += @($Image, 'sh', '-lc', $bootstrap)

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
