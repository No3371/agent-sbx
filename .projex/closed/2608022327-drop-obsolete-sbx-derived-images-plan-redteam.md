# Red Team: Drop obsolete sbx-derived images plan

> **Lead:** agent (redteam-projex, orchestrated run)
> **Subject:** 2608022321-drop-obsolete-sbx-images-plan.md | **Related:** 2608021410-retire-sbx-legacy-plan.md
> **Walkthrough:** 2608022321-drop-obsolete-sbx-images-walkthrough.md

---

## Bottom Line

**Verdict:** Fix Issues

**Top Vulnerabilities:**
1. **Verification does not bind one prepared input, engine, immutable image, and result set** — build/run defaults can exercise different stores; rebuilds can inherit stale checks; cleanup erases identity (Findings 1–4, 7, 9, 15).
2. **Default verification executes mutable host plugin/config content, then grants the image live workspace/account authority** — compatibility/filename filters are not supplier authorization (Findings 7–8, 13–14).
3. **Runtime parity and containment claims are under-proven** — no executable split between direct/launcher probes, no offline browser launch, no enforced local-only/redacted evidence boundary (Findings 2, 5, 10, 12, 16).

Core cutover design is sound: promote self-built definitions, preserve rm-guard and Codex Playwright, remove obsolete sbx-derived files. Execution is not approval-ready until Step 4, rollback, and evidence gates are revised; these are concrete plan defects, not reasons to retain the obsolete images.

---

## Stakeholder Roles

| Wave | Role | Cares About | Pain Points | Critical Assumptions |
|---|---|---|---|---|
| 1 | Image Maintainer | Safe, reproducible promotion; parity; rollback | Destructive name collision; root/user-sensitive layers | Self-built definitions are complete after named ports |
| 1 | Build/Runtime Operator | Same image built, probed, launched, then cleaned | Engine-local stores; interactive prerequisites; lost diagnostics | Build/run defaults and temporary tags identify one artifact |
| 1 | Container Agent User | Working CLI, browser, mounted workspace, persistence, guard | Green version probes hiding runtime breakage | UID/home/cache/mount contract survives base cutover |
| 2 | Launcher/Auth Maintainer | Preserve interactive contracts; exact-image integration proof | OAuth/device auth; shared state; no machine-readable readiness | Disposable workspace makes launcher smoke disposable |
| 2 | Verification Evidence Owner | Trace source/input → image ID → criterion → cleanup | Ephemeral containers/tags; prose-only evidence | Terminal success remains auditable after cleanup |
| 2 | Host Preparation Steward | Safe, attributable generated build inputs | Ignored host state; destructive/incremental staging; secrets | Committed revision identifies default build input |
| 2 | Browser Toolchain Maintainer | Both baked browser stacks work as `agent` | Independent caches/downloads/libs | Version + cache presence proves offline usability |
| 3 | Secrets/Artifact Security Owner | Prevent credential/config disclosure and unsafe image distribution | Live OAuth; host-derived layers; evidence redaction | Local-only verification contains exposure |
| 3 | Change-Control Approver | Decide whether promotion/rollback evidence is sufficient | Mutable inputs/tags; evidence destroyed by cleanup | Checklist completion proves exact artifact |
| 3 | Compromised Plugin/Config Supplier | Persist or distribute code/config via accepted host build input | n/a — succeeds when filtering trusts allowed paths | Baked host content reaches only trusted local use |

### Wave Derivation

- **Wave 1 → 2:** Finding 1–4 implicated launcher/auth and verification owners through engine handoff, incompatible probes, cleanup, and failure attribution. Finding 4's default preparation side effect implicated the host preparation steward. Findings 5–6's independent browser payloads and layer ordering implicated the browser toolchain maintainer.
- **Wave 2 → 3:** Findings 7–8 surfaced the secrets/artifact security owner through host-derived layers, live credentials, and redaction. Finding 9 surfaced the change-control approver who accepts or rejects evidence. Finding 7 plus the host-input trust boundary surfaced a compromised plugin/config supplier able to weaponize accepted staged content.

## Roles Not Attacked

> Roles that surfaced after wave 3 closed. Recorded, not analyzed.

| Role | Surfaced by | What would have been asked |
|---|---|---|
| Artifact Publisher/Distribution Owner | Finding 15: approval covers source, not a retained release digest | What control proves a later distributed digest is the exact approved digest? |
| Plugin Marketplace/Package Registry Maintainer | Finding 13: supplier identity and lifecycle trust are outside this review | What publisher authentication, immutable digest, attestation, and revocation evidence exists before cached plugin bytes enter a build? |

---

## Attack Surface (Per Role)

### Wave 1 — Direct

**Image Maintainer**
- Claims: promote `Dockerfile.slim` as authoritative; port same-suite rm-guard plus Codex Playwright; delete/rename safely (`2608022321-drop-obsolete-sbx-images-plan.md:126-226`).
- Assumptions: Codex root-layer order is unambiguous; legacy block semantics can be retained while obsolete comparison prose is removed.
- Dependencies: suite build contexts, `.dockerignore`, `rm-guard/`, global npm links, browser cache ownership, `agent`, `tini`.

**Build/Runtime Operator**
- Claims: both driver-default builds and runtime parity can be verified, classified, and cleaned (`2608022321-drop-obsolete-sbx-images-plan.md:280-310`).
- Assumptions: selected build engine reaches `run.ps1`; displayed check tags are unique; launcher can represent no-bind and noninteractive probes.
- Dependencies: PowerShell preparation, one engine store, exact image identity, credentials/device auth, network, disposable workspace, scoped cleanup.

**Container Agent User**
- Claims: suite CLI, agent tooling, Playwright, workspace behavior, rm-guard, and maintained launcher remain usable (`2608022321-drop-obsolete-sbx-images-plan.md:30-36,300-305`).
- Assumptions: version output proves browser usability; CLI startup proves mounted state is writable; auth prompts are image-neutral.
- Dependencies: `agent` UID/home, two browser caches, `/workspace` bind, suite persistence mounts, sudo/`rm.real`, shell hooks.

### Wave 2 — Implicated

**Launcher/Auth Maintainer**
- Claims: existing `-Engine`, `-Image`, and `-Workspace` parameters can prove the maintained launcher path without contract changes.
- Assumptions: interactive prompt means auth/bootstrap completion; fresh workspace avoids real state.
- Dependencies: host OAuth/device auth, TTY, shared volumes, workspace-created `.claude`/`.codegraph`, explicit image identity.

