# Stages host ~/.claude payload into ./context/.claude for the podman build.
# Maps: settings.json (rewritten + filtered), skills, agents, tools, commands,
#       hooks, plugins.
# Excludes: .credentials.json, .claude.json, sessions, history, projects,
#           cache, statsig, telemetry — sbx manages those.
#
# Settings filtering rules (applied before writing to context):
#   - Keeps: enabledPlugins (plugins/ is now baked into image)
#   - Strips: skipAutoPermissionPrompt (permission posture is a template-author
#             decision, not silently inherited from host)
#   - statusLine: command rewritten — git-bash node path → bare `node`,
#             cygpath -w wrappers dropped. Kept as-is otherwise.
#   - Hooks: each hook command is path-rewritten (Win → Linux), then the hook
#             entry is dropped if its command references a path that does NOT
#             exist in the staged image FS layout.
#   - mcpServers: commands path-rewritten (Win npx-cache → bare name); entries
#             with no Linux mapping are dropped with a warning.
#   - project .mcp.json: merged from repo root (one level up from this script),
#             command paths rewritten — covers project-level MCP installs like
#             context-mode. Project entries win over global on name collision.

[CmdletBinding()]
param(
    [string]$HostClaudeDir = "$env:USERPROFILE\.claude",
    [string]$Destination   = (Join-Path $PSScriptRoot 'context\.claude')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $HostClaudeDir)) {
    throw "Host .claude dir not found: $HostClaudeDir"
}

$dirs = @('skills', 'agents', 'tools', 'commands', 'hooks', 'plugins')

# Recreate stage dirs so COPY shape is stable even when a host dir is absent.
# Seed a .keep file so BuildKit/Buildah never sees an empty COPY source.
foreach ($name in $dirs) {
    $target = Join-Path $Destination $name
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    # Placeholder ensures COPY works even if no host files are copied in.
    Set-Content -Path (Join-Path $target '.keep') -Value '' -Encoding UTF8
}

# Filename patterns that must never be baked into the image, regardless of directory.
# Applies during copy of any staged dir (especially plugins/).
$credentialExcludePatterns = @(
    '*.credentials', '.credentials', 'auth.json', '.token', '*.token',
    'secrets.json', '*.key', '*.pem', '*.p12', '*.pfx', 'token.json', '.auth'
)
$excludedDirectoryNames = @('.github', '.git', 'node_modules')

function Test-CredentialFileName([string]$name) {
    foreach ($pat in $credentialExcludePatterns) {
        if ($name -like $pat) { return $true }
    }
    return $false
}

function Copy-ItemFiltered([string]$sourcePath, [string]$destinationDir) {
    $item = Get-Item -LiteralPath $sourcePath -Force

    if ($item.PSIsContainer) {
        if ($excludedDirectoryNames -contains $item.Name) {
            Write-Host "[prepare] skipping excluded dir: $($item.FullName)"
            return
        }

        $target = Join-Path $destinationDir $item.Name
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        $children = Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            Copy-ItemFiltered $child.FullName $target
        }
        return
    }

    if (Test-CredentialFileName $item.Name) {
        Write-Warning "[prepare] CREDENTIAL RISK: skipping $($item.FullName)"
        return
    }

    Copy-Item -LiteralPath $item.FullName -Destination $destinationDir -Force
}

foreach ($name in $dirs) {
    $src = Join-Path $HostClaudeDir $name
    $dst = Join-Path $Destination $name
    if (Test-Path $src) {
        $items = Get-ChildItem -Path $src -Force -ErrorAction SilentlyContinue
        if ($items) {
            Write-Host "[prepare] mapping $name ($($items.Count) entries)"
            foreach ($item in $items) {
                Copy-ItemFiltered $item.FullName $dst
            }
        } else {
            Write-Host "[prepare] $name on host is empty"
        }
    } else {
        Write-Host "[prepare] no $name dir on host"
    }
}

# Host .sh files may carry CRLF line endings (authored on Windows) — bash
# rejects a `\r` in the shebang line outright. .gitattributes normalizes *.sh
# in *this* repo, but skills/hooks/scripts staged here come from the host
# ~/.claude tree, so normalize them explicitly.
$utf8NoBomLocal = New-Object System.Text.UTF8Encoding $false
$shFiles = Get-ChildItem -Path $Destination -Recurse -Force -Filter '*.sh' -ErrorAction SilentlyContinue
foreach ($f in $shFiles) {
    $content = [System.IO.File]::ReadAllText($f.FullName)
    if ($content.Contains("`r`n")) {
        [System.IO.File]::WriteAllText($f.FullName, ($content -replace "`r`n", "`n"), $utf8NoBomLocal)
        Write-Host "[prepare] normalized CRLF -> LF: $($f.FullName.Substring($Destination.Length))"
    }
}

