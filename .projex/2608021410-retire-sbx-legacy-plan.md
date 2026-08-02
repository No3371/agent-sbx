# Retire sbx: drop legacy sandbox-template images + strip obsolete sbx references

> **Status:** Blocked
> **Reviewed:** 2026-08-02 — 2608021853-retire-sbx-legacy-review.md — Verdict: Revise
> **Author:** agent (Claude Opus 5) — projex subagent, orchestrated run
> **Source:** Direct request — "We have been building our own images for some time now, but we haven't removed trails of [docker] SBX from our repo. It's time to clean up the obsolete references."
> **Related Projex:** 2607060232-run-images-without-sbx-eval.md | 2607060236-run-images-without-sbx-plan.md | 2607060240-run-images-without-sbx-redteam.md | 2607061500-run-images-without-sbx-audit.md | 2607061530-run-images-without-sbx-walkthrough.md | 2607271806-sbx-base-image-suite-plan.md (**requires status-quo revision** — see Dependencies) | 2607271807-pi-cursor-base-migration-plan.md (**requires disposition/revision** — see Dependencies) | 2607271757-prepare-build-run-optimization-eval.md | 2608021423-retire-sbx-legacy-redteam.md (drove the first 2026-08-02 revision) | 2608021853-retire-sbx-legacy-review.md (triggered the current-state revision)
> **Worktree:** Yes

---

## Summary

`sbx` (Docker Sandboxes CLI) stopped being this repo's launcher when `run.ps1` landed (2607060236, closed). Two `FROM docker/sandbox-templates:*` Dockerfiles and 47 prose/config references survived (49 total sbx hits at `HEAD` `4ae972ae9a06`, incl. the two `FROM` lines). Retire the legacy images and strip every stale sbx claim, after porting the two capabilities that today exist **only** in the legacy files (rm-guard, codex playwright) into the slim ones.

**Scope:** `.gitignore`, `claude/`, `codex/`, `cursor/`, `opencode/`, `omp/` — Dockerfiles, `build.ps1`, `prepare.ps1`, `run.ps1` headers, READMEs, `merge-claude-settings.sh` header, obsolete artifact ignore rule. Root-`.projex/`-governed (cross-suite).
**Estimated Changes:** 20 tracked paths — 2 deleted, 2 renamed + edited, 16 edited. Baseline: **49 sbx hits across 20 files at `HEAD` `4ae972ae9a06`** (`git grep -n -i sbx HEAD -- . ':!*.projex/*'`). Exact roster matters: the count matches the former dirty-tree count, but `.gitignore` + `omp/prepare.ps1` replaced the old `pi/` composition.

