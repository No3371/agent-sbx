# Modernize Codex sandbox suite

> **Status:** In Progress
> **Author:** openai-codex/gpt-5.6-sol (plan-projex)
> **Source:** Direct request — modernize Codex suite to parity with updated suites, including root runtime and robocopy staging
> **Related Projex:** 2608030651-codex-incremental-context-staging-patch.md (robocopy baseline) | 2608030706-coding-agent-sandbox-suite-contract-def.md (shared contract; observed state predates recent Pi/OpenCode updates) | 2608030408-c-c-combined-suite-plan.md (downstream; must rebase Codex assumptions) | 2608030409-retire-merged-codex-suite-plan.md (downstream retirement, dependency-gated) | 2608101607-codex-suite-modernization-plan-redteam.md (revision trigger) | 2608101613-codex-suite-modernization-plan-stress.md (revision trigger)
> **Worktree:** Yes

---

## Summary

Move the standalone Codex image from passwordless-sudo `agent` to root, adopt Pi's current file-or-directory `robocopy` transport for Codex's filtered preparation, extend it to the shared host `~/.agents/skills` tree, and align root-home cache/bootstrap behavior with updated suite patterns. Preserve Codex-specific TOML/plugin transforms, fresh device authentication, approval bypass, browser tooling, and ephemeral auth/history semantics. Root runtime does not authorize root execution of host-derived package lifecycle scripts.

**Scope:** standalone `codex/` suite implementation/docs; no combined-suite, root-contract, retirement, package-catalog, image-name migration, acceptance harness, or acceptance-receipt artifact.
**Estimated Changes:** 6 files — `Dockerfile`, `prepare.ps1`, `build.ps1`, `run.ps1`, `README.md`, new suite-local `.gitignore`.

---

## Objective

### Problem / Gap / Need

`codex/Dockerfile` still creates `/home/agent`, grants passwordless sudo, installs browser/config state there, and ends as `USER agent`. `codex/run.ps1` compensates for fresh-volume ownership with `sudo chown` and uses generic cache/`node_modules` volume names. Meanwhile, recent root-runtime suites operate from `/root`, and recent preparation updates stage the cross-agent `~/.agents/skills` standard with native `robocopy /MIR` plus destination-side exclusion cleanup.

Codex already has a verified incremental robocopy implementation for `skills/`, `vendor_imports/skills/`, and `plugins/cache/`; modernization must extend that implementation, not replace it with a full-tree mirror that would bypass Codex's config filtering.

### Success Criteria

- [ ] Built image defaults to UID/GID 0, `HOME=/root`, `WORKDIR=/workspace`; no maintained Codex product reference requires `/home/agent`, user/group `agent`, passwordless sudo, or ownership repair. Host-derived plugin lifecycle scripts never execute with root authority.
- [ ] Existing prepared Codex payload lands under `/root/.codex`; synthesized marketplace `source` paths also use `/root/.codex`; copied plugin package roots have a relative-path/SHA-256/lifecycle-script inventory.
- [ ] `prepare.ps1` mirrors host `~/.agents/skills` → `codex/context/.agents/skills` with native robocopy contract, recursive SCM/native-dependency/credential exclusions, missing-source placeholder, stale-exclusion cleanup, LF normalization, canonical source/destination containment, no reparse traversal, and collision failure between skill roots; both generated context roots are Git-ignored.
- [ ] `build.ps1` forwards independent host/source overrides for both `.codex` and `.agents/skills` preparation without changing default build/export semantics.
- [ ] `run.ps1` uses root-home, generation-aware Codex volumes; no `sudo`/`chown`; mounts only workspace plus package caches; performs fresh `codex login --device-auth` before bypass mode.
- [ ] Docker Desktop on Windows remains the intended release-supported engine/platform. Podman remains unadvertised until equivalent validation establishes its support contract.
- [ ] `README.md` exactly describes root privilege, trusted-payload limitation, staged inputs, cache names/generation, exclusions, Docker-default support, unsupported Podman status, and unchanged auth/history boundaries.

### Out of Scope

