# Build the custom Claude Code sandbox template with podman.
#
# Output modes (pick one):
#   default          — image stays in the selected engine's local store only
#   -Tar <path>      — also export to a tar
#   -LoadToDocker    — load the exported tar into Docker (requires -Tar)
#   -LoadToPodman    — load the exported tar into Podman (requires -Tar)
#   -Push            — push to a registry
#
# podman save may emit `localhost/<image>:<tag>` in the manifest for bare image
# names. Use -Retag if you need to strip that prefix before loading elsewhere.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Image,            # e.g. cc-custom:v1 (local) or docker.io/<user>/cc-custom:v1 (push)

    [string]$Tar,              # optional path to export tar (e.g. .\cc-custom.tar)
    [switch]$Push,
    [switch]$Retag,            # after Tar export, rewrite localhost/-prefixed manifest tags
    [switch]$LoadToDocker,     # after Tar export, run `docker load -i <tar>`
    [switch]$LoadToPodman,     # after Tar export, run `podman load -i <tar>`
    [switch]$SkipPrepare,
    [switch]$NoCache,
    [string]$Dockerfile = 'Dockerfile.slim',
    [string]$Engine = 'podman',
    [string]$HostClaudeDir = '',   # passed through to prepare.ps1; default: $env:USERPROFILE\.claude
    [string]$Destination   = ''    # passed through to prepare.ps1; default: <repo>/context/.claude
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Input validation
if ($Image -match '<user>') {
    throw "Replace <user> in -Image with your registry username (e.g. docker.io/yourname/cc-custom:v1)."
}
$loadTargets = @()
if ($LoadToDocker) { $loadTargets += 'docker' }
if ($LoadToPodman) { $loadTargets += 'podman' }
if ($loadTargets.Count -gt 0 -and -not $Tar) { throw "-LoadToDocker/-LoadToPodman requires -Tar <path>" }

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
    if ($HostClaudeDir) { $prepareArgs += '-HostClaudeDir'; $prepareArgs += $HostClaudeDir }
    if ($Destination)   { $prepareArgs += '-Destination';   $prepareArgs += $Destination   }
    & (Join-Path $root 'prepare.ps1') @prepareArgs
}

$dockerfilePath = if ([System.IO.Path]::IsPathRooted($Dockerfile)) { $Dockerfile } else { Join-Path $root $Dockerfile }
if (-not (Test-Path $dockerfilePath)) { throw "Dockerfile not found: $dockerfilePath" }

$buildArgs = @('build', '-t', $Image, '-f', $dockerfilePath)
if ($NoCache) { $buildArgs += '--no-cache' }
$buildArgs += $root

Write-Host "==> $Engine $($buildArgs -join ' ')"
& $Engine @buildArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine build failed ($LASTEXITCODE)" }

if ($Tar) {
    Write-Host "==> $Engine save $Image -> $Tar"
    & $Engine save -o $Tar $Image
    if ($LASTEXITCODE -ne 0) { throw "$Engine save failed ($LASTEXITCODE)" }
}

if ($Push) {
    Write-Host "==> $Engine push $Image"
    & $Engine push $Image
    if ($LASTEXITCODE -ne 0) { throw "$Engine push failed ($LASTEXITCODE)" }
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
} elseif ($Push) {
    Write-Host "Pushed: $Image"
} else {
    Write-Host "Note:  image is only in $Engine's local store."
    Write-Host "       Re-run with -Tar <path> [-LoadToDocker|-LoadToPodman] or -Push."
}