> Line numbers below are as-of authoring, measured against `HEAD`. Steps 1–2 insert lines into the two `.slim` files; sites cited *below* an insertion point shift accordingly (only `codex/Dockerfile.slim:32` is affected — Step 2's `ARG PLAYWRIGHT_VERSION` block pushes it down ~3 lines). Match on text, not on line number.

**Blocking discovery:** `rm-guard` is wired into all five `Dockerfile`s and **neither** `Dockerfile.slim`. Since `Dockerfile.slim` is claude's default build, today's default claude image has no `/workspace/.git` delete protection. Deleting the legacy files without porting rm-guard first would make that permanent for claude and introduce it for codex.

---

## Preconditions (must clear before execution — this is why Status is `Blocked`)

**Cleared P1 — prior dirty `pi/` work landed in commit `4ae972ae9a06` (`Convert pi suite to OMP`).** The commit removed `pi/`, created `omp/`, and left no tracked worktree changes. This supersedes the commit/stash choice from the first revision. Current `HEAD` baseline: 49 hits / 20 files, including `.gitignore:26` and `omp/prepare.ps1:5`.

**P2 — both sibling plans need status-quo revision before this plan or either sibling executes.** `2607271806-sbx-base-image-suite-plan.md` (`Ready`) still proposes `sbx-base` and a three-Debian-suite premise invalidated by OMP's `oh-my-pi/pi:dev` base. `2607271807-pi-cursor-base-migration-plan.md` (`Ready`) still targets deleted `pi/` paths. Human decisions required: replacement shared-base name and `2607271807` disposition (cursor-only revision, current OMP/cursor replacement, or abandonment). See Dependencies § Blocks.

---

## Objective

### Problem / Gap / Need

Repo still carries the sbx era: `claude/Dockerfile` + `codex/Dockerfile` extend `docker/sandbox-templates:*` and exist only for `sbx run`; codex's `build.ps1` still **defaults** to that legacy file; READMEs document "Legacy sbx path (requires sbx + Win11)"; comments across all five suites explain behavior by attributing it to sbx ("sbx bind-mounts /workspace…", "sbx manages those", "no sbx integration here"). None of it is true of any image we build or run today. Readers and future agents inherit a wrong mental model of what the runtime is.

### Success Criteria

- [ ] **Exit check (not a standing invariant):** `git grep -i sbx -- . ':!*.projex/*'` returns **zero** hits on the execution branch at Step 7. Projex history is deliberately preserved, so this is permanently pathspec-dependent and nothing in the repo enforces it — there is no CI (no `.github/`), no pre-commit hook, no test. It is a one-time cleanup gate and regresses if either stale sibling plan executes or a new tracked sbx reference lands.
- [ ] `git grep 'sandbox-templates' -- . ':!*.projex/*'` returns zero hits
- [ ] `claude/Dockerfile` and `codex/Dockerfile` build from `node:*-bookworm-slim` (the former `.slim` content); no `Dockerfile.slim` remains in either suite
- [ ] `claude/build.ps1 -Image x` and `codex/build.ps1 -Image x` succeed with no `-Dockerfile` argument
- [ ] Both built images: `rm -rf /workspace/.git` blocked; `rm -f /tmp/probe` still works
- [ ] Both built images: `playwright --version` OK and `~/.cache/ms-playwright` populated
- [ ] claude image: `claude --version`, `pnpm --version`, `codegraph --version`, `agent-browser --version` OK as `agent`
- [ ] codex image: `codex --version`, `codegraph --version`, `agent-browser --version` OK as `agent`
- [ ] `/etc/sandbox-persistent.sh` mechanism still fires (settings merge + codegraph setup) in the claude image

### Out of Scope

- **Renaming `/etc/sandbox-persistent.sh`** and `/etc/profile.d/sandbox-persistent.sh` — "sandbox", not "sbx"; these are files *we* create in the slim images and are wired into `ENV BASH_ENV` / `CLAUDE_ENV_FILE`, `.bashrc`, `.profile.d`, `codegraph-setup.sh`, and `merge-claude-settings.sh`. Renaming is churn with runtime-breakage risk and no reader benefit.
- **Repo/remote name** `custom-sbx-templates` and the `custom_sbx/` root shown in README Layout blocks — the Layout blocks are corrected to `<repo>/` in Steps 4–5; renaming the GitHub repo is a human action outside this repo.
- **Sibling-plan redesign:** `2607271806` needs a non-sbx name plus a re-derived consumer premise; `2607271807` needs a human disposition because `pi/` no longer exists. See Dependencies § Blocks. Those are separate `revise-projex`/lifecycle decisions, not implementation edits made by this plan.
- Any behavior change beyond the two parity ports in Steps 1–2.
- **Retiring `merge-claude-settings.sh`** — it is a dead code path (see Context § Current State), but removing it is behavior, not prose. Follow-up plan.
- **Dangling `LICENSE` / `SECURITY.md` pointers.** `NOTICES.md:3` cites `LICENSE`; `claude/README.md:201` and `codex/README.md:158` cite `SECURITY.md`. Neither file exists (root tracked files: `.gitattributes`, `.gitignore`, `NOTICES.md`). Steps 4–5 rewrite the Notes blocks these lines sit in — leave the pointers alone and log a separate patch. `NOTICES.md` itself needs no change: it never attributed `docker/sandbox-templates`, and its Playwright entry (`:47-48`) already lists `codex/`, which Step 2 makes true rather than false.
- `opencode/`- and `codex/`-scoped `.projex/` documents (history, preserved).

---

## Context

### Current State

| Suite | `Dockerfile` | `Dockerfile.slim` | `build.ps1` default | rm-guard | playwright |
|-------|--------------|-------------------|---------------------|----------|------------|
| claude | `FROM docker/sandbox-templates:claude-code` (legacy, sbx-only) | `FROM node:25-bookworm-slim` (**default**) | `Dockerfile.slim` | legacy only | both |
| codex | `FROM docker/sandbox-templates:codex` (**still default**) | `FROM node:24-bookworm-slim` (alternate) | `Dockerfile` | legacy only | legacy only |
| cursor / opencode | `FROM debian:bookworm-slim` | — | `Dockerfile` | yes | yes |
| omp | `FROM ${OMP_BASE}` (`oh-my-pi/pi:dev` default) | — | `Dockerfile` | yes | yes |

`rm-guard/rm-guard.sh` already exists in all five suite dirs (added by commit `3f40cf6`, wired into `Dockerfile` only). `claude/.dockerignore` and `codex/.dockerignore` do not exclude `rm-guard/`, so it is already in both build contexts.

**`merge-claude-settings.sh` is a dead code path.** An earlier draft of this plan claimed the opposite ("not obsolete — `run.ps1` merges `worktree.bgIsolation` at launch, so a runtime baseline overwrite still happens") and asserted that this corrected the "bonus finding" in `2607060232-run-images-without-sbx-eval.md`. **That claim is withdrawn — the eval's bonus finding was right.** Three verified facts:

1. `claude/run.ps1:225` runs `jq '.worktree.bgIsolation = "none"'` — a single-key edit of the **baked** file, not a foreign baseline replacing it. `~/.claude/settings.json` is not bind-mounted; `run.ps1:210-216` mounts `.claude.json`, `.credentials.json`, `projects/` only.
2. `claude/prepare.ps1:588-589` writes the **same `$settings` object** to both `settings.json` and `settings.local.json`. Merge source and merge target are byte-identical.
3. `merge-claude-settings.sh:21` probe-skips when `.extraKnownMarketplaces` is present in the target — and since the two files are identical, if the key is in the bake it is already in the target. When the key is in *neither*, `jq -s '.[0] * .[1]'` over two identical objects is still a no-op. The script is inert on every path.

The original reason was sbx's boot-time clobber (`claude/Dockerfile:178-183`), which no longer happens. The actor is gone **and** so is the reason — so Step 4 retires the claim in past tense rather than re-attributing it. `claude/Dockerfile.slim:190` (`# Restore baked claude settings after runtime baseline overwrite.`) already carries a laundered version of the same dead rationale and is corrected in Step 4 too.

### Key Files

> Quick reference — detailed changes in Implementation.

| File | Role | Change Summary |
|------|------|----------------|
| `claude/Dockerfile` | legacy sbx image | delete |
| `codex/Dockerfile` | legacy sbx image (current default) | delete |
| `claude/Dockerfile.slim` → `claude/Dockerfile` | the real image | + rm-guard block; de-sbx comments; rename |
| `codex/Dockerfile.slim` → `codex/Dockerfile` | the real image | + rm-guard + playwright; de-sbx comments; rename |
| `claude/build.ps1` | build driver | `-Dockerfile` default `Dockerfile.slim` → `Dockerfile`; cachebust comment |
| `claude/README.md`, `codex/README.md` | suite docs | drop legacy-sbx build/run sections; rewrite intro, Layout, Notes |
| `claude/prepare.ps1`, `codex/prepare.ps1` | staging | exclusion-rationale comments |
| `claude/run.ps1`, `codex/run.ps1`, `cursor/run.ps1`, `opencode/run.ps1` | launchers | line-1 header |
| `claude/context/scripts/merge-claude-settings.sh` | settings merge | header comment — retire, don't re-attribute |
| `cursor/Dockerfile`, `opencode/Dockerfile`, `cursor/README.md`, `opencode/README.md` | docs | drop "no sbx integration" paragraphs |
| `omp/prepare.ps1` | staging | replace inherited `sbx manages those` rationale |
| `.gitignore` | obsolete artifact trace | delete `omp/sbx-omp` rule; no tracked producer references it |

20 tracked paths total.

### Dependencies

- **Requires:** P2 only (see Preconditions). The former dirty-tree P1 was cleared by `4ae972a`.
- **Blocks:** `2607271806-sbx-base-image-suite-plan.md` and `2607271807-pi-cursor-base-migration-plan.md` (both `Ready`, unexecuted) **until each is revised against current state.** Rename-only is insufficient:
  - `2607271806` creates `base/Dockerfile`, `base/build.ps1`, `base/README.md` around an image literally named **`sbx-base`** (`:14`, `:31` success criterion, `:116` Dockerfile header, `:264` `[string]$Image = 'sbx-base:v1'`, `:267`, `:279`, `:294-297`, `:328`) — ~9 tracked-file occurrences on execution. It also assumes opencode/cursor/pi share one Debian-derived stack; `pi/` is gone and OMP defaults to `oh-my-pi/pi:dev`, so its consumer count and extraction source must be re-derived.
  - `2607271807` rebases **deleted `pi/` paths** plus `cursor/Dockerfile`, edits both old `build.ps1`s, and deletes both old `rm-guard/` dirs. Its cursor half overlaps Step 6; its pi half is non-executable. Human must choose cursor-only revision, a replacement current OMP/cursor design, or abandonment.
  - The surviving cursor rm-guard deletion is not a conflict with this plan's claude/codex guard ports if `2607271806` still provides the control from `base/`; that premise must be preserved or replaced during the sibling revisions.
  - `2607271808-opencode-base-migration-plan.md` **does not exist** — not in `.projex/`, not in `.projex/closed/`. Both sibling plans reference it; do not target a nonexistent document.

  Resolution: human selects a non-sbx base name and `2607271807` disposition; then run separate `revise-projex` workflows on the affected sibling plan(s) before any of these plans execute. This plan records the dependency but does not decide their new core scope.

### Constraints

- **Parity before deletion.** Legacy files may only be deleted after their unique capabilities exist in the surviving file. Verified unique: rm-guard (claude + codex), playwright (codex).
- **`codex/build.ps1` default flips silently.** Its default is the string `'Dockerfile'`; after the rename that name resolves to the slim content. No script edit needed — but codex users get a different base image with no flag change. Must be stated in `codex/README.md`.
- **Comment rewrites — three branches, not one.** Decide per site:
  1. *Actor changed, reason survives* → re-attribute. `# sbx bind-mounts /workspace with the host's ownership…` → `# run.ps1 bind-mounts /workspace with the host's ownership…`. Deleting the rationale is a regression.
  2. *Actor and reason both gone* → **retire the claim in past tense**; do not re-attribute. Re-attributing manufactures a fluently-wrong comment that no longer announces its own staleness — strictly worse than the honest "sbx-managed" it replaced. Applies to `merge-claude-settings.sh:3-4`, `claude/prepare.ps1:583-587`, `claude/Dockerfile.slim:190`.
  3. *Claim was only a contrast against sbx* → delete outright (Step 6).
- `.projex/**` is never edited by this plan.

### Assumptions

Verified at authoring:

- All five `*/rm-guard/rm-guard.sh` are byte-identical — md5 `910b41a66b313be9405b5cf91e9de3c5` (matches the hash recorded in `2607271806-sbx-base-image-suite-plan.md`). Step 1 copies no script, only wiring.
- Baseline re-derived at `HEAD` `4ae972ae9a06`: `git grep -n -i sbx HEAD -- . ':!*.projex/*'` → 49 hits / 20 files. Roster includes `.gitignore` and `omp/prepare.ps1`; `pi/` is absent. Same totals as the former dirty tree, different composition.

Verify early during execution:

- Re-run the exact `HEAD` roster, not only the totals. Expected non-suite additions: `.gitignore:26` and `omp/prepare.ps1:5`; any composition drift requires Step 6 reconciliation before editing.
- Neither `claude/.dockerignore` nor `codex/.dockerignore` excludes `rm-guard/` (read both — neither did at authoring).
- The rm-guard `RUN` block placed immediately before `USER agent` does not break later layers: in `codex/Dockerfile.slim` a `RUN` follows `USER agent` — the legacy `codex/Dockerfile` has the identical ordering and builds today.
- No file outside `.projex/` references `Dockerfile.slim` after Step 3 → grep gate in Step 7.

### Impact Analysis

- **Direct:** the 20 tracked paths in Key Files.
- **Adjacent:** anyone invoking `build.ps1 -Dockerfile Dockerfile.slim` (documented only in `codex/README.md:28`, itself rewritten here) or `-Dockerfile Dockerfile` expecting the sbx build (`claude/README.md:30`, deleted here). `run.ps1`/`prepare.ps1` behavior unchanged. **Partially preserved, not fully:** user, paths, `/etc/sandbox-persistent.sh`, and tool locations are preserved in both suites; **entrypoint and base-extra set change for codex** (see Downstream).
- **Downstream:** claude image gains rm-guard (behavior change, intended); its entrypoint is unchanged because `Dockerfile.slim` was already claude's default. codex image gains rm-guard and playwright, gains `ENTRYPOINT ["tini","--"]` (`codex/Dockerfile.slim:93`; the retired `codex/Dockerfile` declares none and inherits the base's), and loses the sandbox-templates base extras (Docker CLI, Java, man-db, clipboard bridge) that `Dockerfile.slim`'s header already documents as deliberately omitted. `codex/run.ps1:88` passes `$Image, 'sh', '-lc', $bootstrap`, which survives a tini entrypoint — the default path is fine; `--entrypoint` overrides are not.