**Verification Evidence Owner**
- Claims: Step 4 results justify every acceptance row and remain reviewable after artifact cleanup.
- Assumptions: tag and terminal output identify immutable content; cleanup does not erase necessary proof.
- Dependencies: source/input manifest, engine/image ID, exact commands/exit codes, criterion mapping, cleanup/rollback ledger.

**Host Preparation Steward**
- Claims: driver-default builds verify the promoted sources from committed-base state.
- Assumptions: ignored generated context is fresh, safe, owned by this run, and reproducible.
- Dependencies: `prepare.ps1`, host `~/.claude`/`~/.codex`, caller-controlled destination, filename filters, `.dockerignore` inclusion.

**Browser Toolchain Maintainer**
- Claims: both independent browser stacks stay baked and usable after promotion.
- Assumptions: connected version/cache checks prove payload resolution without a runtime download.
- Dependencies: exact package pins, cache paths, root-installed shared libraries, ownership transition, offline direct run.

### Wave 3 — Adversarial & Accountable

**Secrets/Artifact Security Owner**
- Claims: local verification does not disclose personalized configuration or expose live authority before trust.
- Assumptions: omitted distribution flags are an enforced boundary; “exact output” is safe evidence; `--rm`/tag cleanup revokes exposure.
- Dependencies: content-sensitive input review, local-only gate, immutable image handoff, credential-owner approval, redacted ledger.

**Change-Control Approver**
- Claims: acceptance rows justify one atomic two-suite go/no-go and rollback is decidable.
- Assumptions: green rows refer to one image generation; rebuilt images inherit earlier passes; filename inventory proves restore equality.
- Dependencies: artifact lineage, pass/blocked/failed/not-run states, downstream invalidation, prestate identity, scoped approval wording.

**Compromised Plugin/Config Supplier**
- Goal/capability: control a plugin/config bundle already accepted into host Claude/Codex state; no repo or registry access initially required.
- First bypass: benign allowed filenames (`package.json`, `settings.json`, `config.toml`, `hooks.json`) and compatibility-valid commands/args.
- Partial gain: build sabotage, staged-data access, runtime command execution, persistence in one local image.
- Full gain: passwordless-sudo image persistence, mounted workspace/live-session access, then replication only through a separate explicit export/load/push.
- Effort asymmetry: one lifecycle or command entry can execute on both default build/runtime paths; local cleanup cannot retract execution, exfiltration, or copied layers.

---

## Critical Findings

### Finding 1: Verification can build in Podman and launch a stale or absent Docker image
**Severity:** High | **Likelihood:** High

**Affects Roles:** Build/Runtime Operator, Image Maintainer, Container Agent User

**Attack Vector:** Step 4 accepts an unspecified `<available-engine>` for each build but does not carry that engine into launcher smoke (`2608022321-drop-obsolete-sbx-images-plan.md:297-305`). Both build drivers default to Podman (`claude/build.ps1:29`; `codex/build.ps1:28`); both launchers default to Docker (`claude/run.ps1:79`; `codex/run.ps1:15`). Engine stores are separate.

**Role-Specific Impact:**
- **Operator:** sees “image not found” or launches a pre-existing Docker tag after a successful Podman build.
- **Maintainer:** valid Dockerfile cutover can be blamed and rolled back for an artifact-handoff failure.
- **Agent User:** apparent successful launcher smoke may exercise old content.

**Blast Radius:** Invalidates both launcher parity evidence and source-defect diagnosis for both suites.

**Remediation:** Define one verification engine variable; pass it to both build and run; inspect the exact fully qualified tag and image ID in that engine before direct probes and launcher smoke.

### Finding 2: Runtime verification combines mutually incompatible probe paths
**Severity:** High | **Likelihood:** High

**Affects Roles:** Build/Runtime Operator, Image Maintainer, Container Agent User

**Attack Vector:** The plan requires a `/workspace/.git` rm-guard fixture with no host workspace bind, binary probes as `agent`, and a `run.ps1` CLI smoke (`2608022321-drop-obsolete-sbx-images-plan.md:300-305`) without prescribing separate commands. Both launchers always bind a host workspace (`claude/run.ps1:208-211`; `codex/run.ps1:66-69`) and hand off to interactive suite flows (`claude/run.ps1:230-232`; `codex/run.ps1:76-88`).

**Role-Specific Impact:**
- **Operator:** cannot execute the no-bind fixture through the maintained launcher without risking a real checkout.
- **Maintainer:** may claim one path proves the other or silently omit a required check.
- **Agent User:** shallow CLI startup can pass while mounted state or browser execution fails.

**Blast Radius:** Runtime acceptance can be green without proving guard isolation, actual image binaries, or maintained launch behavior.

**Remediation:** Specify two command families: direct engine `run --rm --user agent --entrypoint sh` with no volumes for deterministic binary/browser/guard probes; separate `run.ps1 -Engine <same-engine> -Workspace <disposable-dir>` interactive smoke with explicit observables.

### Finding 3: Fixed “temporary” image names make cleanup destructive
**Severity:** Medium | **Likelihood:** High

**Affects Roles:** Build/Runtime Operator

**Attack Vector:** Example names omit an explicit run-unique tag (`2608022321-drop-obsolete-sbx-images-plan.md:297-299`), then cleanup removes temporary tags/artifacts (`:306,353`). Repeated or concurrent verification overwrites and later removes the same local reference.

**Role-Specific Impact:**
- **Operator:** loses or mistakes a prior verification image; concurrent runs can test and clean each other's artifacts.

**Blast Radius:** Local engine store and evidentiary integrity; no remote deletion.

**Remediation:** Generate UTC/run-ID tags, reject pre-existing collisions, record image IDs, and remove only those exact engine-qualified references and containers. Exclude shared launcher volumes.

### Finding 4: Failure classification omits actual build and launch phases
**Severity:** Medium | **Likelihood:** High

**Affects Roles:** Build/Runtime Operator, Image Maintainer, Container Agent User

**Attack Vector:** Plan classifies failure only as source defect or external registry/engine outage (`2608022321-drop-obsolete-sbx-images-plan.md:310`). Default builds first invoke mutable host preparation (`claude/build.ps1:94-100`; `codex/build.ps1:92-98`); Claude launcher needs host credentials (`claude/run.ps1:125-126`), while Codex forces device auth/bootstrap (`codex/run.ps1:76-88`).

**Role-Specific Impact:**
- **Operator:** cannot choose safe retry, source repair, or block action from the prescribed taxonomy.
- **Maintainer:** host staging/auth failures can trigger needless source churn.
- **Agent User:** expected authentication interaction can be misreported as image regression.

**Blast Radius:** Both suites' execution decision and evidence log.

