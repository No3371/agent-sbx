# Run from a PowerShell host: .\test-build-feature-flags.ps1
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$script:engineArgs = @()

function fake-engine {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $script:engineArgs = @($Arguments)
    $global:LASTEXITCODE = 0
}

function Assert-Equal([object[]]$Actual, [object[]]$Expected, [string]$Name) {
    if (($Actual -join "`n") -ne ($Expected -join "`n")) {
        throw "$Name failed. Expected: $($Expected -join ' ') Actual: $($Actual -join ' ')"
    }
}

function Assert-Throws([scriptblock]$Action, [string]$Name) {
    try { & $Action } catch { return }
    throw "$Name did not throw."
}

function Invoke-Build([string]$Path, [string[]]$Arguments) {
    $script:engineArgs = @()
    & (Join-Path $repo $Path) @Arguments
}

$claudeRoot = Join-Path $repo 'claude'
$claudeDockerfile = Join-Path $claudeRoot 'Dockerfile.slim'
Invoke-Build 'claude/build.ps1' @('-Image', 'claude:test', '-SkipPrepare', '-Engine', 'fake-engine')
Assert-Equal -Actual $engineArgs -Expected @('build', '-t', 'claude:test', '-f', $claudeDockerfile, '--build-arg', 'INSTALL_GO=1', '--build-arg', 'INSTALL_DOTNET=1', '--build-arg', 'INSTALL_PYTHON=1', $claudeRoot) -Name 'Claude default'

Invoke-Build 'claude/build.ps1' @('-Image', 'claude:go', '-SkipPrepare', '-Engine', 'fake-engine', '-Enable', 'Go')
Assert-Equal -Actual $engineArgs -Expected @('build', '-t', 'claude:go', '-f', $claudeDockerfile, '--build-arg', 'INSTALL_GO=1', '--build-arg', 'INSTALL_DOTNET=0', '--build-arg', 'INSTALL_PYTHON=0', $claudeRoot) -Name 'Claude enable go'

Invoke-Build 'claude/build.ps1' @('-Image', 'claude:no-dotnet', '-SkipPrepare', '-Engine', 'fake-engine', '-Disable', 'dotnet')
Assert-Equal -Actual $engineArgs -Expected @('build', '-t', 'claude:no-dotnet', '-f', $claudeDockerfile, '--build-arg', 'INSTALL_GO=1', '--build-arg', 'INSTALL_DOTNET=0', '--build-arg', 'INSTALL_PYTHON=1', $claudeRoot) -Name 'Claude disable dotnet'

Assert-Throws { Invoke-Build 'claude/build.ps1' @('-Image', 'claude:invalid', '-Engine', 'fake-engine', '-Enable', 'go', '-Disable', 'dotnet') } 'Mutually exclusive selectors'
Assert-Equal -Actual $engineArgs -Expected @() -Name 'Invalid selector engine side effect'
Assert-Throws { Invoke-Build 'claude/build.ps1' @('-Image', 'claude:invalid', '-Engine', 'fake-engine', '-Enable', 'go', 'GO') } 'Duplicate selector'
Assert-Equal -Actual $engineArgs -Expected @() -Name 'Duplicate selector engine side effect'
Assert-Throws { & (Join-Path $repo 'claude/build.ps1') -Image 'claude:invalid' -Engine fake-engine -Enable @() } 'Empty selector'
Assert-Equal -Actual $engineArgs -Expected @() -Name 'Empty selector engine side effect'
Assert-Throws { Invoke-Build 'codex/build.ps1' @('-Image', 'codex:invalid', '-Engine', 'fake-engine', '-Enable', 'go') } 'Codex empty catalog'
Assert-Equal -Actual $engineArgs -Expected @() -Name 'Codex selector engine side effect'
Assert-Throws { Invoke-Build 'opencode/build.ps1' @('-Image', 'opencode:invalid', '-Engine', 'fake-engine', '-Disable', 'go') } 'OpenCode empty catalog'
Assert-Equal -Actual $engineArgs -Expected @() -Name 'OpenCode selector engine side effect'

foreach ($path in 'claude/build.ps1', 'codex/build.ps1', 'opencode/build.ps1') {
    $text = Get-Content (Join-Path $repo $path) -Raw
    if ($text.IndexOf('$enabledLanguages') -gt $text.IndexOf('if (-not $SkipPrepare)')) { throw "$path validates after prepare." }
}

foreach ($path in 'claude/Dockerfile', 'claude/Dockerfile.slim') {
    $text = Get-Content (Join-Path $repo $path) -Raw
    foreach ($language in 'GO', 'DOTNET', 'PYTHON') {
        if ($text -notmatch "ARG INSTALL_${language}=1") { throw "$path lacks INSTALL_$language." }
    }
    if ($text -notmatch 'INSTALL_\* must be 0 or 1') { throw "$path lacks strict build-arg validation." }
}
if ((Get-Content (Join-Path $repo 'claude/Dockerfile.slim') -Raw) -match 'PATH=.*?/usr/local/go/bin') {
    throw 'Slim image leaves Go on PATH when disabled.'
}

Write-Host 'PASS build feature flags'
