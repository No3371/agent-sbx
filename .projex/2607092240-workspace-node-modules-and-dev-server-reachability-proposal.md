# Workspace node_modules Contamination + Dev-Server Reachability

> **Status:** Accepted
> **Created:** 2026-07-09
> **Author:** Claude (Opus 4.8) — via propose-projex
> **Related Projex:** 2607060232-run-images-without-sbx-eval.md (defines the `run.ps1` mount model this builds on) | 2607071030-sandbox-permission-user-issues-memo.md (sibling class of first-boot workspace-mount friction) | 2607081815-dockerfile-slim-guide.md (slim variant also affected)
> **Reviewed:** 2026-07-09 — 2607092254-workspace-node-modules-and-dev-server-reachability-review.md
> **Review Outcome:** Needs Modification (resolved) — cited refs verified accurate. Reconciled 2026-07-09: node_modules mechanism is now existence-gated (only masks/seeds when host `node_modules` present), named (not anonymous) volume, yarn caveat added, seed-vs-from-empty efficiency deferred to a Plan-stage benchmark rather than asserted. Accepted for planning.
> **Plans (2026-07-09, split):** 2607092303-dev-server-port-reachability-plan.md (P1 half) | 2607092303-workspace-node-modules-boundary-plan.md (Option A half — deviates to from-empty install, drops cp -a seed; opencode excluded, no Node). Split rationale: features independent; P1 plan-ready/trivial, node_modules half carries the mechanism deviation + verification.

---

## Summary

Running a host-side Node/Vite app inside these sandbox containers hits two systemic failures: (1) the host's `node_modules` — installed on Windows — is bind-mounted whole into the Linux container, so native bundler binaries (rolldown/esbuild/rollup `binding-*.mjs`) fail to load; (2) `run.ps1` publishes no ports and app dev-servers default to `--host 127.0.0.1`, so the host browser can never reach a server running inside the container. Both are suite-level launcher/convention gaps, not app bugs. This proposal explores masking `node_modules` at the mount layer and adding port publishing + a `0.0.0.0` convention.

---

## Problem Statement

### Current State

**Mount model** (`claude/run.ps1:94-101`, mirrored in `codex/run.ps1`, `opencode/run.ps1`):
```
-v "${Workspace}:/workspace" -w /workspace
```
Entire host cwd bind-mounted at `/workspace`. No port publishing (`-p`) anywhere in `run.ps1`. Only individual state files (`~/.claude.json`, credentials, `.claude/projects`) get their own mounts.

**The bind-mount is total.** If the host project dir contains `node_modules/` (from a host `npm install` on Windows), that directory appears verbatim inside the Linux container. Vite's bundler stack ships OS/arch-specific native optional-deps (`@rollup/rollup-linux-x64-gnu` vs `-win32-x64-msvc`, esbuild platform binaries, rolldown `binding-*.node`). Windows-installed `node_modules` carries the win32 binaries and omits the Linux ones → the observed failure:
```
node_modules\rolldown\dist\shared\binding-BxaeY8HI.mjs ... Node.js v25.2.1
npm error Lifecycle script `dev` failed ... command failed: vite --host 127.0.0.1 --port 5173
```

**Established precedent in this repo:** the Dockerfiles already solve the *identical* problem for their own baked plugin trees. `prepare.ps1` skips `node_modules/` from `plugins/`, and each Dockerfile reinstalls in-container:
> "prepare.ps1 skips node_modules/ from plugins/ (it's built on the host — Windows — and native .node addons like context-mode's better-sqlite3 won't load in this Linux container). Reinstall ... so native deps get rebuilt for Linux" — `claude/Dockerfile:145-154`

So the suite already knows "host-built `node_modules` does not cross the Win→Linux boundary." That principle is baked for plugins but **not** applied to the mounted `/workspace`.

**Dev-server reachability:** even after deps are fixed, a server bound to `127.0.0.1:5173` inside the container listens only on the container's own loopback; `run.ps1` publishes no ports. Host browser cannot connect. Two independent gaps: no `-p` publish, and the in-container bind address.

### Gap / Need / Opportunity

Any downstream Node/Vite/webpack/next app run through this suite silently inherits both failures. Fixing per-downstream-repo (as was done for `5d-advanced-wars`) leaves every other app broken. The suite should neutralize this class once, at the launcher/convention layer — the same altitude where the plugin `node_modules` problem was already solved.

### Why Now?