- `sbx-codex` image/artifact renaming; current `codex-custom:v1` identity remains.
- New Go/.NET/Python selectors, pnpm, package upgrades, or a new Codex CLI pin.
- Persisting/mounting Codex auth, sessions, logs, SQLite state, or other host runtime state.
- Changing `--dangerously-bypass-approvals-and-sandbox`, device-auth flow, CodeGraph failure policy, GPU handling, timezone mapping, workspace mount, or rm-guard behavior.
- Editing root `.projex/`, `.gitignore`, `c_c/`, `claude/`, `pi/`, `omp/`, `opencode/`, retirement artifacts, or generated personal context in place.
- Reading or copying real credential/session contents during verification.
- Claiming a filename filter proves arbitrary staged content is secret-free, or advertising Podman support before its platform row passes.

---

## Context

### Current State

- `codex/Dockerfile`: `node:25-bookworm-slim`; global Codex/CodeGraph/agent-browser/Playwright install; renames image user `node` to UID-1000 `agent`; creates passwordless sudo; browser/config/cache state under `/home/agent`; final `USER agent`, `WORKDIR /home/agent`.
- `codex/prepare.ps1`: verified incremental `robocopy /MIR` only for three filtered `.codex` subtrees. It separately writes `AGENTS.md`, rewrites `config.toml`, synthesizes local plugin marketplaces, strips credential-pattern files, and hardcodes generated image marketplace roots to `/home/agent/.codex`. Pi's current transport baseline is `pi/prepare.ps1:51-115` at `9d3e6b5`: `Invoke-RobocopyStage` branches on `Get-Item`, mirrors directories, and copies a leaf file via its resolved parent paths without mirroring siblings.
- `codex/build.ps1`: common local build/export driver; invokes preparation with optional `HostCodexDir`/`Destination` only; Docker is code default despite stale README text claiming Podman.
- `codex/run.ps1`: workspace bind + generic `pm-cache` and workspace-keyed `nmvol-*`; fresh volume gets `sudo chown agent:agent`; Podman adds `--userns=keep-id`; Codex authenticates inside each ephemeral container.
- Updated comparisons: Pi establishes root-home runtime/cache behavior; OpenCode/Pi establish separate `~/.agents/skills` robocopy staging. Neither comparison overrides Codex-specific auth/config semantics.
- `2608030408-c-c-combined-suite-plan.md` and `2608030409-retire-merged-codex-suite-plan.md` are dependency-gated, unexecuted downstream directions. Their Codex baseline claims are already stale versus the completed robocopy patch; this plan adds further drift they must re-research before execution.

### Key Files

| File | Role | Change Summary |
| --- | --- | --- |
| `codex/Dockerfile` | Image user, tooling, prepared config, entrypoint | Remove agent-user layer; install/copy/run from root; add cross-agent skills COPY; work in `/workspace` |
| `codex/prepare.ps1` | Filtered host → build-context staging | Add `~/.agents/skills` mirror, root image paths, shared cleanup/LF handling, early required-input validation |
| `codex/.gitignore` | Suite-local generated-input guard | Ignore both generated context roots without editing root scope |
| `codex/build.ps1` | Prepare/build/export orchestration | Add host-skills source/destination overrides and forward both to preparation |
| `codex/run.ps1` | Runtime mounts/bootstrap | Use root cache paths, Codex-specific volume namespace, no ownership repair/userns remap |
| `codex/README.md` | Operator/security contract | Document root/payload/engine/cache boundaries; fix stale engine/user/path claims |

### Dependencies

- **Requires:** implementation follows the stated Windows PowerShell 5.1/`robocopy.exe` and Docker Desktop/Windows contracts when those environments are used. Current Linux environment has none of Docker, Podman, PowerShell, or robocopy; this does not block implementation under the waived Step 0 gate.
- **Blocks:** no acceptance-resource or receipt gate blocks this Plan. `2608030408-c-c-combined-suite-plan.md` and retirement retain their own dependency and acceptance decisions; this revision does not grant them acceptance evidence.
- **No code dependency:** dirty root/Pi work and active `projex/*` branch are isolated through required worktree mode.

### Constraints

