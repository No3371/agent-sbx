# Walkthrough: Drop obsolete sbx-derived images

> **Status:** Complete (Runtime Verification Deferred to Windows)
> **Execution Date:** 2026-08-03
> **Completed By:** agent (orchestrated run)
> **Source Plan:** 2608022321-drop-obsolete-sbx-images-plan.md
> **Execution Log:** 2608022321-drop-obsolete-sbx-images-log.md
> **Execution Branch:** `projex/2608022321-drop-obsolete-sbx-images`
> **Duration:** 14 minutes (04:56–05:10 UTC)
> **Result:** Static cutover recovered and merged; mandatory runtime verification deferred to a Windows host

---

## Summary

Execution completed and committed the planned static source cutover on the isolated branch, then stopped at mandatory Step 4 because PowerShell and every plan-permitted container engine were absent. Static work was not accepted as a substitute for image/runtime proof at the initial close.

The user subsequently directed recovery and closure despite that host limitation. Product changes from `76df874` were recovered and merged; required PowerShell/container runtime verification remains deferred to a Windows host. No runtime engine, prepared context, manifest, image ref/ID, container, auth attempt, distribution event, credential artifact, or run-owned cleanup target was created.

---

## Objectives Completion

| Objective | Execution outcome | Final repository outcome |
|---|---|---|
| Preserve rm-guard in both self-built definitions | Complete on execution branch | Recovered and merged; build/runtime proof deferred |
| Preserve Codex Playwright CLI + Chromium | Complete on execution branch | Recovered and merged; build/runtime proof deferred |
| Promote self-built definitions to canonical `Dockerfile` | Complete on execution branch | Recovered and merged; build/runtime proof deferred |
| Align build/docs callers | Complete on execution branch | Recovered and merged; build/runtime proof deferred |
| Prove both images through one controlled engine/runtime lineage | Blocked | Deferred to a Windows host; not accepted as verified |

Overall product objective: **Static cutover merged; runtime verification deferred**. Branch commit `76df874` supplied the recovered static implementation.

---

## Execution Detail

> Actual history source: `git log`, `git diff --stat`, and `git diff --name-status` for `main..projex/2608022321-drop-obsolete-sbx-images`, plus 2608022321-drop-obsolete-sbx-images-log.md. Post-change line numbers below identify abandoned branch content.

### Step 1: Preserve image capabilities

**Planned:** Port same-suite rm-guard install/self-test blocks into both self-built definitions; add pinned Playwright CLI + Chromium to Codex.

**Actual:**
- `claude/Dockerfile.slim`: inserted rm-guard install and checks after browser layers, before Claude cachebust layer.
- `codex/Dockerfile.slim`: added `PLAYWRIGHT_VERSION=1.61.1`, global CLI link/ownership/version check, agent-owned Chromium cache, then rm-guard before `USER agent`.

**Deviation:** None in source implementation.

**Verification:** Static layer-order/source inspection only. Build-time self-tests and immutable-ID runtime probes did not run.

**Issues:** None until later host-tool preflight.

### Step 2: Delete sbx-derived files and promote self-built files

**Planned:** Delete both legacy canonical files; rename both prepared `.slim` files to `Dockerfile`; neutralize variant-only comments.

**Actual:** `del-n-stage` deleted the two legacy paths; `move-n-stage` promoted both self-built files. Final branch inventory had one `Dockerfile` per suite and no `.slim`; both `FROM` lines were `node:25-bookworm-slim`. Generic `/etc/sandbox-persistent.sh` hooks remained.

Pre-swap source: `db056f5e72c5b065492fa66119f0c5d0758d6d79`.

| Path | Pre-swap SHA-256 |
|---|---|
| `claude/Dockerfile` | `a44d2982e5df4fb372eaab15d88ae6808a8df4656340d7ca77829d102fc850b2` |
| `claude/Dockerfile.slim` | `6bd626934a7ceab173a1eb479ca3449127181b67930b81f8a1d17905728be8ff` |
| `codex/Dockerfile` | `50fbbccbda90ddd645ce02626b5f4bf0de1f9c4cdec84630b4130dd032029629` |
| `codex/Dockerfile.slim` | `ec70c671023cb7a714e1e1f681d35847f6d882312c757cd370a88eadba9200ca` |

**Deviation:** None during execution. Close later abandoned all source changes because Step 4 was mandatory.

**Verification:** Helper results + static inventory/base inspection. No image build.

### Step 3: Align build drivers and documentation

