# Run the baked cc-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `claude` interactively. Reuses host OAuth + session state by bind-mounting
# individual host files (NOT the whole ~/.claude dir, which would shadow the
# image's baked skills/agents/settings).
#
# Run `/login` on the host first. The container mounts the host credentials so
# Claude Code keeps using the same subscription-backed OAuth account.
#
# Conversation history (session transcripts + auto memory) is stored in
# ~/.claude/projects/<encoded-cwd>/ — NOT in .claude.json — so with --rm it
# was lost every run. Since the workspace is always mounted at the fixed path
# /workspace, the encoded dir name is always `-workspace`, so a project-local
# folder is bind-mounted onto it: history now lives in and travels with the
# project instead of the host's global ~/.claude.
#
# SECURITY: ~/.claude.json and ~/.claude/.credentials.json carry live OAuth /
# session tokens. Treat them like SSH keys — never commit, never share them
# (any process/container reading %USERPROFILE% can read the plaintext token).
# The project's .claude/projects/ history folder can contain sensitive
# conversation content too; it's covered by this repo's top-level .gitignore
# (`.claude`), but check your own project's .gitignore if reusing this launcher
# elsewhere.
#
# Runs claude with --permission-mode auto (Claude Code's built-in auto mode,
# v2.1.83+): reads and working-directory file edits auto-approve with no
# prompt, while Bash/shell and network calls still route through Claude
# Code's classifier, which auto-runs what it judges safe and escalates what
# it doesn't — normal Bash review, just without a human in the loop for
# routine stuff. This is a different, mutually exclusive mode from
# --dangerously-skip-permissions (bypassPermissions), which skips review for
# everything including Bash; auto mode's classifier in fact treats launching
# something with --dangerously-skip-permissions as a blockable action.
# Requires the account/model to support auto mode (Team/Enterprise needs an
# Owner to enable it first) — see prepare.ps1's permissions.ask stripping,
# which auto mode needs to actually take effect for Edit/Write/NotebookEdit.

[CmdletBinding()]
param(
    [string]$Image     = 'cc-custom:v1',
    [string]$Engine    = 'docker',
    [string]$Workspace = $PWD.Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command $Engine -ErrorAction SilentlyContinue)) {
    throw "$Engine not found on PATH"
}

# Host timezone -> container TZ, so logs/timestamps match the developer's
# clock instead of defaulting to UTC. TimeZoneInfo.Local.Id is already an IANA
# name on non-Windows PowerShell; TryConvertWindowsIdToIanaId (.NET 6+, i.e.
# pwsh 7+) converts Windows-style ids. ponytail: no conversion path on Windows
# PowerShell 5.1 (.NET Framework lacks that method) — falls back to $null and
# the container just keeps defaulting to UTC as it did before this change.
$tz = $null
try {
    $localId = [System.TimeZoneInfo]::Local.Id
    if ((Test-Path variable:IsWindows) -and -not $IsWindows) {
        # PS Core on Linux/macOS: Local.Id is already an IANA name.
        $tz = $localId
    } elseif ([System.TimeZoneInfo].GetMethod('TryConvertWindowsIdToIanaId')) {
        # Windows (PS Core 7+, .NET 6+): convert the Windows id to IANA.
        $iana = $null
        if ([System.TimeZoneInfo]::TryConvertWindowsIdToIanaId($localId, [ref]$iana)) { $tz = $iana }
    }
    # else: Windows PowerShell 5.1 — .NET Framework has no IANA conversion,
    # $tz stays $null and the container keeps defaulting to UTC as before.
} catch { }

# Host-side persisted state. Bind-mounted as individual files so sibling baked
# files under /home/agent/.claude are NOT shadowed.
$claudeJson = Join-Path $env:USERPROFILE '.claude.json'
$credsFile  = Join-Path $env:USERPROFILE '.claude\.credentials.json'

# Pre-create the host files so the engine bind-mounts them as files, not as
# freshly-created empty directories (Docker creates a dir if the source path
# is absent). BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a
# UTF-8 BOM, which can make a strict JSON parser choke on `{}` before the
# first real write.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
if (-not (Test-Path $claudeJson)) { [System.IO.File]::WriteAllText($claudeJson, '{}', $utf8NoBom) }
if (-not (Test-Path $credsFile)) {
    throw "Host Claude OAuth credentials not found: $credsFile. Run Claude Code on the host and complete /login first."
}

# Project-local conversation history (session transcripts + memory), kept
# alongside the workspace instead of the host's global ~/.claude/projects.
$historyDir = Join-Path $Workspace '.claude\projects'
if (-not (Test-Path $historyDir)) { New-Item -ItemType Directory -Force $historyDir | Out-Null }

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', ("{0}:/home/agent/.claude.json" -f $claudeJson),
    '-v', ("{0}:/home/agent/.claude/.credentials.json" -f $credsFile),
    '-v', ("{0}:/home/agent/.claude/projects" -f $historyDir)
)
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
if ($tz) { $runArgs += @('-e', "TZ=$tz") }
$runArgs += @($Image, 'claude', '--permission-mode', 'auto')

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