- Keep `prepare.ps1` Windows PowerShell 5.1-compatible; no PowerShell 7-only syntax/APIs.
- Preserve robocopy interpretation: `0..7` success, `>=8` failure; reset `$LASTEXITCODE`; disable native-error promotion when available.
- Do not mirror host `.codex` wholesale. Generated `config.toml`, `AGENTS.md`, local marketplace manifests, and `.system` filtering remain authoritative.
- Before any destination mutation, canonicalize all source/destination paths; reject filesystem roots, destination/source equality or ancestry, destination overlap, path escapes from the generated context envelope, and reparse points on traversed source/destination paths. Require a generated-root marker before stale cleanup.
- Every Dockerfile path, generated TOML path, launcher mount, cache path, and doc path must migrate atomically from `/home/agent` to `/root` where it represents image/runtime state.
- Root execution makes rm-guard easier to bypass; README must state accident protection only, not privilege/security isolation.
- Prepared host trees are explicitly trusted local build inputs, not proven secret-free by filename filtering. Verification uses synthetic data only; real trees are never inspected for content.
- Docker Desktop on Windows is the intended release support contract. Podman may receive fake-argv coverage but cannot be documented as supported without equivalent live platform validation.

### Assumptions

- Current Codex CLI discovery of `~/.agents/skills` is version-dependent. Acceptance requires a documented, observed result for a synthetic sentinel and fails closed on duplicate canonical skill names; it never relies on undocumented precedence.
- Root is intentional for this dedicated local sandbox; no multi-tenant or least-privilege claim is retained. A temporary unprivileged plugin-dependency build phase remains required.
- Existing fresh device-auth/no-history behavior is intentional and must not be “parity-normalized” to other suites.
- Generic existing cache volumes may remain on operator hosts after migration; they are not deleted automatically. New volumes include Node/lockfile generation so stale dependency state is not silently reused.

### Impact Analysis

- **Direct:** image layer ownership/home paths; two prepared context roots; containment/inventory; build parameter pass-through; runtime cache mounts/bootstrap; docs.
- **Adjacent:** plugin marketplace paths embedded in generated `config.toml`; agent-browser/Playwright cache locations; named volume continuity; Podman identity behavior.
- **Downstream:** combined-suite plan must consume the new root/skills baseline; retirement inventory file roster stays valid but its replacement-parity evidence must use the modernized source.
- **Security:** root simplifies local volume/tool operation but removes the weak speed bump of non-root execution. Credential exclusion and no-auth-mount boundaries remain mandatory.

---

## Implementation

### Overview

Migrate image/runtime paths, extend preparation without weakening Codex transforms, forward new preparation controls through the build driver, then update operator docs. Step 0's acceptance-resource, harness, and receipt gate is waived; implementation verification remains scoped to product behavior.

### Step 0: Provision acceptance resources and durable evidence — superseded

**Status:** Superseded by direct human waiver.

This gate would have required named Windows/Docker/operator resources, committed synthetic harnesses, and a durable acceptance receipt before implementation. It is not an implementation prerequisite or planned file scope.

**Trigger:** human directive, “what are these enterprise bs? Waive step0”.

---

### Step 1: Convert image to root runtime

**Objective:** remove UID-1000 agent plumbing and make `/root` + `/workspace` the canonical image/runtime homes.
**Confidence:** High.
**Depends on:** None.
**Verify-Projex: Required**

**Files:**

- `codex/Dockerfile`

**Changes:**

```dockerfile
# Before:
ENV ... PATH=/usr/local/share/npm-global/bin:/home/agent/.local/bin:$PATH ...
RUN ... usermod --login agent ...; usermod -aG sudo agent; ...
RUN HOME=/home/agent agent-browser install ... && chown ...
RUN HOME=/home/agent playwright install ... && chown ...
USER agent
WORKDIR /home/agent
COPY --chown=agent:agent context/.codex/... /home/agent/.codex/...

# After:
ENV ... PATH=/usr/local/share/npm-global/bin:$PATH ...
# no node→agent rename, sudoers entry, /home/agent tree, symlink/chown layer
RUN agent-browser install --with-deps
RUN playwright install --with-deps chromium
USER root
WORKDIR /workspace
COPY context/.codex/... /root/.codex/...
COPY context/.agents/skills/ /root/.agents/skills/
```

