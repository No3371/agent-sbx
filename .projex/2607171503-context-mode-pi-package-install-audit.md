# Install Audit: context-mode v1.0.169 (pi package)

**Verdict: APPROVED ✅ (conditional — see Conditions)**
**Audit tier:** Standard
**Subject type:** 1 (registry-package) — npm package `context-mode`, installed via `pi install npm:context-mode`. Same underlying project already runs in this repo's `claude/` suite as a Claude Code plugin (marketplace `mksglu/claude-context-mode`); this audit covers its **pi extension adapter** specifically (`.pi/extensions/context-mode/`, bundled in the same npm package).
**Date:** 2026-07-17

## Summary
Multi-agent "context compaction" tool — sandboxed code execution (`ctx_execute`), an FTS5 knowledge base, and intent-driven search, aimed at cutting how much raw tool/command output enters an agent's context window. Ships native adapters for ~18 agent platforms including Pi (confirmed via its own platform-compatibility table: MCP/native tools, PreToolUse/PostToolUse/SessionStart/PreCompact hooks, and utility commands all supported for Pi). Single maintainer (`mksglu`), very high adoption (19k GitHub stars — far above the other three packages in this batch), Elastic License 2.0 (source-available, not OSI-approved — see Conditions).

This is the **same package** already vendored into `claude/` via the build-time-install pilot documented in `claude/.projex/2607100235-context-mode-build-time-install-pilot-plan.md` — that prior work already established: (a) it has a `better-sqlite3` native dependency requiring a Linux rebuild at build time, (b) its own hook self-heal logic rewrites host-absolute paths into `settings.json`, which is exactly why the claude/ suite build-time-installs it fresh in-container rather than vendoring the host's copy.

