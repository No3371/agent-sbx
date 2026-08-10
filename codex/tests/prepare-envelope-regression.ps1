# Requires Windows PowerShell 5.1 and robocopy.exe.
$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$codexRoot = Split-Path -Parent $PSScriptRoot
$prepare = Join-Path $codexRoot 'prepare.ps1'
$build = Join-Path $codexRoot 'build.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ("codex-prepare-envelope-$([Guid]::NewGuid())")

try {
    $hostCodex = Join-Path $fixture 'host\.codex'
    $missingSkills = Join-Path $fixture 'missing\.agents\skills'
    $victim = Join-Path $fixture 'victim'
    $destination = Join-Path $victim '.codex'
    $skillsDestination = Join-Path $victim '.agents\skills'
    New-Item -ItemType Directory -Path $hostCodex, $destination, $skillsDestination -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $hostCodex 'config.toml'), "[notice]`n")
    $codexSentinel = Join-Path $destination 'keep-codex.txt'
    $skillsSentinel = Join-Path $skillsDestination 'keep-skills.txt'
    [IO.File]::WriteAllText($codexSentinel, 'codex must survive')
    [IO.File]::WriteAllText($skillsSentinel, 'skills must survive')

    $rejected = $false
    try {
        & $prepare -HostCodexDir $hostCodex -HostAgentsSkillsDir $missingSkills -Destination $destination -SkillsDestination $skillsDestination
    } catch {
        $rejected = $_.Exception.Message -match 'marker.*missing or invalid'
    }
    Assert-True $rejected 'Unmarked existing envelope was not rejected.'
    Assert-True ([IO.File]::ReadAllText($codexSentinel) -ceq 'codex must survive') 'Unmarked Codex destination was mutated.'
    Assert-True ([IO.File]::ReadAllText($skillsSentinel) -ceq 'skills must survive') 'Unmarked shared-skills destination was mutated.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $victim '.codex-stage-marker'))) 'Rejected envelope received a marker.'

    $buildText = [IO.File]::ReadAllText($build)
    Assert-True ($buildText -notmatch '-Engine <docker\|podman>') 'Build output still recommends Podman as a run engine.'
    Assert-True ($buildText -notmatch 'template with podman') 'Build header still advertises Podman.'
    Write-Host 'PASS: unmarked destination is immutable; build output recommends Docker only.'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
