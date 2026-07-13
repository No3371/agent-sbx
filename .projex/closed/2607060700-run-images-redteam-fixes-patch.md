# Patch: Fold redteam Should-Fix + Conditions-for-Approval into run-images-without-sbx Plan

> **Date:** 2026-07-06
> **Author:** developer@3371.online (agent-drafted)
> **Directive:** Apply the redteam's Should-Fix and Conditions-for-Approval items to `2607060236-run-images-without-sbx-plan.md` before execution.
> **Source Plan:** `2607060236-run-images-without-sbx-plan.md`
> **Source Redteam:** `2607060240-run-images-without-sbx-redteam.md`
> **Result:** Success

---

## Summary

The plan (not yet executed — no `run.ps1` scripts exist on disk) proposed `claude/run.ps1` / `codex/run.ps1` launchers without addressing four redteam-flagged gaps: undocumented credential exposure, an unmet "any project" distribution goal, a PS5.1 BOM risk in host state-file writes, and a podman flag left as a manual fallback. This patch edits the plan document's Steps 1–4 script/README content and Verification Plan so all four fixes — plus the redteam's No-Go If condition — are baked into the plan text itself, before anyone executes it. No application code was touched; nothing existed to execute yet.

---

## Changes

### `.projex/2607060236-run-images-without-sbx-plan.md` — Step 1 (`claude/run.ps1` proposed content)

**Change Type:** Modified (plan document only)
**What Changed:**
- Added a `SECURITY:` header comment: `.claude.json` / `.claude-docker\.credentials.json` carry live OAuth/session tokens, treat like SSH keys, never commit/share `.claude-docker`.
- Replaced `'{}' | Set-Content -Path ... -Encoding utf8` with `[System.IO.File]::WriteAllText($path, '{}', (New-Object System.Text.UTF8Encoding $false))` for both `$claudeJson` and `$credsFile` — BOM-less write.
- Wired `--userns=keep-id` into `$runArgs` conditionally (`if ($Engine -eq 'podman')`) instead of leaving it as a manual "if this fails" edit.
- Updated the step's Rationale and "If this fails" text to reflect the above are now baked in, not deferred.

**Why:** Addresses redteam Finding 1 (credential files are durable, unscoped host secrets — Should Fix), the BOM challenge under "Human User: Docker Desktop bind-mount UID/permission mapping just works" (Should Fix / Condition for Approval), and the podman edge case under "Human User: Image built for wrong engine's runtime" (Should Fix / Condition for Approval).

---

### `.projex/2607060236-run-images-without-sbx-plan.md` — Step 2 (`codex/run.ps1` proposed content)

**Change Type:** Modified (plan document only)
**What Changed:** Same three fixes mirrored for the codex script: security comment on `.codex-docker\auth.json`, BOM-less `[System.IO.File]::WriteAllText(...)` write, conditional `--userns=keep-id` for `-Engine podman`. Rationale and "If this fails" text updated to match.

**Why:** Same redteam findings as Step 1, applied identically since Step 2 is structurally the same wrapper for the codex template.

---

### `.projex/2607060236-run-images-without-sbx-plan.md` — Step 3 (`claude/README.md` proposed `## Run` content)

**Change Type:** Modified (plan document only)
**What Changed:**
- Added a `**Security:**` paragraph noting `.claude.json`/`.claude-docker\.credentials.json` carry live tokens, treat like SSH keys.
- Added a PowerShell profile function snippet (`function ccrun { & "<repo-path>\claude\run.ps1" @args }`) with instructions to add it to `$PROFILE`, so the launcher is callable from any directory without retyping the repo path.
- Updated Rationale to cite both redteam findings addressed.

