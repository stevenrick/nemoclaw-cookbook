# USE: NemoClaw Day-to-Day Reference

Quick reference for everything you can do with your running NemoClaw setup.

## Connecting to the Sandbox

```bash
nemoclaw my-assistant connect
```

Drops you into a shell inside the sandbox. Everything runs as the `sandbox` user with Landlock + seccomp + network policy enforcement.

## Web UI

Tokenized URLs are saved in `~/openclaw-ui-url.txt`. Open the Brev URL for remote access or the localhost URL for local. Treat these like passwords.

If the internal OpenShell port forward stops (sandbox is running but Web UI is unreachable on localhost):

```bash
openshell forward start 18789 my-assistant
```

Note: This is OpenShell's internal forwarding from sandbox to host. External access (Brev, ngrok, etc.) is configured separately on your hosting platform — see BUILD.md § Remote Access.

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
the policy may need updating (see BUILD_NEMOCLAW_README.md Step 5).

SSO tokens persist across restarts but not sandbox rebuilds. Re-run both logins after any rebuild.

### Using Codex directly

```bash
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

```bash
source ~/.env
export NVIDIA_API_KEY TELEGRAM_BOT_TOKEN ALLOWED_CHAT_IDS
nemoclaw start
```

### Manage

```bash
nemoclaw status    # Bridge and tunnel health
nemoclaw stop      # Stop everything
nemoclaw start     # Restart
```

### Security

`ALLOWED_CHAT_IDS` in `~/.env` restricts which Telegram accounts can talk to the bot. Get your chat ID from **@userinfobot**. Comma-separate multiple IDs.

### Approve network requests

When the agent wants to make external requests, you approve them via:

```bash
openshell term
```

## Inference

### Check current config

```bash
openshell inference get
```

### Switch models

```bash
# Lightweight model
openshell inference set --provider nvidia-prod --model nvidia/nemotron-3-nano-30b-a3b

# Default large model
openshell inference set --provider nvidia-prod --model nvidia/nemotron-3-super-120b-a12b

# Increase timeout (seconds)
openshell inference update --timeout 300
```

Changes are gateway-scoped (shared across all sandboxes) and hot-reload in ~5 seconds.

## Sandbox Management

```bash
nemoclaw list                         # List all sandboxes
nemoclaw my-assistant status          # Health, model, policies
nemoclaw my-assistant logs --follow   # Stream logs
nemoclaw my-assistant connect         # Shell in
nemoclaw my-assistant destroy         # Delete (WARNING: deletes workspace files)
```

## Network Policies

```bash
nemoclaw my-assistant policy-list     # Show available and applied presets
nemoclaw my-assistant policy-add      # Add a preset
```

Default presets: `pypi`, `npm`, `telegram` (plus built-in policies for GitHub, Discord, NVIDIA, Anthropic, etc.)

## Updating OpenClaw

When the web UI shows "Update available":

```bash
source ~/.env && export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1
[ -n "${CHAT_UI_URL:-}" ] && export CHAT_UI_URL

docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest
nemoclaw my-assistant destroy --yes
nemoclaw onboard
```

After rebuild: save new tokenized URL, re-run `claude login`, restart Telegram bridge.

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

## Key Files

| Path | Purpose |
|------|---------|
| `~/.env` | API keys and tokens (sourced before commands) |
| `~/openclaw-ui-url.txt` | Tokenized web UI URLs |
| `~/.nemoclaw/credentials.json` | Inference provider credentials (host-side) |
| `~/.nemoclaw/sandboxes.json` | Sandbox registry |
| `~/NemoClaw/Dockerfile` | Customized sandbox image (includes Claude Code) |
| `~/BUILD_NEMOCLAW_README.md` | How to rebuild from scratch |

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
