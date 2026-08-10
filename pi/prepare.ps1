# Stage ~/.pi to ./context/.pi and ~/.agents/skills to
# ./context/.agents/skills. robocopy /MIR updates incrementally and purges
# destination entries removed from the source.

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
# Exclude mcp-auth because hashed OAuth-token filenames evade credential-name
# filters, and exclude sessions because transcripts must not enter an image.
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
        $item = Get-Item $src
        
        if (-not $item.PSIsContainer) {
$ErrorActionPreference = 'Inquire'
            $srcParent = Split-Path -Path $src -Parent -Resolve

            $fn = Split-Path -Path $src -Leaf -Resolve
        
            $dstParent = Split-Path -Path $dst -Parent
	       
            $rcFlags2 = @('/MT:4', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH', '/NJS')
            
            robocopy $srcParent $dstParent $fn @rcFlags2 | Out-Null
            $rc = $LASTEXITCODE
            $global:LASTEXITCODE = 0

            if ($rc -ge 8) {
                throw "robocopy failed staging ${label}: exit $rc"
            }

            $verdict = switch ($rc) {
                0       { 'unchanged' }
                1       { 'updated' }
                2       { 'stale entries purged' }
                3       { 'updated + purged' }
                default { "exit $rc" }
            }

            Write-Host "[prepare] $label -> $verdict"

		 return # We don't want to add .keep here
        }
        else {
            # Directory source
            robocopy $src $dst @rcFlags @rcExcludeDirs @rcExcludeFiles | Out-Null
            $rc = $LASTEXITCODE
            $global:LASTEXITCODE = 0

            if ($rc -ge 8) {
                throw "robocopy failed staging ${label}: exit $rc"
            }

            $verdict = switch ($rc) {
                0       { 'unchanged' }
                1       { 'updated' }
                2       { 'stale entries purged' }
                3       { 'updated + purged' }
                default { "exit $rc" }
            }

            Write-Host "[prepare] $label($src) -> $verdict"
        }
    }
    else {
        Write-Host "[prepare] no $label on host — staging empty dir"
    }

    # Stage dir must always exist so the Dockerfile COPY shape stays stable.
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Set-Content -Path (Join-Path $dst '.keep') -Value '' -Encoding UTF8
}
Invoke-RobocopyStage $HostPiDir           $Destination       '~/.pi'
Invoke-RobocopyStage $HostAgentsSkillsDir $SkillsDestination '~/.agents/skills'
Invoke-RobocopyStage "$env:USERPROFILE\.pi-lens\config.json" (Join-Path $PSScriptRoot 'context\.pi-lens\config.json') '~/.pi-lens/config.json'

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