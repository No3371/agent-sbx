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

# Filename patterns that must never be baked into the image, regardless of directory.
# Handed to robocopy /XF below, which matches them at every depth.
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

# Staging is INCREMENTAL. This used to delete each stage dir and re-copy the host
# tree file-by-file via Copy-Item — ~2350 files / 32MB for a typical ~/.claude,
# and PowerShell's per-cmdlet overhead dominates when the files are this small.
# robocopy compares size + write time per file in native code and transfers only
# what differs, so an unchanged host tree costs a stat sweep instead of a full
# re-copy (measured 21.1s -> 0.6s here; the gap is wider on a cold file cache or
# with on-access AV inspecting 32MB of fresh writes).
#
# /MIR also purges dest entries whose source is gone — the property the old
# delete-then-copy shape bought, kept without paying the deletion.
#
# robocopy exit codes: 0 = nothing to do | 1 = copied | 2 = purged extras |
# 3 = both | >= 8 = real failure. Everything below 8 is success.
if (-not (Get-Command robocopy -ErrorAction SilentlyContinue)) {
    throw "robocopy not found on PATH — required for staging."
}
# PS 7.3+ can promote a nonzero native exit code to a terminating error under
# $ErrorActionPreference='Stop'. Robocopy's SUCCESS codes are nonzero, so opt out
# for the rest of this script. (No-op on PS 5.1, where the variable is absent.)
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$rcFlags = @('/MIR', '/MT:16', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH', '/NJS')
$rcExcludeDirs = @('/XD') + $excludedDirectoryNames
# .keep exists only on the dest side (seeded below). An /XF entry is also shielded
# from /MIR's purge, so listing it keeps the placeholder stable across runs.
$rcExcludeFiles = @('/XF', '.keep') + $credentialExcludePatterns

foreach ($name in $dirs) {
    $src = Join-Path $HostClaudeDir $name
    $dst = Join-Path $Destination $name

    if (Test-Path $src) {
        robocopy $src $dst @rcFlags @rcExcludeDirs @rcExcludeFiles | Out-Null
        $rc = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($rc -ge 8) { throw "robocopy failed staging ${name}: exit $rc" }
        $verdict = switch ($rc) {
            0       { 'unchanged' }
            1       { 'updated' }
            2       { 'stale entries purged' }
            3       { 'updated + purged' }
            default { "exit $rc" }
        }
        Write-Host "[prepare] $name -> $verdict"
    } else {
        Write-Host "[prepare] no $name dir on host"
    }

    # Stage dir must exist even when the host has none, so COPY shape stays
    # stable; the .keep placeholder stops BuildKit/Buildah seeing an empty COPY
    # source. Written after robocopy so /MIR cannot race the placeholder.
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Set-Content -Path (Join-Path $dst '.keep') -Value '' -Encoding UTF8
}

# Destination-side credential sweep. /XF stops credential files being copied in,
# but an /XF entry is equally shielded from /MIR's purge — so one staged by an
# older revision of this script would otherwise persist indefinitely. Delete on
# sight. This also restores the reporting the old per-file CREDENTIAL RISK
# warning provided: robocopy's own exclusion is silent.
foreach ($name in $dirs) {
    $dstDir = Join-Path $Destination $name
    if (-not (Test-Path $dstDir)) { continue }
    Get-ChildItem -LiteralPath $dstDir -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { Test-CredentialFileName $_.Name } |
        ForEach-Object {
            Write-Warning "[prepare] CREDENTIAL RISK: removing staged $($_.FullName)"
            Remove-Item -LiteralPath $_.FullName -Force
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

# --- Build-time install pilot (see 2607100235-context-mode-build-time-install-pilot-plan.md) ---
# Marketplaces listed here are NOT vendored from the host. The Dockerfile installs
# their plugins fresh via `claude plugin install`, so paths/caches/hook commands are
# whatever Claude Code writes on Linux — nothing to rewrite. Strip their payload dirs
# and registry entries so the image has no host-baked state for them and the in-container
# install writes its own. Extend this list (not fork the logic) for Option A cutover.
# NOTE: defined here (not near $pluginCachesToDrop) because the installed_plugins.json
# filter below references it — PowerShell needs it in scope before first use.
$buildTimeInstallMarketplaces = @('context-mode')

$installedPluginsPath = Join-Path $Destination 'plugins/installed_plugins.json'
if (Test-Path $installedPluginsPath) {
    $obj = Get-Content $installedPluginsPath -Raw | ConvertFrom-Json
    if ($obj.PSObject.Properties['plugins']) {
        foreach ($name in @($obj.plugins.PSObject.Properties.Name)) {
            $mp = ($name -split '@')[-1]
            if ($buildTimeInstallMarketplaces -contains $mp) {
                $obj.plugins.PSObject.Properties.Remove($name)
                Write-Host "[prepare] installed_plugins.json: removed $name (build-time install)"
            }
        }
    }
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

# Strip payload dirs for build-time-installed marketplaces (see $buildTimeInstallMarketplaces).
foreach ($mp in $buildTimeInstallMarketplaces) {
    foreach ($sub in @("plugins/cache/$mp", "plugins/marketplaces/$mp")) {
        $p = Join-Path $Destination $sub
        if (Test-Path $p) {
            Remove-Item $p -Recurse -Force
            Write-Host "[prepare] dropped build-time-install payload: $sub"
        }
    }
}

$knownMarketplacesPath = Join-Path $Destination 'plugins/known_marketplaces.json'
if (Test-Path $knownMarketplacesPath) {
    $obj = Get-Content $knownMarketplacesPath -Raw | ConvertFrom-Json
    foreach ($mp in $buildTimeInstallMarketplaces) {
        if ($obj.PSObject.Properties[$mp]) {
            $obj.PSObject.Properties.Remove($mp)
            Write-Host "[prepare] known_marketplaces.json: removed $mp (build-time install)"
        }
    }
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

# Pre-approve tools that are baked into the image, installed deliberately, and
# have no path to the network or to files outside the workspace on their own.
# A `permissions.allow` match resolves before the classifier runs (same as a
# narrow `Bash(npm test)` allow rule per auto-mode-config docs), so these skip
# the classifier round-trip entirely instead of just skipping a forced prompt.
# Deliberately excludes anything that reaches out: ctx_fetch_and_index (fetches
# URLs) is left off the ctx_ list so out-of-sandbox network calls still hit the
# classifier, per this image's permission posture.
$autoApproveTools = @(
    'Agent', 'ToolSearch', 'Grep', 'Explore', 'AskUserQuestion'
    'mcp__codegraph__*',
    'mcp__plugin_context-mode_context-mode__ctx_batch_execute',
    'mcp__plugin_context-mode_context-mode__ctx_doctor',
    'mcp__plugin_context-mode_context-mode__ctx_execute',
    'mcp__plugin_context-mode_context-mode__ctx_execute_file',
    'mcp__plugin_context-mode_context-mode__ctx_index',
    'mcp__plugin_context-mode_context-mode__ctx_insight',
    'mcp__plugin_context-mode_context-mode__ctx_purge',
    'mcp__plugin_context-mode_context-mode__ctx_search',
    'mcp__plugin_context-mode_context-mode__ctx_stats',
    'mcp__plugin_context-mode_context-mode__ctx_upgrade'
)
if (-not $settings.permissions.PSObject.Properties['allow']) {
    $settings.permissions | Add-Member -NotePropertyName allow -NotePropertyValue @()
}
$existingAllow = @($settings.permissions.allow)
$settings.permissions.allow = @($existingAllow + ($autoApproveTools | Where-Object { $existingAllow -notcontains $_ }))
Write-Host "[prepare] settings: pre-approved no-network/in-workspace-only tools (skip classifier): $($autoApproveTools -join ', ')"

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

# --- plugin-bundled hooks.json: rewrite host paths baked in by plugin self-heal ---
# Plugins declare their own hooks in <plugin>/hooks/hooks.json (not settings.json).
# Some plugins (e.g. context-mode) self-normalize ${CLAUDE_PLUGIN_ROOT} placeholders
# to absolute host paths on first run — on this host that means Windows paths
# (C:/Program Files/nodejs/node.exe, C:/Users/BA/.claude/...) baked straight into
# the cached plugin copy. Copy-ItemFiltered stages that file verbatim, so without
# this pass those absolute Windows paths would ship inside the Linux image.
function Rewrite-CommandsInObject($obj) {
    $changed = $false
    if ($obj -is [System.Array]) {
        foreach ($item in $obj) {
            if (Rewrite-CommandsInObject $item) { $changed = $true }
        }
    } elseif ($obj -is [pscustomobject]) {
        foreach ($prop in $obj.PSObject.Properties) {
            if ($prop.Name -eq 'command' -and $prop.Value -is [string]) {
                $new = Rewrite-Command $prop.Value
                if ($new -ne $prop.Value) {
                    $prop.Value = $new
                    $changed = $true
                }
            } elseif ($prop.Value -is [pscustomobject] -or $prop.Value -is [System.Array]) {
                if (Rewrite-CommandsInObject $prop.Value) { $changed = $true }
            }
        }
    }
    return $changed
}
$pluginsDir = Join-Path $Destination 'plugins'
if (Test-Path $pluginsDir) {
    $pluginHookFiles = Get-ChildItem -Path $pluginsDir -Recurse -Force -Filter 'hooks.json' -ErrorAction SilentlyContinue
    foreach ($f in $pluginHookFiles) {
        $obj = Get-Content $f.FullName -Raw | ConvertFrom-Json
        if (Rewrite-CommandsInObject $obj) {
            Write-JsonNoBom $f.FullName $obj
            Write-Host "[prepare] rewrote host paths in plugin hooks.json: $($f.FullName.Substring($Destination.Length))"
        }
    }
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
