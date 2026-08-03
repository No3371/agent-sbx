# Stages host ~/.codex payload into ./context/.codex for the podman build.
# Maps: config.toml (rewritten + filtered), AGENTS.md, skills/,
#       vendor_imports/skills/, plugins/cache/ (installed plugin bundles).
# Excludes: auth.json, sessions, sqlite state, caches, sandbox dirs, memories,
#           machine-local marker/state files, plugins/data/ and plugin
#           staging dirs — sbx manages auth, the rest is host-only runtime
#           state that has no business in a template image.
#
# config.toml rewriting rules (applied before writing to context):
#   - Drops: [windows] (Windows Sandbox config, meaningless in Linux container)
#   - Drops: [projects.*] (machine-local trust entries)
#   - Drops: ALL [marketplaces.*] (Codex re-registers these at runtime; baking
#            local-source marketplaces is broken because .tmp/ isn't staged)
#   - Drops: [plugins."*@openai-primary-runtime"] (plugins whose marketplace is
#            being dropped — keeping them would dangle)
#   - Keeps: top-level keys (model, model_reasoning_effort, etc.)
#   - Keeps: [plugins."*@openai-bundled"], [plugins."*@openai-curated"]
#   - Keeps: [mcp_servers.*] with command path rewritten Win → bare name

[CmdletBinding()]
param(
    [string]$HostCodexDir = "$env:USERPROFILE\.codex",
    [string]$Destination  = (Join-Path $PSScriptRoot 'context\.codex')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $HostCodexDir)) {
    throw "Host .codex dir not found: $HostCodexDir"
}

# Keep the root stable; staged trees below mirror independently so unchanged
# payloads are not deleted and recopied on every run.
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

# BOMless UTF-8 writer — TOML & Markdown both expected without BOM by their
# typical parsers. PS 5.1 Set-Content -Encoding UTF8 emits BOM; use .NET API
# directly for consistent behavior across PS versions.
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
function Write-TextNoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $Utf8NoBom)
}
function Write-LinesNoBom([string]$path, [string[]]$lines) {
    [System.IO.File]::WriteAllLines($path, $lines, $Utf8NoBom)
}

# Filename patterns that must never be baked into the image, regardless of
# directory. Handed to robocopy /XF below, which matches them at every depth.
$credentialExcludePatterns = @(
    'auth.json', 'token.json', 'secrets.json',
    '*.key', '*.pem', '*.token', '*.credentials',
    '*.p12', '*.pfx'
)
$excludedDirectoryNames = @('.github', '.git', 'node_modules')

