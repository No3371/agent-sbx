# Red Team: Coding-Agent Sandbox Suite Contract

> **Status:** Draft
> **Lead:** RedTeamSuiteContract
> **Subject:** 2608030706-coding-agent-sandbox-suite-contract-def.md
> **Related:** 2608030706-coding-agent-sandbox-suite-contract-def.md

---

## Bottom Line

**Subject inference:** Validated — `2608030706-coding-agent-sandbox-suite-contract-def.md` is the root-scoped Draft defining shared suite architecture/behavior/setup, including the revised Docker build/run default. No competing immediate contract artifact found in the target scope.

**Verdict:** Redesign

**Another workflow warranted:** Yes — run `/define-projex.md` against the subject to redesign the contract and its conformance/security profiles, then re-run red team after revision. Neither workflow was invoked here.

The observed-vs-future split and explicit non-isolation caveat are sound. The document is not approvable as a suite contract: it permits known-secret artifacts and root-equivalent credentialed runtimes through disclosure, has no ratified conformance/provenance authority, and leaves durable state, combined selectors/mounts, abnormal exits, artifact transforms, and Docker cutover without enforceable identity or recovery gates.

**Top Vulnerabilities:**
1. **No enforceable no-secret boundary:** OMP can bake credential/conversation stores, publish them, and print separately forwarded secret values during a normal launch.
2. **No safe runtime profile:** writable host project + root/passwordless sudo + approval bypass + credential channels makes repository/dependency input a high-asymmetry path to host damage and provider authority.
3. **No normative conformance or immutable provenance:** a Draft future-suite rule set with no harness/receipt cannot prove Docker cutover, artifact identity, combined acceptance, recall, or known-good recovery.

---

## Wave 1 — Direct Roles (Working Record)

_Roles derived directly from subject; findings appended before wave 2 begins._

### Coding-Agent User

**Cares:** host-workspace integrity | predictable auth/history | Linux-correct deps | clean interruption | truthful “sandbox” boundary.

**Attack surface:** writable `<host>:/workspace` bind; privileged/approval-bypassing agent; mounted/forwarded/baked credentials; persistent history and package volumes; non-blocking tool bootstrap. Contract promises `/workspace`, `-it --rm`, terminal agent, narrow `rm-guard`, and variation disclosure (`2608030706-coding-agent-sandbox-suite-contract-def.md:69,150-167,190-198`).

**W1-U1 — Writable privileged agent lacks an actionable integrity boundary. Critical / High.** Codex always runs `--dangerously-bypass-approvals-and-sandbox` against the writable bind (`codex/run.ps1:66-88`) and has passwordless sudo (`codex/Dockerfile:41-44`); OMP runs as root (`omp/README.md:25-27`). `rm-guard` retains `/usr/bin/rm.real` and passes unprotected operands (`codex/Dockerfile:91-96`; `codex/rm-guard/rm-guard.sh:85-107`). Definition honestly denies hostile isolation, but requires only disclosure—not safe/destructive modes, protected-write scope, or launch acknowledgement (`2608030706-coding-agent-sandbox-suite-contract-def.md:33-36,150-151,165`). Result: trivial source destruction or secret access survives container removal.

**W1-U2 — “Ephemeral” can be misread as rollback. High / Medium.** Every launcher bind-mounts the project writable and uses `--rm` (`codex/run.ps1:66-72`; `claude/run.ps1:208-220`; `opencode/run.ps1:132-145`; `omp/run.ps1:111-137`). Lifecycle says Running → Built but has no cancellation, partial-write, rollback, or forensic contract (`2608030706-coding-agent-sandbox-suite-contract-def.md:203-213`). OpenCode documents hard-kill loss of the latest uncheckpointed turn (`opencode/README.md:102-108`), proving container exit and durable-state recovery differ.

**W1-U3 — Disclosure substitutes for credential least privilege. High / Medium.** Claude mounts OAuth read-write (`claude/run.ps1:208-216`); OpenCode mounts host auth/state (`opencode/run.ps1:132-145`); OMP forwards provider secrets and bakes credential/history DBs (`omp/run.ps1:75-126`; `omp/README.md:142-167,245-264`). R5 requires disclosure but no read-only default, scope ceiling, or launch-time secret inventory (`2608030706-coding-agent-sandbox-suite-contract-def.md:155-167`).

**W1-U4 — Package mask is persistent, partial, and non-reproducible. Medium / Medium.** Only top-level host `node_modules` triggers masking; install uses mutable `pnpm/yarn/npm install`; Codex and Claude share `nmvol-<48-bit-path-hash>` and `pm-cache` names (`codex/run.ps1:46-72`; `claude/run.ps1:189-224`). R4 requires documentation, not frozen installs, ABI namespacing, cleanup, provenance, or nested-module protection (`2608030706-coding-agent-sandbox-suite-contract-def.md:153`).

**Challenges:** Five Whys for W1-U1: host can be destroyed → bind is writable → agent has arbitrary privileged tools → guard mediates one command/path class → contract intentionally denies isolation → “sandbox” has no operational safety mode. Cascade: launch → privileged agent/package bootstrap → destructive command, secret read, or interruption → host edits and hidden volume state persist while runtime disappears → worst case project loss + credential exfiltration; recovery depends on external VCS/backups and credential revocation, neither contractual. Inversion: treat project or image as hostile; mounted project, credentials, env, volumes, network, and retained real binaries become attack assets. **Solid:** explicit non-isolation and observed/required split prevent a false security claim; guard’s narrow direct/ancestor tests are credible accident protection (`2608030706-coding-agent-sandbox-suite-contract-def.md:33-36,79-82,217-223`).

### Suite Operator

**Cares:** current prepared context | engine-local image identity | safe distribution | deterministic selectors | observable partial failure | reproducible rebuild.

**Attack surface:** host state → `prepare.ps1` → `context/` → Dockerfile COPY → engine image → optional tar/retag/load/push → launcher; depends on PowerShell/robocopy, engines, registries, remote sources, path canonicalization, archive helper.

**W1-O1 — Known-secret image remains one flag from publication. Critical / High.** OMP stages credential-bearing DB/WAL and whole trees into layers, while its normal build example includes `-Push` (`omp/README.md:39-44,142-167,245-264`; `omp/Dockerfile:128-129`). `omp/build.ps1:13-31,92-95,120-123` performs no classification or block. R3/R5 require explicit action and disclosure only, so this remains conformant (`2608030706-coding-agent-sandbox-suite-contract-def.md:140,157-167,198`).

**W1-O2 — Missing OMP source preserves stale sensitive context. High / Medium.** R2 requires stale deletion (`2608030706-coding-agent-sandbox-suite-contract-def.md:124-131`), but OMP mirrors only when source exists and otherwise retains destination content (`omp/prepare.ps1:74-101`), later copied by `omp/Dockerfile:128-129`. Codex removes absent-source destination (`codex/prepare.ps1:102-107`), proving a viable stricter pattern.

