# Memo: context-mode plugin bakes host-absolute paths into sandbox settings.json

> **Date:** 2026-07-09
> **Author:** agent
> **Source Type:** Issue + Idea (proposed fix)
> **Origin:** Conversation — diagnosis of a recurring sandbox failure, mid-investigation when session was interrupted (user restarting in parent path; this sandbox was accidentally run "inside claude specific variation")

---

## Source

User: "It seems like these agent tools may do host-specific configuration during plugin install. i think we need to make the tools install the plugins during build time instead of just map it from host, for example after I update context-mode on my host, it's pointing to absolute paths of node and the hook file on my host system, and that results in errors in these sandboxes"

---

## Context

Repo: `cc-custom` sandbox template (this workspace) — Dockerfile/Dockerfile.slim build a custom Claude Code sandbox image; `prepare.ps1` stages host `~/.claude` config into `context/.claude/` for `COPY` into the image.

Root cause traced during this session:

- `prepare.ps1` does **not** run the plugin installer inside the container. It recursively copies the host's entire `~/.claude/plugins` tree verbatim (`prepare.ps1:87-103`), then patches only known fields via hand-maintained regex: `installed_plugins.json`/`known_marketplaces.json` paths (`Convert-WinPathToLinux`, `prepare.ps1:123-128`) and hook `command` strings in `settings.json` (`Rewrite-Command`, `prepare.ps1:236-254`).
- `context-mode`'s own MCP entrypoint (`.../context-mode/<ver>/start.mjs:291-424`) resolves `homedir()` at runtime on whichever machine last booted it and rewrites `~/.claude/settings.json`'s `SessionStart` hook + hook script to that machine's own absolute paths (self-heal layer, by design — handles brew/nvm node-path drift on a single host). This is exactly the kind of host-shape output `prepare.ps1`'s regex allowlist has to keep chasing (already 3+ generations of patches for Win node.exe path / git-bash path / WSL mount path / cygpath wrapper — see `prepare.ps1:236-254` and README's rewrite table).
- Verified in the current sandbox that `settings.json:31` did resolve correctly to `/home/agent/.claude/hooks/context-mode-cache-heal.mjs` — this instance wasn't broken — but the mechanism is fragile by construction: any new absolute-path shape context-mode's self-heal writes on the host (new plugin version, new OS path convention, or host update not followed by an image rebuild) is a new case the regex rewriter must anticipate or it silently drops the hook or ships a broken one.

Proposed direction (mine, given during this conversation, not yet actioned): stop copying+rewriting the plugin *payload*. The plugin *identity* (`enabledPlugins`, `extraKnownMarketplaces` in `settings.json:41-74`) is already portable — just names/URLs. Replace the `context/.claude/plugins/` COPY + JSON-path-rewriting in `prepare.ps1`/`Dockerfile` with a Dockerfile `RUN` step that does `claude plugin marketplace add <source>` / `claude plugin install <name>@<marketplace>` as the `agent` user for each enabled entry, so Claude Code resolves its own cache paths natively inside the Linux container — nothing to transpile. Trade-off: build now needs network + marketplace auth at `docker build` time (vs. only once on host), and loses "image mirrors host state byte-for-byte" in exchange for "image has the same plugins, correctly installed for its own filesystem."

User was asked (via AskUserQuestion) whether to implement now / just confirm / prototype on context-mode only — question was rejected/interrupted before an answer landed, because the user realized this sandbox session itself is nested inside the wrong context ("claude specific variation") and is restarting in the parent path. This memo exists so the diagnosis + proposed fix aren't lost across that restart.

---

## Related Projex

- None yet — no prior projex found for this repo besides `2607091743-agent-browser-skill-build-pull-eval.md` (unrelated topic).
- Natural next step once resumed: `/propose-projex.md` or `/plan-projex.md` for the build-time-plugin-install change, referencing this memo.
- Consumed by: 2607100201-build-time-plugin-install-for-sandbox-images-proposal.md (Proposal, Review status) — formalizes this memo's diagnosis + fix idea into Options A/B/C with recommendation for a context-mode-only pilot (Option C).
