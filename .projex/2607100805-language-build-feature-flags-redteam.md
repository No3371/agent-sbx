# Red Team: Build-Time Language Feature Flags

> **Created:** 2026-07-10 | **Lead:** Codex
> **Subject:** 2607100748-language-build-feature-flags-plan.md | **Related:** 2607100748-language-build-feature-flags-plan.md

---

## Bottom Line

**Verdict:** Fix Issues

**Top Vulnerabilities:**
1. Direct Docker callers can supply non-`0|1` values unless Dockerfiles explicitly reject them; pseudocode treats every non-`1` value as disabled.
2. `-Enable`/`-Disable` exclusivity and duplicate behavior lack one unambiguous PowerShell contract.
3. Gated install layers do not prove a disabled runtime is absent from the upstream base image or from dynamic user payload dependencies.

Plan is viable after contract hardening. Keep selectors limited to Claude optional runtimes; shared tools remain unconditional.

---

## Stakeholder Roles

| Role | Cares About | Pain Points | Critical Assumptions |
|---|---|---|---|
| Image user | Exact subset image | Missing or unexpectedly present runtime | Flag result matches image contents |
| Build operator | Repeatable, safe build | Side effects before reject; cache confusion | Invalid invocation stops early |
| Maintainer | Small consistent scripts | Drift across full/slim/scripts | One catalog governs both variants |
| Plugin/skill author | Usable staged payload | Runtime absent after image build | Their payload has no hidden language need |
| Direct Docker user | Same safe contract | PowerShell validation bypassed | Dockerfile rejects invalid args |

---

## Attack Surface (Per Role)

**Image user:** claims: `-Enable` allow-list | `-Disable` deny-list | dependencies: canonical selector resolution, final base-image contents.

**Build operator:** claims: mutual exclusion fails before `prepare.ps1`/engine | dependencies: validation placement and PowerShell bound-parameter semantics.

**Maintainer:** claims: full/slim select same three languages | dependencies: every install, PATH, version check, repo setup, cleanup block is gated consistently.

**Plugin/skill author:** claims: shared tools stay usable | dependencies: copied host skills/plugins do not invoke disabled runtimes.

**Direct Docker user:** claims: only `0`/`1` accepted | dependencies: Dockerfile validation, not `build.ps1`.

---

## Critical Findings

### Finding 1: Dockerfile strictness is asserted, not specified

**Severity:** High | **Likelihood:** High

**Affects Roles:** Direct Docker user | Image user | Maintainer

**Attack Vector:** `docker build --build-arg INSTALL_GO=banana ...`. The proposed `if [ "$INSTALL_GO" = "1" ]` disables Go rather than rejecting the unsupported value.

**Evidence:** Plan lines 162 and 235 require strict direct-caller values, but lines 154-159 specify equality-only gates.

**Blast Radius:** Silent, misconfigured image; no script validation protects direct callers.

**Remediation:** Before any language layer, validate each arg with `case "$INSTALL_*" in 0|1) ;; *) exit 2 ;; esac`; test `banana`, empty, and omitted values for full and slim.

---

### Finding 2: Selector presence and duplicate policy conflict

**Severity:** High | **Likelihood:** Medium

**Affects Roles:** Image user | Build operator | Maintainer

**Attack Vector:** Invoke both parameters with empty/programmatically supplied arrays, mixed case duplicates (`go`, `GO`), or aliases/whitespace. A truthiness check can miss parameter presence; deduplication conflicts with the stated duplicate rejection.

**Evidence:** Plan line 29 says both flags always fail; line 33 says duplicates fail; line 73 says normalize/dedupe canonical names.

**Blast Radius:** Whitelist/blacklist contract varies by caller and future script copy.

**Remediation:** Define: exclusivity uses `$PSBoundParameters.ContainsKey('Enable')`/`ContainsKey('Disable')`; trim then lowercase invariant; reject blanks and any duplicate after normalization. Replace “dedupe” with “normalize then reject duplicates”; tests cover `-Enable go -Disable dotnet`, `go,GO`, whitespace, and empty values.

---

### Finding 3: “Disabled means absent” has no base-image proof

**Severity:** High | **Likelihood:** Medium

**Affects Roles:** Image user | Maintainer | Security

**Attack Vector:** Upstream `docker/sandbox-templates:claude-code` supplies a runtime. Gating this repository’s installation leaves the command available, contradicting `-Enable go` and potentially enlarging attack surface.

**Evidence:** Current full Dockerfile explicitly removes upstream Node before installing its pinned version (lines 31-43); plan line 34 promises disabled commands are absent but only describes gating additions/removing Go PATH entries.

**Blast Radius:** Feature flag reports a smaller image that still contains a selected-off runtime.

**Remediation:** Establish the contract as final-command absence. Build subset images from the pinned base and assert `command -v go|dotnet|python3` fails; if base supplies one, explicitly remove it or document that it cannot be selectable.

---

### Finding 4: Dynamic host payload can require a disabled runtime

**Severity:** Medium | **Likelihood:** Medium

**Affects Roles:** Plugin/skill author | Image user | Support

**Attack Vector:** `prepare.ps1` stages host skills, agents, tools, commands, hooks, and plugins. A copied item can invoke Python, Go, or .NET after a successful subset build.

