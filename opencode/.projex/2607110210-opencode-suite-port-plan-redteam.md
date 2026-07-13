# Red Team: OpenCode Suite Port Plan

> **Created:** 2026-07-11 | **Lead:** agent (sonnet)
> **Subject:** `2607110159-opencode-suite-port-plan.md` | **Related:** 2607081900-codegraph-integration-audit.md | 2607100834-language-build-feature-flags-audit.md | 2607100805-language-build-feature-flags-redteam.md

---

## Bottom Line

**Verdict:** Fix Issues

**Top Vulnerabilities:**
1. **Step 3's own scoping claim is false** — opencode.json has a documented `permission` key (opencode.ai/docs/config) directly analogous to what claude's prepare.ps1 deliberately strips (`skipAutoPermissionPrompt`, permissive `ask` rules) for security. The plan asserts "opencode.json has no such fields" and ports zero permission-posture filtering, so a host's fully-auto-approving `permission` block gets baked byte-for-byte into any shared/pushed image.
2. **Step 3's MCP command rewrite only inspects `command[0]`** of the array, never `command[1..]` — a Windows path stashed as an argument (e.g. `["node", "C:\\Users\\dev\\mcp\\index.js"]`) is neither rewritten nor dropped, so the server "passes" prepare.ps1 while silently pointing at a path that doesn't exist in the container, violating the plan's own acceptance criterion.
3. **PowerShell 5.1's JSON array-of-one collapse bug is unaddressed** — a single-token local `command` (e.g. `["some-binary"]`) deserializes as a bare string in PS 5.1 (the project's pinned shell), skips the `-is [System.Array]` rewrite path, and gets re-serialized as a non-array `command` — a schema violation opencode won't accept. The plan's own verification fixture (multi-token example) can't catch this.
4. **`pm-cache`/`pnpm-store-cache` volume names are reused verbatim from claude/run.ps1** — an Alpine/musl container now shares an on-disk package-manager store with a Debian/glibc container under the identical volume name, with no suffix or isolation proposed. This is the same class of cross-platform native-binary bug the node_modules-masking feature exists to prevent, reintroduced one layer up, at the shared-cache layer.
5. **The new `opencode-cache` volume has no ownership-fixing step anywhere in the plan** — Step 2 never creates `/home/agent/.cache/opencode` at build time, Step 4 never chowns it at runtime (unlike `.pnpm-store`, which the ported `$pmSetup` explicitly chowns). On Docker (the project's default engine), the fresh named volume mounts root:root and the non-root `agent` user gets `EACCES` on first opencode plugin install.

---

## Stakeholder Roles

| Role | Cares About | Pain Points | Critical Assumptions |
|------|-------------|-------------|---------------------|
| Operators (build/run images) | Image builds clean, run.ps1 launches reliably, state persists across `--rm` | Silent build success that fails at first real use (permission EACCES, missing pnpm, broken MCP server) | apk repos have go/python3/chromium at pinned base; volumes come up writable |
| Security (image is shared/pushed) | No host secrets or permissive posture baked into an artifact others pull | `opencode.json`'s `permission` key ships un-filtered into a distributable image | Claude's prepare.ps1 pattern ("strip permissive host config, don't inherit silently") was fully re-derived for opencode, not partially |
| Developers (author/execute the plan) | Steps are internally consistent and individually correct | Step 2 (node/npm only, no corepack) and Step 4 (assumes pnpm/corepack) were written independently and never reconciled | Each step's Dockerfile/run.ps1 changes compose without a runtime gap |
| Integrators (run claude/ and opencode/ suite side by side on one host) | Suite images are independent; using one doesn't corrupt the other | Shared literal volume names (`pm-cache`, `pnpm-store-cache`) span two different libc ABIs | No one ever runs both templates against overlapping cache volumes — false, that's the suite's whole premise |
| End users (agents running inside the container) | MCP servers configured on the host actually work in-container; agent-browser actually drives a browser | A "successfully rewritten" MCP entry that's actually still broken; `agent-browser --version` passing while a real navigate silently tries to fetch Chrome-for-Testing | Build-time smoke test (`--version`) is sufficient proof the runtime browser-resolution path works |

---

## Attack Surface (Per Role)

**Operators:**
- Claims: build.ps1 toggles behave like claude's; run.ps1 persists history/caches/deps the same way.
- Assumptions: apk `go`/`python3`/`chromium` availability at build time (only go/python's availability is explicitly verified in the plan — Assumption 3 never covers chromium); named volumes come up writable for a non-root user.
- Dependencies: third-party `ghcr.io/anomalyco/opencode` base's `/etc/apk/repositories` layout (unverified, unpinned upstream), Alpine `community` repo enabled.

**Security:**
- Claims: "Porting Claude's hooks/statusLine/skipAutoPermissionPrompt transforms — opencode.json has no such fields... Nothing to port."
- Assumptions: the plan's Context section's schema summary (`mcp`, no hooks, no statusLine, no skipAutoPermissionPrompt) is complete. It omits `permission`, a documented, security-relevant key.
- Dependencies: prepare.ps1 staying the only line of defense between a developer's personal, permissive `opencode.json` and a distributed image.

**Developers:**
- Claims: "node is baseline now" (Assumption 5) is used in Step 4's rationale to justify porting claude's pnpm-based node_modules-reinstall logic "verbatim."
- Assumptions: baseline node ⇒ baseline pnpm/corepack. False — Step 2 only ever runs `apk add --no-cache nodejs npm chromium`; no `corepack enable`/`corepack prepare pnpm@latest --activate` (which claude's own Dockerfile does explicitly, one ARG block earlier in that file).

**Integrators:**
- Claims (implicit, via "Preserve existing conventions"): named volumes named identically to claude's are safe to reuse because the pattern being ported already works.
- Assumptions: package content addressed by version/integrity is portable across libc. True for packages using the modern per-platform-optionalDependency pattern (rollup, esbuild, sharp v0.3x+); not universally true for older node-gyp/prebuild-install packages that key a cached binary by platform+arch only, not libc.
- Dependencies: whichever packages a given `/workspace` project happens to pull in — not under this suite's control, so the risk surface is "any project a user opens with both templates on the same host," which is exactly the suite's intended use.

---

## Critical Findings

### Finding 1: `permission` config field omitted from Step 3's scope, contradicting the plan's own security rationale
**Severity:** Critical | **Likelihood:** High

**Affects Roles:** Security, Operators, Integrators (anyone who pulls a pushed image)

**Attack Vector:** opencode.json's documented schema (opencode.ai/docs/config) includes a `permission` key: *"By default, opencode allows all operations without requiring explicit approval. You can change this using the `permission` option."* This is the direct functional analog of claude's `skipAutoPermissionPrompt` + `permissions.ask` posture — which claude/prepare.ps1 explicitly strips with the stated rationale: *"permission posture is a template-author decision, not silently inherited from host config."* The plan's Out of Scope section asserts: *"opencode.json has no such fields... Nothing to port; asserted in Step 3."* That assertion is false — the plan's own Context section schema summary lists `mcp` and explicitly denies hooks/statusLine/skipAutoPermissionPrompt, but never mentions `permission` at all, meaning the research pass that produced this plan never surfaced the field.

**Role-Specific Impact:**
- **Security:** A host's `~/.config/opencode/opencode.json` with a wide-open `permission` block (the documented default posture is already "allow all") gets copied through prepare.ps1's plain filtered copy with zero inspection, then baked into any image `build.ps1 -Push`es. Every consumer of that shared image inherits the original author's personal, possibly maximally-permissive automation posture, silently.
- **Operators:** No warning, no log line, no acceptance criterion catches this — prepare.ps1's whole job in the plan's own framing is "adapted to whatever the target's config schema actually supports," and this is exactly the surface it was supposed to catch.

**Blast Radius:** Every opencode image built from a real developer's host config; worse for any image reaching a shared registry per `build.ps1 -Push`, which the plan's own build examples treat as a first-class path.

**Remediation:** Extend Step 3 to inspect and either strip or explicitly warn on a permissive `permission` block the same way claude's `permissions.ask` stripping works — decide the template-author's default posture deliberately, don't inherit it.

---

### Finding 2: MCP command-array rewrite only checks index 0, silently missing path-bearing args
**Severity:** Critical | **Likelihood:** Medium-High

**Affects Roles:** End Users, Operators

**Attack Vector:** opencode's local MCP `command` is documented (and the plan itself states this) as a full array including arguments — `["npx","-y","pkg"]` — unlike claude's schema where `command` and `args` are separate fields. The plan's own worked example only ever puts the problematic Windows path at `command[0]` (an `npx.cmd` shim). But the far more common real-world shape for a locally-installed MCP server is `["node", "C:\\Users\\dev\\.mcp-servers\\foo\\index.js"]` — a bare, already-Linux-safe executable name (`node`) at index 0, with the actual host-only absolute path at index 1+. The sketch's rewrite call (`$srv.command[0] = Rewrite-McpCommand $orig`) and its drop-check (`if ($srv.command[0] -match '^[A-Za-z]:[/\\]')`) both only ever touch index 0. A server shaped this way sails through unmodified and undropped — no warning logged, `command[0]` never matched the Windows-path regex — while `command[1]` still holds a path that doesn't exist anywhere in the container filesystem.

**Role-Specific Impact:**
- **End Users:** The MCP server appears configured (no warning was printed, nothing was dropped) but fails silently or with an opaque "file not found" at opencode startup, with no signal pointing back to prepare.ps1 as the cause.
- **Operators:** The acceptance criterion "drops servers with no Linux mapping (warning)" is not actually met for this common shape — it's met only for the narrower case the plan's own example happens to construct.

**Blast Radius:** Any staged `opencode.json` where a local MCP server's Windows path lives in a command-array position other than 0 — plausible for the majority of node-script-based local servers, since `node <script>` is the idiomatic invocation shape.

**Remediation:** Rewrite/validate every element of `command`, not just `command[0]`; drop the server if any element still matches a Windows drive-letter path after rewriting.

---

### Finding 3: PowerShell 5.1 collapses single-element JSON arrays — breaks the array-typed `command` schema this port relies on
**Severity:** High | **Likelihood:** Medium

**Affects Roles:** Operators, End Users, Developers (whoever debugs the resulting corrupted config)

**Attack Vector:** This repo's own README states PowerShell 5.1 is required ("`pwsh` (PowerShell Core 7.x) has known encoding differences; use Windows PowerShell"). In PS 5.1, `ConvertFrom-Json` deserializes a single-element JSON array (`["some-binary"]`) as a bare scalar, not a one-element array — a long-documented PS 5.1 quirk (fixed only in PS 7's `-AsArray`, which doesn't exist in 5.1). Any local MCP server with a one-token `command` (no args — e.g. a globally-installed binary invoked bare) trips this: `$srv.command -is [System.Array]` evaluates `$false`, so Step 3's whole rewrite/drop branch is skipped for that server. Worse, on the final `ConvertTo-Json` write-back, that field round-trips as a plain string, silently rewriting a spec-valid `command: ["foo"]` into a spec-invalid `command: "foo"` in the baked config — corrupting a server that was never even part of the problem this step was solving.

**Role-Specific Impact:**
- **Operators:** A perfectly valid, non-Windows-path-bearing local MCP entry gets its schema silently broken by a pass-through step that had no reason to touch it.
- **Developers:** The plan's own fixture-based verification ("fixture opencode.json with one local server whose `command[0]` is `C:\Users\me\...\npx.cmd`") uses a multi-element array and would never exercise this path — the bug ships without ever failing a documented check.

**Blast Radius:** Any single-token local MCP `command` in a staged config — a schema-shape choice entirely outside this plan's control, so it will eventually be hit by some developer's real config.

**Remediation:** Force array typing explicitly after `ConvertFrom-Json` (e.g. `@($srv.command)`) before the `-is [System.Array]` check and before iterating; verify round-trip with a single-element fixture, not just multi-element.

---

### Finding 4: Shared `pm-cache`/`pnpm-store-cache` volume names span glibc (claude) and musl (opencode) containers
**Severity:** High | **Likelihood:** Medium (depends on package mix; not universal, but plausible and undetectable until it happens)

**Affects Roles:** Integrators, End Users, Operators

**Attack Vector:** Step 4 item 3 specifies `-v pm-cache:/home/agent/.npm -v pnpm-store-cache:/home/agent/.pnpm-store`, and claude/run.ps1 already uses those exact literal volume names against `docker/sandbox-templates:claude-code`-derived, Debian-glibc images. Because Docker/Podman named volumes are host-global by name, running `opencode/run.ps1` and `claude/run.ps1` on the same machine — the explicit premise of this being a "suite" — now aims both containers' package-manager caches at the same on-disk store, one glibc, one musl. The whole reason `node_modules` masking + per-project reinstall exists in the ported design is that a *host-built* `node_modules` carries win32-native binaries that crash in Linux containers; this finding is the same failure class one layer up: a *glibc-container-built* package-manager store entry can carry compiled/prebuilt native artifacts (older node-gyp/prebuild-install packages that key by platform+arch but not libc) that a musl container then reuses. Modern per-platform-optionalDependency packages (rollup, esbuild, sharp 0.3x+) are safe because the package *name* differs by libc — but that's not universal, and nothing in the plan even considers the question.

**Role-Specific Impact:**
- **Integrators:** Using both templates against the same or sibling projects is the intended workflow; this finding activates exactly there.
- **End Users:** A native-binary crash inside the *opencode* container that only reproduces after the *claude* container was used first (or vice versa) — a heisenbug with no obvious cause, defeating the entire purpose of the masking feature this plan is trying to replicate.

**Blast Radius:** Any project with an older-style native npm dependency, opened under both templates on one host.

**Remediation:** Namespace the volume names per-template (e.g. `opencode-pm-cache`, `opencode-pnpm-store-cache`) — cheap, and removes the question entirely rather than relying on an ecosystem convention that isn't universally followed.

---

### Finding 5: New `opencode-cache` volume has no build-time or run-time ownership fix
**Severity:** High | **Likelihood:** High (default engine is Docker, not podman)

**Affects Roles:** Operators, End Users

**Attack Vector:** Step 4 item 2 adds `-v opencode-cache:/home/agent/.cache/opencode` to persist opencode's Bun-installed plugin `node_modules` across `--rm`. Step 2's Dockerfile changes never create this directory at build time (they only touch `nodejs`, `npm`, `chromium`, `agent-browser`), so nothing exists at that path in the image to "copy up" ownership from when the volume first mounts. A fresh named Docker volume mounted onto a nonexistent image path defaults to root:root. `run.ps1`'s default `$Engine` is `'docker'` (not podman), so `--userns=keep-id` — the one thing that would otherwise paper over this — never fires. The container runs as non-root `agent` (uid 1000, per Dockerfile's `USER agent`). First opencode plugin install attempts to write into `/home/agent/.cache/opencode` and gets `EACCES`. Contrast with `.pnpm-store`, which the ported `$pmSetup` explicitly `sudo chown agent:agent`s at every launch — the plan applied that fix to the volume it copied from claude, but invented a brand-new volume without replicating the same safeguard.

**Role-Specific Impact:**
- **Operators:** "Persist opencode plugin/npm cache across `--rm`" (a stated Step 4 objective) silently fails on the default engine.
- **End Users:** Plugin installs inside opencode fail with a permission error that has nothing obviously to do with the run.ps1 launcher that caused it.

**Blast Radius:** Every `run.ps1` invocation on Docker (the default engine) once this volume exists.

**Remediation:** Add `sudo chown agent:agent /home/agent/.cache/opencode 2>/dev/null` to `$pmSetup` alongside the existing `.pnpm-store` line, or pre-create+chown the directory at build time in Step 2.

---

### Finding 6: Step 4's ported pnpm/corepack logic assumes tooling Step 2 never installs
**Severity:** Medium-High | **Likelihood:** Medium

**Affects Roles:** Developers, Operators, End Users

**Attack Vector:** Step 4's rationale explicitly leans on Assumption 5 ("node is required baseline... therefore NOT a language toggle") to justify porting claude's `$pmSetup`/`$nmInstall` blocks — which invoke `corepack pnpm config set store-dir`, `corepack pnpm install`, and fall back to bare `pnpm`/`yarn`/`npm`. Claude's own Dockerfile earns that assumption explicitly: `corepack enable; corepack prepare pnpm@latest --activate;` runs at build time, right after Node install. Step 2's Dockerfile snippet for opencode is exactly `apk add --no-cache nodejs npm chromium && npm install -g "agent-browser@${AGENT_BROWSER_VERSION}" && agent-browser --version` — no `corepack enable`, no pnpm activation, anywhere in the plan. "node is baseline" was true for claude because pnpm-via-corepack was baselined alongside it in the same file; the plan carries the conclusion into opencode's context without carrying the premise.

**Role-Specific Impact:**
- **Developers:** Step 2 and Step 4 were each individually reasoned through but never cross-checked against each other — the "Implementation Overview" claims the steps only overlap on the Dockerfile for Steps 1+2, missing that Step 4 has a hard runtime dependency on a tool Step 2 doesn't install.
- **End Users:** Any pnpm-lockfile project hitting the node_modules-mask path (`corepack pnpm install || pnpm install`) fails both branches if neither corepack nor a standalone pnpm binary is present.

**Blast Radius:** Every masked-node_modules run against a pnpm-based project — likely, since pnpm is explicitly called out as the primary case in both templates' state-handling design.

**Remediation:** Add `corepack enable && corepack prepare pnpm@latest --activate` to Step 2's Dockerfile block (mirroring claude's), and verify Alpine's `nodejs`/`npm` apk packages actually ship a usable `corepack` binary before assuming parity.

---

### Finding 7: agent-browser/chromium/node have no opt-out, unlike the newly-ported language toggles
**Severity:** Medium | **Likelihood:** High (certain, by design)

**Affects Roles:** Operators, Business (image size / build cost)

**Attack Vector:** The plan's headline feature (Step 1) is giving operators an opt-in/opt-out toggle for optional languages. Step 2 bakes agent-browser + its dependency chain (nodejs, npm, chromium) unconditionally, with zero `ARG`/`-Enable`/`-Disable` knob — despite chromium being, by a wide margin, the single largest and highest-risk addition in the entire plan (an Alpine `community`-repo package; ~127 MiB download / ~281 MiB installed per current Alpine package metadata). Assumption 3 explicitly calls for verifying `go`/`python3` availability against the base's apk repos "without enabling edge" — the same scrutiny is never applied to `chromium`, even though it's newly introduced by this plan (unlike go/python, which the pre-port build.ps1 already referenced) and depends on the `community` repo being enabled in the third-party `ghcr.io/anomalyco/opencode` base image, which the plan never inspects.

**Role-Specific Impact:**
- **Operators:** Anyone who wants a lean opencode image with codegraph but no browser automation has no lever to pull — the port explicitly removed that possibility relative to what a toggle-consistent design would offer, and relative to claude's slim/full Dockerfile split (which this plan correctly declines to replicate, but doesn't replace with an equivalent language-toggle-style escape hatch for agent-browser specifically).

