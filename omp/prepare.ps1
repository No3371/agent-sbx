# Stages host ~/.claude payload into ./context/.claude for the podman build.
# Maps: settings.json (rewritten + filtered), skills, agents, tools, commands,
#       hooks, plugins.
# Excludes: .credentials.json, .claude.json, sessions, history, projects,
#           cache, statsig, telemetry — sbx manages those.
#
# Settings filtering rules (applied before writing to context):
#   - Keeps: enabledPlugins (plugins/ is now baked into image)
#   - Strips: skipAutoPermissionPrompt (permission posture is a template-author
#             decision, not silently inherited from host)
#   - statusLine: command rewritten — git-bash node path → bare `node`,
#             cygpath -w wrappers dropped. Kept as-is otherwise.
#   - Hooks: each hook command is path-rewritten (Win → Linux), then the hook
#             entry is dropped if its command references a path that does NOT
#             exist in the staged image FS layout.
#   - mcpServers: commands path-rewritten (Win npx-cache → bare name); entries
#             with no Linux mapping are dropped with a warning.
#   - project .mcp.json: merged from repo root (one level up from this script),
#             command paths rewritten — covers project-level MCP installs like
#             context-mode. Project entries win over global on name collision.

[CmdletBinding()]
param(
    [string]$HostOMPDir = "$env:USERPROFILE\.omp",
    [string]$Destination   = (Join-Path $PSScriptRoot 'context\.omp')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $HostOMPDir)) {
    throw "Host .claude dir not found: $HostOMPDir"
}

$dirs = @('agent', 'plugins')

# Filename patterns that must never be baked into the image, regardless of directory.
# Handed to robocopy /XF below, which matches them at every depth.
$credentialExcludePatterns = @(
    '*.credentials', '.credentials', 'auth.json', '.token', '*.token',
    'secrets.json', '*.key', '*.pem', '*.p12', '*.pfx', 'token.json', '.auth'
)
$excludedDirectoryNames = @('.github', '.git', 'node_modules')

function Test-CredentialFileName([string]$name) {
    foreach ($pat in $credentialExcludePatterns) {
        if ($name -like $pat) { return $true }
    }
    return $false
}

# Staging is INCREMENTAL. This used to delete each stage dir and re-copy the host
# tree file-by-file via Copy-Item — ~2350 files / 32MB for a typical ~/.claude,
# and PowerShell's per-cmdlet overhead dominates when the files are this small.
# robocopy compares size + write time per file in native code and transfers only
# what differs, so an unchanged host tree costs a stat sweep instead of a full
# re-copy (measured 21.1s -> 0.6s here; the gap is wider on a cold file cache or
# with on-access AV inspecting 32MB of fresh writes).
#
# /MIR also purges dest entries whose source is gone — the property the old
# delete-then-copy shape bought, kept without paying the deletion.
#
# robocopy exit codes: 0 = nothing to do | 1 = copied | 2 = purged extras |
# 3 = both | >= 8 = real failure. Everything below 8 is success.
if (-not (Get-Command robocopy -ErrorAction SilentlyContinue)) {
    throw "robocopy not found on PATH — required for staging."
}
# PS 7.3+ can promote a nonzero native exit code to a terminating error under
# $ErrorActionPreference='Stop'. Robocopy's SUCCESS codes are nonzero, so opt out
# for the rest of this script. (No-op on PS 5.1, where the variable is absent.)
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$rcFlags = @('/MIR', '/MT:16', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH', '/NJS')
$rcExcludeDirs = @('/XD') + $excludedDirectoryNames
# .keep exists only on the dest side (seeded below). An /XF entry is also shielded
# from /MIR's purge, so listing it keeps the placeholder stable across runs.
$rcExcludeFiles = @('/XF', '.keep') + $credentialExcludePatterns

foreach ($name in $dirs) {
    $src = Join-Path $HostOMPDir $name
    $dst = Join-Path $Destination $name

    if (Test-Path $src) {
        robocopy $src $dst @rcFlags @rcExcludeDirs @rcExcludeFiles | Out-Null
        $rc = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($rc -ge 8) { throw "robocopy failed staging ${name}: exit $rc" }
        $verdict = switch ($rc) {
            0       { 'unchanged' }
            1       { 'updated' }
            2       { 'stale entries purged' }
            3       { 'updated + purged' }
            default { "exit $rc" }
        }
        Write-Host "[prepare] $name -> $verdict"
    } else {
        Write-Host "[prepare] no $name dir on host"
    }

    # Stage dir must exist even when the host has none, so COPY shape stays
    # stable; the .keep placeholder stops BuildKit/Buildah seeing an empty COPY
    # source. Written after robocopy so /MIR cannot race the placeholder.
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Set-Content -Path (Join-Path $dst '.keep') -Value '' -Encoding UTF8
}

# Destination-side credential sweep. /XF stops credential files being copied in,
# but an /XF entry is equally shielded from /MIR's purge — so one staged by an
# older revision of this script would otherwise persist indefinitely. Delete on
# sight. This also restores the reporting the old per-file CREDENTIAL RISK
# warning provided: robocopy's own exclusion is silent.
foreach ($name in $dirs) {
    $dstDir = Join-Path $Destination $name
    if (-not (Test-Path $dstDir)) { continue }
    Get-ChildItem -LiteralPath $dstDir -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { Test-CredentialFileName $_.Name } |
        ForEach-Object {
            Write-Warning "[prepare] CREDENTIAL RISK: removing staged $($_.FullName)"
            Remove-Item -LiteralPath $_.FullName -Force
        }
}

# Host .sh files may carry CRLF line endings (authored on Windows) — bash
# rejects a `\r` in the shebang line outright. .gitattributes normalizes *.sh
# in *this* repo, but skills/hooks/scripts staged here come from the host
# ~/.claude tree, so normalize them explicitly.
$utf8NoBomLocal = New-Object System.Text.UTF8Encoding $false
$shFiles = Get-ChildItem -Path $Destination -Recurse -Force -Filter '*.sh' -ErrorAction SilentlyContinue
foreach ($f in $shFiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    if ($content.Contains("`r`n")) {
        [System.IO.File]::WriteAllText($f.FullName, ($content -replace "`r`n", "`n"), $utf8NoBomLocal)
        Write-Host "[prepare] normalized CRLF -> LF: $($f.FullName.Substring($Destination.Length))"
    }
}


Write-Host "[prepare] staged at $Destination"
