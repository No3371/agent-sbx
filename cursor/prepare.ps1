# Stages host ~/.cursor payload into ./context/.cursor for the build.
#
# Unlike opencode's prepare.ps1 (filtered recursive copy of the whole config
# dir), this uses an ALLOWLIST — the same choice codex/prepare.ps1 made for
# ~/.codex. ~/.cursor is shared with the Cursor *editor*, not CLI-only like
# opencode's ~/.config/opencode, so it is expected to also hold IDE-scale state
# (chat/session databases, extension caches, telemetry/machine IDs, indexes,
# possibly OAuth tokens for MCP servers) that has no business in a baked image
# and that a blanket recursive copy would silently vacuum up. Only two files
# are staged:
#   - cli-config.json  (global CLI prefs: editor/model/display/permissions —
#                        schema has no host-path or credential fields)
#   - mcp.json          (shared with the editor; local server `command` values
#                        rewritten Win → Linux, same rationale as
#                        claude/opencode's mcpServers rewrite)
#
# Cursor CLI's actual auth storage location is not documented upstream, so
# nothing credential-shaped is assumed to live under ~/.cursor and staged by
# name — see run.ps1 for how auth is handled instead (fresh login per
# container run, or CURSOR_API_KEY passthrough).

[CmdletBinding()]
param(
    [string]$HostCursorDir = "$env:USERPROFILE\.cursor",
    [string]$Destination   = (Join-Path $PSScriptRoot 'context\.cursor')
)

$ErrorActionPreference = 'Stop'

$credentialExcludePatterns = @(
    'auth.json', 'token.json', 'secrets.json',
    '*.key', '*.pem', '*.token', '*.credentials',
    '*.p12', '*.pfx'
)

