# BUILD: NemoClaw + OpenShell From Scratch

This walkthrough builds a NemoClaw sandbox using upstream NemoClaw as the owner of OpenShell installation, sandbox-base resolution, OpenClaw versioning, inference setup, and web search. The cookbook adds only the temporary overlays listed in [UPSTREAM.md](UPSTREAM.md).

## Prerequisites

- A Brev Ubuntu instance with Docker
- Brev CLI installed and authenticated locally
- `NVIDIA_API_KEY` from https://build.nvidia.com/
- Optional tokens or keys for Telegram, Discord, Slack, Brave, Tavily, or the OpenAI-compatible HTTP API

## Step 1: Configure `.env`

Create `.env` locally:

```bash
cp .env.example .env
# Edit .env. NVIDIA_API_KEY is required.
```

Copy it to the Brev host:

```bash
brev copy .env <instance>:~/.env
```

Never print real values from `.env`, tokenized dashboard URLs, gateway tokens, or generated client env files. Treat tokenized URLs as live credentials. When inspecting env files, mask values:

```bash
sed 's/=.*/=***/' ~/.env
```

When opening the dashboard from your laptop, pass the saved URL directly to the browser instead of printing it into a shell transcript.

## Step 2: Clone the Cookbook on the Host

```bash
brev exec <instance> "git clone https://github.com/stevenrick/nemoclaw-cookbook.git ~/nemoclaw-cookbook"
```

If it already exists:

```bash
brev exec <instance> "cd ~/nemoclaw-cookbook && git pull --ff-only"
```

## Step 3: Run Setup

```bash
brev exec <instance> "cd ~/nemoclaw-cookbook && ./setup.sh"
```

`setup.sh` performs the deployment in this order:

1. Clone or update upstream `~/NemoClaw`.
2. Run upstream `~/NemoClaw/scripts/install-openshell.sh`.
3. Reset upstream files that cookbook overlays may touch.
4. Apply only the cookbook overlays required by your `.env`.
5. Run upstream `bash install.sh --non-interactive`.
6. Install host-side nginx and the optional browser terminal service.
7. Save tokenized UI URLs and optional OpenAI-compatible client env.
8. Start an optional Cloudflare named tunnel only when `CLOUDFLARE_TUNNEL_TOKEN` is set.
9. Write the deployment manifest and run the cookbook verifier.

## Manual Equivalent

For debugging, the underlying host-side flow is:

```bash
cd ~
git clone https://github.com/NVIDIA/NemoClaw || true
cd ~/NemoClaw
git pull --ff-only

source ~/.env
export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1

bash scripts/install-openshell.sh
~/nemoclaw-cookbook/scripts/apply-patches.sh ~/NemoClaw
bash install.sh --non-interactive
~/nemoclaw-cookbook/scripts/install-services.sh
~/nemoclaw-cookbook/scripts/save-ui-url.sh
~/nemoclaw-cookbook/scripts/write-manifest.sh
~/nemoclaw-cookbook/scripts/verify-deployment.sh
```

Prefer `setup.sh` for normal use because it handles failed onboard sessions, detects upstream drift, passes the current upstream environment surface through to onboarding, and manages post-deploy ordering.

## Accessing the Web UI

For an external URL, create a Brev Secure Link / service endpoint to host port
`80`, then set `TUNNEL_FQDN=<hostname>` in `~/.env`. There are two deployment
shapes:

- Loopback-style Secure Link/cloudflared: leave `NEMOCLAW_NGINX_LISTEN_ADDR`
  unset; nginx binds `127.0.0.1:80`.
- Brev `apps.run` service endpoint: set `NEMOCLAW_NGINX_LISTEN_ADDR=0.0.0.0`
  because the platform ingress connects to the host network interface.

Open the saved URL:

```bash
URL=$(brev exec <instance> "sed -n '1p' ~/openclaw-tunnel-url.txt" | sed -n '/^https:/p' | head -1)
open "$URL"
```

Port-forward fallback:

```bash
brev port-forward <instance> -p 18789:18789
URL=$(brev exec <instance> "sed -n '1p' ~/openclaw-ui-url.txt" | sed -n '/^http:/p' | head -1)
open "$URL"
```

Browser terminal on the same Secure Link:

```bash
TERMINAL_URL=$(printf '%s' "$URL" | sed 's#/#/terminal#3')
open "$TERMINAL_URL"
```