**Remediation:** Classify and retain transcript by phase: prepare | daemon/store | pull/registry | Dockerfile layer | direct image probe | launcher/auth/bootstrap. Record engine/version, exact image ref and ID; source edits only for reproducible source-phase failures.

### Finding 5: Browser and mounted-state parity can pass without being usable
**Severity:** Medium | **Likelihood:** Medium

**Affects Roles:** Container Agent User, Image Maintainer

**Attack Vector:** Step 4 checks `agent-browser --version` and Codex Playwright cache presence (`2608022321-drop-obsolete-sbx-images-plan.md:300-305`). Legacy images contain separate agent-browser Chrome and Playwright Chromium payloads (`claude/Dockerfile:90-103`; `codex/Dockerfile:54-67`). Launcher smoke only asks that CLI starts, not that disposable mounted paths are writable.

**Role-Specific Impact:**
- **Agent User:** browser CLI or suite CLI starts while browser payload ownership/shared libraries, workspace, history, credential, or `.codegraph` writes fail.
- **Maintainer:** declares parity based on executable links and cache directory existence.

**Blast Radius:** Browser automation and real project sessions in either promoted image.

**Remediation:** Directly launch/close each baked browser path as `agent`; assert separate caches exist and are agent-owned. In disposable launcher smoke, assert `/workspace` and expected suite persistence paths are writable without touching real credentials.

### Finding 6: Codex Playwright insertion order is not a single executable sequence
**Severity:** Medium | **Likelihood:** Medium

**Affects Roles:** Image Maintainer

**Attack Vector:** The plan distributes ordering across several bullets (`2608022321-drop-obsolete-sbx-images-plan.md:139-147`). Current Codex slim order is user/home creation → global tools → agent-browser → git config → `USER agent` (`codex/Dockerfile.slim:24-74`). `playwright install --with-deps` must run after its global CLI install and before `USER agent`, then cache ownership must be repaired.

**Role-Specific Impact:**
- **Maintainer:** plausible placement causes unavailable CLI, failed apt install, or root-owned cache.

**Blast Radius:** Codex build or Playwright runtime only.

**Remediation:** State one contiguous root sequence and its checks: version arg → global package/link/chown/version → agent-browser install → Playwright browser/deps + cache chown → git config → rm-guard → `USER agent`.

### Wave 1 strengths

- Self-built definitions are the right source: they explicitly own agent/home, paths, shell hooks, config and `tini`; plan refuses to import unmodeled sbx base extras (`2608022321-drop-obsolete-sbx-images-plan.md:59,85-89`).
- Parity inventory correctly finds rm-guard gaps and Codex Playwright/Chromium gap (`:24-26,95-103`).
- rm-guard is framed and tested as an accident guard, not a security boundary (`:87,142,303`).
- `codex/build.ps1` remains unchanged because its existing `Dockerfile` default becomes correct after promotion (`:75,246`).

### Finding 7: Default builds are not attributable to the committed source revision
**Severity:** High | **Likelihood:** High

**Affects Roles:** Host Preparation Steward, Verification Evidence Owner, Image Maintainer

**Attack Vector:** Step 4 requires maintained default-driver builds (`2608022321-drop-obsolete-sbx-images-plan.md:297-299`). Those drivers run preparation unless `-SkipPrepare` (`claude/build.ps1:94-100`; `codex/build.ps1:92-98`), importing mutable host configuration into ignored but Docker-included context. Claude stages incrementally (`claude/prepare.ps1:53-97`); Codex deletes and recreates its destination (`codex/prepare.ps1:32-37`).

**Role-Specific Impact:**
- **Preparation Steward:** two runs at one revision build different inputs; `-SkipPrepare` can consume stale inputs.
- **Evidence Owner:** cannot reproduce or attribute a pass/failure to the Dockerfile cutover.
- **Maintainer:** host-specific staging defects can prompt source rollback.

**Blast Radius:** Both built images and every downstream runtime claim.

**Remediation:** Define preparation as a first-class phase: newly owned staging path, explicit prepare run, redacted path/hash manifest, prepare-script revision, and matched `-SkipPrepare` reuse only. State that host-derived images prove environment-specific integration, not source-only reproducibility.

### Finding 8: “Disposable” launcher smoke crosses live credential and persistent-state boundaries
**Severity:** High | **Likelihood:** High

**Affects Roles:** Launcher/Auth Maintainer, Verification Evidence Owner, Container Agent User

**Attack Vector:** `-Workspace` changes only the workspace bind. Claude requires and mounts a live host credential read-write (`claude/run.ps1:125-126,208-210`), creates workspace history, and attaches shared caches (`:174-175,205-211`). Codex writes `.codegraph`, uses a shared cache, and requires device auth (`codex/run.ps1:66-88`). `--rm` removes none of that host/named-volume state.

**Role-Specific Impact:**
- **Launcher/Auth Maintainer:** cannot call the smoke unattended or side-effect-free.
- **Evidence Owner:** auth/bootstrap output can leak or be mistaken for image evidence.
- **Agent User:** verification can rotate live tokens or leave durable test state.

**Blast Radius:** Local account credential, disposable workspace, shared volumes; no remote source change.

**Remediation:** Make launcher acceptance explicitly manual; invoke existing `-Engine/-Image/-Workspace` with exact run identity and fresh empty directory. Define per-suite authenticated-prompt milestones, redact auth output, inspect/remove only run-owned workspace state, and acknowledge shared volumes/live Claude credential as accepted prerequisites rather than “disposable.”

### Finding 9: Cleanup can erase the only evidence of a successful verification
**Severity:** Medium | **Likelihood:** High

**Affects Roles:** Verification Evidence Owner, Build/Runtime Operator

**Attack Vector:** Plan removes local tags/artifacts after verification (`2608022321-drop-obsolete-sbx-images-plan.md:306,353-355`); launchers use ephemeral `--rm` containers. It requires exact command/output retention only for an external outage (`:310`), not a successful run.

**Role-Specific Impact:**
- **Evidence Owner:** cannot later link source/context, image ID, command, result, and criterion.
- **Operator:** cleanup success destroys post-hoc diagnostic capability.

**Blast Radius:** Approval and rollback confidence, not product runtime.

**Remediation:** Before cleanup, retain a compact run ledger: source revision, redacted context manifest, engine/version, image ref/ID, each command + exit/result, criterion mapping, then exact cleanup results. Never archive secret payloads.

### Finding 10: “Baked browser” parity is not proven without network
**Severity:** Medium | **Likelihood:** Medium

