# Drop obsolete sbx-derived images

> **Status:** Complete (Execution Blocked; Branch Abandoned)
> **Author:** agent (plan-projex, orchestrated run)
> **Source:** Direct request — "Drop obsolete images (Look at those where both Dockerfile and Dockerfile.Slim exist) using docker.sbx the docker product - we build our own images now."
> **Related Projex:** 2608022327-drop-obsolete-sbx-derived-images-plan-redteam.md (revision trigger; Fix Issues) | 2608021410-retire-sbx-legacy-plan.md (broader blocked draft; not a dependency) | 2607060236-run-images-without-sbx-plan.md | 2607061530-run-images-without-sbx-walkthrough.md | 2607081815-dockerfile-slim-guide.md
> **Worktree:** Yes
> **Log:** 2608022321-drop-obsolete-sbx-images-log.md
> **Completed:** 2026-08-03
> **Walkthrough:** 2608022321-drop-obsolete-sbx-images-walkthrough.md

---

## Summary

Retire the only two image definitions still based on Docker's `docker/sandbox-templates` product: `claude/Dockerfile` and `codex/Dockerfile`. Promote each suite's self-built `Dockerfile.slim` to the canonical `Dockerfile`, preserve intentional image capabilities before cutover, and update only build/docs text that would otherwise reference deleted variants.

**Scope:** root `.projex/` cross-suite image retirement; `claude/` + `codex/` only.
**Estimated Changes:** 7 tracked source paths — 2 legacy definitions deleted, 2 self-built definitions renamed + edited, 1 build driver edited, 2 READMEs edited.

---

## Objective

### Problem / Gap / Need

`claude/` and `codex/` each contain both `Dockerfile` and `Dockerfile.slim`. The unsuffixed files extend `docker/sandbox-templates:*`; the `.slim` files build images directly from official Node Debian images. Keeping both preserves obsolete Docker sbx product images, makes the canonical filename ambiguous, and leaves codex's default build pointed at the legacy definition.

Deletion cannot be blind: legacy definitions contain two capabilities absent from one or both self-built definitions. Both legacy definitions wire `rm-guard`; `codex/Dockerfile` also installs Playwright + Chromium while `codex/Dockerfile.slim` does not. Port those blocks before replacing files so the cleanup does not silently remove intended safety/tooling.

### Success Criteria

- [ ] `claude/` and `codex/` each contain exactly one canonical `Dockerfile`; neither contains `Dockerfile.slim`.
- [ ] Both canonical images use `node:25-bookworm-slim`; neither uses `docker/sandbox-templates`.
- [ ] Both canonical images retain the in-repo `rm-guard` wiring and its build-time positive/negative self-test.
- [ ] Codex canonical image retains global Playwright CLI + baked Chromium behavior from the retired definition.
- [ ] `claude/build.ps1` and `codex/build.ps1` build the canonical file with no `-Dockerfile` argument.
- [ ] Claude and codex Build/Layout docs describe one self-built image and contain no command targeting a deleted file or sbx launcher.
- [ ] Both images build through one engine from controlled, manifested inputs; immutable image IDs pass no-volume runtime/browser probes.
- [ ] A sanitized same-lineage ledger records every mandatory result before scoped cleanup; launcher smoke occurs only after manual credential trust approval.

### Out of Scope

- Repo-wide deletion of every `sbx` word or historical claim. `2608021410-retire-sbx-legacy-plan.md` covers that broader cleanup and remains separately blocked.
- `cursor/`, `opencode/`, or `omp/` image, script, README, and comment changes; none has a `Dockerfile`/`Dockerfile.slim` pair.
- Changes to `.projex/closed/`, suite-scoped `.projex/`, archived guidance, or historical command examples.
- Renaming `/etc/sandbox-persistent.sh` or `/etc/profile.d/sandbox-persistent.sh`; those are repo-owned generic sandbox hooks, not Docker sbx product images.
- Removing `claude/context/scripts/merge-claude-settings.sh` or changing settings behavior.
- Reworking image contents beyond parity required to retire the legacy definitions.
- Shared-base redesign in `2607271806-sbx-base-image-suite-plan.md` (abandoned) or the stale `pi`/cursor migration plan.

