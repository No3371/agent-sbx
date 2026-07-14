# Patch: chown `/home/agent/.cache` parent in opencode `run.ps1`'s `$pmSetup`

> **Date:** 2026-07-14
> **Author:** Claude (Sonnet 5) — via patch-projex
> **Directive:** Chat-diagnosed bug (no prior projex reference) — a real projex execution inside the `opencode-custom` sandbox blocked on Corepack failing with an unwritable cache path (`pnpm invokes Corepack, which needs a writable cache directory. The normal cache path was not writable.`). Traced live in conversation to a Docker mount-point ownership gap in `opencode/run.ps1`, not a target-repo issue.
> **Source Plan:** Direct (extends redteam Finding F5 from `2607110159-opencode-suite-port-plan.md`, closed)
> **Result:** Success

---

## Summary

`opencode/run.ps1` mounts a named volume onto the nested path `/home/agent/.cache/opencode`. `/home/agent/.cache` doesn't exist in the image, so Docker auto-creates that missing parent directory as `root:root` before the container starts — independent of the image's own `agent` user setup. The existing `$pmSetup` chown (added for redteam F5) only covered the volume leaf (`.cache/opencode`), never the parent. Corepack's own cache lives at the sibling path `~/.cache/node/corepack`; creating it requires write access to the root-owned parent, so the first `corepack`-mediated pnpm invocation in a fresh container failed with EACCES. Fix: add `/home/agent/.cache` to the existing chown call.

---

## Changes

### `opencode/run.ps1`

**File:** `opencode/run.ps1`
**Change Type:** Modified
**What Changed:**
- Line 99 (`$pmSetup`): added `/home/agent/.cache` to the `sudo chown agent:agent ...` target list, alongside the pre-existing `.npm`, `.pnpm-store`, `.cache/opencode` leaves.
- Lines 90-98: extended the comment to explain the Docker parent-auto-create mechanism and why only opencode (not claude/codex) is exposed to it — neither of the other two suites mounts anything under `.cache/` at all (they follow the `~/.claude` / `~/.codex` single-dot-dir convention; opencode alone follows XDG and splits state across `~/.local/share`, `~/.local/state`, `~/.cache`).

**Why:**
Diagnosed live in conversation by tracing the actual mount list (`-v 'opencode-cache:/home/agent/.cache/opencode'`, `opencode/run.ps1:125`) against Docker's documented behavior for volumes mounted onto paths whose parent doesn't pre-exist in the image: the daemon creates the missing parent as `root:root`, mode 0755, before the container's `USER` directive has any effect. The prior F5 fix (`2607110159-opencode-suite-port-plan.md` → `2607110159-opencode-suite-port-walkthrough.md`) chowned every volume leaf it explicitly mounted but never the implicit parent one of those leaves forced into existence — a gap invisible unless something else (corepack, here) writes to a *sibling* of that leaf under the same unowned parent.

---

## Verification

**Method:** PowerShell AST parse (`[System.Management.Automation.Language.Parser]::ParseFile`) + isolated re-evaluation of the exact `$pmSetup` string assignment, matching this repo's existing patch precedent (`2607100024-workspace-node-modules-pm-cache-patch.md`, which used the same parse+arg-generation method rather than a full image rebuild for a shell-string-only change). No image rebuild performed — the change is a pure string edit with no new commands, only a wider chown target list on an already-proven `sudo chown` invocation pattern.

**Result:**
```
PARSE OK

sudo chown agent:agent /home/agent/.cache /home/agent/.npm /home/agent/.pnpm-store /home/agent/.cache/opencode 2>/dev/null; corepack pnpm config set store-dir /home/agent/.pnpm-store 2>/dev/null || true;
```

**Status:** PASS

---

## Impact on Related Projex

| Document | Relationship | Update Made |
|----------|-------------|-------------|
| `2607110159-opencode-suite-port-walkthrough.md` (closed) | Introduced the `$pmSetup` chown pattern this patch extends (redteam F5) | Cross-referenced here; not edited — F5 as originally scoped (volume leaves) was correctly implemented, this patch closes a gap in what F5 didn't anticipate (the implicit parent), not an error in that walkthrough's claims |
| `2607110210-opencode-suite-port-plan-redteam.md` (active) | Source of F5 | Cross-referenced; F5's scope (leaf-only chown) is now superseded in practice by this patch, no direct edit needed (redteam docs record findings at time of authoring, not live status) |

---

## Notes

- **Why claude/codex are unaffected:** neither `claude/run.ps1` nor `codex/run.ps1` mounts any volume under `.cache/` — Claude Code and Codex CLI keep all state under single dot-dirs (`~/.claude`, `~/.codex`), not XDG `~/.cache`. Only opencode (XDG-following, Bun-based) has a `~/.cache/<tool>` mount, so only opencode can hit this Docker parent-auto-create quirk. No parallel patch needed on the other two suites.
- **Unresolved, separate issue:** the same live diagnostic session also referenced `/tmp/opencode` being root-owned in the blocked execution. No mechanism in `opencode/Dockerfile` or `run.ps1` touches `/tmp` — this is not explained by the `.cache` finding and remains open (possibly a quirk of the upstream `ghcr.io/anomalyco/opencode` base image itself, out of scope for this patch). Flagged for a follow-up scan/debug-projex if it recurs.
- **Node major-version mismatch** (target repo requiring `>=25 <26` against the baked `NODE_MAJOR=24`) raised in the same session is a separate, non-bug gap: `build.ps1` doesn't forward a `-NodeMajor` override even though the Dockerfile already parameterizes it via `ARG NODE_MAJOR`. Not addressed by this patch (out of scope — a `build.ps1` param addition across all three suites, not a `run.ps1` runtime fix); candidate for its own patch if wanted.