1. Retain base, apt tools, pinned shared-tool args, global npm prefix, `BASH_ENV`, git system config, rm-guard install/self-test, plugin dependency reinstall, `tini`, and Codex command.
2. Replace persistent-shell exports referencing `/home/agent/.local/bin` with root/global paths; write any retained user shell initialization under `/root`.
3. Remove `node` rename/user creation, sudo-group/sudoers setup, agent-home directory ownership, global-binary symlinks into agent home, and all `chown agent:agent` operations.
4. Install agent-browser and Playwright in root's default cache; verify browser binaries remain available offline.
5. Copy generated non-plugin `.codex` assets to `/root/.codex`; add prepared shared skills at `/root/.agents/skills`; retain repo-owned agent-browser skill under `/root/.codex/skills/agent-browser`.
6. Copy staged plugin packages to a dedicated non-root build location; create a no-login dependency user; run only `npm` with lifecycle scripts disabled (`--ignore-scripts`) as that user; reject package roots missing the expected package inventory; return the resulting files to `/root/.codex/plugins/cache` only after this phase. Do not run host-derived scripts as root or add a root compatibility exception.
7. Hash/assert critical root-owned binaries, guard, profile files, and package inventory after plugin handling; hostile fixture lifecycle markers must be absent.
8. Set final working directory `/workspace`; preserve `ENTRYPOINT ["tini", "--"]` and Codex bypass `CMD`.

**Rationale:** direct root execution matches requested modern suite posture and removes sudo/ownership machinery rather than retaining a fake non-root abstraction.

**Verification:** Dockerfile static scan finds no `/home/agent`, `agent:agent`, sudoers write, or final `USER agent`; it permits only the dedicated non-login plugin-build identity. Build succeeds; immutable image probe reports `id -u=0`, `HOME=/root`, `pwd=/workspace`, expected CLI versions, executable browser binaries, `.codex` files, repo skill, shared-skills root, recorded critical hashes, and no hostile lifecycle marker.

**If this fails:** revert only `codex/Dockerfile`; inspect first failing layer/path. Do not compensate with broad `chmod 777`, recursive ownership changes, or a mixed `/home/agent` compatibility symlink.

---

### Step 2: Extend safe robocopy staging and root-path generation

**Objective:** stage cross-agent skills with Codex's existing incremental system while preserving every Codex-specific filter/transform.
**Confidence:** Medium — native robocopy and Codex plugin marketplace generation need differential fixtures.
**Depends on:** Step 1 target paths.
**Do-Projex: Encouraged**
**Verify-Projex: Required**

**Files:**

- `codex/prepare.ps1`
- `codex/.gitignore` (new)

**Changes:**

```powershell
# Before:
param(
    [string]$HostCodexDir = "$env:USERPROFILE\.codex",
    [string]$Destination  = (Join-Path $PSScriptRoot 'context\.codex')
)
$imageCodexHome = '/home/agent/.codex'

# After:
param(
    [string]$HostCodexDir           = "$env:USERPROFILE\.codex",
    [string]$HostAgentsSkillsDir    = "$env:USERPROFILE\.agents\skills",
    [string]$Destination            = (Join-Path $PSScriptRoot 'context\.codex'),
    [string]$SkillsDestination      = (Join-Path $PSScriptRoot 'context\.agents\skills')
)
$imageCodexHome = '/root/.codex'
```