**Affects Roles:** Browser Toolchain Maintainer, Container Agent User

**Attack Vector:** Connected version/cache checks can pass while first browser use downloads a payload or fails shared-library resolution. The plan claims baked Chromium behavior (`2608022321-drop-obsolete-sbx-images-plan.md:33,304`) but does not disable runtime networking.

**Role-Specific Impact:**
- **Browser Maintainer:** cannot distinguish baked payload use from runtime resolution/download.
- **Agent User:** first offline automation task fails after green parity.

**Blast Radius:** Both browser stacks in both suites.

**Remediation:** In direct no-bind probes, run as `agent` with network disabled and `HOME=/home/agent`; assert both cache roots are agent-owned and each browser opens/closes against local deterministic content. Do not require offline image builds.

### Finding 11: Worktree rollback omits generated-context disposal
**Severity:** Medium | **Likelihood:** High

**Affects Roles:** Host Preparation Steward, Verification Evidence Owner

**Attack Vector:** Fresh worktrees omit ignored contexts by design; default preparation creates/mutates them. Repository rollback restores tracked paths and image artifacts only (`2608022321-drop-obsolete-sbx-images-plan.md:345-355`). Codex can recursively delete a caller-provided destination (`codex/build.ps1:29-30`; `codex/prepare.ps1:32-37`).

**Role-Specific Impact:**
- **Preparation Steward:** stale/partial personal inputs survive interruption or an unsafe destination can be destroyed.
- **Evidence Owner:** repository restoration is confused with full verification-state restoration.

**Blast Radius:** Ignored worktree context and caller-selected destination.

**Remediation:** Preflight ownership and constrain preparation to run-owned suite staging; record creation; dispose only that state on success/rollback. Report repository restoration and generated-context disposal separately.

### Wave 2 strengths

- Launchers already expose `-Engine`, `-Image`, and `-Workspace`; fixes belong in plan invocations, not new test-only launcher APIs.
- Claude cleans its temporary config copy; Codex intentionally uses device auth because container callback networking is unsuitable.
- Exact browser pins, distinct cache roots, `HOME=/home/agent`, and targeted chown establish the correct parity model.
- Plan already limits cleanup to local artifacts and avoids claiming a rebuilt rollback image when none was exercised.

### Finding 12: Personalized verification images have no enforced local-only distribution gate
**Severity:** High | **Likelihood:** Medium

**Affects Roles:** Secrets/Artifact Security Owner, Host Preparation Steward, Build/Runtime Operator

**Attack Vector:** Both Dockerfiles bake host settings/plugins/skills (`claude/Dockerfile.slim:156-169`; `codex/Dockerfile.slim:80-86`). The invoked drivers expose tar, cross-engine load, and push sinks (`claude/build.ps1:1-20,128-138`; `codex/build.ps1:1-20,107-120`), while Step 4 merely omits those flags (`2608022321-drop-obsolete-sbx-images-plan.md:297-306`). Tag cleanup cannot retract tar files, other-engine layers, registry blobs, or shared caches.

**Role-Specific Impact:**
- **Security Owner:** cannot attest confinement; an accidental convenience flag can irreversibly distribute personal config.
- **Preparation Steward:** filename filtering is mistaken for permission to publish.
- **Operator:** believes generic cleanup restores confidentiality.

**Blast Radius:** Builder personalization and any retained inline secret, multiplied by every exported store.

**Remediation:** Make verification explicitly local-only: prohibit `-Tar`, `-Push`, `-Retag`, cross-engine load, registry-qualified refs, and remote cache/export; use trusted single-user engine/run-ID refs. Any distribution event or unknown destination blocks approval; cleanup is not secure erasure.

### Finding 13: Accepted plugin/config content becomes executable during planned verification
**Severity:** High | **Likelihood:** High conditional on compromised accepted content

**Affects Roles:** Compromised Plugin/Config Supplier, Secrets/Artifact Security Owner, Container Agent User

**Attack Vector:** Default builds import host plugin/config state. Filename/path filters retain ordinary plugin manifests and executable config. Both promoted definitions run `npm install` for discovered plugin `package.json` files (`claude/Dockerfile.slim:153-184`; `codex/Dockerfile.slim:77-90`); both grant `agent` passwordless sudo (`claude/Dockerfile.slim:53-55`; `codex/Dockerfile.slim:40-42`). Claude bare/plugin hook and MCP commands plus Codex MCP args are compatibility-filtered, not publisher-authorized (`claude/prepare.ps1:355-555`; `codex/prepare.ps1:192-305`).

**Role-Specific Impact:**
- **Adversary:** a normal lifecycle/command entry yields build or runtime execution; sudo permits root-owned persistence.
- **Security Owner:** filename exclusions appear stronger than their actual confidentiality/compatibility role.
- **Agent User:** poisoned image later receives workspace and authenticated session access.

**Blast Radius:** One builder/image/workspace by default; wider only after explicit reuse/distribution. Surface pre-exists in legacy definitions; this plan triggers it twice, not creates a new remote foothold.

**Remediation:** Verify retirement from a run-owned minimal non-secret context with no third-party hooks/MCP/plugins, then build with matched `-SkipPrepare`. If personalized integration is required, inventory/approve supplier, version, digest, lifecycle scripts, hooks, and MCP commands. Keep broader signing/sandbox redesign out of this scoped retirement.

### Finding 14: Live authentication is granted before the artifact crosses a trust gate
**Severity:** High | **Likelihood:** Medium

**Affects Roles:** Secrets/Artifact Security Owner, Launcher/Auth Maintainer, Container Agent User

**Attack Vector:** After mutable host input enters the image, Claude launcher mounts a live writable OAuth credential (`claude/run.ps1:123-126,202-211`); Codex authorizes inside the image then runs with bypass flags (`codex/run.ps1:78-92`). Build success and a mutable tag do not authorize all baked code to receive account authority.

**Role-Specific Impact:**
- **Security Owner:** first irreversible trust decision occurs without reviewed diff/context/image identity.
- **Launcher Maintainer:** manual prompt milestone alone does not prove the image deserved credentials.
- **Agent User:** bad artifact can copy/mutate a credential or act through the live session.

**Blast Radius:** Claude/Codex account and tools/resources reachable from the session.

**Remediation:** Run all no-auth direct probes first. Gate one final manual launcher smoke on reviewed tracked diff, redacted prepared-input manifest, exact already-probed image ID, no distribution event, and credential-owner approval. Prefer a least-privilege test account; otherwise require explicit risk acceptance or leave the live-auth criterion Blocked.

### Finding 15: Approval rows are not bound to one immutable image generation
**Severity:** High | **Likelihood:** High

