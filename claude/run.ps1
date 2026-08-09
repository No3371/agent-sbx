# Run the baked cc-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `claude` interactively. Reuses host OAuth by bind-mounting individual host
# files (NOT the whole ~/.claude dir, which would shadow the image's baked
# skills/agents/settings).
#
# Run `/login` on the host first. The container mounts the host credentials so
# Claude Code keeps using the same subscription-backed OAuth account.
#
# HOST STATE ISOLATION: ~/.claude.json is NOT mounted. It is Claude Code's
# global registry — trusted-repo list (projects[<path>].hasTrustDialogAccepted),
# onboarding flags, model caches — and Claude Code rewrites the whole file from
# an in-memory snapshot taken at startup. Mounting the host file made every
# container a second writer racing the host app: whichever instance flushed last
# overwrote the other's state wholesale, silently wiping trusted repos (observed:
# a 17h container dropped the host config 39,902 -> 1,074 bytes with `projects`
# emptied). Instead a throwaway per-run COPY is seeded with just the fields the
# container needs (OAuth identity + MCP servers), mounted, and deleted on exit.
# The container can write it freely; the host file is never opened for write.
#
# .credentials.json IS mounted read-write, deliberately, and unlike .claude.json
# above. The sandbox is the primary place agents run here — not the host app —
# so it is the instance that has to be able to refresh in place. Under the
# previous `:ro` mount every container was capped at whatever life remained on
# the access token it started with, which a long session outlives.
#
# Accepted race: refresh tokens are single-use, and each instance decides to
# refresh from an in-memory snapshot taken at ITS OWN startup — nothing re-reads
# the file, so a fresher expiresAt on disk does not suppress a peer's refresh.
# Two instances both live across an expiry will both try to redeem the same
# token; the first wins, the second is left holding a burned one and must
# /login. A host started AFTER a container refresh is fine — it loads the
# rotated token from disk. So the exposure is narrow but real: host and
# container running concurrently across an expiry boundary. The trade accepted
# here — the inverse of the .claude.json one — is that the host may be the
# loser. Don't leave host Claude Code logged in beside a long container session.
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
# Runs claude with --permission-mode auto by default (Claude Code's built-in
# auto mode, v2.1.83+): reads and working-directory file edits auto-approve
# with no prompt, while Bash/shell and network calls still route through
# Claude Code's classifier, which auto-runs what it judges safe and escalates
# what it doesn't — normal Bash review, just without a human in the loop for
# routine stuff. Requires the account/model to support auto mode
# (Team/Enterprise needs an Owner to enable it first) — see prepare.ps1's
# permissions.ask stripping, which auto mode needs to actually take effect
# for Edit/Write/NotebookEdit.
#
# Also passes --allow-dangerously-skip-permissions, which does NOT start the
# session in bypass — it just adds bypassPermissions to the Shift+Tab mode
# cycle (after plan, before auto) so it's reachable mid-session without a
# restart. --dangerously-skip-permissions (bare) would instead *start* the
# session already in bypass; auto mode's classifier treats launching that
# combination as a blockable action, so auto + allow (not auto + bare-skip)
# is the supported way to get both modes in one session.
#
# Pass -DangerouslySkipPermissions to start directly in bypass instead (skips
# auto mode/the classifier from the first prompt) — the container is still
# the blast-radius boundary, so this is for when you want that boundary alone.

[CmdletBinding()]
param(
    [string]$Image     = 'sbx-cc:v1',
    [string]$Engine    = 'docker',
    [string]$Workspace = $PWD.Path,
    [switch]$GPU,
    [switch]$EnableBgIsolation,
    [switch]$DangerouslySkipPermissions,
    [string]$Prompt,
    [ValidateRange(0, 2147483647)]
    [int]$Delay = 0
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command $Engine -ErrorAction SilentlyContinue)) {
    throw "$Engine not found on PATH"
}

if ($Delay) {
    Write-Host "==> Waiting $Delay seconds before starting Claude"
    Start-Sleep -Seconds $Delay
}

