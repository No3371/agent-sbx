# Audit: Codex suite modernization execution

> **Status:** Complete (Needs Rework)
> **Audit Date:** 2026-08-10 | **Auditor:** openai-codex/gpt-5.6-terra | **Work Period:** 2026-08-10 17:10–17:31 UTC
> **Subject:** commits `22dc865`..`16be36f` on `projex/2608101559-codex-suite-modernization`
> **Related:** 2608101559-codex-suite-modernization-plan.md | 2608101559-codex-suite-modernization-log.md

---

## Audit Summary

**Claim:** Modernize standalone Codex to root runtime; safely stage filtered `.codex` plus shared skills; isolate caches; document Docker-only contract.

**Verdict:** Partial.

**Assessment:** Completeness: Medium | Correctness: Medium | Quality: Medium | Value: Medium.

**Top issues:**

1. High: caller-controlled staging destinations can target an existing arbitrary directory; the generated-root marker is created before cleanup, then missing optional sources delete the selected root.
2. Medium: `build.ps1` still advertises Podman as a normal run engine despite the Docker-only/unadvertised-Podman contract.
3. Medium: no committed executable fixture/harness tests; all PowerShell, robocopy, Docker, device-auth, and workspace semantics remain unverified.

---

## Claims vs Evidence

| Claim | Evidence | Status | Notes |
| --- | --- | --- | --- |
| Root runtime, `/root`, `/workspace` | `22dc865`; `codex/Dockerfile:1-89` | ✓ static | Final `USER root`, root payload copies, `/workspace` workdir. Docker image probe unavailable. |
| No root host-plugin lifecycle execution | `codex/Dockerfile:66-82` | ✓ static | `pluginbuild` no-login user; `npm install --ignore-scripts`; plugin tree copied to root only after install. |
| Shared-skills staging, containment, cleanup | `389835a`; `codex/prepare.ps1` | ⚠ | Main transport/features exist; destination trust boundary is unsafe. |
| Four build overrides | `d22fc59`; `codex/build.ps1:27-30,91-96` | ✓ static | Nonempty override forwarding present. |
| Root caches, fresh device auth, no auth mount | `0288da8`; `codex/run.ps1:102-128` | ✓ static | Root cache and generation volume names; `codex login --device-auth` precedes bypass launch. |
| Docker-only, Podman unadvertised operator contract | `9f4f4ff`; `codex/README.md:11-18`; `codex/build.ps1:1,146` | ⚠ | README is clear; launcher build output conflicts. |
| Generated roots ignored | `codex/.gitignore:1-2`; `git check-ignore -v` | ✓ | Both probes matched suite-local rules. |

## Objective Verification

### 1. Root image/runtime

**Evidence:** `codex/Dockerfile:1-89`; diff `main...HEAD`; scoped legacy-token scan.

**Actual:** Root home paths, root final user/workdir, shared-skill copy, non-root plugin package phase, hash record.

**Verification:** ✓ static. `git diff --check main...HEAD` passed. Docker, browser, UID/HOME/workdir, and hostile-lifecycle image probes were unavailable; no claim of live proof accepted.

### 2. Safe staging

**Evidence:** `codex/prepare.ps1:75-116,137-155,193-214`.

**Actual:** Source existence/config validation; path/reparse checks; filtered robocopy branches; optional placeholders; cleanup; CRLF normalization; skill collision checks; inventory; root-path marketplace synthesis.

**Verification:** ⚠ Partial. The safety invariant fails for caller-selected existing destination envelopes; see High finding. No Windows PowerShell AST parse or native robocopy fixture ran.

### 3. Build forwarding

**Evidence:** `codex/build.ps1:27-30,91-96`.

**Verification:** ✓ static. Parameters and conditional forwarding match the Plan. Mocked argv coverage did not run.

### 4. Launcher/caches

**Evidence:** `codex/run.ps1:89-128`.

**Verification:** ✓ static. Root cache mount is `codex-pm-cache-node25:/root/.npm`; masked dependencies use `codex-nmvol-<workspace>-<lock>`; no `sudo`, `chown`, `/home/agent`, or `--userns=keep-id` in product launcher. Docker Desktop owner/mode and fake-engine checks did not run.

### 5. Documentation

**Evidence:** `codex/README.md:1-112` cross-checked with Dockerfile/scripts.

**Verification:** ⚠ Partial. Root/trusted-payload/auth/cache boundaries match static implementation. `build.ps1` still prints an end-user Podman run command, contradicting the documented unadvertised-Podman boundary.

---

## Code/Implementation Inspection

### `codex/prepare.ps1`

**Claimed:** Canonical containment plus marker-gated cleanup prevents unsafe destination mutation.

**Actual:** `Assert-StageLayout` derives `$envelope` directly from user-supplied `-Destination` (`:75-99`), accepts any envelope whose leaves are `.codex` and `.agents/skills`, creates `.codex-stage-marker` unconditionally (`:193`), then optional-source handling deletes an existing target (`:110-114`). The marker proves only that this invocation wrote it, not that the envelope is generated/safe.