**Affects Roles:** Change-Control Approver, Verification Evidence Owner, Image Maintainer

**Attack Vector:** Acceptance rows define method/expectation but no result state, image ID, evidence reference, or same-lineage rule (`2608022321-drop-obsolete-sbx-images-plan.md:331-343`). A late source/context fix repeats builds (`:307-310`) without explicitly invalidating prior runtime/browser/launcher passes.

**Role-Specific Impact:**
- **Approver:** can combine green evidence from different engines, contexts, tags, or generations.
- **Evidence Owner:** cannot defend atomic go/no-go after reruns.
- **Maintainer:** final bytes may inherit checks performed against superseded bytes.

**Blast Radius:** Both-suite cutover and every downstream approval claim.

**Remediation:** Each required row records Pass/Fail/Blocked/Not Run plus source revision, context-manifest ID, engine, image ID, command/result reference. Any source, context, engine, or image-ID change invalidates all downstream results for that lineage. Mixed identity, partial, blocked, failed, or not-run mandatory rows are no-go for this unsplit plan.

### Finding 16: Raw evidence can become a second disclosure channel
**Severity:** Medium | **Likelihood:** High for metadata; Low–Medium for usable auth material

**Affects Roles:** Secrets/Artifact Security Owner, Verification Evidence Owner

**Attack Vector:** Plan asks for exact command/output on outage (`2608022321-drop-obsolete-sbx-images-plan.md:310`). Prepare warnings emit absolute paths/MCP values (`claude/prepare.ps1:113-120,536-549`; `codex/prepare.ps1:389-406`); launcher/auth output shares a terminal with host mount paths and Codex device codes (`claude/run.ps1:230-243`; `codex/run.ps1:83-92`).

**Role-Specific Impact:**
- **Security Owner:** execution log/chat/ticket can preserve paths, topology, account details, or live auth material.
- **Evidence Owner:** “more exact” proof violates the confidentiality boundary.

**Blast Radius:** Every reader/store receiving the evidence; authorization-code impact is time-bounded.

**Remediation:** Retain normalized command shape, relative names/hashes, immutable IDs, phase/exit/result, acceptance mapping, and cleanup—not payloads. Prohibit OAuth URL/code/token/account ID, credential contents/paths, absolute home/workspace paths, MCP secret-bearing args/env/headers, and raw config/plugin payload. Disable recording during live auth.

### Wave 3 strengths

- Step 4 examples already use `local/...` references and no distribution switches; making that boundary normative is small and scoped.
- Preparation filters exclude common credential filenames, VCS metadata, and `node_modules`; useful confidentiality/compatibility controls, though not authorization.
- Claude limits and removes its temporary account-metadata copy; Codex avoids binding host `auth.json`.
- Worktree isolation, local cleanup scope, and refusal to claim unbuilt rollback runtime are sound accountability foundations.



---

## Role-Based Assumption Challenges

### Image Maintainer: destructive swap is self-describing and recoverable
**Challenge:** Step 2 names generic delete/move helpers and a “step checkpoint,” but not the exact invocation or checkpoint identity (`2608022321-drop-obsolete-sbx-images-plan.md:189-190,226,345-355`).
**Counter-Evidence:** The plan does require committed-base execution and worktree isolation (`:7,79,366`), providing a recoverable substrate, but the executor must derive the concrete restore procedure from the execute workflow.
**If Wrong:** interruption after delete leaves canonical names absent until repository history is consulted.
**Action:** Relax — require execution log to record pre-swap revision/hashes and exact helper results; do not redesign the cutover.

### Build/Runtime Operator: “available engine” is one coherent runtime
**Challenge:** build and run defaults select different engines; a name alone does not identify content across stores.
**Counter-Evidence:** `claude/build.ps1:29`, `codex/build.ps1:28`, `claude/run.ps1:79`, `codex/run.ps1:15`.
**If Wrong:** stale-image success or missing-image failure masquerades as parity evidence.
**Action:** Reject.

### Container Agent User: version output proves tool parity
**Challenge:** executable presence does not exercise downloaded browser payload, ownership, shared libraries, mounts, or auth.
**Counter-Evidence:** separate browser install locations in `claude/Dockerfile:90-103` and `codex/Dockerfile:54-67`; launcher mount/bootstrap in `claude/run.ps1:185-232` and `codex/run.ps1:46-88`.
**If Wrong:** green verification precedes first-task failure.
**Action:** Reject.

### Launcher/Auth Maintainer: a fresh workspace makes integration smoke disposable
**Challenge:** live credential mounts, device auth, shared volumes, and generated workspace state remain.
**Counter-Evidence:** `claude/run.ps1:125-126,174-175,205-211`; `codex/run.ps1:66-88`.
**If Wrong:** test mutates durable account/workspace/cache state and remains human-dependent.
**Action:** Reject.

### Verification Evidence Owner: successful terminal output is sufficient proof
**Challenge:** tag mutability, host-derived inputs, `--rm`, and cleanup sever later linkage.
**Counter-Evidence:** `2608022321-drop-obsolete-sbx-images-plan.md:297-310`; `claude/build.ps1:94-119`; `codex/build.ps1:92-110`.
**If Wrong:** approval cannot be reconstructed after cleanup.
**Action:** Reject.

### Host Preparation Steward: committed base determines default build content
**Challenge:** ignored host-derived context is a material Docker COPY input.
**Counter-Evidence:** `.gitignore:2-4`; `claude/Dockerfile.slim:156-166`; `codex/Dockerfile.slim:80-85`.
**If Wrong:** identical commits produce divergent images.
**Action:** Reject.

### Browser Toolchain Maintainer: connected cache/version checks prove baked payloads
**Challenge:** neither forces use of baked binaries or proves runtime libraries offline.
**Counter-Evidence:** `claude/Dockerfile.slim:109-132`; `codex/Dockerfile:17-23,45-64`.
**If Wrong:** runtime download or first offline launch failure remains hidden.
**Action:** Reject.

### Secrets/Artifact Security Owner: local tag cleanup revokes confidentiality exposure
**Challenge:** content-addressed caches, tar/load/push copies, logs, and remote sessions survive tag/container deletion.
**Counter-Evidence:** `claude/build.ps1:128-138`; `codex/build.ps1:107-120`; `2608022321-drop-obsolete-sbx-images-plan.md:306`.
**If Wrong:** distributed layers, copied secrets, or granted authority remain after “cleanup.”
**Action:** Reject.

