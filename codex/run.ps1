# Run the baked codex-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `codex` interactively. Persists OAuth by bind-mounting the single host
# auth file (NOT the whole ~/.codex dir, which would shadow the baked
# config.toml / skills / vendor_imports).
#
# First run: authenticate once inside the container; the token lands in the
# mounted auth.json on the host and persists. See .projex eval 2607060232.
#
# SECURITY: .codex-docker/auth.json carries a live OAuth token once
# populated. Treat it like an SSH key — never commit, never share the
# .codex-docker directory (any other process/container reading
# %USERPROFILE% can read the plaintext token).

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

# Host-side persisted auth, bind-mounted as a single file so the baked
# ~/.codex contents are not shadowed.
$codexDir  = Join-Path $env:USERPROFILE '.codex-docker'
$authFile  = Join-Path $codexDir 'auth.json'

# BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a UTF-8 BOM,
# which can make a strict JSON parser choke on `{}` before the first real
# write.
if (-not (Test-Path $codexDir))  { New-Item -ItemType Directory -Force $codexDir | Out-Null }
if (-not (Test-Path $authFile))  {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($authFile, '{}', $utf8NoBom)
}

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', ("{0}:/home/agent/.codex/auth.json" -f $authFile)
)
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
$runArgs += @($Image, 'codex')

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