1. Validate host `.codex` and required `config.toml` before mutating either destination. Treat `~/.agents/skills` as optional.
2. Before `New-Item`, `robocopy`, or cleanup: canonicalize both sources and destinations; require the two destination shapes beneath one generated context envelope; reject roots, source/destination equality or ancestry, destination overlap, source-tree destinations, and any traversed reparse point. Create/validate an envelope marker before deletion; every rejection proves zero mutation.
3. Retain independent mirrors for `.codex/skills` (top-level `.system` excluded), `vendor_imports/skills`, and `plugins/cache`; do not mirror the whole `.codex` root.
4. Port the current Pi `Invoke-RobocopyStage` source-kind behavior from `pi/prepare.ps1:51-115` at `9d3e6b5`, preserving Codex containment checks: a directory source uses the filtered `/MIR` path and deterministic `.keep`; a file source resolves source/destination parents, invokes `robocopy <source-parent> <destination-parent> <leaf>` without `/MIR`, and never copies source siblings or writes a directory placeholder. Reset `$LASTEXITCODE` and treat `0..7` as success in both branches. Use the file branch for host `AGENTS.md`; missing input retains Codex's generated empty-stub fallback. Invoke the directory branch for `$HostAgentsSkillsDir` → `$SkillsDestination`, with `.git`, `.github`, `node_modules`, `.keep`, and credential-pattern exclusions. Missing directory source produces deterministic `.keep`-only destination shape.
5. Generalize destination credential sweep and CRLF→LF shell normalization over both staged roots; reject source or destination reparse traversal rather than following it.
6. Remove stale excluded directories (`.git`, `.github`, `node_modules`) only after containment/marker checks; log relative sanitized paths only.
7. Build a sanitized staged-input inventory: relative path, SHA-256, package name/version, and declared lifecycle-script keys; never emit content, absolute source paths, or a claim that filename filtering proves content-safe.
8. Reject duplicate canonical skill names across Codex and shared roots. Retain malformed/nested `.system` and symlink fixtures as fail-closed cases; no precedence assumption is accepted.
9. Preserve Codex-only `AGENTS.md` empty-stub fallback, TOML section drops, MCP command rewrite, dropped-marketplace handling, generated marketplace manifests, bundled-marketplace exclusion, and final status messages; generate image-local marketplace sources under `/root/.codex`.
10. Add suite-local `.gitignore` entries `/context/.codex/` and `/context/.agents/`; generated personal build inputs remain untracked without changing root scope.
11. End with a sanitized summary naming both destination categories and unchanged `codex-custom:v1` next command; do not print host-personal absolute paths or file contents.

**Rationale:** reusing the verified helper retains incremental performance and stale-entry deletion. Whole-tree mirroring would copy sessions/state and overwrite generated config, so parity applies to transport/cleanup—not Codex's source selection. Suite-local ignores prevent the new generated root from escaping the existing root-only `.codex` ignore.

**Verification:** Windows PowerShell 5.1 AST parse; synthetic native-robocopy checks cover file cold/warm/change/missing cases plus directory cold, warm, changed+purged, missing optional skills, stale excluded-dir, stale credential, CRLF shell, top-level/nested `.system`, collision, malformed skill, source/destination root/equality/ancestor/overlap, source-tree destination, reparse, and robocopy-failure cases. File fixtures prove only the named leaf reaches the destination—no source-parent sibling or `.keep` leakage—and missing `AGENTS.md` produces only Codex's empty stub. Every rejected path asserts zero mutation. Compare normalized path/size/SHA-256 manifests for existing `.codex` outputs except expected `/root` marketplace source; prove shared sentinel appears only without a collision, excluded sentinels do not, package/script inventory is complete, and `>=8` terminates. `git check-ignore` must match both generated roots while a tracked suite file remains visible.

**If this fails:** delete only synthetic destinations and revert `prepare.ps1`; never inspect or clean the operator's real `.codex`/`.agents` trees. If Codex does not discover `/root/.agents/skills`, stop rather than baking undiscoverable duplicate content.

---

### Step 3: Forward both preparation roots through build

**Objective:** make automated and isolated builds control both host inputs/destinations.
**Confidence:** High.
**Depends on:** Step 2 parameter contract.
**Do-Projex: Encouraged**

**Files:**

- `codex/build.ps1`

**Changes:**

```powershell
# Before:
[string]$HostCodexDir = '',
[string]$Destination  = ''

# After:
[string]$HostCodexDir        = '',
[string]$HostAgentsSkillsDir = '',
[string]$Destination         = '',
[string]$SkillsDestination   = ''
```

