---
name: setup
description: Guide the user through NemoClaw setup end-to-end — env config, prerequisites, deployment, and post-install auth. Use when the user wants to set up or redeploy NemoClaw.
allowed-tools: Bash Read Write Edit Grep Glob AskUserQuestion
---

# NemoClaw Setup

Walk the user through a complete NemoClaw deployment on Brev. Be conversational — check each phase, report what you find, and only ask the user to act when their input is needed (API keys, browser auth URLs).

This is the same flow for humans and agents. The only steps requiring human involvement are providing API keys and clicking auth URLs in a browser.

## Phase 1 — Prerequisites

Check these in parallel and report a summary:

```bash
# Brev CLI installed and authenticated?
command -v brev > /dev/null 2>&1 && echo "Brev CLI: OK" || echo "Brev CLI: NOT FOUND — install from https://github.com/brevdev/brev-cli"

# Instance running?
brev ls 2>&1
```

If Brev CLI is missing, stop. If no instance is running, ask the user to create one or start it.

Then verify the remote instance has Docker:

```bash
brev exec <instance> "docker info > /dev/null 2>&1 && echo 'Docker: OK' || echo 'Docker: NOT RUNNING'"
```

## Phase 2 — Environment file

Check if `.env` exists in the cookbook repo and what's configured:

```bash
[ -f <cookbook-dir>/.env ] && grep -E '^\s*[A-Z_]+=' <cookbook-dir>/.env | grep -v '^#' | sed 's/=.*/=***/' || echo "NOT FOUND"
```

**If `.env` doesn't exist:** Create it from the template:

```bash
cp <cookbook-dir>/.env.example <cookbook-dir>/.env
chmod 600 <cookbook-dir>/.env
```

Then tell the user:

> I've created `.env` from the template in the cookbook directory. You need to add your NVIDIA API key.
> Get one at https://integrate.api.nvidia.com if you don't have one.
>
> Open `.env` and replace `nvapi-your-key-here` with your actual key.
> Let me know when you're done and I'll continue.

**If `.env` exists:** Parse it and report what's configured:

```bash
source <cookbook-dir>/.env
echo "=== Required ==="
echo "NVIDIA_API_KEY: ${NVIDIA_API_KEY:+SET}${NVIDIA_API_KEY:-NOT SET}"
echo "=== Inference ==="
echo "NEMOCLAW_PROVIDER: ${NEMOCLAW_PROVIDER:-not set (default: NVIDIA cloud)}"
echo "NEMOCLAW_MODEL: ${NEMOCLAW_MODEL:-not set (default: nemotron-3-super-120b)}"
echo "OPENAI_API_KEY: ${OPENAI_API_KEY:+SET}${OPENAI_API_KEY:-not set}"
echo "ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:+SET}${ANTHROPIC_API_KEY:-not set}"
echo "=== Messaging ==="
echo "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:+SET}${TELEGRAM_BOT_TOKEN:-not set}"
echo "DISCORD_BOT_TOKEN: ${DISCORD_BOT_TOKEN:+SET}${DISCORD_BOT_TOKEN:-not set}"
echo "SLACK_BOT_TOKEN: ${SLACK_BOT_TOKEN:+SET}${SLACK_BOT_TOKEN:-not set}"
echo "=== Integrations ==="
echo "BRAVE_API_KEY: ${BRAVE_API_KEY:+SET}${BRAVE_API_KEY:-not set}"
```

If `NVIDIA_API_KEY` is still the placeholder or missing, ask the user to set it and wait.

Confirm what's configured:

> **Ready to deploy with:**
> - NVIDIA API key: configured
> - Inference: [provider/model or defaults]
> - Messaging: [which are configured / none — add later]
> - Search: [Brave configured / not configured]
>
> Want me to proceed?

## Phase 3 — Deploy

Clone the cookbook on the remote instance and copy `.env`:

```bash
brev exec <instance> "git clone https://github.com/stevenrick/nemoclaw-cookbook.git ~/nemoclaw-cookbook"
brev copy <cookbook-dir>/.env <instance>:~/.env
```

The `.env` lives in the repo locally (gitignored) but gets copied to `~/.env` on the remote where `setup.sh` and `nemoclaw` expect it. The cookbook itself is cloned from GitHub — more reliable than `brev copy` for directories.

Then run setup:

```bash
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$HOME/.nvm/versions/node/v22.22.2/bin:\$PATH\" && cd ~/nemoclaw-cookbook && ./setup.sh"
```

This takes ~5-10 minutes. The script handles: cloning repos, installing OpenShell, pulling the Docker image, applying patches, installing NemoClaw, configuring integrations, and starting services.

If setup fails, diagnose the error:
- Patch failure → suggest `claude /refresh-patches`
- Docker error → check if Docker is running and has enough disk
- Network error → check connectivity
- NemoClaw install error → check the install.sh output for specifics

Use `timeout: 600000` for the brev exec call (10 min max).

## Phase 4 — Post-install verification

```bash
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$HOME/.nvm/versions/node/v22.22.2/bin:\$PATH\" && nemoclaw list && openshell sandbox list && openshell status"
```

Both should show the sandbox (typically `my-assistant`) in Ready state.

**If OpenShell shows the sandbox but NemoClaw doesn't:**

```bash
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$HOME/.nvm/versions/node/v22.22.2/bin:\$PATH\" && source ~/.env && export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 && nemoclaw onboard"
```

## Phase 5 — Connect

Forward the Web UI port to the user's local machine:

```bash
lsof -i :18789 2>/dev/null && echo "Port 18789 already in use" || brev port-forward <instance> -p 18789:18789
```

Get the tokenized URL and rewrite it for localhost:

```bash
brev exec <instance> "cat ~/openclaw-ui-url.txt 2>/dev/null"
```

Replace the hostname with `localhost:18789` and give it to the user:

> Web UI is live at: `http://localhost:18789?token=<token>`

## Phase 6 — Authenticate

Run the auth commands remotely and relay the URLs to the user:

```bash
# Claude Code login — will print a URL
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' sandbox@openshell-my-assistant 'claude login 2>&1'"
```

This prints a URL — tell the user to open it in their browser. Same pattern for Codex:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' sandbox@openshell-my-assistant 'codex login --device-auth 2>&1'"
```

Then install the Codex plugin:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' sandbox@openshell-my-assistant 'claude /plugin marketplace add openai/codex-plugin-cc && claude /plugin install codex@openai-codex && claude /reload-plugins'"
```

> Open these URLs in your browser to authenticate:
> - Claude: [URL from output]
> - Codex: [URL from output]
>
> Let me know when you've authenticated both and I'll verify.

After user confirms, verify:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' sandbox@openshell-my-assistant 'claude --version && codex --version 2>/dev/null'"
```

## Principles

- **Brev is the only deployment path.** No local installs, no SSH tunnels, no ngrok.
- **Don't ask for what you can check.** If a file exists, read it. If a tool is installed, version-check it.
- **Minimize human involvement.** The only things requiring a human are: providing API keys and clicking auth URLs.
- **Report state, not instructions.** Say "NVIDIA key is configured, Telegram is not" rather than "please check if your NVIDIA key is configured."
- **Be honest about timing.** The Docker pull and NemoClaw install take minutes. Set expectations.
