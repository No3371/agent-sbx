# Build-Time Plugin Install for Sandbox Images

> **Status:** Review
> **Created:** 2026-07-10
> **Author:** agent
> **Related Projex:** 2607091752-context-mode-plugin-path-mapping-memo.md

---

## Summary

`claude/prepare.ps1` copies the host's `~/.claude/plugins` tree byte-for-byte into the image build context, then hand-patches host-absolute paths in `installed_plugins.json`, `known_marketplaces.json`, and `settings.json` hook commands via regex (`Convert-WinPathToLinux`, `Rewrite-Command` — already 3+ path-shape generations deep). Proposal: replace payload-copy-and-rewrite with a Dockerfile `RUN` step that installs each `enabledPlugins` entry natively inside the container via `claude plugin marketplace add` / `claude plugin install`, so the image resolves its own Linux paths instead of having Windows-host paths transplanted and patched into it.

---

## Problem Statement

### Current State

`claude/prepare.ps1:87-103` recursively copies the host's entire `~/.claude/plugins` directory into `claude/context/.claude/plugins/`, which `claude/Dockerfile:142` then `COPY`s into the image verbatim. Two downstream fixups compensate for the copy being host-shaped:

- `prepare.ps1:123-186` rewrites `installPath`/`installLocation` fields in `installed_plugins.json` and `known_marketplaces.json` via `Convert-WinPathToLinux` (regex on `C:\Users\...\.claude` prefixes).
- `prepare.ps1:236-266` rewrites hook `command` strings in `settings.json` via `Rewrite-Command`/`Rewrite-McpServerCommand` — a growing regex ladder covering Windows `node.exe`, git-bash drive-prefix paths, WSL mount paths, and `cygpath` wrapper syntax, then an allowlist (`allowedPathPrefixes`, `prepare.ps1:271-275`) that drops any hook whose rewritten command doesn't land in a known-safe sandbox path.
- Separately, `claude/Dockerfile:150-154` already runs `npm install` inside the container for every plugin dir with a `package.json`, because native addons (e.g. `context-mode`'s `better-sqlite3`) built on Windows can't load on Linux — i.e. the Dockerfile already treats "payload built on host" as untrustworthy for anything native-code-shaped, just not yet for path-shaped data.

### Gap / Need / Opportunity

`context-mode`'s MCP entrypoint self-heals `settings.json`'s hook paths to whichever host last booted it (by design, for host-side node-path drift). That self-heal output is exactly the shape `prepare.ps1`'s regex allowlist has to keep chasing. Verified in the current image that hooks resolve correctly today, but the mechanism is fragile by construction: any new host-side absolute-path shape (new plugin version, new OS/shell convention, host updated without an image rebuild) is a new regex case that must be anticipated or a hook silently drops or ships broken.

The data actually needed to reconstruct a working plugin set is small and portable: `settings.json`'s `enabledPlugins` (name@marketplace pairs, e.g. `"context-mode@claude-context-mode": true`) and `extraKnownMarketplaces` (source URLs, e.g. GitHub repos — verified in `claude/context/.claude/settings.json:41-74`). Everything else copied under `plugins/` — cache dirs, resolved install paths, host-baked hook commands — is derived state that Claude Code itself already knows how to regenerate given identity + a live install.

### Why Now?

Confirmed live during a prior session (2607091752-context-mode-plugin-path-mapping-memo.md): a host-side `context-mode` update rewrote `settings.json` hook paths to the host's own absolute paths, which is the class of failure this mechanism cannot get ahead of — it can only patch known shapes after the fact.

---

## Proposed Change

### Overview

Stop shipping the plugin *payload* (cache dirs, resolved paths, host-baked commands) and stop rewriting it. Ship only the plugin *identity* (`enabledPlugins` + `extraKnownMarketplaces`, already preserved as-is per `Dockerfile:140-141`), and have the image install its own copies during `docker build` by running the `claude` CLI as the `agent` user inside the container — one `claude plugin marketplace add <source>` per `extraKnownMarketplaces` entry, one `claude plugin install <name>@<marketplace>` per `enabledPlugins` entry. Paths, caches, and hook commands are then whatever Claude Code writes for its own Linux filesystem — nothing to transpile.

### Approach Options

#### Option A: Full build-time install (memo's proposal)

- **Description:** Delete the `context/.claude/plugins/` `COPY` and all path-rewrite logic in `prepare.ps1` (`Convert-WinPathToLinux`, the `installed_plugins.json`/`known_marketplaces.json` patch blocks, `Rewrite-Command`/`Rewrite-McpServerCommand`, `allowedPathPrefixes` hook-filtering). `prepare.ps1` only extracts `enabledPlugins`/`extraKnownMarketplaces` from host `settings.json` (already does — no new extraction code). Add a `Dockerfile` `RUN` block, as `agent`, that loops those entries and calls `claude plugin marketplace add` / `claude plugin install` for each.
- **Pros:** Eliminates the entire rewrite/allowlist surface in one pass — the class of bug in the memo cannot recur, because there's no host-baked path to rewrite. Fewer moving parts long-term (`prepare.ps1` drops ~150 of its 468 lines). Plugin cache/hook commands are always correct for the image's own filesystem, matching how the existing native-module `npm install` step already treats plugin payload as needing a Linux-side rebuild.
- **Cons:** `docker build` now needs network egress and, for private/gated marketplaces, auth material available at build time (today `prepare.ps1` needs neither — the host already resolved and vendored everything once). Build time increases and becomes network-flaky per plugin count. `claude plugin install` behavior/flags for non-interactive, scripted use aren't documented in this repo and would need discovery. Loses host-plugin-version pinning as a side effect: today's image gets exactly what the host has installed at prepare-time; build-time install gets whatever's newest at build-time unless versions are pinned explicitly.
- **Effort:** Medium — new Dockerfile step + `enabledPlugins`/`extraKnownMarketplaces` → shell-loop generation in `prepare.ps1`, minus a larger deletion of now-dead rewrite code. Needs a build-time network/auth story before it can land.

#### Option B: Narrow the existing rewrite surface (no architecture change)

- **Description:** Keep host-copy-and-patch, but shrink what gets copied and patched. Drop cache/derived dirs from the `plugins/` copy (the memo notes `claude-hud`'s caches are already dropped post-copy at `prepare.ps1:158-170` for the same reason — host-state leakage — this generalizes that pattern to more plugins, e.g. `context-mode`'s own local cache/db files if any ship host-absolute state). Fewer bytes copied means fewer path shapes for `Convert-WinPathToLinux`/`Rewrite-Command` to encounter, but the regex ladder itself stays and still needs new cases for genuinely new host shapes.
- **Pros:** No network/auth needed at build time — preserves current build model exactly. Small, incremental, low-risk diff. Can ship immediately without deciding a build-time-auth story.
- **Cons:** Doesn't fix the underlying fragility — a new context-mode self-heal path shape (or any other plugin's host-baked absolute path) still requires a new regex case reactively, after it breaks something. Caches to drop must still be identified per-plugin by hand, same maintenance shape as today, just smaller surface.
- **Effort:** Low — a handful of new entries in `pluginCachesToDrop` (`prepare.ps1:160-163`) plus auditing which plugins write host-absolute state outside `settings.json`/`installed_plugins.json`/`known_marketplaces.json` (context-mode's hook self-heal is the only confirmed case).

#### Option C: Pilot build-time install on context-mode only

- **Description:** Middle ground between A and B. Keep host-copy-and-patch as the default path for most plugins, but carve out `context-mode` specifically (the plugin actually causing failures) for build-time install per Option A's mechanism, leaving its entry out of the `plugins/` copy and its rewrite cases. This is the "prototype on context-mode only" branch the user was asked about but didn't get to answer before the memo's originating session was interrupted.
- **Pros:** Validates the build-time-install mechanism (marketplace add/install syntax, non-interactive behavior, auth requirements) against one real plugin before committing the whole `plugins/` pipeline to it. Limits build-time network/auth exposure to context-mode's marketplace only. Directly resolves the plugin actually observed breaking, without touching plugins that aren't broken.
- **Cons:** Two plugin-provisioning mechanisms live side by side (copy-and-patch for most, build-time-install for one), which is more moving parts than either A or B alone until/unless the rest are migrated too — the regex ladder in `prepare.ps1` doesn't shrink. Migration debt: if the pilot succeeds, Option A's full cutover is still a separate follow-up.
- **Effort:** Low-Medium — same Dockerfile mechanism as Option A but scoped to one `RUN` line / one marketplace+plugin pair, plus one `pluginCachesToDrop`-style exclusion so `prepare.ps1` skips copying `context-mode`'s payload.

### Recommended Approach

Option C, as a bridge to Option A. It answers the open question Option A cannot yet answer on paper — whether `claude plugin marketplace add`/`claude plugin install` work non-interactively inside the container's build, and what auth/network they actually require — against the one plugin with a confirmed failure, before the rewrite-surface deletion (Option A) is applied to marketplaces that haven't been proven to work this way. Option B is available as a fallback if Option C's build-time auth/network requirement turns out to be a hard blocker for this repo's CI/build environment.

---

## Impact Analysis

### Affected Areas

- `claude/prepare.ps1`: plugin-copy loop (`87-103`, scoped by option), `Convert-WinPathToLinux`/JSON-path rewrite blocks (`119-186`), `pluginCachesToDrop` (`158-170`), `Rewrite-Command`/`Rewrite-McpServerCommand`/`allowedPathPrefixes`/`Test-HookFileSelfContained`/`Test-HookCommandAllowed` (`236-320+`) — reduced scope (C) or removed (A).
- `claude/Dockerfile`: `plugins/` `COPY` (`142`) and the native-module `npm install RUN` (`150-154`) — scoped down or removed for whichever plugin(s) move to build-time install; new `RUN` step added for marketplace add/install.
- `claude/Dockerfile.slim`: not yet inspected for its own plugin-handling — must be checked for parity before implementation, since it may duplicate or diverge from `Dockerfile`'s plugin block.
- Build-time network/CI: new outbound dependency on GitHub (and any other marketplace source) at `docker build` time, where none exists today for the plugin payload specifically.

### Dependencies

- Depends on `claude` CLI's non-interactive plugin-install behavior being scriptable as the `agent` user with no TTY (unverified — first thing a pilot must confirm).
- Depends on marketplace auth model: public GitHub-sourced marketplaces (verified shape for `claude-hud`, `openai-codex`, `ponytail` in `extraKnownMarketplaces`) need no auth; `claude-plugins-official`-sourced plugins appear to resolve via a built-in default marketplace already known to Claude Code (no `extraKnownMarketplaces` entry needed for those) — behavior for any future private/gated marketplace is unconfirmed and would need its own auth-at-build-time story.
- codex's and opencode's own `prepare.ps1`/Dockerfile (siblings under `codex/`, `opencode/`) implement the same copy-and-rewrite pattern independently for their own plugin dirs — out of scope here, but a precedent this proposal's outcome could inform later.

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `claude plugin install` isn't fully non-interactive / has no documented CI mode | Low-Med (CLI takes all inputs as flags; no live run confirmed) | High (blocks A and C) | Pilot (Option C) surfaces this before wider rollout |
| Build-time network flake/unavailability breaks reproducible builds | Med | Med | Keep Option B's copy-and-patch as fallback path; don't delete it until pilot proves out |
| Plugin version drift: build-time install gets latest, not what the host had pinned | **Confirmed** — no version/ref flag on `install` or `marketplace add` | Low-Med | No CLI-level pin available; only lever is pinning the marketplace source itself (e.g. a tagged git ref) if the marketplace repo supports it |
| Private/gated marketplace needs credentials at `docker build` time not currently plumbed anywhere in this repo | Low (none observed today) | High if it occurs | Scope pilot to already-public marketplaces; treat private-marketplace auth as a separate follow-up if/when needed |

### Breaking Changes

None to running images — this only changes how the image is built. Local dev builds lose the guarantee that the sandbox's plugin set exactly mirrors whatever's on the host at prepare-time (intentional trade — see Recommended Approach).

---

## Open Questions

- [x] Does `claude plugin marketplace add` / `claude plugin install` support fully non-interactive, scriptable invocation (no prompts, deterministic exit code)? — **Confirmed by CLI surface** (`claude plugin install --help` / `claude plugin marketplace add --help`, checked 2026-07-10): both take all inputs as flags — `install <plugin>` (`plugin@marketplace` form supported), `-s/--scope <user|project|local>` (default `user`), `--config <key=value>` (repeatable, for manifest-declared `userConfig`, same validation path as interactive `/plugin configure`); `marketplace add <source>` takes `--scope` and `--sparse <paths...>` (monorepo subdirectory checkout). No prompts needed if plugin/marketplace/config are fully specified via flags — no live non-interactive run tried yet, but nothing in the surface implies an unavoidable prompt. `--scope` choice matters for the Dockerfile `RUN` step: **decided — `user` scope**, so plugins install into the container's own `~/.claude` (matching where `prepare.ps1`'s copy-and-patch already puts them today). `project`/`local` scope was considered and rejected — those write into whatever directory the build treats as "project," which risks landing under a path the container later bind-mounts back to the host (workdir/repo mount), leaking install state onto the host filesystem. `user` scope keeps it entirely inside the container's own home dir, isolated from any host mount.
- [x] Can plugin versions be pinned in `claude plugin install`, or does it always resolve latest? — **No pin flag exists.** Neither `install` nor `marketplace add` expose a version/ref argument — confirms the version-drift risk below as real, not just theoretical; `marketplace add --sparse` narrows checkout scope but doesn't pin a ref either.
- [ ] Does `Dockerfile.slim` handle plugins the same way as `Dockerfile`, or does it need its own parallel change?
- [ ] What's the credential story for any marketplace that isn't a public GitHub repo, should one get added later?
- [ ] Should `codex/` and `opencode/`'s equivalent prepare/Dockerfile pairs be evaluated for the same change, once context-mode's pilot (if accepted) proves the mechanism out?