# Host timezone -> container TZ, so logs/timestamps match the developer's
# clock instead of defaulting to UTC. TimeZoneInfo.Local.Id is already an IANA
# name on non-Windows PowerShell; TryConvertWindowsIdToIanaId (.NET 6+, i.e.
# pwsh 7+) converts Windows-style ids. Windows PowerShell 5.1 (.NET Framework
# lacks that method) and ids the runtime can't map fall back to a static CLDR
# windowsZones table; only if that also misses does the container stay on UTC.
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
    if (-not $tz) {
        # Windows PowerShell 5.1 (no conversion API) or an id the runtime can't
        # map: static CLDR windowsZones primary mappings (territory 001).
        $windowsToIana = @{
            'Dateline Standard Time'='Etc/GMT+12'; 'UTC-11'='Etc/GMT+11'; 'Aleutian Standard Time'='America/Adak'
            'Hawaiian Standard Time'='Pacific/Honolulu'; 'Marquesas Standard Time'='Pacific/Marquesas'; 'Alaskan Standard Time'='America/Anchorage'
            'UTC-09'='Etc/GMT+9'; 'Pacific Standard Time (Mexico)'='America/Tijuana'; 'UTC-08'='Etc/GMT+8'
            'Pacific Standard Time'='America/Los_Angeles'; 'US Mountain Standard Time'='America/Phoenix'; 'Mountain Standard Time (Mexico)'='America/Mazatlan'
            'Mountain Standard Time'='America/Denver'; 'Yukon Standard Time'='America/Whitehorse'; 'Central America Standard Time'='America/Guatemala'
            'Central Standard Time'='America/Chicago'; 'Easter Island Standard Time'='Pacific/Easter'; 'Central Standard Time (Mexico)'='America/Mexico_City'
            'Canada Central Standard Time'='America/Regina'; 'SA Pacific Standard Time'='America/Bogota'; 'Eastern Standard Time (Mexico)'='America/Cancun'
            'Eastern Standard Time'='America/New_York'; 'Haiti Standard Time'='America/Port-au-Prince'; 'Cuba Standard Time'='America/Havana'
            'US Eastern Standard Time'='America/Indianapolis'; 'Turks And Caicos Standard Time'='America/Grand_Turk'; 'Paraguay Standard Time'='America/Asuncion'
            'Atlantic Standard Time'='America/Halifax'; 'Venezuela Standard Time'='America/Caracas'; 'Central Brazilian Standard Time'='America/Cuiaba'
            'SA Western Standard Time'='America/La_Paz'; 'Pacific SA Standard Time'='America/Santiago'; 'Newfoundland Standard Time'='America/St_Johns'
            'Tocantins Standard Time'='America/Araguaina'; 'E. South America Standard Time'='America/Sao_Paulo'; 'SA Eastern Standard Time'='America/Cayenne'
            'Argentina Standard Time'='America/Buenos_Aires'; 'Greenland Standard Time'='America/Godthab'; 'Montevideo Standard Time'='America/Montevideo'
            'Magallanes Standard Time'='America/Punta_Arenas'; 'Saint Pierre Standard Time'='America/Miquelon'; 'Bahia Standard Time'='America/Bahia'
            'UTC-02'='Etc/GMT+2'; 'Azores Standard Time'='Atlantic/Azores'; 'Cape Verde Standard Time'='Atlantic/Cape_Verde'
            'UTC'='Etc/UTC'; 'GMT Standard Time'='Europe/London'; 'Greenwich Standard Time'='Atlantic/Reykjavik'
            'Sao Tome Standard Time'='Africa/Sao_Tome'; 'Morocco Standard Time'='Africa/Casablanca'; 'W. Europe Standard Time'='Europe/Berlin'
            'Central Europe Standard Time'='Europe/Budapest'; 'Romance Standard Time'='Europe/Paris'; 'Central European Standard Time'='Europe/Warsaw'
            'W. Central Africa Standard Time'='Africa/Lagos'; 'Jordan Standard Time'='Asia/Amman'; 'GTB Standard Time'='Europe/Bucharest'
            'Middle East Standard Time'='Asia/Beirut'; 'Egypt Standard Time'='Africa/Cairo'; 'E. Europe Standard Time'='Europe/Chisinau'
            'Syria Standard Time'='Asia/Damascus'; 'West Bank Standard Time'='Asia/Hebron'; 'South Africa Standard Time'='Africa/Johannesburg'
            'FLE Standard Time'='Europe/Kiev'; 'Israel Standard Time'='Asia/Jerusalem'; 'South Sudan Standard Time'='Africa/Juba'
            'Kaliningrad Standard Time'='Europe/Kaliningrad'; 'Sudan Standard Time'='Africa/Khartoum'; 'Libya Standard Time'='Africa/Tripoli'
            'Namibia Standard Time'='Africa/Windhoek'; 'Arabic Standard Time'='Asia/Baghdad'; 'Turkey Standard Time'='Europe/Istanbul'
            'Arab Standard Time'='Asia/Riyadh'; 'Belarus Standard Time'='Europe/Minsk'; 'Russian Standard Time'='Europe/Moscow'
            'E. Africa Standard Time'='Africa/Nairobi'; 'Iran Standard Time'='Asia/Tehran'; 'Arabian Standard Time'='Asia/Dubai'
            'Astrakhan Standard Time'='Europe/Astrakhan'; 'Azerbaijan Standard Time'='Asia/Baku'; 'Russia Time Zone 3'='Europe/Samara'
            'Mauritius Standard Time'='Indian/Mauritius'; 'Saratov Standard Time'='Europe/Saratov'; 'Georgian Standard Time'='Asia/Tbilisi'
            'Volgograd Standard Time'='Europe/Volgograd'; 'Caucasus Standard Time'='Asia/Yerevan'; 'Afghanistan Standard Time'='Asia/Kabul'
            'West Asia Standard Time'='Asia/Tashkent'; 'Ekaterinburg Standard Time'='Asia/Yekaterinburg'; 'Pakistan Standard Time'='Asia/Karachi'
            'Qyzylorda Standard Time'='Asia/Qyzylorda'; 'India Standard Time'='Asia/Calcutta'; 'Sri Lanka Standard Time'='Asia/Colombo'
            'Nepal Standard Time'='Asia/Katmandu'; 'Central Asia Standard Time'='Asia/Bishkek'; 'Bangladesh Standard Time'='Asia/Dhaka'
            'Omsk Standard Time'='Asia/Omsk'; 'Myanmar Standard Time'='Asia/Rangoon'; 'SE Asia Standard Time'='Asia/Bangkok'
            'Altai Standard Time'='Asia/Barnaul'; 'W. Mongolia Standard Time'='Asia/Hovd'; 'North Asia Standard Time'='Asia/Krasnoyarsk'
            'N. Central Asia Standard Time'='Asia/Novosibirsk'; 'Tomsk Standard Time'='Asia/Tomsk'; 'China Standard Time'='Asia/Shanghai'
            'North Asia East Standard Time'='Asia/Irkutsk'; 'Singapore Standard Time'='Asia/Singapore'; 'W. Australia Standard Time'='Australia/Perth'
            'Taipei Standard Time'='Asia/Taipei'; 'Ulaanbaatar Standard Time'='Asia/Ulaanbaatar'; 'Aus Central W. Standard Time'='Australia/Eucla'
            'Transbaikal Standard Time'='Asia/Chita'; 'Tokyo Standard Time'='Asia/Tokyo'; 'North Korea Standard Time'='Asia/Pyongyang'
            'Korea Standard Time'='Asia/Seoul'; 'Yakutsk Standard Time'='Asia/Yakutsk'; 'Cen. Australia Standard Time'='Australia/Adelaide'
            'AUS Central Standard Time'='Australia/Darwin'; 'E. Australia Standard Time'='Australia/Brisbane'; 'AUS Eastern Standard Time'='Australia/Sydney'
            'West Pacific Standard Time'='Pacific/Port_Moresby'; 'Tasmania Standard Time'='Australia/Hobart'; 'Vladivostok Standard Time'='Asia/Vladivostok'
            'Lord Howe Standard Time'='Australia/Lord_Howe'; 'Bougainville Standard Time'='Pacific/Bougainville'; 'Russia Time Zone 10'='Asia/Srednekolymsk'
            'Magadan Standard Time'='Asia/Magadan'; 'Norfolk Standard Time'='Pacific/Norfolk'; 'Sakhalin Standard Time'='Asia/Sakhalin'
            'Central Pacific Standard Time'='Pacific/Guadalcanal'; 'Russia Time Zone 11'='Asia/Kamchatka'; 'New Zealand Standard Time'='Pacific/Auckland'
            'UTC+12'='Etc/GMT-12'; 'Fiji Standard Time'='Pacific/Fiji'; 'Chatham Islands Standard Time'='Pacific/Chatham'
            'UTC+13'='Etc/GMT-13'; 'Tonga Standard Time'='Pacific/Tongatapu'; 'Samoa Standard Time'='Pacific/Apia'
            'Line Islands Standard Time'='Pacific/Kiritimati'
        }
        $tz = $windowsToIana[$localId]
    }
} catch { }
if (-not $tz) { Write-Warning "[run] could not map host timezone to an IANA name; container clock defaults to UTC" }

