# Install Audit: @earendil-works/pi-coding-agent v0.80.9

**Verdict: APPROVED ✅ (conditional on pinning ≥0.78.1)**
**Audit tier:** Standard
**Subject type:** 1 (registry-package) — npm scoped package `@earendil-works/pi-coding-agent`, the CLI-binary install (`npm install -g`) is the same audited distribution channel; the `curl https://pi.dev/install.sh | sh` alternative installs the identical published artifact.
**Date:** 2026-07-17

## Summary
Pi is an MIT-licensed, multi-provider coding-agent CLI (binary `pi`) from earendil-works — a monorepo with 71.8k GitHub stars, maintained by a 3-person team that includes high-profile developers (`badlogic`/Mario Zechner, `mitsuhiko`/Armin Ronacher of Flask/Sentry fame, `rwachtler`). 860k weekly npm downloads, 32 published versions, active development (pushed same day as this audit). Four GHSA advisories exist against earlier versions (all fixed by 0.78.1/0.79.0); the version being pinned for this build (0.80.9) postdates every fix.

## Security
| Area | Finding |
|------|---------|
| CVEs / Advisories | 4 GHSA advisories found, **all patched**: GHSA-7v5m-pr3q-6453 (XSS in HTML session export, LOW, fixed 0.78.1), GHSA-jfgx-wxx8-mp94 (predictable tmp extension-install path → local code exec on shared hosts, HIGH, fixed 0.78.1), GHSA-mqxh-6gq7-558m (project-local extensions loaded without trust prompt, MODERATE, fixed 0.79.0), GHSA-r95r-rj6r-c39x (auth.json brief non-0600 window on write, LOW, fixed 0.78.1). None affect ≥0.78.1/0.79.0; the pinned version (0.80.9) is unaffected by all four. |
| Supply Chain Risk | Low — reputable, well-known maintainers (Armin Ronacher, Mario Zechner); no install/postinstall scripts (`installScripts: null` in registry metadata); GitHub-reviewed security-advisory process with fast (days) fix turnaround shows a functioning disclosure pipeline, not just absence of reports |
| Permissions | Runs as the invoking OS user, same class of tool as claude/opencode/cursor already in this repo — no elevated privileges required. By design (per project docs) it runs with full read/write/bash permissions in whatever directory it's started in; this is the reason it's being containerized here, not a flaw |
| Telemetry/Privacy | Anonymous install/update ping to `pi.dev/api/report-install`, opt-out via `enableInstallTelemetry: false` or `PI_TELEMETRY=0`; separate update-check ping, disable via `PI_SKIP_VERSION_CHECK=1` or `--offline`/`PI_OFFLINE=1` for both |
| Dependency Risk | Low-Medium — 18 direct deps, mostly small well-known libraries (chalk, diff, glob, semver, yaml, undici); no known-malicious packages in the tree per this lookup |

## Reliability
| Area | Finding |
|------|---------|
| Maintenance | Active — repo pushed the same day as this audit; 32 npm versions since first publish (2026-05-07 under this scope, migrated from an earlier `@mariozechner/pi-coding-agent` scope) |
| Last Release | 0.80.9, published 2026-07-17 (0 days before audit) |
| Publisher Trust | High — 3 named maintainers, two independently well-known in the OSS community (Armin Ronacher, Mario Zechner) |
| Adoption | 860,756 npm downloads/week; 71,805 GitHub stars; 8,852 forks |
| License | MIT — permissive, no compatibility concerns |

## Audit Coverage

**Audit confidence (coverage):** High — registry, GitHub, and OSV lookups all returned live data with no gaps.

| Check | Status | Source or notes |
|-------|--------|-----------------|
| Registry metadata lookup | Done | `scripts/registry-lookup.ps1 npm @earendil-works/pi-coding-agent 0.80.9` |
| Typosquat / name verification | Done | scoped package name matches the GitHub org (`earendil-works`) exactly |
| Download/adoption stats | Done | npm registry API (weekly downloads, version count) |
| GitHub repo metadata | Done | GitHub REST API |
| CVE / advisories | Done, 4 found, all patched pre-0.80.9 | OSV.dev |
| Install script review | Done | `installScripts: null` in registry metadata (no npm lifecycle scripts) |

## Risk Flags
- [LOW] One of the four historical advisories (GHSA-jfgx-wxx8-mp94) was rated HIGH severity, but only affects `--extension`/`-e` with npm/git sources on **shared multi-user Linux hosts** with a shared writable tmpdir — not applicable to this repo's per-container, single-user (`agent`, uid 1000) sandbox model, and fixed regardless in 0.78.1.
- [LOW] Package scope migrated once already (`@mariozechner/pi-coding-agent` → `@earendil-works/pi-coding-agent`); the old scope has no patched releases. Dockerfile must install the **new** scope only (`@earendil-works/pi-coding-agent`), never the deprecated one.
- [LOW] By design, pi runs with unrestricted read/write/bash tool access in its working directory (no built-in sandboxing) — this is the documented reason to containerize it (see upstream `packages/coding-agent/docs/containerization.md`), consistent with why this suite exists.

## Alternatives
No better alternative identified for this specific niche (multi-provider TUI coding-agent CLI) that isn't already covered by the claude/opencode/cursor suites in this repo.

## Conditions
- Pin to an exact version **≥ 0.78.1** (all four advisories fixed by 0.78.1, one more by 0.79.0). This audit pins to **0.80.9** (current latest at audit time) — re-audit on a future major/minor bump per the same policy already applied to codegraph/opencode in this repo.
- Install only the `@earendil-works/pi-coding-agent` scope — never the deprecated `@mariozechner/pi-coding-agent`.

## Recommendation
Approved for use in a new `pi/` sandbox suite, pinned to `@earendil-works/pi-coding-agent@0.80.9` (ARG in the Dockerfile, same pattern as `OPENCODE_VERSION`/`CODEGRAPH_VERSION` elsewhere in this repo). No blockers; the one HIGH-severity historical CVE doesn't apply to this repo's single-user-per-container model and is fixed regardless at the pinned version.

## Post-Install Checklist
- [x] Pin to exact audited version (`@earendil-works/pi-coding-agent@0.80.9`) — apply in `pi/Dockerfile`
- [ ] Verify checksum/signature if provided — none published; rely on npm registry HTTPS + maintainer account trust
- [ ] Check for unexpected lock file entries after install — n/a, global CLI install, no project lock file touched
- [x] Review post-install script output if applicable — no install/postinstall scripts exist (`installScripts: null`)
- [ ] Re-audit on major version bump or maintainer change

**Sources:** https://github.com/earendil-works/pi, https://registry.npmjs.org/@earendil-works/pi-coding-agent, https://api.github.com/repos/earendil-works/pi, https://api.github.com/repos/earendil-works/pi/security-advisories, https://api.osv.dev/v1/query (GHSA-7v5m-pr3q-6453, GHSA-jfgx-wxx8-mp94, GHSA-mqxh-6gq7-558m, GHSA-r95r-rj6r-c39x)