**W1-O3 — Docker-default cutover has no adoption gate. High / High.** R3 mandates Docker build/run defaults (`2608030706-coding-agent-sandbox-suite-contract-def.md:137-139`); current builds default Podman while launchers default Docker (`codex/build.ps1:26`; `claude/build.ps1:28`; `omp/build.ps1:26`; corresponding `run.ps1` parameter defaults). No conformance harness exists (`2608030706-coding-agent-sandbox-suite-contract-def.md:239`), so a “successful default build” can leave default run with no image.

**W1-O4 — Cross-suite volumes collide by construction. High / Medium.** Codex and Claude use identical unprefixed path-hash `node_modules` names and global `pm-cache` (`codex/run.ps1:52-72`; `claude/run.ps1:198-226`); OMP’s prefixed names demonstrate feasible isolation (`omp/README.md:183-191`). R5 asks only to define collision semantics (`2608030706-coding-agent-sandbox-suite-contract-def.md:161-162`).

**W1-O5 — Retag/export can report false semantic success without provenance. High / Medium.** `retag-tar.ps1` performs global text substitution without source-tag occurrence/count, archive semantics, digest, or load verification; no match still prints completion (`codex/retag-tar.ps1:44-63`). Build flows retain earlier side effects on later failure (`codex/build.ps1:89-143`; `omp/build.ps1:105-159`). R3 says reject unsafe helper input but defines no semantic postcondition (`2608030706-coding-agent-sandbox-suite-contract-def.md:140-142`).

**W1-O6 — Floating supply chain defeats reproducibility. High / High.** OMP defaults empty upstream pin, remote GitHub context, `nvm install 26`, and `pnpm@latest` (`omp/build.ps1:29-31,103-105`; `omp/Dockerfile:20-37,74-83`). Pinning remains an Open Question (`2608030706-coding-agent-sandbox-suite-contract-def.md:233`) while reproducibility caveats are merely documentary.

**Challenges:** Five Whys for W1-O3: default run misses image → build used other engine → scripts retain split defaults → new MUST is declarative → no adoption/conformance gate → raw engine failure becomes operator diagnosis. Cascade for W1-O2/O1: prepare once → source disappears/switches → stale credential tree survives → image build succeeds → documented push uploads retained credentials → registry retention outlives tag deletion. Inversion for W1-O6: require rebuild of identical bytes; floating ref/package/base streams cannot reproduce and dependency outage blocks build. **Solid:** selector validation precedes preparation; distribution is opt-in; OMP warns about secrets/root/path limits. These reduce accidents but do not prove safe output (`omp/build.ps1:33-95`; `omp/README.md:142-167,257-278`).

### Suite Maintainer / Integrator

**Cares:** determinate APIs | reviewable conformance | safe multi-agent separation | upgrade/rollback provenance | bounded platform burden.

**Attack surface:** R1–R5 normative wording, combined-suite selector/config branches, current suite divergences, lifecycle and future conformance authority.

**W1-M1 — Multi-agent selector model is undefined. High / High.** R1 requires an explicit launch selector while R3 reserves `-Enable/-Disable` for build features and R5 asks for an exact selector catalog (`2608030706-coding-agent-sandbox-suite-contract-def.md:120,139,164-165`). Combined plan uses runtime-only `-Agent`, stages and validates both host trees, and applies Claude’s feature set image-wide (`2608030408-c-c-combined-suite-plan.md:57-70,91-94,207,246-247,283-285`). Phase, namespace, defaults, partial configuration, and build granularity remain indeterminate.

**W1-M2 — “Common shape” freezes unresolved current intersection. High / Medium.** Definition permits suite-owned engine/base/package/pin variation yet mandates Docker default plus Node/npm, CodeGraph, agent-browser, Playwright, and browser, while asking whether tool/host support is permanent (`2608030706-coding-agent-sandbox-suite-contract-def.md:33-36,137-153,197,233-235`). Minimal/non-Node agents inherit needless supply-chain and patch burden.

**W1-M3 — “Mount only selected project” conflicts with auth/state mounts. High / High.** R4’s literal only-mount statement (`2608030706-coding-agent-sandbox-suite-contract-def.md:151`) conflicts with R5’s runtime-mount disclosure and observed Claude/OpenCode auth/history mounts (`:159-162`; `claude/run.ps1:208-218`; `opencode/run.ps1:132-143`). Conformance becomes reviewer interpretation, weakening least privilege.

**W1-M4 — Lifecycle omits provenance and freshness identity. High / Medium.** Prepared/Built/Running states carry no context manifest, source revision, engine, digest, agent/profile set, or run binding (`2608030706-coding-agent-sandbox-suite-contract-def.md:203-213`). Mutable tags cannot distinguish old credentials/config from current prepared state; the combined plan’s immutable-ID probes remain local, not contractual (`2608030408-c-c-combined-suite-plan.md:311-365`).

**W1-M5 — Security/conformance are self-attested disclosure duties. High / Medium.** Filename-pattern filtering explicitly cannot prove no secrets; known secrets remain allowed with distribution warnings; the minimum acceptance gate is unresolved (`2608030706-coding-agent-sandbox-suite-contract-def.md:88-92,127-131,198,239`). A renamed token or SQLite/WAL store passes normative review.

**Challenges:** Five Whys for W1-M1: implementation diverges → “selector” is overloaded → R1 defines launch identity while R3 defines features → combined plan makes features image-wide → no authority defines phase/domain. Cascade: dual-tree preparation → unrelated source absent/stale → `-SkipPrepare` or retained context → mutable tag hides provenance → wrong/sensitive tree ships → combined acceptance cannot support source retirement. Inversion: choose either independently buildable agent profiles or an explicitly inseparable dual-agent product; current contract specifies neither. **Solid:** present-vs-future membership is explicit; silent selector/portability fallbacks are forbidden; non-isolation is honest (`2608030706-coding-agent-sandbox-suite-contract-def.md:12-19,193-199`).

### Wave 1 Findings Closed

Wave 1 completed before role derivation. Cross-role intersections: secret-bearing state + writable privilege; disclosure without enforcement; mutable/stale preparation without provenance; engine/tool defaults without migration; volume identity without isolation; ambiguous combined-suite selector/mount semantics.

## Wave 2 — Implicated Roles (Working Record)

Derived only after re-reading closed wave 1:
- **Credential & Security Steward** ← W1-U1/U3, W1-O1/O6, W1-M3/M5: privileged execution, secret exposure/distribution, mutable supply chain, ambiguous mount control, disclosure-only gate.
- **Release / Conformance & Artifact Custodian** ← W1-O1/O3/O5/O6, W1-M1/M4/M5: engine cutover, archive semantics, reproducibility, selector ambiguity, missing provenance/gates.
- **Runtime Support & Incident Responder** ← W1-U2/U4, W1-O2/O3/O5/O6, W1-M3/M4: crash persistence, stale state, split-engine failure, partial export, ambiguous mounts/lifecycle.
- **Cross-Suite Package / Cache / State Custodian** ← W1-U4, W1-O4, W1-M4: volume collisions, mutable installs, absent lifecycle identity.

### Credential & Security Steward

**Cares:** prevent secret-bearing artifacts | least privilege | auditable exposure | immutable trusted inputs | enforceable mount/distribution policy.

**Attack surface:** staged config and image layers; writable project/auth/state binds; env forwarding; root/passwordless-sudo agents; registry/tar outputs; floating upstream/tool dependencies.

