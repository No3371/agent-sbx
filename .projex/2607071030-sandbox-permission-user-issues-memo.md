# Memo: New sandbox — 3 permission/user friction points hit during a patch

> **Date:** 2026-07-07
> **Author:** Claude (Sonnet 5)
> **Source Type:** Issue
> **Origin:** Direct — encountered mid-execution of `2607071025-always-show-unit-timeline-edit-patch.md` (patch-projex on `apps/web/src/GameView.tsx`)

---

## Source

Three separate friction points hit back-to-back while running routine git commands in this new customized Docker/sandbox, none related to the actual code change:

1. **Dubious ownership.** Every `git` invocation on `/workspace` failed first with:
   `fatal: detected dubious ownership in repository at '/workspace'` — repo dir is owned differently than the running user (`whoami` = `agent`; dir listing showed `root root` ownership, `777` perms). Worked around per-invocation with `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=/workspace` (env-only, no `git config --global` write, since that's off-limits per session git-safety rules).

2. **No git identity configured.** First commit attempt failed:
   `Author identity unknown ... fatal: unable to auto-detect email address (got 'agent@d81e0f71c11a.(none)')`. Worked around with env-scoped `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL`/`GIT_COMMITTER_NAME`/`GIT_COMMITTER_EMAIL` instead of writing to config.

3. **CRLF line endings on the projex helper scripts themselves.** `stage-n-commit.sh` and `new-projex.sh` (from `/home/agent/.claude/skills/projex/`) have Windows line endings, so direct execution failed with `/usr/bin/env: 'bash\r': No such file or directory`, and even `bash script.sh` failed with `$'\r': command not found` / `set: pipefail: invalid option name`. Worked around by `tr -d '\r'` into a scratchpad copy before running.

All three were pure environment setup gaps, not anything about the actual task (a 1-file React/TSX patch). Each cost a failed tool call + diagnosis before the workaround was found.

---

## Context

This is a fresh/customized sandbox (per user's framing "new customized docker/sandbox"), so these are first-boot gaps rather than regressions. None of the three blocked the work — all had clean per-invocation workarounds that avoided touching persistent config (`git config --global`, editing the checked-out skill scripts in place). But they're exactly the kind of thing worth fixing at the image/bootstrap level so future sessions in this sandbox don't re-pay the same diagnosis cost:

- Repo ownership should probably match the running user, or the image should pre-seed `safe.directory` (system-level git config, not per-repo/global user config) so agents don't need env-var gymnastics on every git call.
- A default git identity (even a placeholder) avoids the first-commit failure.
- The projex skill scripts (`.sh` files under `/home/agent/.claude/skills/projex/`) should be committed/deployed with LF line endings — likely a checkout/packaging step somewhere normalizes to CRLF for this image.

No investigation was done beyond what surfaced naturally while executing the patch — this is a raw capture, not a root-cause analysis of the sandbox provisioning pipeline.

---

## Related Projex

- `2607071025-always-show-unit-timeline-edit-patch.md` — the patch during which these issues surfaced (unrelated to its actual content).
