# BUILD: NemoClaw + OpenShell from Scratch

Reproducible steps to go from a clean Ubuntu machine to a fully operational NemoClaw sandbox with OpenClaw AI assistant, Claude Code, and messaging integrations.

> **Note:** NVIDIA provides a quick-start installer (`curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash`) that walks you through setup interactively. This cookbook's `setup.sh` does the same thing non-interactively (using env vars instead of prompts), then applies patches to add Claude Code, Codex, and extended network policies. If you already ran the interactive installer, you have a working NemoClaw — this cookbook adds the coding agent tooling on top.

## Prerequisites

- A [Brev](https://brev.nvidia.com) instance (Ubuntu 22.04+, Docker pre-installed)
- [Brev CLI](https://github.com/brevdev/brev-cli) installed and authenticated locally
- An NVIDIA API key from https://integrate.api.nvidia.com
- (Optional) Messaging tokens: Telegram (@BotFather), Discord, or Slack

## Step 1: Configure and deploy the cookbook

Create `.env` in the cookbook repo locally (it's gitignored):

```bash
cp .env.example .env
# Edit .env — NVIDIA_API_KEY is required, everything else is optional
```

See `.env.example` for all available options (inference providers, messaging tokens, integrations, policy presets).

Clone the cookbook on the remote instance and copy your `.env`:

```bash
brev exec <instance> "git clone https://github.com/stevenrick/nemoclaw-cookbook.git ~/nemoclaw-cookbook"
brev copy .env <instance>:~/.env
```

## Step 2: Clone repos

```bash
cd ~
git clone https://github.com/NVIDIA/OpenShell
git clone https://github.com/NVIDIA/NemoClaw
```

## Step 3: Install OpenShell

```bash
cd ~/OpenShell && sh install.sh
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
openshell --version
```

## Step 4: Pull latest sandbox base image

Ensures you get the latest OpenClaw version, not whatever was cached.

```bash
docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest
```

## Step 5: Bake Claude Code into the sandbox image (optional)

The cookbook uses modular patch fragments in `patches/fragments/` instead of monolithic patch files. The `scripts/apply-patches.sh` script reads `INSTALL_CLAUDE_CODE` and `INSTALL_CODEX` from `.env` (both default to `true`) and applies only the relevant fragments:

| Fragment | Applied when | What it does |
|----------|-------------|--------------|
| `dockerfile-core` | Always | Git HTTPS/SSL config for sandbox |
| `dockerfile-claude-code` | `INSTALL_CLAUDE_CODE=true` | Claude Code binary install + sandbox symlink |
| `dockerfile-codex` | `INSTALL_CODEX=true` | Codex CLI via npm |
| `policy-core.yaml` | Always | GitHub policy extensions (codeload.github.com) |
| `policy-claude-code.yaml` | `INSTALL_CLAUDE_CODE=true` | Claude auth endpoints, claude binary in policies |
| `policy-codex.yaml` | `INSTALL_CODEX=true` | OpenAI policy block, codex/node binaries |

To apply:

```bash
scripts/apply-patches.sh ~/NemoClaw
```

To skip Codex (for example), set `INSTALL_CODEX=false` in `.env` before running the script.

The Dockerfile fragments add git HTTPS config (so plugin/marketplace cloning works inside the sandbox), the Claude Code binary install (resolving the symlink chain from `/root/.local/` to `/usr/local/bin/`), and the Codex CLI. The policy fragments open the network endpoints needed for Claude Code's login flow, OpenAI auth, and GitHub release downloads — without them you'd need to manually approve endpoints in `openshell term`.

All changes survive future rebuilds.

## Step 6: Install NemoClaw

```bash
cd ~/NemoClaw
source ~/.env
export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1

bash install.sh --non-interactive
```

Takes ~5 minutes. Installs Node.js via nvm, builds NemoClaw, creates the sandbox, configures inference and policies.

Reload your shell after:

```bash
source ~/.bashrc
```

## Step 7: Verify

> **Sandbox name:** Examples use `my-assistant`, the default. Run `nemoclaw list` to see your actual sandbox name and substitute it in all commands below.

```bash
openshell --version
openshell status
nemoclaw --version
nemoclaw list
nemoclaw my-assistant status
openshell inference get
```

## Step 8: Authenticate Codex and Claude Code (if installed in Step 5)

### Codex (can be scripted)

Codex uses device-code auth that works non-interactively:

```bash
SANDBOX_SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' \
  sandbox@openshell-my-assistant"

brev exec <instance> "$SANDBOX_SSH 'codex login --device-auth 2>&1'"
```

This prints a URL and a one-time code — open the URL in your browser and enter the code. The command prints "login successful" when done.

### Claude Code + Codex plugin for Claude Code (interactive)

Claude Code uses a full TUI for auth, and the Codex plugin is installed inside Claude Code's TUI. Do both in one interactive session:

```bash
brev shell <instance>
nemoclaw my-assistant connect
claude
```

Inside Claude Code's TUI:
1. Follow the login prompts (it gives you a URL to open in your browser)
2. Once logged in, install the Codex plugin for Claude Code:
   ```
   /plugin marketplace add openai/codex-plugin-cc
   /plugin install codex@openai-codex
   /reload-plugins
   /codex:setup
   ```

SSO tokens persist across restarts but not sandbox rebuilds. The plugin must also be reinstalled after each rebuild.

Once installed, Claude Code gains these Codex slash commands:
- `/codex:review` — code review
- `/codex:adversarial-review` — adversarial code review
- `/codex:rescue` — rescue stuck tasks

See https://github.com/openai/codex-plugin-cc for the full command list.

## Step 9: Set up Telegram (optional)

If you didn't add tokens in Step 1:

1. Message **@BotFather** in Telegram, send `/newbot`, get the token
2. Message **@userinfobot** to get your chat ID
3. Add to `.env` in the cookbook repo (and re-copy to instance: `brev copy .env <instance>:~/.env`):
   ```
   TELEGRAM_BOT_TOKEN=your-bot-token
   ALLOWED_CHAT_IDS=your-chat-id
   ```

Start the bridge. `nemoclaw start` reads env vars directly from the process environment (no dotenv/file loading):

```bash
# If ~/.env exists and vars are there:
source ~/.env
export NVIDIA_API_KEY TELEGRAM_BOT_TOKEN ALLOWED_CHAT_IDS
nemoclaw start

# Or pass inline (works without any .env file):
NVIDIA_API_KEY=<key> TELEGRAM_BOT_TOKEN=<token> ALLOWED_CHAT_IDS=<id> nemoclaw start
```

This starts a Cloudflare quick tunnel for the Telegram webhook URL. Note: `nemoclaw start` only manages the tunnel — the gateway and sandbox run continuously under systemd.

## Step 9b: Infrastructure Services

`setup.sh` automatically calls `scripts/install-services.sh` which deploys:

| Component | Purpose | Managed by |
|-----------|---------|-----------|
| **nginx** | Reverse proxy: port 80 → dashboard (18789), Origin header rewriting for Secure Link | systemd |
| **openshell-gateway.service** | Auto-starts the OpenShell gateway on boot | systemd |
| **nemoclaw-terminal.service** | Browser terminal server at `/terminal` (optional) | systemd |

All services start on boot and restart on failure. The script is idempotent — safe to re-run after config changes.

To manage manually: `systemctl status|restart|stop <service-name>`. See USE.md § System Services for full commands.

## Step 10: Tokenized UI URL

`setup.sh` extracts the gateway auth token and writes:

- **`~/openclaw-ui-url.txt`** — local access: `http://127.0.0.1:18789/#token=<hex>`
- **`~/openclaw-tunnel-url.txt`** — Secure Link access (if `TUNNEL_FQDN` set): `https://<fqdn>/#token=<hex>`

Both use the same token. It changes on every sandbox rebuild.

If files are missing, regenerate: `~/nemoclaw-cookbook/scripts/save-ui-url.sh`

## Accessing the Web UI

**Option A: Secure Link (recommended)** — no port forwarding needed:

1. Go to Brev Settings → Secure Links → create a link for port 80 on your instance
2. Set `TUNNEL_FQDN=your-link.brevlab.com` in `~/.env`
3. Run `setup.sh` (or re-run `scripts/install-services.sh` + `scripts/save-ui-url.sh`)
4. Open the URL from `~/openclaw-tunnel-url.txt` in your browser

The nginx reverse proxy rewrites the Origin header so the sandbox CORS check passes regardless of your browser's domain.

**Option B: Port forward (local-only fallback)**:

```bash
brev port-forward <instance-name> -p 18789:18789
```

Then open `http://127.0.0.1:18789/#token=<hex>` from `~/openclaw-ui-url.txt`. Use `127.0.0.1`, not `localhost`.

## Adding Integrations

The cookbook supports optional integrations driven by API keys in `.env`. When a key is present, `setup.sh` creates an OpenShell provider post-install and the relevant policy preset can be applied.

### Brave Search

Enables web search capabilities via the Brave Search API.

1. Get a Brave Search API key from https://brave.com/search/api/
2. Add it to `.env` in the cookbook repo:
   ```bash
   echo 'BRAVE_API_KEY=BSA-your-key-here' >> .env
   ```
3. If this is a fresh install, run `./setup.sh` — it handles everything.
4. If you already have a running sandbox, run `/upgrade` from Claude Code.
   This backs up your workspace, recreates the sandbox with updated config, and restores.

### Adding other services

To add a new API integration:

1. Add the API key to `.env` in the cookbook repo
2. Add a policy fragment to `patches/fragments/` for the service's endpoints
3. Update `.env.example` with the new key
4. Run `/upgrade` to apply to a running sandbox

### Why recreation is needed

OpenShell providers (credential bundles injected into the sandbox) can only be attached at sandbox creation time. Adding a new provider to an existing sandbox requires destroying and recreating it. The `/upgrade` skill automates the backup/restore around this constraint.

## Rebuilding the sandbox

Any time you need to rebuild (update, config change, etc.). **Back up first** — Claude Code users can run `/backup` to snapshot to their local machine. Then run via `brev exec` or inside `brev shell`:

```bash
source ~/.env && export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1

# 1. Back up workspace, chat history, and skills (or use /backup from Claude Code)
~/nemoclaw-cookbook/scripts/backup-full.sh backup my-assistant

# 2. Stop services and destroy
nemoclaw stop 2>/dev/null
docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest
nemoclaw my-assistant destroy --yes

# 3. Rebuild
nemoclaw onboard

# 4. Restore workspace + skills, start services, then restore sessions
~/nemoclaw-cookbook/scripts/backup-full.sh restore my-assistant '' workspace
nemoclaw start
~/nemoclaw-cookbook/scripts/backup-full.sh restore my-assistant '' sessions
```

After rebuild:
1. Re-authenticate: run `codex login --device-auth` then launch `claude` (login is forced on first launch) inside the sandbox (SSO tokens don't survive rebuilds)
2. Reinstall the Codex plugin for Claude Code (`/plugin marketplace add openai/codex-plugin-cc`, etc.)

## Refreshing Patches After Upstream Updates

The patch fragments in `patches/fragments/` are unified diffs generated against a specific version of NemoClaw. When NVIDIA updates the upstream files, some fragments may fail to apply.

### Quick path (with Claude Code)

```bash
claude /refresh-patches
```

This skill walks Claude through diagnosing the conflict, understanding what changed upstream, and regenerating the fragments while preserving their intent.

### Manual path

1. Reset and inspect:
   ```bash
   cd ~/NemoClaw
   git pull origin main
   git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
   ```

2. Try applying fragments:
   ```bash
   /path/to/nemoclaw-cookbook/scripts/apply-patches.sh ~/NemoClaw
   ```

3. If any fragments fail, inspect the failing fragment, resolve against the current upstream file, and regenerate the fragment diff.

4. Reset and verify the round-trip:
   ```bash
   git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
   /path/to/nemoclaw-cookbook/scripts/apply-patches.sh ~/NemoClaw
   ```

5. Update `UPSTREAM.md` with the current NemoClaw and OpenShell commits and sandbox-base image tag.

### What to preserve

The fragments add these logical pieces — if upstream restructures things, adapt the placement but keep the intent:

- **Dockerfile**: git HTTPS config, Claude Code binary install (with sandbox user symlink), Codex CLI install, sandbox user ownership fixes
- **Policy**: Claude auth endpoints, OpenAI policy block (with node binary), GitHub policy extensions (codeload.github.com + binaries)

See the `/refresh-patches` skill for the full breakdown.

### Automated validation

To check if fragments still apply against the latest upstream (without modifying anything):

```bash
./scripts/validate-patches.sh
```

This clones upstream into a temp directory, tests each fragment, and reports pass/fail. Safe to run in CI on a schedule to catch upstream drift early.

## Troubleshooting

### Commands not found after install

```bash
source ~/.bashrc
# Or manually:
export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"
```

## Environment Variables

### Core

| Variable | Purpose | When |
|----------|---------|------|
| `NVIDIA_API_KEY` | NVIDIA inference key (starts with `nvapi-`) | Install / onboard |
| `NEMOCLAW_NON_INTERACTIVE=1` | Skip all interactive prompts | Install / onboard |
| `NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1` | Accept third-party software notice | Install / onboard |
| `NEMOCLAW_SANDBOX_NAME` | Custom sandbox name (default: `my-assistant`) | Install / onboard |
| `NEMOCLAW_RECREATE_SANDBOX=1` | Force-recreate existing sandbox | Onboard |
| `INSTALL_CLAUDE_CODE` | Install Claude Code in sandbox (default: `true`) | apply-patches.sh |
| `INSTALL_CODEX` | Install Codex CLI in sandbox (default: `true`) | apply-patches.sh |

### Inference

| Variable | Purpose | When |
|----------|---------|------|
| `NEMOCLAW_PROVIDER` | Provider type (see below) | Install / onboard |
| `NEMOCLAW_MODEL` | Override inference model | Install / onboard |
| `NEMOCLAW_ENDPOINT_URL` | Custom endpoint for custom/nim-local/vllm providers | Install / onboard |
| `NEMOCLAW_EXPERIMENTAL=1` | Enable experimental providers (local NIM, vLLM) | Install / onboard |
| `NEMOCLAW_GPU` | Brev GPU instance type for `nemoclaw deploy` | Deploy |

Valid `NEMOCLAW_PROVIDER` values: `build` (NVIDIA cloud, default), `openai`, `anthropic`, `anthropicCompatible`, `gemini`, `ollama`, `custom`, `nim-local`, `vllm`

### Alternative provider API keys

| Variable | Purpose | When |
|----------|---------|------|
| `OPENAI_API_KEY` | OpenAI API key (when `NEMOCLAW_PROVIDER=openai`) | Install / onboard |
| `ANTHROPIC_API_KEY` | Anthropic API key (when `NEMOCLAW_PROVIDER=anthropic`) | Install / onboard |

### Messaging integrations

| Variable | Purpose | When |
|----------|---------|------|
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather | `nemoclaw start` / onboard |
| `ALLOWED_CHAT_IDS` | Comma-separated Telegram chat IDs | `nemoclaw start` |
| `DISCORD_BOT_TOKEN` | Discord bot token | `nemoclaw start` / onboard |
| `SLACK_BOT_TOKEN` | Slack bot token (`xoxb-...`) | `nemoclaw start` / onboard |

When messaging tokens are set during onboard, NemoClaw auto-detects them and suggests the corresponding policy presets (telegram, discord, slack). During `nemoclaw start`, the tokens are passed into the bridge processes.

### Tool integrations

| Variable | Purpose | When |
|----------|---------|------|
| `BRAVE_API_KEY` | Brave Search API key (`BSA-...`) | Post-install (setup.sh Step 6) |

### Policy

| Variable | Purpose | When |
|----------|---------|------|
| `NEMOCLAW_POLICY_MODE` | `suggested` (default), `custom`, or `skip` | Install / onboard |
| `NEMOCLAW_POLICY_PRESETS` | Comma-separated presets (default: `pypi,npm`) | Install / onboard |

Available presets: `pypi`, `npm`, `telegram`, `discord`, `slack`, `brave`, `brew`, `docker`, `huggingface`, `jira`, `outlook`

## What Gets Installed Where

| Component | Location |
|-----------|----------|
| OpenShell binary | `~/.local/bin/openshell` |
| NemoClaw source | `~/.nemoclaw/source/` |
| NemoClaw shim | `~/.local/bin/nemoclaw` |
| Node.js (via nvm) | `~/.nvm/versions/node/v22.x.x/` |
| Credentials | `~/.nemoclaw/credentials.json` |
| Sandbox registry | `~/.nemoclaw/sandboxes.json` |
| OpenShell gateway | Docker container (K3s cluster) |
| Sandbox image | Inside gateway (~2.4 GB) |
| Patch fragments | `nemoclaw-cookbook/patches/fragments/` |
| Dockerfile customizations | `~/NemoClaw/Dockerfile` or `~/.nemoclaw/source/Dockerfile` |

## Sandbox Security Model

The sandbox enforces defense-in-depth via multiple kernel and container mechanisms:

- **Landlock** — `/sandbox` is mounted read-only at the kernel level. The agent's writable state lives in `/sandbox/.openclaw-data/` (workspace, sessions, plugins). Even root cannot write outside the allowed paths.
- **seccomp** — Restricts available syscalls to a safe subset.
- **Network namespacing** — All egress is proxied through OpenShell's L7 policy engine. Only explicitly allowed endpoints are reachable.
- **Immutable config** — `/sandbox/.openclaw/openclaw.json` is protected by `chattr +i` and verified via SHA-256 hash at startup.
- **Privilege separation** — The gateway runs as a separate `gateway` user with `no-new-privileges`.

This means workspace files in `/sandbox/.openclaw-data/workspace/` are writable, but `/sandbox/.openclaw/` is frozen at build time.

## Advanced Onboarding Options

### Custom sandbox images (`--from`)

You can build from a custom Dockerfile instead of the stock sandbox-base image:

```bash
nemoclaw onboard --from /path/to/Dockerfile
```

This is useful for pre-baking additional tools or dependencies. The cookbook's patching workflow (apply-patches.sh) is still the recommended approach for Claude Code and Codex, but `--from` can be combined with it for further customization.

### Interactive preset selection

When running `nemoclaw onboard` interactively (without `NEMOCLAW_NON_INTERACTIVE=1`), the installer now presents a checkbox UI for selecting policy presets. It auto-detects configured credentials and pre-checks the relevant presets. The env var approach (`NEMOCLAW_POLICY_PRESETS`) still works for non-interactive installs.

## Tearing Down

```bash
# Sandbox only
nemoclaw my-assistant destroy --yes

# Full uninstall
nemoclaw uninstall
# Flags: --yes  --keep-openshell  --delete-models
```

## Resources

- NemoClaw Docs: https://docs.nvidia.com/nemoclaw/latest/
- OpenShell Docs: https://docs.nvidia.com/openshell/latest/
- NemoClaw GitHub: https://github.com/NVIDIA/NemoClaw
- OpenShell GitHub: https://github.com/NVIDIA/OpenShell
- NemoClaw Discord: https://discord.gg/XFpfPv9Uvx
