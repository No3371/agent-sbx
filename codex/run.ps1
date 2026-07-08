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

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace'
)
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }

# codegraph install wires the MCP server into ~/.codex/config.toml; codegraph
# init builds the /workspace graph on first run (guarded by .codegraph/ so it
# doesn't re-index every launch — auto-sync keeps it fresh after that).
# `;` not `&&`: a codegraph hiccup (e.g. no network) must not block codex.
#
# --device-auth (URL + one-time code) instead of the default browser flow,
# which starts a callback server on localhost:1455 inside the container that
# the host browser can't reach without publishing that port.
$bootstrap = "codegraph install --yes --target=codex --location=global; " +
             "test -d .codegraph || codegraph init; " +
             "codex login --device-auth; exec codex --dangerously-bypass-approvals-and-sandbox"
$runArgs += @($Image, 'sh', '-lc', $bootstrap)

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