**Planned:** Default Claude to canonical `Dockerfile`; update Claude/Codex Build, Run, Layout, and base-image prose; retain direct Docker/Podman launchers; leave `codex/build.ps1` unchanged.

**Actual:** `claude/build.ps1` default became `Dockerfile`; both READMEs described one Node 25 self-built image, direct launchers, baked browser tooling, and rm-guard as accident protection. `codex/build.ps1` stayed unchanged with its existing canonical default.

**Deviation:** None.

**Verification:** End-to-end README review and maintained-source search returned no branch matches for `Dockerfile.slim`, `docker/sandbox-templates`, or `sbx run` outside historical `.projex/` documents.

### Step 4: Validate builds and runtime parity

**Planned:** One PowerShell/container-engine lineage: controlled input preparation → two builds → immutable IDs → network-disabled direct/browser/rm-guard probes → manual credential trust gate → exact-ID launcher smoke → sanitized ledger → scoped cleanup.

**Actual:** Bound static review to source `6a81e1fb4e3c74e8baa205eee33e43903c453a28`; recorded prepare-script blobs (`claude` `f1e5bccdfc7c96107e95a3ee28cd8235876890e3`, `codex` `182adcba3b5cd0ad7c051930e3899363cceb052c`); then checked tool availability before creating runtime inputs. `pwsh`, `powershell.exe`, `docker`, `docker.exe`, `podman`, and `podman.exe` were absent (`which` exit `1`). Execution stopped.

**Deviation:** Host-tool availability should have been checked during manual pre-execution validation, not after Steps 1–3. This caused completed source commits to precede blocker discovery, but isolation prevented an unverified integration.

**Verification:** Independent verify-projex round 1: **Rejected**. Static state could not satisfy mandatory runtime claims.

**Issues:** External `engine/store` blocker. No bypass, alternative engine, persistent host install, or product re-execution attempted during close.

---

## Complete Change Log

**Authoritative execution diff:** `main..projex/2608022321-drop-obsolete-sbx-images` = 9 files, +290/-554. These changes existed only on the abandoned branch.

### Files Created

| File | Purpose | In plan? |
|---|---|---|
| `.projex/2608022321-drop-obsolete-sbx-images-log.md` | Execution evidence and blocked ledger | Lifecycle-required |

### Files Modified

| File | Actual changes | Post-change branch lines | In plan? |
|---|---|---:|---|
| `.projex/2608022321-drop-obsolete-sbx-images-plan.md` | Execution status + log link | 3, 8 | Lifecycle-required |
| `claude/Dockerfile` | Promoted self-built Node 25 definition; retained Playwright; added rm-guard/self-tests; neutralized variant comments | 1–7, 22–23, 103–157, 167–168 | Yes |
| `claude/build.ps1` | Canonical default and variant-neutral cachebust comment | 28, 107–111 | Yes |
| `claude/README.md` | One-image intro/build/run/layout/base note; rm-guard boundary | 3–27, 59–75, 155–169, 185–190 | Yes |
| `codex/Dockerfile` | Promoted Node 25 definition; Playwright CLI/Chromium; rm-guard/self-tests; neutralized comments | 1–7, 15–24, 62–110 | Yes |
| `codex/README.md` | One-image intro/build/run/layout/base note; rm-guard boundary | 3–25, 34–45, 87–104, 145–152 | Yes |

### Files Deleted

| File | Reason | In plan? |
|---|---|---|
| `claude/Dockerfile.slim` | Self-built content promoted to canonical filename on execution branch | Yes |
| `codex/Dockerfile.slim` | Self-built content promoted to canonical filename on execution branch | Yes |

### Planned But Not Changed

| File | Planned handling | Actual |
|---|---|---|
| `codex/build.ps1` | Inspect; no edit unless drift required it | Correct existing `Dockerfile` default; unchanged as planned |

### Close Integration

Only lifecycle records reached `main`: closed plan, execution log, walkthrough, and resolved red-team document. Product paths above remained at base state because Option D deleted the execution branch rather than merging it.

---

## Success Criteria Verification