---

## Context

### Current State

| Suite | Legacy definition | Self-built definition | Build default | Relevant parity gap |
|---|---|---|---|---|
| claude | `claude/Dockerfile` → `docker/sandbox-templates:claude-code` | `claude/Dockerfile.slim` → `node:25-bookworm-slim` | `Dockerfile.slim` | self-built file lacks `rm-guard`; Playwright already present |
| codex | `codex/Dockerfile` → `docker/sandbox-templates:codex` | `codex/Dockerfile.slim` → `node:25-bookworm-slim` | `Dockerfile` (legacy) | self-built file lacks `rm-guard`, Playwright CLI, and Playwright Chromium |

Both self-built definitions already recreate the `agent` user, paths, shell hooks, config copy, agent-browser install, suite CLI, and `tini` entrypoint needed by `run.ps1`. Their headers explicitly describe omitted heavyweight base extras as intentional. The cutover therefore promotes the existing self-built design rather than reproducing Docker's sandbox-template base.

Prior art: `2607060236-run-images-without-sbx-plan.md` + `2607061530-run-images-without-sbx-walkthrough.md` established direct Docker/Podman launchers. `2607081815-dockerfile-slim-guide.md` documents why the claude self-built definition exists. `2608021410-retire-sbx-legacy-plan.md` found the parity gaps but expands into repo-wide prose cleanup and human-decision dependencies; this focused plan reuses verified image findings without inheriting that scope or blockers.

### Key Files

| File | Role | Planned change |
|---|---|---|
| `claude/Dockerfile` | obsolete sbx-derived image | delete, freeing canonical filename |
| `claude/Dockerfile.slim` | current self-built default | add rm-guard, neutralize variant-only header/comments, rename to `claude/Dockerfile` |
| `codex/Dockerfile` | obsolete sbx-derived image; current build default | port unique parity blocks, then delete |
| `codex/Dockerfile.slim` | self-built alternate | add rm-guard + Playwright/Chromium, neutralize variant-only header/comments, rename to `codex/Dockerfile` |
| `claude/build.ps1` | build driver | default `Dockerfile.slim` → `Dockerfile`; make cachebust comment variant-neutral |
| `claude/README.md` | claude build/run docs | document one self-built image; remove legacy variant and sbx launch instructions |
| `codex/README.md` | codex build/run docs | make self-built image canonical; remove alternate/legacy and sbx launch instructions |

`codex/build.ps1` is inspected but unchanged: its default already equals `Dockerfile`, which resolves to the promoted self-built definition after rename.

### Dependencies

- **Requires:** no design re-authorization. Execute from the plan's committed base revision; re-check named files for drift. Live launcher completion additionally requires credential-owner approval of a least-privilege account or explicit risk acceptance; absence leaves mandatory launcher rows Blocked.
- **Blocks:** no active workflow. The broader `2608021410-retire-sbx-legacy-plan.md` must reconcile this cutover if later resumed; it must not repeat these deletions/renames.
- **Ordering:** parity ports → deletion/rename → build/docs correction → controlled preparation + one-engine builds → no-auth direct probes → credential trust gate + manual launcher smoke → sanitized ledger → scoped cleanup.

### Constraints

- Preserve self-built files as source of truth; do not merge Docker sandbox-template base packages into them.
- Port parity blocks from the matching suite's legacy file with minimal adaptation.
- Keep rm-guard framing accurate: accident guard, not a security boundary; image user retains passwordless sudo.
- Keep `codex/build.ps1` untouched unless execution research finds post-plan drift; its existing default is already correct.
- Preserve generic `/etc/sandbox-persistent.sh`, CLI/config wiring, and `ENTRYPOINT ["tini", "--"]` behavior.
- Use explicit file paths for destructive moves/deletes; no wildcard deletion.
- Do not modify projex history during execution except the execution log/walkthrough required by its own workflow.
- Verification uses one recorded engine for both suites and runs by immutable image ID after build; tags are collision-free run identifiers, not evidence identity.
- Verification is local-only: no `-Tar`, `-Push`, `-Retag`, `-LoadToDocker`, `-LoadToPodman`, registry-qualified reference, cross-engine load, or remote cache/export.
- Prepare from run-owned minimal non-secret host directories into run-owned worktree staging. Reuse only the matching manifest with `-SkipPrepare`; never accept stale/default personalized context.
- No live credential/auth step before tracked-diff, prepared-input manifest, no-distribution, and exact-image-ID review. Credential owner must approve; use a least-privilege test account or record explicit risk acceptance.
- Evidence is redacted: retain normalized command shape, relative paths/hashes, phase, exit/result, image identity, criterion mapping, and cleanup only; never retain raw config/plugin/auth output or absolute personal paths.

