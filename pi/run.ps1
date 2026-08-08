# Mounts the current directory as the container workspace and drops into
# `pi` interactively.
#
# Persists across --rm: host auth (~/.pi/agent/auth.json, individual file
# mount), per-project session history (project-local .pi\sessions bind mount),
# and the npm/pnpm caches (named volumes). When the host workspace has a
# node_modules, it is masked with a per-project named volume and Linux-native
# deps are reinstalled inside (host node_modules left untouched).
# settings.json and models-store.json are NOT mounted — prepare.ps1 stages
# them into the image as build-time defaults; in-container changes are
# ephemeral and the model catalog regenerates cheaply.

[CmdletBinding()]
param(
    [string]$Image     = 'sbx-pi:v1',
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

# pi's native host state all lives under ~/.pi/agent/: auth.json (provider
# credentials — excluded from the build context by prepare.ps1, mounted here
# instead), settings.json + models-store.json (baked by prepare.ps1 as
# defaults, not mounted), and sessions/ (handled below). Keep auth as an
# individual file mount — never the whole ~/.pi dir, which would shadow the
# baked config/skills.
$piAgentDir = Join-Path $env:USERPROFILE '.pi\agent'
$authFile   = Join-Path $piAgentDir 'auth.json'

# BOM-less write: PS5.1's `Set-Content -Encoding utf8` prefixes a UTF-8 BOM,
# which can make a strict JSON parser choke on `{}` before the first real
# write.
if (-not (Test-Path $piAgentDir)) { New-Item -ItemType Directory -Force $piAgentDir | Out-Null }
if (-not (Test-Path $authFile)) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($authFile, '{}', $utf8NoBom)
}

# Project-local session history. pi organizes ~/.pi/agent/sessions/ into
# per-cwd subdirs; the container's cwd is always /workspace regardless of
# which host project is mounted, so a single shared mount would bleed session
# history across unrelated host projects (omp solves this with a per-project
# named volume). Bind-mount a project-local .pi\sessions dir over it instead —
# same isolation, and history travels with the project and survives --rm.
$sessionsDir = Join-Path $Workspace '.pi\sessions'
if (-not (Test-Path $sessionsDir)) { New-Item -ItemType Directory -Force $sessionsDir | Out-Null }

# Shared package-manager caches (named volumes, per-suite). NOT `pi-*`: the
# omp suite already owns that prefix (pi-pm-cache etc.), and sharing a volume
# across suites couples their lifecycles — `sbx-pi-` matches this suite's
# default image name (per-suite isolation, redteam F4). The container runs as
# root, so fresh root:root volumes need no ownership repair; only relocate
# pnpm's store, which otherwise defaults into /workspace.
$pmSetup = "pnpm config set store-dir /root/.pnpm-store 2>/dev/null || true;"

# node_modules boundary: a host (Windows) node_modules bind-mounted into the
# Linux container carries win32-native binaries that crash here. Only when the
# host actually has one do we mask it with a per-project NAMED volume (empty on
# first run) and install Linux-native deps inside — namespaced `sbx-pi-nmvol-`
# so it never shares another suite's volume for the same workspace (per-suite
# isolation, redteam F4). A fresh named volume mounts root:root — same as the
# runtime user, so no ownership repair. Absent -> plain bind-mount.
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
$nmInstall = ""
if ($maskNodeModules) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash  = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "sbx-pi-nmvol-$hash"
    $nmInstall = "if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi;"
}

# Forward whichever provider credential env vars are set on the host — pi's
# env-var auth path complements the mounted auth.json. Never baked into the
# image — only passed at run time. List taken from pi's own docs/providers.md
# env-var table (Anthropic, OpenAI, Bedrock, Azure, Vertex, Cloudflare,
# OpenRouter, and the rest of the built-in provider catalog), plus pi-package
# env vars (CURSOR_API_KEY for pi-cursor-sdk; the search-provider keys for
# pi-web-access) so they work if those packages are staged in ~/.pi.
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
    '-v', ("{0}:/root/.pi/agent/auth.json" -f $authFile),
    '-v', ("{0}:/root/.pi/agent/sessions" -f $sessionsDir),
    '-v', 'sbx-pi-pm-cache:/root/.npm',
    '-v', 'sbx-pi-pnpm-store-cache:/root/.pnpm-store'
)
if ($maskNodeModules) { $runArgs += @('-v', "${nmVol}:/workspace/node_modules") }
# No --userns=keep-id under podman (contrast the agent-user suites): rootless
# podman already maps container root to the host user, so bind-mount writes
# come out host-owned; keep-id would shift root into the subuid range instead.
if ($tz) { $runArgs += @('-e', "TZ=$tz") }
if ($GPU) { $runArgs += @('--gpus', 'all') }
$runArgs += $envForward

# codegraph's MCP wiring happens at image build (a `codegraph serve --mcp`
# entry in ~/.pi/agent/mcp.json, served to pi via pi-mcp-adapter — there is
# no `codegraph install --target=pi`), so no install step here. `codegraph
# init` still builds the /workspace graph on first run (guarded by .codegraph/
# so it doesn't re-index every launch — auto-sync keeps it fresh after that);
# the MCP server needs that initialized index to answer.
# `;` not `&&`: a codegraph hiccup (e.g. no network) must not block pi.
$bootstrap = "$pmSetup $nmInstall " +
             "test -d .codegraph || codegraph init; " +
             "exec pi"

# The image ENTRYPOINT is `tini -- pi`; override it so the bootstrap shell
# replaces pi as the payload while keeping tini as PID 1.
$runArgs += @(
    '--entrypoint', '/usr/bin/tini',
    $Image,
    '--',
    'sh', '-lc', $bootstrap
)

Write-Host "==> $Engine $($runArgs -join ' ')"
& $Engine @runArgs
if ($LASTEXITCODE -ne 0) { throw "$Engine run failed ($LASTEXITCODE)" }
