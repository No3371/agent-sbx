<#
.SYNOPSIS
    Re-tag an image inside a tar archive (for sbx template load).
.DESCRIPTION
    Rewrites the tag strings inside manifest.json (and repositories) of a
    docker-archive tar without loading the image into the local container store.
    Uses a transient alpine container for the tar/sed operations.
    Used by build.ps1 -Retag / -LoadToSbx.
.PARAMETER Tar
    Path to the image tar file (produced by build.ps1 -Tar).
.PARAMETER OldTag
    Source image tag inside the tar (e.g. localhost/docker.io/user/img:v1).
.PARAMETER NewTag
    Target image tag for sbx load (e.g. docker.io/user/img:v1).
#>
param(
    [Parameter(Mandatory)] [string] $Tar,
    [Parameter(Mandatory)] [string] $OldTag,
    [Parameter(Mandatory)] [string] $NewTag
)

$ErrorActionPreference = 'Stop'

$resolved = (Resolve-Path $Tar).Path
$dir      = [System.IO.Path]::GetDirectoryName($resolved)
$name     = [System.IO.Path]::GetFileName($resolved)

if ($name -match "'") { throw "-Tar filename must not contain a single quote." }

# Escape for sed BRE (used inside single-quoted sh string)
$oldEsc = $OldTag -replace '\.', '\.' `
                  -replace '\[', '\[' `
                  -replace '\]', '\]' `
                  -replace '\^', '\^' `
                  -replace '\\', '\\' `
                  -replace '\*', '\*' `
                  -replace '/',  '\/'
$newEsc = $NewTag -replace '/', '\/' `
                  -replace '&', '\&'

$script = @"
set -e
mkdir -p _retag
tar -xf '$name' -C _retag
sed -i 's/$oldEsc/$newEsc/g' _retag/manifest.json
if [ -f _retag/repositories ]; then
  sed -i 's/$oldEsc/$newEsc/g' _retag/repositories
fi
tar -cf '${name}.new' -C _retag .
mv '${name}.new' '$name'
rm -rf _retag
"@

Write-Host "==> retag-tar: $OldTag -> $NewTag  (alpine sed, no image load)"
podman run --rm -v "${dir}:/work" -w /work docker.io/library/alpine sh -c $script
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "retag-tar: done — $Tar"
