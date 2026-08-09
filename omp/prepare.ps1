# Stage host ~/.omp agent and plugin payloads into ./context/.omp. Credential
# files, repository metadata, and host node_modules are excluded; staged shell
# scripts are normalized for Linux.

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

# robocopy /MIR stages incrementally and purges destination entries removed from
# the source. Exit codes below 8 are success; 8 and above are failures.
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
