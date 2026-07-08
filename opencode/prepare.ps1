# Stages host ~/.config/opencode into ./context/.config/opencode for the build.
#
# Unlike codex/claude's prepare.ps1, this is a filtered recursive copy — no
# path rewriting, no section filtering (opencode.json / AGENTS.md / plugin/ /
# skills/ / vendored repos copied except exclusions). Three exclusions, all reused
# from the codex/claude prepare.ps1 convention:
#   - .git/ and .github/ dirs anywhere in the tree (never belongs in a baked image)
#   - node_modules/ dirs anywhere in the tree (host-built, breaks native addons
#     in a Linux container; see README "What prepare.ps1 excludes")
#   - filenames matching known credential patterns (defense in depth)
#
# opencode manages its own OAuth/provider credentials elsewhere
# (~/.local/share/opencode/auth.json), which is bind-mounted at runtime by
# run.ps1 — nothing under ~/.config/opencode is expected to hold secrets, but
# the scan runs anyway since it's cheap.

[CmdletBinding()]
param(
    [string]$HostOpencodeDir = "$env:USERPROFILE\.config\opencode",
    [string]$Destination     = (Join-Path $PSScriptRoot 'context\.config\opencode')
)

$ErrorActionPreference = 'Stop'

$credentialExcludePatterns = @(
    'auth.json', 'token.json', 'secrets.json',
    '*.key', '*.pem', '*.token', '*.credentials',
    '*.p12', '*.pfx'
)
$excludedDirectoryNames = @('.github', '.git', 'node_modules')

function Test-CredentialFileName([string]$name) {
    foreach ($pat in $credentialExcludePatterns) {
        if ($name -like $pat) { return $true }
    }
    return $false
}

function Copy-ItemFiltered([string]$sourcePath, [string]$destinationDir) {
    $item = Get-Item -LiteralPath $sourcePath -Force

    if ($item.PSIsContainer) {
        if ($excludedDirectoryNames -contains $item.Name) {
            Write-Host "[prepare] skipping excluded dir: $($item.FullName)"
            return
        }

        $target = Join-Path $destinationDir $item.Name
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        $children = Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            Copy-ItemFiltered $child.FullName $target
        }
        return
    }

    if (Test-CredentialFileName $item.Name) {
        Write-Warning "[prepare] CREDENTIAL RISK: skipping $($item.FullName)"
        return
    }

    Copy-Item -LiteralPath $item.FullName -Destination $destinationDir -Force
}

# Recreate $Destination clean on each run so stale entries from a prior layout
# never linger in the build context.
if (Test-Path $Destination) {
    Remove-Item $Destination -Recurse -Force
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

if (Test-Path $HostOpencodeDir) {
    $entries = Get-ChildItem -Path $HostOpencodeDir -Force -ErrorAction SilentlyContinue
    if ($entries) {
        Write-Host "[prepare] copying $($entries.Count) entries from $HostOpencodeDir"
        foreach ($e in $entries) {
            Copy-ItemFiltered $e.FullName $Destination
        }
    } else {
        Write-Host "[prepare] $HostOpencodeDir is empty"
    }
} else {
    Write-Host "[prepare] no ~/.config/opencode on host — staging empty dir"
}

# Host .sh files may carry CRLF line endings (authored on Windows) — bash
# rejects a `\r` in the shebang line outright. Normalize before baking.
$utf8NoBomLocal = New-Object System.Text.UTF8Encoding $false
$shFiles = Get-ChildItem -Path $Destination -Recurse -Force -Filter '*.sh' -ErrorAction SilentlyContinue
foreach ($f in $shFiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    if ($content.Contains("`r`n")) {
        [System.IO.File]::WriteAllText($f.FullName, ($content -replace "`r`n", "`n"), $utf8NoBomLocal)
        Write-Host "[prepare] normalized CRLF -> LF: $($f.FullName.Substring($Destination.Length))"
    }
}

# Credential-pattern scan over the entire staged tree.
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
Write-Host "[prepare] next: ./build.ps1 -Image <repo>/opencode-custom:v1 -Push"