## Security
| Area | Finding |
|------|---------|
| CVEs / Advisories | None found (OSV: 0 results; GitHub Security Advisories: 0) |
| Supply Chain Risk | Medium — single maintainer for a very widely-adopted tool (19k stars) that runs `ctx_execute`-style sandboxed code execution and reads/writes an agent's tool-call history; higher blast radius than a typical extension if the maintainer account were compromised, offset by high visibility (large user base likely to surface issues fast) |
| Permissions | By design, sits in the tool-call path (PreToolUse/PostToolUse hooks) and can execute arbitrary code via its own sandbox (`ctx_execute`/`ctx_batch_execute`) — this is the tool's stated purpose, not a flaw, but it is the most privileged of the four packages audited in this batch |
| Telemetry/Privacy | Package's own docs describe deliberate hardening: `ctx_fetch_and_index` blocks `file://`/`data://` schemes and cloud-metadata/link-local ranges by default (DNS-rebinding defense), and `tool_input` for MCP calls is regex-redacted (`authorization`, `api_key`, `token`, `password`, etc. → `[REDACTED]`) before being persisted to its session DB — a privacy-conscious design, not zero-telemetry by default (session content is persisted locally to its own FTS5 store) |
| Dependency Risk | Medium — 8 direct deps; `better-sqlite3` is a **native addon** (needs compilation via `node-gyp`/Python at install time — same requirement already handled in this repo's `claude/Dockerfile` native-module rebuild loop). Others (`@modelcontextprotocol/sdk`, `zod`, `turndown`) are small/well-known |
| Install scripts | **Has a `postinstall` script** (`node scripts/postinstall.mjs`) — the one package in this batch that isn't script-free. Its own repo shows this is a self-heal/config-repair step (`scripts/heal-better-sqlite3.mjs`, `scripts/heal-installed-plugins.mjs`), consistent with the "self-heal" behavior already observed and documented in this repo's `claude/.projex/2607091752-context-mode-plugin-path-mapping-memo.md`. Review its output on first build. |

## Reliability
| Area | Finding |
|------|---------|
| Maintenance | Very active — pushed 2026-07-16 (1 day before audit), 223 published versions since 2026-02-23 (extremely high release cadence) |
| Last Release | 1.0.169, 2026-06-30 (npm registry timestamp) / repo pushed 2026-07-16 |
| Publisher Trust | Unverified individual maintainer (`mksglu`), but the highest adoption of any package in this batch by a wide margin |
| Adoption | 13,536 downloads/week on the bare `context-mode` npm package (separate count from its Claude Code plugin-marketplace distribution channel already used in `claude/`); 19,010 GitHub stars, 1,338 forks |
| License | **Elastic License 2.0** — source-available, NOT an OSI-approved open-source license. Permits use but restricts offering the software as a hosted/managed service to third parties and circumventing license keys. No conflict for this repo's use case (running it as a dev-sandbox tool, not reselling it as a service), but flagged since it differs from the MIT license on every other package in this repo's dependency set. |

## Audit Coverage

**Audit confidence (coverage):** High — registry, GitHub, and OSV lookups all returned live data; this repo also has substantial first-hand operational history with this exact package (`claude/.projex/2607091752-*`, `2607100201-*`, `2607100235-*`, `closed/2607100248-*`) that independently corroborates the native-dependency and self-heal findings above.

| Check | Status | Source or notes |
|-------|--------|-----------------|
| Registry metadata lookup | Done | npm registry API |
| Typosquat / name verification | Done | matches `pi.dev/packages/context-mode` listing and the already-vendored `claude/` plugin exactly |
| CVE / advisories | Done, 0 results | OSV.dev, GitHub Security Advisories API |
| GitHub repo metadata | Done | GitHub REST API |
| Install script review | Done — **has one** | registry metadata (`postinstall: node scripts/postinstall.mjs`); corroborated by this repo's own prior operational history with the package |
| License review | Done | Elastic-2.0, source-available not OSI — flagged, not blocking |

## Risk Flags
- [MEDIUM] Single maintainer for a tool with unusually broad reach into the agent's tool-call path and a large user base — compromise impact would be high, though likelihood is mitigated by visibility.
- [MEDIUM] Has a `postinstall` script (only package in this batch that does) — review its output the first time `pi install npm:context-mode` runs in the Dockerfile build log.
- [LOW] Elastic-2.0 license, not OSI-approved — no practical restriction for this repo's use (internal dev sandbox, not a resold hosted service), but worth knowing if this repo's own license posture ever needs auditing.
- [LOW] `better-sqlite3` native dependency needs a Linux rebuild at container-build time — already solved once in this repo (`claude/Dockerfile`'s native-module `npm install` loop); the `pi/` Dockerfile needs the equivalent (build-essential + python3, both already present in `pi/Dockerfile`'s base layer).

## Alternatives
No alternative identified that does the same "cut tool-output bytes from the agent's context" job across this many agent platforms including Pi natively; this repo's own `codegraph` skill workaround (see `pi/skills/codegraph/SKILL.md`) solves a different problem (code-symbol graph, not general tool-output/context management) and is not a substitute.

## Conditions
- Pin to the exact audited version (`context-mode@1.0.169`) in the Dockerfile `RUN pi install` step, same policy as the other three packages in this batch.
- `pi install` must run where npm's native-addon toolchain (Python + a C/C++ compiler) is available, so `better-sqlite3` rebuilds for Linux instead of failing or silently loading a broken binary — verify in the build log, don't just assume.
- Review the `postinstall.mjs` output the first time this lands in a build.

## Recommendation
Approved for the `pi/` sandbox suite as the pi-native equivalent of what `claude/` already runs. Since pi has no separate "plugin marketplace" concept (unlike Claude Code), the pi install is simpler than the `claude/` pilot's two-step `marketplace add` + `plugin install` — a single `pi install npm:context-mode@1.0.169` covers it.

## Post-Install Checklist
- [x] Pin to exact audited version (`context-mode@1.0.169`)
- [ ] Verify checksum/signature if provided — none published; rely on npm registry HTTPS + maintainer account trust (same posture already accepted for this exact package in `claude/`)
- [ ] Check build log for `postinstall.mjs` output and confirm `better-sqlite3` rebuilds cleanly for Linux
- [x] Review post-install script output if applicable — flagged above as a condition, not yet run
- [ ] Re-audit on major version bump or maintainer change

**Sources:** https://github.com/mksglu/context-mode, https://registry.npmjs.org/context-mode, https://api.github.com/repos/mksglu/context-mode, https://api.osv.dev/v1/query, https://pi.dev/packages/context-mode, this repo's `claude/.projex/2607091752-context-mode-plugin-path-mapping-memo.md`, `claude/.projex/2607100201-build-time-plugin-install-for-sandbox-images-proposal.md`, `claude/.projex/2607100235-context-mode-build-time-install-pilot-plan.md`, `claude/.projex/closed/2607100248-context-mode-build-time-install-pilot-patch.md`
