# Install Audit: pi-web-access v0.13.0

**Verdict: APPROVED ✅**
**Audit tier:** Quick
**Subject type:** 1 (registry-package) — npm package, installed via `pi install npm:pi-web-access`; pi.dev flags all pi packages as able to "execute code and influence agent behavior."
**Date:** 2026-07-17

## Summary
Web search / URL fetch / GitHub repo clone / PDF extraction / video-understanding toolset for pi. Works zero-config via Exa's MCP (no API key required); optional keys for OpenAI/Brave/Exa direct/Perplexity/Gemini/Tavily/Parallel/Cloudflare improve or diversify search. MIT licensed, no install scripts, moderate dependency surface, all well-known libraries (readability, linkedom, turndown, unpdf).

## Security
| Area | Finding |
|------|---------|
| CVEs / Advisories | None found (OSV: 0 results; GitHub Security Advisories: 0) |
| Supply Chain Risk | Low-Medium — single maintainer, but highest adoption of the three non-context-mode packages audited here |
| Permissions | Outbound network access is the whole point (web search/fetch) — same class of tool as `agent-browser`/`WebFetch` already in this repo's other suites; optional API keys stored in `~/.pi/web-search.json` or env vars, same pattern as pi's own provider auth |
| Telemetry/Privacy | None observed in package docs; a fetched page's content obviously leaves the sandbox to whichever search/fetch provider is configured (same trust model as any web-search tool) |
| Dependency Risk | Low — 5 direct deps (`@mozilla/readability`, `linkedom`, `p-limit`, `turndown`, `unpdf`), all small/well-known, no native addons in the core package (video-frame extraction is an *optional* external binary — `ffmpeg`/`yt-dlp` — not a package dependency) |

## Reliability
| Area | Finding |
|------|---------|
| Maintenance | Active — pushed 2026-06-25 (22 days before audit), 19 versions since first publish 2026-01-06 (repo itself created 2026-01-28) |
| Last Release | 0.13.0, 2026-06-25 |
| Publisher Trust | Unverified individual maintainer (`nicopreme`/`nicobailon`), good adoption |
| Adoption | 27,072 downloads/week; 809 GitHub stars, 133 forks |
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
- [LOW] Single, unverified maintainer.
- [LOW] Optional `ffmpeg`/`yt-dlp` binaries for video-frame extraction are not needed for core web search/fetch — skip installing them unless video analysis is actually wanted, to keep the image's attack surface and size down.

## Recommendation
Approved for the `pi/` sandbox suite. Pin to `0.13.0` (current at audit time; requires pi v0.37.3+, satisfied by this suite's pinned pi 0.80.9). Optional API keys (never baked into the image) follow the same env-var-forwarding pattern `run.ps1` already uses for provider keys.

## Post-Install Checklist
- [x] Pin to exact audited version (`pi-web-access@0.13.0`)
- [x] Review post-install script output if applicable — no install scripts exist
- [ ] Re-audit on major version bump or maintainer change

**Sources:** https://github.com/nicobailon/pi-web-access, https://registry.npmjs.org/pi-web-access, https://api.github.com/repos/nicobailon/pi-web-access, https://api.osv.dev/v1/query
