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

# --- opencode.json: rewrite Win paths in local MCP server command arrays ---
# opencode.json's only host-path-bearing, config-embedded surface is local MCP
# `command` arrays (["npx","-y","pkg"] / ["node","C:\\...\\index.js"]). Unlike
# claude's settings.json there are no hooks/statusLine/skipAutoPermissionPrompt
# to port. Rewrite EVERY element (a Win path can live in an arg, not just [0] —
# redteam F2), force-array-cast for PS 5.1's single-element-array collapse
# (F3), drop the server if any element is still a Windows drive path after
# rewrite. `permission` (a documented opencode key controlling auto-approval)
# is NOT stripped here — the plan scoped permission-posture out — but its
# presence is surfaced before build/export (F1, minimal touch).
function Convert-OpencodeWinPath([string]$p) {
    if ([string]::IsNullOrEmpty($p)) { return $p }
    # host opencode config dir → container path
    $p = $p -replace '(?i)^([A-Za-z]):[\\/]Users[\\/][^\\/]+[\\/]\.config[\\/]opencode', '/home/agent/.config/opencode'
    # normalize backslashes only for things that look like Windows paths (leave
    # bare tool names / flags untouched)
    if ($p -match '^[A-Za-z]:[\\/]' -or $p -match '\\') { $p = $p -replace '\\', '/' }
    return $p
}

function Rewrite-McpCommandElement([string]$e) {
    if ([string]::IsNullOrEmpty($e)) { return $e }
    # node.exe (Win) / git-bash / WSL node → node
    $e = $e -replace '(?i)^"?[A-Za-z]:[\\/]Program Files[\\/]nodejs[\\/]node\.exe"?$', 'node'
    $e = $e -replace '(?i)^"?/(?:c|mnt/[a-z])/Program Files/nodejs/node(?:\.exe)?"?$', 'node'
    # npx one-off cache shim: ...\_npx\<hash>\node_modules\.bin\<name>[.cmd] → <name>
    if ($e -match '(?i)[/\\]_npx[/\\][^/\\]+[/\\]node_modules[/\\]\.bin[/\\]([^/\\]+?)(?:\.cmd)?$') { return $Matches[1] }
    # global npm .cmd shim on a Win path: ...\<name>.cmd → <name>
    if ($e -match '^[A-Za-z]:[\\/]' -and $e -match '(?i)[/\\]([^/\\]+?)\.cmd$') { return $Matches[1] }
    # host opencode config path → container path
    $e = Convert-OpencodeWinPath $e
    # strip any remaining .cmd
    $e = $e -replace '(?i)\.cmd$', ''
    return $e
}

$ocJson = Join-Path $Destination 'opencode.json'
if (Test-Path $ocJson) {
    $rawOc = [System.IO.File]::ReadAllText($ocJson)
    # JSONC guard: opencode allows comments; ConvertFrom-Json (PS 5.1) does not.
    # If the file carries // or /* comments, skip the rewrite rather than corrupt it.
    $looksJsonc = $rawOc -match '(?m)^\s*//' -or $rawOc -match '/\*'
    $cfg = $null
    if ($looksJsonc) {
        Write-Warning "[prepare] opencode.json has comments (JSONC) — skipping MCP rewrite to avoid corrupting it"
    } else {
        try { $cfg = $rawOc | ConvertFrom-Json } catch { Write-Warning "[prepare] opencode.json not valid JSON — skipping MCP rewrite: $($_.Exception.Message)" }
    }
    if ($cfg) {
        if ($cfg.PSObject.Properties['permission']) {
            Write-Warning "[prepare] opencode.json has a 'permission' block — it controls auto-approval and is baked as-is (not stripped). Review before building or sharing an exported tar."
        }
        if ($cfg.PSObject.Properties['mcp']) {
            $dropped = [System.Collections.Generic.List[string]]::new()
            foreach ($name in @($cfg.mcp.PSObject.Properties.Name)) {
                $srv = $cfg.mcp.$name
                if ($srv.type -eq 'local' -and $srv.PSObject.Properties['command']) {
                    # F3: force array — PS 5.1 deserializes ["x"] as a bare string
                    $cmdArr = @($srv.command)
                    if ($cmdArr.Count -eq 0) { continue }
                    $newArr = @()
                    $changed = $false
                    $unmappable = $false
                    foreach ($el in $cmdArr) {
                        $rew = Rewrite-McpCommandElement ([string]$el)
                        if ($rew -ne [string]$el) { $changed = $true }
                        if ($rew -match '^[A-Za-z]:[\\/]') { $unmappable = $true }
                        $newArr += $rew
                    }
                    if ($unmappable) {
                        Write-Warning "[prepare] mcp.${name}: dropping — no Linux mapping for command: $($cmdArr -join ' ')"
                        $dropped.Add($name)
                    } else {
                        # reassign as array (also repairs a PS 5.1 collapsed single-element command)
                        $srv.command = [string[]]$newArr
                        if ($changed) { Write-Host "[prepare] mcp.${name}: rewrote command -> $($newArr -join ' ')" }
                    }
                }
            }
            foreach ($d in $dropped) { $cfg.mcp.PSObject.Properties.Remove($d) }
        }
        $utf8NoBomOc = New-Object System.Text.UTF8Encoding $false
        $ocOut = $cfg | ConvertTo-Json -Depth 20
        # PS 5.1 ConvertTo-Json collapses single-element arrays to scalars on
        # OUTPUT too; repair any local MCP `command` that came out as a bare
        # string so the array-typed schema opencode requires is preserved.
        $ocOut = [regex]::Replace($ocOut, '("command":\s*)("(?:[^"\\]|\\.)*")(\s*[,}\r\n])', '$1[$2]$3')
        [System.IO.File]::WriteAllText($ocJson, $ocOut, $utf8NoBomOc)
        Write-Host "[prepare] opencode.json: MCP rewrite complete (BOM-less)"
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
Write-Host "[prepare] next: ./build.ps1 -Image opencode-custom:v1"