# --- plugins/*.json: rewrite Win install paths so claude-code resolves plugins in sandbox ---
# Claude Code persists absolute host paths in installed_plugins.json (installPath)
# and known_marketplaces.json (installLocation). Without rewriting, the sandbox
# sees `C:\Users\...` and fails to locate any plugin asset (MCPs included).
function Convert-WinPathToLinux([string]$p) {
    if ([string]::IsNullOrEmpty($p)) { return $p }
    $p = $p -replace '(?i)^C:\\Users\\[^\\]+\\\.claude', '/home/agent/.claude'
    $p = $p -replace '\\', '/'
    return $p
}

# Claude Code's JSON parser rejects UTF-8 BOM. PS 5.1 Set-Content -Encoding UTF8
# emits BOM, breaking the plugin/marketplace loader. Use .NET's UTF8 (false)
# constructor for BOMless writes consistently across PS versions.
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
function Write-JsonNoBom([string]$path, $obj) {
    $json = $obj | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($path, $json, $Utf8NoBom)
}

$installedPluginsPath = Join-Path $Destination 'plugins/installed_plugins.json'
if (Test-Path $installedPluginsPath) {
    $obj = Get-Content $installedPluginsPath -Raw | ConvertFrom-Json
    $rewrites = 0
    if ($obj.PSObject.Properties['plugins']) {
        foreach ($name in @($obj.plugins.PSObject.Properties.Name)) {
            foreach ($inst in @($obj.plugins.$name)) {
                if ($inst.PSObject.Properties['installPath']) {
                    $orig = $inst.installPath
                    $inst.installPath = Convert-WinPathToLinux $orig
                    if ($inst.installPath -ne $orig) { $rewrites++ }
                }
            }
        }
    }
    Write-JsonNoBom $installedPluginsPath $obj
    Write-Host "[prepare] installed_plugins.json: rewrote $rewrites installPath(s)"
}

# Drop plugin runtime caches keyed to host cwd/mtimes — stale + leak host paths.
# claude-hud regenerates these inside the sandbox on first use.
$pluginCachesToDrop = @(
    'plugins/claude-hud/config-cache',
    'plugins/claude-hud/transcript-cache'
)
foreach ($rel in $pluginCachesToDrop) {
    $cachePath = Join-Path $Destination $rel
    if (Test-Path $cachePath) {
        Remove-Item $cachePath -Recurse -Force
        Write-Host "[prepare] dropped host-state cache: $rel"
    }
}

$knownMarketplacesPath = Join-Path $Destination 'plugins/known_marketplaces.json'
if (Test-Path $knownMarketplacesPath) {
    $obj = Get-Content $knownMarketplacesPath -Raw | ConvertFrom-Json
    $rewrites = 0
    foreach ($name in @($obj.PSObject.Properties.Name)) {
        $entry = $obj.$name
        if ($entry.PSObject.Properties['installLocation']) {
            $orig = $entry.installLocation
            $entry.installLocation = Convert-WinPathToLinux $orig
            if ($entry.installLocation -ne $orig) { $rewrites++ }
        }
    }
    Write-JsonNoBom $knownMarketplacesPath $obj
    Write-Host "[prepare] known_marketplaces.json: rewrote $rewrites installLocation(s)"
}

# --- settings.json: rewrite host paths, filter unsafe/broken keys, inject hook ---
$settingsSrc = Join-Path $HostClaudeDir 'settings.json'
if (-not (Test-Path $settingsSrc)) {
    throw "host settings.json missing at $settingsSrc"
}

$settings = Get-Content $settingsSrc -Raw | ConvertFrom-Json

# skipAutoPermissionPrompt — permission posture must be an explicit template
# decision, never silently inherited from the developer's host config.
# Default in sandbox: prompt normally (false / absent).
if ($settings.PSObject.Properties['skipAutoPermissionPrompt']) {
    $settings.PSObject.Properties.Remove('skipAutoPermissionPrompt')
    Write-Host "[prepare] settings: stripped skipAutoPermissionPrompt (not inheriting host auto-approve)"
}

