# Guide: Understanding `claude/Dockerfile.slim`

> **Created:** 2026-07-08 | **Author:** agent
> **Type:** Codebase
> **Target Audience:** Developer new to this repo, comfortable with Docker/Dockerfile basics but not this project's sandbox history
> **Estimated Time:** 20-25 min
> **Prerequisites:** Basic Dockerfile syntax (FROM/RUN/COPY/ENV/ARG), what a bind mount is
> **Related Projex:** 2607060236-run-images-without-sbx-plan.md, 2607061530-run-images-without-sbx-walkthrough.md

---

## Objective

After this guide you'll understand what `Dockerfile.slim` builds, why it exists as a second Dockerfile alongside the original `Dockerfile`, and how each of its layers (packages, agent user, Go, Claude Code, baked `.claude` config, plugin rebuild) fits into the runtime story completed by `run.ps1`.

---

## Quick Introduction

`Dockerfile.slim` is the **default, non-sbx** image for this repo: `node:24-bookworm-slim` + apt packages + Go (tarball) + Claude Code, with the host's `~/.claude` config (skills, agents, hooks, plugins, settings) baked in by `prepare.ps1` before build. It exists because the original `Dockerfile` requires `docker/sandbox-templates:claude-code` as a base — which in turn requires `sbx` (Windows 11 only). `Dockerfile.slim` recreates just the pieces of that base image this project actually needs (an `agent` user, git identity, PATH plumbing) on top of a plain Node slim image, so the whole stack runs on Docker/Podman alone — no sbx, no Win11 requirement. `build.ps1` builds it by default; `run.ps1` launches it with host OAuth bind-mounted in.

---

## Reading Path

### Phase 1: Orientation — why two Dockerfiles

**Goal:** Understand the fork between `Dockerfile` and `Dockerfile.slim` before reading either line-by-line.

#### Step 1.1: README's Build/Run sections

- **Read:** `claude/README.md` lines 1-32 (top matter through "Build")
- **Focus on:** The line "Default path is non-sbx: `Dockerfile.slim`... The original `Dockerfile` (full `docker/sandbox-templates:claude-code` base, for sbx use) is still there"
- **Key takeaway:** `Dockerfile.slim` isn't a trimmed-down alternative for size — it's the primary, sbx-independent path. `Dockerfile` is now the legacy/secondary one, kept for users still on sbx + Win11.

#### Step 1.2: `Dockerfile` header comment (for contrast, not full read)

- **Read:** `claude/Dockerfile` lines 1-16
- **Focus on:** `FROM docker/sandbox-templates:claude-code` and the comment "sbx supplies host OAuth + `~/.claude.json` itself; this template does not bake credentials"
- **Key takeaway:** The original Dockerfile leans on the sbx base image for the agent user, git config, and OAuth handling. `Dockerfile.slim` has none of that base to lean on, so it must build those pieces itself — that's most of what you're about to read.

---

### Phase 2: `Dockerfile.slim` top to bottom

**Goal:** Walk every layer in build order and know why it's there.

#### Step 2.1: Header, base image, ARGs/ENV

- **Read:** `claude/Dockerfile.slim` lines 1-18
- **Focus on:** The header's bullet list (what this template recreates vs. the sbx base) and the `PATH`/`BASH_ENV`/`CLAUDE_ENV_FILE` env vars
- **Key takeaway:** `BASH_ENV` and `CLAUDE_ENV_FILE` both point at `/etc/sandbox-persistent.sh` — a single file that gets sourced on every non-interactive bash spawn AND read by claude itself. This file is the mechanism used later (Step 2.6) to re-inject baked settings.

#### Step 2.2: apt packages + optional .NET

- **Read:** `claude/Dockerfile.slim` lines 20-37
- **Focus on:** The comment "Deliberately omits sbx base extras like Docker CLI, Java, man-db..." and the `INSTALL_DOTNET` conditional
- **Key takeaway:** This is a scoped package list, not a copy of the sbx base's full toolset — anything not installed here (Docker CLI, Java, etc.) simply isn't available in this image. .NET is opt-out via `ARG INSTALL_DOTNET=0` at build time.

#### Step 2.3: The `agent` user block

