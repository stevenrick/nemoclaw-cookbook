# BUILD: NemoClaw + OpenShell from Scratch

Reproducible steps to go from a clean Ubuntu machine to a fully operational NemoClaw sandbox with OpenClaw AI assistant, Claude Code, and Telegram integration.

## Prerequisites

- Ubuntu 22.04 LTS or later
- Docker installed and running
- 8 GB RAM minimum (16 GB recommended), 20 GB free disk
- An NVIDIA API key from https://integrate.api.nvidia.com
- (Optional) Your external proxy URL if accessing remotely (e.g. Brev, ngrok)
- (Optional) A Telegram bot token from @BotFather

## Step 1: Create .env

```bash
cat > ~/.env << 'EOF'
NVIDIA_API_KEY=nvapi-your-key-here
# TELEGRAM_BOT_TOKEN=your-bot-token-here
# ALLOWED_CHAT_IDS=your-chat-id-here
EOF
chmod 600 ~/.env
```

Uncomment the Telegram lines if you have them ready. You can add them later too.

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

The Codex plugin is pre-cloned over HTTPS because Claude Code's `/plugin marketplace add` command
hardcodes SSH for GitHub, which isn't available in the sandbox.

Also add Claude Code's SSO/auth endpoints to the network policy so `claude login` works
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
export NVIDIA_API_KEY
export NEMOCLAW_NON_INTERACTIVE=1

# Set this if accessing via a remote proxy URL:
export CHAT_UI_URL="https://your-proxy-url.example.com"
# Omit CHAT_UI_URL for local-only access (defaults to http://127.0.0.1:18789)

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

## Step 8: Authenticate Claude Code and set up Codex (if installed in Step 5)

```bash
nemoclaw my-assistant connect
```

Inside the sandbox:

```bash
# Authenticate Claude Code via browser SSO
claude login

# Authenticate Codex via browser SSO
codex login --device-auth

# Install the Codex plugin for Claude Code
claude /plugin marketplace add openai/codex-plugin-cc
claude /plugin install codex@openai-codex
claude /reload-plugins
claude /codex:setup    # verify installation
```

Both logins print a URL — open it in your browser and authenticate. Re-run both after any sandbox rebuild. SSO tokens persist across restarts but not rebuilds.

Once installed, Claude Code gains these Codex slash commands:
- `/codex:review` — code review
- `/codex:adversarial-review` — adversarial code review
- `/codex:rescue` — rescue stuck tasks

See https://github.com/openai/codex-plugin-cc for the full command list.

## Step 9: Set up Telegram (optional)

If you didn't add tokens in Step 1:

1. Message **@BotFather** in Telegram, send `/newbot`, get the token
2. Message **@userinfobot** to get your chat ID
3. Add to `~/.env`:
   ```
   TELEGRAM_BOT_TOKEN=your-bot-token
   ALLOWED_CHAT_IDS=your-chat-id
   ```

Start the bridge:

```bash
source ~/.env
export NVIDIA_API_KEY TELEGRAM_BOT_TOKEN ALLOWED_CHAT_IDS
nemoclaw start
```

## Step 10: Save your tokenized UI URL

The installer prints tokenized URLs at the end. Save them:

```bash
# The URLs look like:
# http://127.0.0.1:18789/#token=<hex>
# https://your-proxy.example.com/#token=<hex>
```

Treat these like passwords. They change on every sandbox rebuild.

## Rebuilding the sandbox

Any time you need to rebuild (update, config change, etc.):

```bash
source ~/.env && export NVIDIA_API_KEY
export NEMOCLAW_NON_INTERACTIVE=1
export CHAT_UI_URL="https://your-proxy-url.example.com"  # if applicable

nemoclaw stop 2>/dev/null; kill $(pgrep -f telegram-bridge) $(pgrep -f cloudflared) 2>/dev/null
docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest
nemoclaw my-assistant destroy --yes
nemoclaw onboard
```

After rebuild:
1. Save the new tokenized URL
2. Re-run `claude login` and `codex login --device-auth` inside the sandbox (SSO tokens don't survive rebuilds)
3. Re-install the Codex plugin:
   ```
   claude /plugin marketplace add openai/codex-plugin-cc
   claude /plugin install codex@openai-codex
   claude /reload-plugins
   ```
4. Restart Telegram: `source ~/.env && export NVIDIA_API_KEY TELEGRAM_BOT_TOKEN ALLOWED_CHAT_IDS && nemoclaw start`

## Troubleshooting

### "origin not allowed" in the Web UI

Your proxy URL wasn't set when the sandbox was built. Rebuild with `CHAT_UI_URL` set.

### Commands not found after install

```bash
source ~/.bashrc
# Or manually:
export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"
```

## Environment Variables

| Variable | Purpose | When |
|----------|---------|------|
| `NVIDIA_API_KEY` | NVIDIA inference key | Install / onboard |
| `NEMOCLAW_NON_INTERACTIVE=1` | Skip all prompts | Install / onboard |
| `CHAT_UI_URL` | External URL for web UI (sets allowedOrigins) | Install / onboard |
| `NEMOCLAW_SANDBOX_NAME` | Custom sandbox name (default: `my-assistant`) | Install / onboard |
| `NEMOCLAW_RECREATE_SANDBOX=1` | Force-recreate existing sandbox | Onboard |
| `NEMOCLAW_PROVIDER` | Provider type: `cloud`, `ollama`, `nim`, `vllm` | Install / onboard |
| `NEMOCLAW_MODEL` | Override inference model | Install / onboard |
| `NEMOCLAW_POLICY_MODE` | `suggested`, `custom`, or `skip` | Install / onboard |
| `NEMOCLAW_POLICY_PRESETS` | Comma-separated presets (default: `pypi,npm`) | Install / onboard |
| `NEMOCLAW_EXPERIMENTAL=1` | Enable experimental providers (local NIM, vLLM) | Install / onboard |
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather | `nemoclaw start` |
| `ALLOWED_CHAT_IDS` | Comma-separated Telegram chat IDs | `nemoclaw start` |

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
| Dockerfile customizations | `~/NemoClaw/Dockerfile` |

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
