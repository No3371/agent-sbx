# Definition: Coding-Agent Sandbox Suite Contract

> **Created:** 2026-08-03 | **Last Revised:** 2026-08-03
> **Author:** OpenAI Codex
> **Scope:** Root-owned architecture, behavior, setup, and conformance contract for coding-agent container suites
> **Status:** Draft

---

## Identity

A coding-agent sandbox suite is a root-owned, self-contained container product that turns selected host agent configuration into a Linux image, then launches one or more coding-agent CLIs against the caller's project at `/workspace`. It consists of a preparation boundary, image build/export boundary, and ephemeral interactive runtime boundary. Agent-specific auth, config schema, CLI flags, history, base image, and optional toolchains remain suite-owned variations behind that common shape.

Current observed population: `claude/`, `codex/`, `opencode/`, `omp/`. Each has the runnable asset set defined below. `c_c/` is not current-population evidence: it contains a combined-suite Plan but no runnable suite assets; the Plan treats Claude and Codex as separate source suites until combined acceptance (`2608030408-c-c-combined-suite-plan.md:47-83,111-117`).

This document separates:

- **Observed shared traits (O):** facts present in all four current suites.
- **Future-suite requirements (R):** minimum contract a new suite must satisfy. These requirements intentionally encode only the common shape plus explicit-documentation duties; stronger standardization remains in Open Questions where current suites diverge.

---

## Boundaries

**Is:**

- Root-level contract for suite ownership, canonical assets, preparation/build/run interfaces, workspace mapping, baseline image capabilities, safety layer, operator documentation, and explicit variation points.
- Applicable to a one-agent suite or a combined suite that preserves agent-specific branches behind an explicit selector.
- Concerned with observable suite behavior, not shared-source refactoring.

**Is not:**

- A definition of any agent CLI, provider, model, MCP server, plugin, or language toolchain.
- A promise of hostile-code isolation. Current `rm-guard` prevents accidental deletion only; it is explicitly not a security boundary (`codex/README.md:5-9`; `omp/README.md:109-121`).
- A uniform auth/history policy: current suites materially differ.
- A uniform base-image, Linux user, package-manager, version-pin, engine-default, cache, or optional-language policy.
- A migration, implementation plan, verification plan, or retirement decision for any suite.
- Coverage of obsolete `sbx` variants or directories that only contain projex documents.

---

## Observed Shared Traits

### O1 — Suite ownership and canonical assets

Each current suite is a top-level ownership unit containing:

| Asset | Shared role |
|---|---|
| `README.md` | Operator contract: prerequisites, build, run, state/auth caveats, layout |
| `Dockerfile` | Canonical Linux OCI image definition |
| `.dockerignore` | Excludes image exports, editor noise, and `.git/` from build context |
| `prepare.ps1` | Stages selected host config into suite-local `context/` |
| `build.ps1` | Prepares by default, builds, optionally exports/loads image |
| `run.ps1` | Mounts caller workspace and launches agent interactively |
| `retag-tar.ps1` | Rewrites exported image archive tags when requested |
| `context/` | Generated, filtered image-input tree |
| `rm-guard/rm-guard.sh` | In-image accidental-deletion guard |
| `skills/agent-browser/SKILL.md` | Agent-browser discovery integration |

Grounding: suite layouts (`codex/README.md:87-104`; `claude/README.md:155-169`; `opencode/README.md:138-152`; `omp/README.md:202-219`). All four `.dockerignore` files express the same exclusion categories; suite artifact names vary.

Exact-copy status is not universal. `rm-guard/rm-guard.sh` is byte-identical across all four (SHA-256 `26b546f9240d670646730f5aae0b8d07b6edf9e70d8aef48da7ee9ccaa2bf324`, observed 2026-08-03). `retag-tar.ps1` and agent-browser skill stubs form differing implementations/content, so only their roles are shared.

### O2 — Three-boundary architecture