---

## Implementation

### Overview

Parity first (Steps 1–2), then retire + rename (Step 3), then prose per suite (Steps 4–6), then gate (Step 7). Steps 4–6 are independent of each other.

---

### Step 1: Port rm-guard into both slim images

**Objective:** the surviving images keep `/workspace/.git` delete protection.
**Confidence:** High — verbatim block move; already builds in five Dockerfiles.
**Depends on:** None
**Verify-Projex: Encouraged**

**Files:** `claude/Dockerfile.slim`, `codex/Dockerfile.slim`

**Changes:** copy the block verbatim from the same suite's legacy `Dockerfile` (claude `:136-160`, codex `:75-99`) — comment block plus the `COPY` + `RUN` below.

**Insertion point — last *cacheable* root layer, not last root layer:**
- `claude/Dockerfile.slim`: after the playwright layer (ends `:132`), **before** the `ARG CLAUDE_CODE_CACHEBUST` comment block (starts `:134`). Not after it: that layer is busted on every build by design, and anything below it would rebuild too. The guard is inert for the claude-code npm install that follows (nothing there touches `/workspace`).
- `codex/Dockerfile.slim`: after the `git config --system` layer (ends `:75`), before `USER agent` (`:77`) — same relative position as the legacy file.

```dockerfile
COPY rm-guard/rm-guard.sh /usr/local/libexec/rm-guard.sh
RUN set -eux; \
    chmod 0755 /usr/local/libexec/rm-guard.sh; \
    real_rm="$(readlink -f "$(command -v rm)")"; \
    cp "$real_rm" /usr/bin/rm.real; \
    ln -sf /usr/local/libexec/rm-guard.sh "$real_rm"; \
    rm --version >/dev/null; \
    # Self-test: /workspace doesn't exist yet at build time (it's a runtime
    # bind mount), so fake one up here to actually exercise the guard rather
    # than have "path not found" masquerade as "blocked".
    mkdir -p /workspace/.git && echo test > /workspace/.git/HEAD; \
    if rm -rf /workspace/.git 2>/dev/null; then echo "ERROR: rm-guard did not block direct delete of /workspace/.git"; exit 1; fi; \
    [ -f /workspace/.git/HEAD ] || { echo "ERROR: /workspace/.git/HEAD missing after a supposedly-blocked delete"; exit 1; }; \
    if rm -rf /workspace 2>/dev/null; then echo "ERROR: rm-guard did not block ancestor delete of /workspace"; exit 1; fi; \
    [ -f /workspace/.git/HEAD ] || { echo "ERROR: /workspace/.git/HEAD missing after a supposedly-blocked ancestor delete"; exit 1; }; \
    touch /tmp/rm-guard-selftest && rm -f /tmp/rm-guard-selftest; \
    [ ! -e /tmp/rm-guard-selftest ] || { echo "ERROR: rm-guard blocked an unprotected delete"; exit 1; }; \
    /usr/bin/rm.real -rf /workspace
```

