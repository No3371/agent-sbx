# Agent SBX

We all know due to LLMs' probablistics nature, it's not impossible your agents go rogue on a whim and do unacceptable mistakes. Therefore isolation is always a good idea no matter how unlikely such accident could happen. 

Inspired by Docker SBX, this repo contains multiple tool suites to build personalized Docker/Podman images that contains your preferred agentic coding harness and your personal setup (configs, plugins, skills) so you can easily run agents in isolated environment without being limited from your usual workflow.

Additionally some opinionated tools/plugins are packed: context-mode, agent-browser, and per-harness addons.

## Supported Harness

- Claude Code
- Codex
- Opencode
- Pi (Slow on new sessions, probably due to pi-lens or pi-fff)
- Oh-My-Pi

## Feature Toggles

The `build.ps1|sh` scripts accept Enable/Disable parameters which toggles optional features like language SDKs (Go/Python\.NET) and Powershell.

Some features may be built-in in certain harnesses and not toggleable. For example, `omp` comes with python installed.

Expected values: `go`, `python`, `dotnet`, `pwsh`.

## Usage

Run `build.ps1|sh` inside the folder for your harness of choice. With the built image in your Docker/Podman store, call `run.ps1|sh` whereever you want to work on; the $pwd would be mounted as `/workspace`. Podman users may need to look into the -Retag parameter.

## Note

- The suites contains a `rm-guard` script which shadows `rm` to protect accidental deletion for `/workspace/.git`.
- Features/plugins/extensions versions are pinned.
