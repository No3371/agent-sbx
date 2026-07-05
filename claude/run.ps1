# Run the baked cc-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `claude` interactively. Persists OAuth + session state across runs by
# bind-mounting individual host files (NOT the whole ~/.claude dir, which
# would shadow the image's baked skills/agents/settings).
#
# First run: inside the container run `/login` once. The OAuth token is
# written to the mounted credentials file on the host and persists to
# future runs. See .projex eval 2607060232 for the rationale.
#
# SECURITY: ~/.claude.json and .claude-docker/.credentials.json carry live
# OAuth/session tokens once populated. Treat them like SSH keys — never
# commit, never share the .claude-docker directory (any other process/
# container reading %USERPROFILE% can read the plaintext token).

[CmdletBinding()]
param(
    [string]$Image     = 'cc-custom:v1',
    [string]$Engine    = 'docker',
    [string]$Workspace = $PWD.Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command $Engine -ErrorAction SilentlyContinue)) {
    throw "$Engine not found on PATH"
}

# Host-side persisted state. Bind-mounted as individual files so sibling
# baked files under /home/agent/.claude are NOT shadowed.
$claudeJson  = Join-Path $env:USERPROFILE '.claude.json'
$credsDir    = Join-Path $env:USERPROFILE '.claude-docker'
$credsFile   = Join-Path $credsDir '.credentials.json'

# Pre-create the host files so the engine bind-mounts them as files, not as
# freshly-created empty directories (Docker creates a dir if the source path
# is absent). BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a
# UTF-8 BOM, which can make a strict JSON parser choke on `{}` before the
# first real write.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
if (-not (Test-Path $claudeJson)) { [System.IO.File]::WriteAllText($claudeJson, '{}', $utf8NoBom) }
if (-not (Test-Path $credsDir))   { New-Item -ItemType Directory -Force $credsDir | Out-Null }
if (-not (Test-Path $credsFile))  { [System.IO.File]::WriteAllText($credsFile, '{}', $utf8NoBom) }

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', ("{0}:/home/agent/.claude.json" -f $claudeJson),
    '-v', ("{0}:/home/agent/.claude/.credentials.json" -f $credsFile)
)
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
$runArgs += @($Image, 'claude')

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