Copy the legacy file's explanatory comment above the `COPY` too (why a shim, not a `.bashrc` alias) — but drop the sbx wording if any survives.

**Rationale:** the guard is a safety control that the default claude build silently lacks. Porting it is a precondition for deleting its only current home, not scope creep.

**Framing — say this wherever the guard is claimed** (Step 1, both README bullets, Success Criteria): it is an **accident guard, not a security boundary**. `rm-guard.sh:15-20` says so itself, and both slim images grant the agent unrestricted passwordless root (`claude/Dockerfile.slim:53-54`, `codex/Dockerfile.slim:40-41`: `usermod -aG sudo agent` + `agent ALL=(ALL) NOPASSWD:ALL`), with `claude/run.ps1:228` launching under `--dangerously-skip-permissions` or `--permission-mode auto`. `sudo ln -sf /usr/bin/rm.real /usr/bin/rm` voids it in one command with no prompt. Pre-existing, not introduced here — but a `GUARD-OK` line must not be read as a deletion guarantee or as a reason to skip host-side backups.

**Verification:** the block's own build-time self-test — the layer fails the build if the guard mis-fires in either direction. Confirmed by Step 7 builds.

**If this fails:** revert the two files (`git checkout -- claude/Dockerfile.slim codex/Dockerfile.slim`); nothing else depends on Step 1 until Step 3.

---

### Step 2: Port playwright into `codex/Dockerfile.slim`

**Objective:** codex keeps its baked Chromium after the legacy file goes.
**Confidence:** High
**Depends on:** None
**Verify-Projex: Encouraged**

**Files:** `codex/Dockerfile.slim`

**Changes:**

1. After `ARG AGENT_BROWSER_VERSION=0.31.1` (`:19`), add — comment taken from `codex/Dockerfile:21-23`:

```dockerfile
# Playwright: baked so JS/TS/Node projects that use it for browser testing don't
# hit a cold `playwright install` mid-task. Pinned for the same reason as above.
ARG PLAYWRIGHT_VERSION=1.61.1
```

2. In the npm layer (`:60-67`):

```dockerfile
// Before:
    npm install -g @openai/codex "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" "agent-browser@${AGENT_BROWSER_VERSION}"; \
    ...
    chown -h agent:agent /home/agent/.local/bin/codex /home/agent/.local/bin/codegraph /home/agent/.local/bin/agent-browser; \
    node --version; npm --version; codex --version; codegraph --version; agent-browser --version

// After:
    npm install -g @openai/codex "@colbymchenry/codegraph@${CODEGRAPH_VERSION}" "agent-browser@${AGENT_BROWSER_VERSION}" "playwright@${PLAYWRIGHT_VERSION}"; \
    ...
    ln -sf /usr/local/share/npm-global/bin/playwright /home/agent/.local/bin/playwright; \
    chown -h agent:agent /home/agent/.local/bin/codex /home/agent/.local/bin/codegraph /home/agent/.local/bin/agent-browser /home/agent/.local/bin/playwright; \
    node --version; npm --version; codex --version; codegraph --version; agent-browser --version; playwright --version
```

3. After the `agent-browser install` layer (`:69-70`), add — from `codex/Dockerfile:58-64`:

```dockerfile
# Playwright's own Chromium build + Linux system libs (--with-deps, needs
# root/apt), baked at build time rather than left for a project's first
# `playwright install` to do cold. HOME override lands it in the agent's cache
# instead of /root, avoiding a second download after USER agent below.
RUN HOME=/home/agent playwright install --with-deps chromium \
 && chown -R agent:agent /home/agent/.cache/ms-playwright
```

Order: this layer must sit **before** the Step 1 rm-guard block (which must remain the last root layer before `USER agent`).

**Rationale:** matches `claude/Dockerfile.slim`'s existing shape exactly; without it, retiring the legacy codex image is a silent capability loss.

**Cost — not free.** `codex/Dockerfile.slim:69` already runs `agent-browser install --with-deps` (Chrome for Testing). This adds a **second** full browser download plus apt system libs to the codex cold build — order of ~1 GB image growth and several minutes, unmeasured here (no container engine in the authoring environment; the operator should record the real delta at Step 7). Caches after the first build. This restores what the retired image already shipped rather than adding new weight to the suite, but the cost lands on codex's own build for the first time. Cross-ref `2607271757-prepare-build-run-optimization-eval.md` and `2607271806-sbx-base-image-suite-plan.md` — both exist because browser layers dominate build cost.

**Verification:** Step 7 — `playwright --version` and non-empty `~/.cache/ms-playwright` in the built codex image.

**If this fails:** `git checkout -- codex/Dockerfile.slim`.

---

### Step 3: Retire the legacy sbx Dockerfiles

**Objective:** one `Dockerfile` per suite, none of them sbx-derived.
**Confidence:** High
**Depends on:** Steps 1–2 (parity must land first)
**Verify-Projex: Encouraged**

**Files:** `claude/Dockerfile`, `codex/Dockerfile` (delete); `claude/Dockerfile.slim`, `codex/Dockerfile.slim` (rename); `claude/build.ps1`

**Changes:**

1. `{projex-scripts}/del-n-stage.{sh|ps1} <repo-root> claude/Dockerfile codex/Dockerfile`
2. `{projex-scripts}/move-n-stage.{sh|ps1} <repo-root> claude/Dockerfile.slim claude/Dockerfile codex/Dockerfile.slim codex/Dockerfile`
3. `claude/build.ps1:28` — `[string]$Dockerfile = 'Dockerfile.slim',` → `[string]$Dockerfile = 'Dockerfile',`
4. `claude/build.ps1:107-111` comment:

