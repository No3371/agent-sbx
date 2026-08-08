# Stages host pi payload into the build context:
#   ~/.pi            -> ./context/.pi            (agent/settings.json, models-store.json, ...)
#   ~/.agents/skills -> ./context/.agents/skills (cross-agent skills standard; pi
#                       auto-loads ~/.agents/skills as an always-trusted user resource)
#
# Staging is INCREMENTAL via robocopy /MIR (same system as claude/codex
# prepare.ps1): robocopy compares size + write time per file in native code and
# transfers only what differs, so an unchanged host tree costs a stat sweep
# instead of a full re-copy. /MIR also purges dest entries whose source is gone.

[CmdletBinding()]
param(
    [string]$HostPiDir           = "$env:USERPROFILE\.pi",
    [string]$HostAgentsSkillsDir = "$env:USERPROFILE\.agents\skills",
    [string]$Destination         = (Join-Path $PSScriptRoot 'context\.pi'),
    [string]$SkillsDestination   = (Join-Path $PSScriptRoot 'context\.agents\skills')
)

$ErrorActionPreference = 'Stop'

$credentialExcludePatterns = @(
    'auth.json', 'token.json', 'secrets.json',
    '*.key', '*.pem', '*.token', '*.credentials',
    '*.p12', '*.pfx'
)
# mcp-auth is where pi MCP tooling (e.g. pi-mcp-extension) writes OAuth tokens
# as <sha>.json — names the credential patterns above can't match, so exclude
# the dir outright in case the host ever grows one. (The suite's own MCP
# bridge, pi-mcp-adapter, keeps tokens in the OS credential store, not files.)
# sessions holds host conversation transcripts (~/.pi/agent/sessions and
# per-profile dirs like ~/.pi/context-mode/sessions) — never bake those into a
# shareable image, matching the claude/codex suites' session-history exclusion.
$excludedDirectoryNames = @('.github', '.git', 'node_modules', 'mcp-auth', 'sessions')

function Test-CredentialFileName([string]$name) {
    foreach ($pat in $credentialExcludePatterns) {
        if ($name -like $pat) { return $true }
    }
    return $false
}

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
# *.exe/*.dll: Windows binaries pi drops under ~/.pi/agent/bin (e.g. fd.exe)
# can never run in the Linux image — dead weight, silently excluded.
$rcExcludeFiles = @('/XF', '.keep', '*.exe', '*.dll') + $credentialExcludePatterns

# robocopy exit codes: 0 = nothing to do | 1 = copied | 2 = purged extras |
# 3 = both | >= 8 = real failure. Everything below 8 is success.
function Invoke-RobocopyStage([string]$src, [string]$dst, [string]$label) {
    if (Test-Path $src) {
        robocopy $src $dst @rcFlags @rcExcludeDirs @rcExcludeFiles | Out-Null
        $rc = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($rc -ge 8) { throw "robocopy failed staging ${label}: exit $rc" }
        $verdict = switch ($rc) {
            0       { 'unchanged' }
            1       { 'updated' }
            2       { 'stale entries purged' }
            3       { 'updated + purged' }
            default { "exit $rc" }
        }
        Write-Host "[prepare] $label -> $verdict"
    } else {
        Write-Host "[prepare] no $label on host — staging empty dir"
    }

    # Stage dir must exist even when the host has none, so the Dockerfile COPY
    # shape stays stable; the .keep placeholder stops BuildKit/Buildah seeing an
    # empty COPY source. Written after robocopy so /MIR cannot race it.
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Set-Content -Path (Join-Path $dst '.keep') -Value '' -Encoding UTF8
}

Invoke-RobocopyStage $HostPiDir           $Destination       '~/.pi'
Invoke-RobocopyStage $HostAgentsSkillsDir $SkillsDestination '~/.agents/skills'

$stagedRoots = @($Destination, $SkillsDestination)

# Destination-side credential sweep. /XF stops credential files being copied in,
# but an /XF entry is equally shielded from /MIR's purge — so one staged by an
# older revision of this script would otherwise persist indefinitely. Delete on
# sight (also restores the per-file CREDENTIAL RISK reporting robocopy's own
# silent exclusion doesn't provide).
foreach ($root in $stagedRoots) {
    Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { Test-CredentialFileName $_.Name } |
        ForEach-Object {
            Write-Warning "[prepare] CREDENTIAL RISK: removing staged $($_.FullName)"
            Remove-Item -LiteralPath $_.FullName -Force
        }
}

# Same shielding applies to /XD dirs and the /XF binary patterns: entries staged
# by an older script revision (e.g. sessions/, fd.exe) survive /MIR untouched,
# so purge them dest-side too.
foreach ($root in $stagedRoots) {
    Get-ChildItem -LiteralPath $root -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { $excludedDirectoryNames -contains $_.Name } |
        ForEach-Object {
            Write-Host "[prepare] removing stale excluded dir from stage: $($_.FullName.Substring($root.Length))"
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*.exe' -or $_.Name -like '*.dll' } |
        ForEach-Object {
            Write-Host "[prepare] removing stale Windows binary from stage: $($_.FullName.Substring($root.Length))"
            Remove-Item -LiteralPath $_.FullName -Force
        }
}

# Host .sh files may carry CRLF line endings (authored on Windows) — bash
# rejects a `\r` in the shebang line outright. Normalize before baking.
$utf8NoBomLocal = New-Object System.Text.UTF8Encoding $false
foreach ($root in $stagedRoots) {
    $shFiles = Get-ChildItem -Path $root -Recurse -Force -Filter '*.sh' -ErrorAction SilentlyContinue
    foreach ($f in $shFiles) {
        $content = [System.IO.File]::ReadAllText($f.FullName)
        if ($content.Contains("`r`n")) {
            [System.IO.File]::WriteAllText($f.FullName, ($content -replace "`r`n", "`n"), $utf8NoBomLocal)
            Write-Host "[prepare] normalized CRLF -> LF: $($f.FullName.Substring($root.Length))"
        }
    }
}

Write-Host "[prepare] staged at $Destination and $SkillsDestination"
Write-Host "[prepare] next: ./build.ps1 -Image sbx-pi:v1"
