# Third-Party Notices

This repository's scripts and Dockerfiles are licensed under MIT (see `LICENSE`).
The images produced by building these Dockerfiles include third-party components.
Each component retains its original license, summarized below.

Adopters who stage additional content via `vendor_imports/skills/` or host plugin
installs are responsible for verifying the licenses of that additional content.

---

## claude-hud

- **Version:** latest at build time (installed as a Claude Code plugin)
- **License:** MIT
- **Source:** https://www.npmjs.com/package/claude-hud

## context-mode

- **Version:** latest at build time in `claude/` (installed as a Claude Code
  plugin); pinned `1.0.169` in `pi/` (installed as a plain npm package via
  `pi install npm:context-mode`)
- **License:** Elastic License 2.0 (ELv2)
- **Source:** https://www.npmjs.com/package/context-mode
- **Note:** Elastic License 2.0 permits use and redistribution but prohibits
  providing the software as a managed/hosted service to third parties. Baking
  into a personal-use sandbox image is within scope; building a commercial
  hosted agent service on top of it is not. Same package, same license terms,
  regardless of which suite's Dockerfile installs it or by what mechanism.

## codegraph

- **Version:** `1.3.0` (pinned; installed via `npm install -g` in `claude/`,
  `codex/`, `opencode/`, `cursor/`, and `pi/`)
- **License:** MIT
- **Source:** https://www.npmjs.com/package/@colbymchenry/codegraph

## agent-browser

- **Version:** `0.31.1` (pinned; installed via `npm install -g` in `claude/`,
  `codex/`, `opencode/`, `cursor/`, and `pi/`)
- **License:** Apache License 2.0
- **Source:** https://github.com/vercel-labs/agent-browser

## Playwright

- **Version:** `1.61.1` (pinned; installed via `npm install -g` in `claude/`,
  `codex/`, `opencode/`, `cursor/`, and `pi/`)
- **License:** Apache License 2.0
- **Source:** https://github.com/microsoft/playwright

## opencode

- **Version:** `1.18.3` (pinned; npm package `opencode-ai`, installed via
  `npm install -g` in `opencode/`)
- **License:** MIT
- **Source:** https://www.npmjs.com/package/opencode-ai

## Pi (pi-coding-agent)

- **Version:** `0.80.9` (pinned; npm package `@earendil-works/pi-coding-agent`,
  installed via `npm install -g` in `pi/`)
- **License:** MIT
- **Source:** https://github.com/earendil-works/pi

## pi-subagents

- **Version:** `0.14.1` (pinned; npm package `@tintinweb/pi-subagents`,
  installed via `pi install npm:...` in `pi/`)
- **License:** MIT
- **Source:** https://github.com/tintinweb/pi-subagents

## pi-cursor-sdk

- **Version:** `0.1.59` (pinned; installed via `pi install npm:...` in `pi/`)
- **License:** MIT
- **Source:** https://github.com/fitchmultz/pi-cursor-sdk
- **Note:** This wrapper package is MIT, but it depends on Cursor's own
  `@cursor/sdk` package ("SEE LICENSE IN LICENSE.md" — proprietary, governed by
  Cursor's terms at https://cursor.com/terms-of-service). It only activates
  when a `CURSOR_API_KEY` is supplied at container-run time; no Cursor SDK
  credentials or code are baked into the image.

## pi-web-access

- **Version:** `0.13.0` (pinned; installed via `pi install npm:...` in `pi/`)
- **License:** MIT
- **Source:** https://github.com/nicobailon/pi-web-access

## pi-mcp-adapter

- **Version:** `2.21.1` (pinned; installed via `pi install npm:...` in `pi/`)
- **License:** MIT
- **Source:** https://github.com/nicobailon/pi-mcp-adapter
- **Note:** MCP bridge (single proxy tool, on-demand discovery). Stores MCP
  OAuth tokens only in an OS credential store and fails closed without one —
  no token files exist to bake or mount; the container runs no secret
  service, so in-sandbox MCP auth is bearer/env-based via `run.ps1`'s
  provider env forwarding.

## Cursor CLI (cursor-agent)

- **Version:** unpinned — installed at build time in `cursor/` via the
  official installer (`curl https://cursor.com/install | bash`), which always
  resolves to whatever Cursor currently publishes; there is no version-pin
  knob upstream
- **License:** Proprietary — governed by Cursor's own Terms of Service, not an
  open-source license
- **Source:** https://cursor.com/terms-of-service
- **Note:** No Cursor account credentials are baked into the image;
  `run.ps1` authenticates fresh inside each ephemeral container.
