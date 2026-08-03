# Mounts the current directory as the container workspace and drops into
# `pi` interactively.
#
# Persists across --rm: per-project
# session history (named volume keyed by a hash of the workspace path — pi
# organizes sessions by working directory, and the container's cwd is always
# /workspace, so a single shared volume would bleed session history across
# unrelated host projects; a per-project volume avoids that), and the npm
# cache. When the host workspace has a node_modules, it is masked with a
# per-project named volume and Linux-native deps are reinstalled inside (host
# node_modules left untouched). trust.json and the models-store.json cache are
# NOT persisted — they regenerate cheaply (a fresh container just re-asks
# project trust / re-fetches model catalogs).

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
# pwsh 7+) converts Windows-style ids. No conversion path on Windows
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

# Per-project session isolation: pi stores all session history under
# ~/.omp/agent/sessions/, organized by working directory. Since the container's
# cwd is always /workspace regardless of which host project is mounted, a
# single shared volume for that directory would mix every project's history
# together. Hash the host workspace path (same technique as the node_modules
# masking below) to give each real project its own named volume instead.
$shaSessions = [System.Security.Cryptography.SHA256]::Create()
$sessionHash = ([BitConverter]::ToString($shaSessions.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant()))) -replace '-','').Substring(0,12).ToLower()
$sessionsVol = "pi-sessions-$sessionHash"

# node_modules boundary: a host (Windows) node_modules bind-mounted into the
# Linux container carries win32-native bundler binaries that crash here. Only
# when the host actually has one do we mask it with a per-project NAMED
# volume (empty on first run) and install Linux-native deps inside —
# namespaced `pi-nmvol-` so it never shares the claude/opencode/cursor/codex
# templates' volume for the same workspace (per-suite isolation).
$maskNodeModules = Test-Path (Join-Path $Workspace 'node_modules')
$nmInstall = ""
if ($maskNodeModules) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Workspace.ToLowerInvariant())
    $hash  = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,12).ToLower()
    $nmVol = "pi-nmvol-$hash"
    $nmInstall = "if [ -z `"`$(ls -A /workspace/node_modules 2>/dev/null)`" ]; then echo '[run] node_modules masked + empty -> installing Linux-native deps'; if [ -f pnpm-lock.yaml ]; then pnpm install; elif [ -f yarn.lock ]; then yarn install; else npm install; fi; fi; "
}

# Forward whichever provider credential env vars are set on the host. Never
# baked into the image — only passed at `docker run` time, same principle as
# the other suites' API-key passthrough. List taken from pi's own
# docs/providers.md env-var table (Anthropic, OpenAI, Bedrock, Azure, Vertex,
# Cloudflare, OpenRouter, and the rest of the built-in provider catalog), plus
# the build-time-installed pi packages' own env vars (CURSOR_API_KEY for
# pi-cursor-sdk; the search-provider keys for pi-web-access — see README "Pi
# packages").
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

# codegraph has no --target=pi (see skills/codegraph/SKILL.md) — pi has no MCP
# client to wire a server into anyway, so there is no `codegraph install`
# step here (unlike claude/opencode/cursor). `codegraph init` still builds the
# local graph so the baked codegraph skill can query it via plain CLI calls.
# `;` not `&&`: a codegraph hiccup (e.g. no network) must not block pi.
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
