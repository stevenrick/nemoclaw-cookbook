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

Verify the remote instance has Docker:

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
echo "OPENAI_API_KEY: $([ -n "${OPENAI_API_KEY:-}" ] && echo SET || echo 'not set')"
echo "ANTHROPIC_API_KEY: $([ -n "${ANTHROPIC_API_KEY:-}" ] && echo SET || echo 'not set')"
echo "=== Messaging ==="
echo "TELEGRAM_BOT_TOKEN: $([ -n "${TELEGRAM_BOT_TOKEN:-}" ] && echo SET || echo 'not set')"
echo "DISCORD_BOT_TOKEN: $([ -n "${DISCORD_BOT_TOKEN:-}" ] && echo SET || echo 'not set')"
echo "SLACK_BOT_TOKEN: $([ -n "${SLACK_BOT_TOKEN:-}" ] && echo SET || echo 'not set')"
echo "=== Web Search ==="
echo "TAVILY_API_KEY: $([ -n "${TAVILY_API_KEY:-}" ] && echo SET || echo 'not set')"
echo "BRAVE_API_KEY: $([ -n "${BRAVE_API_KEY:-}" ] && echo SET || echo 'not set')"
echo "=== Sandbox Tools ==="
echo "INSTALL_CLAUDE_CODE: ${INSTALL_CLAUDE_CODE:-true}"
echo "INSTALL_CODEX: ${INSTALL_CODEX:-true}"
```

If `NVIDIA_API_KEY` is missing, the placeholder, or not set, ask the user to set it and wait. **Never display the actual key value.**

Confirm what's configured:

> **Ready to deploy with:**
> - NVIDIA API key: configured
> - Inference: [provider/model or defaults]
> - Messaging: [which are configured / none — add later]
> - Search: [Tavily configured / Brave configured / not configured — Tavily preferred when both are set]
> - Sandbox tools: [Claude Code, Codex / none]
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
brev exec <instance> "[ -s \$HOME/.nvm/nvm.sh ] && . \$HOME/.nvm/nvm.sh; export PATH=\"\$HOME/.local/bin:\$PATH\" && cd ~/nemoclaw-cookbook && ./setup.sh"
```

This takes ~5-10 minutes. The script handles: cloning repos, installing OpenShell, pulling the Docker image, applying patches, installing NemoClaw, deploying infrastructure services (nginx, systemd, terminal server via `install-services.sh`), configuring integrations, and starting services.

If setup fails, diagnose the error:
- Patch failure → suggest `claude /refresh-patches`
- Docker error → check if Docker is running and has enough disk
- Network error → check connectivity
- NemoClaw install error → check the install.sh output for specifics
- Service install error → re-run just: `~/nemoclaw-cookbook/scripts/install-services.sh`

Use `timeout: 600000` for the brev exec call (10 min max).

## Phase 4 — Post-install verification

Run the comprehensive health check (setup.sh runs this automatically as Step 9):

```bash
brev exec <instance> "[ -s \$HOME/.nvm/nvm.sh ] && . \$HOME/.nvm/nvm.sh; export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/verify-deployment.sh"
```

This checks gateway, sandbox, dashboard, OpenClaw, tools, workspace, services, infrastructure (nginx, systemd, terminal server), and manifest. If the dashboard port forward is dead, it auto-restarts it.

**If sandbox shows but NemoClaw doesn't recognize it:**

```bash
brev exec <instance> "[ -s \$HOME/.nvm/nvm.sh ] && . \$HOME/.nvm/nvm.sh; export PATH=\"\$HOME/.local/bin:\$PATH\" && set -a && source ~/.env && set +a && export NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 && nemoclaw onboard && ~/nemoclaw-cookbook/scripts/save-ui-url.sh"
```

## Phase 5 — Connect

`setup.sh` saves the tokenized URL automatically (Step 6). Retrieve it:

```bash
# If Secure Link is configured (TUNNEL_FQDN in .env):
brev exec <instance> "cat ~/openclaw-tunnel-url.txt 2>/dev/null"
# Otherwise (port-forward mode):
brev exec <instance> "cat ~/openclaw-ui-url.txt 2>/dev/null"
```

If the file is missing (manual onboard, or extraction failed), regenerate it:

```bash
brev exec <instance> "[ -s \$HOME/.nvm/nvm.sh ] && . \$HOME/.nvm/nvm.sh; export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/save-ui-url.sh"
```

