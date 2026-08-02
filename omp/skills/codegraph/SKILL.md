---
name: codegraph
description: Local code-intelligence CLI that builds a queryable graph of this repository (symbols, call paths, cross-file references). Use when you need to find where a symbol is defined or called, understand the impact of changing a function, find test files affected by a diff, or explore unfamiliar code faster than grep. Triggers include "what calls this function", "what would break if I change X", "find the definition of", "what tests cover this file", or any request to understand code structure/relationships across files. Prefer codegraph over grep/ripgrep when the question is about symbol relationships rather than plain text.
allowed-tools: bash(codegraph:*)
hidden: true
---

# codegraph

Local-first code-intelligence CLI (`@colbymchenry/codegraph`) — builds a SQLite graph of this repo's symbols and call relationships for fast, structural queries. 100% local, no API keys, no data leaves the machine.

## Why this is a skill, not an MCP tool

Pi has no MCP client by design (see pi's own docs: "No MCP. Build CLI tools with READMEs, or build an extension that adds MCP support"). codegraph's own installer (`codegraph install --target=...`) also doesn't support `pi` as a target — its supported list is Claude Code, Cursor, Codex CLI, opencode, Hermes Agent, Gemini CLI, Antigravity IDE, and Kiro. So instead of MCP wiring, this image bakes the `codegraph` CLI directly and documents it here as a skill: every command below is a plain shell command, invoked the same way `agent-browser` is.

The container's `run.ps1` already runs `codegraph init` on first launch (guarded by `.codegraph/` so it doesn't re-index every run; auto-sync keeps the graph fresh after that) — the graph should already exist when you read this.

## Commands

```bash
codegraph status                  # graph statistics — confirm it's built and fresh
codegraph query <search>          # search symbols by name (--kind, --limit, --json)
codegraph explore <query>         # relevant symbols' source + call paths in one shot — start here for open-ended questions
codegraph node <symbol|file>      # one symbol's source + callers, or read a file with line numbers
codegraph files [path]            # file structure (--format, --filter, --max-depth, --json)
codegraph callers <symbol>        # what calls a function/method (--limit, --json)
codegraph callees <symbol>        # what a function/method calls (--limit, --json)
codegraph impact <symbol>         # what code is affected by changing a symbol (--depth, --json)
codegraph affected [files...]     # find test files affected by changed files (--stdin to pipe from git diff)
codegraph sync                    # force an incremental update if something looks stale
```

`codegraph explore <query>` is usually the best first move — it's the same tool codegraph exposes as its single MCP tool (`codegraph_explore`) on agents that do support MCP, so it's the most "figure this out for me" of the commands above.

## CI/hook-style usage

```bash
git diff --name-only HEAD | codegraph affected --stdin --quiet
```

Useful before running a targeted test subset instead of the whole suite.
