# USE: NemoClaw Day-to-Day Reference

Examples use the default sandbox name, `my-assistant`. If you set `NEMOCLAW_SANDBOX_NAME`, substitute your name. Check with:

```bash
nemoclaw list
```

## Connect

Interactive:

```bash
brev shell <instance>
nemoclaw my-assistant connect
```

Non-interactive command inside the sandbox:

```bash
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' \
  sandbox@openshell-my-assistant '<command>'"
```

The sandbox is managed by OpenShell. Do not use `docker exec` as the normal access path.

## Endpoints

| Endpoint | URL / Command | Purpose |
|----------|---------------|---------|
| Web UI | `~/openclaw-tunnel-url.txt` or `~/openclaw-ui-url.txt` | Dashboard chat, skills, settings |
| Browser terminal | `/terminal#token=<hex>` on the same host | OpenShell policy approval TUI |
| CLI | `nemoclaw <sandbox> connect` | Terminal UI inside the sandbox |
| Telegram / Discord / Slack | Your configured bot or app | Async messaging |
| OpenAI-compatible HTTP | `~/openclaw-openai.env` | Optional `/v1/*` client settings |

Open URLs without printing the tokenized value:

```bash
# Secure Link
URL=$(brev exec <instance> "sed -n '1p' ~/openclaw-tunnel-url.txt" | sed -n '/^https:/p' | head -1)
open "$URL"

# Browser terminal on that Secure Link
TERMINAL_URL=$(printf '%s' "$URL" | sed 's#/#/terminal#3')
open "$TERMINAL_URL"
```

Port-forward fallback:

```bash
brev port-forward <instance> -p 18789:18789
URL=$(brev exec <instance> "sed -n '1p' ~/openclaw-ui-url.txt" | sed -n '/^http:/p' | head -1)
open "$URL"
```

If URL files are missing:

```bash
brev exec <instance> "~/nemoclaw-cookbook/scripts/save-ui-url.sh"
```

Upstream NemoClaw can also expose the browser URL and raw gateway token for troubleshooting. Redact the URL and check only token length in shared logs:

```bash
nemoclaw my-assistant dashboard-url --quiet | sed -E 's/#token=.*/#token=<redacted>/'
nemoclaw my-assistant gateway-token --quiet | wc -c
```

## OpenClaw Inside the Sandbox

```bash
openclaw tui
openclaw agent --agent main --local -m "hello" --session-id test
openclaw channels list
```

## Messaging

