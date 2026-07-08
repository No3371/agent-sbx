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

# Recreate $Destination clean on each run so stale entries from a prior layout
# never linger in the build context.
if (Test-Path $Destination) {
    Remove-Item $Destination -Recurse -Force
}
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
# directory.
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

# --- skills/: stage with .system/ excluded, seed .keep placeholder ---
$skillsDst = Join-Path $Destination 'skills'
New-Item -ItemType Directory -Path $skillsDst -Force | Out-Null
Set-Content -Path (Join-Path $skillsDst '.keep') -Value '' -Encoding UTF8

$skillsSrc = Join-Path $HostCodexDir 'skills'
if (Test-Path $skillsSrc) {
    $entries = Get-ChildItem -Path $skillsSrc -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '.system' }
    if ($entries) {
        Write-Host "[prepare] mapping skills ($($entries.Count) entries; excluding .system/)"
        foreach ($e in $entries) {
            Copy-ItemFiltered $e.FullName $skillsDst
        }
    } else {
        Write-Host "[prepare] skills on host is empty (after .system/ exclusion)"
    }
} else {
    Write-Host "[prepare] no skills dir on host"
}

# --- vendor_imports/skills/: staged with recursive excludes ---
$vendorDst = Join-Path $Destination 'vendor_imports\skills'
New-Item -ItemType Directory -Path $vendorDst -Force | Out-Null
Set-Content -Path (Join-Path $vendorDst '.keep') -Value '' -Encoding UTF8

$vendorSrc = Join-Path $HostCodexDir 'vendor_imports\skills'
if (Test-Path $vendorSrc) {
    $topEntries = Get-ChildItem -Path $vendorSrc -Force -ErrorAction SilentlyContinue
    if ($topEntries) {
        Write-Host "[prepare] mapping vendor_imports/skills ($($topEntries.Count) entries)"
        foreach ($e in $topEntries) {
            Copy-ItemFiltered $e.FullName $vendorDst
        }
    } else {
        Write-Host "[prepare] vendor_imports/skills on host is empty"
    }
} else {
    Write-Host "[prepare] no vendor_imports/skills dir on host"
}

# --- plugins/cache/: installed plugin bundles (context-mode, ponytail, bundled
# browser/chrome, etc.), staged with recursive excludes. Only cache/ is staged — plugins/data/,
# .plugin-appserver/, .marketplace-plugin-source-staging/, and
# .remote-plugin-install-staging/ are machine-local runtime/staging state with
# no place in a baked image (same rationale as excluding sessions/sqlite
# above).
$pluginsCacheDst = Join-Path $Destination 'plugins\cache'
New-Item -ItemType Directory -Path $pluginsCacheDst -Force | Out-Null
Set-Content -Path (Join-Path $pluginsCacheDst '.keep') -Value '' -Encoding UTF8

$pluginsCacheSrc = Join-Path $HostCodexDir 'plugins\cache'
if (Test-Path $pluginsCacheSrc) {
    $topEntries = Get-ChildItem -Path $pluginsCacheSrc -Force -ErrorAction SilentlyContinue
    if ($topEntries) {
        Write-Host "[prepare] mapping plugins/cache ($($topEntries.Count) entries)"
        foreach ($e in $topEntries) {
            Copy-ItemFiltered $e.FullName $pluginsCacheDst
        }
    } else {
        Write-Host "[prepare] plugins/cache on host is empty"
    }
} else {
    Write-Host "[prepare] no plugins/cache dir on host"
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

# --- post-copy credential scan over entire $Destination ---
# Catches anything that slipped through directory-level exclusions (deep
# nesting inside skills/ or vendor_imports/). Match files by name against the
# credential pattern list and warn + remove each hit.
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
Write-Host "[prepare] next: ./build.ps1 -Image <repo>/codex-custom:v1 -Push"
