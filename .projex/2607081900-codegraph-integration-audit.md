# Install Audit: @colbymchenry/codegraph v1.3.0

**Verdict: APPROVED ✅**
**Audit tier:** Standard
**Subject type:** 1 (registry-package) — npm package `@colbymchenry/codegraph`; the CLI-binary install.sh path (Type 7) for the opencode/Alpine image is a secondary distribution channel of the same audited project, not a separate subject.
**Date:** 2026-07-08

## Summary
CodeGraph is an MIT-licensed, single-maintainer (colbymchenry) local code-intelligence MCP server/CLI — builds a SQLite knowledge graph of a repo for AI coding agents (Claude Code, Codex, opencode, Cursor, etc.). 100% local processing, no API keys, no data leaves the machine per docs; ships opt-out anonymous usage telemetry (`codegraph telemetry off` / `DO_NOT_TRACK=1`). Actively maintained (pushed same day as audit), 41 npm releases, no known CVEs/advisories.

## Security
| Area | Finding |
|------|---------|
| CVEs / Advisories | None found (OSV: 0 results; GitHub Security Advisories: 0) |
| Supply Chain Risk | Low-Medium — single maintainer (bus-factor risk), but high adoption/visibility acts as a deterrent; `install.sh`/`install.ps1` download release tarballs over HTTPS from `github.com/colbymchenry/codegraph/releases` with **no checksum/signature verification** in the script itself |
| Permissions | Runs as the same OS user as the agent (no elevated privileges required); starts a local file watcher (inotify/FSEvents) scoped to the indexed project directory |
| Telemetry/Privacy | Anonymous, aggregated daily, opt-out (`codegraph telemetry off`, `DO_NOT_TRACK=1`, `CODEGRAPH_TELEMETRY=0`); documented field list in `TELEMETRY.md`; no code/paths/symbol names/queries collected per docs |
| Dependency Risk | Low — npm deps are small, well-known (`commander`, `@clack/prompts`, `web-tree-sitter`/`tree-sitter-wasms` for WASM-based parsing — no native/compiled addons to build); no `postinstall` script in `package.json` (only `preuninstall`, which runs the project's own `dist/bin/uninstall.js` cleanup) |

## Reliability
| Area | Finding |
|------|---------|
| Maintenance | Active — latest commit/release the same day as this audit (2026-07-07/08), ~41 npm versions since first publish |
| Last Release | v1.3.0, 2026-07-07 (release cadence: several per week recently) |
| Publisher Trust | Unverified individual maintainer, but high-visibility project (58.5k GitHub stars, 104k npm downloads/week) |
| Adoption | 104,177 npm downloads (last week), 58,532 GitHub stars, 3,620 forks |
| License | MIT — permissive, no compatibility concerns |

## Audit Coverage

**Audit confidence (coverage):** High — registry, GitHub, and vulnerability-database lookups all returned live data; only gap is that install-script checksum verification isn't independently confirmed beyond reading the script source.

| Check | Status | Source or notes |
|-------|--------|-----------------|
| Registry metadata lookup | Done | npm registry API |
| Download/adoption stats | Done | npmjs.org downloads API |
| GitHub repo metadata | Done | GitHub REST API |
| CVE / advisories | Done, 0 results | OSV.dev, GitHub Security Advisories API |
| Install script review | Done | `install.sh` read directly from repo clone |
| package.json script review | Done | no `postinstall`, only `preuninstall` |
| Checksum/signature verification of releases | Not available | not published by the project; not independently verifiable without downloading + comparing against a separate trust anchor |

## Risk Flags
- [MEDIUM] Single maintainer — if the account is compromised, both the npm package and GitHub release binaries are a single point of failure. Mitigated by high project visibility (likely to surface issues quickly) and MIT license (source is auditable).
- [LOW] `install.sh`/`install.ps1` fetch release tarballs without a published checksum/signature to verify against — relying on GitHub/npm registry transport security (HTTPS) and account integrity rather than independent artifact verification.
- [LOW] Telemetry is on by default (opt-out, not opt-in) — acceptable given documented scope (aggregated, anonymous, no code/path content) and multiple documented off-switches.

## Alternatives
No better alternative identified for this specific "pre-built local code graph for AI agents" niche — closest comparators (Sourcegraph, ctags/cscope, LSP-based tools) either require a server/subscription or don't produce agent-oriented context bundles the same way.

## Conditions (n/a — approved, not conditional)
None required to proceed; recommendations below are hardening, not blockers.

## Recommendation
Approved for use in the claude/codex/opencode sandbox images. Pin to the currently audited version (`1.3.0` / `v1.3.0`) rather than tracking `latest` in the Dockerfiles, since these are shared, versioned build artifacts — re-audit on a future version bump. Telemetry can stay on (it's anonymous and off-switched easily) unless the team has a blanket no-telemetry policy for sandbox tooling.

## Post-Install Checklist
- [x] Pin to exact audited version (`@colbymchenry/codegraph@1.3.0` for npm; `CODEGRAPH_VERSION=v1.3.0` for install.sh) — apply in the Dockerfiles being edited
- [ ] Verify checksum/signature if provided — none published; rely on HTTPS + GitHub/npm account trust
- [ ] Check for unexpected lock file entries after install (not applicable — global CLI install, no project lock file touched)
- [x] Review post-install script output if applicable — no postinstall script exists
- [ ] Re-audit on major version bump or maintainer change

**Sources:** https://github.com/colbymchenry/codegraph (cloned locally), https://registry.npmjs.org/@colbymchenry/codegraph, https://api.npmjs.org/downloads/point/last-week/@colbymchenry/codegraph, https://api.github.com/repos/colbymchenry/codegraph, https://api.github.com/repos/colbymchenry/codegraph/releases, https://api.github.com/repos/colbymchenry/codegraph/security-advisories, https://api.osv.dev/v1/query