Messaging is handled by upstream NemoClaw/OpenClaw. Configure tokens in `~/.env` before setup:

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_IDS=...
TELEGRAM_REQUIRE_MENTION=1
DISCORD_BOT_TOKEN=...
DISCORD_SERVER_ID=...
DISCORD_ALLOWED_IDS=...
DISCORD_REQUIRE_MENTION=1
SLACK_BOT_TOKEN=...
SLACK_APP_TOKEN=...
SLACK_ALLOWED_USERS=...
SLACK_ALLOWED_CHANNELS=...
```

Slack requires both the bot token and the app-level Socket Mode token. Upstream validates token formats during onboarding; placeholder values are ignored.

Start or stop an optional upstream Cloudflare tunnel:

```bash
source ~/.env
nemoclaw tunnel start
nemoclaw tunnel stop
nemoclaw status
```

Messaging channels and their required policy presets are handled by upstream onboarding and rebuild commands. Set `NEMOCLAW_POLICY_TIER`, `NEMOCLAW_POLICY_MODE`, or `NEMOCLAW_POLICY_PRESETS` only when you want to override upstream's suggested policy selection.

## Web Search

Configure one provider in `~/.env`:

```bash
BRAVE_API_KEY=BSA-...     # Native upstream
TAVILY_API_KEY=tvly-...   # Cookbook overlay
```

If both are set, the cookbook config gives Tavily priority for OpenClaw web search. After changing web-search configuration, rerun:

```bash
cd ~/nemoclaw-cookbook && ./setup.sh
```

## Inference

Check current gateway inference:

```bash
openshell inference get
```

Switch model at runtime:

```bash
openshell inference set --provider nvidia-prod --model nvidia/nemotron-3-super-120b-a12b
openshell inference update --timeout 300
```

Or set `NEMOCLAW_MODEL` / `NEMOCLAW_PROVIDER` in `~/.env` before setup.

## Resources

Inspect upstream sandbox resource profiles:

```bash
nemoclaw resources
nemoclaw resources --json
```

Set a profile before setup:

```bash
NEMOCLAW_RESOURCE_PROFILE=developer
```

`NEMOCLAW_CPU` and `NEMOCLAW_RAM` can override profile values for scripted runs.

## OpenAI-Compatible HTTP API

Enable before setup:

```bash
NEMOCLAW_OPENAI_HTTP_ENABLED=1
```

Load client settings after deploy:

```bash
source ~/openclaw-openai.env
```

Smoke test from the Brev host:

```bash
python -c "from openai import OpenAI; print([m.id for m in OpenAI().models.list().data])"
```

For laptop clients, prefer an SSH port-forward:

```bash
ssh -L 8080:127.0.0.1:80 <brev-host>
OPENAI_BASE_URL=http://127.0.0.1:8080/v1 OPENAI_API_KEY=<gateway-token> python your_client.py
```

`NEMOCLAW_OPENAI_HTTP_TUNNEL=1` removes nginx's loopback-only guard for `/v1/*`. Use it only when nginx is intentionally exposed directly on the host network and the gateway token is the external auth boundary.

## Sandbox Management

```bash
nemoclaw list
nemoclaw my-assistant status
nemoclaw my-assistant logs --follow
nemoclaw my-assistant connect
nemoclaw my-assistant recover
nemoclaw my-assistant destroy --yes
```

Back up before destroy or rebuild.

## System Services

The cookbook manages nginx and the optional browser terminal service. Upstream `nemoclaw` manages the OpenShell gateway lifecycle.

```bash
systemctl status nemoclaw-terminal
sudo systemctl status nginx
journalctl -u nemoclaw-terminal -n 50
sudo tail -f /var/log/nginx/error.log
sudo systemctl restart nginx

nemoclaw my-assistant recover
tail -f ~/.local/state/nemoclaw/openshell-docker-gateway/openshell-gateway.log
```

## Network Policies

```bash
nemoclaw my-assistant policy-list
nemoclaw my-assistant policy-add
openshell term
```

Use the browser terminal at `/terminal#token=<hex>` when you want policy approvals without an SSH session.

## Backup and Restore

The backup script snapshots workspace files, chat sessions, and installed skills. It does not back up credentials, Docker images, nginx, or systemd units.

```bash
~/nemoclaw-cookbook/scripts/backup-full.sh backup my-assistant
~/nemoclaw-cookbook/scripts/backup-full.sh list
~/nemoclaw-cookbook/scripts/backup-full.sh restore my-assistant
~/nemoclaw-cookbook/scripts/backup-full.sh restore my-assistant '' workspace
~/nemoclaw-cookbook/scripts/backup-full.sh restore my-assistant '' sessions
```

After a rebuild, restore workspace before restarting tunnels, then restore sessions after channels reconnect.

## Upgrade Flow

```bash
~/nemoclaw-cookbook/scripts/backup-full.sh backup my-assistant

cd ~/nemoclaw-cookbook
git pull --ff-only
./scripts/validate-patches.sh
./setup.sh
```

`setup.sh` pulls upstream NemoClaw, runs upstream OpenShell installation, reapplies required cookbook overlays, and rebuilds the sandbox when the recorded NemoClaw commit changed.

## Diagnostics

```bash
nemoclaw debug
nemoclaw debug --quick
openshell doctor
openshell status
~/nemoclaw-cookbook/scripts/verify-deployment.sh
```

## Troubleshooting

### Web UI unreachable after rebuild

```bash
openshell forward start 18789 my-assistant --background
nemoclaw my-assistant recover
```

### `nemoclaw` crashes after upstream pull

```bash
cd ~/NemoClaw
bash install.sh --non-interactive
```

### `git pull` in `~/NemoClaw` is blocked by local changes

```bash
cd ~/NemoClaw
git checkout -- Dockerfile Dockerfile.base nemoclaw-blueprint/policies/openclaw-sandbox.yaml scripts/nemoclaw-start.sh
git pull --ff-only
```

### Setup reuses an old sandbox

```bash
export NEMOCLAW_RECREATE_SANDBOX=1
cd ~/nemoclaw-cookbook && ./setup.sh
```

## Agent Workspace

OpenClaw workspace files live under:

```text
/sandbox/.openclaw/workspace/
```

Chat sessions live under OpenClaw's agent session directory. Use `scripts/backup-full.sh` rather than copying internal paths by hand when possible.

## Copy Files To or From the Sandbox

Download:

```bash
openshell sandbox download my-assistant /sandbox/path/file.md /tmp/sandbox-staging/
cp /tmp/sandbox-staging/file.md ./file.md
rm -rf /tmp/sandbox-staging
```

Upload:

```bash
openshell sandbox upload my-assistant ./file.md /sandbox/path/
```

From a local machine through Brev:

```bash
brev exec <instance> "openshell sandbox download my-assistant /sandbox/path/file.md /tmp/sandbox-staging/"
brev copy <instance>:/tmp/sandbox-staging/file.md ./file.md
brev exec <instance> "rm -rf /tmp/sandbox-staging"
```

## Key Files

| Path | Purpose |
|------|---------|
| `~/.env` | Host-side credentials and deployment options |
| `~/openclaw-ui-url.txt` | Tokenized local Web UI URL |
| `~/openclaw-tunnel-url.txt` | Tokenized Secure Link Web UI URL |
| `~/openclaw-openai.env` | Optional `/v1/*` client settings |
| `~/.nemoclaw/credentials.json` | Host-side inference credentials |
| `~/.nemoclaw/sandboxes.json` | Sandbox registry |
| `~/.nemoclaw/cookbook-deployment.json` | Cookbook deployment manifest |
| `~/NemoClaw/Dockerfile` | Upstream Dockerfile after any active cookbook overlays |

## Resources

- NemoClaw docs: https://docs.nvidia.com/nemoclaw/latest/
- OpenShell docs: https://docs.nvidia.com/openshell/latest/
- NemoClaw GitHub: https://github.com/NVIDIA/NemoClaw
- OpenShell GitHub: https://github.com/NVIDIA/OpenShell
