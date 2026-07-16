# Stages host ~/.pi/agent into ./context/.pi/agent for the build.
#
# Filtered recursive copy, same shape as opencode/prepare.ps1 — but simpler,
# because pi has no MCP client (see pi's own README: "No MCP."), so there is no
# command-array/Win-path rewrite to do at all, unlike opencode.json or
# ~/.cursor/mcp.json.
#
# Excluded, always:
#   - auth.json, trust.json, models-store.json — credentials / host-specific
#     trust decisions / a refreshable model-catalog cache; auth.json is
#     bind-mounted at runtime by run.ps1 instead (mirrors opencode's auth.json
#     handling), trust.json and models-store.json are just left to regenerate
#     inside the container
#   - sessions/ — pi's session history (organized by working directory);
#     bind-mounted per-project at runtime by run.ps1 instead of baked, since a
#     baked copy would freeze host session history into every image
#   - git/, npm/ — pi's own installed-package directories (`pi install ...`);
#     host-built, may carry native binaries that don't load in the Linux
#     container, and trivially reinstalled with `pi install` if needed
#   - tmp/ — pi's own scratch dir for temporary extension installs; ephemeral
#   - .git/, .github/, node_modules/ dirs anywhere in the tree (vendored
#     extension/skill repos) — never belongs in a baked image
#   - files matching known credential patterns — defense in depth
#
# Baked as-is: settings.json (prefs, no credentials), AGENTS.md/SYSTEM.md/
# APPEND_SYSTEM.md, extensions/, skills/, themes/, prompts/.

[CmdletBinding()]
param(
    [string]$HostPiDir  = "$env:USERPROFILE\.pi\agent",
    [string]$Destination = (Join-Path $PSScriptRoot 'context\.pi\agent')
)

$ErrorActionPreference = 'Stop'

$credentialExcludePatterns = @(
    'auth.json', 'token.json', 'secrets.json',
    '*.key', '*.pem', '*.token', '*.credentials',
    '*.p12', '*.pfx'
)
$excludedDirectoryNames = @('.github', '.git', 'node_modules', 'git', 'npm', 'sessions', 'tmp')
$excludedFileNames = @('auth.json', 'trust.json', 'models-store.json')

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

    if ($excludedFileNames -contains $item.Name) {
        Write-Host "[prepare] skipping excluded file: $($item.FullName)"
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
    Write-Host "[prepare] no ~/.pi/agent on host — staging empty dir"
}

# Host .md/.ts/.js files may carry CRLF line endings (authored on Windows) —
# extensions are TypeScript/JavaScript that pi's loader reads as-is; normalize
# defensively before baking (mirrors opencode's .sh normalization).
$utf8NoBomLocal = New-Object System.Text.UTF8Encoding $false
$textFiles = Get-ChildItem -Path $Destination -Recurse -Force -Include '*.sh','*.ts','*.js','*.mjs' -ErrorAction SilentlyContinue
foreach ($f in $textFiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    if ($content.Contains("`r`n")) {
        [System.IO.File]::WriteAllText($f.FullName, ($content -replace "`r`n", "`n"), $utf8NoBomLocal)
        Write-Host "[prepare] normalized CRLF -> LF: $($f.FullName.Substring($Destination.Length))"
    }
}

# Credential-pattern scan over the entire staged tree (defense in depth).
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
Write-Host "[prepare] next: ./build.ps1 -Image <repo>/pi-custom:v1 -Push"
