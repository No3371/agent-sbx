# Run the baked codex-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `codex` interactively. No host auth.json bind-mount: a partially-written
# auth.json (e.g. a `{}` placeholder, or a file whose device-auth tokens
# lack a ChatGPT plan type) makes `codex login status` report success while
# the TUI's `account/read` bootstrap still hard-errors ("plan type is
# required for chatgpt authentication"). Since device-auth login is required
# either way, just do it fresh each run inside the ephemeral container. See
# .projex eval 2607060232.

[CmdletBinding()]
param(
    [string]$Image     = 'codex-custom:v1',
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

# node_modules boundary: a host (Windows) node_modules bind-mounted into the
# Linux container carries win32-native bundler binaries (rollup/esbuild/
# rolldown) that crash here. Only when the host actually has a node_modules do
# we mask it with a per-project NAMED volume (empty on first run) and install
# Linux-native deps from empty inside the container — mirroring the plugin
# reinstall precedent in this Dockerfile. A fresh named volume mounts root:root
# while we run as agent, so chown it unconditionally (every run, in case the
# volume was recreated) before the empty-check. Absent -> plain bind-mount,
# unchanged. pnpm not baked here -> pnpm projects belong in the claude image
# (the pnpm branch errors visibly; documented caveat).
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
$nmInstall = ""
if ($maskNodeModules) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash  = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "nmvol-$hash"
    $nmInstall = "sudo chown agent:agent /workspace/node_modules; if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then corepack pnpm install || pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi; "
}

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', 'pm-cache:/home/agent/.npm'
)
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
if ($tz) { $runArgs += @('-e', "TZ=$tz") }

# codegraph install wires the MCP server into ~/.codex/config.toml; codegraph
# init builds the /workspace graph on first run (guarded by .codegraph/ so it
# doesn't re-index every launch — auto-sync keeps it fresh after that).
# `;` not `&&`: a codegraph hiccup (e.g. no network) must not block codex.
#
# --device-auth (URL + one-time code) instead of the default browser flow,
# which starts a callback server on localhost:1455 inside the container that
# the host browser can't reach without publishing that port.
$bootstrap = $nmInstall +
             "codegraph install --yes --target=codex --location=global; " +
             "test -d .codegraph || codegraph init; " +
             "codex login --device-auth; exec codex --dangerously-bypass-approvals-and-sandbox"
$runArgs += @($Image, 'sh', '-lc', $bootstrap)

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