### Assumptions

Verified at authoring:

- Only `claude/` and `codex/` have both `Dockerfile` and `Dockerfile.slim`.
- Legacy `FROM` values are `docker/sandbox-templates:claude-code` and `docker/sandbox-templates:codex`; self-built values are official Node bookworm-slim images.
- `claude/build.ps1:28` defaults to `Dockerfile.slim`; `codex/build.ps1:27` defaults to `Dockerfile`.
- Both legacy files wire same-suite `rm-guard/rm-guard.sh`; neither self-built file wires it.
- `claude/rm-guard/rm-guard.sh` and `codex/rm-guard/rm-guard.sh` are byte-identical at authoring (`md5 910b41a66b313be9405b5cf91e9de3c5`).
- Claude self-built file already installs Playwright CLI and Chromium; codex self-built file installs agent-browser only.
- Direct non-sbx `run.ps1` launchers already exist and are documented by the closed run-images-without-sbx plan/walkthrough.

Re-check at execution start:

- No new non-projex caller references `Dockerfile.slim` beyond `claude/build.ps1` and the two READMEs.
- `claude/.dockerignore` and `codex/.dockerignore` still allow `rm-guard/` into build context.
- Legacy parity blocks have not changed since plan authoring; if changed, compare semantics before copying.
- One selected engine can build, inspect, and run both images and is passed explicitly to both maintained launchers.
- Run-owned source, staged-context, and workspace paths are fresh; any pre-existing/unknown ownership fails preflight rather than being reused or deleted.

### Impact Analysis

- **Direct:** 7 paths listed above.
- **Adjacent:** callers passing `-Dockerfile Dockerfile.slim` must use the canonical default or `-Dockerfile Dockerfile`; current tracked callers are README examples being updated.
- **Downstream:** claude default image gains rm-guard; codex default filename switches from Docker sbx-derived image to self-built Node image while preserving rm-guard and Playwright. Codex intentionally loses unmodeled base extras (Docker CLI, Java, man-db, Ubuntu development bundle, clipboard bridge), already declared omitted by `Dockerfile.slim`.
- **Operational:** first codex self-built image build becomes heavier because Playwright downloads a second browser beside agent-browser's Chrome. This is parity with the retired image, not a new product promise.

---

## Implementation

### Overview

Prepare the two self-built definitions for sole ownership, then perform explicit delete + rename operations and align the only affected build/docs callers. Do not mix broader sbx prose cleanup into these steps.

### Step 1: Preserve image capabilities in self-built definitions

**Objective:** remove parity blockers before deleting legacy definitions.
**Confidence:** High — existing blocks are already used in same-suite Dockerfiles.
**Depends on:** None
**Verify-Projex: Encouraged**

**Files:**
- `claude/Dockerfile.slim`
- `codex/Dockerfile.slim`

**Changes:**

1. Add each legacy file's rm-guard comment + `COPY rm-guard/rm-guard.sh /usr/local/libexec/rm-guard.sh` + self-testing `RUN` block to its self-built peer.
   - Claude insertion: after Playwright's Chromium layer, before `ARG CLAUDE_CODE_CACHEBUST`; this keeps the stable guard layer above the intentionally cache-busted Claude install.
   - Codex insertion: after Playwright/agent-browser root layers and system git config, before `USER agent`.
   - Preserve checks that direct `/workspace/.git` and ancestor `/workspace` deletion fail, a normal `/tmp` deletion succeeds, and build-time fixture cleanup uses `/usr/bin/rm.real`.