- **Read:** `claude/Dockerfile.slim` lines 39-65
- **Focus on:** The `if id node` branch (renames the base image's built-in `node` user to `agent` in place) vs. the `else` branch (`useradd` from scratch), and the `printf` blocks writing the same PATH/BASH_ENV lines into both `/etc/profile.d/` and `~/.bashrc`
- **Key takeaway:** `node:24-bookworm-slim` already ships a `node` user (uid 1000) — this block reuses it by renaming rather than creating a second uid-1000 user. The PATH/BASH_ENV setup is written twice (profile.d for login shells, `.bashrc` for interactive) because sbx's base image doesn't exist here to do it for you.

#### Step 2.4: Git identity block

- **Read:** `claude/Dockerfile.slim` lines 67-74
- **Focus on:** The comment explaining *why* — bind-mounting `/workspace` with host ownership trips git's dubious-ownership guard, and a fresh container has no git identity for the agent's first commit
- **Key takeaway:** This exact block is duplicated verbatim in `claude/Dockerfile` (lines 83-90) — it's not slim-specific, it's a fix both Dockerfiles need for the same bind-mount reason.

#### Step 2.5: Go install + Claude Code/pnpm install

- **Read:** `claude/Dockerfile.slim` lines 76-98
- **Focus on:** `dpkg --print-architecture` arch detection and the final verification line (`node --version; npm --version; pnpm --version; claude --version`)
- **Key takeaway:** Go comes from the official tarball (pinned by `ARG GO_VERSION`), not apt — same reasoning as `Dockerfile`'s Go block (apt's `golang-go` lags upstream). This block is smaller than `Dockerfile`'s Node-purge dance (lines 29-57 there) because slim's base Node is already the desired one — nothing to purge.

#### Step 2.6: Baking `.claude` config + plugin rebuild

- **Read:** `claude/Dockerfile.slim` lines 100-129
- **Focus on:** The `COPY --chown=agent:agent context/.claude/...` lines, then the comment above the plugin-rebuild `RUN` block, then the final `USER root` block appending to `/etc/sandbox-persistent.sh`
- **Key takeaway:** `context/.claude/` isn't checked into this repo as-is — it's generated fresh by `prepare.ps1` (Phase 3) every build. Plugins get `npm install` re-run at build time because native addons (e.g. `better-sqlite3`) built on Windows can't load on Linux — `build-essential` (Step 2.2) exists specifically so this recompile can happen.

> Contrast: `Dockerfile`'s equivalent COPY block (lines 96-137) does the same thing but additionally documents *why* the merge-back is needed (sbx clobbers `settings.json` at boot) — that rationale carries over unchanged to slim's `merge-claude-settings.sh` call, described next.

---

### Phase 3: How the image gets its config — `prepare.ps1`

**Goal:** Understand where `context/.claude/` (baked into the image in Step 2.6) actually comes from, and why settings need a runtime merge step.

#### Step 3.1: What `prepare.ps1` stages and filters

- **Read:** `claude/prepare.ps1` lines 1-21 (header) and 46-58 (`credentialExcludePatterns`)
- **Focus on:** The explicit exclude list — `.credentials.json`, `.claude.json`, sessions, history, projects, cache, statsig, telemetry — and the filename-pattern guard against baking credential-shaped files from *any* staged directory
- **Key takeaway:** `prepare.ps1` runs on the host before `docker build`, converting `~/.claude/{skills,agents,tools,commands,hooks,plugins}` plus `settings.json` into the `claude/context/.claude/` directory that Dockerfile.slim's `COPY` instructions consume. This is a one-way, filtered copy — never raw credentials.

#### Step 3.2: The permission-posture injection

- **Read:** `claude/prepare.ps1` lines 196-234
- **Focus on:** Why `skipAutoPermissionPrompt` is stripped, and why any inherited `ask` rule on `Edit`/`Write`/`NotebookEdit` is stripped too
- **Key takeaway:** The sandbox's permission posture (`--permission-mode auto`, set in `run.ps1`) is a deliberate template decision made *here*, not something silently inherited from whatever the developer's host `settings.json` happens to have — this prevents host-side auto-approve settings (or the opposite: host `ask` overrides) from leaking into the container's behavior.

#### Step 3.3: `merge-claude-settings.sh` — why settings need a runtime merge

- **Read:** `claude/context/scripts/merge-claude-settings.sh` (whole file, 28 lines)
- **Focus on:** The idempotency probe (`jq -e '.extraKnownMarketplaces'`) and the merge direction (`jq -s '.[0] * .[1]'` — bake settings win)
- **Key takeaway:** This script is what Step 2.6's final `RUN` block wires into `/etc/sandbox-persistent.sh`. It's a no-op unless something later overwrites `~/.claude/settings.json` — in `Dockerfile.slim`'s pure-Docker case there's no sbx runtime doing that, but the hook fires harmlessly on every shell/claude spawn regardless (the idempotency check is cheap).