# Staging is incremental. robocopy compares size + write time in native code
# and transfers only changes; /MIR also purges destination entries removed from
# the source, preserving the old clean-rebuild result without paying for a full
# delete and per-file PowerShell copy.
#
# robocopy exit codes: 0 = nothing to do | 1 = copied | 2 = purged extras |
# 3 = both | >= 8 = real failure. Everything below 8 is success.
if (-not (Get-Command robocopy -ErrorAction SilentlyContinue)) {
    throw "robocopy not found on PATH — required for staging."
}
# PS 7.3+ can promote a nonzero native exit code to a terminating error under
# $ErrorActionPreference='Stop'. Robocopy's success codes are often nonzero.
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$rcFlags = @('/MIR', '/MT:16', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH', '/NJS')

function Sync-StageTree(
    [string]$label,
    [string]$source,
    [string]$destination,
    [string[]]$additionalExcludedDirectories = @()
) {
    $rcExcludeDirs = @('/XD') + $excludedDirectoryNames + $additionalExcludedDirectories
    # .keep exists only in the destination. /XF also shields it from /MIR purge.
    $rcExcludeFiles = @('/XF', '.keep') + $credentialExcludePatterns

    if (Test-Path $source) {
        robocopy $source $destination @rcFlags @rcExcludeDirs @rcExcludeFiles | Out-Null
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
        Write-Host "[prepare] no $label dir on host"
    }

    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Set-Content -Path (Join-Path $destination '.keep') -Value '' -Encoding UTF8
}

# --- skills/: stage with .system/ excluded, seed .keep placeholder ---
$skillsSrc = Join-Path $HostCodexDir 'skills'
$skillsDst = Join-Path $Destination 'skills'
Sync-StageTree 'skills' $skillsSrc $skillsDst @('.system')

# --- vendor_imports/skills/: staged with recursive excludes ---
$vendorSrc = Join-Path $HostCodexDir 'vendor_imports\skills'
$vendorDst = Join-Path $Destination 'vendor_imports\skills'
Sync-StageTree 'vendor_imports/skills' $vendorSrc $vendorDst

# --- plugins/cache/: installed plugin bundles (context-mode, ponytail, bundled
# browser/chrome, etc.). Only cache/ is staged — plugins/data/,
# .plugin-appserver/, .marketplace-plugin-source-staging/, and
# .remote-plugin-install-staging/ remain host-only runtime/staging state.
$pluginsCacheSrc = Join-Path $HostCodexDir 'plugins\cache'
$pluginsCacheDst = Join-Path $Destination 'plugins\cache'
Sync-StageTree 'plugins/cache' $pluginsCacheSrc $pluginsCacheDst

# /XF prevents credentials entering from the source but also shields matching
# destination files from /MIR purge. Remove anything left by an older prepare
# revision before later processing can fail, while retaining the old warning.
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

# Host .sh files may carry CRLF line endings (authored on Windows) — bash
# rejects a `\r` in the shebang line outright. Normalize before baking.
$shFiles = Get-ChildItem -Path $Destination -Recurse -Force -Filter '*.sh' -ErrorAction SilentlyContinue
foreach ($f in $shFiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    if ($content.Contains("`r`n")) {
        Write-TextNoBom $f.FullName ($content -replace "`r`n", "`n")
        Write-Host "[prepare] normalized CRLF -> LF: $($f.FullName.Substring($Destination.Length))"
    }
}

# --- AGENTS.md: stage as-is, or create empty stub if absent ---
$agentsSrc = Join-Path $HostCodexDir 'AGENTS.md'
$agentsDst = Join-Path $Destination 'AGENTS.md'
if (Test-Path $agentsSrc) {
    Copy-Item -Path $agentsSrc -Destination $agentsDst -Force
    Write-Host "[prepare] staged AGENTS.md"
} else {
    Write-TextNoBom $agentsDst ''
    Write-Host "[prepare] AGENTS.md not on host — wrote empty stub"
}

# --- config.toml: rewrite per drop/keep rules above ---
$configSrc = Join-Path $HostCodexDir 'config.toml'
if (-not (Test-Path $configSrc)) {
    throw "host config.toml missing at $configSrc"
}

# Sections (case-insensitive, after stripping all `"` chars) whose entire body
# must be dropped. Match is by prefix-with-dot-or-exact:
#   "windows"        matches [windows]
#   "projects"       matches [projects.<anything>]
#   "marketplaces"   matches [marketplaces.<anything>]
# Plugin entries pointing at a dropped marketplace are filtered separately.
$dropSectionPrefixes = @(
    'windows',
    'projects',
    'marketplaces'
)

# Plugin marketplaces that no longer exist after [marketplaces.*] drop.
# Sections like [plugins."documents@openai-primary-runtime"] must be dropped.
$droppedPluginMarketplaces = @(
    'openai-primary-runtime'
)

# Rewrite an mcp_servers.* `command = "..."` line. If the value is a Windows
# path (contains a drive letter or a backslash), extract the basename and strip
# .cmd/.exe — leaving the bare binary name (PATH resolution in container).
# Otherwise pass through unchanged. Args array is never touched.
function Rewrite-TomlLine([string]$line, [string]$currentSection) {
    if ([string]::IsNullOrEmpty($line)) { return $line }
    if (-not $currentSection.StartsWith('mcp_servers.')) { return $line }
    # Match `command = "..."` (single or double-quoted) optionally indented.
    $m = [regex]::Match($line, '^(\s*command\s*=\s*)(["''])(.+?)(["''])\s*$')
    if (-not $m.Success) { return $line }
    $prefix = $m.Groups[1].Value
    $openQ  = $m.Groups[2].Value
    $value  = $m.Groups[3].Value
    $closeQ = $m.Groups[4].Value
    # TOML string-literal unescape: doubled-backslash → single. Common in
    # double-quoted TOML strings on Windows. Single-quoted literals are taken
    # raw, so the unescape is a no-op there.
    if ($openQ -eq '"') {
        $value = $value -replace '\\\\', '\'
    }
    # Bare name (no path separators, no drive) → keep as-is.
    if ($value -notmatch '[\\/:]') {
        return $line
    }
    # Extract filename → strip .cmd / .exe suffix.
    $leaf = [System.IO.Path]::GetFileName($value)
    $leaf = $leaf -replace '(?i)\.(cmd|exe)$', ''
    if ([string]::IsNullOrEmpty($leaf)) { return $line }
    return "$prefix`"$leaf`""
}

# Read raw lines (UTF-8 BOM-tolerant via Get-Content -Raw + split).
$rawText  = [System.IO.File]::ReadAllText($configSrc)
$rawLines = $rawText -split "`r?`n"

$outLines        = New-Object System.Collections.Generic.List[string]
$currentSection  = ''  # lowercase, dequoted
$skipSection     = $false
$pendingBlank    = $false  # emit blank line before next kept section header
$keptPluginMarketplaces = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($lineRaw in $rawLines) {
    $line = $lineRaw

    # Section header detection. Empty `[]` shouldn't occur but be defensive.
    $hdr = [regex]::Match($line, '^\s*\[([^\]]+)\]\s*$')
    if ($hdr.Success) {
        $rawName = $hdr.Groups[1].Value
        # Strip ALL `"` characters (not just leading/trailing) so quoted dotted
        # paths like `plugins."documents@openai-primary-runtime"` compare cleanly.
        $name = $rawName.Replace('"', '').ToLower()
        $currentSection = $name
        $skipSection = $false

        # Drop entire section families: windows / projects / marketplaces.
        foreach ($dp in $dropSectionPrefixes) {
            if ($name -eq $dp -or $name.StartsWith("$dp.")) {
                $skipSection = $true
                break
            }
        }

        # Drop plugin entries whose marketplace was removed.
        if (-not $skipSection -and $name.StartsWith('plugins.')) {
            # Plugin section key form: plugins.<plugin-name>@<marketplace>
            # After dequote, section name looks like: plugins.documents@openai-primary-runtime
            $tail = $name.Substring('plugins.'.Length)
            $at = $tail.LastIndexOf('@')
            if ($at -ge 0) {
                $mkt = $tail.Substring($at + 1)
                if ($droppedPluginMarketplaces -contains $mkt) {
                    $skipSection = $true
                } else {
                    [void]$keptPluginMarketplaces.Add($mkt)
                }
            }
        }

        if ($skipSection) {
            # Don't emit header or any of its body until the next header.
            continue
        }

        # Kept header: emit a single blank separator line before it (preserves
        # readability and avoids stacking blanks).
        if ($outLines.Count -gt 0) {
            if ($outLines[$outLines.Count - 1] -ne '') {
                $outLines.Add('') | Out-Null
            }
        }
        $outLines.Add($line) | Out-Null
        $pendingBlank = $false
        continue
    }

    if ($skipSection) { continue }

    # In-section line. Rewrite mcp_servers command paths; everything else passes
    # through verbatim (preserves user comments, ordering, formatting).
    $rewritten = Rewrite-TomlLine $line $currentSection
    $outLines.Add($rewritten) | Out-Null
}

