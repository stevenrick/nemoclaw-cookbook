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

If Brev CLI is missing, stop.

If multiple instances are listed, ask the user which one to use. If no instances are listed, ask the user to create one:

> No Brev instances found. Create one at https://brev.nvidia.com or run:
> ```
> brev create <instance-name>
> ```
> Let me know when it's ready.

If exactly one instance is listed, confirm with the user before proceeding:

> Found Brev instance `<name>` (STATUS). Deploy NemoClaw here?

Establish the port forward early — this warms up the SSH connection and all subsequent `brev exec` calls multiplex over it:

```bash
lsof -i :18789 2>/dev/null && echo "Port 18789 already in use" || brev port-forward <instance> -p 18789:18789
```

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

**Important: never print, log, or display the actual values of any keys or tokens. Only report whether they are SET or NOT SET.**

```bash
source <cookbook-dir>/.env
echo "=== Required ==="
if [ -z "${NVIDIA_API_KEY:-}" ]; then
  echo "NVIDIA_API_KEY: NOT SET"
elif [ "$NVIDIA_API_KEY" = "nvapi-your-key-here" ]; then
  echo "NVIDIA_API_KEY: STILL PLACEHOLDER — replace with your real key"
else
  echo "NVIDIA_API_KEY: SET"
fi
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

If `NVIDIA_API_KEY` is missing, the placeholder, or not set, ask the user to set it and wait. **Never display the actual key value.**

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

The port forward was established in Phase 1. Get the tokenized URL:

```bash
brev exec <instance> "cat ~/openclaw-ui-url.txt 2>/dev/null"
```

The URL from `openclaw-ui-url.txt` will have a hostname like `127.0.0.1:18789` and a `/#token=<hex>` fragment. If the hostname differs, replace only the hostname with `127.0.0.1:18789` — preserve the exact path and `/#token=` fragment. **Always use `127.0.0.1`, not `localhost`** — the sandbox only allows `127.0.0.1` as an origin.

> Web UI is live at: `http://127.0.0.1:18789/#token=<hex>`

## Phase 6 — Authenticate

Do everything the agent can automate first, then hand off to the human for interactive steps.

### Step 1: Codex (agent can relay)

Codex uses device-code auth that works non-interactively:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' sandbox@openshell-my-assistant 'codex login --device-auth 2>&1'"
```

This prints a URL and a one-time code. Relay both to the user:

> To authenticate Codex:
> 1. Open [URL from output] in your browser
> 2. Enter code: [code from output]

The command will print "login successful" once the user completes auth — no need to ask for confirmation.

### Step 2: Claude Code + Codex plugin for Claude Code (interactive — requires human)

Claude Code uses a full TUI for auth, and the Codex plugin is installed inside Claude Code's TUI. Combine these into one interactive session. Tell the user:

> Last step — authenticate Claude Code and install the Codex plugin (inside Claude Code).
> Run these commands:
>
> ```
> brev shell <instance>
> nemoclaw my-assistant connect
> claude
> ```
>
> Inside Claude Code's TUI:
> 1. Follow the login prompts (it will give you a URL to open in your browser)
> 2. Once logged in, install the Codex plugin for Claude Code:
>    ```
>    /plugin marketplace add openai/codex-plugin-cc
>    /plugin install codex@openai-codex
>    /reload-plugins
>    /codex:setup
>    ```
> Let me know when you're done.

### Verify

After the user confirms, verify binaries and plugin state:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' sandbox@openshell-my-assistant 'claude --version && codex --version 2>/dev/null && ls /sandbox/.openclaw-data/plugins/*/codex* 2>/dev/null && echo PLUGIN_OK || echo PLUGIN_MISSING'"
```

If `PLUGIN_MISSING`, tell the user the Codex plugin install didn't complete and ask them to re-run the `/plugin` commands inside Claude Code's TUI.

## Phase 7 — Record upstream versions

After a successful deployment, capture the exact versions that were deployed and update `UPSTREAM.md` in the cookbook repo. This is the "last known good" record for the community.

```bash
# On the Brev instance — capture deployed versions
brev exec <instance> "git -C ~/NemoClaw log --oneline -1"
brev exec <instance> "git -C ~/OpenShell log --oneline -1"
brev exec <instance> "docker images ghcr.io/nvidia/nemoclaw/sandbox-base --format '{{.Tag}} {{.Digest}}'"
```

Update `UPSTREAM.md` in the cookbook repo with the commit SHAs, descriptions, and today's date. The sandbox-base tag is a NemoClaw commit SHA — record it as-is from the Docker image tag.

If the deployed versions differ from what's currently in `UPSTREAM.md`, note what changed in the commit message when the user commits (e.g., "docs: update UPSTREAM.md — validated against NemoClaw c99e3e8").

## Principles

- **Never leak secrets.** Never print, log, display, or include in output the actual values of API keys, tokens, or credentials. Only report SET / NOT SET / PLACEHOLDER. Use `sed 's/=.*/=***/'` when listing env vars. Never `cat .env` or `echo $API_KEY`.
- **Brev is the only deployment path.** No local installs, no SSH tunnels, no ngrok.
- **Confirm the instance.** Always show the user which Brev instance will be used and get confirmation before deploying.
- **Don't ask for what you can check.** If a file exists, read it. If a tool is installed, version-check it.
- **Minimize human involvement.** The only things requiring a human are: providing API keys and clicking auth URLs.
- **Report state, not instructions.** Say "NVIDIA key is configured, Telegram is not" rather than "please check if your NVIDIA key is configured."
- **Be honest about timing.** The Docker pull and NemoClaw install take minutes. Set expectations.
