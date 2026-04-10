# USE: NemoClaw Day-to-Day Reference

Quick reference for everything you can do with your running NemoClaw setup.

> **Sandbox name:** Examples below use `my-assistant`, which is the default. If you set `NEMOCLAW_SANDBOX_NAME` during setup, substitute your name. Run `nemoclaw list` to check.

## Connecting to the Sandbox

The sandbox is not a regular Docker container — it runs inside OpenShell's K3s cluster. Don't use `docker exec`.

**Interactive (via brev shell):**

```bash
brev shell <instance>
nemoclaw my-assistant connect
```

**Non-interactive (via brev exec + SSH proxy):**

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' \
  sandbox@openshell-my-assistant '<command>'"
```

The non-interactive method works for both humans and agents. Use it for automation, scripting, and relaying auth URLs.

## Web UI

**If you configured a Secure Link** (`TUNNEL_FQDN` in `.env`):

```bash
brev exec <instance> "cat ~/openclaw-tunnel-url.txt"
```

Open that URL — nginx proxies to the dashboard with Origin rewriting, so no port-forward or `127.0.0.1` restrictions.

**If using port-forward** (no `TUNNEL_FQDN`):

```bash
brev port-forward <instance> -p 18789:18789
brev exec <instance> "cat ~/openclaw-ui-url.txt"
```

Open the URL with `127.0.0.1` (not `localhost` — the sandbox CORS config requires it).

**If the URL file is missing**, regenerate it:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/save-ui-url.sh"
```

If the internal OpenShell port forward stops (sandbox is running but Web UI is unreachable):

```bash
brev exec <instance> "openshell forward start 18789 my-assistant --background"
```

## Browser Terminal

If the terminal server is enabled (`ENABLE_TERMINAL_SERVER=true` in `.env`, default), you can access an `openshell term` session in the browser:

```
https://<your-secure-link>/terminal#token=<hex>
```

Or via port-forward: `http://127.0.0.1/terminal#token=<hex>` (requires nginx on port 80).

This gives you the OpenShell egress approval TUI — approve or deny sandbox network requests from any browser.

## OpenClaw (inside the sandbox)

```bash
openclaw tui                                                    # Interactive terminal UI
openclaw agent --agent main --local -m "hello" --session-id test  # One-off message
```

## Coding Agents (Claude Code + Codex)

> These tools are only available if installed during setup (default: both enabled). Check with `INSTALL_CLAUDE_CODE` and `INSTALL_CODEX` in `.env`, or look at the deployment manifest: `cat ~/.nemoclaw/cookbook-deployment.json`.

NemoClaw's `coding-agent` skill automatically delegates coding tasks to Claude Code or Codex.
Just ask your agent (via Telegram, web UI, or terminal) to build something and it will spawn
the right coding agent in the background.

### Using Claude Code directly

```bash
brev shell <instance>
nemoclaw my-assistant connect
claude --dangerously-skip-permissions   # Full autonomy mode (safe inside OpenShell sandbox)
```

Claude Code has the Codex plugin installed (a plugin that runs inside Claude Code), adding these slash commands:
- `/codex:review` — code review
- `/codex:adversarial-review` — adversarial code review
- `/codex:rescue` — rescue stuck tasks

See https://github.com/openai/codex-plugin-cc for the full list.

If you get an auth error, re-authenticate:

```bash
codex login --device-auth   # Can be run non-interactively via brev exec
claude                       # Interactive TUI — follow login prompts
```

The login flow reaches `platform.claude.com`, `downloads.claude.ai`, and `raw.githubusercontent.com`.
These are pre-approved in the sandbox network policy. If you see blocked requests in `openshell term`,
the policy may need updating (see BUILD.md Step 5).

SSO tokens persist across restarts but not sandbox rebuilds. Re-run both logins after any rebuild.

### Using Codex directly

```bash
brev shell <instance>
nemoclaw my-assistant connect
codex                                   # Interactive mode
codex -q "explain this codebase"        # One-off query
```

### Delegating via NemoClaw (autonomous)

The OpenClaw agent inside the sandbox has a `coding-agent` skill that can spawn either Claude Code
or Codex as a background process. Just tell your agent what to build — via Telegram, the web UI,
or `openclaw tui` — and it handles the rest.

