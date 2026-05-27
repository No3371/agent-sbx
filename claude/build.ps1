# Build the custom Claude Code sandbox template with podman.
#
# Output modes (pick one):
#   default     — image stays in local podman store only (not usable by sbx)
#   -Tar <path> — also export to a tar; load into sbx with `sbx template load <tar>`
#                 Add -Retag to strip the `localhost/` prefix so the tar is
#                 drop-in for sbx without a manual retag-tar.ps1 step.
#   -Push       — push to a registry (sbx pulls from there)
#
# sbx note: the sandbox runtime does NOT share your local podman/docker image
# store. To use a freshly built template you must EITHER push to a registry OR
# export to tar and `sbx template load` it. Also: podman save always emits
# `localhost/<image>:<tag>` in the manifest; sbx parses `localhost/` as a
# registry hostname and fails. -Retag (or -LoadToSbx) rewrites the manifest.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Image,            # e.g. cc-custom:v1 (local) or docker.io/<user>/cc-custom:v1 (push)

    [string]$Tar,              # optional path to export tar (e.g. .\cc-custom.tar)
    [switch]$Push,
    [switch]$Retag,            # after Tar export, rewrite localhost/-prefixed manifest tags
    [switch]$LoadToSbx,        # after Tar export, run `sbx template load` (implies -Retag)
    [switch]$SkipPrepare,
    [switch]$NoCache,
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
# Single-quote guard only matters when retag-tar.ps1 will be invoked.
# (retag-tar.ps1 embeds the tar path in a sh heredoc — single-quote injection risk)
$doRetag = $Retag -or $LoadToSbx
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

$buildArgs = @('build', '-t', $Image, '-f', (Join-Path $root 'Dockerfile'))
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

# Retag the tar's manifest so sbx doesn't interpret `localhost/` as a registry.
# Fires when -Retag is explicit OR -LoadToSbx is set (load needs a clean tag).
# podman save normalizes tags to `localhost/<image>:<tag>` even when the user
# passed a bare name, so retag is always needed for the sbx tar workflow.
if ($doRetag) {
    if (-not $Tar) { throw "-Retag/-LoadToSbx requires -Tar <path>" }
    if ($Image -like 'localhost/*') {
        $oldTag = $Image
        $newTag = $Image -replace '^localhost/', ''
    } else {
        $oldTag = "localhost/$Image"
        $newTag = $Image
    }
    Write-Host "==> retag-tar.ps1 $Tar  $oldTag -> $newTag"
    & (Join-Path $root 'retag-tar.ps1') -Tar $Tar -OldTag $oldTag -NewTag $newTag
    if ($LASTEXITCODE -ne 0) { throw "retag-tar failed ($LASTEXITCODE)" }
}

if ($LoadToSbx) {
    if (-not (Get-Command sbx -ErrorAction SilentlyContinue)) { throw "sbx not on PATH" }
    Write-Host "==> sbx template load $Tar"
    & sbx template load $Tar
    if ($LASTEXITCODE -ne 0) { throw "sbx template load failed ($LASTEXITCODE)" }
}

Write-Host ""
Write-Host "Built: $Image"
if ($Tar)     { Write-Host "Tar:   $Tar" }
if ($doRetag) { Write-Host "Retag: $oldTag -> $newTag" }
if ($LoadToSbx) {
    Write-Host "Loaded into sbx. Run: sbx run -t $newTag claude"
} elseif ($doRetag) {
    Write-Host "Next:  sbx template load $Tar  &&  sbx run -t $newTag claude"
} elseif ($Tar) {
    Write-Host "Next:  ./retag-tar.ps1 -Tar $Tar -NewTag <bare-tag>  &&  sbx template load $Tar"
    Write-Host "       (or re-run build with -Retag to bake the retag into this command.)"
} elseif ($Push) {
    Write-Host "Use:   sbx run --template $Image claude"
} else {
    Write-Host "Note:  image is only in $Engine's local store; sbx can't pull it."
    Write-Host "       Re-run with -Tar <path> [-Retag|-LoadToSbx] or -Push."
}