If `TUNNEL_FQDN` is set, the tunnel URL works directly in any browser (nginx rewrites the Origin header). If using port-forward, use `127.0.0.1` (not `localhost`).

> Web UI is live at: `<URL from the appropriate file>`

## Phase 6 — Authenticate

Do everything the agent can automate first, then hand off to the human for interactive steps. Skip tools that aren't installed (check `INSTALL_CLAUDE_CODE` and `INSTALL_CODEX` from `.env`).

**Important:** The sandbox name comes from Phase 4's `nemoclaw list` output. Use the actual discovered name, not a hardcoded default.

### Step 1: Codex (agent can relay — skip if INSTALL_CODEX=false)

Codex uses device-code auth that works non-interactively:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name <sandbox>' sandbox@openshell-<sandbox> 'codex login --device-auth 2>&1'"
```

This prints a URL and a one-time code. Relay both to the user:

> To authenticate Codex:
> 1. Open [URL from output] in your browser
> 2. Enter code: [code from output]

The command will print "login successful" once the user completes auth — no need to ask for confirmation.

### Step 2: Claude Code (interactive — requires human — skip if INSTALL_CLAUDE_CODE=false)

Claude Code uses a full TUI for auth. If Codex is also installed, the Codex plugin should be set up inside Claude Code's TUI. Tell the user:

> Authenticate Claude Code (interactive — requires brev shell):
>
> ```
> brev shell <instance>
> nemoclaw <sandbox> connect
> claude
> ```
>
> Follow the login prompts (it will give you a URL to open in your browser).

If both Claude Code and Codex are installed, also instruct:

> Once logged into Claude Code, install the Codex plugin:
> ```
> /plugin marketplace add openai/codex-plugin-cc
> /plugin install codex@openai-codex
> /reload-plugins
> /codex:setup
> ```

> Let me know when you're done.

### Verify

After the user confirms, verify installed tools:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name <sandbox>' sandbox@openshell-<sandbox> 'claude --version 2>/dev/null; codex --version 2>/dev/null; ls /sandbox/.openclaw-data/plugins/*/codex* 2>/dev/null && echo PLUGIN_OK || echo PLUGIN_MISSING'"
```

Only check for tools that were installed. If `PLUGIN_MISSING` and both tools are installed, tell the user to re-run the `/plugin` commands inside Claude Code's TUI.

## Phase 7 — Record upstream versions

After a successful deployment, capture the exact versions that were deployed and update `UPSTREAM.md` in the cookbook repo. This is the "last known good" record for the community.

```bash
# On the Brev instance — capture deployed versions
brev exec <instance> "git -C ~/NemoClaw log --oneline -1"
brev exec <instance> "git -C ~/OpenShell log --oneline -1"
brev exec <instance> "docker inspect ghcr.io/nvidia/nemoclaw/sandbox-base:latest --format '{{index .Config.Labels \"org.opencontainers.image.revision\"}}'"
```

Update `UPSTREAM.md` in the cookbook repo with the commit SHAs, descriptions, and today's date. The sandbox-base tag is a NemoClaw commit SHA, embedded as an OCI label on the pulled image — read it via `docker inspect`, not the GitHub packages page.

If the deployed versions differ from what's currently in `UPSTREAM.md`, note what changed in the commit message when the user commits (e.g., "docs: update UPSTREAM.md — validated against NemoClaw c99e3e8").

## Principles

- **Never leak secrets.** Never print, log, display, or include in output the actual values of API keys, tokens, or credentials. Only report SET / NOT SET / PLACEHOLDER. Use `sed 's/=.*/=***/'` when listing env vars. Never `cat .env` or `echo $API_KEY`.
- **Brev is the only deployment path.** No local installs, no SSH tunnels, no ngrok.
- **Confirm the instance.** Always show the user which Brev instance will be used and get confirmation before deploying.
- **Don't ask for what you can check.** If a file exists, read it. If a tool is installed, version-check it.
- **Minimize human involvement.** The only things requiring a human are: providing API keys and clicking auth URLs.
- **Report state, not instructions.** Say "NVIDIA key is configured, Telegram is not" rather than "please check if your NVIDIA key is configured."
- **Be honest about timing.** The Docker pull and NemoClaw install take minutes. Set expectations.