**W2-CS1 — Personalized secret-bearing image can pass contract and publish. Critical / High.** OMP documents credential/conversation DB/WAL staging and whole-tree COPY (`omp/README.md:142-167,245-264`; `omp/Dockerfile:128-129`), yet `-Push/-Tar/-Load*` have no taint gate (`omp/build.ps1:13-31,120-159`). Definition explicitly treats filename filtering as non-proof and known-secret restriction as disclosure (`2608030706-coding-agent-sandbox-suite-contract-def.md:88-92,127-131,198`). Incident radius includes engine layers, tars, registry blobs/caches, loaded copies, credentials, and conversations.

**W2-CS2 — Credentialed runtime is root-equivalent without a safe profile. Critical / High.** Codex runs approval bypass with passwordless sudo (`codex/run.ps1:66-88`; `codex/Dockerfile:41-44`); Claude/OpenCode have passwordless sudo (`claude/Dockerfile:53-55`; `opencode/Dockerfile:67-72`); OMP runs root (`omp/Dockerfile:5-6`). Host project and credentials/state are writable/readable. R5 only asks permission mode and mount disclosure (`2608030706-coding-agent-sandbox-suite-contract-def.md:159-165`); no privilege ceiling, safe default, network/mount restriction, or explicit dangerous-mode consent.

**W2-CS3 — OMP deterministically prints provider secret values. High / High.** Launcher expands each host secret into `-e NAME=value`, appends it to `$runArgs`, then prints the full joined command (`omp/run.ps1:83-105,111-140`). Secrets therefore enter console/transcript and engine process arguments; forwarding is normal-path, not an edge. Fix: pass names without inline values (`--env NAME` where supported or protected env-file/secret mechanism), redact diagnostics, and add a canary-secret output/argv conformance check.

**W2-CS4 — Mutable root build inputs can become the trusted runtime. High / Medium.** OMP defaults a remote GitHub build with empty pin and installs moving Node/package streams as root (`omp/build.ps1:29-31,103-105`; `omp/Dockerfile:20-37,74-83`). No digest/signature/provenance policy exists; pinning is unresolved (`2608030706-coding-agent-sandbox-suite-contract-def.md:233`). A compromised/moved upstream can access every later runtime secret and writable workspace.

**W2-CS5 — Mount/security conformance is ambiguous and self-attested. High / High.** “Mount only the selected project” conflicts with permitted auth/state mounts (`2608030706-coding-agent-sandbox-suite-contract-def.md:151,159-162`); filename exclusions and README disclosure lack an executable gate (`:127-131,167,239`). A reviewer cannot consistently accept/reject additional RW mounts or prove that renamed secrets are absent.

**Challenges:** Five Whys: secret image publishes → known store enters context → whole tree enters layer → output flag checks intent only → disclosure is treated as control → no conformance authority. Cascade: mutable source/credential DB → privileged image → broad runtime secret access → console/registry exposure → revocation, artifact recall, and user notification with no complete inventory. Inversion: deny prepared/runtime secrets and privilege by default; require typed, auditable exceptions rather than warning-based conformance. **Solid:** Draft explicitly denies hostile isolation and calls filename filtering non-proof; OMP warnings expose rather than hide risk. These facts enable a stronger enforceable tier.

### Release / Conformance & Artifact Custodian

**Cares:** certifiable inputs/outputs | same-engine launchability | digest-bound provenance | deterministic rollback | retention/recall | atomic combined acceptance.

**W2-RC1 — No release gate makes Docker cutover and artifact identity unenforceable. Critical / High.** All observed build drivers default Podman while launchers default Docker (`codex/build.ps1:13-27`; `claude/build.ps1:13-29`; `opencode/build.ps1:13-31`; `omp/build.ps1:13-32`; corresponding `run.ps1` parameter blocks). R3 declares Docker default, but conformance evidence remains open (`2608030706-coding-agent-sandbox-suite-contract-def.md:137-139,239`). “Built” need not mean default-launchable and a same-tag stale Docker image may run.

**W2-RC2 — Output chain is non-transactional and semantically unverified. High / High.** Save/push/retag/load run sequentially; later failure leaves earlier effects (`codex/build.ps1:118-153`; `omp/build.ps1:134-169`). Retag globally rewrites manifest text and overwrites the archive without match cardinality, structure, digest, or clean-engine load proof (`codex/retag-tar.ps1:43-64`). Exported/Published conflates distinct outcomes (`2608030706-coding-agent-sandbox-suite-contract-def.md:203-213`).

**W2-RC3 — Prepared state, sources, and retention lack immutable provenance. Critical / High.** Lifecycle has no context manifest, script/Dockerfile revisions, selector/profile, engine/digest, sensitivity, registry destination, or retention owner (`2608030706-coding-agent-sandbox-suite-contract-def.md:203-213`). Mutable rebuild/tag rollback cannot reconstruct or recall secret-bearing content.

**W2-RC4 — Combined acceptance has no coherent release unit. High / Medium.** Planned `c_c` stages two config domains, builds one image, uses runtime `-Agent`, and permits `-SkipPrepare`; planned probes are not a contract-bound release record (`2608030408-c-c-combined-suite-plan.md:57-94,202-249,305-365`). A half-stale context plus one passing agent smoke can be mistaken for successor acceptance.

**Challenges:** Five Whys for false archive success: process exits 0 → substitution has no semantic postcondition → build equates exit with artifact proof → lifecycle has no identity/partial-success state → no acceptance authority. Cascade: prepare secret/mutable state → push tag → later retag/load fails → copies and retained blobs diverge → rollback by tag selects unknown content. Inversion: promote immutable digest only after a signed receipt binds sanitized context manifest, source pins, selectors, engine, semantic archive/load result, destinations, retention, and both agent branches. **Solid:** distribution flags are explicit and invalid selectors fail before prepare; process failures stop later steps. Neither proves artifact semantics.

### Runtime Support & Incident Responder

**Cares:** identify what ran/where data went | contain safely | restore known state | finite MTTR | defensible timeline.

**W2-RS1 — Lifecycle is not an incident record. High / High.** Broad states omit run ID, manifest, context revision, engine/digest, mounts, volume generation, agent/profile, exit/signal, and cleanup result (`2608030706-coding-agent-sandbox-suite-contract-def.md:203-213`). `--rm` erases the runtime witness while workspace, volumes, image layers, and auth/history remain.

**W2-RS2 — Abnormal exit has data-loss/contamination risk but no recovery protocol. High / Medium.** OpenCode documents WAL checkpoint loss on hard kill (`opencode/README.md:102-108`); project DB, auth/state binds, caches, dependency install, and workspace have different durability (`opencode/run.ps1:62-88,135-143`). Contract lacks Interrupted/Recovering states, checkpoint, quarantine, retry, or evidence-preservation rules.

**W2-RS3 — Default engine mismatch produces opaque wrong/stale-image incidents. High / High.** Static defaults contradict Draft cutover and launcher emits engine command/error rather than resolving build receipt/digest (`omp/run.ps1:139-142`; evidence under W2-RC1). Support cannot tell absent image from stale same-tag image in another store.