Examples you can send via Telegram:
- "Create a Python Flask API with health check and user endpoints"
- "Review the code in /sandbox/myproject and suggest improvements"
- "Refactor the database module to use async/await"

## Telegram

### How it works

Telegram messaging runs natively inside OpenClaw via the gateway delivery queue — no host-side bridge. Messages are async with no timeout, so long-running coding agent tasks work reliably. The Telegram token is injected at sandbox build time and the bot connects automatically.

`nemoclaw start` starts the Cloudflare quick tunnel needed for the Telegram webhook callback URL:

```bash
# If vars are already exported in your shell:
nemoclaw start

# If starting fresh (no ~/.env or vars not exported):
NVIDIA_API_KEY=<key> TELEGRAM_BOT_TOKEN=<token> ALLOWED_CHAT_IDS=<id> nemoclaw start
```

### Manage

```bash
nemoclaw status    # Tunnel health
nemoclaw stop      # Stop tunnel
nemoclaw start     # Restart tunnel
```

To check channel status inside the sandbox:
```bash
# Via brev exec + SSH proxy:
openclaw channels list        # Shows: Telegram main: configured, token=config, enabled
```

### Security

`ALLOWED_CHAT_IDS` in `.env` restricts which Telegram accounts can talk to the bot. Get your chat ID from **@userinfobot**. Comma-separate multiple IDs.

### Approve network requests

When the agent wants to make external requests, you approve them via:

```bash
openshell term
```

## Brave Search

If `BRAVE_API_KEY` is set in `.env`, the sandbox can reach `api.search.brave.com` for web search. The API key is injected via OpenShell's provider system — the sandbox never sees the real key.

### Adding Brave Search to an existing sandbox

1. Add `BRAVE_API_KEY` to your `.env` file.
2. Run `/upgrade` in Claude Code — it detects the new key, creates the provider, and rebuilds the sandbox.

`/upgrade` backs up your workspace automatically and restores your agent's memory and personality after the rebuild.

### Adding Brave Search during fresh setup

Add the key to `.env` before running `./setup.sh` — it's picked up automatically.

## Inference

### Check current config

```bash
openshell inference get
```

### Switch models

Set `NEMOCLAW_MODEL` in `.env` before setup/rebuild, or switch at runtime:

```bash
# Lightweight model
openshell inference set --provider nvidia-prod --model nvidia/nemotron-3-nano-30b-a3b

# Default large model
openshell inference set --provider nvidia-prod --model nvidia/nemotron-3-super-120b-a12b

# Non-NVIDIA model (if configured)
openshell inference set --provider nvidia-prod --model openai/gpt-oss-120b

# Increase timeout (seconds)
openshell inference update --timeout 300
```

Changes are gateway-scoped (shared across all sandboxes) and hot-reload in ~5 seconds.

## Sandbox Management

```bash
nemoclaw list                         # List all sandboxes
nemoclaw my-assistant status          # Health, model, policies
nemoclaw my-assistant logs --follow   # Stream logs
nemoclaw my-assistant connect         # Shell in (via brev shell)
nemoclaw my-assistant destroy         # Delete (WARNING: deletes workspace files)
```

## System Services

The deployment uses systemd for infrastructure. All services auto-start on boot.

```bash
# Check status
systemctl status openshell-gateway     # OpenShell gateway (sandbox runtime)
systemctl status nemoclaw-terminal     # Browser terminal server (if enabled)
sudo systemctl status nginx            # Reverse proxy

# View logs
journalctl -u openshell-gateway -f     # Follow gateway logs
journalctl -u nemoclaw-terminal -n 50  # Last 50 terminal server lines
sudo tail -f /var/log/nginx/error.log  # nginx errors

# Restart (brief interruption)
systemctl restart openshell-gateway    # Restart gateway
sudo systemctl restart nginx           # Restart proxy
```

**`nemoclaw start/stop` vs `systemctl`:** `nemoclaw start` only starts the Cloudflare tunnel (needed for Telegram webhooks). The gateway and sandbox run continuously under systemd, independent of `nemoclaw start/stop`.

## Network Policies

```bash
nemoclaw my-assistant policy-list     # Show available and applied presets
nemoclaw my-assistant policy-add      # Add a preset
```