**Blast Radius:** Every build, permanently, unless the plan is revised.

**Remediation:** At minimum, verify `community` repo + chromium availability against the base image's actual `/etc/apk/repositories` (same rigor as go/python), and consider an `INSTALL_AGENT_BROWSER` toggle consistent with the Step 1 pattern this same plan just introduced.

---

### Finding 8: `go`/`python3` apk installs are unpinned, contradicting the plan's own stated convention
**Severity:** Medium | **Likelihood:** High (certain)

**Affects Roles:** Operators, Developers

**Attack Vector:** The plan's Constraints section states: *"Preserve existing conventions: pinned versions via `ARG` (not `@latest`)."* Claude's Go install pins `ARG GO_VERSION=1.26.3` against an official tarball; its .NET install pins `ARG DOTNET_CHANNEL=10.0`. Step 1's Dockerfile snippet for opencode is `apk add --no-cache go` / `apk add --no-cache python3 py3-pip` — no version argument at all. Combined with the opencode README's already-documented note that the base image tag itself floats ("Base image tag... is floating (`:latest`)... rebuilds on different dates may pull a different base"), this compounds: not just the base OS but now the language toolchains inside it are unpinned and will drift silently between rebuilds.

**Role-Specific Impact:**
- **Operators:** Two builds run weeks apart, same command, can produce images with different Go/Python versions with no record of which.

