---
name: brev
description: Run commands on the remote NemoClaw instance via Brev CLI (brev exec/copy/ls). Use when you need to inspect, manage, or operate the remote sandbox without an interactive shell.
allowed-tools: Bash Read Grep Glob AskUserQuestion
---

# Brev — Remote Instance Management

Execute commands, transfer files, and manage the NemoClaw instance on Brev — all non-interactively via `brev exec`, `brev copy`, and lifecycle commands.

**Important:** The sandbox name is NOT always `my-assistant`. Always look it up via `nemoclaw list` on the remote instance. Use the discovered name in place of `<sandbox>` in all examples below.

## When to use this skill

- Checking remote state (logs, processes, file contents)
- Running commands inside the NemoClaw sandbox remotely
- Copying files to/from the instance
- Managing instance lifecycle (start/stop/status)
- Connecting to the Web UI via port forward

## Phase 1 — Discover the instance

```bash
brev ls
```

Identify the instance name from the output. If no instances are listed, the user needs to create one first — ask them.

If the instance is STOPPED, start it:

```bash
brev start <instance-name>
```

## Phase 2 — Connect (Web UI)

**If `TUNNEL_FQDN` is configured** (Secure Link — check `.env`):

```bash
brev exec <instance> "cat ~/openclaw-tunnel-url.txt 2>/dev/null"
```

Give this URL to the user — nginx proxies to the dashboard with Origin rewriting, so it works directly in any browser.

**If no Secure Link** (port-forward fallback):

```bash
lsof -i :18789 2>/dev/null && echo "already forwarded" || brev port-forward <instance> -p 18789:18789
brev exec <instance> "cat ~/openclaw-ui-url.txt 2>/dev/null"
```

Use `127.0.0.1` (not `localhost`) — the sandbox CORS config requires it.

## Phase 3 — Execute the requested work

### Running commands on the host

Commands run via `brev exec` land on the Brev VM (the host). NemoClaw management commands (`nemoclaw`, `openshell`) run here. Source nvm and set PATH explicitly since `.bashrc` isn't sourced in non-interactive mode:

```bash
brev exec <instance> "[ -s \$HOME/.nvm/nvm.sh ] && . \$HOME/.nvm/nvm.sh; export PATH=\"\$HOME/.local/bin:\$PATH\" && <command>"
```

### Running commands inside the sandbox

The sandbox is an OpenShell-managed container, not a regular Docker container. Reach it via SSH through the OpenShell proxy:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name <sandbox>' sandbox@openshell-<sandbox> '<command>'"
```

This is verbose but reliable. Use it to read/write workspace files, check installed tools, etc.

### Copying files

```bash
# Local to remote (host)
brev copy ./local-file <instance>:/remote/path/

# Remote to local
brev copy <instance>:/remote/path/file ./local-destination

# Directories
brev copy ./local-dir/ <instance>:/remote/path/
```

### Copying files out of the sandbox (sandbox → local)

Three hops: sandbox → host staging → local, then clean up staging. `openshell sandbox download` wraps files in a directory, so always use a staging dir on the host:

```bash
# 1. Download from sandbox to host staging dir
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$PATH\" && openshell sandbox download <sandbox> /sandbox/path/to/file.md /tmp/sandbox-staging/"

# 2. Copy from host to local (default: current working directory)
brev copy <instance>:/tmp/sandbox-staging/file.md ./file.md

# 3. Clean up staging on host
brev exec <instance> "rm -rf /tmp/sandbox-staging"
```

Always clean up the staging dir after copying. Don't leave artifacts on the host.

### Copying files into the sandbox (local → sandbox)

Same pattern in reverse, with cleanup:

```bash
# 1. Copy from local to host staging dir
brev copy ./file.txt <instance>:/tmp/sandbox-staging/file.txt

# 2. Upload from host to sandbox
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$PATH\" && openshell sandbox upload <sandbox> /tmp/sandbox-staging/file.txt /sandbox/path/"

