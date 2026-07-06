# Stages host ~/.codex payload into ./context/.codex for the podman build.
# Maps: config.toml (rewritten + filtered), AGENTS.md, skills/, vendor_imports/skills/.
# Excludes: auth.json, sessions, sqlite state, caches, sandbox dirs, memories,
#           machine-local marker/state files — sbx manages auth, the rest is
#           host-only runtime state that has no business in a template image.
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
# directory. Applied as a post-copy scan over the entire $Destination tree —
# the host exclude list already covers known credential paths but deep nesting
# inside skills/ or vendor_imports/ could still surface secrets.
$credentialExcludePatterns = @(
    'auth.json', 'token.json', 'secrets.json',
    '*.key', '*.pem', '*.token', '*.credentials',
    '*.p12', '*.pfx'
)

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
            Copy-Item -Path $e.FullName -Destination $skillsDst -Recurse -Force
        }
    } else {
        Write-Host "[prepare] skills on host is empty (after .system/ exclusion)"
    }
} else {
    Write-Host "[prepare] no skills dir on host"
}

# --- vendor_imports/skills/: staged as-is; .git/ purged in the general pass below ---
$vendorDst = Join-Path $Destination 'vendor_imports\skills'
New-Item -ItemType Directory -Path $vendorDst -Force | Out-Null
Set-Content -Path (Join-Path $vendorDst '.keep') -Value '' -Encoding UTF8

$vendorSrc = Join-Path $HostCodexDir 'vendor_imports\skills'
if (Test-Path $vendorSrc) {
    $topEntries = Get-ChildItem -Path $vendorSrc -Force -ErrorAction SilentlyContinue
    if ($topEntries) {
        Write-Host "[prepare] mapping vendor_imports/skills ($($topEntries.Count) entries)"
        foreach ($e in $topEntries) {
            Copy-Item -Path $e.FullName -Destination $vendorDst -Recurse -Force
        }
    } else {
        Write-Host "[prepare] vendor_imports/skills on host is empty"
    }
} else {
    Write-Host "[prepare] no vendor_imports/skills dir on host"
}

# Strip .git/ and .github/ dirs from all staged content (skills/,
# vendor_imports/). Copy-Item -Exclude only matches top-level names, so
# git-cloned skill dirs still carry nested .git/ subtrees; .github/ carries
# upstream CODEOWNERS/dependabot/issue templates. Neither belongs in a baked
# image.
$vcsDirs = Get-ChildItem -Path $Destination -Recurse -Force -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq '.github' -or $_.Name -eq '.git' }
foreach ($g in $vcsDirs) {
    Write-Host "[prepare] removing $($g.Name) dir from staged context: $($g.FullName)"
    Remove-Item $g.FullName -Recurse -Force
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
