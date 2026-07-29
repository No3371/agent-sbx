# Install Audit: @tintinweb/pi-subagents v0.14.1

**Verdict: APPROVED ✅**
**Audit tier:** Quick
**Subject type:** 1 (registry-package) — npm package, installed via `pi install npm:@tintinweb/pi-subagents` (pi's package manifest declares `extensions`/`skills` fields it loads, same shape as `context-mode`; pi.dev itself flags "Pi packages can execute code and influence agent behavior. Review the source before installing third-party packages.")
**Date:** 2026-07-17

## Summary
Brings Claude Code-style autonomous sub-agent orchestration to pi (`spawn_subagent`/`steer_subagent` tools). Maintained by `tintinweb` — a well-known, high-profile security researcher/tool author (ConsenSys Diligence, prolific VS Code/Burp extension author). MIT licensed, no install scripts, small clean dependency tree.

## Security
| Area | Finding |
|------|---------|
| CVEs / Advisories | None found (OSV: 0 results; GitHub Security Advisories: 0) |
| Supply Chain Risk | Low — single maintainer, but a well-known, long-tenured OSS security-tooling author (established reputation predates this package by years) |
| Permissions | Runs inside the pi process (same trust model as any pi extension); registers subagent-management tools, no unusual system access beyond what pi itself already has |
| Telemetry/Privacy | None observed |
| Dependency Risk | Low — 3 direct deps (`@sinclair/typebox`, `croner`, `nanoid`), all small/well-known, no native addons |

## Reliability
| Area | Finding |
|------|---------|
| Maintenance | Active — pushed 2026-07-14 (3 days before audit), 43 versions since first publish 2026-03-05 |
| Last Release | 0.14.1, 2026-07-14 |
| Publisher Trust | High — named, long-established individual maintainer |
| Adoption | 8,633 downloads/week; 647 GitHub stars, 132 forks |
| License | MIT — permissive |

## Audit Coverage

**Audit confidence (coverage):** High — registry, GitHub, and OSV lookups all returned live data.

| Check | Status | Source or notes |
|-------|--------|-----------------|
| Registry metadata lookup | Done | npm registry API |
| CVE / advisories | Done, 0 results | OSV.dev, GitHub Security Advisories API |
| Install script review | Done | `installScripts: null` |
| GitHub repo metadata | Done | GitHub REST API |

## Risk Flags
- [LOW] Single maintainer (bus-factor risk), mitigated by the maintainer's established public reputation and active recent commit history.

## Recommendation
Approved for the `pi/` sandbox suite. Pin to `0.14.1` (current at audit time) when adding the `pi install npm:@tintinweb/pi-subagents@0.14.1` build step.

## Post-Install Checklist
- [x] Pin to exact audited version (`@tintinweb/pi-subagents@0.14.1`)
- [x] Review post-install script output if applicable — no install scripts exist
- [ ] Re-audit on major version bump or maintainer change

**Sources:** https://github.com/tintinweb/pi-subagents, https://registry.npmjs.org/@tintinweb/pi-subagents, https://api.github.com/repos/tintinweb/pi-subagents, https://api.osv.dev/v1/query