# Sandbox-only permission posture: run.ps1 launches with `--permission-mode
# auto` (Claude Code's built-in auto mode, v2.1.83+). In that mode, reads and
# working-directory file edits (Edit/Write/NotebookEdit) skip Claude Code's
# classifier and auto-approve with no prompt and no extra classifier call;
# Bash/shell and network calls still route through the classifier, which
# auto-runs what it judges safe and escalates/blocks what it doesn't — same
# as normal, just without a blanket allow. An explicit `ask` rule still
# forces a prompt in every mode including auto, so any Edit/Write/
# NotebookEdit ask rule inherited from host settings.json would silently
# defeat that — strip it. This is injected here rather than in host
# settings.json so it applies only to the built image, not the host's own
# Claude Code session.
if (-not $settings.PSObject.Properties['permissions']) {
    $settings | Add-Member -NotePropertyName permissions -NotePropertyValue ([pscustomobject]@{})
}
if ($settings.permissions.PSObject.Properties['ask']) {
    $settings.permissions.ask = @($settings.permissions.ask | Where-Object { @('Edit', 'Write', 'NotebookEdit') -notcontains $_ })
}
# classifyAllShell (v2.1.193+): auto mode already suspends blanket `Bash`/
# `Bash(*)` allow rules on entry, but this forces every Bash/PowerShell
# invocation through the classifier even if a narrower allow rule is ever
# added later, so shell coverage doesn't silently regress.
if (-not $settings.PSObject.Properties['autoMode']) {
    $settings | Add-Member -NotePropertyName autoMode -NotePropertyValue ([pscustomobject]@{})
}
if ($settings.autoMode.PSObject.Properties['classifyAllShell']) {
    $settings.autoMode.classifyAllShell = $true
} else {
    $settings.autoMode | Add-Member -NotePropertyName classifyAllShell -NotePropertyValue $true
}
Write-Host "[prepare] settings: injected sandbox permission posture (auto mode via run.ps1 --permission-mode auto; Edit/Write/NotebookEdit ask stripped; classifyAllShell on)"

function Rewrite-Command([string]$cmd) {
    if ([string]::IsNullOrEmpty($cmd)) { return $cmd }
    # node.exe (Win path) → node
    $cmd = $cmd -replace '(?i)"?C:[\\/]Program Files[\\/]nodejs[\\/]node\.exe"?', 'node'
    # node (git-bash drive-prefix path) → node
    $cmd = $cmd -replace '(?i)"?/c/Program Files/nodejs/node(\.exe)?"?', 'node'
    # node (WSL mount path) → node
    $cmd = $cmd -replace '(?i)"?/mnt/[a-z]/Program Files/nodejs/node(\.exe)?"?', 'node'
    # "$(cygpath -w "X")" → "X"  (statusLine wraps args for Windows node; on Linux drop
    # the cygpath substitution. Consume the outer wrapping quotes so we don't double them.)
    $cmd = $cmd -replace '"?\$\(\s*cygpath\s+-w\s+"([^"]+)"\s*\)"?', '"$1"'
    # host .claude → sandbox .claude
    $cmd = $cmd -replace '(?i)C:[\\/]Users[\\/][^\\/]+[\\/]\.claude', '/home/agent/.claude'
    # normalize backslashes (Windows paths only — leave shell/awk/sed escapes
    # like \t \n \r \\ \" \' \$ alone, or embedded commands like claude-hud's
    # `awk '{ print $1 "\t" $2 }'` get mangled into a literal "/t" and break)
    $cmd = $cmd -replace '\\(?![tnr\\"''\$])', '/'
    return $cmd
}

function Rewrite-McpServerCommand([string]$cmd) {
    if ([string]::IsNullOrEmpty($cmd)) { return $cmd }
    $cmd = Rewrite-Command $cmd
    # npm/npx one-off cache: .../npm-cache/_npx/<hash>/node_modules/.bin/<name>.cmd → <name>
    if ($cmd -match '(?i)[/\\]npm-cache[/\\]_npx[/\\][^/\\]+[/\\]node_modules[/\\]\.bin[/\\]([^/\\]+?)(?:\.cmd)?$') {
        return $Matches[1]
    }
    # Strip any remaining .cmd extension (npx.cmd → npx, node.cmd → node, etc.)
    $cmd = $cmd -replace '(?i)\.cmd$', ''
    return $cmd
}

# Paths that exist in the baked image and are safe for hooks to reference.
# A rewritten hook command must begin with (or contain as a word) one of these
# prefixes to be kept; anything referencing host-only plugin paths is dropped.
$allowedPathPrefixes = @(
    '/home/agent/.claude/hooks/',
    '/home/agent/.claude/plugins/',
    '/home/agent/.local/bin/'
)

