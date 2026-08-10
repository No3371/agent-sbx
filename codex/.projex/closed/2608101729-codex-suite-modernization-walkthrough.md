# Walkthrough: Modernize Codex sandbox suite

> **Status:** Complete (Success)
> **Execution Date:** 2026-08-10
> **Completed By:** openai-codex/gpt-5.6-terra
> **Source Plan:** 2608101559-codex-suite-modernization-plan.md
> **Execution Log:** 2608101559-codex-suite-modernization-log.md
> **Result:** Success — static verification; Windows/Docker live checks waived as non-blocking.

## Summary

Modernized the standalone `codex/` suite to a root `/root` runtime with `/workspace` workdir, safe filtered Codex/shared-skills staging, root-specific cache volumes, and a Docker Desktop-only operator contract. Post-execution audit found an unsafe pre-existing staging-envelope path and Podman-facing output; bounded patch commits `10ea277` and `d3082a5` resolved both and added a Windows regression fixture.

## Objectives

| Objective | Result | Evidence |
| --- | --- | --- |
| Root image/runtime; no root plugin lifecycle execution | Complete | `codex/Dockerfile`; static legacy-token scan; non-login `pluginbuild` phase with `npm install --ignore-scripts` |
| Safe `.codex` + shared-skills staging | Complete | `codex/prepare.ps1`; marker-bound envelope patch; `codex/tests/prepare-envelope-regression.ps1` |
| Four build staging overrides | Complete | `codex/build.ps1:24-30,90-96` |
| Root, generation-aware caches and fresh auth | Complete | `codex/run.ps1:90-132`; static launcher scan |
| Truthful Docker-only docs | Complete | `codex/README.md`; Docker-only build output patch |

## Execution Detail

### Step 1 — Root runtime

**Planned:** Remove `agent`/sudo `/home/agent` plumbing; use root `/root` payloads and `/workspace`; prevent host plugin lifecycle scripts from running as root.

**Actual:** `codex/Dockerfile` removed the agent-user/sudo/home layers, installs browser tooling for root, copies `.codex` and `.agents/skills` under `/root`, ends as `USER root` with `WORKDIR /workspace`, and uses a no-login `pluginbuild` phase with `npm install --ignore-scripts`, package inventory checks, hostile-lifecycle-marker rejection, and critical hash records.

**Deviation:** None.

**Verification:** Static scan found no `/home/agent`, `agent:agent`, sudoers, or `USER agent`; Docker image probe deferred because Docker Desktop/Windows is unavailable.

### Step 2 — Safe staging

**Planned:** Extend filtered Codex preparation to optional shared `~/.agents/skills` using native `robocopy`, containment/reparse/collision checks, cleanup, normalization, and inventory.

**Actual:** `codex/prepare.ps1` added independent file-or-directory `robocopy` staging, canonical source/destination validation, reparse refusal, `.git`/`.github`/`node_modules` and credential cleanup, LF normalization, malformed/duplicate skill refusal, root-local marketplace paths, and sanitized SHA-256/package/lifecycle inventory. `codex/.gitignore` ignores both generated context roots.

**Deviation:** Audit found the initial marker could claim arbitrary existing destination envelopes. Commit `10ea277` now accepts only a newly-created envelope or a marker whose content exactly binds to that canonical envelope before any mutation; unmarked existing envelopes fail closed.

**Verification:** Static invariants and `git diff --check` passed. `codex/tests/prepare-envelope-regression.ps1:1-43` covers the formerly destructive unmarked-envelope shape. Windows PowerShell 5.1 and `robocopy.exe` execution are waived/non-blocking here.

### Step 3 — Build forwarding

**Planned:** Forward separate Codex and shared-skills source/destination overrides without altering defaults.

**Actual:** `codex/build.ps1` conditionally forwards nonempty `HostCodexDir`, `HostAgentsSkillsDir`, `Destination`, and `SkillsDestination` values to `prepare.ps1`.

**Deviation:** Commit `10ea277` also removed user-facing Podman run guidance: Docker Desktop is the only recommended run path; Podman transfer output remains explicitly unverified.

**Verification:** Static argument and output scan passed; PowerShell AST and mocked engine argv checks remain unavailable.

### Step 4 — Launcher/cache alignment

**Planned:** Remove ownership repair, move caches to `/root`, namespace cache volumes by suite/workspace/lockfile, and retain fresh device auth.

**Actual:** `codex/run.ps1` uses `codex-nmvol-<workspace-hash>-<lock-hash>` and `codex-pm-cache-node25:/root/.npm`, removes `sudo`, `chown`, and `--userns=keep-id`, retains device auth before bypass launch, and emits visible non-blocking CodeGraph degradation messages.

**Deviation:** None.

**Verification:** Static scan confirms root paths, generation names, no agent-era tokens/auth mounts, and unchanged device-auth/bypass ordering. Docker Desktop workspace/volume owner-mode smoke remains waived/non-blocking.

### Step 5 — Operator contract

**Planned:** Rewrite docs for root privilege, trusted staged payloads, Docker-only support, caches, staging, and ephemeral auth/history boundaries.

**Actual:** `codex/README.md` documents root + bypass limits, filtered and shared staging, marker/containment rules, no-root plugin lifecycle authority, Docker Desktop support, unsupported Podman, root cache names, and no host auth/history mount.

**Deviation:** None after the build-output remediation.

