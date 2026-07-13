# Red Team: Run baked images without sbx — Plan

> **Created:** 2026-07-06 | **Lead:** developer@3371.online (agent-drafted)
> **Subject:** `2607060236-run-images-without-sbx-plan.md` | **Related:** `2607060232-run-images-without-sbx-eval.md`

---

## Bottom Line

**Verdict:** Proceed with Caution

**Top Vulnerabilities:**
1. **Credential bind-mount is a permanent, silently-shared host secret** — `%USERPROFILE%\.claude-docker\.credentials.json` / `.codex-docker\auth.json` become plain files any *other* container run with a `%USERPROFILE%` mount (or any local process) can read; the plan treats this purely as a persistence mechanism, never as an attack surface.
2. **"Use in any project" contradicts the scripts' actual location** — `run.ps1` lives inside `custom-sbx-templates`, not on PATH, not installed anywhere; every invocation needs the repo's absolute path, which the plan never resolves into an actual distribution story.
3. **No first-run-safety net for `--rm` + `-it` combined with unverified assumptions (A1/A2/A3/A5)** — if any assumption is wrong, the container has already exited and discarded itself (`--rm`), so debugging happens blind, with no `--rm`-off fallback or diagnostic mode documented.

---

## Stakeholder Roles

| Role | Cares About | Pain Points | Critical Assumptions |
|------|-------------|-------------|---------------------|
| Human User (op+dev+end-user) | Fast, reliable "just works" launch from any project dir | Re-auth loops, silent data loss on crash, confusing docker errors | Docker Desktop always running; image already pulled/built; USERPROFILE = real home |
| Future Self / Other Machines | Reusing these images+scripts elsewhere without re-deriving the setup | Scripts are repo-local, not installed; breaks the moment repo isn't cloned there | Repo path is stable and known at call time |
| Security (credential handling) | OAuth/session tokens not exposed beyond the intended process | Host-side plaintext token files reachable by any other container/process with a `%USERPROFILE%` mount | Only this container reads/writes the mounted creds files |
| Integrators (other repo consumers) | Same run experience across engines/OSes | Docker-only behavior tested; podman uid gaps unresolved; PS5.1-only | `-Engine podman` parity with `-Engine docker` holds untested |

---

## Attack Surface (Per Role)

**Human User:**
- Claims: "from any project dir, mount + launch + persist login" (Success Criteria in plan).
- Assumptions: image is already built/loaded; `%USERPROFILE%` is a normal, non-redirected, space-free-enough path; only one `run.ps1` invocation happens at a time per project.
- Dependencies: Docker Desktop (or podman) daemon running; image present in local store; interactive TTY (Windows Terminal) available.

**Future Self / Other Machines:**
- Claims (implicit, from the human task): "use these in any project."
- Assumptions: the repo (and thus `run.ps1`) is available at a known path on whatever machine is being used.
- Dependencies: manual repo clone + path memorization; no install/PATH step exists or is planned.

