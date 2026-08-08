# Stages host opencode payload into the build context:
#   ~/.config/opencode -> ./context/.config/opencode (opencode.json, AGENTS.md,
#                         plugin/, skills/, vendored repos, ...)
#   ~/.agents/skills   -> ./context/.agents/skills   (cross-agent skills standard;
#                         opencode auto-loads ~/.agents/skills/<name>/SKILL.md)
#
# Staging is INCREMENTAL via robocopy /MIR (same system as claude/codex
# prepare.ps1): robocopy compares size + write time per file in native code and
# transfers only what differs, so an unchanged host tree costs a stat sweep
# instead of a full re-copy. /MIR also purges dest entries whose source is gone.
# Exclusions (reused from the claude/codex prepare.ps1 convention):
#   - .git/ and .github/ dirs anywhere in the tree (never belongs in a baked image)
#   - node_modules/ dirs anywhere in the tree (host-built, breaks native addons
#     in a Linux container; see README "What prepare.ps1 excludes")
#   - filenames matching known credential patterns (defense in depth)
#
# opencode manages its own OAuth/provider credentials elsewhere
# (~/.local/share/opencode/auth.json), which is bind-mounted at runtime by
# run.ps1 — nothing under ~/.config/opencode is expected to hold secrets, but
# the scan runs anyway since it's cheap.
#
# After staging, opencode.json gets its local MCP `command` arrays rewritten
# (Win paths -> Linux) — see the section comment below.

[CmdletBinding()]
param(
    [string]$HostOpencodeDir     = "$env:USERPROFILE\.config\opencode",
    [string]$HostAgentsSkillsDir = "$env:USERPROFILE\.agents\skills",
    [string]$Destination         = (Join-Path $PSScriptRoot 'context\.config\opencode'),
    [string]$SkillsDestination   = (Join-Path $PSScriptRoot 'context\.agents\skills')
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

Invoke-RobocopyStage $HostOpencodeDir     $Destination       '~/.config/opencode'
Invoke-RobocopyStage $HostAgentsSkillsDir $SkillsDestination '~/.agents/skills'

$stagedRoots = @($Destination, $SkillsDestination)

# Host .sh files may carry CRLF line endings (authored on Windows) — bash
# rejects a `\r` in the shebang line outright. Normalize before baking.
# NOTE: robocopy compares size+mtime against the HOST file, so normalized (and
# rewritten) files re-copy on the next run and get normalized again — expected.
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

Write-Host "[prepare] staged at $Destination and $SkillsDestination"
Write-Host "[prepare] next: ./build.ps1 -Image opencode-custom:v1"