```powershell
# Before:
# re-resolve on every build. Only Dockerfile.slim declares the ARG — the sbx
# Dockerfile inherits Claude Code from its base image, so skip it there rather
# than emit an unconsumed-build-arg warning.

# After:
# re-resolve on every build. The probe below keeps this a no-op for any
# Dockerfile that does not declare the ARG, rather than emitting an
# unconsumed-build-arg warning.
```

Leave the `$declaresCachebust` probe itself — it stays correct and cheap.
`codex/build.ps1` needs **no** edit: its default is already the literal `'Dockerfile'`.

**Rationale:** two operations (delete, rename), not one, because the target name is occupied. Deletion + rename is preferred over keeping `.slim`: the `.slim` suffix only ever meant "slim *relative to the sandbox-templates base*" — with the base gone the qualifier is itself an obsolete reference.

**Verification:** `ls claude codex` shows one `Dockerfile`, no `Dockerfile.slim`; `git status` shows two deletions + two renames; `head -3 claude/Dockerfile` shows the slim header.

**If this fails:** the two scripts roll back their own batch. Post-hoc: `git checkout -- claude codex`.

---

### Step 4: De-sbx the claude suite

**Objective:** no stale sbx claim in `claude/`.
**Confidence:** High
**Depends on:** Step 3 (README describes the post-rename layout)
**Do-Projex: Encouraged**

**Files:** `claude/Dockerfile` (the renamed file), `claude/build.ps1` (done in Step 3), `claude/prepare.ps1`, `claude/run.ps1`, `claude/README.md`, `claude/context/scripts/merge-claude-settings.sh`

**Changes:**

| Site | Before → After |
|------|----------------|
| `claude/Dockerfile:2` | `Starts from Node 25 slim instead of docker/sandbox-templates:claude-code` → `Base: node:25-bookworm-slim` |
| `claude/Dockerfile:22` | `Deliberately omits sbx base extras like Docker CLI, Java, man-db, Ubuntu dev bundles, and clipboard bridge.` → `Deliberately omits the heavyweight extras of general-purpose agent base images (Docker CLI, Java, man-db, Ubuntu dev bundles, clipboard bridge).` |
| `claude/Dockerfile:73` | `# sbx bind-mounts /workspace…` → `# run.ps1 bind-mounts /workspace…` (rest of the paragraph unchanged) |
| `claude/prepare.ps1:5` | `cache, statsig, telemetry — sbx manages those.` → `cache, statsig, telemetry — host-only runtime state, never baked.` |
| `claude/prepare.ps1:583-587` | Retire the sbx narrative in **past tense** — do not re-attribute (Constraint branch 2). New text: settings.json lands at user level and settings.local.json is stashed at `/home/agent/.claude-bake/`; the stash existed because the sbx launcher clobbered `~/.claude/settings.json` at sandbox boot. Nothing overwrites it under `run.ps1`, so both copies are written identically here and the merge is a no-op — retained pending a follow-up that retires the merge path. |
| `claude/run.ps1:1` | `# Run the baked cc-custom image without sbx.` → `# Run the baked cc-custom image.` |
| `claude/Dockerfile.slim:190` (the renamed file) | `# Restore baked claude settings after runtime baseline overwrite.` → `# No-op under run.ps1: kept for launchers that overwrite ~/.claude/settings.json at boot (sbx did). See merge-claude-settings.sh.` — the existing text asserts an overwrite that does not happen. |
| `merge-claude-settings.sh:3-4` | `Merges … on top of the sbx-managed ~/.claude/settings.json.` → **past tense, no live-mechanism claim**: `Historically restored the baked settings after the sbx launcher overwrote ~/.claude/settings.json at sandbox boot. Nothing overwrites it under run.ps1 — prepare.ps1 writes both copies from the same object, so this merge is a no-op. Retained as a safety net for launchers that do overwrite; slated for removal.` Do **not** substitute "which run.ps1 rewrites at container launch" — `run.ps1:225` is a single-key jq edit of the baked file, not a baseline replacement, and asserting it would launder a dead rationale into one that reads true. |

`claude/README.md` — rewrite:

- `:3` `Extends docker/sandbox-templates:claude-code with:` → `Node 25 slim image with:` (keep the bullet list; add **rm-guard** as a bullet, new in Step 1 — worded per Step 1 § Framing: *accident guard against deleting `/workspace/.git`, not a security boundary; the agent has `NOPASSWD` sudo and can remove the shim deliberately*)
- `:9` `sbx manages OAuth + ~/.claude.json …` → OAuth comes from the host credentials file bind-mounted by `run.ps1`; `~/.claude.json` is a per-run throwaway (already described at `:77-86` — cross-reference rather than restate)
- `:15` drop `this template's default workflow is non-sbx + Docker`
- `:19-31` Build section: single `Dockerfile`, no variant table, delete the `-Dockerfile Dockerfile` example block
- `:35`, `:48-51` freshness section: drop the "sbx `Dockerfile` inherits Claude Code" paragraph entirely; `Dockerfile.slim` → `Dockerfile`
- `:69` `Without sbx (Win10) — from any project directory:` → `From any project directory:`
- `:127-131` delete the whole "Legacy sbx path" section incl. code fence
- `:171-173` Layout: root `custom_sbx/` → `<repo>/claude/`; one `Dockerfile` line; add `rm-guard/rm-guard.sh`
- `:203-205` Notes: replace the floating-base-tag note with the `node:25-bookworm-slim` equivalent

**Rationale:** claude is where the sbx story is thickest; every remaining claim there is false today.

**Verification:** `git grep -i -e sbx -e sandbox-templates -- claude ':!claude/.projex/*'` → zero hits. Read the rewritten Build + Run sections top-to-bottom: a first-time reader can build and run with no `-Dockerfile` flag.

**If this fails:** `git checkout -- claude/` (Steps 1 and 3 land in earlier commits; re-apply only this step).

---

### Step 5: De-sbx the codex suite

**Objective:** no stale sbx claim in `codex/`; the default-image flip is documented.
**Confidence:** High
**Depends on:** Step 3
**Do-Projex: Encouraged**

**Files:** `codex/Dockerfile` (renamed), `codex/prepare.ps1`, `codex/run.ps1`, `codex/README.md`

**Changes:**

| Site | Before → After |
|------|----------------|
| `codex/Dockerfile:2` | `Starts from Node 24 slim instead of docker/sandbox-templates:codex` → `Base: node:24-bookworm-slim` |
| `codex/Dockerfile:21-22` | `Deliberately omits sbx base extras like…` → same rewording as claude |
| `codex/Dockerfile:32` | `so the wrapper's /home/agent mounts and baked config paths match the sbx-derived image.` → `…match the paths run.ps1 and the baked config expect.` |
| `codex/prepare.ps1:6` | `sbx manages auth, the rest is host-only runtime state` → `auth is obtained by device login inside the container; the rest is host-only runtime state` |
| `codex/run.ps1:1` | `# Run the baked codex-custom image without sbx.` → `# Run the baked codex-custom image.` |