The token changes when the sandbox is rebuilt. Avoid `cat` for these files in shared logs; use it only in a private terminal when you intentionally need to inspect the URL.

## Optional Integrations

### Messaging

Set one or more of these in `~/.env` before setup:

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

`setup.sh` exports these for upstream onboard. Upstream NemoClaw owns channel credential validation, required policy preset merging, and rebuild-time channel configuration.

Slack Socket Mode requires both `SLACK_BOT_TOKEN` (`xoxb-...`) and `SLACK_APP_TOKEN` (`xapp-...`). Upstream ignores malformed messaging tokens, so placeholder values do not enable a channel.

### Resource Profiles

Upstream NemoClaw exposes sandbox CPU/RAM profiles:

```bash
nemoclaw resources
```

Set one before setup when you want a scripted resource choice:

```bash
NEMOCLAW_RESOURCE_PROFILE=developer
```

Use `NEMOCLAW_CPU` or `NEMOCLAW_RAM` only when you need a direct override rather than a named upstream profile.

### Web Search

Brave Search and Tavily Search are native upstream. Configure one provider:

```bash
BRAVE_API_KEY=BSA-...
```

```bash
NEMOCLAW_WEB_SEARCH_PROVIDER=tavily
TAVILY_API_KEY=tvly-...
```

When both `BRAVE_API_KEY` and `TAVILY_API_KEY` are present, set `NEMOCLAW_WEB_SEARCH_PROVIDER` explicitly to avoid relying on upstream default precedence.

### OpenAI-Compatible HTTP API

Set:

```bash
NEMOCLAW_OPENAI_HTTP_ENABLED=1
```

After deploy, client settings are written to:

```bash
source ~/openclaw-openai.env
```

The gateway exposes:

- `POST /v1/chat/completions`
- `POST /v1/responses`
- `GET /v1/models`
- `POST /v1/embeddings`

This API grants operator-level access to the sandbox. By default, nginx allows
`/v1/*` only from loopback and CORS is limited to localhost origins plus the
configured Secure Link origin. Use an SSH port-forward for programmatic clients:

```bash
ssh -L 8080:127.0.0.1:80 <brev-host>
OPENAI_BASE_URL=http://127.0.0.1:8080/v1 OPENAI_API_KEY=<edge-token-from-openclaw-openai.env> python your_client.py
```

The generated `~/openclaw-openai.env` file reads the API key from the owner-only
token file instead of storing the raw key inline. nginx validates that edge token
and rewrites requests to the private OpenClaw gateway token upstream, so API
token rotation does not require rebuilding or restarting the sandbox:

```bash
./scripts/rotate-openai-http-token.sh
source ~/openclaw-openai.env
```

Do not expose `/v1/*` publicly with the API bearer as the only auth layer. Keep
the default loopback-only mode and use SSH port-forwarding whenever possible.
If non-loopback clients must use the endpoint, set `NEMOCLAW_OPENAI_HTTP_TUNNEL=1`
and configure a second header credential:

```bash
NEMOCLAW_OPENAI_HTTP_TUNNEL=1
NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_ID=<client-id>
NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_SECRET=<client-secret>
```

nginx requires both the normal `Authorization: Bearer ...` API key and matching
`CF-Access-Client-Id` / `CF-Access-Client-Secret` headers for non-loopback
callers. If tunnel mode is enabled without those two variables, `/v1/*` fails
closed for non-loopback clients. The dashboard URL still carries the gateway token for the Web UI; do not reuse that token for API clients.
nginx also rate limits `/v1/*` by source IP at 120 requests per minute with a
burst of 30 requests.

For Brev `apps.run` service endpoints, expose host port `80` and set
`NEMOCLAW_NGINX_LISTEN_ADDR=0.0.0.0` so the platform ingress can reach nginx.
If `/v1/*` should be reachable through that endpoint, also configure the
`NEMOCLAW_OPENAI_HTTP_TUNNEL` and `NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_*`
variables above; otherwise external dashboard and terminal work, but `/v1/*`
stays loopback-guarded.

## Refreshing Patches After Upstream Updates

Run:

```bash
./scripts/validate-patches.sh
```

The validator clones current upstream NemoClaw, checks anchors, applies the remaining OpenAI HTTP overlay, and audits whether upstream now appears to cover that gap.

