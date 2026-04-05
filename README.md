# NemoClaw Cookbook

Automated setup for [NemoClaw](https://github.com/NVIDIA/NemoClaw) + [OpenShell](https://github.com/NVIDIA/OpenShell) with Claude Code, Codex, and messaging integrations (Telegram, Discord, Slack).

> **Note:** This is a community cookbook / reference implementation, not an official NVIDIA project. It is not endorsed by or supported by NVIDIA. For issues with NemoClaw or OpenShell themselves, please file issues in their respective repositories.

## Prerequisites

- A [Brev](https://brev.nvidia.com) instance with Docker
- [Brev CLI](https://github.com/brevdev/brev-cli) installed and authenticated on your local machine
- An NVIDIA API key from https://integrate.api.nvidia.com

## Setup

Both paths produce the same result. Choose whichever fits your workflow.

### Option A: Let a coding agent do it

Clone the repo locally and hand it off to your agent:

```
git clone https://github.com/stevenrick/nemoclaw-cookbook && cd nemoclaw-cookbook
```

**Claude Code:** run `/setup`. The agent will:
1. Check prerequisites, port-forward, and verify Docker
2. Check your `.env` in the cookbook repo (create from template if needed)
3. Clone the cookbook on your Brev instance, copy `.env`, and run `setup.sh`
4. Relay the Codex auth URL + code for you to enter in your browser
5. Tell you to open `brev shell` for Claude Code TUI login + Codex plugin install (inside Claude Code)

Your only involvement: provide API keys in `.env`, click auth URLs, and do one interactive Claude session.

**Other agents:** point them at this repo and tell them to follow BUILD.md.

### Option B: Do it yourself

Everything runs on your Brev instance — you work from your local terminal.

```bash
# 1. Configure — create .env in the repo with your keys
cp .env.example .env
# Edit .env — NVIDIA_API_KEY is required, everything else is optional

# 2. Deploy — clone on remote and run setup
brev exec <instance> "git clone -b main https://github.com/stevenrick/nemoclaw-cookbook.git ~/nemoclaw-cookbook"
brev copy .env <instance>:~/.env
brev exec <instance> "cd ~/nemoclaw-cookbook && ./setup.sh"

# 3. Connect — port-forward the Web UI
brev port-forward <instance> -p 18789:18789
brev exec <instance> "cat ~/openclaw-ui-url.txt"
# Open the URL in your browser (use 127.0.0.1, not localhost)

# 4. Authenticate Codex (works non-interactively)
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy \
  --gateway-name nemoclaw --name my-assistant' sandbox@openshell-my-assistant \
  'codex login --device-auth 2>&1'"
# Opens a URL + code — enter in your browser

# 5. Authenticate Claude Code + install Codex plugin inside Claude Code (interactive)
brev shell <instance>
nemoclaw my-assistant connect
claude                # TUI — follow login prompts, then install Codex plugin inside Claude Code
```

See [BUILD.md](BUILD.md) for the full step-by-step walkthrough with explanations.

## What This Sets Up

- **OpenShell** — sandboxed runtime with Landlock, seccomp, and network policy enforcement
- **NemoClaw** — CLI stack running an OpenClaw AI assistant inside an OpenShell sandbox
- **Claude Code** — installed via native installer (Codex plugin for Claude Code installed post-deploy)
- **Codex CLI** — OpenAI's coding agent
- **Messaging bridges** — Telegram, Discord, and Slack (set tokens in `~/.env`)
- **Brave Search** — optional web search integration (add `BRAVE_API_KEY` to `~/.env`)
- **Inference** — NVIDIA Nemotron by default, configurable via `NEMOCLAW_MODEL` in `~/.env`

## What the Patches Do

Our patches on top of upstream NemoClaw:

**Dockerfile** — adds Claude Code (native installer), Codex CLI, git HTTPS/SSL config, and correct sandbox user ownership

**Sandbox policy** — adds network endpoints for:
- Claude Code SSO (`platform.claude.com`, `downloads.claude.ai`, `storage.googleapis.com`)
- OpenAI/Codex (`api.openai.com`, `auth.openai.com`, `chatgpt.com`, `ab.chatgpt.com`)
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

Via `brev exec` or inside `brev shell`. Always back up first — destroy wipes the workspace:

```bash
source ~/.env && export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1

~/nemoclaw-cookbook/scripts/backup-full.sh backup my-assistant
nemoclaw stop 2>/dev/null
docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest
nemoclaw my-assistant destroy --yes
nemoclaw onboard
~/nemoclaw-cookbook/scripts/backup-full.sh restore my-assistant
```

After rebuild: re-authenticate by running `codex login --device-auth` then launching `claude` (login is forced on first launch), and reinstall the Codex plugin inside Claude Code.

## File Structure

```
.env.example          # Template for API keys and tokens
setup.sh              # Automated setup script
patches/
  Dockerfile.patch    # Claude Code + Codex + git config
  policy.patch        # Network policy for auth endpoints
scripts/
  validate-patches.sh # Check patches still apply against upstream
  backup-full.sh      # Workspace + chat history backup/restore
BUILD.md              # Detailed setup walkthrough
USE.md                # Usage reference
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
