# Run the baked opencode-custom image without sbx.
#
# Mounts the current directory as the container workspace and drops into
# `opencode` interactively. Persists auth by bind-mounting the single host
# auth file (NOT the whole ~/.local/share/opencode dir, which would shadow
# the container's own state dirs).
#
# First run: authenticate once inside the container (`opencode auth login`);
# the token lands in the native host auth.json and persists. The native state
# directory is also mounted, so the selected model/variant follows into it.
#
# Persists across --rm: provider auth + model preferences (host
# ~/.local/share/opencode/auth.json + ~/.local/state/opencode), session history
# (project-local .opencode/opencode.db, opencode's SQLite store),
# and package-manager / opencode plugin caches (named volumes). When the host
# workspace has a node_modules, it is masked with a per-project named volume and
# Linux-native deps are reinstalled inside (host node_modules left untouched).
#
# SECURITY: .local/share/opencode/auth.json carries live provider credentials.
# Treat it like an SSH key — never commit or share it (any other
# process/container reading %USERPROFILE% can read the plaintext token). The project-local
# .opencode/opencode.db can hold conversation content — add `.opencode/` to the
# project's .gitignore if reusing this launcher outside this repo.

[CmdletBinding()]
param(
    [string]$Image     = 'opencode-custom:v1',
    [string]$Engine    = 'docker',
    [string]$Workspace = $PWD.Path,
    [switch]$GPU
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command $Engine -ErrorAction SilentlyContinue)) {
    throw "$Engine not found on PATH"
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

# Map OpenCode's native host state: auth lives in data, while the selected
# model/variant lives in state/model.json. Keep auth as a file mount so the
# project-local session DB can remain separate.
$dataDir  = Join-Path $env:USERPROFILE '.local\share\opencode'
$authFile = Join-Path $dataDir 'auth.json'
$stateDir = Join-Path $env:USERPROFILE '.local\state\opencode'

# BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a UTF-8 BOM,
# which can make a strict JSON parser choke on `{}` before the first real
# write.
if (-not (Test-Path $dataDir))  { New-Item -ItemType Directory -Force $dataDir | Out-Null }
if (-not (Test-Path $authFile)) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($authFile, '{}', $utf8NoBom)
}
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force $stateDir | Out-Null }

# Project-local session history. opencode 1.17 stores all sessions in a single
# SQLite DB at ~/.local/share/opencode/opencode.db (verified against opencode
# 1.17.14 — NOT a per-project storage/ dir; the plan's assumption 4 was wrong).
# Bind-mount just that DB file (individual-path, like auth.json — never the
# whole share dir, which would shadow baked state and collide with the auth
# file-mount) into the project's .opencode/ so history travels with the project
# and survives --rm. A 0-byte file is a valid empty SQLite DB. The -wal/-shm
# sidecars live in the container and checkpoint into the .db on clean exit; a
# hard kill can lose the most recent uncommitted turn.
$historyDb     = Join-Path $Workspace '.opencode\opencode.db'
$historyParent = Split-Path $historyDb -Parent
if (-not (Test-Path $historyParent)) { New-Item -ItemType Directory -Force $historyParent | Out-Null }
if (-not (Test-Path $historyDb))     { [System.IO.File]::WriteAllBytes($historyDb, @()) }

# Shared package-manager + opencode plugin caches (named volumes, per-suite).
# Namespaced with an `opencode-` prefix so each suite keeps its own caches: this
# store never shares a volume with the claude template's for the same name —
# independent lifecycles, not a base/libc difference (redteam F4). Fresh named volumes mount root:root; chown every one the non-root
# agent writes to — npm cache (~/.npm), pnpm store, opencode's Bun plugin cache
# (~/.cache/opencode) — each launch (redteam F5). Unlike claude, this image does
# not pre-warm ~/.npm, so a fresh opencode-pm-cache volume is root:root and npm
# install fails without this chown. pnpm otherwise defaults its store into
# /workspace, so relocate it to the HOME volume. pnpm baked in (Step 2).
# `/home/agent/.cache` itself is also chowned. The image bakes this directory at
# build time: `playwright install --with-deps chromium` runs as root with
# HOME=/home/agent, creating `.cache/ms-playwright` (and the `.cache` parent)
# root:root, and the Dockerfile chowns it back to agent right after (D1). So the
# parent already exists agent-owned in the image before the container starts. The
# runtime chown here fixes ownership on top of that baked-in state rather than a
# directory the image never touched: run.ps1 mounts the `opencode-cache` named
# volume onto the nested `.cache/opencode` leaf, and a fresh volume mounts
# root:root — this is the only one of the three suites that mounts anything under
# `.cache/`, so it's the only one exposed to it. F5's chown covered the volume
# leaf but not the parent; any tool that caches to a sibling under `~/.cache`
# needs the parent agent-owned to `mkdir` there. With D1's build-time bake the
# parent is already agent-owned, so chowning it here is a defensive no-op; the
# leaf chown stays load-bearing for the fresh volume.
$pmSetup = "sudo chown agent:agent /home/agent/.cache /home/agent/.npm /home/agent/.pnpm-store /home/agent/.cache/opencode 2>/dev/null; pnpm config set store-dir /home/agent/.pnpm-store 2>/dev/null || true;"

# node_modules boundary: a host (Windows) node_modules bind-mounted into the
# Linux container carries win32-native binaries that crash here. Only when the
# host actually has one do we mask it with a per-project NAMED volume (empty on
# first run) and install Linux-native deps inside — namespaced `opencode-nmvol-`
# so it never shares the claude template's volume for the same workspace
# (per-suite isolation, redteam F4). A fresh named volume mounts root:root while we run as
# agent, so chown it before the empty-check. Absent -> plain bind-mount.
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
$nmInstall = ""
if ($maskNodeModules) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash  = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "opencode-nmvol-$hash"
    $nmInstall = "sudo chown agent:agent /workspace/node_modules; if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi;"
}

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', ("{0}:/home/agent/.local/share/opencode/auth.json" -f $authFile),
    '-v', ("{0}:/home/agent/.local/state/opencode" -f $stateDir),
    '-v', ("{0}:/home/agent/.local/share/opencode/opencode.db" -f $historyDb),
    '-v', 'opencode-cache:/home/agent/.cache/opencode',
    '-v', 'opencode-pm-cache:/home/agent/.npm',
    '-v', 'opencode-pnpm-store-cache:/home/agent/.pnpm-store'
)
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
if ($tz) { $runArgs += @('-e', "TZ=$tz") }
if ($GPU) { $runArgs += @('--gpus', 'all') }

# codegraph install wires the MCP server into opencode's config; codegraph
# init builds the /workspace graph on first run (guarded by .codegraph/ so it
# doesn't re-index every launch — auto-sync keeps it fresh after that).
# `;` not `&&`: a codegraph hiccup (e.g. no network) must not block opencode.
$bootstrap = "$pmSetup $nmInstall " +
             "codegraph install --yes --target=opencode --location=global; " +
             "test -d .codegraph || codegraph init; " +
             "exec opencode"
$runArgs += @($Image, 'sh', '-lc', $bootstrap)

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