# Node built-in modules that resolve without a node_modules tree. Used by
# Test-HookFileSelfContained to decide whether a .mjs/.cjs hook is safe to run
# from an isolated /home/agent/.claude/hooks/ location.
$nodeBuiltins = @(
    'assert', 'async_hooks', 'buffer', 'child_process', 'cluster', 'console',
    'crypto', 'dgram', 'dns', 'events', 'fs', 'fs/promises', 'http', 'http2',
    'https', 'module', 'net', 'os', 'path', 'path/posix', 'path/win32',
    'perf_hooks', 'process', 'querystring', 'readline', 'repl', 'stream',
    'string_decoder', 'sys', 'timers', 'tls', 'tty', 'url', 'util', 'v8', 'vm',
    'worker_threads', 'zlib'
)

# Returns $true if the file's imports/requires resolve from Node built-ins or
# relative paths only — i.e. it can run without a co-located node_modules tree.
# Returns $false if any external (bare, non-builtin) module is referenced.
function Test-HookFileSelfContained([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    $src = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($src)) { return $true }
    $deps = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($m in [regex]::Matches($src, 'import\b[^''"]*from\s*[''"]([^''"]+)[''"]')) { $null = $deps.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($src, 'import\s*[''"]([^''"]+)[''"]'))               { $null = $deps.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($src, 'require\s*\(\s*[''"]([^''"]+)[''"]\s*\)'))    { $null = $deps.Add($m.Groups[1].Value) }
    foreach ($d in $deps) {
        if ($d.StartsWith('.') -or $d.StartsWith('/') -or $d.StartsWith('node:')) { continue }
        # Strip subpath (e.g. "lodash/get" → "lodash") for builtin lookup
        $head = $d.Split('/')[0]
        if ($script:nodeBuiltins -contains $d -or $script:nodeBuiltins -contains $head) { continue }
        return $false
    }
    return $true
}

function Test-HookCommandAllowed([string]$cmd) {
    if ([string]::IsNullOrEmpty($cmd)) { return $false }
    # Hook commands reference their script either as an already-rewritten
    # /home/agent path or (if authored portably) a literal $HOME — check both
    # forms for a file that actually made it into the staged hooks/ dir; a
    # deleted host script must not survive staging just because its command
    # string doesn't start with '/' (the bare-command fallback below).
    if ($cmd -match '(?:/home/agent|\$HOME)/\.claude/hooks/([^"'' ]+)') {
        $relPath = $Matches[1]
        $stagedFile = Join-Path $Destination "hooks/$relPath"
        if (-not (Test-Path $stagedFile)) {
            Write-Host "[prepare] settings: dropped hook referencing unstaged hook script: hooks/$relPath"
            return $false
        }
        # .mjs/.cjs/.js hooks may additionally fail at runtime if they import
        # external modules with no co-located node_modules — drop those too.
        if ($relPath -match '\.(m?js|cjs)$' -and -not (Test-HookFileSelfContained $stagedFile)) {
            Write-Host "[prepare] settings: dropped hook — external deps not resolvable: hooks/$relPath"
            return $false
        }
    }
    foreach ($prefix in $allowedPathPrefixes) {
        if ($cmd -like "*$prefix*") {
            # Extra check for plugins/ prefix: verify the referenced file actually
            # exists in the staged plugins directory (not just the prefix match).
            if ($prefix -eq '/home/agent/.claude/plugins/') {
                # Extract the path segment after the prefix
                if ($cmd -match '/home/agent/\.claude/plugins/([^"'' ]+)') {
                    $relPath = $Matches[1]
                    $stagedPath = Join-Path $Destination "plugins/$relPath"
                    if (-not (Test-Path $stagedPath)) {
                        Write-Host "[prepare] settings: dropped hook referencing unstaged plugin path: $relPath"
                        return $false
                    }
                }
            }
            if ($prefix -eq '/home/agent/.local/bin/') {
                if ($cmd -match '/home/agent/\.local/bin/([^"'' ]+)') {
                    $relPath = $Matches[1]
                    $stagedPath = Join-Path $PSScriptRoot "context/scripts/$relPath"
                    if (-not (Test-Path $stagedPath)) {
                        Write-Host "[prepare] settings: dropped hook referencing unstaged script: $relPath"
                        return $false
                    }
                }
            }
            return $true
        }
    }
    # Also allow bare commands (no path) — these resolve via PATH and are fine.
    if ($cmd -notmatch '^/') {
        return $true
    }
    return $false
}

# statusLine: rewrite host paths (git-bash node + cygpath wrap) and keep.
# Plugins are now baked into the image so the `plugins/cache/*/claude-hud/*`
# glob resolves inside the sandbox.
if ($settings.PSObject.Properties['statusLine']) {
    if ($settings.statusLine.PSObject.Properties['command']) {
        $settings.statusLine.command = Rewrite-Command $settings.statusLine.command
        Write-Host "[prepare] settings: rewrote statusLine command"
    }
}