`codex/README.md` — rewrite:

- `:3` `Extends docker/sandbox-templates:codex with:` → `Node 24 slim image with:` (bullets keep Node 24; **add** codegraph, agent-browser, playwright, rm-guard — all present, none previously listed; rm-guard worded per Step 1 § Framing)
- `:8` `sbx manages OAuth + auth.json at runtime` → device auth runs inside the container on each run; nothing credential-related is baked or mounted (matches `run.ps1:1-8`)
- `:25-29` delete the "To try the no-sbx slim image" block; **replace with a migration note** enumerating every delta, not just the base swap:
  - the slim image is now the only image; `-Dockerfile Dockerfile` (the default) no longer resolves to the `docker/sandbox-templates:codex` build, which is removed
  - **gone:** Docker CLI, Java, man-db, clipboard bridge (base extras, by design)
  - **new:** `ENTRYPOINT ["tini", "--"]` — the retired file declared none and inherited the base's. `run.ps1` is unaffected (`codex/run.ps1:88` passes `sh -lc <bootstrap>`), but `docker run --entrypoint …` overrides now compose with tini
  - **new:** rm-guard, playwright + baked Chromium (Steps 1–2); first cold rebuild is materially slower and the image materially larger — see Step 2 § Cost
- `:40` `Without sbx (Win10) —` → `From any project directory:`
- `:60-64` delete the "Legacy sbx path" section incl. code fence
- `:99` Layout root `custom_sbx/codex/` → `<repo>/codex/`; add `rm-guard/rm-guard.sh`
- `:143` `auth.json — credentials; sbx manages auth at runtime` → `auth.json — credentials; device login happens inside the container`
- `:160-162` Notes: replace floating-base-tag note with the `node:24-bookworm-slim` equivalent

**Rationale:** codex is the only suite whose *default build output* changes; the README must say so plainly, not just drop the old text.

**Verification:** `git grep -i -e sbx -e sandbox-templates -- codex ':!codex/.projex/*'` → zero hits. The migration note names the removed base extras explicitly.

**If this fails:** `git checkout -- codex/`.

---

### Step 6: De-sbx cursor / opencode + OMP traces

**Objective:** delete obsolete contrast prose and the two sbx traces introduced by the OMP migration.
**Confidence:** High
**Depends on:** None
**Do-Projex: Encouraged**

**Files:** `.gitignore`, `cursor/Dockerfile`, `cursor/README.md`, `cursor/run.ps1`, `opencode/Dockerfile`, `opencode/README.md`, `opencode/run.ps1`, `omp/prepare.ps1`

**Changes:**

| Site | Before → After |
|------|----------------|
| `cursor/Dockerfile:2-4` | `Base: debian:bookworm-slim (glibc) — same rationale as opencode/: no docker/sandbox-templates:cursor base exists, so this is the plain-docker path, not an sbx extension (unlike claude/codex).` → `Base: debian:bookworm-slim (glibc) — same rationale as opencode/.` |
| `cursor/README.md:25-28` | Delete the `No docker/sandbox-templates:cursor base exists …` sentence; keep `No credentials are baked into the image; see "Auth" below…` |
| `cursor/run.ps1:1` | drop ` without sbx` |
| `opencode/Dockerfile:13-14` | Delete `No docker/sandbox-templates:opencode base exists (unlike claude/codex), so there's no sbx integration here — this is the plain-docker path, run via run.ps1.`; keep the following sentence about host auth bind-mounting |
| `opencode/README.md:24-26` | same deletion; keep the host-auth/state sentence |
| `opencode/run.ps1:1` | drop ` without sbx` |
| `.gitignore:26` | Delete `omp/sbx-omp`. Commit `4ae972a` carried the old local-artifact name into the OMP layout, but no tracked producer references it; preserving the ignore rule itself defeats the zero-hit gate. |
| `omp/prepare.ps1:5` | `cache, statsig, telemetry — sbx manages those.` → `cache, statsig, telemetry — host-only runtime state, never baked.` |

**Rationale:** cursor/opencode paragraphs exist only to contrast against claude/codex's sbx integration. The OMP migration copied two sbx-era traces into current tracked files; neither describes a live mechanism.

**Verification:** `git grep -i -e sbx -e sandbox-templates -- .gitignore cursor opencode omp ':!*/.projex/*'` → zero hits.

**If this fails:** `git checkout -- .gitignore cursor/Dockerfile cursor/README.md cursor/run.ps1 opencode/Dockerfile opencode/README.md opencode/run.ps1 omp/prepare.ps1` inside the execution worktree; no user work exists there.

---

### Step 7: Gate — grep + host builds

**Objective:** prove both criteria families (zero references, no capability lost).
**Confidence:** Medium — build/smoke cannot run in the agent environment (no docker/podman/pwsh); human-executed on the Windows host.
**Depends on:** Steps 1–6

**Changes:** none (verification only).

Agent-executable:

```bash
git -C <repo-root> grep -n -i sbx -- . ':!*.projex/*'                 # expect: no output
git -C <repo-root> grep -n sandbox-templates -- . ':!*.projex/*'       # expect: no output
git -C <repo-root> grep -n 'Dockerfile\.slim' -- . ':!*.projex/*'      # expect: no output
ls <repo-root>/claude <repo-root>/codex | grep -i dockerfile           # expect: one 'Dockerfile' each
```

Human-executed (Windows host, PowerShell 5.1) — record results in the execution log as human-reported. Nothing in this block can run in the agent environment (no docker/podman/pwsh); every line below was instead **statically checked against the script it calls**, which is what the pre-revision version of this block was not.

