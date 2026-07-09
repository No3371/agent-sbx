---
Created: 2026-07-09
Author: eval-projex (subagent)
Subject: Should Dockerfile fetch agent-browser SKILL.md stub via `npx skills add vercel-labs/agent-browser` at build time, instead of vendoring the static copy at skills/agent-browser/SKILL.md?
Type: Proposal
Tier: Quick Take
Lenses Applied: Constraint Mapping, Inversion
Related Projex: .projex/2607081900-codegraph-integration-audit.md (referenced by Dockerfile comment, not read — establishes the repo's version-pin rationale for build artifacts)
---

## Executive Summary

Verified primary sources: Dockerfile (`/workspace/Dockerfile`), vendored stub (`/workspace/skills/agent-browser/SKILL.md`), and upstream `vercel-labs/agent-browser` raw stub on `main`. The vendored copy is **byte-for-byte identical** to upstream's current stub — no drift exists today. Upstream's own text confirms the stub is designed to be release-invariant ("The content in this stub cannot change between releases, which is why it just points at `skills get core`"); the actual version-sync upstream advertises happens at *runtime* via `agent-browser skills get core`, not via this file. Switching to `npx skills add` at build time would add an unpinned, unauditable network fetch (no version/ref pin equivalent to `AGENT_BROWSER_VERSION`) for a file that, by upstream's own design, has nothing to sync. Recommendation: **keep vendoring**, do not pull at build time.

## Analysis

**Finding 1 — No drift, so nothing to fix.** (Confidence: High — direct diff of both files)
`/workspace/skills/agent-browser/SKILL.md` (read in full) matches `https://raw.githubusercontent.com/vercel-labs/agent-browser/main/skills/agent-browser/SKILL.md` verbatim, including the "Observability Dashboard" section — this is upstream content, not a local customization that auto-fetch would clobber. The problem this change would solve ("stub going stale") does not currently exist.

**Finding 2 — The staleness upstream warns about isn't this file's problem.** (Confidence: High — direct quote, upstream README via WebFetch)
Upstream's install docs warn: "Do not copy `SKILL.md` from `node_modules` as it will become stale" — but the *reason* they give is that the stub's job is only to redirect to `agent-browser skills get core`, which "serves skill content that always matches the installed [CLI] version." The stub's own text says its content "cannot change between releases." So the version-alignment upstream is selling with `npx skills add` is already achieved in this repo by the CLI-version pin (`AGENT_BROWSER_VERSION=0.31.1`, Dockerfile lines 26-29, 61) plus the runtime `agent-browser skills get core` call — the stub file itself has no version to go stale against.

**Finding 3 — `npx skills add` would contradict, not extend, this Dockerfile's pin policy.** (Confidence: Medium — inferred; did not verify whether `skills add` supports pinning to a specific upstream ref/tag)
Dockerfile's stated policy (comment at lines 24-26): "Pinned, not @latest — a shared build artifact should track an audited version explicitly." `AGENT_BROWSER_VERSION` and `CODEGRAPH_VERSION` both follow this. `npx skills add vercel-labs/agent-browser` as documented upstream carries no version qualifier — it would fetch whatever's on the default branch at build time, unpinned, which is the same non-determinism the repo explicitly rejects elsewhere. If `skills add` does support a ref pin (unverified), the case weakens somewhat, but the current vendored file plus the code comment already gives an auditable, diffable, offline-reviewable equivalent of a pin — a `git diff`-visible artifact vs. a build-time fetch whose exact content isn't visible without running the build.

**Finding 4 — Build-time network dependency.** (Confidence: High — direct read, Dockerfile)
The build already depends on network for many steps (apt, NodeSource, Microsoft packages, Go tarball, two `npm install -g` calls, plugin `npm install`). Adding one more `npx` fetch would not introduce a *qualitatively* new class of risk to this build. This criterion is close to a wash — it doesn't favor either approach strongly, but it also means "avoids a network call" is not a real argument for the change, since the build isn't network-independent regardless.

**Finding 5 — Maintenance burden is asymmetric but low either way.** (Confidence: Medium)
Vendoring costs: someone must manually notice and re-copy if upstream's stub content ever does change (it says it won't, but "won't" is upstream's promise, not a guarantee). Auto-fetch costs: build reproducibility drops, and the repo loses the explicit, diffable record of what discovery-stub content shipped in a given image build — which cuts against the audit-trail rationale the Dockerfile already states for pinned versions.

## Recommendation

**Keep vendoring the static stub; do not switch to `npx skills add vercel-labs/agent-browser` at build time.**

Reasoning: the stub is upstream-documented as release-invariant, the vendored copy is currently verified identical to upstream, and the actual version-tracking behavior upstream advertises is already delivered by the pinned `AGENT_BROWSER_VERSION` + the runtime `agent-browser skills get core` call — not by this file. Pulling it at build time would trade a small, auditable, git-diffable artifact for an unpinned network fetch, which runs counter to this Dockerfile's own stated policy on build-artifact determinism.

**Conditional:** If `npx skills add` is later found to support pinning to a specific tag/commit (unverified here), re-open this eval — a pinned fetch would remove the version-drift objection (Finding 3) and the choice becomes closer to a style preference (one more moving part in the build vs. one more file to remember to re-sync manually).

**Next steps:**
- Immediate: none — current setup is correct as-is.
- Low-effort hardening (optional, not required): add a comment or lightweight CI check that diffs the vendored stub against upstream's raw URL periodically, to catch the rare case upstream does change it despite their stated intent.

## Open Questions
- [ ] Does `npx skills add <owner>/<repo>` support a ref/tag pin (e.g., `@v0.31.1` or similar)? Not verified — would affect Finding 3 if deepened.