1. Add optional `HostAgentsSkillsDir` and `SkillsDestination` parameters beside existing prepare pass-throughs.
2. Append each argument/value only when supplied; preserve prepare defaults when omitted.
3. Keep mandatory `-Image`, Docker default, no-selector catalog, canonical Dockerfile, no-cache behavior, local-only default, tar/retag/load validation, and no-push policy unchanged.
4. Update parameter comments/examples only where needed to identify the new paths; retain `codex-custom:v1` naming.

**Rationale:** isolated fixtures/worktrees must not depend on or overwrite the operator's real shared-skills stage.

**Verification:** PowerShell 5.1 AST parse; mocked `prepare.ps1`/engine argv checks prove default invocation, all four overrides, partial overrides, `-SkipPrepare`, and unchanged build/export validation. Expected: no empty-value flags and no host path printed through engine argv.

**If this fails:** revert `build.ps1`; staged fixture outputs are disposable. Do not alter preparation defaults to compensate for a forwarding bug.

---

### Step 4: Align launcher with root and isolate Codex caches

**Objective:** remove agent ownership bootstrap and mount persistent package state at root-owned, suite-specific paths.
**Confidence:** High.
**Depends on:** Step 1 image contract.
**Verify-Projex: Required**

**Files:**

- `codex/run.ps1`

**Changes:**

```powershell
# Before:
$nmVol = "nmvol-$hash"
$nmInstall = "sudo chown agent:agent /workspace/node_modules; ..."
'-v', 'pm-cache:/home/agent/.npm'
if ($Engine -eq 'podman') { $runArgs += '--userns=keep-id' }

# After:
$nmVol = "codex-nmvol-$hash"
$nmInstall = "if [ -z ... ]; then ...; fi;"
'-v', 'codex-pm-cache:/root/.npm'
# no sudo/chown bootstrap; no keep-id remap that defeats root identity
```

1. Preserve parameters, workspace hashing, Windows `node_modules` mask detection, npm/yarn/corepack decision, timezone map, GPU option, CodeGraph non-blocking setup, device auth, and final Codex command.
2. Namespace dependency/cache volumes by workspace plus lockfile and Node generation: `codex-nmvol-<workspace-hash>-<lock-hash>` and `codex-pm-cache-node25`; mount npm cache at `/root/.npm`. Empty/mismatched generation initializes a new volume; old volumes remain operator-owned.
3. Remove `sudo chown agent:agent` and any agent-home reference. Root writes fresh volumes directly.
4. Remove Podman `--userns=keep-id`. Docker Desktop/Windows is the only release row: require in-container and host-side create/edit/delete plus owner/mode assertions. Keep a Podman fake-argv regression only; do not claim or document support without its own passing live row.
5. Make CodeGraph bootstrap degradation explicit in the launcher before the privileged TUI starts; preserve its non-blocking policy.
6. Do not add auth/history/config mounts or environment secret forwarding.

**Rationale:** root should remove ownership bootstrap, not keep sudo as dead code. Suite names prevent accidental coupling to legacy generic volumes while leaving old volumes untouched for manual cleanup.

**Verification:** AST parse + fake-engine argv capture for Docker/Podman, with/without host `node_modules`, changed lockfile, timezone, and GPU. Assert root cache paths, generation names, no `sudo|chown|/home/agent|--userns=keep-id`, no auth/state mount, explicit CodeGraph degradation signal, and unchanged device-auth/bypass command. On Docker Desktop/Windows, live smoke creates, edits, deletes, and host-verifies workspace files; writes fresh named volumes; checks host owner/mode.

**If this fails:** revert `run.ps1`; do not delete legacy/new named volumes automatically. Diagnose engine-specific rootless Podman mapping separately rather than silently restoring non-root behavior.

---

### Step 5: Rewrite operator contract to match behavior

**Objective:** eliminate stale user/path/engine/staging claims and disclose root implications.
**Confidence:** High.
**Depends on:** Steps 1–4 final interfaces.
**Do-Projex: Encouraged**

**Files:**

- `codex/README.md`

**Changes:**