**High finding:** A command such as `-Destination C:\victim\.codex -SkillsDestination C:\victim\.agents\skills -HostCodexDir C:\fixture\.codex -HostAgentsSkillsDir C:\missing` passes the shape and current source-conflict checks. It writes `C:\victim\.codex-stage-marker`, mirrors into the real `.codex`, then removes real `.agents\skills` because the optional shared source is absent. Existing user data can be deleted or overwritten. README's marker/containment claim therefore overstates the protection.

**Remediation:** Before every destination mutation, require a trusted script-managed envelope: either a new empty envelope created by this invocation, or a pre-existing, validated marker for that exact generated root. Reject existing unmarked envelopes and source ancestry into either destination root; only then create targets/markers and permit `Remove-Item` or `/MIR`. Add fixture coverage proving this command shape fails with zero mutation.

### `codex/build.ps1`

**Claimed:** Docker Desktop is sole release-supported engine; Podman stays unadvertised.

**Actual:** Default engine remains Docker, but the header says “with podman” (`:1`) and success output recommends `-Engine <docker|podman>` (`:146`).

**Medium finding:** The command output promotes an unvalidated runtime path. Keep transfer compatibility if needed, but make Docker the only recommended/run output until a supported Podman row passes.

### `codex/Dockerfile`, `run.ps1`, `README.md`

**Positive:** Static migration is coherent: root paths align across image, launch cache, and docs; plugin installation disables lifecycle scripts; device authentication remains fresh/ephemeral; README accurately discloses root plus bypass risk. `codex/.dockerignore` permits both generated roots.

---

## Testing Validation

**Executed by audit:** `git diff --check main...HEAD` ✓; `git check-ignore -v` for both generated roots ✓; static legacy-token scan ✓; commit/diff/log/document inspection ✓.

**Not executable here:** Windows PowerShell 5.1, `robocopy.exe`, Docker Desktop, Docker/Podman, browser/image probe, device authentication. Environment has no `powershell`, `pwsh`, `docker`, or `hadolint` executable.

**Coverage:** Unit/integration: none committed under `codex/`. Fixture/mock/AST evidence claimed by the Plan and log was not present. The Step 0 waiver makes unavailable live smoke non-blocking, but does not turn absent automated regression coverage into proof.

**Missing:** destination-marker/destructive-cleanup regression; robocopy file/directory/failure fixtures; PowerShell AST parse; build/run fake-engine argv checks; supported Docker Windows workspace/volume/auth/sentinel probe.

---

## Documentation Audit

**Completeness:** High for root privilege, trusted staged payloads, no-auth mounts, cache names, shared skills, unsupported Podman, and ephemeral state.

**Accuracy:** Partial. README says Podman is unadvertised, but `build.ps1` emits an explicit Podman run recommendation. README's statement that marker-gated cleanup protects generated context is not justified by the current marker creation order/trust model.

---

## Gap Analysis

| Promise | Status | Impact |
| --- | --- | --- |
| Destination/marker containment prevents unsafe cleanup | Failed | High — user data can be overwritten/deleted through allowed override shapes. |
| Podman remains unadvertised | Partial | Medium — user-visible script output suggests unvalidated use. |
| Synthetic/static regression verification | Missing | Medium — regressions in Windows-only code have no reproducible evidence. |

## Findings

### Critical

None found.

### Significant

- **High — untrusted staging envelope.** `prepare.ps1` creates rather than validates its cleanup marker and permits existing arbitrary override envelopes. Patch before any operator runs preparation; rerun static/fixture checks afterward.
- **Medium — Podman promoted by build output.** `build.ps1:1,146` conflicts with Plan/README Docker-only support framing. Limit user-facing output to Docker-supported execution.
- **Medium — no executable verification artifacts.** No Codex tests/harness exist; log records static checks only. Add portable fake-engine/fixture coverage when patching; Windows/Docker proof remains deferred under the waiver.

### Minor

- **Traceability:** Plan checkboxes remain unchecked despite document status `Complete`; log marks deferred checks but does not distinguish verified from claimed criteria in a durable acceptance matrix.

### Positive

- Scope matches six product files plus expected Plan/log lifecycle updates; commits are granular and linear (`22dc865`..`16be36f`).
- Diff is whitespace-clean; both generated context roots are ignored.
- Root runtime, cache namespace, device-auth ordering, plugin lifecycle suppression, and operator disclosure align statically.

## Final Verdict

**Status:** Needs Rework

- Completeness: Medium
- Correctness: Medium
- Quality: Medium
- Value: Medium — modernization materially improves root/runtime consistency, but the staging safety regression blocks safe operator use.

**Immediate code-level patch:** Yes. Fix the staging-envelope/marker trust boundary and Podman-facing output; add focused regression coverage. Re-audit those changes before close.

**Blocker:** Close is not permitted while the High destructive staging path remains. Windows/Docker/device-auth smoke remains deferred and non-blocking under the documented Step 0 waiver.

**Sign-off:** No — safety condition unmet.
