# Run the baked codex-custom image with the current directory as /workspace.
# Do not mount host auth.json: incomplete device-auth state can pass login status
# but fail TUI startup, so authenticate inside each ephemeral container.

[CmdletBinding()]
param(
    [string]$Image     = 'codex-custom:v1',
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

# If the host has Windows node_modules, mask it with a per-project named volume
# because native binaries cannot run in Linux. Chown a fresh volume and install
# Linux dependencies when empty. pnpm is not baked into this image, so its
# projects fail with an explicit error.
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
$nmInstall = ""
if ($maskNodeModules) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash  = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "nmvol-$hash"
    $nmInstall = "sudo chown agent:agent /workspace/node_modules; if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then corepack pnpm install || pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi; "
}

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', 'pm-cache:/home/agent/.npm'
)
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
if ($tz) { $runArgs += @('-e', "TZ=$tz") }
if ($GPU) { $runArgs += @('--gpus', 'all') }

# codegraph install wires the MCP server into ~/.codex/config.toml; codegraph
# init builds the /workspace graph on first run (guarded by .codegraph/ so it
# doesn't re-index every launch — auto-sync keeps it fresh after that).
# `;` not `&&`: a codegraph hiccup (e.g. no network) must not block codex.
#
# --device-auth (URL + one-time code) instead of the default browser flow,
# which starts a callback server on localhost:1455 inside the container that
# the host browser can't reach without publishing that port.
$bootstrap = $nmInstall +
             "codegraph install --yes --target=codex --location=global; " +
             "test -d .codegraph || codegraph init; " +
             "codex login --device-auth; exec codex --dangerously-bypass-approvals-and-sandbox"
$runArgs += @($Image, 'sh', '-lc', $bootstrap)

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