---

### Phase 4: Running the built image

**Goal:** See how `run.ps1` turns the image into a live, host-connected session — closing the loop from build back to daily use.

#### Step 4.1: What gets bind-mounted and why

- **Read:** `claude/run.ps1` lines 1-37 (header comment) and 52-82 (the actual mounts + run args)
- **Focus on:** Why individual files are mounted (`.claude.json`, `.credentials.json`) instead of the whole `~/.claude` dir, and the project-local `.claude/projects` history mount
- **Key takeaway:** Mounting the whole `~/.claude` directory would shadow everything Dockerfile.slim just baked in (skills, agents, settings) — so `run.ps1` mounts only the three files/dirs that carry host identity and history, leaving the image's baked config untouched.

#### Step 4.2: `--permission-mode auto`

- **Read:** `claude/run.ps1` lines 26-37, 82
- **Focus on:** The distinction drawn from `--dangerously-skip-permissions` — auto mode still routes Bash/network calls through Claude Code's classifier
- **Key takeaway:** This flag is why Step 3.2's `ask`-rule stripping matters: an inherited `ask` rule on Edit/Write would silently defeat auto mode's no-prompt behavior for those tools even though the flag is set.

---

## Key Concepts Index

| Concept | Where | Why It Matters |
|---|---|---|
| Non-sbx default path | `claude/README.md:19`, `Dockerfile.slim:1-5` | Explains the whole file's reason to exist |
| `agent` user reuse-or-create | `Dockerfile.slim:39-49` | Avoids a duplicate uid-1000 user; slim-specific vs. `Dockerfile`'s always-fresh `sbx` user |
| `/etc/sandbox-persistent.sh` | `Dockerfile.slim:16-18, 53-65, 127-128` | Single hook file wired to both `BASH_ENV` and `CLAUDE_ENV_FILE`; carries the settings-merge trigger |
| Credential exclusion | `prepare.ps1:46-58` | Guarantees no OAuth/token files get baked into the image layer |
| Permission posture injection | `prepare.ps1:196-234` | Makes sandbox auto-mode behavior an explicit template choice, not inherited host state |
| `merge-claude-settings.sh` | `context/scripts/merge-claude-settings.sh` | Runtime settings merge-back; idempotent, jq-based |
| Individual-file bind mounts | `run.ps1:52-79` | Preserves baked config while still sharing host OAuth/history |

---

## Common Pitfalls

- **Assuming `Dockerfile.slim` is a stripped `Dockerfile`:** It's not a subset build of the same base — it's an independent recreation of only the pieces this project needs, on a completely different (non-sbx) base image. Some blocks (git identity) are duplicated verbatim; others (Go, agent user, Node handling) differ because the underlying base differs.
- **Expecting `context/.claude/` to be a real, hand-edited source directory:** It's fully regenerated by `prepare.ps1` from the host's `~/.claude` on every build — don't hand-edit files there expecting them to persist.
- **Missing why the plugin `npm install` re-run exists:** It's not routine hygiene — it's specifically because `node_modules/` built on Windows can contain native `.node` addons that won't load on Linux (`Dockerfile.slim:113-122`).
- **Confusing `merge-claude-settings.sh`'s job with sbx's:** In the original `Dockerfile`, this script undoes damage sbx's runtime does (clobbering `settings.json` at boot). In the slim/non-sbx path there's no sbx runtime to clobber anything — the script still runs (harmlessly, via the idempotency probe) but isn't doing rescue work there.

---

## Open Questions

- Whether `Dockerfile.slim`'s base image tag (`node:24-bookworm-slim`) is pinned to a digest anywhere in the build pipeline, or floats like `Dockerfile`'s sbx base tag (README.md:108-110 notes this caveat only for the sbx variant) — not verified in this pass.
- `build.ps1` and `.dockerignore` were not read in this guide; the guide covers `Dockerfile.slim` + its direct config/run dependencies (`prepare.ps1`, `merge-claude-settings.sh`, `run.ps1`) but not the build-invocation script itself.

---

## Further Reading

- `claude/Dockerfile` — the sbx/Win11 variant, for full contrast once slim is understood
- `.projex/closed/2607060236-run-images-without-sbx-plan.md` and `2607061530-run-images-without-sbx-walkthrough.md` — the design/implementation history behind why the non-sbx path was added
- `.projex/2607071030-sandbox-permission-user-issues-memo.md` — open notes on permission/user issues in this same area (still active, not closed)