### Change-Control Approver: green checks can be composed across rebuilds
**Challenge:** acceptance table lacks artifact identity and invalidation semantics.
**Counter-Evidence:** `2608022321-drop-obsolete-sbx-images-plan.md:307-310,331-343`.
**If Wrong:** final bytes are approved with stale evidence.
**Action:** Reject.

### Compromised Plugin/Config Supplier: filename/path filters establish trust
**Challenge:** ordinary allowed manifests and commands reach build/runtime execution sinks.
**Counter-Evidence:** `claude/prepare.ps1:355-555`; `codex/prepare.ps1:192-305`; plugin npm loops in both self-built Dockerfiles.
**If Wrong:** low-effort accepted content gains execution and sudo-backed persistence.
**Action:** Reject.

---

## Role-Specific Edge Cases & Failures

### Build/Runtime Operator: Podman build, Docker launch
**Trigger:** use both script defaults.
**Role Experience:** fresh image builds, then launcher cannot find it or finds an older Docker copy.
**Recovery:** Possible
**Mitigation:** one explicit engine/tag/image-ID handoff.

### Build/Runtime Operator: repeated fixed-tag cleanup
**Trigger:** rerun or concurrent execution using displayed check names.
**Role Experience:** prior artifact is overwritten or removed; evidence no longer maps to a unique image.
**Recovery:** Difficult
**Mitigation:** collision-checked run-ID tags and exact cleanup ledger.

### Container Agent User: auth/bootstrap blocks launcher smoke
**Trigger:** missing/expired Claude credential or Codex device-auth/network prerequisite.
**Role Experience:** verification never reaches suite CLI despite a sound image.
**Recovery:** Possible
**Mitigation:** declare prerequisites and `auth/bootstrap/environment` failure class.

### Container Agent User: browser cache exists but cannot launch
**Trigger:** wrong ownership, missing shared lib, or distinct agent-browser payload absent.
**Role Experience:** version check passes; first automation task fails.
**Recovery:** Difficult
**Mitigation:** non-network launch/close smoke for both browser stacks.

### Launcher/Auth Maintainer: expired token or unfinished device auth
**Trigger:** valid image, invalid Claude host credential, or incomplete Codex device flow.
**Role Experience:** no defined “CLI ready” milestone; failure is attributed to image.
**Recovery:** Possible
**Mitigation:** manual role-owned milestones and phase result.

### Host Preparation Steward: stale `-SkipPrepare` context
**Trigger:** generated context exists from another host/run with no matching manifest.
**Role Experience:** build succeeds with unknown personal configuration.
**Recovery:** Difficult
**Mitigation:** manifest match or fresh run-owned preparation.

### Verification Evidence Owner: cleanup before identity capture
**Trigger:** tag/container removed after prose checklist completion.
**Role Experience:** later review cannot prove which bytes passed.
**Recovery:** Impossible
**Mitigation:** durable redacted ledger before cleanup.

### Browser Toolchain Maintainer: browser launch with network disabled
**Trigger:** baked payload missing/unreadable or runtime library absent.
**Role Experience:** connected version check was green; offline process fails.
**Recovery:** Difficult
**Mitigation:** local-target offline launch/close as `agent`.

### Secrets/Artifact Security Owner: operator follows a prepare banner or adds `-Push`
**Trigger:** personalized context is built with any distribution sink.
**Role Experience:** local cleanup succeeds but confidentiality cannot be restored.
**Recovery:** Impossible
**Mitigation:** enforced local-only gate; stop and block on any export.

### Change-Control Approver: late rebuild after earlier green probes
**Trigger:** source/context fix changes image ID.
**Role Experience:** checklist retains passes from superseded bytes.
**Recovery:** Difficult
**Mitigation:** lineage-wide downstream invalidation and full rerun.

### Compromised Plugin/Config Supplier: benign `package.json` lifecycle
**Trigger:** accepted plugin cache is staged by default build.
**Role Experience:** adversary code executes during verification; non-root boundary falls to passwordless sudo.
**Recovery:** Difficult
**Mitigation:** minimal context or approved supplier/digest/lifecycle inventory.

### Secrets/Artifact Security Owner: recorded device authorization
**Trigger:** screenshot/raw transcript captures Codex auth ceremony.
**Role Experience:** evidence store receives live code/account metadata.
**Recovery:** Difficult
**Mitigation:** recording off during auth; sanitized milestone only.

---

## What's Hidden (Per Role)

**Omissions per role:**
- **Image Maintainer:** exact Codex root-layer sequence and concrete checkpoint record.
- **Build/Runtime Operator:** engine/tag handoff; launcher prerequisites; phase diagnostics; prepare side effects; cleanup ledger.
- **Container Agent User:** actual browser launch and mounted-state write observables.
- **Launcher/Auth Maintainer:** authenticated prompt success markers; accepted live-credential/shared-volume side effects.
- **Verification Evidence Owner:** pre-cleanup run ledger and criterion-to-command mapping.
- **Host Preparation Steward:** input provenance, destination ownership, content-sensitive confidentiality boundary, disposal.
- **Browser Toolchain Maintainer:** network-isolated runtime use of both baked payloads.
- **Secrets/Artifact Security Owner:** explicit local-only prohibition; credential trust gate; evidence forbidden-field list.
- **Change-Control Approver:** same-lineage results, invalidation rules, exact prestate equality, source-only approval boundary.
- **Compromised Plugin/Config Supplier:** supplier identity/lifecycle authorization is absent; compatibility filters are not trust controls.

**Tradeoffs per role:**
- **Image Maintainer:** simpler self-built bases intentionally lose Docker CLI, Java, man-db, development bundle, and clipboard bridge (`2608022321-drop-obsolete-sbx-images-plan.md:115`); plan states this honestly but proves only maintained declared tools.
- **Build/Runtime Operator:** driver-default build includes mutable prepare staging; reproducibility requires recording or freezing that input.
- **Container Agent User:** two browsers preserve parity but increase image size, build time, cache ownership surface, and failure modes (`:116`).
- **Launcher/Auth Maintainer:** preserving launcher contract makes smoke manual integration evidence, not deterministic CI evidence.
- **Verification Evidence Owner:** useful context provenance must avoid copying personal configuration into the report.
- **Host Preparation Steward:** default convenience trades hermeticity for personalized baked images; local cleanup cannot retract a pushed/exported layer.
- **Browser Toolchain Maintainer:** separate pinned browsers preserve declared parity at cost of size and duplicate failure surfaces.
- **Secrets/Artifact Security Owner:** verification convenience trades personalized image utility against confidentiality and live-account exposure.
- **Change-Control Approver:** cleaning temporary images means approval can cover source cutover only unless exact verified digest is retained.
- **Compromised Plugin/Config Supplier:** local-only limits propagation, not build execution, exfiltration, or authenticated runtime damage.