# Host-side state. Bind-mounted as individual files so sibling baked files
# under /home/agent/.claude are NOT shadowed.
$hostClaudeJson = Join-Path $env:USERPROFILE '.claude.json'
$credsFile      = Join-Path $env:USERPROFILE '.claude\.credentials.json'

if (-not (Test-Path $credsFile)) {
    throw "Host Claude OAuth credentials not found: $credsFile. Run Claude Code on the host and complete /login first."
}

# Per-run throwaway .claude.json for the container (see HOST STATE ISOLATION).
# Seeded from the host file with only what the container actually needs:
#   oauthAccount / userID  - so the mounted credentials resolve to a logged-in
#                            account instead of re-prompting for /login
#   mcpServers             - host-configured MCP servers the container consumed
#                            before this became a copy
#   firstStartTime         - suppresses first-run treatment
# Deliberately NOT copied: `projects` (the host trust registry + per-project
# allowedTools), caches, migration flags. The container has no use for the
# host's other repos, so it never sees them.
#
# BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a UTF-8 BOM,
# which can make a strict JSON parser choke.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$runId     = [guid]::NewGuid().ToString('N').Substring(0, 12)
$claudeJsonCopy = Join-Path ([System.IO.Path]::GetTempPath()) "cc-custom-claude-$runId.json"

