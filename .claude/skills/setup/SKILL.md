---
name: setup
description: Guide the user through NemoClaw setup end-to-end — env config, prerequisites, deployment, and post-install auth. Use when the user wants to set up or redeploy NemoClaw.
allowed-tools: Bash Read Write Edit Grep Glob AskUserQuestion
---

# NemoClaw Setup

Walk the user through a complete NemoClaw deployment. Be conversational — check each phase, report what you find, and only ask the user to act when their input is needed (API keys, browser auth).

## Phase 1 — Prerequisites

Check these in parallel and report a summary:

```bash
# Docker running?
docker info > /dev/null 2>&1 && echo "Docker: OK" || echo "Docker: NOT RUNNING"

# Disk space
df -h ~ | tail -1

# RAM
free -h 2>/dev/null || sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB\n", $1/1073741824}'
```

If Docker isn't running, stop and tell the user. Don't proceed without it.

## Phase 2 — Environment file

Check if `~/.env` exists and what's configured:

```bash
[ -f ~/.env ] && cat ~/.env || echo "NOT FOUND"
```

**If `~/.env` doesn't exist:** Create it from the template with placeholder values:

```bash
cp <cookbook-dir>/.env.example ~/.env
chmod 600 ~/.env
```

Then tell the user:

> I've created `~/.env` from the template. You need to add your NVIDIA API key.
> Get one at https://integrate.api.nvidia.com if you don't have one.
>
> Open `~/.env` and replace `nvapi-your-key-here` with your actual key.
> Let me know when you're done and I'll continue.

**If `~/.env` exists:** Parse it and report what's configured vs what's missing:

```bash
source ~/.env
echo "NVIDIA_API_KEY: ${NVIDIA_API_KEY:+SET (${#NVIDIA_API_KEY} chars)}"
echo "NVIDIA_API_KEY: ${NVIDIA_API_KEY:-NOT SET}"
echo "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:-not set (optional)}"
echo "ALLOWED_CHAT_IDS: ${ALLOWED_CHAT_IDS:-not set (optional)}"
echo "CHAT_UI_URL: ${CHAT_UI_URL:-not set (local access only)}"
```

If `NVIDIA_API_KEY` is still the placeholder or missing, ask the user to set it and wait.

If the key looks real, confirm what's configured and what's optional:

> **Ready to deploy with:**
> - NVIDIA API key: configured
> - Telegram: [configured / not configured — add later with `nemoclaw start`]
> - Remote access: [CHAT_UI_URL set to X / local only — see BUILD.md § Remote Access if you need remote]
>
> Want me to proceed?

**Important:** If accessing remotely (Brev, ngrok, etc.), the user MUST uncomment and set `CHAT_UI_URL` in `~/.env` before install. Ask if they're running locally or remotely. If remote, they need to:
1. Set up port forwarding for port 18789 (Brev: "Share a Service", ngrok: `ngrok http 18789`)
2. Uncomment `CHAT_UI_URL` in `~/.env` and set it to the forwarded URL

## Phase 3 — Run setup

Once the user confirms, run setup.sh and monitor output:

```bash
cd <cookbook-dir> && ./setup.sh 2>&1
```

This takes ~5-10 minutes. The script handles: cloning repos, installing OpenShell, pulling the Docker image, applying patches, and installing NemoClaw.

If setup fails, diagnose the error:
- Patch failure → suggest `claude /refresh-patches`
- Docker error → check if Docker is running and has enough disk
- Network error → check connectivity
- NemoClaw install error → check the install.sh output for specifics

## Phase 4 — Post-install verification

Run these checks:

```bash
openshell --version
openshell status
nemoclaw --version
nemoclaw list
```

Report the results. If anything looks wrong, diagnose before proceeding.

## Phase 5 — Save the UI URL

```bash
cat ~/openclaw-ui-url.txt 2>/dev/null || echo "URL file not found"
```

Tell the user to save this URL — it's their access to the Web UI. Remind them it changes on every rebuild.

## Phase 6 — Authentication guidance

Tell the user they need to connect to the sandbox and authenticate:

> Now connect to the sandbox and authenticate your tools:
>
> ```
> nemoclaw my-assistant connect
> ```
>
> Then inside the sandbox, run these one at a time:
>
> ```
> claude login
> codex login --device-auth
> claude /plugin marketplace add openai/codex-plugin-cc
> claude /plugin install codex@openai-codex
> claude /reload-plugins
> ```
>
> Each login will print a URL — open it in your browser and authenticate.
> Let me know when you're done and I'll verify everything is working.

## Principles

- **Don't ask for what you can check.** If a file exists, read it. If a tool is installed, version-check it.
- **Minimize user burden.** Create files, set permissions, run commands. Only stop for things that require the user's credentials or browser.
- **Report state, not instructions.** Say "NVIDIA key is configured, Telegram is not" rather than "please check if your NVIDIA key is configured."
- **Be honest about timing.** The Docker pull and NemoClaw install take minutes. Set expectations.