function Test-CredentialFileName([string]$name) {
    foreach ($pat in $credentialExcludePatterns) {
        if ($name -like $pat) { return $true }
    }
    return $false
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
function Write-JsonNoBom([string]$path, $obj) {
    $json = $obj | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($path, $json, $Utf8NoBom)
}

# Recreate $Destination clean on each run so stale entries from a prior layout
# never linger in the build context.
if (Test-Path $Destination) {
    Remove-Item $Destination -Recurse -Force
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

# --- cli-config.json: copied as-is (no host paths / credentials in schema) ---
$cliConfigSrc = Join-Path $HostCursorDir 'cli-config.json'
if (Test-Path $cliConfigSrc) {
    if (Test-CredentialFileName 'cli-config.json') {
        Write-Warning "[prepare] CREDENTIAL RISK: skipping cli-config.json (matches credential pattern?!)"
    } else {
        Copy-Item -LiteralPath $cliConfigSrc -Destination (Join-Path $Destination 'cli-config.json') -Force
        Write-Host "[prepare] staged cli-config.json"
    }
} else {
    Write-Host "[prepare] no cli-config.json on host — skipping"
}

# --- mcp.json: rewrite local `command` (Win path → Linux/bare name) ---
# Same schema Claude Desktop/Code use (mcpServers.<name>.{command,args,env} for
# stdio; {url,headers,auth} for remote) — reuses that rewrite precedent rather
# than opencode.json's array-command variant.
function Rewrite-Command([string]$cmd) {
    if ([string]::IsNullOrEmpty($cmd)) { return $cmd }
    # node.exe (Win path) → node
    $cmd = $cmd -replace '(?i)"?[A-Za-z]:[\\/]Program Files[\\/]nodejs[\\/]node\.exe"?', 'node'
    # node (git-bash / WSL mount path) → node
    $cmd = $cmd -replace '(?i)"?/(?:c|mnt/[a-z])/Program Files/nodejs/node(\.exe)?"?', 'node'
    # host ~/.cursor config dir → container path (in case a server script lives
    # under the config dir itself, mirroring opencode.json's precedent)
    $cmd = $cmd -replace '(?i)^([A-Za-z]):[\\/]Users[\\/][^\\/]+[\\/]\.cursor', '/home/agent/.cursor'
    # normalize backslashes only for things that look like Windows paths
    if ($cmd -match '^[A-Za-z]:[\\/]' -or $cmd -match '\\') { $cmd = $cmd -replace '\\', '/' }
    return $cmd
}

function Rewrite-McpServerCommand([string]$cmd) {
    if ([string]::IsNullOrEmpty($cmd)) { return $cmd }
    $cmd = Rewrite-Command $cmd
    # npx one-off cache shim: .../_npx/<hash>/node_modules/.bin/<name>[.cmd] → <name>
    if ($cmd -match '(?i)[/\\]_npx[/\\][^/\\]+[/\\]node_modules[/\\]\.bin[/\\]([^/\\]+?)(?:\.cmd)?$') {
        return $Matches[1]
    }
    # global npm .cmd shim on a Win path: ...\<name>.cmd → <name>
    if ($cmd -match '^[A-Za-z]:[\\/]' -and $cmd -match '(?i)[/\\]([^/\\]+?)\.cmd$') { return $Matches[1] }
    # strip any remaining .cmd extension
    $cmd = $cmd -replace '(?i)\.cmd$', ''
    return $cmd
}

$mcpSrc = Join-Path $HostCursorDir 'mcp.json'
if (Test-Path $mcpSrc) {
    $rawMcp = [System.IO.File]::ReadAllText($mcpSrc)
    $cfg = $null
    try { $cfg = $rawMcp | ConvertFrom-Json } catch { Write-Warning "[prepare] mcp.json not valid JSON — skipping: $($_.Exception.Message)" }
    if ($cfg -and $cfg.PSObject.Properties['mcpServers']) {
        $dropped = [System.Collections.Generic.List[string]]::new()
        foreach ($name in @($cfg.mcpServers.PSObject.Properties.Name)) {
            # An empty JSON object (e.g. "mcpServers": {}) can enumerate as a
            # single phantom property with an empty-string name — skip it.
            if ([string]::IsNullOrEmpty($name)) { continue }
            $srv = $cfg.mcpServers.$name
            if ($null -eq $srv) { continue }
            if ($srv.PSObject.Properties['command']) {
                $orig = $srv.command
                $srv.command = Rewrite-McpServerCommand $orig
                if ($srv.command -match '^[A-Za-z]:[\\/]') {
                    Write-Warning "[prepare] mcpServers.${name}: dropping — no Linux mapping for: $orig"
                    $dropped.Add($name)
                } elseif ($srv.command -ne $orig) {
                    Write-Host "[prepare] mcpServers.${name}: rewrote command -> $($srv.command)"
                }
            }
            # Remote servers (url-based) carry no host filesystem path — passed through untouched.
        }
        foreach ($d in $dropped) { $cfg.mcpServers.PSObject.Properties.Remove($d) }
        Write-JsonNoBom (Join-Path $Destination 'mcp.json') $cfg
        Write-Host "[prepare] staged mcp.json (MCP rewrite complete)"
    } elseif ($cfg) {
        Write-JsonNoBom (Join-Path $Destination 'mcp.json') $cfg
        Write-Host "[prepare] staged mcp.json (no mcpServers key — copied as-is)"
    }
} else {
    Write-Host "[prepare] no mcp.json on host — skipping"
}

# Credential-pattern scan over the staged tree (defense in depth).
$leaked = Get-ChildItem -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer } |
    Where-Object {
        $n = $_.Name
        $matched = $false
        foreach ($pat in $credentialExcludePatterns) {
            if ($n -like $pat) { $matched = $true; break }
        }
        $matched
    }
if ($leaked) {
    foreach ($f in $leaked) {
        Write-Warning "[prepare] CREDENTIAL RISK: removing $($f.FullName) from staged context"
        Remove-Item $f.FullName -Force
    }
}

Write-Host "[prepare] staged at $Destination"
Write-Host "[prepare] next: ./build.ps1 -Image <repo>/cursor-custom:v1 -Push"
