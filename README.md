# NemoClaw Cookbook

Thin deployment and integration helpers for upstream [NemoClaw](https://github.com/NVIDIA/NemoClaw) and [OpenShell](https://github.com/NVIDIA/OpenShell).

> This is a community cookbook / reference implementation, not an official NVIDIA project. For NemoClaw or OpenShell issues, file upstream issues in those repositories.

## Upstream-First

This repo is not a fork and not a competing distribution. It exists to make NemoClaw easier to deploy while upstream support is still landing. Every patch should be temporary: when upstream absorbs a capability, this cookbook deletes its version.

The current upstream alignment notes are in [UPSTREAM.md](UPSTREAM.md).

## Secret Hygiene

Tokenized dashboard URLs, gateway tokens, API keys, and bot tokens are live credentials. The cookbook treats them as non-printable runtime values: scripts write them to files, pass them directly to browsers or clients, and redact them in status output. Do not paste tokenized URLs into issues, PRs, chat, shell transcripts, or shared logs.

## Prerequisites

- A [Brev](https://brev.nvidia.com) Ubuntu instance with Docker
- [Brev CLI](https://github.com/brevdev/brev-cli) installed and authenticated locally
- An NVIDIA API key from [https://build.nvidia.com/](https://build.nvidia.com/)

## Setup

Create a local `.env`, copy it to the Brev instance, then run the cookbook setup script on the instance:

```bash
cp .env.example .env
# Edit .env. NVIDIA_INFERENCE_API_KEY is required. Select NEMOCLAW_AGENT if
# you do not want the default OpenClaw harness.

brev exec <instance> "git clone -b main https://github.com/stevenrick/nemoclaw-cookbook.git ~/nemoclaw-cookbook"
brev copy .env <instance>:~/.env
brev exec <instance> "cd ~/nemoclaw-cookbook && ./setup.sh"
```

Connect after setup:

```bash
# Public/Secure Link, if TUNNEL_FQDN is set. Opens without printing the tokenized URL.
URL=$(brev exec <instance> "sed -n '1p' ~/nemoclaw-tunnel-url.txt" | sed -n '/^https:/p' | head -1)
open "$URL"

# Browser terminal (works for all three agent runtimes).
TERMINAL_URL=$(brev exec <instance> "sed -n '1p' ~/nemoclaw-terminal-url.txt" | sed -n '/^https:/p' | head -1)
open "$TERMINAL_URL"

# Port-forward fallback for OpenClaw or Hermes: get the allocated dashboard
# port from `nemoclaw list --json`, then forward that same host/local port.
brev port-forward <instance> -p <dashboard-port>:<dashboard-port>
URL=$(brev exec <instance> "sed -n '1p' ~/nemoclaw-ui-url.txt" | sed -n '/^http:/p' | head -1)
open "$URL"
```

External endpoints should target host port `80`. If the platform endpoint can
only reach the host network interface, such as Brev `apps.run`, set
`NEMOCLAW_NGINX_LISTEN_ADDR=0.0.0.0` in `~/.env`; leave it unset for loopback
Secure Link/cloudflared and SSH-forwarded access. Set
`NEMOCLAW_OPENAI_HTTP_TUNNEL=1` only when `/v1/*` should be reachable through
that external endpoint, and pair it with
`NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_ID` plus
`NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_SECRET`. Non-loopback API callers must send
both those headers and the generated API bearer. Rotate the API bearer without
rebuilding the sandbox with `scripts/rotate-openai-http-token.sh`. nginx rate
limits `/v1/*` by source IP at 120 requests per minute with a burst of 30
requests.

See [BUILD.md](BUILD.md) for the full setup walkthrough and [USE.md](USE.md) for day-to-day commands.

## Supported Agent Runtimes

| `NEMOCLAW_AGENT` | Runtime | Browser surface | OpenAI-compatible API |
|-------------------|---------|-----------------|-----------------------|
| `openclaw` (default) | Gateway | Upstream dashboard plus cookbook browser terminal | Optional cookbook `/v1/*` overlay |
| `hermes` | Gateway | Upstream Hermes dashboard plus cookbook browser terminal | Native Hermes API on its allocated `8642`–`8652` port |
| `langchain-deepagents-code` | Terminal | Cookbook browser terminal launches `dcode`; no dashboard | Not applicable |

NemoClaw remains the source of truth for each runtime's image, lifecycle,
ports, sessions, and skill directories. Cookbook scripts discover the selected
agent from `nemoclaw status --json`; they do not infer it from OpenClaw paths.

## What This Sets Up

- Upstream NemoClaw and OpenShell, using NemoClaw's own `scripts/install-openshell.sh`
- The selected upstream OpenClaw, Hermes, or LangChain Deep Agents Code harness inside OpenShell
- nginx reverse proxy for gateway dashboards (or a `/terminal` redirect for Deep Agents Code), Secure Link origin handling, and optional OpenClaw `/v1/*` CORS
- Optional agent-aware browser terminal at `/terminal`, launched through `nemoclaw launch`
- Optional upstream messaging channels for Telegram, Discord, Slack, WeChat, and WhatsApp
- Upstream sandbox resource profiles via `NEMOCLAW_RESOURCE_PROFILE`, `NEMOCLAW_CPU`, and `NEMOCLAW_RAM`
- Native upstream web search via `NEMOCLAW_WEB_SEARCH_PROVIDER`, `BRAVE_API_KEY`, and `TAVILY_API_KEY`
- Optional OpenClaw HTTP API on `/v1/*`; Hermes uses its native upstream API
- Manifest-driven upstream snapshot/restore, validation, and deployment manifest scripts

## What the Patches Do

`scripts/apply-patches.sh` applies only environment-driven OpenClaw overlays.
Hermes and Deep Agents Code use their upstream images unchanged:

| Overlay | Trigger | Purpose |
|---------|---------|---------|
| `patches/fragments/dockerfile-integrations` | `NEMOCLAW_OPENAI_HTTP_ENABLED=1` | Deep-merge cookbook-only OpenAI-compatible HTTP config into `openclaw.json` before the upstream integrity hash is pinned |
| Reviewed Tavily plugin install in `scripts/apply-patches.sh` | Upstream selects Tavily explicitly, or `TAVILY_API_KEY` is set without a competing Brave selection | Add the exact checksum-addressed Tavily archive to upstream's offline plugin install path until upstream ships it natively |

There are no cookbook patches for upstream web-search configuration or policy; the temporary reviewed Tavily package install above is the only web-search-related exception. Sandbox-installed coding-agent tools, OpenShell version pinning, OpenClaw version overrides, and generic git/plugin setup are also absent or delegated to upstream.

## When Upstream Changes

Validate against current upstream before rebuilding a live sandbox:

```bash
./scripts/validate-patches.sh
```

If validation fails, inspect what changed upstream and update the smallest affected overlay. If upstream now provides the capability, delete the cookbook overlay instead of carrying it forward. Update [UPSTREAM.md](UPSTREAM.md) only after a revised cookbook has been verified with an end-to-end deployment.

## Backup and Restore

```bash
~/nemoclaw-cookbook/scripts/backup-full.sh backup <sandbox> before-change
~/nemoclaw-cookbook/scripts/backup-full.sh list <sandbox>
~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> before-change
```

This is a thin wrapper over upstream agent manifests. It preserves the selected
runtime's declared sessions, workspace, and skills and excludes credentials.

## Upgrading

The safe manual flow is:

```bash
~/nemoclaw-cookbook/scripts/backup-full.sh backup <sandbox>
cd ~/nemoclaw-cookbook && git pull --ff-only
./scripts/validate-patches.sh
cd ~/nemoclaw-cookbook && ./setup.sh
```

`setup.sh` updates upstream NemoClaw, lets upstream install the matching OpenShell version, reapplies only required cookbook overlays, and forces a sandbox rebuild when the recorded NemoClaw commit changed.

## File Structure

```text
.env.example          # Template for credentials and optional integrations
setup.sh              # Automated deployment script
patches/fragments/    # Small temporary overlays
scripts/
  apply-patches.sh    # Applies only needed overlays to upstream NemoClaw
  validate-patches.sh # Tests overlays against current upstream
  install-services.sh # nginx and optional browser-terminal services
  lib/agent-runtime.sh # Discovers sandbox, agent, runtime, and allocated ports from upstream
  save-ui-url.sh      # Writes agent-appropriate UI, terminal, and API client files
  backup-full.sh      # Wraps upstream manifest-driven snapshots
BUILD.md              # From-scratch setup details
USE.md                # Day-to-day reference
UPSTREAM.md           # Current upstream compatibility and removal plan
```

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). The short version: search upstream first, keep patches narrow, document the removal condition, and delete cookbook code when upstream closes the gap.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