1. Intro/capability list: root runtime; `/root/.codex`; host `~/.agents/skills`; rm-guard accident-only warning without passwordless-agent wording.
2. Build section: `build.ps1` prepares automatically unless `-SkipPrepare`; Docker is the default and sole release-supported engine. Preserve mandatory image and transfer-mode examples; state Podman may be invoked only as unverified behavior, not a supported path.
3. Run/security: root privilege, workspace bind, fresh per-container device auth, no host auth/history mounts, bypass mode, GPU, and engine prerequisites.
4. Dependency/cache section: `codex-nmvol-*`, `codex-pm-cache`, `/root/.npm`, no ownership repair; explain old generic volumes are orphaned but not auto-pruned.
5. Layout/staging: use repo-relative `codex/` root; add `context/.agents/skills`; distinguish filtered Codex subtrees from shared-skills mirror; document missing-source placeholders, containment marker, stale exclusion cleanup, reparse rejection, collision failure, and inventory boundaries.
6. Config transform section: marketplace sources now `/root/.codex/...`; every other drop/keep rule unchanged.
7. Notes: root + approval bypass is for dedicated local use; staged data is explicitly trusted but filename filtering cannot prove arbitrary content secret-free; package scripts do not receive root authority; mutable base/unpinned Codex caveats, Docker-only release support, and Podman non-support remain explicit.

**Rationale:** root and additional host input materially change privilege, disclosure, cleanup, and reproducibility claims.

**Verification:** every command maps to actual parameters/defaults; scoped search finds no `/home/agent`, `USER agent`, passwordless-agent claim, Podman-default claim, generic `nmvol-`/`pm-cache` names, or omission of shared-skills staging. Cross-check README tables/paths against final Dockerfile and scripts.

**If this fails:** revert README only; implementation remains testable but plan cannot pass acceptance until docs are exact.

---

## Verification Plan

> Per-step checks prove local mechanics. Step 0's durable evidence/receipt binding is waived; checks below remain implementation targets, not a pre-execution resource gate.

### Automated Checks

- [ ] Parse changed `.ps1` product files with Windows PowerShell 5.1 when that environment is available; zero syntax errors.
- [ ] Exercise synthetic staging fixtures for cold/warm/change/delete/missing/failure/exclusion/credential/LF/collision/reparse/containment cases; every invalid path asserts zero mutation.
- [ ] Exercise build overrides, partial overrides, `-SkipPrepare`, no-cache, and output modes; no empty flags or source path reaches engine argv.
- [ ] Exercise Docker/Podman argv across masked/unmasked deps, changed lockfile, GPU, and timezone; assert generation-aware names, no auth/history mount, no agent-home token, and visible CodeGraph degradation.
- [ ] Scoped product search: no `/home/agent`, `agent:agent`, sudoers, root package-script execution, launcher `sudo|chown`, generic volume names, or Podman support claim.
- [ ] Build the canonical Dockerfile with an explicit test tag on Docker Desktop/Windows when available; check UID 0, `/root`, `/workspace`, expected tool/browser availability, `.codex` payload, repo skill, shared-skills root, critical files, and absent hostile lifecycle marker.
- [ ] Prepared `config.toml` contains only `/root/.codex` image-local marketplace sources and expected kept/dropped sections.

### Manual Verification

- [ ] On supported Docker Desktop/Windows row, launch from disposable external workspace; complete device auth using redacted attestation only; confirm TUI starts in `/workspace` as root and approval bypass remains explicit.
- [ ] Confirm shared sentinel is discoverable only in no-collision fixture; duplicate skill fixture fails staging rather than relying on precedence.
- [ ] Create, edit, delete, then host-verify workspace file and owner/mode; restart confirms workspace persistence while Codex auth/history remain ephemeral.
- [ ] Run masked `node_modules` with one lockfile twice, then changed lockfile: first initializes matching `codex-nmvol-*`; second reuses it; changed lock creates a new generation; host Windows tree remains unchanged.
- [ ] Confirm no real credential/session content is read or captured; use only synthetic manifests and redacted manual attestation.

### Acceptance Criteria Validation