**W2-RS4 — Persistent objects lack recoverable identity/reset ownership. High / Medium.** Auth/history/cache/module mounts differ; Codex/Claude share names while OMP prefixes them (`codex/run.ps1:61-72`; `claude/run.ps1:203-218`; `omp/run.ps1:56-71,114-117`). R5 prose does not supply machine-readable inventory, producer, backup, rotation, reset, or retention.

**Challenges:** Five Whys: support cannot establish failure → lifecycle is coarse → no receipt/manifest → R5 requires prose → definition excludes verification plan → recovery is not normative behavior. Cascade: crash during edit/install/SQLite/auth refresh → container disappears → partial host/state changes remain → retry consumes stale/dirty state → forensic context is lost. Recovery today: isolate workspace/volumes, snapshot DB+WAL+SHM, restore from external VCS, revoke auth, identify image manually. Inversion: force explicit engine until cutover proof; retain a redacted run receipt after abnormal exit. **Solid:** persistence vs removal is honestly distinguished; OpenCode discloses WAL risk; Codex demonstrates missing-source reset.

### Cross-Suite Package / Cache / State Custodian

**Cares:** private compatible state | deterministic install | canonical project identity | inventory/migration/expiry | safe retirement.

**W2-ST1 — Codex and Claude share dependency/cache namespaces. High / Medium.** Both use `nmvol-<12-hex lowercased-path hash>` and bare `pm-cache` (`codex/run.ps1:56-72`; `claude/run.ps1:190-219`). Image, suite, OS/arch, Node/package-manager, schema, and lock digest are absent; OpenCode/OMP prefixes prove avoidability (`opencode/run.ps1:90-133`; `omp/run.ps1:49-68,106-115`).

**W2-ST2 — Nonempty directory substitutes for valid immutable install. High / High.** Every launcher runs mutable `install` commands only when `ls -A` says empty (`codex/run.ps1:63`; `claude/run.ps1:203`; `opencode/run.ps1:126`; `omp/run.ps1:68`). Failed/killed/concurrent install or attacker sentinel becomes indefinitely reusable; no lockfile hash, frozen mode, compatibility marker, lock, or atomic completion exists.

**W2-ST3 — Raw path hash is not project identity. Medium / Medium.** Launchers hash `$Workspace.ToLowerInvariant()` without canonical resolution or stored mapping (`codex/run.ps1:56-63`; `claude/run.ps1:190-204`; `opencode/run.ps1:118-127`; `omp/run.ps1:49-68`). Aliases split state; path reuse inherits old state; truncated IDs have no collision detection.

**W2-ST4 — Durable state has no lifecycle, inventory, or retention contract. High / High.** Named volumes survive `--rm`; cleanup is manual and incomplete (`codex/README.md:84-85`; `claude/README.md:152-153`; `opencode/README.md:104-121`; `omp/README.md:175-191`). Image/container lifecycle omits data state (`2608030706-coding-agent-sandbox-suite-contract-def.md:203-213`).

**Challenges:** Five Whys: stale volume reused → emptiness means health → no completion/provenance → identity is shortened raw-path hash → collision is disclosure duty → lifecycle ignores durable data. Cascade: first mutable/concurrent install → partial/foreign persistent tree → opaque cross-agent failure → broad prune threatens another suite → retirement/incident cannot bound data. Inversion: ephemeral state by default maximizes isolation but costs cold start; balanced fix is suite-private, schema/ABI/lock-digest metadata-validated state with explicit sharing and expiry. **Solid:** masking correctly avoids Windows-native modules; OMP/OpenCode already prefix state; R5 recognizes collision semantics.

### Wave 2 Findings Closed

Wave 2 completed and was written before wave-3 derivation. Cross-role intersections: disclosure-only security; absent digest/provenance receipts; runtime disappearance with durable unowned state; mutable/colliding first-writer caches; no executable adoption, release, recovery, or retirement authority.

## Wave 3 — Adversarial & Accountable Roles (Working Record)

Derived only after re-reading closed waves 1–2:
- **Workspace / Repository / Cache Attacker** ← W2-CS2, W2-RS2, W2-ST1/ST2/ST3: privileged writable runtime, crash ambiguity, shared/weakly initialized persistent state.
- **Supply-Chain / Registry Attacker** ← W2-CS1/CS4, W2-RC2/RC3: secret-bearing outputs, mutable root inputs, unverified artifact transforms, absent provenance.
- **Host Transcript / Process Observer** ← W2-CS3: normal OMP launch prints secrets and embeds them in engine client arguments.
- **Release & Security Approver** ← W2-CS5, W2-RC1–RC4: ambiguous conformance, no cutover gate, no coherent release identity.
- **Incident Commander / Credential-Revocation & Privacy Owner** ← W2-CS1–CS3, W2-RS1/RS2/RS4, W2-ST4: distributed secret/state blast radius without inventory, recovery, or retention lifecycle.

### Workspace / Repository / Cache Attacker

**Capability:** controls project content, dependency metadata/lifecycle behavior, agent-visible instructions, or a prior same-user/same-engine persistent volume. **Gain:** partial—deny/degrade work, hide provenance, persist across runs; full—execute through a privileged credentialed agent, alter host project, access provider authority. **Asymmetry:** one repository/dependency/state change can affect every later agent launch; host recovery and credential rotation far exceed attacker effort.

**W3-WA1 — Repository/dependency input reaches a privileged credentialed runtime. Critical / Medium.** Project is writable; masked initialization runs package-manager install commands; agents are root/passwordless-sudo and may receive host auth/env (`codex/run.ps1:56-88`; `claude/run.ps1:203-224`; `opencode/run.ps1:126-159`; `omp/run.ps1:68,75-140`; privilege evidence under W2-CS2). A hostile dependency lifecycle or agent instruction can target workspace, mounted state, env, and network. The first defense probed—`rm-guard`—mediates only `rm` against `.git`, explicitly not hostile isolation (`2608030706-coding-agent-sandbox-suite-contract-def.md:33-36,150`).

**W3-WA2 — One nonempty sentinel or interrupted first write can become persistent “healthy” state. High / Medium.** All module-volume gates use `ls -A` rather than ownership/completion/lock provenance (W2-ST2 evidence). A prior run, crash, or same-engine actor can make later launches skip initialization; Codex/Claude then cross the suite boundary through identical volume names. Partial exploit causes opaque dependency drift; full compromise persists executable content across agent changes.

**W3-WA3 — Path alias/reuse and abnormal exit amplify deniability. High / Medium.** Raw lowercased path hashes lack canonical metadata, and `--rm` removes the runtime while dirty volumes/project/DB remain (W2-ST3, W2-RS2). An induced failure can leave effects attributed to the next run. **Cascade:** controlled repo/state → install/agent execution → privileged access → interruption → persistent dirty state + vanished runtime witness → retry reuses it. **Remediation:** default non-root/no-sudo profile; explicit consent for dangerous mode; frozen installs with lifecycle scripts disabled unless approved; atomic completion metadata keyed by suite/schema/ABI/lock digest; volume lock/quarantine; canonical workspace identity; capture-engine hostile-fixture and interrupted-install proofs. **Solid:** top-level masking blocks Windows-native module reuse; explicit non-isolation avoids overstating the guard.

