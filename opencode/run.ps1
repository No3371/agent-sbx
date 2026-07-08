# Run the baked opencode-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `opencode` interactively. Persists auth by bind-mounting the single host
# auth file (NOT the whole ~/.local/share/opencode dir, which would shadow
# the container's own state dirs).
#
# First run: authenticate once inside the container (`opencode auth login`);
# the token lands in the mounted auth.json on the host and persists.
#
# SECURITY: .opencode-docker/auth.json carries live provider credentials once
# populated. Treat it like an SSH key — never commit, never share the
# .opencode-docker directory (any other process/container reading
# %USERPROFILE% can read the plaintext token).

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

# Host-side persisted auth, bind-mounted as a single file so the container's
# own ~/.local/share/opencode contents are not shadowed.
$ocDir    = Join-Path $env:USERPROFILE '.opencode-docker'
$authFile = Join-Path $ocDir 'auth.json'

# BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a UTF-8 BOM,
# which can make a strict JSON parser choke on `{}` before the first real
# write.
if (-not (Test-Path $ocDir))    { New-Item -ItemType Directory -Force $ocDir | Out-Null }
if (-not (Test-Path $authFile)) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($authFile, '{}', $utf8NoBom)
}

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', ("{0}:/home/agent/.local/share/opencode/auth.json" -f $authFile)
)
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }

# codegraph install wires the MCP server into opencode's config; codegraph
# init builds the /workspace graph on first run (guarded by .codegraph/ so it
# doesn't re-index every launch — auto-sync keeps it fresh after that).
# `;` not `&&`: a codegraph hiccup (e.g. no network) must not block opencode.
$bootstrap = "codegraph install --yes --target=opencode --location=global; " +
             "test -d .codegraph || codegraph init; " +
             "exec opencode"
$runArgs += @($Image, 'sh', '-lc', $bootstrap)

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