**Verification:** Static cross-check against Dockerfile and scripts passed.

## Complete Change Log

Derived from `git diff --stat main..HEAD`: 11 files, 761 insertions, 542 deletions.

| File | Change | Planned? | Actual detail |
| --- | --- | --- | --- |
| `codex/Dockerfile` | Modified | Yes | Root runtime/home/workdir; shared-skills copy; non-root script-disabled plugin install; integrity checks. |
| `codex/prepare.ps1` | Modified | Yes | Filtered dual-root staging, containment/envelope trust, cleanup, normalization, collisions, inventory, `/root` marketplace sources. |
| `codex/.gitignore` | Created | Yes | Ignores generated `context/.codex/` and `context/.agents/`. |
| `codex/build.ps1` | Modified | Yes | Four optional preparation overrides; Docker-only operator output. |
| `codex/run.ps1` | Modified | Yes | Root cache mount, generation-aware Codex volumes, no ownership/userns repair, CodeGraph degradation messages. |
| `codex/README.md` | Modified | Yes | Root/trust/staging/cache/auth/Docker contract. |
| `codex/tests/prepare-envelope-regression.ps1` | Created | No — audit remediation | Unmarked-envelope no-mutation and no-Podman-guidance regression fixture. |
| `codex/.projex/2608101559-codex-suite-modernization-plan.md` | Modified | Lifecycle | Related-artifact ledger and post-audit revision entry. |
| `codex/.projex/2608101559-codex-suite-modernization-log.md` | Created | Lifecycle | Step outcomes, verification boundary, remediation record. |
| `codex/.projex/2608101720-codex-suite-modernization-execution-audit.md` | Created | Related audit | Audit evidence identifying bounded remediation. |
| `codex/.projex/closed/2608101725-codex-staging-envelope-safety-patch.md` | Created | Post-audit patch | Born-closed remediation record. |

## Success Criteria Verification

| Criterion | Method | Result | Evidence |
| --- | --- | --- | --- |
| Root runtime and no root host-lifecycle scripts | Static Dockerfile/token inspection | Pass (static) | Root final user/workdir; `pluginbuild`; `--ignore-scripts`; no legacy-user tokens. |
| Preserved Codex payload/root marketplace paths | Static preparation inspection | Pass (static) | Filtered transforms retained; image marketplace sources use `/root/.codex`. |
| Shared skills safely staged | Static invariants + regression fixture | Pass (static) | Canonical marker-bound envelope gate; unmarked-envelope fixture. |
| Build interface forwards four overrides | Static parameter/forwarding inspection | Pass (static) | `build.ps1:24-30,90-96`. |
| Docker-only runtime contract | Static launcher/docs/output inspection | Pass (static) | Root cache names; fresh device auth; Docker-only guidance; no Podman run recommendation. |
| Documentation matches behavior | Static cross-check | Pass (static) | README aligns with Dockerfile, prepare/build/run scripts. |
| Windows/Docker device-auth and volume checks | Live supported-platform tests | Waived, non-blocking | No Windows PowerShell, `robocopy`, Docker Desktop, or device-auth environment available. |

**Overall:** All close-required static criteria pass. The explicitly waived live platform checks remain release-evidence gaps, not close blockers.

## Deviations and Issues

- **Audit remediation:** `2608101720-codex-suite-modernization-execution-audit.md` found an unsafe pre-existing envelope and Podman promotion. `10ea277` fixed both; `d3082a5` recorded the patch and updated lifecycle evidence.
- **Unavailable live tools:** No `powershell`/`pwsh`, `robocopy`, Docker/Podman, or device-auth environment. No real credentials or host state were inspected. The plan's Step 0 waiver explicitly makes these checks non-blocking.
- **Originating checkout artifacts:** `2608101607-codex-suite-modernization-plan-redteam.md` and `2608101613-codex-suite-modernization-plan-stress.md` are uncommitted in the originating checkout, not present in this execution worktree, and therefore not moved or integrated by this close.

## Insights

- A generated-root marker is a trust boundary only when validated before mutation and bound to one canonical envelope; creation-before-cleanup is insufficient.
- Root runtime migration must cover image, staging-generated config, launcher mounts, cache namespaces, and docs together.
- Docker-only support requires product output to match documentation; retaining an unverified transfer path must not advertise it as runnable.
- Platform-specific PowerShell/robocopy and Docker checks require a supported Windows validation row; static checks limit risk but do not replace that evidence.

## Follow-up

- Run `codex/tests/prepare-envelope-regression.ps1` and the plan's remaining fixture/AST matrix on Windows PowerShell 5.1 with `robocopy.exe`.
- Run Docker Desktop build/image/device-auth/workspace-volume checks before asserting release-supported live evidence.
- Treat the originating uncommitted Red Team/Stress artifacts independently; they were outside this clean child worktree.

## Lifecycle Reconciliation

Moved together: `2608101559-codex-suite-modernization-plan.md`, `2608101559-codex-suite-modernization-log.md`, and `2608101720-codex-suite-modernization-execution-audit.md`. The born-closed patch `2608101725-codex-staging-envelope-safety-patch.md` remains in `closed/`. No navigation was referenced by the plan.

## Commits Preserved by Finalization

`22dc865` `389835a` `d22fc59` `0288da8` `9f4f4ff` `16be36f` `10ea277` `d3082a5`; squash-close preserves these messages in the base commit description.
