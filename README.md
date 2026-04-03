# NemoClaw Cookbook

Automated setup for [NemoClaw](https://github.com/NVIDIA/NemoClaw) + [OpenShell](https://github.com/NVIDIA/OpenShell) with Claude Code, Codex, and Telegram integration.

> **Note:** This is a community cookbook / reference implementation, not an official NVIDIA project. It is not endorsed by or supported by NVIDIA. For issues with NemoClaw or OpenShell themselves, please file issues in their respective repositories.

## Quick Start

### With a coding agent (recommended)

Clone the repo and tell your agent to set it up:

```
git clone https://github.com/stevenrick/nemoclaw_cookbook && cd nemoclaw_cookbook
```

**Claude Code:** run `/setup` — it handles env config, prerequisites, deployment, and walks you through post-install auth interactively.

**Other agents:** point them at this repo and ask them to follow BUILD.md.

### Manual

```bash
# 1. Create your env file and fill in your values
cp .env.example ~/.env
# Edit ~/.env — NVIDIA_API_KEY is required, everything else is optional

# 2. Run setup
./setup.sh

# 3. Connect and authenticate (inside the sandbox)
nemoclaw my-assistant connect
claude login
codex login --device-auth
claude /plugin marketplace add openai/codex-plugin-cc
claude /plugin install codex@openai-codex
claude /reload-plugins
```

## What This Sets Up

- **OpenShell** — sandboxed runtime with Landlock, seccomp, and network policy enforcement
- **NemoClaw** — CLI stack running an OpenClaw AI assistant inside an OpenShell sandbox
- **Claude Code** — installed via native installer, with Codex plugin
- **Codex CLI** — OpenAI's coding agent
- **Telegram bridge** — chat with your agent from your phone
- **Brave Search** — optional web search integration (add `BRAVE_SEARCH_API_KEY` to `~/.env`)
- **NVIDIA Nemotron** inference via `nvidia/nemotron-3-super-120b-a12b`

## What the Patches Do

Our patches on top of upstream NemoClaw:

**Dockerfile** — adds Claude Code (native installer), Codex CLI, and git HTTPS/SSL config

**Sandbox policy** — adds network endpoints for:
- Claude Code SSO (`platform.claude.com`, `downloads.claude.ai`, `storage.googleapis.com`)
- OpenAI/Codex (`api.openai.com`, `auth.openai.com`, `chatgpt.com`, `ab.chatgpt.com`)
- Brave Search (`api.search.brave.com`)
- GitHub access for Claude/Codex/Node binaries (`codeload.github.com`)

## When Upstream Changes

Patches apply with `git apply --3way`, which handles minor upstream drift automatically. If patches break after an upstream NemoClaw update:

```bash
claude /refresh-patches    # Claude Code walks you through regenerating patches
```

Or see [BUILD.md § Refreshing Patches](BUILD.md#refreshing-patches-after-upstream-updates) for the manual process.

## Docs

- [BUILD.md](BUILD.md) — step-by-step from-scratch setup with explanations
- [USE.md](USE.md) — day-to-day reference for all commands and features

## Rebuilding

```bash
source ~/.env && export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1
# Ensure CHAT_UI_URL is set in ~/.env if accessing remotely

nemoclaw stop 2>/dev/null
docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest
nemoclaw my-assistant destroy --yes
nemoclaw onboard
```

After rebuild: re-run `claude login`, `codex login --device-auth`, and plugin install.

## File Structure

```
.env.example          # Template for API keys and tokens
setup.sh              # Automated setup script
patches/
  Dockerfile.patch    # Claude Code + Codex + git config
  policy.patch        # Network policy for auth endpoints
scripts/
  validate-patches.sh # Check patches still apply against upstream
BUILD.md              # Detailed setup walkthrough
USE.md                # Usage reference
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