1. **Prepare boundary:** Windows PowerShell reads agent-owned host config, filters it into a suite-local `context/` subtree, and performs suite-specific portability transforms where implemented. Default source/destination parameters are explicit (`codex/prepare.ps1:20-24`; `claude/prepare.ps1:22-26`; `opencode/prepare.ps1:17-21`; `omp/prepare.ps1:22-26`).
2. **Build boundary:** `build.ps1` accepts mandatory `-Image` and common `-Tar`, `-Retag`, `-LoadToDocker`, `-LoadToPodman`, `-SkipPrepare`, `-NoCache`, `-Enable`, `-Disable`, `-Dockerfile`, and `-Engine` controls. It invokes `prepare.ps1` unless skipped (`codex/build.ps1:13-29,87-93`; equivalent parameter/preparation blocks at `claude/build.ps1:13-30,88-94`, `opencode/build.ps1:13-29,87-93`, `omp/build.ps1:13-30,88-94`). Unsupported language selectors fail rather than becoming silent no-ops; supported catalogs vary.
3. **Run boundary:** `run.ps1` accepts image, engine, workspace, and opt-in `-GPU`; defaults workspace to the caller's current directory; launches `run -it --rm`; bind-mounts it to `/workspace`; sets container cwd `/workspace`; `-GPU` appends `--gpus all`; then starts the suite agent (`codex/run.ps1:12-17,66-89`; `claude/run.ps1:76-87,208-222`; `opencode/run.ps1:25-31,132-156`; `omp/run.ps1:15-21,111-138`).

### O3 — Host and engine setup

All current suites document Windows + Windows PowerShell 5.1 as the supported host scripting environment and Docker/Podman as selectable engines (`codex/README.md:11-16`; `claude/README.md:12-17`; `opencode/README.md:30-35`; `omp/README.md:29-36`). Engine defaults differ: build generally defaults to Podman; run defaults to Docker. Each launcher assumes the image already exists in the selected engine.

### O4 — Image baseline

All current images:

- Are Linux OCI images with an agent CLI and shell/repository baseline.
- Include Node/npm, CodeGraph, agent-browser, Playwright, and a browser installed at build time; pinned `CODEGRAPH_VERSION`, `AGENT_BROWSER_VERSION`, and `PLAYWRIGHT_VERSION` build args are present (`codex/Dockerfile:7-21,63-76`; `claude/Dockerfile:7-19,98-131`; `opencode/Dockerfile:20-34,58-65,76-85`; `omp/Dockerfile:3-16,34-52`).
- Use `tini` as PID 1, either through image `ENTRYPOINT` or explicit runtime entrypoint (`codex/Dockerfile:126-127`; `claude/Dockerfile:221-222`; `opencode/Dockerfile:169-170`; `omp/run.ps1:133-137`).
- Install the same `rm-guard` behavior and build-time self-test: refuse removal of `/workspace/.git`, its descendants, or an ancestor while allowing an unprotected deletion (`codex/Dockerfile:85-108`; `claude/Dockerfile:134-157`; `opencode/Dockerfile:135-158`; `omp/Dockerfile:101-124`).

### O5 — Workspace and package boundary

All launchers expose exactly one caller-selected project at fixed in-container path `/workspace`. If top-level host `node_modules/` exists, each masks it with a workspace-keyed named volume and installs Linux-native dependencies by lockfile/package-manager choice, preventing Windows-native modules from being used inside Linux (`codex/README.md:57-80`; `claude/README.md:120-150`; `opencode/README.md:117-121`; `omp/README.md:186-191`). Cache names, package managers, ownership repair, and persistence differ.

### O6 — Prepared-config filtering and disclosure

All preparation pipelines exclude nested source-control metadata, host `node_modules/`, and recognized credential-pattern filenames before image build. All document the staged subset or exclusions (`codex/README.md:106-141`; `claude/README.md:155-181`; `opencode/README.md:154-179`; `omp/README.md:221-264`). This is filename-pattern filtering, not a proven no-secret invariant: OMP currently stages SQLite/WAL files containing credentials and history and documents the image as secret (`omp/README.md:142-167,245-264`).

Agent-config portability is intentionally suite-specific: Codex rewrites TOML MCP commands; Claude rewrites JSON paths/hooks; OpenCode rewrites local MCP command arrays; OMP performs no path rewriting (`codex/README.md:106-130`; `claude/README.md:171-181`; `opencode/README.md:164-179`; `omp/README.md:221-227,262-264`).