**Evidence:** Current Claude Dockerfile lines 112-142 copies those payload classes; plan line 79 only assumes shared plugins do not need a disabled runtime. The proposed build matrix exercises three language commands, not arbitrary staged payloads.

**Blast Radius:** Successful build, delayed runtime failure in a user-customized sandbox.

**Remediation:** Document subset images as incompatible with payloads requiring disabled runtimes; during verification, stage a representative payload or add a lightweight declared runtime-requirement check only if users need enforcement.

---

### Finding 5: Microsoft repo setup must follow the .NET gate

**Severity:** Medium | **Likelihood:** High

**Affects Roles:** Image user | Security | Maintainer

**Attack Vector:** Refactor only `dotnet-sdk-${DOTNET_CHANNEL}` out of the apt install list while retaining lines 49-53 of the full Dockerfile. A no-.NET image still downloads, installs, and trusts the Microsoft apt repository.

**Evidence:** Current full Dockerfile installs `packages-microsoft-prod.deb` before the joint Node/.NET/Python apt command; plan says “move optional packages out of shared core lists” without explicitly gating repo registration.

**Blast Radius:** Unneeded network dependency, image layer, and repository trust in `-Disable dotnet` images.

**Remediation:** Put Microsoft repository bootstrap and SDK installation in the same validated .NET conditional; assert repository files/package are absent in no-.NET images.

---

## Role-Based Assumption Challenges

### Build operator: validation before side effects

**Challenge:** Existing scripts call `prepare.ps1` before Dockerfile resolution/build args. A resolver added later preserves the bad ordering.
**Counter-Evidence:** Current `claude/build.ps1` follows the same prepare-before-build pattern as Codex/OpenCode; plan requires early rejection.
**If Wrong:** Invalid selectors mutate staged context before failure.
**Action:** Validate and resolve immediately after parameter binding, before engine lookup and `prepare.ps1`; harness asserts neither runs.

### Maintainer: one catalog stays synchronized

**Challenge:** Three duplicated selector routines and two Dockerfiles can diverge.
**Counter-Evidence:** Plan deliberately avoids a shared module, so no shared executable source guarantees parity.
**If Wrong:** Same flag produces a different full/slim image or an unsupported script result.
**Action:** Keep duplication, but add a table-driven PowerShell harness covering each script and both Claude Dockerfiles’ fixed catalog.

---

## Role-Specific Edge Cases & Failures

### Image user: `-Enable go` with an untagged reused image name

**Trigger:** Build subset image over an existing default tag.
**Role Experience:** Later run uses an image whose contents no longer match the remembered tag.
**Recovery:** Possible.
**Mitigation:** README examples already use distinct tags; state this as required practice for subset images.

### Direct Docker user: no cache masks a gate regression

**Trigger:** Cached full-language layer reused while iterating on conditionals.
**Role Experience:** Runtime appears installed despite changed selector.
**Recovery:** Difficult to diagnose.
**Mitigation:** Build at least one subset verification case with `--no-cache`; inspect final commands, not layer logs.

---

## What's Solid

- Shared tools/core runtimes explicitly remain outside selector scope.
- Fixed generated build args avoid forwarding raw selector values to shell.
- Plan requires invalid selections to stop before `prepare.ps1` and engine execution.
- Full/slim parity and a subset build matrix are correctly included.

## Scale & Stress

**At 10x variants:** repeated manual catalog edits drift across three scripts/two Dockerfiles; harness catches contract drift.

**At 100x variants:** fixed three-language booleans do not scale; defer a manifest only when catalogs grow beyond this bounded set.

---

## Remediation

### Must Fix (Before Proceeding)

- **Strict Docker args** (affects: direct callers) → reject non-`0|1` in both Dockerfiles → negative build tests.
- **Selector contract** (affects: users/operators) → presence-based exclusivity; normalize then reject duplicates → PowerShell harness.
- **Final runtime absence** (affects: users/security) → verify pinned-base contents and remove upstream runtime if present → `command -v` checks.

### Should Fix (Before Production)

- **.NET repo leakage** (affects: security/users) → gate Microsoft repo bootstrap with .NET → package/file assertion.
- **Payload compatibility** (affects: plugin authors/users) → document limitation → representative staged-payload check.

### Monitor

- **Catalog growth** (affects: maintainers) → retain duplicated fixed catalog → introduce one manifest only after another image gains optional languages.

---

## Final Assessment

**Soundness:** Fixable | **Risk:** Medium | **Readiness:** Ready with Fixes

**Per-Role Readiness:**
- **Image user:** Not Ready — disabled-runtime absence unproven.
- **Build operator:** Not Ready — selector semantics need exact presence/duplicate rules.
- **Maintainer:** Ready with Fixes — bounded catalog keeps duplication reasonable.
- **Plugin/skill author:** Ready with Fixes — compatibility boundary needs documentation.
- **Direct Docker user:** Not Ready — direct arg validation must be real.

**Conditions for Approval:**
- [ ] Must-fix items implemented in the plan (for users, operators, direct callers).
- [ ] Full/slim negative matrix proves selected-off runtimes and .NET repo state (for users/security).

**No-Go If:**
- [ ] Both selector parameters can reach `prepare.ps1`/engine, or arbitrary Docker args silently alter selection (impacts users/operators).