**Security:**
- Claims: OAuth persists "without shadowing baked content" — security framing stops at *shadowing*, never *exposure*.
- Assumptions: host filesystem is a trusted boundary; nothing else on the machine reads `%USERPROFILE%\.claude-docker\`.
- Dependencies: Windows ACLs on `%USERPROFILE%` (default: owner + admins) are the only control; no encryption, no scoping to this specific wrapper.

**Integrators:**
- Claims: `-Engine docker`/`-Engine podman` both "work," mirroring `build.ps1`.
- Assumptions: podman-rootless uid mapping is a simple `--userns=keep-id` flag away; no one has actually run the podman path per the plan's own Verification Plan (docker-only walkthroughs specified).

---

## Critical Findings

### Finding 1: Credential files are durable, unscoped host secrets
**Severity:** High | **Likelihood:** Medium

**Affects Roles:** Human User, Security

**Attack Vector:** `run.ps1` bind-mounts `%USERPROFILE%\.claude.json`, `%USERPROFILE%\.claude-docker\.credentials.json`, and (codex) `%USERPROFILE%\.codex-docker\auth.json` as plain files, permanently, at predictable paths. Any other container the user later runs with `-v "${env:USERPROFILE}:/host"` (a common ad-hoc debugging pattern), any malware with user-level file access, or any other local process reads the live OAuth token in plaintext — no different from any dotfile, but the plan never flags this as a new attack surface introduced *specifically by containerizing the credential*. sbx presumably scoped/brokered this differently (unverified, but the eval never checked how sbx protected these tokens — an omission carried forward unchallenged).

**Role-Specific Impact:**
- **Human User:** A compromised or curious other container/process running under the same Windows account can read the live Claude/Codex OAuth token without the user ever knowing — token theft looks identical to normal use since the file is legitimately written by the wrapper itself.
- **Security:** No rotation story, no scoping, no permission-tightening step (e.g., `icacls` restricting the file to the user) is in the plan or its Constraints.

**Blast Radius:** Full account takeover of Claude/Codex session for as long as the token is valid; contained to the local machine (not a network-exposed vector), but persistent until manually revoked.

**Remediation:** Add an explicit note (README + script comment) that these files carry live credentials and should be treated like SSH keys — not committed, not shared, not readable by other local tooling. Consider tightening file ACLs at creation time (`icacls $credsFile /inheritance:r /grant:r "$env:USERNAME:F"`) as a cheap belt-and-suspenders step; optional but should at least be a documented risk, not a silent one.

---

### Finding 2: "Use in any project" is unmet by the plan as scoped
**Severity:** Medium | **Likelihood:** High

**Affects Roles:** Human User, Future Self / Other Machines

**Attack Vector:** The original task explicitly states the goal: "so that I can use these in any project." The plan's own Verification Plan invokes `<repo>\claude\run.ps1` — i.e., every single use requires knowing and typing (or aliasing) the absolute repo path. No PATH registration, no PowerShell profile function, no global install step is proposed or even flagged as follow-up. This is a real gap between stated intent and delivered mechanism, not a cosmetic one — "any project" was the entire premise of ditching sbx.

**Role-Specific Impact:**
- **Human User:** Must either (a) remember/type the full repo path every time, (b) manually create a PowerShell function/alias (not covered anywhere), or (c) copy the scripts out of the repo (breaking the "single source of truth" property implied by keeping them here).
- **Future Self / Other Machines:** On a new machine, this repo must be re-cloned to a known path before any project can use it — undocumented as a setup step.

**Blast Radius:** Doesn't block the core mechanism, but the deliverable under-serves the actual ask. Low technical risk, high "did we solve the real problem" risk.

**Remediation:** At minimum, add a README note showing how to add a PowerShell profile function/alias (`function ccrun { & "S:\Repos\custom-sbx-templates\claude\run.ps1" @args }`) so "any project" is actually true day-to-day. Out-of-scope for this plan's file list, but should be flagged as a following Patch, not silently dropped.

---

### Finding 3: `--rm` discards all diagnostic evidence when an unverified assumption fails
**Severity:** Medium | **Likelihood:** Medium

**Affects Roles:** Human User

**Attack Vector:** The plan carries five explicitly-unverified assumptions (A1-A5) that are meant to be checked "early during execution," not blockers. But the wrapper runs with `--rm`, so the instant the container exits (crash, wrong mount target, unexpected auth prompt, Ctrl-C), all container-side state vanishes except the three bind-mounted files. If A1 (creds file location) or A3 (codex auth path) is wrong, there is no `docker logs`, no `docker cp`, no stopped container to inspect — the user is thrown back to a bare shell with only "it didn't persist" as a symptom, and must re-derive the correct in-container path from scratch (e.g., `docker run -it <img> bash` to go spelunking) since the wrapper offers no debug/no-rm mode.

**Role-Specific Impact:**
- **Human User:** First-run verification (which the plan explicitly assigns as the acceptance mechanism for A1/A2/A3) becomes trial-and-error with no forensic trail if it fails silently (e.g., login "succeeds" in-container but the mounted file stays `{}` because the real path differs).

**Blast Radius:** Contained to developer friction — no data loss beyond re-doing the login — but directly undermines the plan's own verification strategy, which depends on being able to observe what happened.

**Remediation:** For the first verification run only, suggest dropping `--rm` (or adding a `-Debug` switch that omits it) so the container can be inspected post-exit if persistence doesn't work as expected. Cheap to add, not required for the steady-state script.

---

### Finding 4: Concurrent invocations share mutable state with no coordination
**Severity:** Low | **Likelihood:** Low

**Affects Roles:** Human User

**Attack Vector:** Two terminals running `run.ps1` from the same or different project dirs simultaneously both bind-mount the *same* host `~/.claude.json` and creds files. Claude Code / Codex writing session/history state from two live containers concurrently is a last-writer-wins race on plain files — not a container-isolation problem, a shared-mutable-file problem the plan never mentions. Multi-project "use in any project" concurrently is a realistic scenario for a working developer (e.g., two repos open in two terminals) and isn't covered in Success Criteria or Verification Plan (which only tests two *sequential* runs).

**Role-Specific Impact:**
- **Human User:** Session/history corruption or lost writes are possible but silent — no error surfaces, just occasionally-missing history entries.

**Blast Radius:** Low — `~/.claude.json` is session/history/plugin metadata, not the OAuth token itself; worst case is cosmetic data loss, not an auth break.

**Remediation:** Document as a known limitation (not worth engineering a lock for personal single-user tooling) — one line in the README under "Run" is sufficient given the low stakes.

---

### Finding 5: No image-presence or tag-drift guard before `run`
**Severity:** Low | **Likelihood:** Medium

**Affects Roles:** Human User

**Attack Vector:** `run.ps1` assumes the image is already in the local store (explicitly Out of Scope in the plan) but doesn't check for it first — `docker run` on a missing image either fails with a moderately cryptic error or, worse, silently pulls from a registry if a same-named public image exists there (unlikely for `cc-custom:v1` specifically, but the floating `:v1` tag itself is a real drift risk: rebuilding the image with `build.ps1` silently changes what `run.ps1` launches next time, with no digest pin or warning).

**Role-Specific Impact:**
- **Human User:** After a rebuild, `run.ps1` launches whatever `:v1` currently resolves to — could be an in-progress/broken build if `build.ps1` was interrupted, since nothing checks image health before run.

**Blast Radius:** Low — worst case is running a broken image and getting an obvious in-container failure; not silent corruption.

**Remediation:** Optional: `docker image inspect $Image` check with a friendly "image not found — run build.ps1 first" message before invoking `run`. Matches the plan's own deferred "Long-term" opportunity (auto-load) — same root gap, smaller fix.

---

## Role-Based Assumption Challenges

### Human User: "`$env:USERPROFILE` is a normal, stable home directory"
**Challenge:** Corporate-managed Windows 10 machines commonly redirect `USERPROFILE` subfolders (Documents, Desktop) via Group Policy to network shares or OneDrive; while `USERPROFILE` itself usually stays local, environments with roaming profiles or OneDrive Known Folder Move can put `.claude.json`/`.claude-docker` on a synced/network path, adding latency, sync-conflict files, or intermittent lock errors on the bind-mount source.
**Counter-Evidence:** Plan and eval never test on anything but an implied standard Docker Desktop dev box; no mention of enterprise-managed Win10 image profiles.
**If Wrong:** Bind-mount either fails outright (network path syntax issues with Docker Desktop's Linux VM) or works with added latency/OneDrive sync conflicts polluting the creds file.
**Action:** Validate on first run only — low cost given this is personal tooling on a machine the user controls; not worth pre-emptive engineering.

### Human User: "Docker Desktop bind-mount UID/permission mapping just works"
**Challenge:** A2 is flagged as "Medium" confidence in the eval; the plan's own risk table calls it "Low under Docker Desktop" — but Docker Desktop's file-sharing permission model has historically had quirks with WSL2 backend vs Hyper-V backend, and line-ending/permission translation on bind-mounted files (not just directories) specifically for files created fresh by `Set-Content` (which writes UTF-8 **with possible BOM behavior differences** across PowerShell versions) could produce a `.credentials.json`/`auth.json` that the in-container JSON parser chokes on if a BOM sneaks in.
**Counter-Evidence:** `Set-Content -Encoding utf8` in PowerShell 5.1 writes a **BOM-prefixed** UTF-8 file by default (unlike PS7's `utf8NoBOM`) — this is a concrete, verifiable behavior difference the plan doesn't account for. A BOM at the start of `{}` could make some strict JSON parsers fail as soon as the app tries to read what should be valid empty-object JSON.
**If Wrong:** First login write from inside the container either overwrites the file cleanly (masking the issue) or the app errors reading a BOM-prefixed `{}` before any write happens.
**Action:** Validate — trivial to check (`Format-Hex` the created file for `EF BB BF` prefix) before relying on it; if present, switch to `[System.IO.File]::WriteAllText($path, '{}', (New-Object System.Text.UTF8Encoding $false))` for BOM-less output.

### Security: "Individual-file bind-mounts don't shadow siblings" (A5)
**Challenge:** True for the mount mechanics themselves, but the plan's mitigation ("pre-create an empty file") has a race: if two processes (e.g., a stray leftover container from a previous crashed run, still starting up, plus a fresh `run.ps1` invocation) both hit the "file doesn't exist, create it" branch at nearly the same time, one could still observe Docker materializing a directory at the source path if the check-then-create isn't atomic — `Test-Path` + `Set-Content` is a classic TOCTOU gap, though the odds are low for a single-user interactive workflow.
**Counter-Evidence:** No file-locking or atomic-create (`New-Item -ErrorAction Stop` pattern) is used; plain `if (-not (Test-Path ...))` then `Set-Content`.
**If Wrong:** Rare — most likely never triggered in practice given single-user sequential usage — but if triggered, produces the exact "whole-dir shadow" failure mode the plan's entire mount strategy exists to avoid.
**Action:** Reject as a blocking concern — likelihood too low for personal single-session tooling to warrant an atomic-create pattern; note as accepted risk.

---

## Role-Specific Edge Cases & Failures

### Human User: Path with spaces or Unicode in `$Workspace`
**Trigger:** Project directory under e.g. `C:\Users\BA\OneDrive - Company\My Projects\demo`.
**Role Experience:** The plan's Risk notes assert splatting handles spaces "identical to build.ps1" — true for `-v` value *strings* passed as single array elements to native `docker.exe`, since PowerShell's native-command argument passing does correctly preserve embedded spaces within one array element as of PS5.1's argument marshaling. This specific claim likely holds, but it is asserted, not verified in the plan — no test with a spaced path appears in the Verification Plan.
**Recovery:** Possible — but only after the user hits it once and has to debug a `-v` string silently split into two docker args.
**Mitigation:** Add one spaced-path test case to the Manual Verification checklist before calling this done.

### Human User: Windows Terminal vs. legacy `powershell.exe` console vs. VS Code integrated terminal
**Trigger:** `-it` TTY allocation behaves differently across hosts; the plan's Constraints say "run under Windows Terminal" but Success Criteria and Verification Plan don't gate on it — a user running from the PowerShell ISE (no PTY) or an older `conhost.exe`-only console could get a garbled or non-interactive session.
**Role Experience:** TUI renders broken, arrow keys/control sequences misbehave, or `-it` fails to allocate a TTY at all in non-interactive hosts (e.g., invoked from a CI-style script, a VS Code task runner without PTY passthrough).
**Recovery:** Possible — just re-run from a real terminal — but the failure mode is confusing without the constraint being enforced or at least detected (`$Host.Name` check).
**Mitigation:** Optional: check `$Host.UI.SupportsVirtualTerminal` or just document "must run from Windows Terminal or a real console, not ISE/tasks" more prominently in the script header, not just the plan's Constraints section (which isn't user-facing).

### Human User: Image built for wrong engine's runtime (podman rootless vs Docker Desktop)
**Trigger:** User has both docker and podman installed (repo already supports both via `-Engine`); switches between them across sessions.
**Role Experience:** Under podman rootless, A2 (cwd writability) may fail with permission-denied errors the user doesn't expect after having successfully run the same command under docker moments earlier.
**Recovery:** Documented mitigation exists (`--userns=keep-id`) but is not wired into the script even as a commented-out/conditional flag — the user must edit the script by hand after debugging the failure themselves.
**Mitigation:** Add `--userns=keep-id` conditionally when `$Engine -eq 'podman'` proactively, rather than waiting for the user to hit and diagnose the failure. This is a known, named risk in both eval and plan — leaving it as a manual "if this fails" step for a *documented* podman-specific failure mode is an avoidable rough edge.

---

## What's Hidden (Per Role)

**Omissions per role:**
- **Human User:** Not told that credential files, once created, persist indefinitely on host disk with no expiry, no rotation, and no cleanup story (e.g., what happens on logout, on token revocation, on wanting to switch accounts).
- **Security:** Not told (anywhere in plan or eval) how sbx itself protected these same credentials — was sbx's OAuth broker doing anything smarter (scoped socket, ephemeral token, memory-only) that a bind-mounted plaintext file regresses from? This comparison is never made, so the plan can't claim parity, only "not worse than typical dotfile handling."
- **Future Self / Other Machines:** Not told that "any project" still requires the repo to be cloned and the path known — the distribution gap (Finding 2) is invisible unless explicitly hunted for, since the plan's own language ("Users switch from `sbx run --template …` to `./run.ps1`") implies frictionless parity that isn't actually delivered.

**Tradeoffs per role:**
- **Human User:** Trades sbx's abstraction (whatever auth brokering it did) for full manual credential lifecycle ownership — simpler mechanism, but now the user's own responsibility to not leak `.claude-docker\`/`.codex-docker\`.
- **Security:** Trades "unknown but possibly-better" sbx credential handling for "known, simple, plaintext-on-disk" — arguably more auditable, but strictly more exposed to any co-located process.

---

## Scale & Stress (Role Impact)

**At 10x (multiple projects/day, normal solo dev cadence):**
- **Human User:** Path-typing friction (Finding 2) becomes actively annoying without an alias; still functionally fine.
- **Future Self / Other Machines:** No change — this scale doesn't stress the design, it stresses the same single gap repeatedly.

**At 100x (team adoption / multiple people using this repo's images):**
- **Human User (now plural):** The shared-repo-path assumption breaks down entirely — every teammate needs their own clone at their own path, and the README's `<repo>\claude\run.ps1` literal-path examples become actively misleading without a "clone this repo, then..." framing.
- **Security:** Multiple users' credential files coexist fine (each keyed to their own `%USERPROFILE%`), so this specific risk doesn't compound — but the plan was never designed with multi-user reuse in mind (explicitly out of scope: "personal dev tooling"), so 100x is out of this plan's intended envelope and shouldn't be over-weighted in the verdict.

---

## Remediation

### Must Fix (Before Proceeding)
- None — no finding rises to a hard blocker for personal single-user tooling as scoped.

### Should Fix (Before Production / Before Calling This Done)
- **Credential exposure undocumented** (affects: Human User, Security) → Add a one-paragraph security note in both READMEs: these mounted files carry live OAuth tokens, treat like SSH keys, don't share the `.claude-docker`/`.codex-docker` dirs.
- **"Any project" distribution gap** (affects: Human User, Future Self) → Add a README snippet showing a PowerShell profile alias/function so the stated goal ("use in any project") is actually achieved day-to-day, not just per-invocation-with-full-path.
- **PS5.1 `Set-Content -Encoding utf8` BOM risk** (affects: Human User) → Verify empirically (hex-dump the created `{}` file) before relying on it; switch to BOM-less write if a BOM is present and any consuming JSON parser is strict.
- **podman `--userns=keep-id` left as manual fallback** (affects: Human User) → Wire conditionally when `$Engine -eq 'podman'` since the failure mode is already known and named, not hypothetical.

### Monitor
- **Concurrent-run file races** (affects: Human User) → Revisit only if actual data loss is observed; not worth engineering for single-user sequential usage today.
- **Image tag drift (`:v1` floating tag)** (affects: Human User) → Revisit if a broken-rebuild-then-run incident actually occurs; cheap to add an existence check later.
- **Enterprise-redirected `USERPROFILE`** (affects: Human User) → Irrelevant unless the user's machine situation changes (e.g., new corporate policy); not applicable to current known environment.

---

## Final Assessment

**Soundness:** Solid with Caveats
**Risk:** Low (personal single-user tooling; no production/multi-tenant exposure; credential-file risk is real but bounded to local-machine co-located processes)
**Readiness:** Ready with Fixes

**Per-Role Readiness:**
- **Human User:** Ready — the mechanism works as designed for the stated Success Criteria; the "any project" friction and credential-hygiene gaps are real but don't block using it today.
- **Future Self / Other Machines:** Not Ready as a distribution story — works fine on this machine, but "any project, any machine" needs the alias/PATH follow-up to actually hold.
- **Security:** Ready with Caveats — no worse than typical local dotfile-based credential storage, but the plan should say so explicitly rather than leaving the comparison to sbx implicit and unexamined.

**Conditions for Approval:**
- [ ] Security note on credential file exposure added to both READMEs (for Human User, Security)
- [ ] BOM check performed on `Set-Content`-created files before first real login (for Human User)
- [ ] podman `--userns=keep-id` wired conditionally rather than left as a manual fallback (for Human User)

**No-Go If:**
- [ ] The five unverified assumptions (A1-A5) are batch-executed without checking each in isolation first — the `--rm` lifecycle means a compound failure across multiple assumptions at once is hard to diagnose (impacts Human User)