2. Add codex Playwright parity as one contiguous root sequence:
   - declare `ARG PLAYWRIGHT_VERSION=1.61.1` with tool version args;
   - add `playwright@${PLAYWRIGHT_VERSION}` to global npm install, link/chown `/home/agent/.local/bin/playwright`, and run `playwright --version`;
   - install agent-browser, then run `HOME=/home/agent playwright install --with-deps chromium` and chown `/home/agent/.cache/ms-playwright`;
   - apply system git config, install/self-test rm-guard, then switch once to `USER agent`.
3. Do not port Docker sandbox-template base packages or entrypoint behavior; self-built definitions remain authoritative.

**Before / After:**

```dockerfile
# Before (both self-built definitions):
# ... root install layers ...
USER agent

# After (shape; use existing legacy block verbatim):
# ... root install layers, including codex Playwright ...
COPY rm-guard/rm-guard.sh /usr/local/libexec/rm-guard.sh
RUN set -eux; \
    # install wrapper + exercise blocked and allowed deletion paths
    ...
USER agent
```

**Rationale:** deletion must not silently remove explicit safety/tooling already provided by the canonical legacy filename. Copying proven same-suite blocks is lower risk than new abstractions.

**Verification:** inspect final layer order; build-time checks must fail the build on guard regression. Confirm codex npm + browser layers mirror claude's established Playwright pattern.

**If this fails:** revert only the two `.slim` files; do not start deletion/rename.

---

### Step 2: Delete sbx-derived files and promote self-built files

**Objective:** leave one canonical, self-built `Dockerfile` per suite.
**Confidence:** High
**Depends on:** Step 1
**Verify-Projex: Encouraged**

**Files:**
- `claude/Dockerfile`
- `claude/Dockerfile.slim`
- `codex/Dockerfile`
- `codex/Dockerfile.slim`

**Changes:**

1. Delete `claude/Dockerfile` and `codex/Dockerfile` with explicit paths using the projex delete helper.
2. Rename `claude/Dockerfile.slim` → `claude/Dockerfile` and `codex/Dockerfile.slim` → `codex/Dockerfile` with explicit pairs using the projex move helper.
3. In promoted files, rewrite only comparison comments that would retain a false two-variant model:
   - headers: identify official Node bookworm-slim base directly, not “slim instead of docker/sandbox-templates”;
   - package comments: state intentionally omitted heavyweight extras without naming sbx base;
   - ownership comments: attribute `/workspace` bind mount to `run.ps1`, not sbx;
   - codex agent-user comment: say paths match `run.ps1` mounts and baked config, not “sbx-derived image”.
4. Keep `/etc/sandbox-persistent.sh` names and functional lines unchanged.

**Before / After:**

```dockerfile
# Before: claude/Dockerfile
FROM docker/sandbox-templates:claude-code

# Before: claude/Dockerfile.slim
FROM node:25-bookworm-slim

# After: claude/Dockerfile
FROM node:25-bookworm-slim
```

```dockerfile
# Before: codex/Dockerfile
FROM docker/sandbox-templates:codex

# Before: codex/Dockerfile.slim
FROM node:25-bookworm-slim

# After: codex/Dockerfile
FROM node:25-bookworm-slim
```

**Rationale:** `.slim` only distinguished the self-built alternative from Docker's larger sandbox-template base. Once the obsolete image is gone, conventional `Dockerfile` is unambiguous and existing default build behavior remains simple.

**Verification:** before the swap, record committed source revision plus SHA-256 for the exact four paths; record delete/move helper results. Final inventory shows one `Dockerfile` per suite and no `.slim` variant; both `FROM` lines match expected Node bases; non-projex `docker/sandbox-templates` search in both suites is empty after Step 3.

**If this fails:** stop before caller updates. Restore the exact four paths from the recorded revision, confirm their hashes match the pre-swap ledger, and retain helper failure output in redacted form.

---

