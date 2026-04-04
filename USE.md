# USE: NemoClaw Day-to-Day Reference

Quick reference for everything you can do with your running NemoClaw setup.

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

Forward the Web UI port to your local machine:

```bash
brev port-forward <instance> -p 18789:18789
```

Get the tokenized URL (treat it like a password — changes on every rebuild):

```bash
brev exec <instance> "cat ~/openclaw-ui-url.txt"
```

Replace the hostname with `localhost:18789` and open in your browser.

If the internal OpenShell port forward stops (sandbox is running but Web UI is unreachable):

```bash
brev exec <instance> "openshell forward start 18789 my-assistant"
```

## OpenClaw (inside the sandbox)

```bash
openclaw tui                                                    # Interactive terminal UI
openclaw agent --agent main --local -m "hello" --session-id test  # One-off message
```

## Coding Agents (Claude Code + Codex)

NemoClaw's `coding-agent` skill automatically delegates coding tasks to Claude Code or Codex.
Just ask your agent (via Telegram, web UI, or terminal) to build something and it will spawn
the right coding agent in the background.

### Using Claude Code directly

```bash
brev shell <instance>
nemoclaw my-assistant connect
claude --dangerously-skip-permissions   # Full autonomy mode (safe inside OpenShell sandbox)
```

Claude Code has the Codex plugin installed, adding these slash commands:
- `/codex:review` — code review
- `/codex:adversarial-review` — adversarial code review
- `/codex:rescue` — rescue stuck tasks

See https://github.com/openai/codex-plugin-cc for the full list.

If you get an auth error, re-authenticate:

```bash
claude login
codex login --device-auth
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

### Start the bridge

`nemoclaw start` reads env vars directly from the process environment (no dotenv/file loading). If you've exported them in your shell, just run `nemoclaw start`. Otherwise, pass them explicitly:

```bash
# If vars are already exported in your shell:
nemoclaw start

# If starting fresh (no ~/.env or vars not exported):
NVIDIA_API_KEY=<key> TELEGRAM_BOT_TOKEN=<token> ALLOWED_CHAT_IDS=<id> nemoclaw start
```

This starts both the Telegram bridge and a Cloudflare quick tunnel (needed for the Telegram webhook callback URL). The output shows the tunnel URL and bridge status.

### Manage

```bash
nemoclaw status    # Bridge and tunnel health
nemoclaw stop      # Stop everything
nemoclaw start     # Restart
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

```bash
# If you added the key after initial setup, use:
claude /add-integration
```

This backs up your workspace, creates the provider, recreates the sandbox, and restores your agent's memory and personality.

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

## Network Policies

```bash
nemoclaw my-assistant policy-list     # Show available and applied presets
nemoclaw my-assistant policy-add      # Add a preset
```

Default presets: `pypi`, `npm`, `telegram` (plus built-in policies for GitHub, Discord, NVIDIA, Anthropic, etc.)

## Updating OpenClaw

When the web UI shows "Update available". Run via `brev exec` or inside `brev shell`:

```bash
source ~/.env && export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1

# Back up workspace + chat history first
~/nemoclaw-cookbook/scripts/backup-full.sh backup my-assistant

# Rebuild
docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest
nemoclaw my-assistant destroy --yes
nemoclaw onboard

# Restore workspace + chat history
~/nemoclaw-cookbook/scripts/backup-full.sh restore my-assistant
```

After rebuild:
- Re-run `claude login` and `codex login --device-auth` (SSO tokens don't survive rebuilds)
- Reinstall the Codex plugin
- Restart messaging: `nemoclaw start`

## Diagnostics

```bash
nemoclaw debug                        # Full diagnostic dump
nemoclaw debug --quick                # Quick health check
openshell doctor                      # Gateway-level diagnostics
openshell status                      # Gateway connection status
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

The backup script (`scripts/backup-full.sh`) backs up both workspace and session files.

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

Non-interactive SSH doesn't source `.bashrc`, so PATH must be set explicitly:

```bash
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$HOME/.nvm/versions/node/v22.22.2/bin:\$PATH\" && nemoclaw list"
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
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$HOME/.nvm/versions/node/v22.22.2/bin:\$PATH\" \
  && NVIDIA_API_KEY=<key> TELEGRAM_BOT_TOKEN=<token> ALLOWED_CHAT_IDS=<id> nemoclaw start"
```

### Port forwarding the Web UI

```bash
brev port-forward <instance> -p 18789:18789   # Returns immediately (backgrounded SSH tunnel)
```

See also: `/brev` skill in Claude Code for the full reference.

## Key Files

| Path | Purpose |
|------|---------|
| `.env` (repo) → `~/.env` (remote) | API keys and tokens — edit locally, copied to instance during deploy |
| `~/openclaw-ui-url.txt` | Tokenized web UI URLs |
| `~/.nemoclaw/credentials.json` | Inference provider credentials (host-side) |
| `~/.nemoclaw/sandboxes.json` | Sandbox registry |
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