### Supply-Chain / Registry Attacker

**Capability:** influences mutable upstream Git/base/package/tag or reads/writes a distribution destination. **Gain:** partial—availability/drift/tag confusion; full—code execution in every root-built runtime or retrieval/substitution of credential-bearing layers. **Asymmetry:** one upstream or registry position fans out to every rebuild/run; defenders must inventory and recall all copies.

**W3-SA1 — Mutable inputs become root-built trusted runtimes. Critical / Medium.** OMP accepts empty upstream pin, remote default branch, moving Node/pnpm/package inputs, and root image execution (`omp/build.ps1:29-31,103-105`; `omp/Dockerfile:3-6,20-37,74-83`). Draft both requires explicit shared-tool args and leaves immutable pinning open (`2608030706-coding-agent-sandbox-suite-contract-def.md:147-149,233`). First probes: absent signatures/digests/SBOM/provenance and tag-based launch.

**W3-SA2 — Distribution converts documented local secrets into attacker-retained artifacts. Critical / Medium.** OMP’s credential/history layers can be pushed/exported without taint block (W2-CS1). Registry read or later access yields value without compromising a live container; tag deletion need not prove blob/tar/loaded-copy deletion [INFERENCE—registry retention is deployment-specific].

**W3-SA3 — Mutable tags and text retagging erase trustworthy identity. High / Medium.** Nontransactional save/push/retag/load plus unrestricted manifest substitution provide no exact source-match, digest, or destination equivalence (W2-RC2/RC3). **Cascade:** upstream/tag moves → privileged image builds → secret context enters layer → push succeeds → later transform/load fails → unknown copies persist → rollback/rebuild selects different bytes. **Remediation:** immutable commit/base/package identities with integrity/signature checks; SBOM and signed provenance; no-secret layer invariant; digest-only promotion/run; structural archive rewrite to separate output with exactly-one match and clean-engine equivalence; registry receipt and verified deletion/recall. **Solid:** output actions are opt-in and process failures stop subsequent steps, limiting accidental fan-out but not prior effects.

### Host Transcript / Process Observer

**Capability:** reads terminal/CI transcript or, subject to host policy, another process’s command arguments. **Motive/gain:** obtain provider/cloud/search credentials with no container or registry access. **Asymmetry:** passive observation of one normal launch can expose every populated forwarded variable; revocation spans many providers.

**W3-HO1 — Normal launch deterministically emits plaintext secrets. High / High.** OMP builds literal `NAME=value` entries and prints the complete engine command (`omp/run.ps1:83-105,111-140`). This establishes transcript exposure statically. **W3-HO2 — Values enter native client argv. High / Medium.** `$runArgs` contains the literals passed to Docker/Podman; whether another host principal/telemetry can read them is OS/policy-specific [INFERENCE]. First defense probed is logging redaction; none exists. Cascade: routine launch → transcript/process capture → credential reuse → provider data/cost impact → broad rotation and transcript purge. Fix: inherit by name or use engine secret/protected env file, redact diagnostics/errors, and prove a canary is absent from output/argv while functional injection still works. **Solid:** forwarded names are bounded and `GOOGLE_APPLICATION_CREDENTIALS` is intentionally excluded (`omp/run.ps1:83-109`).

### Release & Security Approver

**Cares:** repeatable accept/reject | exact release unit | bounded security claim | rollback/recall | challenge-resistant evidence.

**W3-AP1 — Draft cannot authorize current conformance. Critical / High.** Definition is Draft, scopes R1–R5 to future suites, reports no runtime probes, and leaves gate authority open (`2608030706-coding-agent-sandbox-suite-contract-def.md:3-19,217-239`). An approver cannot self-invent applicability/exceptions. Ratify a versioned contract naming current/future/combined scope, profiles, authorities, evidence schema, and exception rules.

**W3-AP2 — Docker-default promotion is no-go without same-ID end-to-end proof. Critical / High.** Build/run defaults currently diverge (W2-RC1). Required receipt: clean-store default build without override → immutable Docker image ID/digest → default launch of that exact ID; combined suite runs both branches against the same ID.

**W3-AP3 — Exports and dangerous profiles lack approval units. Critical / High.** Each irreversible output needs context/source/script/Dockerfile hashes, sensitivity class, selectors/profile, engine/digest, archive semantic equivalence, registry destination/digest, per-stage result, retention/recall owner. Security profiles must enumerate UID/sudo/capabilities/network, every mount mode/owner, secret channel, persistence, agent bypass, and explicit consent. Unknown/sensitive context, undeclared RW mount, or `-SkipPrepare` without exact context receipt is no-go.

**W3-AP4 — Combined release must be atomic across both agents. High / Medium.** Planned synthetic manifests, immutable ID, two branch probes, live smokes, and blocked retirements are useful but not executed (`2608030408-c-c-combined-suite-plan.md:202-249,305-365`). Any stale subtree, different ID, unrun/failed branch, or source coupling rejects the whole unit. **Challenges:** Five Whys: approval indefensible → self-attested prose → no executable gate → no receipt lifecycle → applicability/authority unresolved. Inversion: default-deny promotion, keep local outputs untrusted, approve dangerous behavior only under an explicitly dangerous profile. **Solid:** observed/future/planned facts are separated; output flags and invalid-selector timing are explicit.

### Incident Commander / Credential-Revocation & Privacy Owner

**Cares:** detect/scope | stop access | recall/revoke | known-good restore | notification | evidence hold vs deletion | provable closure.

**W3-IC1 — No immutable incident inventory bounds containment. Critical / High.** Lifecycle omits run/context/image/distribution/state identity while `--rm` removes runtime and durable objects survive (`2608030706-coding-agent-sandbox-suite-contract-def.md:190-213`). Require append-only redacted receipts binding canonical workspace, credential principals by name/issuer not value, context/source, engine/digest, mounts/volumes, destinations, exit/signal, owners, timestamps, cleanup.

**W3-IC2 — Secret recall and credential revocation cannot be proven complete. Critical / High.** Credential/conversation layers, tars, registry blobs, loaded images, console transcripts, env, host auth/state, project DB, and volumes have no common ledger (W2-CS1/CS3, W2-RS4/ST4). Closure needs per-destination quarantine/deletion acknowledgements, provider revocation, access-log review where available, owner notification, and residual-risk record.

**W3-IC3 — Abnormal exit makes restoration unsafe. High / Medium.** Workspace edits, package volumes, auth refresh, and SQLite checkpoint durability diverge; no dirty/quarantine state exists (W2-RS2/ST2). Before retry: preserve project and DB/WAL/SHM/volume evidence, restore from known source, invalidate dirty state, reauthenticate, and run only a provenance-bound image.

**Worst case:** secret image distributes while OMP prints other keys; privileged run mutates workspace/auth/cache then dies; runtime evidence vanishes; retry consumes dirty state; unknown copies remain; credentials keep working; affected owners cannot be bounded. Recovery cost is unbounded without inventory. **No-go closure:** any unknown copy, unacknowledged credential owner, unexplained durable state, unproven restore, or missing notification/retention decision. **Solid:** Draft distinguishes persistent state from container removal and candid READMEs expose secret/WAL risks.