Concrete hit: developer running `vite` dev inside a container against `5d-advanced-wars` got the `binding-BxaeY8HI.mjs` crash. The `run.ps1` no-sbx launcher (per `2607060232-run-images-without-sbx-eval.md`) is now the default entry path, so bind-mount semantics are fully under this repo's control — the right moment to set the convention.

---

## Proposed Change

### Overview

Two orthogonal fixes, packageable together or separately:

1. **`node_modules` boundary** — stop the host's `node_modules` from shadowing into the container, so the container uses Linux-native deps.
2. **Dev-server reachability** — publish ports from `run.ps1` and establish/enforce a `--host 0.0.0.0` convention for servers run inside the container.

### Approach Options — node_modules boundary

#### Option A: Volume mask over `/workspace/node_modules`, seeded from host + reconciled — gated on `node_modules` existing

- **Description:** `run.ps1` checks `Test-Path "$Workspace\node_modules"` before doing anything — **the entire mechanism below is a no-op if the project has no `node_modules` yet.** Nothing to mask, nothing to seed, nothing to conflict with; the plain bind-mount handles that case (container installs fresh, directly into the mount, no contamination possible since there was nothing there). Only when host `node_modules` is present does `run.ps1` add: a read-only shadow bind-mount of it (`/mnt/host-node_modules:ro`) + a named volume (keyed per-project path — see below) masking the live `/workspace/node_modules`. On first start, if the masked volume is empty, `cp -a` the shadow tree into it (local FS copy, no registry traffic), then run `npm install && npm rebuild` inside the container. `install` reconciles per-platform `optionalDependencies` (fixes rolldown/esbuild/rollup-style prebuilt swaps); `rebuild` forces postinstall/native-fetch re-run for packages npm otherwise treats as already satisfied (fixes better-sqlite3/sharp-style postinstall-compiled natives that plain `install` would skip).
- **Pros:** Preventive — host binaries never reach the running app, and only when there's a host tree to protect against in the first place. Named volume (keyed per-project) makes the seed a one-time cost, not per-run. Directly mirrors the precedent the Dockerfiles already set for plugins. Gate keeps a fresh-clone / never-installed project on the cheap, unmodified fast path.
- **Cons:** Nested `node_modules` (monorepos) still need one mask+seed per package dir — single top-level handling insufficient, needs a convention or glob. pnpm is a poor fit for the copy step (node_modules is symlinks into a content-store that isn't copied) — pnpm projects should skip the seed and just run `pnpm install` directly, which re-links from its own store cheaply. Host tooling (IDE running on host) and container hold divergent `node_modules` regardless of seeding. **Unverified:** whether `cp -a` across the Docker Desktop Win↔Linux file-sharing boundary is actually faster than a from-empty `npm install` — the repo's own plugin precedent uses from-empty, not seed-copy; needs a benchmark before locking this in (see Open Questions).
- **Effort:** Low for the top-level single-project case; Medium once monorepo/pnpm-specific branching is handled.

#### Option B: Documented convention + agent-facing skill (reactive remediation)

- **Description:** Ship a short skill/doc (baked like the existing `agent-browser` stub skill) telling the agent: on a `binding-*.mjs` / native-module load error in `/workspace`, `rm -rf node_modules && <pkgmgr> install` to rebuild for Linux; and bind dev servers to `0.0.0.0`. No mount change. Optionally a first-run entrypoint check that greps `/workspace/node_modules` for a win32 binary and prints a one-line warning.
- **Pros:** Zero mount-semantics risk; no reinstall forced when the host `node_modules` happens to be absent or already Linux-native. Handles nested/monorepo cases naturally (agent reruns install where needed). Cheap — one markdown file, reuses the baked-skill delivery path already in the Dockerfiles. Same doc covers the `0.0.0.0` half.
- **Cons:** Reactive — the agent (or human) still eats one failed run + diagnosis before remediation. Relies on the agent reading/triggering the skill. Mutates the host's `node_modules` in place (destructive to host IDE state) unless paired with a mask. Doesn't *prevent* the contamination, only recovers from it.
- **Effort:** Low.

#### Option C: Entrypoint auto-detect + auto-heal

- **Description:** Baked entrypoint/persistent-hook script checks on container start whether `/workspace/node_modules` exists and contains a foreign-platform binary (e.g. presence of `*win32*` optional-dep dirs, or absence of `*linux*` ones). If mismatch → either warn loudly, or auto `rm -rf` + reinstall.
- **Pros:** Fully automatic; no agent/human action. Central — one script covers all three templates via the existing `/etc/sandbox-persistent.sh` wiring.
- **Cons:** Auto-`rm -rf node_modules` on a bind-mounted host dir is **destructive to host state** — deletes the developer's host-side install. Detection heuristics are brittle across pkg managers (npm/pnpm/yarn) and app types. Startup-time reinstall delays every session. Highest blast radius of the three.
- **Effort:** Medium; higher risk.

### Approach Options — dev-server reachability

#### Option P1: `-Ports` param on `run.ps1` + documented `--host 0.0.0.0` convention

- **Description:** Add an optional `-Ports` param to each `run.ps1` that appends `-p` publish flags (e.g. `-Ports 5173` → `-p 127.0.0.1:5173:5173`). Document that servers run inside the container must bind `0.0.0.0`, not `127.0.0.1` (the app's own flag/config — `vite --host 0.0.0.0`, `next -H 0.0.0.0`, etc.).
- **Pros:** Minimal, explicit, opt-in. Publishing to host loopback (`127.0.0.1:host:cont`) keeps the port off the LAN. Reuses the existing param-block pattern in `run.ps1`. The `0.0.0.0` half is doc-only (the container-internal bind is the app's setting, not the launcher's to force).
- **Cons:** Two-sided — user must both pass `-Ports` and ensure the app binds `0.0.0.0`; forgetting either still fails. No autodetection of which ports an app wants.
- **Effort:** Low.

#### Option P2: Publish a fixed common-dev-port range by default

- **Description:** `run.ps1` publishes a default set (3000, 5173, 8080, …) with no user action.
- **Pros:** Works out-of-the-box for common frameworks; no per-run flag.
- **Cons:** Port collisions on the host when multiple containers run; publishes ports the app may not use; still needs the `0.0.0.0` app-side bind. Guessing the range is fragile.
- **Effort:** Low, but noisier.

### Recommended Approach

**Lean hybrid: A (gated, seeded, named-volume mask) + P1 (`-Ports` + `0.0.0.0` doc), with B's short doc as the connective tissue.**

- Node_modules mechanism (A), gated: `run.ps1` only masks+seeds when `$Workspace\node_modules` exists on host. Present → shadow-mount read-only, mask `/workspace/node_modules` with a named volume keyed off the workspace path (e.g. `nmvol-<short-hash($Workspace)>`, since a Windows path isn't a legal Docker volume name), seed via `cp -a` on first (empty-volume) start, then `npm install && npm rebuild`. Absent → do nothing; container installs straight into the bind mount, single package case covered, monorepo caveat documented rather than globbed on day one.
- P1 for reachability: opt-in `-Ports`, host-loopback publish, plus one line of doc telling apps to bind `0.0.0.0`.
- Fold both conventions into one short baked doc/skill (B, minus the destructive auto-heal) so the agent knows *why* `node_modules` looks empty pre-seed (masked, must install) and to bind `0.0.0.0`.
- Reject C — auto-`rm -rf` on a bind-mounted host dir is too destructive for the marginal automation gain.
- **Plan must resolve before finalizing:** benchmark `cp -a` seed+rebuild against a plain from-empty `npm install` on a representative `node_modules` tree (the repo's own plugin precedent uses from-empty, not seed — see review). If seed isn't measurably faster, fall back to from-empty install; keep the named volume either way for persistence.

Rationale (ponytail): climb to the mount-layer fix that *prevents* rather than the entrypoint that *heals destructively*; gate the whole mechanism on node_modules actually existing rather than paying mask/seed cost on every project; ship the single-mask 80% case + a documented caveat over a speculative monorepo-globbing engine.

---

## Impact Analysis

### Affected Areas

- `claude/run.ps1` | `codex/run.ps1` | `opencode/run.ps1`: add `node_modules` mask arg + optional `-Ports` publish arg. Three near-identical edits.
- Baked docs/skill: new short convention doc, delivered via the existing baked-skill COPY path (cf. `skills/agent-browser/` stub in each Dockerfile).
- README run sections: note the `-Ports` flag and the `0.0.0.0` requirement.
- **No Dockerfile logic change required** for the recommended path — masks and ports are pure `run.ps1` runtime flags. (Task constraint: do not modify Dockerfiles — honored; recommended approach lives entirely in `run.ps1` + docs.)

### Dependencies

- Builds on the `run.ps1` launcher established by `2607060232-run-images-without-sbx-eval.md`. If the suite ever returns to sbx-managed launching, sbx controls mounts and this convention would move there.
- Package manager present in-container: Node 24 + npm + pnpm (via corepack) already baked (`claude/Dockerfile:57-58`), so in-container install works offline-permitting.

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `cp -a` seed across Docker Desktop Win↔Linux boundary is slower than from-empty install (unverified — no repo precedent for seed) | Med | Med | Benchmark in Plan; fall back to from-empty `npm install` if seed doesn't win, keep named volume regardless |
| Nested/monorepo `node_modules` not covered by single top-level mask | Med | Med | Document caveat; agent reinstalls per-package (B doc); add globbed masks only if needed |
| Named volume bleeds deps across projects | Med | Med | Per-project volume name keyed off workspace path (hashed — see Recommended Approach) |
| pnpm symlink tree copied without its content-store → dangling links | Med | Low | Skip the seed/copy step for pnpm projects; run `pnpm install` directly, it re-links from its store |
| yarn Berry/PnP has no `node_modules` at all — mask is a silent no-op, `.yarn/unplugged` natives stay broken | Low | Low | Document caveat; not a repo-baked package manager today, so speculative — revisit if it comes up |
| Gate triggers on a host tree that's already Linux-native (host on WSL/Linux) — mask+seed still runs, just redundant | Low | Low | Harmless no-op cost (copy + no-op install/rebuild), not a correctness risk; skip further gating on host platform |
| User passes `-Ports` but app still binds `127.0.0.1` | Med | Low | One-line doc; the failure is self-evident (connection refused) |
| Published port exposed beyond host | Low | Med | Publish to `127.0.0.1:` explicitly, not `0.0.0.0:` on the host side |

### Breaking Changes

None. The `node_modules` mechanism is existence-gated (only activates when `node_modules` is already present on host) rather than an opt-in flag — a fresh/never-installed project's behavior is unchanged. `-Ports` remains a separate opt-in flag; default `run.ps1` behavior otherwise unchanged.

---

## Open Questions

- [ ] `cp -a` seed+rebuild vs plain from-empty `npm install` — which is actually faster/more reliable? No repo precedent for seed (plugin precedent uses from-empty); needs a benchmark early in Plan/Execute before locking the mechanism in.
- [ ] Does the suite want to cover monorepos/pnpm-workspaces now (globbed masks) or defer to the reactive doc?
- [ ] Should `-Ports` publish to `127.0.0.1:` (host-loopback only) or `0.0.0.0:` on the host side? Loopback is safer; LAN-visible only if the developer explicitly wants device testing.
- [ ] Is a baked *skill* (agent-triggerable) preferable to a plain README note, given the agent is often the one hitting the error mid-task (cf. permission memo pattern)?

**Resolved by reconciliation (2026-07-09):** node_modules mask is existence-gated, not opt-in/default-on (mechanism only runs when host `node_modules` present) | volume is named, keyed per-project-path hash, not anonymous | pnpm skips the copy step, runs `pnpm install` directly.

---

## Next Steps

If accepted:
1. Derive a Plan projex scoping the exact `run.ps1` edits (mask arg + `-Ports`) across all three launchers, plus the baked convention doc.
2. Decide the open questions (mask default-on vs opt-in; anon vs named volume) — likely via a short interview or the plan's own trade-off call.
3. Validate against the original `5d-advanced-wars` Vite case end-to-end: mask on → `npm install` in container → `vite --host 0.0.0.0` → `-Ports 5173` → host browser reaches `127.0.0.1:5173`.

---

## Appendix

### Research / References

- `claude/run.ps1:94-104` — total `/workspace` bind-mount, no `-p` publish, individual-file state mounts.
- `claude/Dockerfile:145-154` / `claude/Dockerfile.slim:131-140` / `codex/Dockerfile:85-89` — existing precedent: host `node_modules` skipped + reinstalled in-container for plugins (the principle this proposal extends to `/workspace`).
- `2607060232-run-images-without-sbx-eval.md` — established the `run.ps1` mount/launch model.
- Observed failure (verbatim): `node_modules\rolldown\dist\shared\binding-BxaeY8HI.mjs ... command failed: vite --host 127.0.0.1 --port 5173`.

### Alternatives Considered

- **Entrypoint auto-`rm -rf` + reinstall (Option C):** rejected as primary — destructive to bind-mounted host state, brittle detection. Viable only as a *warn-don't-delete* first-boot check.
- **Default fixed port range (Option P2):** rejected — collision-prone, publishes unused ports, still needs the app-side `0.0.0.0` bind.
- **Force `--host 0.0.0.0` from the launcher:** not possible — the bind address is the downstream app's own dev-server flag/config, outside `run.ps1`'s reach. Launcher can only publish ports + document the convention.
