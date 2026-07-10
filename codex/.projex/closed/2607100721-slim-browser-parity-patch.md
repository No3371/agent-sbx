# Patch: Slim Browser Parity

> **Date:** 2026-07-10
> **Author:** Codex
> **Directive:** `patch-projex`
> **Source Plan:** Direct
> **Result:** Success

## Summary

Ported `agent-browser` runtime support from full image to slim image. Corrected auth docs: `run.ps1` uses ephemeral device auth; it neither mounts nor persists host credentials.

## Changes

### Slim Image

**File:** `Dockerfile.slim`
**Change Type:** Modified

- Added pinned `AGENT_BROWSER_VERSION`; installs, links, verifies `agent-browser` (17-19, 60-67).
- Installs Chrome runtime; copies discovery skill (69-70, 83).
- Corrected auth comment (5).

### Run Documentation

**File:** `README.md`
**Change Type:** Modified

- Replaced false persistent-auth instructions with per-run device-auth behavior (40-42).

## Verification

**Method:** Node assertion check for version pin, package installation, executable link, browser runtime installation, discovery skill, and auth wording.

**Result:**
```
PASS: slim image has agent-browser parity and auth documentation matches run.ps1.
```

**Status:** PASS

## Notes

No Git repository or container engine is present in this exported workspace; commit and image-build verification were unavailable.