**Why:** Addresses redteam Finding 1 (credential exposure undocumented) and Finding 2 ("any project" distribution gap — the plan's own Verification Plan required typing the full repo path every invocation, contradicting the stated goal).

---

### `.projex/2607060236-run-images-without-sbx-plan.md` — Step 4 (`codex/README.md` proposed `## Run` content)

**Change Type:** Modified (plan document only)
**What Changed:** Same two additions mirrored for codex: security paragraph on `.codex-docker\auth.json`, and a `codexrun` profile-function snippet. Rationale updated.

**Why:** Same as Step 3, applied to the codex README content.

---

### `.projex/2607060236-run-images-without-sbx-plan.md` — Verification Plan

**Change Type:** Modified (plan document only)
**What Changed:** Added a callout above "Automated Checks": verify A1 (creds file vs keychain), A2 (cwd writability), and A3 (codex auth path) one at a time, not batch-executed together.

**Why:** Folds in the redteam's **No-Go If** condition — `--rm` discards container state on exit, so a compound failure across multiple unverified assumptions at once is hard to diagnose blind.

---

### `.projex/2607060236-run-images-without-sbx-plan.md` — Header + Notes/Risks

**Change Type:** Modified (plan document only)
**What Changed:**
- `Related Projex` header line now references the redteam doc and this patch doc, with `[PATCHED]` marker.
- Notes → Risks section: added entries for the BOM fix, credential-exposure documentation, and "any project" gap, each tagged `[PATCHED — see 2607060700-run-images-redteam-fixes-patch.md]`; podman risk mitigation line updated to note it's now wired, not manual.

**Why:** Per `patch-projex.md` § Update Related Documents — mark patched objectives and link the patch doc so the plan doesn't carry stale "not yet addressed" language into execution.

---

## Verification

**Method:** Manual read-through of the edited plan sections against each of the redteam's four Should-Fix items and the No-Go If condition; confirmed each is now present in Steps 1–4 script/README content and the Verification Plan, not merely mentioned in the Notes.

**Result:**
- Credential exposure note: present in Step 1, Step 2 script headers and Step 3, Step 4 README snippets. PASS
- PowerShell profile alias snippet: present in Step 3 (`ccrun`) and Step 4 (`codexrun`). PASS
- BOM-less write: present in Step 1 and Step 2 script content, replacing `Set-Content -Encoding utf8`. PASS
- `--userns=keep-id` wired conditionally: present in Step 1 and Step 2 `$runArgs` construction. PASS
- No-Go If (verify A1/A2/A3 one at a time): present as a callout in Verification Plan. PASS

**Status:** PASS

---

## Impact on Related Projex

| Document | Relationship | Update Made |
|----------|-------------|-------------|
| `2607060236-run-images-without-sbx-plan.md` | Source Plan | Steps 1–4 and Verification Plan edited per the five fixes above; header `Related Projex` line and Notes/Risks section updated with `[PATCHED]` markers linking to this patch doc. Status remains `Ready` — plan is still unexecuted. |
| `2607060240-run-images-without-sbx-redteam.md` | Source of fixes | Not modified — its findings are now reflected in the plan; no change needed to the redteam doc itself. |

---

## Notes

- **No commits made.** This repo's `.gitignore` (`.gitignore:10`, the `.projex` line) ignores the entire `.projex/` directory — per `claude/README.md`, active development notes are intentionally not committed in this repo. Both the edited plan file and this patch document live under `.projex/`, so the `stage-n-commit` steps in `patch-projex.md`'s Git Integration section do not apply here. No files were force-added; the edits exist only in the working tree, consistent with repo convention.
- Plan Status remains `Ready` (unexecuted) — this patch only edits proposed content, it does not create `claude/run.ps1` / `codex/run.ps1` or touch any actual README. Execution of the (now-patched) plan is a separate future action.
- Redteam's "Must Fix" list was empty (no hard blockers) — this patch covers only "Should Fix" + "Conditions for Approval," per the directive's scope. "Monitor" items (concurrent-run file races, image tag drift, enterprise-redirected `USERPROFILE`) were intentionally left untouched — redteam itself deferred them as not worth engineering for personal single-user tooling.