| Criterion | How to Verify | Expected Result |
| --- | --- | --- |
| Root runtime + plugin authority | image check + hostile lifecycle fixture | UID 0 final runtime; no host-derived lifecycle script runs as root; critical hashes match expected values |
| Existing Codex config preserved | pre/post synthetic normalized manifests + TOML semantic assertions | only expected root path and shared-skills output differ |
| Shared skills safely staged | synthetic robocopy/collision/reparse checks + sentinel discovery | no reparse/overlap escape; duplicate fails; stale/credential/SCM/native-dep sentinels absent |
| Build interface complete | mocked prepare/engine checks | all four source/destination overrides forwarded exactly; defaults unchanged |
| Docker release contract | supported-row live workspace/volume matrix | create/edit/delete + host owner/mode pass; unsupported Podman absent from docs |
| Docs truthful | path/default/command/support cross-check | README matches implementation; states payload trust and Docker-only release support |

---

## Rollback Plan

Per-step rollback is specified above. Full abandonment:

1. Revert only the six scoped suite files from the modernization commits (including `codex/.gitignore`).
2. Rebuild the prior explicit `codex-custom:v1` tag; verify it returns to UID-1000 `/home/agent` behavior and prior prepared synthetic manifest.
3. Leave generated operator context, old/new named volumes, images, and credentials untouched unless the operator explicitly authorizes exact cleanup targets.
4. If a migration-built tag exists, remove/retag only that recorded image ID after confirming no active container uses it.
5. Record why root or shared-skills parity failed before any narrower retry.
6. On suspected payload/image compromise: stop downstream consumption; preserve the image digest and sanitized inventory; quarantine tag/volumes only with explicit operator authorization; have the credential owner assess/revoke the affected device-auth session; assess workspace ownership/damage before reusing the image.

---

## Revision Log

- **2026-08-10:** Rebased Codex staging transport on Pi's latest file-or-directory `robocopy` behavior; added file-branch `AGENTS.md` staging and sibling/placeholder-leak acceptance cases while retaining Codex transforms and containment — trigger: human requirement, “Use the latest robocopy code from pi suite which covers file-level copy”; source verified at `pi/prepare.ps1:51-115` in `9d3e6b5`.
- **2026-08-10:** Blocked Plan; added unprivileged plugin dependency phase, destination/reparse containment, fail-closed skill collisions, Docker-only release matrix, generation-aware caches, committed harness/receipt scope, and compromise response — trigger: 2608101607-codex-suite-modernization-plan-redteam.md § Critical Findings/Remediation/Final Assessment and 2608101613-codex-suite-modernization-plan-stress.md § Findings/Remediation/Final Assessment; re-verified current root package install at `codex/Dockerfile:110-113`, caller-selected staging roots in `codex/prepare.ps1:7-20`, and absent local Docker/Podman/PowerShell/robocopy.
- **2026-08-10:** Waived Step 0; marked its resource/harness/receipt gate superseded, removed its five artifact files and durable-evidence acceptance requirement, updated affected scope, dependencies, verification, rollback, and status to `Ready` — trigger: human directive, “what are these enterprise bs? Waive step0”.

## Notes

### Split Verdict

`No split — six tightly coupled suite files, five implementation steps, within size budget. Downstream c_c/root artifacts are read-only relationships, not implementation targets.`

### Risks

- **Root path missed in generated config:** semantic TOML assertions + zero `/home/agent` product scan.
- **Robocopy exclusion leaves stale sensitive content:** explicit destination-side credential and excluded-dir sweeps; synthetic stale sentinels.
- **Whole `.codex` accidentally mirrored:** helper calls remain allowlisted to three Codex subtrees plus independent shared-skills root.
- **Shared skill present but undiscoverable:** Codex-level sentinel discovery is acceptance, not filesystem presence alone.
- **Podman identity differs:** no release-support claim until its separate workspace/cache evidence row passes; no silent fallback to mixed user semantics.
- **Legacy volume data appears lost:** names intentionally change; no automatic deletion; README migration note.
- **Downstream plan drift:** combined/retirement workflows must re-read current Codex implementation and cannot rely on their older clean-rebuild/non-root claims.
- **Privilege expectation:** README states root + bypass mode and rm-guard limits prominently.

### Open Questions

None.