if ($settings.PSObject.Properties['hooks']) {
    $filteredHooks = [pscustomobject]@{}
    foreach ($eventName in @($settings.hooks.PSObject.Properties.Name)) {
        $filteredEntries = [System.Collections.Generic.List[object]]::new()
        foreach ($matcherEntry in $settings.hooks.$eventName) {
            $rewrittenHooks = [System.Collections.Generic.List[object]]::new()
            foreach ($h in $matcherEntry.hooks) {
                if ($h.PSObject.Properties['command']) {
                    $h.command = Rewrite-Command $h.command
                    if (Test-HookCommandAllowed $h.command) {
                        $rewrittenHooks.Add($h)
                    } else {
                        Write-Host "[prepare] settings: dropped hook ($eventName) referencing non-image path: $($h.command)"
                    }
                } else {
                    $rewrittenHooks.Add($h)
                }
            }
            if ($rewrittenHooks.Count -gt 0) {
                # Rebuild matcher entry with filtered hooks list
                $newEntry = [pscustomobject]@{}
                foreach ($prop in $matcherEntry.PSObject.Properties) {
                    if ($prop.Name -eq 'hooks') {
                        $newEntry | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ($rewrittenHooks.ToArray())
                    } else {
                        $newEntry | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
                    }
                }
                $filteredEntries.Add($newEntry)
            }
        }
        $filteredHooks | Add-Member -NotePropertyName $eventName -NotePropertyValue ($filteredEntries.ToArray())
    }
    $settings.hooks = $filteredHooks
}

# --- mcpServers: rewrite host paths so server commands resolve in the sandbox ---
if ($settings.PSObject.Properties['mcpServers']) {
    $droppedServers = [System.Collections.Generic.List[string]]::new()
    foreach ($serverName in @($settings.mcpServers.PSObject.Properties.Name)) {
        $server = $settings.mcpServers.$serverName
        if ($server.PSObject.Properties['command']) {
            $orig = $server.command
            $server.command = Rewrite-McpServerCommand $orig
            if ($server.command -match '^[A-Za-z]:[/\\]') {
                Write-Warning "[prepare] mcpServers.${serverName}: dropping — no Linux mapping for: $orig"
                $droppedServers.Add($serverName)
            } elseif ($server.command -ne $orig) {
                Write-Host "[prepare] mcpServers.${serverName}: rewrote command → $($server.command)"
            }
        }
    }
    foreach ($d in $droppedServers) { $settings.mcpServers.PSObject.Properties.Remove($d) }
}

# --- project .mcp.json: merge project-level MCP servers (e.g. context-mode) ---
# $PSScriptRoot is claude/ (or codex/); go up one level to reach the repo root.
$projectMcpPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.mcp.json'
if (Test-Path $projectMcpPath) {
    $projectMcp = Get-Content $projectMcpPath -Raw | ConvertFrom-Json
    if ($projectMcp.PSObject.Properties['mcpServers']) {
        if (-not $settings.PSObject.Properties['mcpServers']) {
            $settings | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{})
        }
        $mergedCount = 0
        foreach ($serverName in @($projectMcp.mcpServers.PSObject.Properties.Name)) {
            $server = $projectMcp.mcpServers.$serverName
            if ($server.PSObject.Properties['command']) {
                $server.command = Rewrite-McpServerCommand $server.command
            }
            if ($settings.mcpServers.PSObject.Properties[$serverName]) {
                $settings.mcpServers.PSObject.Properties.Remove($serverName)
            }
            $settings.mcpServers | Add-Member -NotePropertyName $serverName -NotePropertyValue $server
            $mergedCount++
        }
        Write-Host "[prepare] project .mcp.json: merged $mergedCount mcpServer(s)"
    }
} else {
    Write-Host "[prepare] no project .mcp.json found at $projectMcpPath"
}

# Stage both settings.json and settings.local.json in the build context.
# Dockerfile drops settings.json at ~/.claude/ (user-level; sbx clobbers this
# at sandbox boot but it's useful for bare-podman runs) and stashes
# settings.local.json at /home/agent/.claude-bake/. merge-claude-settings.sh
# (sourced from /etc/sandbox-persistent.sh via BASH_ENV / CLAUDE_ENV_FILE)
# merges the baked copy back onto sbx's baseline before claude reads settings.
Write-JsonNoBom (Join-Path $Destination 'settings.json')       $settings
Write-JsonNoBom (Join-Path $Destination 'settings.local.json') $settings

Write-Host "[prepare] staged at $Destination"
Write-Host "[prepare] next: ./build.ps1 -Image <repo>/cc-custom:v1 -Push"
