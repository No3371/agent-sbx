# Run baked images without sbx — Evaluation

> **Created:** 2026-07-06
> **Author:** developer@3371.online
> **Subject:** Replacing `sbx` as the launcher for this repo's baked container images (Win10, no OS upgrade)
> **Type:** Status Quo / Comparative
> **Tier:** Standard
> **Lenses:** Constraint Mapping, Inversion, Steel-Manning
> **Related Projex:** none (first projex in repo)

---

## 1. Executive Summary

`sbx` dropped Windows 10 support; the user won't upgrade the OS yet, so the baked `cc-custom`/`codex-custom` images need a new launcher. sbx currently supplies four things the image does *not* bake: (1) a workspace bind-mount, (2) OAuth + `~/.claude.json` session/history/plugin persistence, (3) launching the agent inside the running container, (4) its own `settings.json` baseline (which the image's merge script works *around*). The image is otherwise self-contained (skills/agents/tools/hooks/plugins/settings all baked).

**Recommendation:** a thin `run.ps1` wrapper around `docker run` (or `podman run`) — bind-mount the cwd as the workspace, bind-mount host `~/.claude.json` + the credentials file for OAuth/session persistence, and drop into `claude`/`codex` interactively. No compose, no devcontainer CLI, no new dependency. Roughly 15–25 lines. Everything else in the image already works without sbx because the persistence hook fires from the base image's `/etc/sandbox-persistent.sh` (`BASH_ENV`/`CLAUDE_ENV_FILE`), not from sbx.

**Bonus finding:** removing sbx makes the `merge-claude-settings.sh` dance *unnecessary* — it exists only to survive sbx clobbering `settings.json`. Without sbx nothing clobbers it, so the baked `settings.json` stands as-is and the merge is a harmless idempotent no-op.

---

## 2. Evaluation Scope

**Subject:** How to launch the images built by `claude/` and `codex/` templates without `sbx`, preserving sbx-equivalent runtime behavior.

**Questions addressed:**
- What exactly does sbx do for these images at runtime?
- Which of those responsibilities must the replacement reproduce?
- What are the candidate launchers, and how do they compare?

**Evaluation criteria:**

| Criterion | Weight | Description |
|---|---|---|
| Workspace mount from any dir | High | Run from any project; that dir is the agent's workspace inside the container |
| Agent tool works in workspace | High | `claude`/`codex` runs interactively against the mounted workspace |
| OAuth / session persistence | High | Login survives; sessions/history/plugins/projects persist across runs (sbx did this via host `~/.claude.json`) |
| Win10 compatibility | High | Must run on Win10 with Docker Desktop or podman (already in play) |
| Minimal new surface | Med | Fewest new deps/files; reuse existing `-Engine docker|podman` split |
| Reproducibility / parity | Low | Behaves the same across projects |

**Out of scope:** changing the Dockerfiles or `prepare.ps1` (image internals are correct as-is); multi-container orchestration; remote/registry hosting.

---

## 3. Context Analysis

**Current state (verified against files):**

- Images extend `docker/sandbox-templates:{claude-code,codex}`. Run as `USER agent`, `WORKDIR /home/agent`. Base image ships tini + a CMD that launches the agent (`claude/Dockerfile:156-157`).
- `prepare.ps1` stages host `~/.claude`/`~/.codex` config into `context/`, rewriting Win→Linux paths; `build.ps1` does `podman|docker build` + optional `-Tar`/`-Push`/`-LoadToSbx`.
- README states plainly: **"sbx manages OAuth + `~/.claude.json` (sessions, history, plugins, projects) — none of that is baked here."** (`claude/README.md:10`).
- The Dockerfile documents sbx's runtime shape: **"sbx replaces the container CMD with a sleep sentinel and invokes claude via container-exec"** (`claude/Dockerfile:107-108`) and **"sbx rewrites [settings.json] with its own auth/permissions baseline at sandbox boot, clobbering the baked content"** (`claude/Dockerfile:99-104`).
- `merge-claude-settings.sh` restores baked settings *on top of* sbx's clobber, fired from `/etc/sandbox-persistent.sh` — the base image's `BASH_ENV`/`CLAUDE_ENV_FILE` hook, which fires on every bash/claude spawn **independent of sbx** (`claude/context/scripts/merge-claude-settings.sh`, `Dockerfile:125-136`).