### Wave 3 Findings Closed

Exactly three waves completed. No fourth wave opened.

## Roles Not Attacked

| Role | Surfaced by | What would have been asked |
|---|---|---|
| Contract / Policy Ratifier | W3-AP1 | Who makes Draft requirements normative, assigns exception authority, and versions the evidence schema? |
| Registry / Engine Retention Administrator | W3-SA2, W3-IC2 | How are blobs, loaded images, caches, access logs, deletion, and tombstones enumerated and proven? |
| Provenance Trust-Root / Signing-Key Custodian | W3-SA1/SA3 | Who protects signing identity, rotates it, and prevents validly signed malicious or stale provenance? |
| CI Transcript / Endpoint Visibility Administrator | W3-HO1/HO2 | Which principals and telemetry retain console/argv data, for how long, and how is purge proved? |
| External Provider / Identity Administrator | W3-IC2 | How are each principal’s tokens/sessions revoked and invalidation acknowledged? |
| Affected Workspace / Data Owner & Backup/VCS Custodian | W3-IC3 | Who confirms scope/notification, preserves necessary evidence, and proves a clean restore without retaining excess personal data? |

## Cross-Wave Pass

Run only after wave 3 closed; all roles considered together.

### CW1 — Disclosure-to-breach-to-unbounded-recall

**Path:** Operator W1-O1 stages/publishes known secrets → Security Steward W2-CS1 accepts that disclosure is non-enforcement → Supply-Chain/Registry Attacker W3-SA2 gains durable copies → Incident Commander W3-IC1/IC2 lacks inventory or deletion/revocation proof.

**Severity:** Critical | **Likelihood:** High. Normal documented OMP build guidance includes push while DB/WAL credential/history state enters image layers (`omp/README.md:39-44,142-167,245-264`; `omp/Dockerfile:128-129`). No exploit beyond an explicit supported action is required. Worst case spans provider compromise, private conversations, registry retention, tars, loaded engines, and transcripts.

### CW2 — Project Input-to-Privilege-to-Persistent Re-entry

**Path:** Agent User W1-U1 exposes writable privileged project/credentials → State Custodian W2-ST1/ST2 finds shared, non-atomic “nonempty=healthy” volumes → Workspace Attacker W3-WA1/WA2 executes or persists via dependency/agent inputs → Runtime Support W2-RS1/RS2 loses the `--rm` runtime witness and cannot attribute dirty state.

**Severity:** Critical | **Likelihood:** Medium. Cost asymmetry: one repository/dependency/state mutation may affect repeated privileged launches and cross Codex/Claude volume boundaries; recovery requires project restore, state quarantine, and credential rotation.

### CW3 — Ambiguity-to-False Combined Acceptance

**Path:** Maintainer W1-M1/M3/M4 receives undefined selector/mount semantics and no provenance → Release Custodian W2-RC3/RC4 cannot bind both prepared trees/agents to an image → Approver W3-AP1/AP4 lacks normative authority yet accepts one passing branch/tag → Operator retires or bypasses source suites against a half-stale successor.

**Severity:** Critical | **Likelihood:** Medium. Planned `c_c` safeguards help but are not executed or root-contract gates. Recovery requires keeping source suites, rebuilding both sanitized contexts to one immutable digest, and repeating both branches before any retirement.

### CW4 — Default Cutover-to-Wrong Artifact-to-Supply-Chain Ambiguity

**Path:** Operator W1-O3 defaults build to Podman → Support W2-RS3 sees Docker absence or stale same tag → Release Custodian W2-RC1/RC2 accepts process/tag output without digest equivalence → Supply-Chain Attacker W3-SA3 exploits mutable identity or defenders simply run unintended bytes.

**Severity:** Critical | **Likelihood:** High during cutover. Default build→default run does not identify one artifact today; current static defaults establish the mismatch.

### CW5 — Routine Secret Log-to-Privacy Incident

**Path:** Agent User/Operator supplies provider env → Security Steward W2-CS3 identifies literal argument and command output → Host Observer W3-HO1 gains values from a normal transcript → Incident Commander W3-IC2 cannot enumerate transcript recipients/retention or prove purge.

**Severity:** High | **Likelihood:** High. This path is independent of image publication and should be fixed at launcher source immediately.

**Cross-wave Five Whys:** Why can one routine action create an unbounded incident? → secrets/state are allowed across build/runtime channels → disclosure is treated as sufficient → no machine-readable profile/taint/receipt exists → lifecycle tracks broad product states, not data/artifact identity → conformance authority is an Open Question. **First principle:** sensitive data and durable artifacts require prevention policy, immutable identity, explicit owner, integrity transitions, and terminal disposition—not prose alone.

**Cross-wave inversion:** Assume each boundary supplies hostile or stale input: host config, workspace, cache, upstream, tag, registry, transcript, interrupted state, and reviewer judgment. Under that model, safe defaults deny secrets/privilege/distribution, every exception is typed and captured, and promotion occurs only by immutable receipt.

## Stakeholder Roles

| Wave | Role | Cares About / Gain | Pain / Success | Critical Assumptions |
|---|---|---|---|---|
| 1 | Coding-Agent User | project integrity, auth/history, continuity | loss, exfiltration, opaque state | `--rm`/guard imply safety |
| 1 | Suite Operator | correct, reproducible, distributable image | stale/secret/wrong-engine output | prepare/tag/exit status prove identity |
| 1 | Suite Maintainer / Integrator | determinate API and conformance | ambiguous MUSTs, unsafe combination | current intersection is durable |
| 2 | Credential & Security Steward | prevention, least privilege, audit | disclosure-only controls | docs constrain runtime/output |
| 2 | Release / Conformance & Artifact Custodian | certifiable immutable release | partial/untraceable output | tag/process success proves artifact |
| 2 | Runtime Support & Incident Responder | diagnosis, containment, restoration | vanished witness, unowned state | disclosed persistence is discoverable |
| 2 | Package / Cache / State Custodian | compatible private durable state | collisions, drift, orphaning | path hash/nonempty imply identity/health |
| 3 | Workspace / Repository / Cache Attacker | persistence, authority, disruption | succeeds via low-cost trusted input | privileged launch will trust project/state |
| 3 | Supply-Chain / Registry Attacker | fan-out, substitution, secret retrieval | succeeds through mutable inputs/copies | provenance/recall stays absent |
| 3 | Host Transcript / Process Observer | passive credential collection | succeeds when literal values are logged | output/argv remains accessible |
| 3 | Release & Security Approver | defensible promotion/no-go | false acceptance, orphaned side effects | Draft supplies authority/evidence |
| 3 | Incident / Revocation & Privacy Owner | bounded recall/recovery/closure | unknown copies/owners/dirty restores | affected objects can be enumerated |

### Wave Derivation