$seed = [ordered]@{}
if (Test-Path $hostClaudeJson) {
    try {
        $hostCfg = Get-Content -LiteralPath $hostClaudeJson -Raw | ConvertFrom-Json
        foreach ($key in 'oauthAccount', 'userID', 'firstStartTime', 'mcpServers') {
            $prop = $hostCfg.PSObject.Properties[$key]
            if ($prop -and $null -ne $prop.Value) { $seed[$key] = $prop.Value }
        }
    } catch {
        # Unparseable host config is not fatal — the container just starts from
        # an empty one and prompts /login, exactly as the pre-copy design did.
        Write-Warning "[run] could not parse ${hostClaudeJson}: $($_.Exception.Message)"
        Write-Warning "[run] container will start from an empty config (expect a /login prompt)"
    }
}

# Workspace is always mounted at the fixed path /workspace, so pre-accept the
# trust dialog for it — the copy is fresh every run and would otherwise prompt.
$seed['hasCompletedOnboarding'] = $true
$seed['projects'] = @{
    '/workspace' = [ordered]@{
        hasTrustDialogAccepted                  = $true
        projectOnboardingSeenCount              = 1
        hasClaudeMdExternalIncludesApproved     = $false
        hasClaudeMdExternalIncludesWarningShown = $false
    }
}
[System.IO.File]::WriteAllText($claudeJsonCopy, ($seed | ConvertTo-Json -Depth 100), $utf8NoBom)

