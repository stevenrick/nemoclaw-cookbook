# USE: NemoClaw Day-to-Day Reference

Use the sandbox name recorded by upstream NemoClaw. JSON output also identifies
the agent and dynamically allocated dashboard port:

```bash
nemoclaw list --json
```

## Connect

Interactive:

```bash
brev shell <instance>
nemoclaw <sandbox> connect
```

Non-interactive command inside the sandbox:

```bash
brev exec <instance> "nemoclaw <sandbox> exec -- <command>"
```

The sandbox is managed by OpenShell. Do not use `docker exec` as the normal access path.

## Endpoints

| Endpoint | URL / Command | Purpose |
|----------|---------------|---------|
| Dashboard | `~/nemoclaw-tunnel-url.txt` or `~/nemoclaw-ui-url.txt` | OpenClaw and Hermes only |
| Browser terminal | `~/nemoclaw-terminal-url.txt` | Agent-aware `nemoclaw launch`; all runtimes |
| CLI | `nemoclaw launch <sandbox>` | OpenClaw TUI, Hermes, or `dcode` |
| Telegram / Discord / Slack | Your configured bot or app | Async messaging |
| OpenAI-compatible HTTP | `~/nemoclaw-openai.env` | Hermes native API or optional OpenClaw `/v1/*`; not applicable to Deep Agents Code |

External URLs should point at host port `80`. For Brev `apps.run`, set
`NEMOCLAW_NGINX_LISTEN_ADDR=0.0.0.0` before setup; loopback Secure
Link/cloudflared and SSH-forwarded access should leave it unset.

Open URLs without printing the tokenized value:

```bash
# Secure Link
URL=$(brev exec <instance> "sed -n '1p' ~/nemoclaw-tunnel-url.txt" | sed -n '/^https:/p' | head -1)
open "$URL"

# Browser terminal on that Secure Link
TERMINAL_URL=$(brev exec <instance> "sed -n '1p' ~/nemoclaw-terminal-url.txt" | sed -n '/^https:/p' | head -1)
open "$TERMINAL_URL"
```

Port-forward fallback:

```bash
brev port-forward <instance> -p <dashboard-port>:<dashboard-port>
URL=$(brev exec <instance> "sed -n '1p' ~/nemoclaw-ui-url.txt" | sed -n '/^http:/p' | head -1)
open "$URL"
```

If URL files are missing:

```bash
brev exec <instance> "~/nemoclaw-cookbook/scripts/save-ui-url.sh <sandbox>"
```

Upstream NemoClaw can also expose the browser URL and raw gateway token for troubleshooting. Redact the URL and check only token length in shared logs:

```bash
nemoclaw <sandbox> dashboard-url --quiet | sed -E 's/#token=.*/#token=<redacted>/'
nemoclaw <sandbox> gateway-token --quiet | wc -c
```

## Agent Harness Commands

```bash
# OpenClaw
openclaw tui

# Hermes
hermes
hermes -z "hello"

# LangChain Deep Agents Code
dcode
dcode -n "hello" -q --no-stream
```

From the host, prefer `nemoclaw launch <sandbox>` and
`nemoclaw <sandbox> exec -- <agent-command>` so automation does not assume a
specific harness.

## Messaging

Messaging is handled by upstream NemoClaw. OpenClaw and Hermes support
agent-specific channel subsets; Deep Agents Code is terminal-only. Configure
tokens in `~/.env` before setup:

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_IDS=...
TELEGRAM_REQUIRE_MENTION=1
TELEGRAM_GROUP_POLICY=allowlist
DISCORD_BOT_TOKEN=...
DISCORD_SERVER_ID=...
DISCORD_ALLOWED_IDS=...
DISCORD_REQUIRE_MENTION=1
SLACK_BOT_TOKEN=...
SLACK_APP_TOKEN=...
SLACK_ALLOWED_USERS=...
SLACK_ALLOWED_CHANNELS=...
```

OpenClaw defaults Telegram group access to `open`; set `TELEGRAM_GROUP_POLICY=allowlist` to require explicit group entries, or `disabled` to turn off group access. The setup wrapper passes this setting to upstream onboarding and reapplies it with upstream's `openclaw config set` after a forced recreate, which currently drops the stored value. Slack requires both the bot token and the app-level Socket Mode token. Upstream validates token formats during onboarding; placeholder values are ignored.

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
BRAVE_API_KEY=BSA-...

# Or:
NEMOCLAW_WEB_SEARCH_PROVIDER=tavily
TAVILY_API_KEY=tvly-...
```

Web search is handled by upstream NemoClaw. If both keys are present, set `NEMOCLAW_WEB_SEARCH_PROVIDER` explicitly. After changing web-search configuration, rerun:

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

For Hermes, no feature flag is needed. Setup writes the native API's allocated
port and owner-only bearer loader to:

```bash
source ~/nemoclaw-openai.env
```

Deep Agents Code has no HTTP service. For OpenClaw only, enable the cookbook
overlay before setup:

```bash
NEMOCLAW_OPENAI_HTTP_ENABLED=1
```

Load client settings after deploy:

```bash
source ~/nemoclaw-openai.env
```

Smoke test from the Brev host:

```bash
python -c "from openai import OpenAI; print([m.id for m in OpenAI().models.list().data])"
```

For laptop clients, prefer an SSH port-forward:

```bash
ssh -L 8080:127.0.0.1:80 <brev-host>
OPENAI_BASE_URL=http://127.0.0.1:8080/v1 OPENAI_API_KEY=<edge-token-from-nemoclaw-openai.env> python your_client.py
```