- **Wave 1 → 2:** W1-U1/U3 + W1-O1/O6 + W1-M3/M5 → security steward; W1-O1/O3/O5/O6 + W1-M1/M4/M5 → release/conformance custodian; W1-U2/U4 + W1-O2/O3/O5/O6 + W1-M3/M4 → support responder; W1-U4 + W1-O4 + W1-M4 → durable-state custodian.
- **Wave 2 → 3:** W2-CS2/RS2/ST1–ST3 → workspace/cache attacker; W2-CS1/CS4/RC2/RC3 → supply-chain/registry attacker; W2-CS3 → host observer; W2-CS5/RC1–RC4 → approver; W2-CS1–CS3/RS1/RS2/RS4/ST4 → incident/privacy owner.

## Attack Surface (Per Role)

- **User:** writable workspace | bypass/privilege | credentials/history | package/tool bootstrap | interruption.
- **Operator:** host source | generated context | engine defaults/stores | tar/retag/load/push | remote inputs | diagnostics.
- **Maintainer:** normative R1–R5 text | agent/feature selectors | combined config trees | mounts/profiles | lifecycle.
- **Security:** secrets across context/layers/env/mounts/logs | UID/sudo/network | supply-chain trust | policy enforcement.
- **Release:** context/source identity | engine/image digest | output destinations | archive semantics | combined acceptance.
- **Support:** run/exit identity | workspace/auth/DB/volume durability | engine mismatch | quarantine/reset.
- **State:** volume namespace | project canonicalization | lock/install integrity | schema/ABI | retention/migration.
- **Workspace attacker:** repository/dependency/instruction input | same-engine volumes | crash timing.
- **Supply-chain attacker:** upstream refs/base/packages | mutable tags | registry reads/writes/retention.
- **Host observer:** terminal/CI logs | native argv/telemetry [host-dependent].
- **Approver:** policy authority | evidence receipt | exception/security-profile scope | stop/go.
- **Incident owner:** detection inventory | containment | recall/revocation | restore | notification | closure.

## Critical Findings

### F1 — No enforceable no-secret boundary

**Severity:** Critical | **Likelihood:** High | **Affects:** user, operator, security, release, attacker, incident owner.

**Evidence/attack:** filename filters are explicitly not proof; OMP stages known credential/history stores, whole-tree COPYs them, allows distribution, and prints separately forwarded env secrets (`2608030706-coding-agent-sandbox-suite-contract-def.md:88-92,198`; `omp/Dockerfile:128-129`; `omp/build.ps1:120-159`; `omp/run.ps1:83-105,111-140`). **Blast radius:** layers, engines, tars, registry, transcripts, provider accounts, conversations. **Remediation:** public-image tier MUST reject secret/session/history/DB/WAL/SHM/unknown content; personalized tier MUST be explicit, non-distributable by default, tainted, and separately consented.

### F2 — No safe runtime profile

**Severity:** Critical | **Likelihood:** High | **Affects:** user, security, support, workspace attacker.

**Evidence/attack:** writable workspace + mounted/forwarded credentials + root/passwordless sudo + approval bypass; guard is explicitly narrow non-isolation (W1-U1, W2-CS2, W3-WA1). **Blast radius:** project destruction, secret access, agent/dependency execution, persistent state. **Remediation:** default non-root/no-sudo/no-new-privileges/cap-drop; typed RO/RW mounts; scoped/brokered secrets; bounded egress; explicit destructive profile consent.

### F3 — No normative conformance or immutable provenance gate

**Severity:** Critical | **Likelihood:** High | **Affects:** operator, maintainer, release, support, approver, incident owner.

**Evidence/attack:** Definition is Draft, future-scoped, unprobed, and leaves acceptance evidence open; lifecycle lacks manifests/digests/receipts (`2608030706-coding-agent-sandbox-suite-contract-def.md:3-19,203-239`). **Blast radius:** false Docker cutover, wrong/stale image, non-reproducible release/incident, unsafe combined acceptance. **Remediation:** ratified versioned scope + executable gate + signed prepare/build/run/distribution receipts.

### F4 — Durable state lacks identity, integrity, and retirement

**Severity:** High | **Likelihood:** High | **Affects:** user, support, state custodian, workspace attacker, incident owner.

**Evidence/attack:** Codex/Claude collide; every suite reuses any nonempty module volume; raw truncated path hash has no canonical metadata; lifecycle omits volumes (W2-ST1–ST4). **Blast radius:** cross-suite dependency contamination, drift, interrupted state, orphaned sensitive data. **Remediation:** suite/purpose/schema/ABI/lock identity; canonical project mapping; frozen atomic initialization with locks/health metadata; inspect/migrate/quarantine/prune lifecycle.

### F5 — Artifact transform/distribution lacks semantic postconditions

**Severity:** High | **Likelihood:** High | **Affects:** operator, release, supply-chain attacker, incident owner.

**Evidence/attack:** sequential irreversible actions preserve partial outputs; global tar-manifest text substitution lacks match/digest/load verification (`codex/build.ps1:118-153`; `codex/retag-tar.ps1:43-64`). **Blast radius:** false success, unintended tag/image, unknown registry/tar copies. **Remediation:** structural rewrite to separate output; exactly-one reference; archive digest; clean-engine equivalence; per-step durable receipt and compensation/recall.

### F6 — Contract contradictions leave multi-agent and mount behavior reviewer-defined

**Severity:** High | **Likelihood:** High | **Affects:** maintainer, security, release, approver.

**Evidence/attack:** runtime agent selector vs build feature selectors is undefined; “mount only selected project” conflicts with auth/state mount disclosure; current-intersection tool baseline remains open (W1-M1–M3). **Blast radius:** cross-agent config/state, unnecessary supply-chain surface, inconsistent conformance. **Remediation:** typed selector namespaces/phases; exact workspace-only bind wording plus allowlisted non-workspace mounts; capability profiles instead of unresolved universal tool MUSTs.

### F7 — Abnormal exit and ephemerality have no recovery contract

**Severity:** High | **Likelihood:** Medium | **Affects:** user, support, state/incident owners.

**Evidence/attack:** writable project/state persist after `--rm`; OpenCode documents hard-kill WAL loss; lifecycle lacks signal/checkpoint/dirty/recovering states (W1-U2, W2-RS1/RS2). **Remediation:** exit/signal receipts; checkpoint and WAL/SHM policy; dirty-state quarantine; safe retry/reset; evidence preservation and external restore ownership.

### F8 — Mutable supply inputs undermine trusted rebuilds

**Severity:** High | **Likelihood:** Medium | **Affects:** operator, security, release, support, supply-chain attacker.

**Evidence/attack:** empty upstream pin, remote default, moving Node/pnpm/package/base streams can become root runtime (`omp/build.ps1:29-31,103-105`; `omp/Dockerfile:20-37,74-83`). **Remediation:** immutable refs/digests/locks, integrity/signature verification, SBOM/signed provenance, explicit freshness mode separate from release mode.

## Role-Based Assumption Challenges

