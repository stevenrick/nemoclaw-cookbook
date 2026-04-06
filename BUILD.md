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

In `~/NemoClaw/Dockerfile`, find:

```dockerfile
# Set up blueprint for local resolution
```

Add this line immediately before it:

```dockerfile
# Force git to use HTTPS instead of SSH (sandbox has no ssh)
RUN git config --global url.'https://github.com/'.insteadOf 'git@github.com:' \
    && git config --global --add url.'https://github.com/'.insteadOf 'ssh://git@github.com/' \
    && git config --global http.sslCAInfo /etc/openshell-tls/ca-bundle.pem \
    && cp /root/.gitconfig /sandbox/.gitconfig && chown 1000:1000 /sandbox/.gitconfig

# Install Claude Code via native installer and Codex CLI via npm
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && cp "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude \
    && chmod 755 /usr/local/bin/claude \
    && npm install -g @openai/codex@latest
```

The native installer puts the binary in `/root/.local/` which the sandbox user can't access. The `cp` + `readlink -f` resolves the symlink chain and copies the actual binary to `/usr/local/bin/`.

The git HTTPS config ensures plugin and marketplace cloning works inside the sandbox (git is redirected from SSH to HTTPS). The Codex plugin for Claude Code is installed manually after first connect (see Step 8).

Also add Claude Code's SSO/auth endpoints to the network policy so Claude Code's login flow works
without manual approval. In `~/NemoClaw/nemoclaw-blueprint/policies/openclaw-sandbox.yaml`,
find the `claude_code` policy's `sentry.io` entry and add these three endpoints after it
(before the `binaries:` line):

```yaml
      - host: platform.claude.com
        port: 443
        access: full
      - host: downloads.claude.ai
        port: 443
        access: full
      - host: raw.githubusercontent.com
        port: 443
        access: full
```

Also add `/usr/local/bin/codex` to the `binaries:` list alongside claude.

Then add an `openai` policy block after the `claude_code` block (before `nvidia:`):

```yaml
  openai:
    name: openai
    endpoints:
      - host: api.openai.com
        port: 443
        protocol: rest
        enforcement: enforce
        tls: terminate
        rules:
          - allow: { method: GET, path: "/**" }
          - allow: { method: POST, path: "/**" }
      - host: auth.openai.com
        port: 443
        access: full
      - host: chatgpt.com
        port: 443
        access: full
      - host: ab.chatgpt.com
        port: 443
        access: full
    binaries:
      - { path: /usr/local/bin/codex }
```

Also update the existing `github` policy — add `codeload.github.com` to endpoints and
`claude`/`codex`/`node` to binaries:

```yaml
      - host: codeload.github.com
        port: 443
        access: full
    binaries:
      ...existing entries...
      - { path: /usr/local/bin/claude }
      - { path: /usr/local/bin/codex }
      - { path: /usr/local/bin/node }
```

OpenShell policies are binary-scoped — Codex runs under `node`, so the GitHub policy
needs to know that `node`, `claude`, and `codex` are allowed to reach GitHub endpoints.
`codeload.github.com` is used for downloading release tarballs (e.g. plugin installs).

Without these policy changes, you'd need to manually approve endpoints in `openshell term`.

Both changes survive all future rebuilds.

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

This also starts a Cloudflare quick tunnel for the Telegram webhook URL.

## Step 10: Save your tokenized UI URL

The installer prints tokenized URLs at the end. Save them:

```bash
cat ~/openclaw-ui-url.txt
# http://127.0.0.1:18789/#token=<hex>
```

Treat these like passwords. They change on every sandbox rebuild.

## Accessing the Web UI

Port-forward the Web UI to your local machine:

```bash
brev port-forward <instance-name> -p 18789:18789
```

Then open `http://127.0.0.1:18789/#token=<hex>` in your browser (get the token from `~/openclaw-ui-url.txt` on the instance). **Use `127.0.0.1`, not `localhost`** — the sandbox only allows `127.0.0.1` as an origin. This returns immediately — Brev backgrounds the SSH tunnel.

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
4. If you already have a running sandbox, use Claude Code: `claude /add-integration`
   This backs up your workspace, creates the provider, recreates the sandbox, and restores.

### Adding other services

To add a new API integration:

1. Add the API key to `.env` in the cookbook repo
2. Add a network policy block to `patches/policy.patch` for the service's endpoints
3. Update `.env.example` with the new key
5. Run `/add-integration` to apply to a running sandbox

### Why recreation is needed

OpenShell providers (credential bundles injected into the sandbox) can only be attached at sandbox creation time. Adding a new provider to an existing sandbox requires destroying and recreating it. The `/add-integration` skill automates the backup/restore around this constraint.

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

# 4. Restore workspace, chat history, and skills (or use /restore from Claude Code)
~/nemoclaw-cookbook/scripts/backup-full.sh restore my-assistant
```

After rebuild:
1. Re-authenticate: run `codex login --device-auth` then launch `claude` (login is forced on first launch) inside the sandbox (SSO tokens don't survive rebuilds)
2. Reinstall the Codex plugin for Claude Code (`/plugin marketplace add openai/codex-plugin-cc`, etc.)
3. Restart messaging: `nemoclaw start` (with tokens exported)

## Refreshing Patches After Upstream Updates

The patches in `patches/` are unified diffs generated against a specific version of NemoClaw. When NVIDIA updates the upstream files, the patches may fail to apply.

### Quick path (with Claude Code)

```bash
claude /refresh-patches
```

This skill walks Claude through diagnosing the conflict, understanding what changed upstream, and regenerating the patches while preserving their intent.

### Manual path

1. Reset and inspect:
   ```bash
   cd ~/NemoClaw
   git pull origin main
   git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
   ```

2. Try applying with 3-way merge:
   ```bash
   git apply --3way /path/to/nemoclaw-cookbook/patches/Dockerfile.patch
   git apply --3way /path/to/nemoclaw-cookbook/patches/policy.patch
   ```

3. If conflicts appear, resolve them in the affected files, then regenerate:
   ```bash
   git diff Dockerfile > /path/to/nemoclaw-cookbook/patches/Dockerfile.patch
   git diff nemoclaw-blueprint/policies/openclaw-sandbox.yaml > /path/to/nemoclaw-cookbook/patches/policy.patch
   ```

4. Reset and verify the round-trip:
   ```bash
   git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
   git apply --3way /path/to/nemoclaw-cookbook/patches/Dockerfile.patch
   git apply --3way /path/to/nemoclaw-cookbook/patches/policy.patch
   ```

5. Update `UPSTREAM.md` with the current NemoClaw and OpenShell commits and sandbox-base image tag.

### What to preserve

The patches add these logical pieces — if upstream restructures things, adapt the placement but keep the intent:

- **Dockerfile**: git HTTPS config, Claude Code binary install (with sandbox user symlink), Codex CLI install, sandbox user ownership fixes
- **Policy**: Claude auth endpoints, OpenAI policy block (with node binary), GitHub policy extensions (codeload.github.com + binaries)

See the `/refresh-patches` skill for the full breakdown.

### Automated validation

To check if patches still apply against the latest upstream (without modifying anything):

```bash
./scripts/validate-patches.sh
```

This clones upstream into a temp directory, tests each patch with `--check --3way`, and reports pass/fail. Safe to run in CI on a schedule to catch upstream drift early.

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

Available presets: `pypi`, `npm`, `telegram`, `discord`, `slack`, `brave`, `docker`, `huggingface`, `jira`, `outlook`

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
| Dockerfile customizations | `~/NemoClaw/Dockerfile` or `~/.nemoclaw/source/Dockerfile` |

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