---

## Next Steps

If accepted (Option C):
1. Plan projex scoping the context-mode-only pilot: exclude `context-mode` from `prepare.ps1`'s plugin copy/rewrite, add a `Dockerfile` `RUN` step installing it via `claude plugin marketplace add`/`claude plugin install --scope user` as `agent` (user scope — installs into the container's own `~/.claude`, not a project-scoped path that could leak onto a host bind mount), verify hook paths resolve correctly in a built image with no host-baked state involved.
2. Confirm `Dockerfile.slim` parity requirement before or alongside the pilot.
3. If the pilot holds, follow-up Plan/Proposal for full Option A cutover across the remaining plugin set (and optionally `codex/`/`opencode/`).

---

## Appendix

### Research / References

- 2607091752-context-mode-plugin-path-mapping-memo.md — originating diagnosis + fix idea this proposal formalizes.
- `claude/prepare.ps1:60-320` — current copy/rewrite/allowlist implementation (read in full during this proposal's research).
- `claude/Dockerfile:130-180` — plugin `COPY`, native-module rebuild `RUN`, and the pre-existing `merge-claude-settings.sh` first-boot merge mechanism (evidence that this repo already has precedent for deferring some settings work past `docker build` to container-start, relevant if build-time network/auth for Option A/C proves infeasible and a first-boot-install variant is considered later).
- `claude/context/.claude/settings.json:41-74` — verified live shape of `enabledPlugins`/`extraKnownMarketplaces` used to size the Dockerfile `RUN` step in Options A/C.

### Alternatives Considered

- **First-boot install (container-start, not build-time):** Not written up as a fourth option because the memo's stated goal is a network/auth trade at `docker build` time specifically, and `merge-claude-settings.sh` already establishes a working first-boot-merge pattern this repo could reuse — noted here as a variant worth a follow-up proposal if Option C's build-time network/auth requirement proves to be a hard blocker in practice.