### Step 3: Align build drivers and suite documentation

**Objective:** every maintained build/run instruction targets the promoted files with no sbx dependency.
**Confidence:** High
**Depends on:** Step 2
**Do-Projex: Encouraged**

**Files:**
- `claude/build.ps1`
- `claude/README.md`
- `codex/README.md`

**Changes:**

1. `claude/build.ps1:28`: default `Dockerfile.slim` → `Dockerfile`.
2. Keep `$declaresCachebust` behavior; rewrite its preceding comment so it explains the probe generically rather than contrasting `.slim` and sbx definitions.
3. Do not edit `codex/build.ps1`; verify its existing `Dockerfile` default now resolves to promoted content.
4. Rewrite each README's intro + Build + Run + Layout + base-image note as one-image documentation:
   - describe official Node slim base and current baked tools;
   - default build command requires no `-Dockerfile` override;
   - delete alternate/legacy build examples and `sbx run` sections;
   - replace `Dockerfile.slim` layout/mentions with `Dockerfile`;
   - document rm-guard as an accident guard, not a security boundary;
   - codex docs state Playwright remains baked and the self-built image is now default;
   - preserve direct Docker/Podman `run.ps1` instructions.
5. Do not sweep unrelated comments/scripts merely because they contain “sbx”; log them under the broader blocked plan if discovered.

**Before / After:**

```powershell
# Before (claude/build.ps1)
[string]$Dockerfile = 'Dockerfile.slim',

# After
[string]$Dockerfile = 'Dockerfile',
```

```powershell
# Canonical build UX for both suites
./build.ps1 -Image <suite-image>:<tag>
```

**Rationale:** deleting image files without fixing default/docs callers leaves broken commands and an inaccurate two-image model. Restricting edits to direct callers keeps this plan focused.

**Verification:** search maintained claude/codex files (excluding `.projex/`) for `Dockerfile.slim`, `docker/sandbox-templates`, and `sbx run`; all return zero. Read Build and Run sections end-to-end and execute both default build commands in Step 4.

**If this fails:** revert the three documentation/driver files; keep Step 2 checkpoint intact and repair caller mapping before verification.

---

### Step 4: Validate canonical builds and runtime parity

**Objective:** prove both promoted images from one controlled source/input lineage build and preserve declared runtime + launcher contracts without distributing personalized artifacts.
**Confidence:** Medium — container downloads, registries, live auth, and credential-owner approval are environment-dependent; identity and no-auth checks are deterministic.
**Depends on:** Steps 1–3
**Verify-Projex: Required**

**Files:** no planned edits; any failure returns to its owning phase.

**Changes:** none.

**Verification:**

1. Establish one run lineage before preparation:
   - record committed source revision, reviewed tracked diff, prepare-script revisions, and Step 2 pre-swap path hashes;
   - select one `$Engine` (`docker` or `podman`) for both suites; record `$Engine --version`;
   - generate a UTC + random `$RunId`; assign bare local refs `$ClaudeRef = "claude-sbx-retirement:$RunId"` and `$CodexRef = "codex-sbx-retirement:$RunId"`;
   - require `image inspect` to report both refs absent before build. Never add distribution switches or destinations listed under Constraints; any distribution or unknown destination makes execution **Blocked/no-go**, because cleanup is not secure erasure.
2. Prepare controlled build inputs:
   - assign `$RunRoot` to a fresh ignored directory inside the isolated worktree; derive empty `$ClaudeHostSource`, `$CodexHostSource`, `$ClaudeWorkspace`, and `$CodexWorkspace` children; reject any pre-existing path, then create them;
   - run `./claude/prepare.ps1 -HostClaudeDir $ClaudeHostSource -Destination ./claude/context/.claude` and `./codex/prepare.ps1 -HostCodexDir $CodexHostSource -Destination ./codex/context/.codex`;
   - confirm staged inputs contain no third-party plugin, lifecycle-bearing `package.json`, hook, host MCP, credential, or auth payload. Include any committed project-derived config merged by preparation in tracked-diff review;
   - write a redacted manifest of suite-relative path, size, SHA-256, and prepare-script revision. Do not record file contents or absolute source paths.