### O7 — Ephemeral container, explicit persistence

Containers are removed after exit (`--rm`), while selected state may survive through host binds or named volumes. Each suite documents its own auth/history/cache contract:

| Suite | Auth/history distinction |
|---|---|
| Codex | Device auth each run; no host credentials or history persistence by launcher (`codex/README.md:34-45`) |
| Claude | Host OAuth file mounted; project-local history mounted (`claude/README.md:59-88`) |
| OpenCode | Host auth/preferences plus project-local SQLite history mounted (`opencode/README.md:87-127`) |
| OMP | Provider DB may be baked; per-project session volume and env credential forwarding (`omp/README.md:142-184`) |

The shared trait is explicit ownership and disclosure of state—not identical persistence.

---

## Future-Suite Requirements

### R1 — Identity and asset surface

A future root-level suite MUST:

- Own a unique root directory and declare its agent CLI(s), host config source(s), container config destination(s), and default image name.
- Provide the canonical assets in O1. `context/` MUST remain generated input owned by `prepare.ps1`, not an alternate runtime state store.
- Use one canonical `Dockerfile`; alternate build modes belong behind build args/selectors unless a separately defined product requires another image.
- Keep suite-specific active projex under `<suite>/.projex/`; root cross-suite definitions/plans remain under root `.projex/`.

A combined suite MAY serve multiple agents only when launch selection is explicit and agent-specific config, auth, state, and option branches cannot be selected implicitly or crossed. This matches the accepted design direction, not current-population evidence (`2608030408-c-c-combined-suite-plan.md:53-76,85-94`).

### R2 — Prepare contract

`prepare.ps1` MUST:

- Be Windows PowerShell 5.1-compatible, terminate on errors, expose overridable host-source and destination parameters, and write only inside its destination.
- Produce the complete Docker build input for agent config; repeated runs MUST remove source-deleted entries or rebuild the destination, so stale config cannot survive silently.
- Recursively exclude `.git/`, `.github/`, `node_modules/`, and the repository's recognized credential filename patterns from staged content.
- Preserve required empty directory/file shape so a build with absent optional host content has deterministic `COPY` inputs.
- State whether host paths/commands require Windows→Linux rewriting. It MUST rewrite, reject, or prominently disclose unresolved host-only paths; it MUST NOT silently claim portability.
- Document every staged category, excluded category, destructive mirror/rebuild behavior, and known sensitive store that filename filtering does not recognize.

### R3 — Build/export contract

`build.ps1` MUST:

- Require `-Image`; default to canonical `Dockerfile`; select Docker or Podman explicitly; invoke preparation unless `-SkipPrepare` is set.
- Default to Docker for both build and run. Podman remains an explicit `-Engine` override.
- Implement the common control surface in O2. `-Enable` and `-Disable` MUST be mutually exclusive; blank, duplicate, or unknown selectors MUST fail before preparation/build. A suite with no optional catalog MUST accept the parameters but reject every selector.
- MUST NOT expose `-Push` or any registry-publication action. `-Tar`, `-Retag`, `-LoadToDocker`, and `-LoadToPodman` remain explicit local operator actions; absent flags MUST NOT export or load elsewhere.
- Use `retag-tar.ps1` only for requested archive retagging and reject input unsafe for that helper.
- Keep build context suite-local through `.dockerignore`, excluding exports, local binaries, editor noise, and SCM metadata while retaining generated `context/`.

### R4 — Image/runtime baseline

A future image and launcher MUST:

- Provide Linux execution, the declared agent CLI, Node/npm, Git/SSH/shell basics, CodeGraph, agent-browser, Playwright, and a build-time-installed compatible browser. Shared tooling versions MUST be explicit build args rather than implicit `latest` resolution.
- Use `tini` as PID 1.
- Install the canonical `rm-guard/rm-guard.sh` and execute its direct-target, ancestor-target, and allowed-delete self-test during build. Documentation MUST repeat that this is accident protection, not isolation.
- Accept `-Image`, `-Engine`, and `-Workspace`; default workspace to caller cwd; launch interactively with `--rm`; mount the selected project at `/workspace`; set cwd `/workspace`; execute the selected agent as the terminal process. Additional auth/state mounts are allowed only when explicitly documented.
- Make CodeGraph initialization/integration failure non-blocking unless the suite explicitly declares CodeGraph indispensable to its agent CLI.
- If host top-level `node_modules/` exists, mask it with the canonical workspace-keyed dependency volume before any Linux install. Dependency/cache volumes are intentionally shared by all suites for the same canonical repository; package-manager choice, compatibility boundaries, ownership repair, and nested-module limits MUST be documented.

### R5 — Auth, state, and variation disclosure

A future suite MUST define—without relying on convention:

- Image user/home and privilege model.
- Credential source, image-build exposure, runtime mounts/env forwarding, refresh/write behavior, and distribution restrictions.
- Session/history, preferences, cache, and package-store locations; which are ephemeral, host-bound, project-local, or named-volume persistent.
- Named dependency/cache volumes use canonical repository identity as their shared scope; they are intentionally cross-suite rather than suite-isolated. Session/history state remains suite-specific unless documented otherwise.
- Base-image/upstream-agent source and pin/freshness behavior.
- Required vs optional toolchains, defaults, exact selector catalog, and what each selector actually removes.
- Agent command, permissions/bypass mode, entrypoint, and agent-specific launcher options.
- A dedicated local sandbox MAY use privileged execution or approval-bypass modes when its command and permission posture are explicit; no separate safe runtime profile is required.
- Redact credential values from diagnostics; never print expanded secret values or secret-bearing engine argument strings.


### R6 — Local conformance

Future-suite conformance requires static contract review plus focused preparation/build-script fixtures. Runtime smoke is OPTIONAL because these suites are highly integrational and personal-state-dependent.
Differences in these fields are valid only when explicit. A README MUST cover prerequisites, build, run, auth/security, persistent state, workspace dependency handling, preparation/staging, exclusions, layout, and reproducibility caveats.

---

## Relationships

| Related entity | Relationship |
|---|---|
| Host agent config | Selected source material; filtered into `context/` before build |
| `context/` | Prepared build input; copied into image-owned agent home |
| Docker/Podman | Interchangeable build/run engines exposed by scripts |
| Upstream base and agent CLI | Suite-specific supply-chain inputs |
| Host project | Single runtime workspace bind at `/workspace` |
| Named volumes / project-local state | Explicit persistence beyond ephemeral container lifetime |
| CodeGraph / agent-browser / Playwright | Shared baked agent capabilities |
| `rm-guard` | Shared accidental-deletion layer for workspace Git metadata |
| `2608030408-c-c-combined-suite-plan.md` | Planned multi-agent suite and future-population change |
| `2607271757-prepare-build-run-optimization-eval.md` | Cross-suite duplication/performance analysis; does not redefine behavior |
| `2608030931-drop-push-current-suites-patch.md` | Removed registry publication from every current suite and updated this contract |

---

## Constraints & Invariants

- **Workspace identity:** launcher-selected host project maps to exactly `/workspace`; container cwd is `/workspace` before agent execution.
- **Ephemerality:** launcher-created container is removed at exit; persistence exists only through explicitly declared binds/volumes or image-baked prepared content.
- **Prepare/build separation:** host config reaches image only through declared prepared context; runtime credential/state mounts are separate and documented.
- **No silent selector fallback:** unsupported, contradictory, blank, or duplicate language selection fails before mutation/build.
- **No silent portability claim:** retained host-only paths are rewritten, rejected, or disclosed.
- **SCM deletion guard:** canonical `rm-guard` protects `/workspace/.git` paths and ancestors and passes unrelated deletion; it is never represented as a security sandbox.
- **Generated-context availability:** absent optional host config cannot make required Docker `COPY` sources disappear.
- **Explicit variation:** auth, history, cache, privilege, pins, toolchains, engine defaults, and agent permission modes are suite-owned and documented; consumers MUST NOT infer one suite's choices from another.
- **No registry publication:** build interfaces do not publish images. Archive export, retag, and cross-engine load occur only when explicitly requested; any known prepared secret makes image/tar distribution restrictions explicit.
- **Living membership:** only runnable roots satisfying R1 count as suites; planned, retired, or projex-only roots do not become population evidence automatically.

