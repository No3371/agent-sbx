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

- **Version:** latest at build time (installed as a Claude Code plugin)
- **License:** Elastic License 2.0 (ELv2)
- **Source:** https://www.npmjs.com/package/context-mode
- **Note:** Elastic License 2.0 permits use and redistribution but prohibits
  providing the software as a managed/hosted service to third parties. Baking
  into a personal-use sandbox image is within scope; building a commercial
  hosted agent service on top of it is not.