3. Build exactly once from those manifests:
   - `./claude/build.ps1 -Image $ClaudeRef -Engine $Engine -SkipPrepare`;
   - `./codex/build.ps1 -Image $CodexRef -Engine $Engine -SkipPrepare`;
   - inspect each ref in `$Engine`, record immutable `$ClaudeImageId` / `$CodexImageId`, and use those IDs—not mutable tags—for every downstream command.
4. Run these deterministic direct probes with no volumes, no credentials, and disabled network:

   ```powershell
   $ClaudeProbe = @'
   set -eu
   test "$(id -un)" = agent
   claude --version
   pnpm --version
   codegraph --version
   agent-browser --version
   playwright --version
   test "$(stat -c %U /home/agent/.agent-browser)" = agent
   test "$(stat -c %U /home/agent/.cache/ms-playwright)" = agent
   printf '<title>sbx-retirement</title>' >/tmp/browser-probe.html
   agent-browser open file:///tmp/browser-probe.html
   test "$(agent-browser get title)" = sbx-retirement
   agent-browser close
   playwright screenshot file:///tmp/browser-probe.html /tmp/playwright-probe.png
   test -s /tmp/playwright-probe.png
   mkdir -p /workspace/.git
   printf 'ref: refs/heads/probe\n' >/workspace/.git/HEAD
   if rm -rf /workspace/.git; then exit 41; fi
   test -f /workspace/.git/HEAD
   touch /tmp/rm-guard-probe
   rm -f /tmp/rm-guard-probe
   test ! -e /tmp/rm-guard-probe
   '@

   $CodexProbe = @'
   set -eu
   test "$(id -un)" = agent
   codex --version
   codegraph --version
   agent-browser --version
   playwright --version
   test "$(stat -c %U /home/agent/.agent-browser)" = agent
   test "$(stat -c %U /home/agent/.cache/ms-playwright)" = agent
   printf '<title>sbx-retirement</title>' >/tmp/browser-probe.html
   agent-browser open file:///tmp/browser-probe.html
   test "$(agent-browser get title)" = sbx-retirement
   agent-browser close
   playwright screenshot file:///tmp/browser-probe.html /tmp/playwright-probe.png
   test -s /tmp/playwright-probe.png
   mkdir -p /workspace/.git
   printf 'ref: refs/heads/probe\n' >/workspace/.git/HEAD
   if rm -rf /workspace/.git; then exit 41; fi
   test -f /workspace/.git/HEAD
   touch /tmp/rm-guard-probe
   rm -f /tmp/rm-guard-probe
   test ! -e /tmp/rm-guard-probe
   '@

   & $Engine run --rm --network none --user agent --entrypoint sh $ClaudeImageId -lc $ClaudeProbe
   & $Engine run --rm --network none --user agent --entrypoint sh $CodexImageId  -lc $CodexProbe
   ```

   Exit `0` from each complete script is the only Pass. Network/download attempts fail under `--network none`; exit `41` identifies a guard that allowed protected deletion.
5. Apply the manual live-credential trust gate only after both direct probes pass:
   - reviewer confirms tracked diff, redacted manifests, exact already-probed image IDs, and no distribution event;
   - credential owner approves a least-privilege test account; otherwise records explicit risk acceptance. No approval → launcher rows **Blocked**, no auth attempt, no plan completion;
   - disable transcript/screen recording for live auth. Never retain OAuth URL/code/token/account ID, credential contents/path, MCP secret-bearing args/env/headers, or raw launcher output.
6. Run launcher integration separately against fresh run-owned empty workspaces and the same IDs:
   - `./claude/run.ps1 -Engine $Engine -Image $ClaudeImageId -Workspace $ClaudeWorkspace`;
   - `./codex/run.ps1 -Engine $Engine -Image $CodexImageId -Workspace $CodexWorkspace`;
   - manually confirm authenticated suite prompt starts as `agent`, `/workspace` is writable, and suite-owned state is writable (`.claude/projects` for claude; `.codegraph` for codex). Record milestone result only, not prompt/auth content;
   - acknowledge claude's live read-write credential + shared caches and codex's device auth + shared cache as accepted prerequisites. Remove only run-owned workspace state; never classify shared launcher volumes as disposable.