---

## Scale & Stress (Role Impact)

**At 10x:**
- **Image Maintainer:** source drift makes scattered layer-order prose easier to misapply.
- **Build/Runtime Operator:** retries collide on fixed image names; preparation and browser downloads amplify churn.
- **Container Agent User:** multiple projects amplify named-volume and mounted-path ownership defects.
- **Launcher/Auth Maintainer:** repeated smoke accumulates generated directories/cache state and human auth work.
- **Verification Evidence Owner:** ten runs without manifests/IDs are incomparable after cleanup.
- **Host Preparation Steward:** parallel worktrees stage different host state under one revision.
- **Browser Toolchain Maintainer:** a latent runtime-download dependency multiplies first-task outages.
- **Secrets/Artifact Security Owner:** repeated runs multiply retained logs/caches and opportunities for an accidental export.
- **Change-Control Approver:** reruns create mixed-lineage evidence unless invalidated automatically.
- **Compromised Plugin/Config Supplier:** one accepted bundle poisons every personalized rebuild on that host.

**At 100x:**
- **Image Maintainer:** unrecorded source/checkpoint identity undermines repeatable rollback across executions.
- **Build/Runtime Operator:** concurrent engine stores and shared tags make evidence attribution impossible.
- **Container Agent User:** fleet/unattended smoke cannot satisfy forced interactive authentication without a separate direct-probe contract.
- **Launcher/Auth Maintainer:** unattended fleet verification is incompatible with current auth flows.
- **Verification Evidence Owner:** distributed operators need structured provenance, not mutable tags and prose.
- **Host Preparation Steward:** host config becomes a supply-chain input; filename-only secret filters are inadequate for distribution.
- **Browser Toolchain Maintainer:** missing offline baseline becomes systematic browser outage.
- **Secrets/Artifact Security Owner:** one convenience push can turn personal contexts into a replicated supply-chain artifact.
- **Change-Control Approver:** approval without immutable lineage cannot survive distributed execution.
- **Compromised Plugin/Config Supplier:** supplier payload scales only when images/config are reused, but effort remains one small manifest/command entry.

---

## Cross-Wave Cascade Pass

### Cascade A: Accepted host payload → build execution → authenticated workspace

1. **Host Preparation Steward (W2)** accepts mutable plugin/config state under compatibility/filename filters (Finding 7).
2. **Compromised Supplier (W3)** uses allowed `package.json`, hook, or MCP command; default **Operator (W1)** build executes or bakes it (Finding 13).
3. Passwordless sudo permits image persistence; direct CLI/version checks can remain green.
4. **Launcher/Auth Maintainer (W2)** supplies live Claude OAuth or fresh Codex authorization and mounted workspace (Findings 8, 14).
5. **Agent User (W1)** exposes source/session to poisoned bytes; **Security Owner (W3)** cannot revoke copied authority with `--rm`.
6. **Approver (W3)** can accept the artifact if results lack same-lineage/input identity (Finding 15).

**Worst Case:** personal source plus Claude/Codex authority compromised; later explicit export multiplies affected consumers.
**Recovery Cost:** credential revocation, workspace review, image/cache inventory, context rebuild; cleanup cannot retract exfiltration.
**Break Point:** run-owned minimal non-secret context for deterministic verification; attested personalized inputs only after direct probes; immutable image-ID and credential trust gate before launcher smoke.

### Cascade B: Engine split → stale success → wrong artifact approved

1. **Operator (W1)** builds in default Podman but runs default Docker (Finding 1).
2. Fixed/shared tag resolves to absent or older Docker image (Finding 3).
3. Launcher smoke or earlier probes appear green against different bytes; cleanup removes identity evidence (Findings 2, 9).
4. **Evidence Owner (W2)** cannot reconstruct lineage; **Approver (W3)** composes green rows across generations (Finding 15).
5. **Maintainer (W1)** may roll back valid sources or merge untested final bytes.

**Worst Case:** Ready/Complete claimed while promoted image generation never received required runtime checks.
**Recovery Cost:** rebuild and rerun every criterion; prior evidence discarded.
**Break Point:** one engine/run-ID/image-ID ledger; all invocations explicit; any lineage change invalidates downstream checks.

### Cascade C: Shallow browser proof → later offline failure

1. **Browser Maintainer (W2)** sees pinned CLI and populated cache; **Maintainer (W1)** considers parity preserved.
2. No offline process launch exercises payload, ownership, or shared libraries (Findings 5, 10).
3. **Agent User (W1)** reaches first real/offline automation after source approval and fails.
4. Cleaned image/evidence obscures whether payload, dependency, or cache path caused failure.

**Worst Case:** both canonical images ship browser automation unusable in the environment baked payloads were meant to support.
**Recovery Cost:** recreate exact image/context, diagnose two independent browser stacks, rebuild/reverify.
**Break Point:** network-disabled local-target launch/close of both stacks as `agent`, tied to final image ID.

### Cascade D: Non-source failure → source churn → stale approval/rollback

1. Preparation, daemon, registry, auth, or bootstrap fails but taxonomy offers source defect vs external outage only (Finding 4).
2. **Maintainer (W1)** changes source or rebuilds; earlier checks remain checked.
3. **Approver (W3)** sees mixed-generation passes; late failure may trigger file-by-file rollback with no exact prestate proof.
4. Ignored generated context survives tracked rollback (Finding 11); failure can recur under restored filenames.

**Worst Case:** partial cutover or rollback declared complete while tracked bytes, ignored inputs, or operational images differ from claimed state.
**Recovery Cost:** compare exact base tree, dispose run-owned context, rebuild if operational restoration is claimed.
**Break Point:** phase taxonomy + prestate/tree identity + lineage invalidation + separate source-restoration and runtime-restoration outcomes.

### Cross-Wave Five Whys

Why can a sound file promotion produce unsafe approval? Verification is treated as a list, not an artifact lineage. Why is lineage unstable? Engines, tags, host-prepared context, rebuilds, and auth state vary independently. Why can dangerous input survive? Preparation controls compatibility and obvious credential filenames, not supplier authorization. Why does cleanup not solve it? Execution, remote authority, copied layers, and evidence have independent lifetimes. Why revise the plan? Implementation intent is sound, but its verification/approval transaction does not bind input, bytes, authority, result, and cleanup.

### Cross-Wave Inversion

