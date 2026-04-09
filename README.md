# NemoClaw Cookbook

Automated setup for [NemoClaw](https://github.com/NVIDIA/NemoClaw) + [OpenShell](https://github.com/NVIDIA/OpenShell) with Claude Code, Codex, and messaging integrations (Telegram, Discord, Slack).

> **Note:** This is a community cookbook / reference implementation, not an official NVIDIA project. It is not endorsed by or supported by NVIDIA. For issues with NemoClaw or OpenShell themselves, please file issues in their respective repositories.

## Prerequisites

- A [Brev](https://brev.nvidia.com) instance with Docker
- [Brev CLI](https://github.com/brevdev/brev-cli) installed and authenticated on your local machine
- An NVIDIA API key from [https://build.nvidia.com/](https://build.nvidia.com/)

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

# 4–5. Authenticate coding agents (if installed — see INSTALL_CLAUDE_CODE / INSTALL_CODEX in .env)
#
# Examples use "my-assistant" — this is the default sandbox name.
# If you chose a different name during setup, substitute it everywhere.
# Run `nemoclaw list` to check.

# Codex (works non-interactively)
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy \
  --gateway-name nemoclaw --name my-assistant' sandbox@openshell-my-assistant \
  'codex login --device-auth 2>&1'"
# Opens a URL + code — enter in your browser

# Claude Code + Codex plugin (interactive)
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

Modular patch fragments in `patches/fragments/` customize upstream NemoClaw. Core fragments (git config) always apply. Claude Code and Codex are optional — set `INSTALL_CLAUDE_CODE=false` or `INSTALL_CODEX=false` in `.env` to exclude them.

**Dockerfile** — adds Claude Code (native installer), Codex CLI, git HTTPS/SSL config, and correct sandbox user ownership

**Sandbox policy** — adds network endpoints for:
- Claude Code SSO (`platform.claude.com`, `downloads.claude.ai`, `storage.googleapis.com`)
- OpenAI/Codex (`api.openai.com`, `auth.openai.com`, `chatgpt.com`, `ab.chatgpt.com`)
- GitHub access for Claude/Codex/Node binaries (`codeload.github.com`)

## When Upstream Changes

See [UPSTREAM.md](UPSTREAM.md) for the upstream versions this cookbook was last validated against.

Patch fragments in `patches/fragments/` are assembled and applied by `scripts/apply-patches.sh`, which handles minor upstream drift automatically. If patches break after an upstream NemoClaw update:

```bash
claude /refresh-patches    # Claude Code walks you through regenerating patches
```

Or see [BUILD.md § Refreshing Patches](BUILD.md#refreshing-patches-after-upstream-updates) for the manual process.

## Docs

- [BUILD.md](BUILD.md) — step-by-step from-scratch setup with explanations
- [USE.md](USE.md) — day-to-day reference for all commands and features

## Backup & Restore

**Claude Code users:** run `/backup` to snapshot workspace, chat history, and skills to your local machine. Run `/restore` to push a backup to any NemoClaw instance.

**Manual (on the host):**

```bash
~/nemoclaw-cookbook/scripts/backup-full.sh backup <sandbox>                  # back up
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox>                 # restore all (gateway not running)
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> '' workspace    # restore workspace only
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> '' sessions     # restore sessions only (after start)
~/nemoclaw-cookbook/scripts/backup-full.sh list                              # list backups
```

Replace `<sandbox>` with your sandbox name (default: `my-assistant`).

Local backups are stored in `backups/` (gitignored). See [USE.md § Backup & Restore](USE.md#backup--restore) for details.

## Upgrading & Rebuilding

**Claude Code users:** run `/upgrade` — it checks what's changed, backs up, applies patches safely, rebuilds only if needed, and restores. Host-only updates (CLI tools) don't require a rebuild.

**Manual rebuild** — see [USE.md § Updating OpenClaw](USE.md#updating-openclaw) for the full steps. The key safety rule: always validate patches apply *before* destroying the sandbox.

## File Structure

```
.env.example          # Template for API keys and tokens
setup.sh              # Automated setup script
patches/
  fragments/          # Modular patch fragments (Dockerfile, policy, etc.)
scripts/
  validate-patches.sh # Check patches still apply against upstream
  backup-full.sh      # Workspace, chat history, and skills backup/restore
BUILD.md              # Detailed setup walkthrough
USE.md                # Usage reference
backups/              # Local backups (gitignored)
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