`NEMOCLAW_OPENAI_HTTP_TUNNEL=1` can make `/v1/*` reachable by non-loopback
clients, but it no longer permits bearer-only public exposure. Tunnel mode also
requires `NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_ID` and
`NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_SECRET`; nginx checks those values against
the `CF-Access-Client-Id` and `CF-Access-Client-Secret` request headers before
proxying non-loopback API requests. If either value is missing, `/v1/*` fails
closed for non-loopback clients. CORS is restricted to localhost origins plus
the configured Secure Link origin; it is not a replacement for token secrecy or
edge authentication. nginx rate limits `/v1/*` by source IP at 120 requests per
minute with a burst of 30 requests.

Rotate the API edge token without rebuilding or restarting the sandbox:

```bash
./scripts/rotate-openai-http-token.sh
source ~/nemoclaw-openai.env
```

Brev `apps.run` service endpoints should target host port `80` and set
`NEMOCLAW_NGINX_LISTEN_ADDR=0.0.0.0`; loopback Secure Link/cloudflared and SSH
port-forward modes should leave that unset. If `/v1/*` should be externally
reachable through `apps.run`, also set `NEMOCLAW_OPENAI_HTTP_TUNNEL=1` and the
`NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_*` values.

## Sandbox Management

```bash
nemoclaw list
nemoclaw <sandbox> status
nemoclaw <sandbox> logs --follow
nemoclaw launch <sandbox>
nemoclaw <sandbox> recover
nemoclaw <sandbox> destroy --yes
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

nemoclaw <sandbox> recover
tail -f ~/.local/state/nemoclaw/openshell-docker-gateway/openshell-gateway.log
```

## Network Policies

```bash
nemoclaw <sandbox> policy-list
nemoclaw <sandbox> policy-add
nemoclaw launch <sandbox>
```

Use the browser terminal at `/terminal#token=<hex>` when you want policy approvals without an SSH session.

## Backup and Restore

The backup script delegates to upstream's selected-agent manifest. It preserves
that runtime's declared sessions, workspace, and installed skills while
excluding credential-bearing files, Docker images, nginx, and systemd units.

```bash
~/nemoclaw-cookbook/scripts/backup-full.sh backup <sandbox> before-change
~/nemoclaw-cookbook/scripts/backup-full.sh list <sandbox>
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> before-change
```

Snapshot restore is atomic at the upstream agent-state boundary; there are no
cookbook-specific workspace/session phases.

## Upgrade Flow

```bash
~/nemoclaw-cookbook/scripts/backup-full.sh backup <sandbox> before-upgrade

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

### Dashboard unreachable after rebuild

```bash
nemoclaw <sandbox> recover
```

### `nemoclaw` crashes after upstream pull

```bash
cd ~/NemoClaw
bash install.sh --non-interactive
```

### `git pull` in `~/NemoClaw` is blocked by local changes

```bash
cd ~/NemoClaw
git checkout -- Dockerfile Dockerfile.base package-lock.json nemoclaw-blueprint/policies/openclaw-sandbox.yaml scripts/nemoclaw-start.sh
git pull --ff-only
```

### Setup reuses an old sandbox

```bash
export NEMOCLAW_RECREATE_SANDBOX=1
cd ~/nemoclaw-cookbook && ./setup.sh
```

## Agent State and Skills

Do not build backup automation around private harness paths. Upstream manifests
currently preserve OpenClaw's workspace/skills/sessions, Hermes' `.hermes`
state including skills and sessions, and Deep Agents Code's `.state`, `skills`,
and `agent/skills`. Use `scripts/backup-full.sh` so future upstream layout
changes remain transparent.

## Copy Files To or From the Sandbox

Download:

```bash
openshell sandbox download <sandbox> /sandbox/path/file.md /tmp/sandbox-staging/
cp /tmp/sandbox-staging/file.md ./file.md
rm -rf /tmp/sandbox-staging
```

Upload:

```bash
openshell sandbox upload <sandbox> ./file.md /sandbox/path/
```

From a local machine through Brev:

```bash
brev exec <instance> "openshell sandbox download <sandbox> /sandbox/path/file.md /tmp/sandbox-staging/"
brev copy <instance>:/tmp/sandbox-staging/file.md ./file.md
brev exec <instance> "rm -rf /tmp/sandbox-staging"
```

## Key Files

| Path | Purpose |
|------|---------|
| `~/.env` | Host-side credentials and deployment options |
| `~/nemoclaw-ui-url.txt` | Selected gateway agent's local dashboard URL, written `0600` |
| `~/nemoclaw-tunnel-url.txt` | Selected gateway agent's Secure Link dashboard URL, written `0600` |
| `~/nemoclaw-terminal-url.txt` | Independent agent-aware browser-terminal URL, written `0600` |
| `~/nemoclaw-openai.env` | Hermes native or optional OpenClaw API client settings; loads an owner-only token file |
| `~/.nemoclaw/terminal-access-token` | Browser-terminal credential, kept separate from agent gateway/API tokens |
| `~/.nemoclaw/openai-http-edge-token` | Host-side `/v1/*` API token accepted by nginx, written `0600` |
| `~/.nemoclaw/openai-http-gateway-token` | Private OpenClaw gateway token used only by nginx upstream, written `0600` |
| `~/.nemoclaw/credentials.json` | Host-side inference credentials |
| `~/.nemoclaw/sandboxes.json` | Sandbox registry |
| `~/.nemoclaw/cookbook-deployment.json` | Cookbook deployment manifest |
| `~/NemoClaw/Dockerfile` | Upstream OpenClaw Dockerfile after any active cookbook overlays; other agent images are unchanged |

## Resources

- NemoClaw docs: https://docs.nvidia.com/nemoclaw/latest/
- OpenShell docs: https://docs.nvidia.com/openshell/latest/
- NemoClaw GitHub: https://github.com/NVIDIA/NemoClaw
- OpenShell GitHub: https://github.com/NVIDIA/OpenShell