Default presets: `pypi`, `npm`, `telegram` (plus built-in policies for GitHub, Discord, NVIDIA, Anthropic, etc.)

## Backup & Restore

Snapshot your sandbox state to your local machine, and restore it later to any NemoClaw instance.

**What's backed up:** workspace files (SOUL.md, USER.md, IDENTITY.md, AGENTS.md, HEARTBEAT.md, TOOLS.md, memory/), chat session history, and installed skills.

**Not backed up:** infrastructure config (nginx, systemd — reinstalled by `install-services.sh`), Docker images (pulled fresh on rebuild), API credentials (stay in `.env` on host).

**Claude Code users:** use `/backup` and `/restore` — they handle the full workflow interactively.

Backups are stored locally in `backups/<timestamp>/` (gitignored). Each backup includes a `backup-meta.json` with the timestamp, source instance, sandbox name, and what's included.

### Manual backup/restore (on the host)

```bash
# Backup workspace + sessions + skills
~/nemoclaw-cookbook/scripts/backup-full.sh backup <sandbox>

# List available backups
~/nemoclaw-cookbook/scripts/backup-full.sh list

# Restore latest backup (workspace + sessions in one step — use when gateway is not running)
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox>

# Restore a specific backup
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> 2026-04-05_143022

# Two-phase restore (use after rebuild when gateway is already running)
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> '' workspace   # phase 1: before nemoclaw start
nemoclaw start                                                             # start services
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> '' sessions    # phase 2: after nemoclaw start
```

Replace `<sandbox>` with your sandbox name (default: `my-assistant` — run `nemoclaw list` to check).

Backups on the host are stored at `~/.nemoclaw/backups/<timestamp>/`.

**Session restore note:** After a rebuild, sessions must be restored **after** `nemoclaw start`. The gateway reads sessions.json from disk on each operation, so restoring after start overwrites whatever the gateway created during channel reconnect. Restoring before start would be overwritten when Telegram/Discord channels reconnect.

## Updating OpenClaw

**Claude Code users:** run `/upgrade` — it checks versions, backs up, rebuilds, restores, and re-authenticates automatically.

### Manual fallback

If you need to upgrade without Claude Code, run via `brev exec` or inside `brev shell`:

```bash
source ~/.env && export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1

# 1. Back up
~/nemoclaw-cookbook/scripts/backup-full.sh backup <sandbox>

# 2. Pull latest upstream
cd ~/nemoclaw-cookbook && git pull
cd ~/NemoClaw && git pull --ff-only origin main
cd ~/OpenShell && git pull --ff-only origin main && sh install.sh
docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest

# 3. Validate patches BEFORE destroying (critical — if this fails, stop here)
cd ~/NemoClaw && git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
~/nemoclaw-cookbook/scripts/apply-patches.sh ~/NemoClaw

# 4. Destroy and rebuild
nemoclaw stop 2>/dev/null
nemoclaw <sandbox> destroy --yes
nemoclaw onboard

# 5. Restore workspace, start services, then restore sessions
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> '' workspace
nemoclaw start
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> '' sessions
```

Replace `<sandbox>` with your sandbox name (run `nemoclaw list` to check).

After rebuild:
- Update the deployment manifest: `~/nemoclaw-cookbook/scripts/write-manifest.sh`
- Re-authenticate: `codex login --device-auth` then launch `claude` (login forced on first launch)
- Reinstall the Codex plugin inside Claude Code
- Restart messaging: `nemoclaw start` (with tokens exported)

## Claude Code Skills