| Role | Assumption | Counter-Evidence / If Wrong | Action |
|---|---|---|---|
| User | `--rm` or guard protects project | writable bind and privilege survive/remain effective; guard covers only `rm`/`.git` | Reject |
| Operator | prepared context is current/safe | missing OMP source retains old destination; filename filter misses known stores | Reject |
| Maintainer | selectors and mounts have one meaning | R1/R3/R4/R5 conflict/underdefine combined phases and non-workspace mounts | Reject |
| Security | disclosure constrains exposure | publish/log/runtime paths remain mechanically allowed | Reject |
| Release | tag/exit 0 proves artifact | engine split, mutable tags, textual retag, partial side effects | Reject |
| Support | persistent objects are discoverable | no manifest, receipt, producer, generation, dirty state | Reject |
| State custodian | nonempty hashed volume is valid project state | collision/alias/interruption/first-writer lack metadata | Reject |
| Approver | Draft can serve as gate | current/future applicability and evidence authority unresolved | Reject |
| Incident owner | recall/restore can be bounded | no ledger links credentials, layers, tars, engines, logs, state | Reject |

## Role-Specific Edge Cases & Failures

- **User/Support:** SIGKILL or engine loss during workspace edit, dependency install, auth refresh, or SQLite write → persistent partial effects; recovery difficult.
- **Operator/Release:** default build Podman then default run Docker; stale same-tag Docker image exists → wrong image may run; recovery requires immutable receipt.
- **Security/Incident:** source directory disappears after secret staging → stale context builds/publishes; recall may be impossible without destination ledger.
- **State/Workspace attacker:** concurrent cold starts or one sentinel file → incomplete volume becomes reusable; quarantine required.
- **Maintainer/Approver:** combined context one subtree stale or absent, `-SkipPrepare`, only one branch probed → false atomic acceptance.
- **Supply-chain:** upstream/tag/package moves or disappears during incident rebuild → different or impossible recovery.
- **Host observer:** CI captures routine OMP command → plaintext credentials retained; transcript purge + rotation required.

## What's Hidden (Per Role)

**Omissions:** user—workspace writes are not transactional; operator—no sensitivity/provenance receipt; maintainer—selector/mount/profile grammar; security—safe default and taint policy; release—partial-output ledger/retention; support—abnormal-exit state; state custodian—owner/schema/expiry; approver—ratification authority; incident owner—recall/notification closure schema.

**Tradeoffs:** current design favors agent power, convenience, cache speed, portable host config, fresh upstream, and output flexibility over least privilege, deterministic bytes, strong isolation, state integrity, and recall. These tradeoffs are sometimes disclosed but rarely enforced or measured.

## Scale & Stress (Role Impact)

**At 10x:** operators accumulate opaque volumes/images/tars; support sees more engine/tag/state ambiguity; security rotates more credential families; approvers perform bespoke prose reviews; registry/transcript copies multiply.

**At 100x:** 48-bit/path-alias identity and shared namespace become fleet risks; mutable inputs prevent consistent rebuild; manual recall/retention/volume pruning becomes impossible; one upstream or secret-bearing release fans out across many projects/agents; absence of machine-readable receipts makes incident scope unbounded.

## Remediation

### Must Fix (Before Proceeding)

1. **Ratify applicability and authority** (maintainer, approver) → version current/future/combined scope, security tiers/profiles, exception owner, conformance schema.
2. **Enforce no-secret distribution boundary** (user, operator, security, incident) → allowlisted prepared manifest + content/layer canaries; reject tainted tar/push/load; remove OMP DB/WAL/history from distributable context.
3. **Stop literal secret output/argv** (operator, security, host observer) → name-only inheritance or protected secret channel; redaction; output/argv canary proof.
4. **Create safe runtime default** (user, security, workspace attacker) → non-root/no-sudo, reduced privileges, typed mounts, secret broker/scope, explicit destructive mode.
5. **Bind every state transition to immutable evidence** (release, support, incident) → prepare manifest; build provenance/digest; run receipt; distribution ledger/retention/recall.
6. **Prove Docker cutover end to end** (operator, release, support) → clean-store default build→default run of same immutable ID for every suite/profile; no stale/preloaded tag.
7. **Define durable-state lifecycle** (user, support, state custodian) → namespaced schema/ABI/lock identity, canonical project ID, atomic locked init, dirty quarantine, inspect/migrate/prune/retire.
8. **Make combined acceptance atomic** (maintainer, release, approver) → both sanitized subtree manifests and both agent branches against one digest; block retirement on any partial result.

### Should Fix (Before Production)

- Structural tar retag + clean-engine digest equivalence; partial-success compensation/receipt.
- Immutable upstream/base/package defaults, SBOM, integrity/signature and signed provenance; separate explicit freshness mode.
- Interrupt/checkpoint/WAL/SHM/retry semantics and sanitized abnormal-exit evidence.
- Capability profiles for optional browser/Node/tool baseline and host-shell portability.

### Monitor

- Upstream/profile relevance drift; credential-pattern/schema drift; volume growth/collision/quarantine; install-lock contention; dirty-exit rate; transcript retention; registry deletion guarantees; conformance-gate false positives/waivers.

## Final Assessment

**Soundness:** Serious Issues | **Risk:** Unacceptable | **Readiness:** Not Ready

**Per-Role Readiness:**
- **User:** Not Ready — privileged writable runtime and secrets lack safe default.
- **Operator:** Not Ready — known-secret publication, engine mismatch, no provenance.
- **Maintainer:** Not Ready — selector/mount/profile/conformance ambiguity.
- **Security:** Not Ready — disclosure substitutes for enforceable policy.
- **Release/Approver:** Not Ready — no ratified gate or immutable release unit.
- **Support/Incident:** Not Ready — no receipt, dirty-state, recall, or closure contract.
- **State Custodian:** Not Ready — shared/non-atomic/unversioned durable state.

**Conditions for Approval:**
- [ ] All Must Fix items implemented in Definition and conformance spec, with observed evidence per affected role.
- [ ] No secret/session/history content in distributable layers; OMP literal secret output removed.
- [ ] Default Docker build→run resolves one immutable identity for each suite and both combined branches.
- [ ] Safe and dangerous runtime profiles are mechanically distinct and consented.
- [ ] Durable-state and abnormal-exit lifecycle is inspectable, recoverable, and retireable.

**No-Go If:**
- [ ] Definition remains Draft or current/future/combined applicability remains ambiguous.
- [ ] Any known/unclassified sensitive context can be tarred, loaded, or pushed.
- [ ] Any credential value appears in logs/argv or undeclared RW mount/env channel.
- [ ] Release/run/rollback relies on mutable tag without digest-bound receipt.
- [ ] Combined acceptance omits either agent/config branch or source retirement precedes exact successor proof.
- [ ] Incident owner cannot enumerate, revoke/recall, restore, notify, and disposition every affected object.

## Workflow Validation

- [x] Exactly three sequential waves; none skipped/merged; no fourth opened.
- [x] Wave 2/3 roles trace to written earlier findings.
- [x] Each prior wave was written and re-read before deriving the next.
- [x] Per-role cares, assumptions, attack surface, failures, challenges, inversions, cascades, solid points, and remediation recorded.
- [x] Terminal adversaries include capability, motive/gain, effort/damage asymmetry, and defenses probed.
- [x] Post-wave-3 cross-wave pass completed.
- [x] Later roles logged under Roles Not Attacked.
- [x] Evidence labels distinguish Draft/static/README/inference; no dynamic validation claimed.
- [x] Body completed before Bottom Line synthesis.