```powershell
# Build. No -LoadToDocker: build.ps1:76 (claude) / :75 (codex) throw
# "-LoadToDocker/-LoadToPodman requires -Tar <path>", and the flag is a no-op
# with -Engine docker anyway (it exists for the podman-build -> docker-load path).
# No separate prepare.ps1 call: build.ps1:90 / :89 invoke it unless -SkipPrepare.
./claude/build.ps1 -Image cc-custom:desbx    -Engine docker
./codex/build.ps1  -Image codex-custom:desbx -Engine docker

# Tool matrix.
docker run --rm cc-custom:desbx    bash -lc 'claude --version; pnpm --version; codegraph --version; agent-browser --version; playwright --version; ls ~/.cache/ms-playwright; whoami'
docker run --rm codex-custom:desbx bash -lc 'codex --version; codegraph --version; agent-browser --version; playwright --version; ls ~/.cache/ms-playwright; whoami'

# rm-guard, both images. /workspace MUST be bind-mounted: the guard layer ends
# `/usr/bin/rm.real -rf /workspace`, so the path does not exist in the image, and
# both images end as USER agent (claude/Dockerfile.slim:194, codex:77) who cannot
# mkdir at / . Without -v, `mkdir -p /workspace/.git` fails with Permission denied,
# GUARD-OK never prints, PASSTHRU-OK does — reading as "guard broken" on a
# perfectly correct image. -v also matches how run.ps1:210 actually launches.
$probe = New-Item -ItemType Directory -Force -Path "$env:TEMP\rmguard-probe"
docker run --rm -v "${probe}:/workspace" cc-custom:desbx    bash -lc 'mkdir -p /workspace/.git && echo x > /workspace/.git/HEAD; rm -rf /workspace/.git; test -f /workspace/.git/HEAD && echo GUARD-OK; touch /tmp/p && rm -f /tmp/p && test ! -e /tmp/p && echo PASSTHRU-OK'
docker run --rm -v "${probe}:/workspace" codex-custom:desbx bash -lc 'mkdir -p /workspace/.git && echo x > /workspace/.git/HEAD; rm -rf /workspace/.git; test -f /workspace/.git/HEAD && echo GUARD-OK; touch /tmp/p && rm -f /tmp/p && test ! -e /tmp/p && echo PASSTHRU-OK'
Remove-Item -Recurse -Force $probe
```

Fallback if the bind mount is not writable by uid 1000 on this host: prepend `--user root` to the two guard lines instead of `-v`. Root can `mkdir /workspace`, so the guard still gets a real target — but it no longer reproduces the real runtime user, so prefer `-v`.

Both builds also exercise the rm-guard self-test layer, so a build that exits 0 already proves the guard fires and passes through correctly; the runtime checks exist only to confirm it survives into the launched container.

Also record the codex image size and cold-build time (Step 2 § Cost — the ~1 GB / N-minute figure is an unmeasured estimate).

**Verification:** every grep empty; both builds exit 0; every version prints; `GUARD-OK` + `PASSTHRU-OK` from both images.

**If this fails:** a failing version/guard check names the step that dropped it (Step 1 → rm-guard, Step 2 → playwright, Step 3 → wrong file promoted). Fix forward in that step's file; the deletions in Step 3 are recoverable from git history for reference.

**Before concluding rm-guard is broken:** confirm the `-v` mount is present and writable. A missing/read-only mount produces exactly the same output as a genuinely broken guard (`PASSTHRU-OK` without `GUARD-OK`). Never "fix" this by weakening or removing the guard.

---

## Verification Plan

### Automated Checks
- [ ] `git grep -i sbx -- . ':!*.projex/*'` → empty
- [ ] `git grep sandbox-templates -- . ':!*.projex/*'` → empty
- [ ] `git grep 'Dockerfile\.slim' -- . ':!*.projex/*'` → empty
- [ ] `git status` touches only the 20 tracked paths in Key Files, plus the plan doc

### Manual Verification
- [ ] Both images build with no `-Dockerfile` flag and no `-LoadToDocker` (human, Windows host)
- [ ] Tool matrix passes in both images
- [ ] rm-guard runtime check passes in both images **with `/workspace` bind-mounted** — a bare `docker run` false-fails
- [ ] `claude/README.md` and `codex/README.md` read end-to-end with no dangling reference to a removed section
- [ ] `codex/README.md` states the default-image change explicitly, including the `ENTRYPOINT` delta

### Acceptance Criteria Validation
| Criterion | How to Verify | Expected |
|-----------|---------------|----------|
| Zero sbx references outside `.projex/` (exit check, branch-scoped) | the three greps, on the execution branch | empty output |
| One Dockerfile per suite | `ls claude codex` | `Dockerfile` only |
| Default build works flagless | `build.ps1 -Image x -Engine docker` | exit 0 |
| rm-guard present in both | build self-test + runtime check **with `-v <tmp>:/workspace`** | `GUARD-OK` / `PASSTHRU-OK` |
| playwright present in both | `playwright --version` + `ls ~/.cache/ms-playwright` | version + non-empty |
| Persistent-env hook intact | claude image: settings merge + codegraph setup run | both fire on shell start |

---

## Rollback Plan

Worktree branch — abandon with `{projex-scripts}/projex-abandon.{sh|ps1} <repo-root> main projex/2608021410-retire-sbx-legacy --worktree`. `main` is never touched during **execution**.

Commit `4ae972a` cleared the former tracked-tree blocker. The close script's repo-wide dirty-base gate still applies: if new tracked edits appear on `main` before close, the ephemeral branch survives intact and the owner must commit or stash those edits before retrying. **Do not** use `git reset --hard`, `git checkout --`, or `git stash drop` on unrelated work.

Post-merge: `git revert` the squash commit — restores both legacy Dockerfiles, the `.slim` names, and every comment in one operation.

---

## Revision Log