If you use [Claude Code](https://claude.ai/code) in this repo, these slash commands are available:

| Skill | What it does |
|-------|-------------|
| `/setup` | End-to-end deployment — env config, prerequisites, deploy, auth |
| `/upgrade` | Check versions, update host tooling, rebuild sandbox if needed. Also handles adding integrations (e.g., Brave Search) — just update `.env` and run `/upgrade` |
| `/backup` | Snapshot workspace, sessions, and skills to local `backups/` directory |
| `/restore` | Push a local backup to a remote sandbox |
| `/brev` | Run commands on the remote instance — inspect, manage, transfer files |
| `/dev` | Debug NemoClaw/OpenClaw/OpenShell issues, read sandbox logs, test upstream branches |
| `/refresh-patches` | Update patch fragments when upstream NemoClaw changes break them |

Key concepts from the skills:
- **`/upgrade` distinguishes host-only updates from sandbox rebuilds.** CLI updates (NemoClaw, OpenShell) don't need a rebuild — zero downtime. Image changes (new tools, new sandbox-base) require backup/destroy/rebuild/restore.
- **Patches are validated before anything is destroyed.** If fragments fail against new upstream, `/upgrade` aborts with your sandbox intact.
- **Upstream overlap is audited automatically.** `/upgrade` and `/refresh-patches` check if upstream now provides something we previously patched, so we can trim our fragments.

## Diagnostics

```bash
nemoclaw debug                        # Full diagnostic dump
nemoclaw debug --quick                # Quick health check
openshell doctor                      # Gateway-level diagnostics
openshell status                      # Gateway connection status
~/nemoclaw-cookbook/scripts/verify-deployment.sh   # Cookbook health check (gateway, sandbox, dashboard, tools, manifest)
```

## Upgrading OpenClaw (experimental)

The sandbox-base image bundles a specific OpenClaw version (pinned by NemoClaw). To use a different version, set `OPENCLAW_VERSION` in `~/.env`:

```bash
OPENCLAW_VERSION=<version-tag>
```

This rebuilds the sandbox-base image locally (~5-10 min first time, cached after). The entire base image is rebuilt so everything stays in sync — config, UI, plugins, auth. Run `setup.sh` or `/upgrade` afterward to apply.

**You are responsible for testing your chosen version.** Not all OpenClaw versions are compatible with the current NemoClaw release — tool schemas, UI scopes, and plugin dependencies can change between versions. See BUILD.md and the `/dev` skill for diagnostic approaches. Remove the variable to revert to the upstream default.

## Troubleshooting

### Web UI unreachable after rebuild
The internal OpenShell port forward (18789) can die during sandbox destroy/rebuild. `verify-deployment.sh` detects and auto-restarts it, but if running manually:
```bash
openshell forward start 18789 my-assistant --background
```

### `nemoclaw` crashes with MODULE_NOT_FOUND after `git pull`
Upstream NemoClaw added new TypeScript modules but the CLI wasn't rebuilt. Run `setup.sh` (which handles the full rebuild) or:
```bash
cd ~/NemoClaw && bash install.sh --non-interactive
```

### `git pull` fails in ~/NemoClaw with "local changes would be overwritten"
Our patches modify the Dockerfile and policy YAML. Reset before pulling:
```bash
cd ~/NemoClaw && git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml && git pull
```
`setup.sh` handles this automatically.

### `setup.sh` ran but sandbox still has old tools/patches
`nemoclaw onboard` reuses an existing healthy sandbox instead of rebuilding. If upstream or patches changed, `setup.sh` auto-detects the drift and forces a rebuild. You can also force it manually:
```bash
export NEMOCLAW_RECREATE_SANDBOX=1
./setup.sh
```

## How Security Works

- API keys live on the host at `~/.nemoclaw/credentials.json` -- never exposed inside the sandbox
- The sandbox hits `https://inference.local/v1` for inference; the host proxy injects credentials server-side
- Filesystem: Landlock restricts writes to `/sandbox` and `/tmp`; system paths are read-only
- Network: only policy-approved hosts/ports are reachable
- Process: runs as unprivileged `sandbox` user with seccomp filtering
- Claude Code's `--dangerously-skip-permissions` is safe here because OpenShell enforces all the above constraints

## Agent Workspace (inside the sandbox)

The OpenClaw agent's workspace lives at `/sandbox/.openclaw-data/workspace/`:

| File | Purpose |
|------|---------|
| `SOUL.md` | Agent personality and behavioral guidelines |
| `IDENTITY.md` | Agent name and identity (default: "Nemo") |
| `USER.md` | Learned information about the user |
| `AGENTS.md` | Agent operating manual — memory, heartbeats, group chat rules |
| `TOOLS.md` | Environment-specific notes (SSH hosts, device names, etc.) |
| `HEARTBEAT.md` | Periodic check tasks (empty = skip heartbeats) |
| `memory/` | Daily notes (`YYYY-MM-DD.md`) and long-term `MEMORY.md` |

Chat session history lives at `/sandbox/.openclaw-data/agents/main/sessions/` (JSONL files).

The backup script (`scripts/backup-full.sh`) backs up workspace files, session history, and installed skills.

### Copying files to/from the sandbox

The sandbox filesystem is isolated — you can't access it directly from the host. Use `openshell sandbox download/upload` to transfer via a staging directory, then clean up.

**On the host** (or via `brev exec`):

```bash
# Download: sandbox → host
openshell sandbox download my-assistant /sandbox/.openclaw-data/workspace/myfile.md /tmp/sandbox-staging/
# Note: creates /tmp/sandbox-staging/myfile.md (wraps file in a directory)
cp /tmp/sandbox-staging/myfile.md ./myfile.md
rm -rf /tmp/sandbox-staging

# Upload: host → sandbox
openshell sandbox upload my-assistant ./myfile.md /sandbox/.openclaw-data/workspace/
```

**From your local machine via Brev** (three hops — sandbox → host staging → local):

```bash
# Download: sandbox → local
brev exec <instance> "openshell sandbox download my-assistant /sandbox/path/file.md /tmp/sandbox-staging/"
brev copy <instance>:/tmp/sandbox-staging/file.md ./file.md
brev exec <instance> "rm -rf /tmp/sandbox-staging"

# Upload: local → sandbox
brev copy ./file.md <instance>:/tmp/sandbox-staging/file.md
brev exec <instance> "openshell sandbox upload my-assistant /tmp/sandbox-staging/file.md /sandbox/path/"
brev exec <instance> "rm -rf /tmp/sandbox-staging"
```

Always clean up `/tmp/sandbox-staging` after transfers.

## Remote Automation (Brev CLI)

When running on a Brev instance, you can manage everything from your local machine without an interactive shell.

### Commands on the host (nemoclaw, openshell)

Non-interactive SSH doesn't source `.bashrc`, so source nvm and set PATH explicitly:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && nemoclaw list"
```

### Commands inside the sandbox

The sandbox runs inside OpenShell's K3s cluster, not as a Docker container. Reach it via the OpenShell SSH proxy:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' \
  sandbox@openshell-my-assistant '<command>'"
```

### Starting Telegram remotely

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" \
  && NVIDIA_API_KEY=<key> TELEGRAM_BOT_TOKEN=<token> ALLOWED_CHAT_IDS=<id> nemoclaw start"
```

### Accessing the Web UI

**Secure Link** (if `TUNNEL_FQDN` is set in `.env`):
```bash
brev exec <instance> "cat ~/openclaw-tunnel-url.txt"   # Open this URL directly
```

**Port forward** (fallback):
```bash
brev port-forward <instance> -p 18789:18789   # Returns immediately (backgrounded SSH tunnel)
brev exec <instance> "cat ~/openclaw-ui-url.txt"       # Use 127.0.0.1, not localhost
```

See also: `/brev` skill in Claude Code for the full reference.

## Key Files

| Path | Purpose |
|------|---------|
| `.env` (repo) → `~/.env` (remote) | API keys and tokens — edit locally, copied to instance during deploy |
| `~/openclaw-ui-url.txt` | Tokenized web UI URL (auto-generated by `setup.sh` / `save-ui-url.sh`) |
| `~/.nemoclaw/credentials.json` | Inference provider credentials (host-side) |
| `~/.nemoclaw/sandboxes.json` | Sandbox registry |
| `~/.nemoclaw/cookbook-deployment.json` | Deployment manifest — versions, tools, providers (written by setup/upgrade) |
| `~/NemoClaw/Dockerfile` or `~/.nemoclaw/source/Dockerfile` | Customized sandbox image (includes Claude Code) |
| `~/nemoclaw-cookbook/BUILD.md` | How to rebuild from scratch |

## Shell Environment

If commands aren't found:

```bash
source ~/.bashrc
```

## Resources

- NemoClaw Docs: https://docs.nvidia.com/nemoclaw/latest/
- OpenShell Docs: https://docs.nvidia.com/openshell/latest/
- NemoClaw GitHub: https://github.com/NVIDIA/NemoClaw
- OpenShell GitHub: https://github.com/NVIDIA/OpenShell
- NemoClaw Discord: https://discord.gg/XFpfPv9Uvx
