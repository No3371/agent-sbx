# Mount the current directory as /workspace and launch pi. Per-project session
# volumes prevent history crossing workspace boundaries. Host node_modules is
# masked when necessary for Linux dependencies; transient trust and model state
# is not persisted.

[CmdletBinding()]
param(
    [string]$Image     = 'sbx-omp:v1',
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

# Per-project session isolation: pi stores all session history under
# ~/.omp/agent/sessions/, organized by working directory. Since the container's
# cwd is always /workspace regardless of which host project is mounted, a
# single shared volume for that directory would mix every project's history
# together. Hash the host workspace path (same technique as the node_modules
# masking below) to give each real project its own named volume instead.
$shaSessions = [System.Security.Cryptography.SHA256]::Create()
$sessionHash = ([BitConverter]::ToString($shaSessions.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant()))) -replace '-','').Substring(0,12).ToLower()
$sessionsVol = "pi-sessions-$sessionHash"

# If the host has Windows node_modules, mask it with a per-project named volume
# and install Linux-native dependencies inside the container.
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
$nmInstall = ""
if ($maskNodeModules) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash  = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "pi-nmvol-$hash"
    $nmInstall = "if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi; "
}

# Forward provider and installed-package credential variables documented by pi
# only at container run time; never bake them into the image.
$providerEnvVars = @(
    'ANTHROPIC_API_KEY','ANT_LING_API_KEY','AZURE_OPENAI_API_KEY','AZURE_OPENAI_BASE_URL',
    'AZURE_OPENAI_RESOURCE_NAME','AZURE_OPENAI_API_VERSION','AZURE_OPENAI_DEPLOYMENT_NAME_MAP',
    'OPENAI_API_KEY','DEEPSEEK_API_KEY','NVIDIA_API_KEY','GEMINI_API_KEY',
    'AWS_BEARER_TOKEN_BEDROCK','AWS_PROFILE','AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_REGION',
    'AWS_ENDPOINT_URL_BEDROCK_RUNTIME','AWS_BEDROCK_SKIP_AUTH','AWS_BEDROCK_FORCE_HTTP1','AWS_BEDROCK_FORCE_CACHE',
    'MISTRAL_API_KEY','GROQ_API_KEY','CEREBRAS_API_KEY',
    'CLOUDFLARE_API_KEY','CLOUDFLARE_ACCOUNT_ID','CLOUDFLARE_GATEWAY_ID',
    'XAI_API_KEY','OPENROUTER_API_KEY','AI_GATEWAY_API_KEY',
    'ZAI_API_KEY','ZAI_CODING_CN_API_KEY','OPENCODE_API_KEY','RADIUS_API_KEY','HF_TOKEN',
    'FIREWORKS_API_KEY','TOGETHER_API_KEY','KIMI_API_KEY',
    'MINIMAX_API_KEY','MINIMAX_CN_API_KEY',
    'XIAOMI_API_KEY','XIAOMI_TOKEN_PLAN_CN_API_KEY','XIAOMI_TOKEN_PLAN_AMS_API_KEY','XIAOMI_TOKEN_PLAN_SGP_API_KEY',
    'GOOGLE_CLOUD_PROJECT','GOOGLE_CLOUD_LOCATION',
    'PI_SKIP_VERSION_CHECK','PI_TELEMETRY','PI_OFFLINE',
    'CURSOR_API_KEY',
    'BRAVE_API_KEY','EXA_API_KEY','PERPLEXITY_API_KEY','TAVILY_API_KEY','PARALLEL_API_KEY','GOOGLE_GEMINI_BASE_URL'
)
$envForward = @()
foreach ($name in $providerEnvVars) {
    $val = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrEmpty($val)) { $envForward += @('-e', "$name=$val") }
}
# GOOGLE_APPLICATION_CREDENTIALS points at a file path on the host — the env
# var alone is useless in the container without the file itself, so it is
# deliberately not forwarded here. Use `gcloud auth application-default login`
# inside the container instead, or bind-mount the key file manually.

$runArgs = @(
    'run', '-it', '--rm',
    '-v', ("{0}:/workspace" -f $Workspace),
    '-w', '/workspace',
    '-v', "${sessionsVol}:/root/.omp/agent/sessions",
    '-v', 'pi-pm-cache:/root/.npm',
    '-v', 'pi-pnpm-store-cache:/root/.pnpm-store'
)
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }
if ($tz) { $runArgs += @('-e', "TZ=$tz") }
if ($GPU) { $runArgs += @('--gpus', 'all') }
$runArgs += $envForward

# Codegraph has no --target=pi, so initialize its local graph on first run for
# CLI skill queries. Use `;` so initialization failure does not block pi.
$bootstrap = $pmSetup + $nmInstall +
             "test -d .codegraph || codegraph init; " +
             "exec /usr/local/bin/omp launch"

$runArgs += @(
    '--entrypoint', '/usr/bin/tini',
    $Image,
    '--',
    'sh', '-lc', $bootstrap
)

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
