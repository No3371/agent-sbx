# Patch: Incremental Context Staging (robocopy)

> **Status:** Complete
> **Date:** 2026-07-29
> **Author:** agent (Claude)
> **Directive:** Skip context preparation for unchanged dirs/files — cheap + fast. Prepare costs ~2 min.
> **Source Plan:** Direct — addresses F7 of `2607271757-prepare-build-run-optimization-eval.md`
> **Result:** Success

---

## Summary

`claude/prepare.ps1` deleted every stage dir and re-copied the host `~/.claude` tree file-by-file via `Copy-Item` on every run — ~2350 files / 32MB, where PowerShell per-cmdlet overhead dominates because the files are small. Replaced the delete-then-copy shape with `robocopy /MIR`, which does size+write-time comparison in native code and transfers only what differs. Cold 22.7s → 3.3s, warm (unchanged tree) → 2.1s, staged output byte-identical.

---

## Changes

### Staging loop → robocopy

**File:** `claude/prepare.ps1`
**Change Type:** Modified

**What Changed:**

- Removed the stage-dir reset loop (`Remove-Item $target -Recurse -Force` + recreate). `/MIR` purges dest entries whose source is gone, so the property the reset bought is retained without paying the deletion.
- Removed `Copy-ItemFiltered` — the recursive per-file copy function (~25 lines).
- Staging loop now calls `robocopy $src $dst /MIR /MT:16 /R:1 /W:1 /NFL /NDL /NP /NJH /NJS` with exclusions.
- `$excludedDirectoryNames` (`.github` | `.git` | `node_modules`) → `/XD`. Bare names match at every depth, same as the old `$item.Name` check.
- `$credentialExcludePatterns` → `/XF`. Wildcards match at every depth, same as the old `Test-CredentialFileName` call per file.
- `.keep` seeding moved *after* robocopy, and added to `/XF` — an `/XF` entry is shielded from `/MIR`'s purge, so the placeholder survives across runs.
- Per-dir result reported from robocopy's exit code: `unchanged` | `updated` | `stale entries purged` | `updated + purged`.

**Why:** ~2350 `Copy-Item` invocations is the entire cost. Native change detection removes both the enumeration cost and the write cost on an unchanged tree — and, on a cold cache or with on-access AV, the cost of re-writing 32MB that did not change.

### Robocopy exit-code handling

**File:** `claude/prepare.ps1`

**What Changed:**

- `if ($rc -ge 8) { throw ... }` — robocopy uses `0..7` for SUCCESS (`0` nothing to do | `1` copied | `2` purged | `3` both). `$LASTEXITCODE` reset to `0` after each call so downstream checks are not tripped by a successful `1`.
- Opt out of `$PSNativeCommandUseErrorActionPreference` when the variable exists (PS 7.3+).

**Why:** the script runs `$ErrorActionPreference = 'Stop'`. On PS 7.3+ that promotes a nonzero native exit to a terminating error — which would make *every successful* robocopy run throw. No-op on PS 5.1, where the variable is absent.

### Destination-side credential sweep

**File:** `claude/prepare.ps1`
**Change Type:** Added

**What Changed:** post-staging pass over each stage dir; any file matching `$credentialExcludePatterns` is deleted with a `CREDENTIAL RISK: removing staged <path>` warning. `Test-CredentialFileName` retained to drive it.

**Why:** two reasons, both load-bearing.

1. `/XF` shields a dest file from `/MIR`'s purge as well as from copying. A credential staged by an older revision of this script would otherwise persist in `context/.claude` indefinitely — the old code's `Remove-Item` reset made that impossible.
2. `/XF` is silent. The per-file `CREDENTIAL RISK: skipping` warning was this script's only signal that an exclusion had fired; the sweep restores it.

---

## Verification

**Method:** clean A/B — old version (`git show HEAD:claude/prepare.ps1`) and new version each staged to a separate temp `-Destination` from the same host tree; wall-clock timed; manifests (relative path + byte length, sorted) compared with `Compare-Object`. Plus AST parse.

**Result:**

```
AST parse OK

OLD cold: 22.7s | NEW cold: 3.3s | NEW warm(unchanged): 2.1s
OLD files=2351  NEW files=2351
manifest diffs: 0
```

Staged composition (unchanged by this patch): 2351 files / 32.6MB — `plugins` 2140 files / 30.6MB | `skills` 203 / 1.9MB | `hooks` 3 | `agents` 1 | `commands` 1.

Downstream steps confirmed still firing on a real run: `dropped host-state cache: plugins/claude-hud/{config,transcript}-cache` | `dropped build-time-install payload: plugins/{cache,marketplaces}/context-mode` | `known_marketplaces.json: removed context-mode` | settings rewrite | statusLine rewrite.

**Status:** PASS

---

## Impact on Related Projex

| Document | Relationship | Update Made |
|----------|-------------|-------------|
| `2607271757-prepare-build-run-optimization-eval.md` | F7 recommended exactly this (`robocopy /MIR` + combined post-walk) for claude/codex | F7 addressed for `claude/` only — see Notes |
| `2607100235-context-mode-build-time-install-pilot-plan.md` | Owns `$buildTimeInstallMarketplaces` | Not modified — see Notes (marketplace rename observation) |

---

## Notes

**Warm run is 2.1s, not ~0.6s, and `skills`/`plugins` always report `updated`.** By design, not a defect. Post-staging steps mutate the destination: the CRLF normalizer rewrites `*.sh` to LF, and the JSON rewrites edit `installed_plugins.json` / `known_marketplaces.json`. Those dest files then differ in size from their CRLF/unrewritten host originals, so the next `/MIR` re-copies them and the normalizer re-runs. Self-limiting — bounded to the ~20 `.sh` + 2 JSON files, not the 2351 — and idempotent in effect, so output stays correct. Eliminating it would mean normalizing into a staging area outside the mirror, which costs more complexity than the ~1.5s it would save.

**Not done: `codex/prepare.ps1`.** F7 names codex (61MB staged) as the other suite worth converting, and it is the larger of the two. Left out to keep this patch to one verified file — its `prepare.ps1` was not read and may not share the same loop shape. Follow-up.

**Incidental observation, not acted on.** The host now carries *both* `plugins/cache/context-mode` and `plugins/cache/claude-context-mode`; `known_marketplaces.json` still keys only `context-mode`. `$buildTimeInstallMarketplaces = @('context-mode')` drops the former correctly, so the newer `claude-context-mode` payload **is** vendored into the image. If context-mode has renamed its marketplace, the build-time-install pilot's intent (no host-baked state for that marketplace) is now partially bypassed. Worth confirming against `2607100235-context-mode-build-time-install-pilot-plan.md` before the next build.

**`/MIR` blast radius is unchanged from the code it replaces.** It is scoped per stage subdir (`context/.claude/skills`, `…/plugins`, …), exactly like the `Remove-Item $target -Recurse -Force` it removes — not the whole `-Destination`.