**In-progress evidence (uncommitted, read-only — the user's own exploration):**
- `claude/prepare.ps1`, `codex/prepare.ps1`: modified to also strip nested `.git/` dirs from staged skill trees (hygiene, unrelated to launcher).
- `claude/sbx-cc-custom`: untracked — a **POSIX tar archive (GNU)**, i.e. an exported image (`podman/docker save` output). Confirms the user is already producing loadable tars, one step removed from `docker load` + `docker run`.

**Constraints (Constraint Mapping lens):**

| Constraint | Type | Removable? |
|---|---|---|
| Win10, no OS upgrade | Hard (user-imposed) | No — the whole premise |
| sbx dropped Win10 | Hard (external) | No |
| Docker Desktop or podman present | Soft — both already scripted | n/a (leverage) |
| OAuth not baked in image | Hard (by design, security) | No — must be supplied at runtime |
| Agent runs as `USER agent`, home `/home/agent` | Hard (image) | No — mounts must target `/home/agent/...` and be agent-writable |
| Base image CMD auto-launches agent | Soft | Can override CMD or exec in |

---

## 4. Foundations

**Principle:** sbx is *only* a launcher + credential/session broker + bind-mount manager. The image carries everything else. So replacing sbx = reproduce mount + credentials + session persistence + "start the agent." All four are native `docker run` flags/mounts.

**Key assumptions:**

| Assumption | Validity | Risk if wrong | Sensitivity |
|---|---|---|---|
| Claude Code OAuth/session state lives in host `~/.claude.json` + a credentials file, bind-mountable | High (README states `~/.claude.json` is what sbx manages; CC stores OAuth in `~/.claude/.credentials.json` on Linux or OS keychain elsewhere) | Login won't persist; must re-auth each run | **High** — if creds are keychain-only inside the container, a bind-mount won't capture them; mitigated by `claude login` once into a persisted volume |
| Base image auto-launches the agent via CMD | High (`Dockerfile:156`) | Would need explicit `claude` command | Low — trivially handled by passing the command |
| `/etc/sandbox-persistent.sh` hook fires without sbx | High (it's `BASH_ENV`/`CLAUDE_ENV_FILE` in the base image, not sbx-injected) | Baked settings merge wouldn't run | Low — and without sbx the merge is unneeded anyway |
| Bind-mounted host dir is writable by container `agent` uid | Medium (Docker Desktop on Win handles uid mapping; podman rootless may differ) | Agent can't write workspace | Medium — Docker Desktop generally transparent; test on first run |
| Codex auth analogous (`~/.codex/auth.json`) | Medium | Codex login won't persist | Medium — same mount pattern, different path |

**Prior work:** sbx itself is the prior art — it proves the image runs correctly when given a mount + credentials + exec. The replacement just re-implements sbx's three jobs with stock engine flags.

---

## 5. Analysis

### 5.1 What sbx does — and the minimal replacement for each

| sbx job | Replacement (docker/podman) | Confidence |
|---|---|---|
| Mount project as workspace | `-v "${PWD}:/workspace" -w /workspace` | High |
| Launch agent in container | `docker run -it <img> claude` (override CMD) or default CMD | High |
| OAuth + `~/.claude.json` persistence | `-v "$HOME/.claude.json:/home/agent/.claude.json"` + persist creds (see 5.3) | Medium |
| Rewrite settings.json baseline | **Not needed** — nothing clobbers it without sbx | High |

### 5.2 Candidate launchers (Comparative)

**Finding:** thin `docker run` wrapper wins on every criterion. — Confidence: High — Lens: Constraint Mapping.

| Option | Mount | Agent works | OAuth persist | Win10 | New surface | Verdict |
|---|---|---|---|---|---|---|
| **A. `run.ps1` wrapper (`docker/podman run`)** | ✓ `-v cwd` | ✓ interactive | ✓ mount `~/.claude.json` + creds volume | ✓ | ~20 lines, 0 new deps, reuses `-Engine` split | **Recommended** |
| B. `docker-compose.yml` | ✓ | ✓ but compose is service-oriented, not per-cwd | ✓ | ✓ | new file + must template cwd per project → awkward | Weaker |
| C. devcontainer CLI (`@devcontainers/cli`) | ✓ | ✓ | ✓ | ✓ | new npm dep + `devcontainer.json` per project + heavier | Overkill |
| D. VS Code Dev Containers extension | ✓ | ✓ (in-editor) | ✓ | ✓ | editor-bound, not CLI-from-any-dir | Different use-case |
| E. raw `docker run` typed by hand | ✓ | ✓ | ✓ | ✓ | no file, but long error-prone command each time | Fine as fallback |

**Why A over B/C:** the core requirement is *"from any project dir, mount cwd."* That is inherently a per-invocation, cwd-relative operation — exactly what a shell wrapper does natively and what compose/devcontainer fight against (both expect a project-pinned config file). Compose and devcontainer add a config file per project and (for C) a Node dependency, to buy orchestration/editor features this use-case doesn't need. Ladder rung: native engine feature (`-v`) over dependency.

**Steel-man for devcontainer (C):** if the user later wants per-project tool overrides, forwarded ports, and VS Code "reopen in container," devcontainer is the ecosystem-blessed path and would subsume the wrapper. Counter: none of that is in the stated requirements; adopt C only if/when those needs appear. YAGNI.

### 5.3 OAuth / session persistence — the one real subtlety

**Finding:** `~/.claude.json` persists sessions/history/plugins/projects; OAuth *tokens* live separately. — Confidence: Medium — Lens: Inversion ("what makes login not persist?").

- `~/.claude.json` (sessions, history, plugins, projects) — plain file, bind-mount host→`/home/agent/.claude.json`. Straightforward.
- OAuth credentials — Claude Code stores these in `~/.claude/.credentials.json` (Linux) or an OS keychain. Inside the Linux container there's no keychain, so it falls to the file. **Cleanest approach:** persist the container's `/home/agent/.claude` in a named volume (`-v cc-claude:/home/agent/.claude`), run `claude` once, do the interactive `/login` OAuth flow, and the token file lands in the volume and survives future runs.
  - **Caveat:** the image *bakes* `/home/agent/.claude/{skills,agents,...,settings.json}`. A named volume mounted at `/home/agent/.claude` would **shadow the baked content** on first mount (empty volume masks the image dir). Two clean resolutions:
    1. Mount only the two credential/state files, not the whole dir: `-v cc-state-claudejson:/... ` won't work for a single file cleanly — instead bind-mount host files: `-v "$HOME/.claude.json:/home/agent/.claude.json"` and `-v "$HOME/.claude-docker/.credentials.json:/home/agent/.claude/.credentials.json"`. Host-file bind-mounts don't shadow sibling baked files. **Preferred.**
    2. Or bake nothing to `~/.claude` and mount the host `~/.claude` whole (loses the "self-contained image" property — rejected).
- Codex: analogous — bind-mount `~/.codex/auth.json` (host) → `/home/agent/.codex/auth.json`; `config.toml`/skills already baked, don't mount the whole dir.

**Ponytail note:** don't over-engineer credential handling. First run: `claude` → `/login` → token written to the bind-mounted creds path on host → persists. One host file per agent. No secret manager, no env-injection.

### 5.4 Workspace writability

**Finding:** Docker Desktop on Windows maps the bind-mount transparently; the container `agent` user can read/write the mounted cwd. — Confidence: Medium — verify on first run; if podman-rootless shows uid mismatch, add `--userns=keep-id` (podman) — the calibration knob, not a code change.

---

## 6. Evidence Log

| # | Finding | Source | Type | Conf | Notes |
|---|---|---|---|---|---|
| 1 | OAuth + `~/.claude.json` not baked; sbx supplies them | `claude/README.md:10`, `claude/Dockerfile:11-12` | Primary | High | Defines what the wrapper must add |
| 2 | Base CMD auto-launches agent | `claude/Dockerfile:156-157` | Primary | High | Default `docker run` starts agent |
| 3 | sbx replaces CMD w/ sleep + container-exec | `claude/Dockerfile:107-108` | Primary | High | Without sbx, default CMD path is live |
| 4 | settings.json merge exists only to survive sbx clobber | `claude/Dockerfile:99-109`, `merge-claude-settings.sh` | Primary | High | No sbx → merge is idempotent no-op |
| 5 | Persistence hook is base-image `BASH_ENV`, not sbx | `claude/Dockerfile:125-136` | Primary | High | Baked config works without sbx |
| 6 | Runs as `agent`, home `/home/agent` | `claude/Dockerfile:85-86`, `codex/Dockerfile:44-45` | Primary | High | Mount targets under `/home/agent` |
| 7 | User already exports image to tar | untracked `claude/sbx-cc-custom` = GNU tar | Primary | High | `docker load` + run is one step away |
| 8 | Both engines already supported | `build.ps1:27` (`-Engine`) | Primary | High | Wrapper mirrors the same switch |
| 9 | CC stores OAuth in creds file/keychain | Tertiary (Claude Code auth behavior) | Tertiary | Medium | Drives the bind-mount-creds approach |

---

## 7. Evaluation Against Criteria

| Criterion | Score | Conf | Rationale |
|---|---|---|---|
| Workspace mount from any dir | Strong | High | `-v "${PWD}:/workspace"` is cwd-native |
| Agent tool works in workspace | Strong | High | Interactive `docker run -it ... claude`; base CMD already does this |
| OAuth / session persistence | Adequate | Medium | Bind-mount `~/.claude.json` + creds file; needs one-time `/login`; verify keychain-vs-file |
| Win10 compatibility | Strong | High | Docker Desktop / podman both run on Win10; no sbx dependency |
| Minimal new surface | Strong | High | One `run.ps1`, zero new deps, reuses `-Engine` pattern |
| Reproducibility / parity | Strong | Med | Same wrapper from any dir → identical behavior |

**Overall:** Option A (wrapper) is Strong across the board; the only Medium is credential persistence, which is a one-time-setup detail, not a blocker.

---

## 8. Challenges and Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| OAuth token in container keychain, not a bind-mountable file | Low–Med | Re-auth each run | Bind-mount host creds file → `/home/agent/.claude/.credentials.json`; if CC insists on keychain, persist whole `~/.claude` via named volume seeded from the image once |
| Named-volume-on-`~/.claude` shadows baked skills/settings | Med (if taken naively) | Baked config disappears | Bind-mount **individual** state files, not the whole dir (§5.3) |
| Bind-mount uid mismatch (podman rootless) | Low (Docker Desktop) / Med (podman) | Agent can't write workspace | `--userns=keep-id` (podman); Docker Desktop handles it |
| `~/.claude.json` schema drift between host CC and container CC | Low | Session corruption | Both are current CC; keep versions aligned; back up the file |
| Interactive TTY quirks under Windows PowerShell | Low | Garbled TUI | `docker run -it`; use Windows Terminal; `winpty` only if legacy console |

**Inversion — what makes this fail?** (1) mounting the whole `~/.claude` and shadowing baked content; (2) forgetting `-w /workspace` so the agent starts in `/home/agent`; (3) credentials in a keychain the container can't reach. All three are known and mitigated above.

---

## 9. Findings

- **F1 (High):** The image is fully self-contained except for OAuth, `~/.claude.json`, workspace mount, and "start the agent" — all four are stock `docker run` mounts/flags.
- **F2 (High):** Removing sbx *simplifies* runtime: the `settings.json` merge machinery becomes a harmless no-op because nothing clobbers `settings.json` anymore.
- **F3 (High):** A cwd-relative bind-mount is inherently a shell-wrapper job; compose/devcontainer fight the "any dir" requirement.
- **F4 (Medium):** The only genuine design decision is credential persistence — resolved by bind-mounting individual host state files (not the whole `~/.claude` dir, which would shadow baked skills/settings).
- **F5 (High):** User is already 90% there — producing image tars (`claude/sbx-cc-custom`); `docker load <tar>` then `docker run` closes the loop.

**Gaps:** exact CC OAuth storage inside this specific base image (file vs keychain) is unverified locally — a 2-minute first-run check settles it. Codex `auth.json` path assumed by analogy.

**Opportunities:** the wrapper can subsume `build.ps1`'s `-Engine` switch and even auto-`docker load` the tar if not present, giving a single "build → run anywhere" path with zero sbx.

---

## 10. Recommendations

**Primary:** Write `run.ps1` (in `claude/` and `codex/`, or one shared) wrapping `docker|podman run`:

```powershell
# run.ps1 (sketch — claude variant)
param([string]$Image='cc-custom:v1', [string]$Engine='docker', [string]$Workspace=$PWD)
$claudeState = "$env:USERPROFILE\.claude-docker"   # host-side persisted creds
New-Item -ItemType Directory -Force $claudeState | Out-Null
& $Engine run -it --rm `
  -v "${Workspace}:/workspace" -w /workspace `
  -v "$env:USERPROFILE\.claude.json:/home/agent/.claude.json" `
  -v "${claudeState}:/home/agent/.claude-state" `
  $Image claude
# first run inside container: /login  (OAuth token persists to mounted state)
```

Reasoning: satisfies all High-weight criteria with zero new dependencies, reuses the existing `-Engine` convention, and is cwd-native. Verify on first run whether the OAuth token lands in a bind-mountable file; if so, mount that file directly instead of a state dir.

**Conditional:**
- If OAuth proves keychain-only inside the container → seed a named volume from the image's `~/.claude` once, then reuse it (documented in §5.3 / §8).
- If the user later wants VS Code "reopen in container" or per-project port forwarding → adopt devcontainer CLI (Option C) *then*, not now.

**Next steps:**
- **Immediate:** confirm CC OAuth storage location in a live container (`claude` → `/login` → inspect where the token file lands). Confirm bind-mounted cwd is agent-writable.
- **Short-term:** commit `run.ps1` (+`run.ps1` for codex); update `claude/README.md` Run section to show the no-sbx command alongside the sbx one.
- **Long-term:** optionally fold the tar `docker load` step into the wrapper for a single build→run flow; consider whether `merge-claude-settings.sh` can be dropped now that sbx isn't clobbering settings (leave it — it's a cheap no-op and keeps sbx compatibility).

---

## 11. Open Questions

- [ ] Does this base image's Claude Code write OAuth to `~/.claude/.credentials.json` (bind-mountable) or an OS keychain (not present in-container → file fallback expected)?
- [ ] Is the bind-mounted host cwd writable by the container `agent` uid under Docker Desktop without extra flags? (Expected yes.)
- [ ] Codex OAuth: does it persist to `~/.codex/auth.json`? Same mount pattern assumed.
- [ ] Keep `merge-claude-settings.sh` for dual sbx/no-sbx compatibility, or retire it in the no-sbx world?

---

## 12. Appendix

**Methodology:** Primary-source read of `claude/` + `codex/` Dockerfiles, `README.md`, `build.ps1`, `retag-tar.ps1`, `merge-claude-settings.sh`, and the uncommitted `git diff` of both `prepare.ps1` files + the untracked `sbx-cc-custom` tar. Standard tier: moderate stakes (personal dev tooling), low external uncertainty, single session.

**Lenses:** Constraint Mapping (what sbx must supply), Inversion (failure modes of credential persistence), Steel-Manning (devcontainer as the heavier alternative).

**Sources consulted:** `claude/Dockerfile`, `codex/Dockerfile`, `claude/README.md`, `claude/build.ps1`, `claude/retag-tar.ps1`, `claude/context/scripts/merge-claude-settings.sh`, `git diff` (unstaged `prepare.ps1` ×2), `file claude/sbx-cc-custom`.

**Dissenting view (from steel-manning):** if the user's real trajectory is IDE-integrated container dev, the wrapper is a stopgap and devcontainer is the "correct" long-term tool. Held as a conditional, not the primary — the stated requirement is CLI-from-any-dir, which the wrapper serves better and cheaper.