Do not begin with personalized default builds and treat launch success as proof. First verify static cutover and deterministic image contract from run-owned minimal inputs; then test exact image IDs directly with no bind/auth/network where applicable; finally perform one explicit, credential-gated, same-image launcher integration per suite. Personalization, live authority, and distribution are opt-in trust decisions—not default evidence sources.

---

## Remediation

### Must Fix (Before Proceeding)

- **Artifact lineage and invalidation** (affects: all non-adversarial roles) → one engine + collision-free run-ID refs + recorded image IDs; explicit `-Engine/-Image/-Workspace`; criterion results tied to lineage; any input/image change invalidates downstream checks.
- **Executable verification split** (affects: Operator, Maintainer, Agent User, Browser Maintainer) → exact direct no-bind commands for binary/rm-guard/browser checks; separate manual launcher smoke with per-suite ready milestones and disposable workspace.
- **Controlled preparation** (affects: Preparation Steward, Security Owner, Approver) → run-owned minimal non-secret context for retirement proof, or redacted manifest plus approved supplier/version/digest/lifecycle/MCP/hook inventory; matched `-SkipPrepare`; owned-context cleanup.
- **Credential trust boundary** (affects: Security Owner, Launcher/Auth Maintainer, Agent User) → no-auth probes first; reviewed diff/context/exact image ID; no distribution; credential-owner approval; least-privilege test account or explicit risk acceptance before live smoke.
- **Local-only gate** (affects: Security Owner, Operator) → prohibit tar/push/retag/cross-engine load/registry refs/remote export; any breach or unknown destination = Blocked/no-go, not “cleaned.”
- **Safe evidence** (affects: Evidence Owner, Security Owner, Approver) → sanitized run ledger before cleanup; no raw config/auth transcript; Pass/Fail/Blocked/Not Run per criterion; exact cleanup results.
- **Rollback identity** (affects: Maintainer, Preparation Steward, Approver) → record base tree/path identities; prove scoped source equality; dispose run-owned ignored context; label operational restoration untested unless rebuilt.

### Should Fix (Before Execution Completion)

- **Codex root-layer sequence** (affects: Maintainer, Browser Maintainer) → consolidate exact Playwright/rm-guard order from Finding 6.
- **Browser proof** (affects: Browser Maintainer, Agent User) → network-disabled launch/close for both caches/stacks plus ownership assertions.
- **Mounted-state proof** (affects: Agent User, Launcher Maintainer) → disposable workspace write checks for `/workspace` and suite-owned state without logging secrets.
- **Failure taxonomy** (affects: Operator, Evidence Owner) → bootstrap/context ownership | prepare | engine/store | registry/pull | Dockerfile | direct probe | launcher/auth; retry/source-edit rule per phase.
- **Approval scope** (affects: Approver) → state decision approves source cutover only; future/distributed images are not approved unless exact verified digest is retained and published.

### Monitor

- **Intentional legacy-extra loss** (affects: Agent User, Support-equivalent maintainers) → revisit only on a concrete missing maintained capability; do not re-import the sbx base bundle.
- **Browser pin/cache drift** (affects: Browser Maintainer) → compare package, installer, cache, ownership matrix when pins or paths change.
- **Plugin supply-chain governance** (affects: Security Owner, un-attacked marketplace maintainer) → broader signing/revocation/build sandbox is follow-up scope; minimal/attested input gate is sufficient for this retirement.
- **Shared launcher volumes/auth concurrency** (affects: Launcher Maintainer, Agent User) → revisit after observed state collision; record current accepted side effects.

---

## Final Assessment

**Soundness:** Serious Issues
**Risk:** High
**Readiness:** Needs Work

**Per-Role Readiness:**
- **Image Maintainer:** Not Ready — parity edits are actionable, but verification sequence/rollback identity need revision.
- **Build/Runtime Operator:** Not Ready — engine/tag/probe/cleanup contract is unsafe and ambiguous.
- **Container Agent User:** Not Ready — browser, mounted state, and live-auth trust remain under-proven.
- **Launcher/Auth Maintainer:** Not Ready — success milestones and accepted persistent effects are unspecified.
- **Verification Evidence Owner:** Not Ready — no immutable criterion lineage or safe retention contract.
- **Host Preparation Steward:** Not Ready — generated context provenance/ownership/disposal absent.
- **Browser Toolchain Maintainer:** Not Ready — baked payload use is not proven offline.
- **Secrets/Artifact Security Owner:** Not Ready — local-only, credential, and redaction gates absent.
- **Change-Control Approver:** Not Ready — mixed-generation evidence and rollback fidelity permit false approval.
- **Compromised Plugin/Config Supplier:** Succeeds cheaply if compromised content is already accepted; propagation remains local unless explicitly distributed.

**Conditions for Approval:**
- [ ] One explicit engine/run-ID/image-ID lineage covers every required result for both suites.
- [ ] Deterministic direct probes and manual launcher integration are separate, exact, and criterion-indexed.
- [ ] Verification inputs are minimal or attested; no unreviewed plugin lifecycle/hook/MCP content executes.
- [ ] Live authentication follows immutable-image review and credential-owner approval.
- [ ] No image/context/evidence distribution occurred; sanitized ledger exists before scoped cleanup.
- [ ] Rebuild invalidates and reruns every downstream check for that artifact.
- [ ] Rollback source equality and generated-context disposal are decidable and separately recorded.

**No-Go If:**
- [ ] Any mandatory row is Failed, Partial, Blocked, Not Run, mixed-lineage, or lacks image identity.
- [ ] Build/run engine or exact image reference differs anywhere in one suite lineage.
- [ ] Context provenance/ownership is unknown or `-SkipPrepare` lacks a matching manifest.
- [ ] Any tar/push/load/registry/remote export occurred or destination inventory is incomplete.
- [ ] Live credential is exposed before input/image trust gate or auth output is recorded.
- [ ] Final image changes after a downstream check without full invalidation/rerun.

### Workflow Validation

- [x] Exactly three sequential waves: Direct → Implicated → Adversarial & Accountable; no fourth wave opened.
- [x] Wave 2 roles trace to recorded wave-1 Findings 1–6; wave 3 roles trace to recorded wave-2 Findings 7–9.
- [x] Each prior wave's findings were written and re-read before deriving the next.
- [x] Each role has independent attack surface, assumptions, edges/failures, scale, five-whys/cascade/inversion coverage, strengths, and remediation.
- [x] Post-wave-3 cross-wave cascade pass completed.
- [x] Later roles recorded under Roles Not Attacked only.
- [x] Findings cite concrete plan/product evidence and role-grounded severity/likelihood.
- [x] Bottom Line synthesis is the final content change after all findings and validation.
