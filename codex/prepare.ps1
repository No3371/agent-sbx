# Stage filtered Codex inputs plus optional shared agent skills. Inputs are trusted
# local build payloads, not content-certified by the filename exclusions below.

[CmdletBinding()]
param(
    [string]$HostCodexDir = "$env:USERPROFILE\.codex",
    [string]$HostAgentsSkillsDir = "$env:USERPROFILE\.agents\skills",
    [string]$Destination = (Join-Path $PSScriptRoot 'context\.codex'),
    [string]$SkillsDestination = (Join-Path $PSScriptRoot 'context\.agents\skills')
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$credentialExcludePatterns = @('auth.json', 'token.json', 'secrets.json', '*.key', '*.pem', '*.token', '*.credentials', '*.p12', '*.pfx')
$excludedDirectoryNames = @('.github', '.git', 'node_modules')
$rcMirrorFlags = @('/MIR', '/MT:16', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH', '/NJS')
$markerName = '.codex-stage-marker'

function Write-TextNoBom([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}
function Write-LinesNoBom([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllLines($Path, $Lines, $Utf8NoBom)
}
function Get-CanonicalPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}
function Test-PathInside([string]$Child, [string]$Parent) {
    $c = (Get-CanonicalPath $Child).ToLowerInvariant()
    $p = (Get-CanonicalPath $Parent).ToLowerInvariant()
    return $c -eq $p -or $c.StartsWith($p + [IO.Path]::DirectorySeparatorChar)
}
function Assert-NotFilesystemRoot([string]$Path, [string]$Label) {
    $full = Get-CanonicalPath $Path
    if ($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\', '/')) { throw "$Label must not be a filesystem root." }
}
function Assert-NoReparseTraversal([string]$Path, [string]$Label, [switch]$AllowMissing) {
    $full = Get-CanonicalPath $Path
    $cursor = $full
    while (-not (Test-Path -LiteralPath $cursor)) {
        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor -or [string]::IsNullOrEmpty($parent)) { break }
        $cursor = $parent
    }
    if (-not (Test-Path -LiteralPath $cursor)) {
        if ($AllowMissing) { return }
        throw "$Label does not exist."
    }
    while ($true) {
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Label traverses a reparse point." }
        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor -or [string]::IsNullOrEmpty($parent)) { break }
        $cursor = $parent
    }
    if (Test-Path -LiteralPath $full) {
        $reparse = Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction Stop | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }
        if ($reparse) { throw "$Label contains a reparse point." }
    }
}
function Assert-SkillShape([string]$Root, [string]$Label, [switch]$Optional) {
    if (-not (Test-Path -LiteralPath $Root)) {
        if ($Optional) { return }
        throw "$Label missing."
    }
    foreach ($dir in Get-ChildItem -LiteralPath $Root -Directory -Force) {
        if ($dir.Name -eq '.system' -and $Label -eq 'Codex skills') { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'SKILL.md') -PathType Leaf)) {
            throw "$Label contains malformed skill '$($dir.Name)'."
        }
    }
    $nestedSystem = Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force | Where-Object { $_.Name -eq '.system' -and $_.FullName -ne (Join-Path $Root '.system') }
    if ($nestedSystem) { throw "$Label contains nested .system directory." }
}
function Assert-StageLayout {
    if (-not (Test-Path -LiteralPath $HostCodexDir -PathType Container)) { throw 'Host .codex dir not found.' }
    $configSrc = Join-Path $HostCodexDir 'config.toml'
    if (-not (Test-Path -LiteralPath $configSrc -PathType Leaf)) { throw 'host config.toml missing.' }

    $envelope = Split-Path -Parent (Get-CanonicalPath $Destination)
    $expectedCodex = Join-Path $envelope '.codex'
    $expectedSkills = Join-Path (Join-Path $envelope '.agents') 'skills'
    if ((Get-CanonicalPath $Destination) -ne (Get-CanonicalPath $expectedCodex) -or (Get-CanonicalPath $SkillsDestination) -ne (Get-CanonicalPath $expectedSkills)) {
        throw 'Destinations must be <generated-envelope>/.codex and <generated-envelope>/.agents/skills.'
    }
    foreach ($pair in @(@($HostCodexDir, 'Host .codex'), @($HostAgentsSkillsDir, 'Host shared skills'), @($Destination, 'Codex destination'), @($SkillsDestination, 'Shared-skills destination'), @($envelope, 'Generated envelope'))) {
        Assert-NotFilesystemRoot $pair[0] $pair[1]
    }
    Assert-NoReparseTraversal $HostCodexDir 'Host .codex'
    Assert-NoReparseTraversal $HostAgentsSkillsDir 'Host shared skills' -AllowMissing
    Assert-NoReparseTraversal $Destination 'Codex destination' -AllowMissing
    Assert-NoReparseTraversal $SkillsDestination 'Shared-skills destination' -AllowMissing
    if ((Test-PathInside $Destination $HostCodexDir) -or (Test-PathInside $SkillsDestination $HostCodexDir) -or ((Test-Path $HostAgentsSkillsDir) -and ((Test-PathInside $Destination $HostAgentsSkillsDir) -or (Test-PathInside $SkillsDestination $HostAgentsSkillsDir)))) { throw 'Destination must not be inside a source tree.' }
    if ((Test-PathInside $HostCodexDir $Destination) -or ((Test-Path $HostAgentsSkillsDir) -and (Test-PathInside $HostAgentsSkillsDir $SkillsDestination))) { throw 'Source must not be inside its destination.' }
    if ((Test-PathInside $Destination $SkillsDestination) -or (Test-PathInside $SkillsDestination $Destination)) { throw 'Staging destinations overlap.' }
    Assert-SkillShape (Join-Path $HostCodexDir 'skills') 'Codex skills' -Optional
    Assert-SkillShape $HostAgentsSkillsDir 'Shared skills' -Optional
    return $envelope
}
function Get-MarkerContent([string]$Envelope) {
    return "codex/prepare.ps1 generated envelope: $(Get-CanonicalPath $Envelope)`n"
}
function Assert-Marker([string]$Envelope) {
    $marker = Join-Path $Envelope $markerName
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or [IO.File]::ReadAllText($marker) -cne (Get-MarkerContent $Envelope)) {
        throw 'Generated-root marker is missing or invalid; refusing destination mutation.'
    }
}
function Initialize-TrustedEnvelope([string]$Envelope) {
    if (Test-Path -LiteralPath $Envelope) {
        if (-not (Test-Path -LiteralPath $Envelope -PathType Container)) { throw 'Generated envelope must be a directory.' }
        Assert-Marker $Envelope
        return
    }
    New-Item -ItemType Directory -Path $Envelope -Force | Out-Null
    Write-TextNoBom (Join-Path $Envelope $markerName) (Get-MarkerContent $Envelope)
}
function Assert-Contained([string]$Path, [string]$Root) {
    if (-not (Test-PathInside $Path $Root)) { throw 'Path escapes generated context envelope.' }
}
function Invoke-RobocopyStage([string]$Label, [string]$Source, [string]$Target, [string[]]$ExcludedDirs = @(), [switch]$OptionalDirectory) {
    Assert-Marker $envelope
    Assert-Contained $Target $envelope
    $sourceItem = if (Test-Path -LiteralPath $Source) { Get-Item -LiteralPath $Source -Force } else { $null }
    if (-not $sourceItem) {
        if (-not $OptionalDirectory) { return $false }
        if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        Write-TextNoBom (Join-Path $Target '.keep') ''
        Write-Host "[prepare] $Label absent; wrote placeholder"
        return $false
    }
    $excludeFiles = @('/XF', '.keep') + $credentialExcludePatterns
    if ($sourceItem.PSIsContainer) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        robocopy $sourceItem.FullName $Target @rcMirrorFlags @('/XD') $excludedDirectoryNames $ExcludedDirs @excludeFiles | Out-Null
        $rc = $LASTEXITCODE; $global:LASTEXITCODE = 0
        if ($rc -ge 8) { throw "robocopy failed staging $Label: exit $rc" }
        Write-TextNoBom (Join-Path $Target '.keep') ''
        Write-Host "[prepare] $Label -> robocopy exit $rc"
        return $true
    }
    $sourceParent = Split-Path -Parent $sourceItem.FullName
    $targetParent = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    robocopy $sourceParent $targetParent $sourceItem.Name '/R:1' '/W:1' '/NFL' '/NDL' '/NP' '/NJH' '/NJS' | Out-Null
    $rc = $LASTEXITCODE; $global:LASTEXITCODE = 0
    if ($rc -ge 8) { throw "robocopy failed staging $Label: exit $rc" }
    Write-Host "[prepare] $Label -> robocopy file exit $rc"
    return $true
}
function Remove-StaleExcluded([string]$Root) {
    Assert-Marker $envelope
    foreach ($dir in Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $excludedDirectoryNames -contains $_.Name }) {
        Assert-Contained $dir.FullName $envelope
        Remove-Item -LiteralPath $dir.FullName -Recurse -Force
        Write-Host "[prepare] removed excluded directory: $($dir.FullName.Substring($envelope.Length).TrimStart('\','/'))"
    }
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction SilentlyContinue) {
        if ($credentialExcludePatterns | Where-Object { $file.Name -like $_ }) {
            Assert-Contained $file.FullName $envelope
            Remove-Item -LiteralPath $file.FullName -Force
            Write-Host "[prepare] removed credential-pattern file: $($file.FullName.Substring($envelope.Length).TrimStart('\','/'))"
        }
    }
}
function Normalize-ShellFiles([string]$Root) {
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse -Force -Filter '*.sh' -ErrorAction SilentlyContinue) {
        $text = [IO.File]::ReadAllText($file.FullName)
        if ($text.Contains("`r`n")) { Write-TextNoBom $file.FullName ($text -replace "`r`n", "`n") }
    }
}
function Assert-NoSkillCollisions([string[]]$Roots) {
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $Roots) {
        foreach ($dir in Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue) {
            if ($dir.Name -eq '.system') { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'SKILL.md') -PathType Leaf)) { throw "Staged malformed skill '$($dir.Name)'." }
            if (-not $names.Add($dir.Name)) { throw "Duplicate canonical skill name '$($dir.Name)'." }
        }
    }
}
function Write-Inventory([string[]]$Roots) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($root in $Roots) {
        $rootName = if ((Get-CanonicalPath $root) -eq (Get-CanonicalPath $Destination)) { '.codex' } else { '.agents/skills' }
        foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName) {
            if ($file.Name -eq '.keep') { continue }
            $package = $null; $version = $null; $lifecycle = @()
            if ($file.Name -eq 'package.json') {
                try {
                    $parsed = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                    $package = $parsed.name; $version = $parsed.version
                    if ($parsed.scripts) { $lifecycle = @($parsed.scripts.PSObject.Properties | Where-Object { $_.Name -in @('preinstall','install','postinstall','prepublish','preprepare','prepare','postprepare') } | ForEach-Object { $_.Name }) }
                } catch { throw "Invalid package.json at staged relative path '$($file.FullName.Substring($root.Length).TrimStart('\','/'))'." }
            }
            $items.Add([ordered]@{ root = $rootName; path = $file.FullName.Substring($root.Length).TrimStart('\','/').Replace('\','/'); sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash; package = $package; version = $version; lifecycleScripts = $lifecycle }) | Out-Null
        }
    }
    $inventory = [ordered]@{ format = 1; files = $items }
    Write-TextNoBom (Join-Path $Destination 'staged-input-inventory.json') ($inventory | ConvertTo-Json -Depth 6)
}

if (-not (Get-Command robocopy -ErrorAction SilentlyContinue)) { throw 'robocopy not found on PATH — required for staging.' }
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
$envelope = Assert-StageLayout
Initialize-TrustedEnvelope $envelope

$skillsSrc = Join-Path $HostCodexDir 'skills'
$skillsDst = Join-Path $Destination 'skills'
$vendorSrc = Join-Path $HostCodexDir 'vendor_imports\skills'
$vendorDst = Join-Path $Destination 'vendor_imports\skills'
$pluginsSrc = Join-Path $HostCodexDir 'plugins\cache'
$pluginsDst = Join-Path $Destination 'plugins\cache'
Invoke-RobocopyStage 'skills' $skillsSrc $skillsDst @((Join-Path $skillsSrc '.system')) -OptionalDirectory | Out-Null
Invoke-RobocopyStage 'vendor_imports/skills' $vendorSrc $vendorDst -OptionalDirectory | Out-Null
Invoke-RobocopyStage 'plugins/cache' $pluginsSrc $pluginsDst -OptionalDirectory | Out-Null
Invoke-RobocopyStage 'shared skills' $HostAgentsSkillsDir $SkillsDestination -OptionalDirectory | Out-Null
Remove-StaleExcluded $Destination
Remove-StaleExcluded $SkillsDestination
Normalize-ShellFiles $Destination
Normalize-ShellFiles $SkillsDestination
Assert-NoSkillCollisions @($skillsDst, $vendorDst, $SkillsDestination)

$agentsDst = Join-Path $Destination 'AGENTS.md'
if (-not (Invoke-RobocopyStage 'AGENTS.md' (Join-Path $HostCodexDir 'AGENTS.md') $agentsDst)) { Write-TextNoBom $agentsDst '' }

function Rewrite-TomlLine([string]$Line, [string]$CurrentSection) {
    if ([string]::IsNullOrEmpty($Line) -or -not $CurrentSection.StartsWith('mcp_servers.')) { return $Line }
    $m = [regex]::Match($Line, '^(\s*command\s*=\s*)(["''])(.+?)(["''])\s*$')
    if (-not $m.Success) { return $Line }
    $value = $m.Groups[3].Value
    if ($m.Groups[2].Value -eq '"') { $value = $value -replace '\\\\', '\' }
    if ($value -notmatch '[\\/:]') { return $Line }
    $leaf = ([IO.Path]::GetFileName($value) -replace '(?i)\.(cmd|exe)$', '')
    if ([string]::IsNullOrEmpty($leaf)) { return $Line }
    return "$($m.Groups[1].Value)`"$leaf`""
}
$configSrc = Join-Path $HostCodexDir 'config.toml'
$outLines = New-Object 'System.Collections.Generic.List[string]'; $section = ''; $skip = $false
$keptMarketplaces = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($line in ([IO.File]::ReadAllText($configSrc) -split "`r?`n")) {
    $header = [regex]::Match($line, '^\s*\[([^\]]+)\]\s*$')
    if ($header.Success) {
        $section = $header.Groups[1].Value.Replace('"','').ToLowerInvariant(); $skip = $section -eq 'windows' -or $section.StartsWith('windows.') -or $section -eq 'projects' -or $section.StartsWith('projects.') -or $section -eq 'marketplaces' -or $section.StartsWith('marketplaces.')
        if (-not $skip -and $section.StartsWith('plugins.')) { $at = $section.LastIndexOf('@'); if ($at -ge 0) { $marketplace = $section.Substring($at + 1); if ($marketplace -eq 'openai-primary-runtime') { $skip = $true } else { [void]$keptMarketplaces.Add($marketplace) } } }
        if (-not $skip) { if ($outLines.Count -gt 0 -and $outLines[$outLines.Count - 1] -ne '') { $outLines.Add('') | Out-Null }; $outLines.Add($line) | Out-Null }
    } elseif (-not $skip) { $outLines.Add((Rewrite-TomlLine $line $section)) | Out-Null }
}
foreach ($marketplace in $keptMarketplaces) {
    if ($marketplace -eq 'openai-bundled') { continue }
    $marketCache = Join-Path $pluginsDst $marketplace
    if (-not (Test-Path -LiteralPath $marketCache)) { continue }
    $manifestDir = Join-Path $marketCache '.agents\plugins'; New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($plugin in Get-ChildItem -LiteralPath $marketCache -Directory -Force | Where-Object { $_.Name -ne '.agents' }) {
        $version = Get-ChildItem -LiteralPath $plugin.FullName -Directory -Force | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.codex-plugin\plugin.json') } | Sort-Object Name -Descending | Select-Object -First 1
        if ($version) { $entries.Add([ordered]@{ name = $plugin.Name; source = [ordered]@{ source = 'local'; path = "./$($plugin.Name)/$($version.Name)" }; policy = [ordered]@{ installation = 'AVAILABLE'; authentication = 'ON_INSTALL' }; category = 'Productivity' }) | Out-Null }
    }
    if ($entries.Count -gt 0) {
        Write-TextNoBom (Join-Path $manifestDir 'marketplace.json') (([ordered]@{ name = $marketplace; interface = [ordered]@{ displayName = $marketplace }; plugins = $entries } | ConvertTo-Json -Depth 10))
        $relative = $marketCache.Substring($Destination.Length).TrimStart('\','/').Replace('\','/')
        $outLines.Add('') | Out-Null; $outLines.Add("[marketplaces.$marketplace]") | Out-Null; $outLines.Add('last_updated = "1970-01-01T00:00:00Z"') | Out-Null; $outLines.Add('source_type = "local"') | Out-Null; $outLines.Add("source = `"/root/.codex/$relative`"") | Out-Null
    }
}
while ($outLines.Count -gt 0 -and $outLines[$outLines.Count - 1] -eq '') { $outLines.RemoveAt($outLines.Count - 1) }
Write-LinesNoBom (Join-Path $Destination 'config.toml') $outLines.ToArray()
Write-Inventory @($Destination, $SkillsDestination)
Write-Host '[prepare] staged filtered .codex and shared .agents/skills inputs'
Write-Host '[prepare] next: ./build.ps1 -Image codex-custom:v1'
