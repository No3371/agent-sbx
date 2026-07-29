# Install Audit: pi-cursor-sdk v0.1.59

**Verdict: APPROVED ✅**
**Audit tier:** Quick
**Subject type:** 1 (registry-package) — npm package, installed via `pi install npm:pi-cursor-sdk`; pi.dev flags all pi packages as able to "execute code and influence agent behavior."
**Date:** 2026-07-17

## Summary
Provider extension backed by `@cursor/sdk` — registers Cursor's `composer-2-5` local/cloud models as pi model targets. Requires a Cursor SDK API key (`CURSOR_API_KEY` env var or `/login`), separate from Cursor Agent CLI/Desktop auth. MIT licensed, no install scripts, small dependency surface (`@cursor/sdk`, `@modelcontextprotocol/sdk`).

## Security
| Area | Finding |
|------|---------|
| CVEs / Advisories | None found (OSV: 0 results; GitHub Security Advisories: 0) |
| Supply Chain Risk | Low-Medium — single maintainer, moderate adoption; depends on the official `@cursor/sdk` package (Cursor/Anysphere-published) |
| Permissions | Only activates when a Cursor SDK API key is configured; passes the key explicitly to `@cursor/sdk` per its own docs — does not read Cursor Agent CLI/Desktop credentials |
| Telemetry/Privacy | None observed beyond what `@cursor/sdk` itself does; package's own docs explicitly warn not to store the API key in its non-secret `cursor-sdk.json` state file |
| Dependency Risk | Low — 2 direct deps, both well-known/official (`@cursor/sdk`, `@modelcontextprotocol/sdk`); no native addons |

## Reliability
| Area | Finding |
|------|---------|
| Maintenance | Active — pushed 2026-07-17 (same day as audit), 61 versions since first publish 2026-05-05 |
| Last Release | 0.1.59, 2026-07-17 |
| Publisher Trust | Unverified individual maintainer (`fitchmultz`), moderate adoption |
| Adoption | 1,749 downloads/week; 225 GitHub stars, 19 forks |
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
- [LOW] Single, unverified maintainer — lowest adoption of the four packages audited in this batch. No red flags found, but bus-factor risk is real.
- [LOW] Requires a live Cursor SDK API key to do anything — inert without one, so the blast radius of a compromised package is bounded by whatever that key can reach (Cursor model inference only, per its documented scope).

## Recommendation
Approved for the `pi/` sandbox suite, conditional on treating `CURSOR_API_KEY` with the same care as other provider keys (never baked into the image; forwarded only at container-run time). Pin to `0.1.59` (current at audit time).

## Post-Install Checklist
- [x] Pin to exact audited version (`pi-cursor-sdk@0.1.59`)
- [x] Review post-install script output if applicable — no install scripts exist
- [ ] Re-audit on major version bump or maintainer change

**Sources:** https://github.com/fitchmultz/pi-cursor-sdk, https://registry.npmjs.org/pi-cursor-sdk, https://api.github.com/repos/fitchmultz/pi-cursor-sdk, https://api.osv.dev/v1/query
