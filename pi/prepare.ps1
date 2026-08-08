[CmdletBinding()]
param(
    [string]$HostPiDir = "$env:USERPROFILE\.pi",
    [string]$Destination     = (Join-Path $PSScriptRoot 'context\.pi')
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
$excludedDirectoryNames = @('.github', '.git', 'node_modules', 'mcp-auth')

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

if (Test-Path $HostPiDir) {
    $entries = Get-ChildItem -Path $HostPiDir -Force -ErrorAction SilentlyContinue
    if ($entries) {
        Write-Host "[prepare] copying $($entries.Count) entries from $HostPiDir"
        foreach ($e in $entries) {
            Copy-ItemFiltered $e.FullName $Destination
        }
    } else {
        Write-Host "[prepare] $HostPiDir is empty"
    }
} else {
    Write-Host "[prepare] no $($HostPiDir) on host — staging empty dir"
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
Write-Host "[prepare] next: ./build.ps1 -Image sbx-pi:v1"