If validation fails:

1. Inspect the upstream file that changed.
2. Preserve only the logical overlay that is still needed.
3. Delete the overlay if upstream now owns the behavior.
4. Re-run `./scripts/validate-patches.sh`.
5. Deploy end-to-end on a Brev instance.
6. Update [UPSTREAM.md](UPSTREAM.md) only after that deployment is verified.

## Rebuilding or Upgrading a Sandbox

Back up first:

```bash
~/nemoclaw-cookbook/scripts/backup-full.sh backup my-assistant
```

Then update and run setup again:

```bash
cd ~/nemoclaw-cookbook
git pull --ff-only
./scripts/validate-patches.sh
./setup.sh
```

`setup.sh` records the upstream NemoClaw commit in `~/.nemoclaw/cookbook-deployment.json`. If that commit changes, it sets `NEMOCLAW_RECREATE_SANDBOX=1` so the sandbox image is rebuilt.

## Troubleshooting

### Docker-driver gateway blocked by UFW

If onboarding prints a gateway reachability error, retry once after restarting Docker:

```bash
sudo systemctl restart docker
cd ~/nemoclaw-cookbook && ./setup.sh
```

If it repeats and UFW is active, run the exact `ufw allow` command printed by NemoClaw, then rerun setup.

### Commands not found after install

```bash
source ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"
```

### Web UI URL missing

```bash
~/nemoclaw-cookbook/scripts/save-ui-url.sh
```

### Upstream pull blocked by local changes

The cookbook modifies upstream working-tree files before building. Reset those files before pulling:

```bash
cd ~/NemoClaw
git checkout -- Dockerfile Dockerfile.base package-lock.json nemoclaw-blueprint/policies/openclaw-sandbox.yaml scripts/nemoclaw-start.sh
git pull --ff-only
```

`setup.sh` does this automatically.

## Environment Variables

Key variables are documented in [.env.example](.env.example). The most common are:

| Variable | Purpose |
|----------|---------|
| `NVIDIA_API_KEY` | Required NVIDIA inference key |
| `NEMOCLAW_MODEL` | Optional model override |
| `NEMOCLAW_PROVIDER` | Optional provider override |
| `NEMOCLAW_RESOURCE_PROFILE`, `NEMOCLAW_CPU`, `NEMOCLAW_RAM` | Optional upstream sandbox resource selection |
| `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN` | Optional upstream messaging channels |
| `NEMOCLAW_WEB_SEARCH_PROVIDER`, `BRAVE_API_KEY`, `TAVILY_API_KEY` | Optional upstream web-search selection |
| `NEMOCLAW_OPENAI_HTTP_ENABLED=1` | Cookbook `/v1/*` API enablement |
| `NEMOCLAW_OPENAI_HTTP_TUNNEL=1` | Allows non-loopback `/v1/*` only when the second header credential below is also configured |
| `NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_ID` | Required `CF-Access-Client-Id` value for non-loopback `/v1/*` callers |
| `NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_SECRET` | Required `CF-Access-Client-Secret` value for non-loopback `/v1/*` callers |
| `NEMOCLAW_NGINX_LISTEN_ADDR=0.0.0.0` | Bind nginx to the host network interface for Brev `apps.run` service endpoints |
| `TUNNEL_FQDN` | Secure Link hostname for browser access |
| `CLOUDFLARE_TUNNEL_TOKEN` | Optional upstream Cloudflare named tunnel |
| `NEMOCLAW_POLICY_TIER`, `NEMOCLAW_POLICY_PRESETS`, `NEMOCLAW_POLICY_MODE` | Upstream policy selection |

## Security Model

The sandbox security model is upstream NemoClaw/OpenShell:

- Landlock limits writable paths.
- seccomp restricts syscalls.
- network egress flows through OpenShell policy.
- inference credentials stay host-side.
- `openclaw.json` is integrity checked at sandbox startup.

The cookbook does not weaken those controls. Its overlays either add explicit policy for a configured service or add host-side proxying around upstream endpoints.

## Resources

- NemoClaw docs: https://docs.nvidia.com/nemoclaw/latest/
- OpenShell docs: https://docs.nvidia.com/openshell/latest/
- NemoClaw GitHub: https://github.com/NVIDIA/NemoClaw
- OpenShell GitHub: https://github.com/NVIDIA/OpenShell