# Trim trailing blank lines for tidy output.
while ($outLines.Count -gt 0 -and $outLines[$outLines.Count - 1] -eq '') {
    $outLines.RemoveAt($outLines.Count - 1)
}

# Codex's `/plugins` and `codex plugin list` do not consider a copied
# plugins/cache tree installed unless the plugin's marketplace can also be
# resolved. Host marketplace sections are intentionally dropped above because
# their sources often point at machine-local `.tmp/` clones, so synthesize
# image-local marketplace mappings for every kept [plugins."name@marketplace"]
# section that has staged cache content.
$imageCodexHome = '/home/agent/.codex'
$marketplaceSections = New-Object System.Collections.Generic.List[string]
foreach ($marketplace in @($keptPluginMarketplaces)) {
    # Browser/chrome bundled plugins are app-runtime payloads and are large
    # enough to make `codex plugin list` sluggish when exposed as a normal
    # local marketplace in this plain Docker variant.
    if ($marketplace -eq 'openai-bundled') { continue }

    $marketCache = Join-Path $pluginsCacheDst $marketplace
    if (-not (Test-Path $marketCache)) { continue }

    # Generate a local marketplace under plugins/cache/<marketplace> that
    # points at already-staged versioned plugin directories. Some upstream
    # manifests advertise Git/URL sources, which makes `codex plugin list`
    # slow or network-dependent even though the cache is already baked.
    $agentsPluginsDir = Join-Path $marketCache '.agents\plugins'
    New-Item -ItemType Directory -Path $agentsPluginsDir -Force | Out-Null

    $pluginEntries = New-Object System.Collections.Generic.List[object]
    $pluginDirs = Get-ChildItem -LiteralPath $marketCache -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '.agents' }
    foreach ($pluginDir in $pluginDirs) {
        $versionDirs = Get-ChildItem -LiteralPath $pluginDir.FullName -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName '.codex-plugin\plugin.json') } |
            Sort-Object Name -Descending
        $versionDir = @($versionDirs)[0]
        if (-not $versionDir) { continue }

        $pluginEntries.Add([ordered]@{
            name = $pluginDir.Name
            source = [ordered]@{
                source = 'local'
                path = "./$($pluginDir.Name)/$($versionDir.Name)"
            }
            policy = [ordered]@{
                installation = 'AVAILABLE'
                authentication = 'ON_INSTALL'
            }
            category = 'Productivity'
        }) | Out-Null
    }

    if ($pluginEntries.Count -eq 0) { continue }

    $marketplaceJson = [ordered]@{
        name = $marketplace
        interface = [ordered]@{
            displayName = $marketplace
        }
        plugins = $pluginEntries
    } | ConvertTo-Json -Depth 10
    Write-TextNoBom (Join-Path $agentsPluginsDir 'marketplace.json') $marketplaceJson

    $relRoot = $marketCache.Substring($Destination.Length).TrimStart('\','/') -replace '\\','/'
    $source = "$imageCodexHome/$relRoot"

    $marketplaceSections.Add("") | Out-Null
    $marketplaceSections.Add("[marketplaces.$marketplace]") | Out-Null
    $marketplaceSections.Add('last_updated = "1970-01-01T00:00:00Z"') | Out-Null
    $marketplaceSections.Add('source_type = "local"') | Out-Null
    $marketplaceSections.Add("source = `"$source`"") | Out-Null
}

foreach ($line in $marketplaceSections) {
    $outLines.Add($line) | Out-Null
}

$configDst = Join-Path $Destination 'config.toml'
Write-LinesNoBom $configDst $outLines.ToArray()
Write-Host "[prepare] config.toml rewritten ($($outLines.Count) lines)"


Write-Host "[prepare] staged at $Destination"
Write-Host "[prepare] next: ./build.ps1 -Image <repo>/codex-custom:v1 -Push"
