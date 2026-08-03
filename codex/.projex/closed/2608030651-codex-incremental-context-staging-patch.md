# Patch: Codex Incremental Context Staging (robocopy)

> **Status:** Complete
> **Date:** 2026-08-03
> **Author:** agent (Codex)
> **Directive:** orchestrate-projex patch(slow) apply the same robocopy trick from claude suite to codex suite
> **Source Plan:** Direct — closes Codex remainder of F7 in `2607271757-prepare-build-run-optimization-eval.md`
> **Result:** Success

---

## Scope Guard

**Qualified:** ✓ well-understood Claude precedent | ✓ one implementation file + two direct docs | ✓ one approach | ✓ immediate fixture verification. No architecture, runtime launcher, image, or combined-suite change.

---

## Summary

`codex/prepare.ps1` rebuilt `context/.codex` and copied three host trees file-by-file. It now mirrors `skills/`, `vendor_imports/skills/`, and `plugins/cache/` incrementally with Claude's `robocopy /MIR` flags and exit handling while retaining Codex-only filtering, generated config/plugin behavior, missing-source cleanup, and exact staged bytes.

---

## Changes

### Incremental staged-tree mirror

**File:** `codex/prepare.ps1`  
**Change Type:** Modified

**What Changed:**
- Root destination stays stable (`:32-34`); removed whole-tree delete.
- `Sync-StageTree` (`:47-105`) runs `robocopy /MIR /MT:16 /R:1 /W:1 /NFL /NDL /NP /NJH /NJS`, translates exit codes `0..7` as success, resets `$LASTEXITCODE`, and disables PS 7.3+ native-error promotion.
- Three mapped trees call the helper (`:108-125`). Codex's top-level `skills/.system/` remains excluded without over-excluding nested user `.system/` dirs.
- Missing optional host trees are reset to `.keep`-only, preserving old clean-rebuild output.

**Why:** Native size+write-time comparison avoids PowerShell cmdlet overhead and unchanged-file rewrites. `/MIR` keeps source deletion propagation.

### Credential-safe mirror

**File:** `codex/prepare.ps1`  
**Change Type:** Modified

**What Changed:** `/XF` carries existing credential patterns. A pre-transform destination sweep (`:127-145`) deletes matching files shielded from `/MIR` purge and emits the existing `CREDENTIAL RISK` warning.

**Why:** Incremental destinations can outlive one prepare run; an excluded credential left by older/manual staging must not persist.

### User-facing behavior

**File:** `codex/README.md`  
**Change Type:** Modified

**What Changed:** Credential-copy note documents `/XF` + destination cleanup (`:141`); obsolete “no incremental staging” claim replaced with `/MIR` behavior and exit contract (`:147`).

### Related finding

**File:** `.projex/2607271757-prepare-build-run-optimization-eval.md`  
**Change Type:** Modified

**What Changed:** F7 marked patched for Claude + Codex; linked this artifact and recorded Codex parity evidence (`:72-76`).

---

## Verification

**Method:** Executed pre-patch (`17d191a^`) and patched `codex/prepare.ps1` under PowerShell 7.5.2 against separate temp destinations from one synthetic host tree. A PATH-injected `robocopy` test double implemented the used `/MIR`, `/XD`, `/XF`, metadata comparison, and `0|1|2|3` exit contract. Compared sorted `relative path + byte length + SHA-256` manifests after cold, unchanged warm, changed+stale, and missing-optional-tree runs. Fixture exercised CRLF normalization, TOML filtering/command rewrite, marketplace synthesis, source deletion, `.git`/credential exclusion, top-level-vs-nested `.system`, stale credential cleanup, and absent trees.

**Result:**
```text
PowerShell parse/execute: PASS (7.5.2)
Cold parity: PASS (11 files, 0 byte-manifest diffs)
Warm idempotence: PASS (11 files, 0 byte-manifest diffs)
Changed/purge parity: PASS (11 files, 0 byte-manifest diffs)
Absent-tree parity: PASS (8 files, 0 byte-manifest diffs)
Recursive excludes, top-level skills/.system boundary, destination credential cleanup: PASS
Cold: skills -> updated | vendor_imports/skills -> updated | plugins/cache -> updated
Warm: skills -> updated | vendor_imports/skills -> unchanged | plugins/cache -> stale entries purged
Changed: skills -> updated + purged | vendor_imports/skills -> updated + purged | plugins/cache -> stale entries purged
```

**Status:** PASS

---

## Impact on Related Projex

| Document | Relationship | Update Made |
|---|---|---|
| `2607271757-prepare-build-run-optimization-eval.md` | F7 source finding | Codex remainder closed; verification recorded |
| `2607291244-incremental-context-staging-patch.md` | Claude precedent | Referenced only; no stale claim to revise |

---

## Commits

| Commit | Change |
|---|---|
| `17d191a` | Incremental Codex mirror + README |
| `9b2796e` | Missing-tree and `.system` edge parity |

---

## Notes

- Verification ran real PowerShell control flow with a focused robocopy test double; native Windows `robocopy.exe` and host-scale timing were unavailable. Command shape and exit contract match verified Claude precedent.
- `/MIR` blast radius: only the three generated staged subtrees, never caller `$Destination` wholesale.
- Pre-existing untracked `c_c/` and 2026-08-03 migration/retirement projex remain untouched. They are separate future scopes and preservation constraints forbid folding them into this direct patch.