7. Before cleanup, write one sanitized ledger row per acceptance criterion: `Pass | Fail | Blocked | Not Run`, source revision, context-manifest ID, engine/version, image ref/ID, normalized command/result reference, and criterion mapping. Then remove only exact run refs/IDs, stopped run-owned containers, prepared destinations, minimal host-source dirs, and workspaces; record each cleanup result.

**Invalidation / no-go:** source revision, prepared context/manifest, engine, ref, or image-ID change invalidates all downstream results for the affected suite; source or engine change invalidates both. Rebuild → re-inspect ID and rerun direct, trust, launcher, ledger, and cleanup gates. Final approval requires both suites on the same source/run/engine lineage; any mandatory `Fail`, `Blocked`, `Not Run`, partial/mixed lineage, absent identity, distribution event, or unredacted evidence is no-go.

**Failure handling:** classify `bootstrap/context ownership | prepare | engine/store | registry/pull | Dockerfile layer | direct probe | trust gate | launcher/auth`. Retain redacted phase, normalized command, exit/result, and identity. Edit source only for a reproducible source-phase defect; auth refusal and external availability remain Blocked rather than triggering source churn.

**Rationale:** static diff checks cannot prove container layer order, executable links, baked offline browsers, guard behavior, launcher mounts, or that approval evidence belongs to the final bytes.

**If this fails:** return to the owning phase; do not combine prior green rows with a rebuilt/reprepared artifact. Apply invalidation rules and rerun all downstream gates.

## Verification Plan

### Automated Checks

- [ ] Exact file inventory: one `Dockerfile` each; no `.slim` files.
- [ ] Scoped non-projex searches: no `docker/sandbox-templates`, `Dockerfile.slim`, or `sbx run` in maintained claude/codex files.
- [ ] Controlled prepare produces a redacted manifest from run-owned minimal non-secret sources; matched builds use `-SkipPrepare`.
- [ ] One recorded engine builds both collision-free run refs; inspected immutable IDs back every downstream check.
- [ ] Dockerfile rm-guard self-tests pass during both builds.
- [ ] No-volume, no-auth, network-disabled direct probes pass CLI/tool, ownership, browser launch/close, rm-guard refusal, and normal-delete checks for both IDs.
- [ ] Sanitized ledger binds every mandatory result to source/context/engine/image identity before cleanup.

### Manual Verification

- [ ] Read both README Build/Run flows as a first-time operator: one canonical image, no deleted command/path.
- [ ] Review tracked diff + redacted manifests + direct-probe results + exact image IDs; confirm no distribution event.
- [ ] Credential owner approves least-privilege account or explicit risk acceptance before live auth; no auth output is recorded.
- [ ] Launch each exact ID through existing `run.ps1` with same engine and fresh run-owned workspace; authenticated prompt starts as `agent`, workspace and suite-owned state are writable.
- [ ] Confirm only run-owned workspaces/context/refs are removed; shared launcher volumes remain untouched and cleanup results are recorded.

### Acceptance Criteria Validation

| Criterion | How to verify | Expected result |
|---|---|---|
| One image definition per paired suite | scoped file inventory | only `claude/Dockerfile`, `codex/Dockerfile` |
| No Docker sbx product base | inspect `FROM`; scoped search | Node bookworm-slim bases; zero sandbox-template hits |
| Canonical build defaults | controlled prepare; run both `build.ps1` commands without `-Dockerfile` and with matched `-SkipPrepare` | promoted files build from manifested inputs |
| Immutable one-engine lineage | inspect refs/IDs; compare ledger identity fields | both suites share source/run/engine; every result names final image ID |
| rm-guard parity | build self-test + direct no-volume protected/unprotected probes | protected delete refused; normal delete succeeds |
| Browser parity | network-disabled direct agent-browser + Playwright launch/close and cache ownership | both baked stacks work as `agent` without download |
| Maintained docs match cutover | scoped search + read Build/Run/Layout | no deleted filename or sbx launch command |
| Launcher/runtime intact | manual trust gate + same-ID `run.ps1` smoke in run-owned workspaces | credential-approved prompt starts; workspace/suite state writable |
| Local-only + safe evidence | distribution gate; sanitized ledger before scoped cleanup | no export/push/load/remote sink; no secret/raw auth evidence |
| Atomic approval | inspect mandatory row states and invalidation history | every row Pass on current lineage; rebuild caused full downstream rerun |