**Blast Radius:** Every build; a reproducibility regression, not a functional break.

**Remediation:** Either accept and document the drift explicitly (Alpine's own package-pinning story for `go`/`python3` is weaker than a tarball/apt-pin approach, so full parity may not be achievable), or pin via `apk add go=<version>` where the base's repo snapshot supports it.

---

## Role-Based Assumption Challenges

### Security: "opencode.json has no permission-posture fields to strip"
**Challenge:** Directly contradicted by opencode's own documentation, which defines a `permission` config key controlling exactly this posture, with a default of "allow all."
**Counter-Evidence:** opencode.ai/docs/config lists `permission` as a top-level key alongside `mcp`, `agent`, `tools`, etc.
**If Wrong:** Every image built from a permissive host config ships that posture to every consumer, silently — the precise failure claude's prepare.ps1 was written to prevent.
**Action:** Reject as stated; revise Step 3 to cover `permission`.

### Developers: "node is required baseline; therefore NOT a language toggle" implies pnpm/corepack parity with claude
**Challenge:** Node-as-baseline and pnpm-as-baseline are two different claims; claude bundles both explicitly in the same Dockerfile block, this plan's Step 2 bundles only the former.
**Counter-Evidence:** Step 2's Dockerfile snippet text contains no `corepack` reference at all.
**If Wrong:** Step 4's entire node_modules-masking reinstall path (the pnpm branch specifically) fails at runtime for pnpm-lockfile projects.
**Action:** Relax — add the missing `corepack enable` step, then the assumption holds.

### Operators: "reusing claude's exact volume names is safe because the underlying pattern already works there"
**Challenge:** The pattern (persist a package-manager store across `--rm`) works fine in isolation; the *specific literal names* were never designed to be shared across two different libc targets, and nothing in either template's design considered that case.
**Counter-Evidence:** claude/run.ps1 and the proposed opencode/run.ps1 use identical volume name strings for architecturally different containers, and the "suite" framing of this port task means both are expected to run on the same host.
**If Wrong:** Native-binary corruption bugs that are hard to reproduce and don't correlate with any single template's changes.
**Action:** Reject as stated; namespace the volume names.

---

## Role-Specific Edge Cases & Failures

### Operators: single-token local MCP `command` in a real host config
**Trigger:** A developer's `~/.config/opencode/opencode.json` has a local MCP server with no arguments, e.g. `"command": ["my-mcp-server"]`.
**Role Experience:** prepare.ps1 runs cleanly, no warnings; the baked image's `opencode.json` has that server's `command` silently changed from an array to a string, which — per opencode's documented schema (array required for local servers) — likely fails validation or misbehaves when opencode loads it.
**Recovery:** Difficult — nothing in prepare.ps1's own output points at this field; a user has to diff the source and staged JSON to find it.
**Mitigation:** Force-array-cast after `ConvertFrom-Json`; add a single-element fixture to the automated checks.

### End Users: local MCP server with a path argument, not a path executable
**Trigger:** `"command": ["node", "C:\\Users\\dev\\mcp-servers\\foo\\index.js"]` in the host config.
**Role Experience:** No warning at prepare time; the server appears configured; opencode fails to start it (or errors at first tool call) with no path back to prepare.ps1 as root cause.
**Recovery:** Possible once diagnosed, but the diagnosis path is non-obvious (nothing flags this as prepare.ps1's doing).
**Mitigation:** Validate every array element, not just index 0.

### Integrators: running both templates against the same host, different projects
**Trigger:** `opencode/run.ps1` used on a project with an older-style native npm dependency, after `claude/run.ps1` has already populated `pnpm-store-cache` from a glibc build.
**Role Experience:** A native-binary load failure inside the opencode (Alpine) container for a dependency that installs fine everywhere else — looks like an Alpine/musl incompatibility bug in the dependency itself, not a caching design flaw in this suite.
**Recovery:** Possible (clear the shared volume) once correctly diagnosed; otherwise very difficult to root-cause.
**Mitigation:** Namespace volumes per template.

---

## What's Hidden (Per Role)

**Omissions per role:**
- **Security:** The plan never re-derives claude's "strip permissive host posture" principle against opencode's actual permission schema — it asserts the schema has nothing analogous and moves on, without the schema check that assertion required.
- **Operators:** No opt-out for the single largest/riskiest new dependency (agent-browser's chromium chain), despite Step 1 introducing exactly that opt-out mechanism for languages in the same plan.
- **Developers:** Step 2 and Step 4 were drafted as independent, "no shared file" steps (per the plan's own Overview: "Steps are independent in intent") — but Step 4 has an undeclared functional dependency on tooling only Step 2 could have installed, and didn't.

**Tradeoffs per role:**
- **Operators:** Traded build-time reproducibility (unpinned go/python versions) for Alpine-native simplicity, without flagging the tradeoff against the plan's own stated pinning convention.
- **Integrators:** Traded volume-naming simplicity (verbatim reuse) for cross-architecture cache isolation, without the tradeoff being surfaced as a decision at all.

---

## Scale & Stress (Role Impact)

**At 10x (many developers building/running this suite on shared or long-lived hosts):**
- **Operators:** Volume-name collisions (Finding 4) and permission-key leakage (Finding 1) go from "theoretical" to "statistically likely to be hit by someone" — more developers, more host configs, more chance one of them has a permissive `permission` block or an older native dependency.
- **Integrators:** The shared-cache risk compounds with every additional template added to the suite in the future if the same verbatim-naming pattern is followed again.

**At 100x (this pattern reused as the template for a future codex/ or other suite port):**
- **Developers:** Each future port inherits the same "steps independently reasoned, not cross-checked" process gap (Finding 6) unless this plan's remediation is fed back into how future ports are drafted.

---

## Remediation

### Must Fix (Before Proceeding)
- **Step 3 omits `permission` config filtering** (affects: Security, Operators) → add permission-posture handling analogous to claude's `skipAutoPermissionPrompt`/`ask` stripping → verify against opencode.ai/docs/config schema
- **MCP rewrite only checks `command[0]`** (affects: End Users, Operators) → validate/rewrite every array element → verify with a `["node", "C:\\...\\index.js"]`-shaped fixture
- **PS 5.1 single-element array collapse** (affects: Operators, End Users) → force-array-cast after `ConvertFrom-Json` → verify with a `["binary"]`-shaped fixture, not just multi-element

### Should Fix (Before Production)
- **Shared `pm-cache`/`pnpm-store-cache` volume names across claude/opencode** (affects: Integrators, End Users) → namespace per template
- **`opencode-cache` volume has no ownership fix** (affects: Operators, End Users) → extend `$pmSetup`'s chown pattern to cover it
- **Step 4 assumes pnpm/corepack that Step 2 never installs** (affects: Developers, End Users) → add `corepack enable && corepack prepare pnpm@latest --activate` to Step 2
- **agent-browser/chromium/node have no opt-out + chromium's apk-repo availability never verified** (affects: Operators) → verify `community` repo availability in base image; consider a toggle

### Monitor
- **Unpinned `go`/`python3` apk versions** (affects: Operators) → revisit if reproducibility complaints surface; document the drift if left as-is
- **JSONC handling left as an execution-time judgment call** (affects: Developers) → resolve to a concrete rule before Step 3 executes, not during
- **Agent-browser's `AGENT_BROWSER_EXECUTABLE_PATH` wiring is asserted as a success criterion but never actually exercised end-to-end** (only `--version` is smoke-tested at build time) (affects: End Users) → add a real browser-launch check to Manual Verification, not just `--version`

---

## Final Assessment

**Soundness:** Fixable
**Risk:** Medium
**Readiness:** Needs Work

**Per-Role Readiness:**
- **Security:** Not Ready — permission-posture gap (Finding 1) is a real leak vector for any pushed image.
- **Operators:** Not Ready — three separate mechanisms in Step 4 (opencode-cache ownership, shared volume names, missing corepack) each independently break state persistence on the default engine/config.
- **Developers:** Ready with Fixes — the plan's structure, rollback plan, and per-step verification discipline are sound; the gaps found here are concrete and independently fixable without a redesign.
- **End Users:** Not Ready — MCP rewrite gaps (Findings 2, 3) mean "prepare.ps1 ran clean" is not reliable evidence that a given local MCP server will actually work in-container.

**Conditions for Approval:**
- [ ] Step 3 handles `permission` config (Security, Operators)
- [ ] Step 3's MCP rewrite covers every `command` array element, not just index 0 (End Users)
- [ ] Step 3's array handling is verified safe under PS 5.1 for single-element arrays (Operators)
- [ ] Step 4's new/reused volumes are either namespaced (pm-cache/pnpm-store-cache) or ownership-safe (opencode-cache) (Integrators, Operators)
- [ ] Step 2 installs/activates corepack+pnpm if Step 4's pnpm-dependent logic is kept (Developers)

**No-Go If:**
- [ ] `build.ps1 -Push` is used to publish images built from an unaudited host `opencode.json` before Finding 1 is fixed (impacts Security)