| Criterion | Method | Result | Evidence |
|---|---|---|---|
| One image definition per paired suite | Branch inventory | Pass (branch only) | Only `claude/Dockerfile`, `codex/Dockerfile`; no `.slim` |
| No Docker sbx product base | `FROM` inspection + maintained-source search | Pass (branch only) | Both Node 25; zero retired-base hits |
| Canonical build defaults | Static defaults + required controlled build | **Blocked** | Defaults correct; build commands not run |
| Immutable one-engine lineage | Engine/ref/ID ledger | **Blocked** | No permitted engine, refs, or IDs |
| rm-guard parity | Source inspection + build/direct probes | **Blocked** | Source blocks present; no build/runtime proof |
| Browser parity | Source inspection + offline exact-ID probes | **Blocked** | Layers present; no browser execution |
| Maintained docs match cutover | Scoped search + Build/Run/Layout read | Pass (branch only) | No retired maintained command/path |
| Launcher/runtime intact | Trust gate + exact-ID `run.ps1` smoke | **Blocked** | Prerequisites unmet; approval not requested |
| Local-only + safe evidence | Distribution/auth artifact review | Pass | No export, push, load, registry, auth, or secret output |
| Atomic approval | Mandatory-row/invalidation review | **Blocked** | Runtime rows lacked current-lineage Pass evidence |

**Overall:** 4/10 evidence rows passed on the execution branch; 6/10 mandatory rows blocked. Plan no-go rule applied. Because static branch passes were not merged, they are historical execution outcomes—not claims about final `main` product state.

---

## Deviations and Issues

### Late host-tool preflight
- **Planned:** Confirm one engine during execution-start assumptions.
- **Actual:** Checked at Step 4 after source commits.
- **Impact:** Static work completed but could not be approved; worktree isolation made full abandonment safe.
- **Prevention:** Treat required PowerShell and engine availability as a hard pre-edit gate for a future execution.

### Runtime verification unavailable
- **Severity:** High; blocks approval.
- **Resolution:** None in this environment. Correct close action was abandonment, not weaker verification.
- **Preserved evidence:** Exact missing executables, static source revision, prepare-script revisions, no-artifact ledger, independent rejection.

---

## Key Insights

1. **Static parity is not runtime parity.** Dockerfile layers cannot prove installed executables, ownership, offline browsers, guard behavior, or launcher mounts.
2. **Worktree isolation contained no-go work.** Five source/lifecycle commits were reviewable, then discarded without touching product paths on `main`.
3. **Tooling preflight belongs before mutation.** External prerequisites known to be mandatory should gate Step 1, even when source work is independently correct.
4. **No artifact is meaningful evidence.** Because failure occurred before preparation/build/auth, cleanup had zero runtime targets and there was no distribution or credential exposure.

### Gotchas

- A clean static diff is not an approval surrogate when the plan explicitly requires one immutable image lineage.
- Installing unplanned host tooling or changing engines during close would alter scope and evidence lineage.
- Abandoning the branch must not discard the log/walkthrough; lifecycle records were integrated separately before helper cleanup.

---

## Recovery Closure

- **Decision:** user directed recovery and closure despite the unavailable Linux-host verification tooling.
- **Action:** recovered execution commit `76df874`; merged static source changes on 2026-08-03.
- **Deferred:** PowerShell plus a Docker or Podman engine must be available on Windows before the controlled prepare/build/immutable-ID/direct-probe/trust/launcher/ledger sequence can establish runtime evidence.
- **Evidence boundary:** recovery did not create runtime artifacts, distributions, auth attempts, or credentials. Static checks recorded by the original execution remain the only completed verification.

---

## Related Projex Updates

| Document | Close action |
|---|---|
| 2608022321-drop-obsolete-sbx-images-plan.md | Closed lifecycle metadata updated with recovery/deferred-runtime qualifier |
| 2608022321-drop-obsolete-sbx-images-log.md | Historical blocked execution record retained |
| 2608022327-drop-obsolete-sbx-derived-images-plan-redteam.md | Findings were incorporated into revised plan; linked here and moved to `closed/` |
| 2608021410-retire-sbx-legacy-plan.md | Broader blocked plan remains active; unrelated pre-existing edit preserved through stash/restore |

No Nav was referenced. No new follow-up projex was created.

---

## Appendix

### Execution commits (abandoned)

```text
76df874 projex: block drop-obsolete-sbx-images verification
ebe52f0 projex: step 4 - record blocked runtime verification
6a81e1f projex: step 3 - align canonical build docs
9280a00 projex: step 2 - promote self-built Dockerfiles
db056f5 projex: step 1 - preserve image capabilities
```

### Blocker probe

```text
pwsh, powershell.exe, docker, docker.exe, podman, podman.exe: absent (`which` exit 1)
```

### Runtime artifact ledger

```text
source: 6a81e1fb4e3c74e8baa205eee33e43903c453a28
context manifest: N/A (prepare not run)
engine/version: N/A (Docker/Podman absent)
refs/image IDs: N/A
distribution: none
auth/credentials: not attempted
cleanup targets: none created
```
