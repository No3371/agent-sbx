# Build oh-my-pi sandbox with personal state from the host with podman or docker.
#
# Output modes (pick one):
#   default          — image stays in the selected engine's local store only
#   -Tar <path>      — also export to a tar
#   -LoadToDocker    — load the exported tar into Docker (requires -Tar)
#   -LoadToPodman    — load the exported tar into Podman (requires -Tar)
#
# podman save may emit `localhost/<image>:<tag>` in the manifest for bare image
# names. Use -Retag if you need to strip that prefix before loading elsewhere.

[CmdletBinding()]
param(
    [string]$Image = "sbx-omp:v1",            # e.g. sbx-omp:v1

    [string]$Tar,              # optional path to export tar (e.g. .\sbx-omp.tar)
    [switch]$Retag,            # after Tar export, rewrite localhost/-prefixed manifest tags
    [switch]$LoadToDocker,     # after Tar export, run `docker load -i <tar>`
    [switch]$LoadToPodman,     # after Tar export, run `podman load -i <tar>`
    [switch]$SkipPrepare,
    [switch]$NoCache,
    [string[]]$Enable,
    [string[]]$Disable,
    [string]$Dockerfile = 'Dockerfile',
    [string]$Engine = 'docker',
    [string]$HostPiDir  = '',   # passed through to prepare.ps1; default: $env:USERPROFILE\.pi\agent
    [string]$Destination = '',   # passed through to prepare.ps1; default: <repo>/context/.pi/agent
    [string]$OMPPin = ""
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Resolve-LanguageSelection {
    param(
        [string[]]$Enable,
        [string[]]$Disable,
        [string[]]$Supported,
        [bool]$EnableSpecified,
        [bool]$DisableSpecified
    )

    if ($EnableSpecified -and $DisableSpecified) { throw '-Enable and -Disable are mutually exclusive.' }
    if (($EnableSpecified -or $DisableSpecified) -and $Supported.Count -eq 0) {
        throw 'This image has no optional language features; selectors are unsupported.'
    }

    $selected = @()
    $seen = @{}
    $rawValues = if ($EnableSpecified) { @($Enable) } elseif ($DisableSpecified) { @($Disable) } else { @() }
    if (($EnableSpecified -or $DisableSpecified) -and $rawValues.Count -eq 0) { throw 'Language selector requires at least one name.' }
    foreach ($raw in $rawValues) {
        if ([string]::IsNullOrWhiteSpace($raw)) { throw 'Language names must not be blank.' }
        $language = $raw.Trim().ToLowerInvariant()
        if ($seen.ContainsKey($language)) { throw "Language '$language' was selected more than once." }
        if ($language -notin $Supported) { throw "Unknown language '$language'. Supported: $($Supported -join ', ')." }
        $seen[$language] = $true
        $selected += $language
    }

    if ($EnableSpecified) { return @($selected) }
    if ($DisableSpecified) { return @($Supported | Where-Object { $_ -notin $selected }) }
    return @($Supported)
}

# Input validation
if ($Image -match '<user>') {
    throw "Replace <user> in -Image with your registry username (e.g. docker.io/yourname/sbx-omp:v1)."
}
$loadTargets = @()
if ($LoadToDocker) { $loadTargets += 'docker' }
if ($LoadToPodman) { $loadTargets += 'podman' }
if ($loadTargets.Count -gt 0 -and -not $Tar) { throw "-LoadToDocker/-LoadToPodman requires -Tar <path>" }
$enabledLanguages = Resolve-LanguageSelection -Enable $Enable -Disable $Disable -Supported @('go', 'dotnet', 'pwsh') -EnableSpecified ($PSBoundParameters.ContainsKey('Enable')) -DisableSpecified ($PSBoundParameters.ContainsKey('Disable'))

# Single-quote guard only matters when retag-tar.ps1 will be invoked.
# (retag-tar.ps1 embeds the tar path in a sh heredoc — single-quote injection risk)
$doRetag = $Retag
if ($doRetag -and $Tar -and $Tar -match "'") {
    throw "-Tar path must not contain a single quote — path injection risk in retag-tar.ps1 shell script."
}

if (-not (Get-Command $Engine -ErrorAction SilentlyContinue)) {
    throw "$Engine not found on PATH"
}

if (-not $SkipPrepare) {
    Write-Host "==> prepare.ps1"
    $prepareArgs = @()
    if ($HostPiDir)   { $prepareArgs += '-HostPiDir';   $prepareArgs += $HostPiDir   }
    if ($Destination) { $prepareArgs += '-Destination'; $prepareArgs += $Destination }
    & (Join-Path $root 'prepare.ps1') @prepareArgs
}

$dockerfilePath = if ([System.IO.Path]::IsPathRooted($Dockerfile)) { $Dockerfile } else { Join-Path $root $Dockerfile }
if (-not (Test-Path $dockerfilePath)) { throw "Dockerfile not found: $dockerfilePath" }

$buildArgs = @('build', '-t', $Image, '-f', $dockerfilePath)
foreach ($language in @('go', 'dotnet', 'pwsh')) {
    $buildArgs += '--build-arg'
    $buildArgs += "INSTALL_$($language.ToUpperInvariant())=$([int]($language -in $enabledLanguages))"
}
if ($NoCache) { $buildArgs += '--no-cache' }
$buildArgs += $root

Write-Host "==> optional languages: $(if ($enabledLanguages) { $enabledLanguages -join ', ' } else { 'none' })"
Write-Host "==> $Engine $($buildArgs -join ' ')"

Write-Host "Building on-my-pi as base image"
& $Engine build -t oh-my-pi/pi:dev "https://github.com/can1357/oh-my-pi.git#$OMPPin"
if ($LASTEXITCODE -ne 0) { throw "$Engine build -t oh-my-pi/pi:dev failed ($LASTEXITCODE)" }

& $Engine @buildArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine build failed ($LASTEXITCODE)" }

if ($Tar) {
    Write-Host "==> $Engine save $Image -> $Tar"
    & $Engine save -o $Tar $Image
    if ($LASTEXITCODE -ne 0) { throw "$Engine save failed ($LASTEXITCODE)" }
}


# Retag the tar's manifest when explicitly requested.
if ($doRetag) {
    if (-not $Tar) { throw "-Retag requires -Tar <path>" }
    if ($Image -like 'localhost/*') {
        $oldTag = $Image
        $newTag = $Image -replace '^localhost/', ''
    } else {
        $oldTag = "localhost/$Image"
        $newTag = $Image
    }
    Write-Host "==> retag-tar.ps1 $Tar  $oldTag -> $newTag"
    & (Join-Path $root 'retag-tar.ps1') -Tar $Tar -OldTag $oldTag -NewTag $newTag -Engine $Engine
    if ($LASTEXITCODE -ne 0) { throw "retag-tar failed ($LASTEXITCODE)" }
}

foreach ($target in $loadTargets) {
    if (-not (Get-Command $target -ErrorAction SilentlyContinue)) { throw "$target not found on PATH" }
    Write-Host "==> $target load -i $Tar"
    & $target load -i $Tar
    if ($LASTEXITCODE -ne 0) { throw "$target load failed ($LASTEXITCODE)" }
}

Write-Host ""
Write-Host "Built: $Image"
if ($Tar)     { Write-Host "Tar:   $Tar" }
if ($doRetag) { Write-Host "Retag: $oldTag -> $newTag" }
if ($loadTargets.Count -gt 0) {
    Write-Host "Loaded into: $($loadTargets -join ', ')"
    Write-Host "Run:   ./run.ps1 -Image $Image -Engine <docker|podman>"
} elseif ($Tar) {
    Write-Host "Next:  docker load -i $Tar  OR  podman load -i $Tar"
} else {
    Write-Host "Note:  image is only in $Engine's local store."
    Write-Host "       Re-run with -Tar <path> [-LoadToDocker|-LoadToPodman]."
}