# 3. Clean up staging on host
brev exec <instance> "rm -rf /tmp/sandbox-staging"
```

## Sandbox workspace layout

The agent's workspace lives at `/sandbox/.openclaw-data/workspace/` inside the sandbox:

```
/sandbox/.openclaw-data/
  workspace/
    SOUL.md              # Agent personality and behavioral guidelines
    IDENTITY.md          # Agent name and identity (default: "Nemo")
    USER.md              # Learned info about the user
    AGENTS.md            # Agent operating manual (memory, heartbeats, tools)
    TOOLS.md             # Environment-specific notes (SSH hosts, cameras, etc.)
    HEARTBEAT.md         # Periodic check tasks (empty = skip heartbeats)
    memory/              # Daily notes (YYYY-MM-DD.md) and long-term MEMORY.md
    .openclaw/           # Internal state
  agents/main/sessions/  # Chat session history (JSONL)
  skills/                # Installed OpenClaw skills
  devices/               # Device auth tokens
```

The backup script (`scripts/backup-full.sh`) backs up both `workspace/` and `agents/main/sessions/`.

## Common tasks

### Check NemoClaw status

```bash
brev exec <instance> "[ -s \$HOME/.nvm/nvm.sh ] && . \$HOME/.nvm/nvm.sh; export PATH=\"\$HOME/.local/bin:\$PATH\" && nemoclaw list && openshell sandbox list && openshell status"
```

### Start Telegram bridge

Requires env vars in the process environment (not a file):

```bash
brev exec <instance> "[ -s \$HOME/.nvm/nvm.sh ] && . \$HOME/.nvm/nvm.sh; export PATH=\"\$HOME/.local/bin:\$PATH\" && export TELEGRAM_BOT_TOKEN=<token> TELEGRAM_ALLOWED_IDS=<id> NVIDIA_API_KEY=<key> && nemoclaw tunnel start"
```

### Read sandbox workspace files

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name <sandbox>' sandbox@openshell-<sandbox> 'cat /sandbox/.openclaw-data/workspace/SOUL.md'"
```

### Check what's installed inside the sandbox

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name <sandbox>' sandbox@openshell-<sandbox> 'ls /usr/local/bin/ && claude --version 2>/dev/null && codex --version 2>/dev/null'"
```

### Pull latest cookbook and redeploy

```bash
brev exec <instance> "cd ~/nemoclaw-cookbook && git pull"
brev exec <instance> "cd ~/nemoclaw-cookbook && ./setup.sh"
```

## Limitations

- **No interactive sessions.** `brev shell` requires a terminal — use `brev exec` for everything.
- **No browser auth for Claude.** Claude Code uses a full TUI — auth requires `brev shell` (interactive). Codex auth (`codex login --device-auth`) works via `brev exec` — it prints a URL + code that can be relayed to the user.
- **Timeouts.** Long-running commands may exceed the 2-minute default Bash timeout. Use `timeout` parameter up to 600000ms (10 min), or run in background and poll.
- **No stdin.** Commands that prompt for input will hang. Always use non-interactive flags (e.g., `NEMOCLAW_NON_INTERACTIVE=1`).
- **PATH not set.** Non-interactive SSH doesn't source `.bashrc`. Always source nvm and export PATH for `nemoclaw`/`openshell` commands.

## Principles

- **Prefer `brev exec` over asking the user to SSH in.** If you can do it remotely, do it.
- **Prefer Secure Links when configured.** If `TUNNEL_FQDN` is set in `.env`, use `~/openclaw-tunnel-url.txt`. Fall back to `brev port-forward` only when no Secure Link is configured.
- **Report results, don't dump raw output.** Summarize what you find; include key details.
- **Check instance status first.** A stopped instance will cause exec to auto-start it (with a 10-min timeout), but it's better to be explicit.