- **2026-08-02:** Revised against `2608021423-retire-sbx-legacy-redteam.md` (verdict `Fix Issues` / `Needs Work`). All 12 findings re-verified against the repo before applying; all accepted, three with corrected remediations. Changes:
  - **F1** — baseline re-derived from `HEAD` (50 hits / 21 files) instead of the dirty working tree (49/20); `Worktree: Yes` means the worktree materialises `HEAD`. `pi/Dockerfile:2-4` and `pi/run.ps1:1` added to Step 6 and Key Files; `pi/prepare.ps1:5` made conditional (no sbx line at `HEAD`; present only in the user's uncommitted work). Step 6's `git checkout -- pi/` warning retracted — it was written as if executing on `main`. *Correction to the finding: the resulting count is 21 files + 1 conditional, not a flat 22 — which of the two shapes applies depends on how P1 resolves.*
  - **F2** — Step 7 build lines dropped `-LoadToDocker`; verified `claude/build.ps1:76` / `codex/build.ps1:75` throw without `-Tar`, and the flag is a no-op under `-Engine docker`. Separate `prepare.ps1` calls dropped (`build.ps1:90`/`:89` invoke it unless `-SkipPrepare`).
  - **F3** — Step 7's rm-guard smoke test now bind-mounts `/workspace`; verified the guard layer ends `/usr/bin/rm.real -rf /workspace` and both images end `USER agent` (`claude/Dockerfile.slim:194`, `codex/Dockerfile.slim:77`), so the old bare `docker run` could not `mkdir /workspace` and false-failed on a correct image. `--user root` documented as fallback; an explicit "do not weaken the guard" note added to Step 7's failure path.
  - **F4** — `ENTRYPOINT ["tini","--"]` added to Step 5's migration-note delta list (`codex/Dockerfile.slim:93`; the retired `codex/Dockerfile` declares none). "Image contract preserved" softened in Impact Analysis to name what is and is not preserved.
  - **F5** — the "`merge-claude-settings.sh` is not obsolete" correction **withdrawn**; the eval's bonus finding was right. All three of the redteam's facts verified, plus a fourth: with `.extraKnownMarketplaces` absent from both files the merge still no-ops, since `prepare.ps1:588-589` writes the same object to both. Step 4's header rewrite changed to past tense; `claude/Dockerfile.slim:190`'s already-laundered comment added as an edit site; Constraints gained a third branch (*actor gone and reason gone → retire, don't re-attribute*); retiring the merge path listed as Out of Scope follow-up.
  - **F6** — dirty-`pi/` handling promoted from a close-time decision to blocking **Precondition P1**. *Correction to the finding: verified `projex-squash-close.sh:191-198` gates on **any** tracked change in the base checkout, not just merged paths — so the fallback "drop `pi/` from scope and close anyway" does not work either. The precondition is mandatory.* Rollback Plan now documents the refusal and the recovery reflexes to avoid.
  - **F7** — `Requires nothing / Blocks nothing` replaced with an explicit `Blocks: 2607271806, 2607271807` and per-plan evidence; `2607271808` confirmed non-existent and the recommendation to revise it dropped. Rename sequenced **before** this plan executes. Added: the sibling rm-guard deletions are not a conflict, since `2607271806` provides the control from `base/`.
  - **F8** — "17" corrected; counts reconciled to 21 (+1 conditional) in Summary, Key Files, Impact Analysis, and Verification Plan.
  - **F9** — accident-guard-not-security-boundary framing added to Step 1 and propagated to both README bullets and Risks; verified `rm-guard.sh:15-20`, `claude/Dockerfile.slim:53-54`, `codex/Dockerfile.slim:40-41`, `claude/run.ps1:228`.
  - **F10** — Criterion 1 restated as a branch-scoped **exit check**, not a standing invariant; verified no CI (`.github/` absent; root tracked files are `.gitattributes`, `.gitignore`, `NOTICES.md`). `pi/sbx-omp` confirmed unmatched by `.gitignore`.
  - **F11** — Step 2 gained a Cost paragraph (second browser download on top of `codex/Dockerfile.slim:69`'s `agent-browser install --with-deps`). *Correction to the finding: the "~1 GB" figure is an unmeasured estimate — no container engine in the authoring environment — so it is marked as such and Step 7 now asks the operator to record the real delta.*
  - **F12** — dangling `LICENSE` / `SECURITY.md` pointers logged in Out of Scope with their exact sites; `NOTICES.md` confirmed needing no change.
  - **Status:** `Ready` → `Blocked`. P1 (human decision on the dirty `pi/` tree) and P2 (`sbx-base` rename on two `Ready` plans) are external dependencies that must clear before execution; both resolve into `Ready` once cleared. Nothing was executed.

- **2026-08-02:** Revised against `2608021853-retire-sbx-legacy-review.md` (verdict `Revise`) after post-authoring commit `4ae972ae9a06` (`Convert pi suite to OMP`). Trigger re-verified at current `HEAD`: tracked tree clean; baseline 49 hits / 20 files; `pi/` absent; live omitted sites `.gitignore:26` and `omp/prepare.ps1:5`.
  - Scope, Summary, Current State, Key Files, Assumptions, Impact, Step 6, Verification Plan, and Rollback now use the exact OMP-era roster. Former conditional `pi/prepare.ps1` handling is superseded.
  - P1 marked cleared; Status remains `Blocked` only on P2 human judgments.
  - P2 strengthened from string rename to status-quo revision: `2607271806` must re-derive its three-suite premise and non-sbx name; `2607271807` needs cursor-only revision, replacement, or abandonment because its `pi/` half targets deleted files. Sibling documents were not edited: those choices change their own core scope and require separate workflows.

---

## Notes

### Risks

- **Roster drift can hide behind unchanged totals.** `HEAD` now has the former dirty-tree total (49/20), but `.gitignore` + `omp/prepare.ps1` replaced deleted `pi/` sites. Mitigated by Step 7's exact-roster check; count-only reconciliation is insufficient.
- **codex's default image changes without a flag change.** Anyone rebuilding codex gets the slim base: loses Docker CLI / Java / man-db / clipboard bridge, gains a tini `ENTRYPOINT`, rm-guard, playwright + Chromium, and a materially longer first cold build. Mitigated by the explicit README migration note (Step 5) — not by a compatibility shim; keeping one would defeat the plan.
- **Two `Ready` sibling plans are stale and re-seed the term.** `2607271806` still assumes three Debian-derived consumers; `2607271807` targets deleted `pi/` paths. Both require separate lifecycle decisions before execution. `2607271808` was never authored; do not target it.
- **rm-guard is new behavior in the claude default image.** A `rm -rf` inside `/workspace/.git` that previously succeeded now fails. That is the guard's intent, and the shim passes every other invocation through; the build-time self-test proves both directions. It is an accident guard, not a security boundary — see Step 1 § Framing.
- **Prose-only edits can silently drop a real rationale — or manufacture a false one.** Both failure directions are live. Constraint § Comment rewrites now has three branches; the `merge-claude-settings.sh` site is the case where re-attribution would have produced a *fluently wrong* comment, worse than the honest staleness it replaced. Checked by reading each rewritten comment against its original in Step 7's manual pass.
- **The exit check has no enforcement.** No CI, no hook, no test in this repo. Nothing prevents regression after close; detection lag is unbounded. Accepted as a one-time cleanup (see Success Criteria). Revisit if any suite gains CI or when `2607271806` is next picked up.

### Split Decision

**No split — heuristic partly tripped (7 steps) but well under the size budget, single root `.projex/` scope.** Steps 1–3 and 4–5 edit the same files (`claude/Dockerfile`, `codex/Dockerfile`, both READMEs); splitting would duplicate those edits and force one plan to be authored against a state the other has not produced yet.

### Open Questions

- [ ] **P2a — shared-base name:** `agent-base`, `suite-base`, or another non-`sbx` term?
- [ ] **P2b — `2607271807` disposition:** revise to cursor-only, replace with a current OMP/cursor design, or abandon?