---

## States & Lifecycle

| State | Meaning | Valid next state |
|---|---|---|
| Unprepared | No reliable suite-local representation of current host config | Prepared |
| Prepared | Filtered `context/` exists as Docker input | Prepared, Built |
| Built | Image exists in selected engine; no running container implied | Built, Running, Exported/Loaded |
| Running | Ephemeral interactive container owns agent process at `/workspace` | Built |
| Exported/Loaded | Explicit operator action produced tar or loaded another engine | Built, Running |

Re-preparation may change subsequent image content but does not mutate an already-built image. Container removal does not remove declared host/project/volume persistence.

---

## Evidence Quality

- Source snapshot: current repository files on 2026-08-03; no builds or runtime probes performed by this Definition workflow.
- High confidence: asset presence, PowerShell interfaces, Dockerfile declarations, launcher arguments, README-stated behavior.
- Hash grounding: explicit SHA-256 comparison of the four `rm-guard` files and corresponding comparisons showing `retag-tar.ps1`/skill stubs are not universal exact copies.
- Documentation-only confidence: credential contents, provider behavior, cache effectiveness, and hard-kill persistence caveats were not independently exercised.
- Planned direction is not current fact: combined-suite claims are labeled and sourced only from `2608030408-c-c-combined-suite-plan.md`.

---

## Open Questions

- [ ] **Membership:** When `c_c/` becomes runnable, does it replace `claude/` and `codex/` in the active population, coexist with them, or remain a distribution variant?
- [ ] **Multi-agent identity:** Is a suite fundamentally an image/runtime product (allowing multiple agents) or one agent integration? This affects future naming and required selector semantics.
- [ ] **Supply-chain pinning:** Must base images use digests and agent/tool packages use immutable versions, or are documented rolling tags/freshness cache-busts acceptable?
- [ ] **Tool baseline:** Are Node/npm, CodeGraph, agent-browser, Playwright, and a preinstalled browser permanent suite requirements, or merely today's intersection that a non-Node/minimal future agent may omit?
- [ ] **Host support:** Is Windows PowerShell 5.1 a permanent API requirement or a current limitation? If cross-platform support is intended, which shell/script interface is canonical?
- [ ] **State policy:** Must session history persist per project, remain ephemeral, or be agent-specific?
- [ ] **Config portability:** Must preparation reject every unresolved Windows path, or is explicit warning/documentation sufficient for agents such as OMP whose config is copied unchanged?
- [ ] **Shared implementation:** Should byte-identical `rm-guard` and near-duplicate build/export logic remain copied into every self-contained suite, or move to a root-owned shared source while preserving the behavior contract?
- [ ] **Runtime isolation claim:** Is “container is the blast-radius boundary” an intended product guarantee, or should suites consistently avoid isolation language because privileged/root and host mounts weaken it?

---

## Revision Log

| Date | Summary |
|---|---|
| 2026-08-03 | `2608030931-drop-push-current-suites-patch.md`: removed `-Push` from all four current-suite build interfaces, maintained docs/callers, and observed shared surface; registry publication is now prohibited suite-wide. |
| 2026-08-03 | Resolved engine default: future suites default both build and run to Docker; Podman remains explicit override. |
| 2026-08-03 | Local-only policy: remove `-Push`; retain explicit local export/load actions; redact secrets; allow explicit dedicated-sandbox bypass; require static/fixture conformance, not runtime smoke. R2 stale-context rule remains required; Codex now has verified robocopy parity, while current-suite compliance remains uneven. |
| 2026-08-03 | Resolved volume scope: dependency/cache volumes are intentionally shared by all suites per canonical repository; session/history remains suite-specific unless documented otherwise. |
| 2026-08-03 | Initial root-scoped definition; separated four-suite observations from future requirements; recorded divergence and human decisions |