---

## Rollback Plan

Per-step rollback precedes dependent work. If full cutover must be abandoned:

1. Use the recorded committed pre-swap revision and exact four-path SHA-256 set; restore both legacy `Dockerfile` paths and both `.slim` paths, then confirm source equality by inventory + hashes.
2. Restore `claude/build.ps1` default/comment and both READMEs; re-run scoped static gates. Record repository restoration separately from runtime restoration.
3. Remove parity-only edits from restored `.slim` files when returning exactly to pre-plan state.
4. Before cleanup, preserve the sanitized failure/rollback ledger. Dispose only run-owned ignored preparation destinations, minimal host-source dirs, launcher workspaces, stopped containers, and exact verification refs/IDs; verify each removal. Leave shared launcher volumes untouched.
5. Do not claim restored images work unless rebuilt and exercised. If rebuilt, assign a new run/manifest/image lineage; previous operational evidence remains invalid.
6. A tar/push/load/registry/remote-export event or unknown destination is not rollback-complete after local deletion: mark **Blocked**, record the redacted destination inventory, and escalate exposure handling.

No data migration or planned remote image deletion exists. Rollback proves tracked-source equality + run-owned generated-context disposal; it does not prove confidentiality erasure or old-image runtime without a new build.

---

## Revision Log

- **2026-08-02:** Kept the sound self-built cutover; replaced ambiguous Step 4, evidence, invalidation, and rollback contracts with one-engine immutable lineage, controlled minimal preparation, separate no-volume/browser probes and manual launcher trust gate, local-only distribution rules, redacted ledger, and scoped cleanup — trigger: 2608022327-drop-obsolete-sbx-derived-images-plan-redteam.md § Bottom Line, § Critical Findings 1–16, and § Remediation.
- **2026-08-02:** Standardized the planned Codex self-built base from `node:24-bookworm-slim` to `node:25-bookworm-slim`, matching Claude — trigger: direct requirement, "sync both to node25".

---

## Notes

### Risks

- **Codex base cutover changes implicit extras:** mitigation — retain only declared suite requirements; smoke actual maintained launcher/tool contract, not Docker base internals.
- **Browser layer cost:** mitigation — preserve layer ordering; prove both baked stacks offline before auth.
- **rm-guard overclaim:** mitigation — document as accident protection; test refusal and pass-through without host volumes.
- **Destructive filename collision:** mitigation — explicit helper calls plus recorded pre-swap revision/hashes and worktree isolation.
- **Mutable/personalized build input:** mitigation — run-owned minimal sources, redacted hash manifests, matched `-SkipPrepare`, immutable IDs.
- **Credential exposure:** mitigation — no-auth probes first; manual reviewed-image gate and credential-owner approval; never record auth.
- **Image/evidence distribution:** mitigation — prohibit every export/load/push/remote sink; retain redacted ledger before exact local cleanup.
- **Mixed-generation approval:** mitigation — identity change invalidates downstream rows; mandatory non-Pass or mixed lineage is no-go.
- **Historical false positives:** mitigation — exclude `.projex/` from source gates; history intentionally retains old names.
- **Broader plan overlap:** mitigation — this plan owns only paired-image retirement; broader blocked plan must reconcile before resumption.

### Split Decision

**No split — single root cross-suite scope, within size budget.** Four implementation steps are tightly coupled around one invariant: retire both paired Docker sbx-derived images while preserving the self-built canonical contract. Root `.projex/` already governs the prior cross-suite run-images-without-sbx lifecycle.

### Open Questions

None.