# Project-local conversation history (session transcripts + memory), kept
# alongside the workspace instead of the host's global ~/.claude/projects.
$historyDir = Join-Path $Workspace '.claude\projects'
if (-not (Test-Path $historyDir)) { New-Item -ItemType Directory -Force $historyDir | Out-Null }

# Shared package-manager caches (named volumes reused by every project/container
# of this suite). npm's cache (~/.npm) is pre-warmed + agent-owned in the image,
# so a fresh mount copy-ups clean — no setup needed. pnpm's store otherwise
# defaults to /workspace/.pnpm-store (pollutes the host repo with Linux store
# content, per-project, unshareable), so relocate it to a shared HOME volume via
# `pnpm config set store-dir` and chown the (fresh -> root:root) volume first.
# Runs every launch, node_modules mask or not.
$pmSetup = "sudo chown agent:agent /home/agent/.pnpm-store 2>/dev/null; pnpm config set store-dir /home/agent/.pnpm-store 2>/dev/null || true;"

# node_modules boundary: a host (Windows) node_modules bind-mounted into the
# Linux container carries win32-native bundler binaries (rollup/esbuild/
# rolldown) that crash here. Only when the host actually has a node_modules do
# we mask it with a per-project NAMED volume (empty on first run) and install
# Linux-native deps from empty inside the container — mirroring the plugin
# reinstall precedent in this Dockerfile. A fresh named volume mounts root:root
# while we run as agent, so chown it unconditionally (every run, in case the
# volume was recreated) before the empty-check. Absent -> plain bind-mount, and
# only the pm-cache volumes above change vs. pre-pivot behavior.
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
$nmInstall = ""
if ($maskNodeModules) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash  = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "nmvol-$hash"
    $nmInstall = "sudo chown agent:agent /workspace/node_modules; if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi;"
}

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', ("{0}:/home/agent/.claude.json" -f $claudeJsonCopy),
    '-v', ("{0}:/home/agent/.claude/.credentials.json" -f $credsFile),
    '-v', ("{0}:/home/agent/.claude/projects" -f $historyDir),
    '-v', 'pm-cache:/home/agent/.npm',
    '-v', 'pnpm-store-cache:/home/agent/.pnpm-store'
)
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
if ($tz) { $runArgs += @('-e', "TZ=$tz") }
if ($GPU) { $runArgs += @('--gpus', 'all') }

# Disable background-agent worktree isolation unless explicitly enabled.
# jq creates the worktree object if the baked settings.json lacks one.
$worktreeOverride = if ($EnableBgIsolation) { '' } else {
    'jq ''.worktree.bgIsolation = "none"'' /home/agent/.claude/settings.json > /tmp/settings.json.new && mv /tmp/settings.json.new /home/agent/.claude/settings.json; '
}

$permFlag = if ($DangerouslySkipPermissions) { '--dangerously-skip-permissions' } else { '--permission-mode auto --allow-dangerously-skip-permissions' }
$claudeCommand = "$pmSetup $nmInstall $worktreeOverride exec claude $permFlag `"`$@`""
$runArgs += @($Image, 'sh', '-lc', $claudeCommand, 'claude-run')
if ($PSBoundParameters.ContainsKey('Prompt')) { $runArgs += $Prompt }

Write-Host "==> $Engine $($runArgs -join ' ')"
try {
    & $Engine @runArgs
    $engineExit = $LASTEXITCODE
} finally {
    # The copy carries the host's OAuth account metadata — do not leave it in
    # temp. `finally` so it is removed on Ctrl-C / engine failure too.
    Remove-Item -LiteralPath $claudeJsonCopy -Force -ErrorAction SilentlyContinue
}
if ($engineExit -ne 0) { throw "$Engine run failed ($engineExit)" }
