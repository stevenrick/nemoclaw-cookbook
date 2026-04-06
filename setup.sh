#!/usr/bin/env bash
# NemoClaw automated setup — from clean machine to operational sandbox.
# Usage: ./setup.sh
#
# Prerequisites:
#   - Docker installed and running
#   - ~/.env populated (copy from .env.example)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HOME}/.env"

# ── Preflight ─────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: ~/.env not found. Copy .env.example and fill in your keys:"
  echo "  cp ${SCRIPT_DIR}/.env.example ~/.env"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [ -z "${NVIDIA_API_KEY:-}" ]; then
  echo "ERROR: NVIDIA_API_KEY not set in ~/.env"
  exit 1
fi

export NVIDIA_API_KEY
export NEMOCLAW_NON_INTERACTIVE=1
export NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1

# Inference configuration
[ -n "${NEMOCLAW_MODEL:-}" ] && export NEMOCLAW_MODEL
[ -n "${NEMOCLAW_PROVIDER:-}" ] && export NEMOCLAW_PROVIDER
[ -n "${NEMOCLAW_ENDPOINT_URL:-}" ] && export NEMOCLAW_ENDPOINT_URL
[ -n "${NEMOCLAW_GPU:-}" ] && export NEMOCLAW_GPU
[ -n "${NEMOCLAW_EXPERIMENTAL:-}" ] && export NEMOCLAW_EXPERIMENTAL

# Alternative inference provider keys
[ -n "${OPENAI_API_KEY:-}" ] && export OPENAI_API_KEY
[ -n "${ANTHROPIC_API_KEY:-}" ] && export ANTHROPIC_API_KEY

# Messaging integrations
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && export TELEGRAM_BOT_TOKEN
[ -n "${ALLOWED_CHAT_IDS:-}" ] && export ALLOWED_CHAT_IDS
[ -n "${DISCORD_BOT_TOKEN:-}" ] && export DISCORD_BOT_TOKEN
[ -n "${SLACK_BOT_TOKEN:-}" ] && export SLACK_BOT_TOKEN

# Tool integrations
[ -n "${BRAVE_API_KEY:-}" ] && export BRAVE_API_KEY

# Policy configuration
[ -n "${NEMOCLAW_POLICY_MODE:-}" ] && export NEMOCLAW_POLICY_MODE
[ -n "${NEMOCLAW_POLICY_PRESETS:-}" ] && export NEMOCLAW_POLICY_PRESETS

echo "=== Step 1: Clone / update repositories ==="
cd "$HOME"
if [ -d OpenShell ]; then
  echo "  OpenShell exists, pulling latest..."
  git -C OpenShell pull --ff-only || echo "  Warning: pull failed, continuing with existing checkout"
else
  git clone https://github.com/NVIDIA/OpenShell
fi
if [ -d NemoClaw ]; then
  echo "  NemoClaw exists, pulling latest..."
  git -C NemoClaw pull --ff-only || echo "  Warning: pull failed, continuing with existing checkout"
else
  git clone https://github.com/NVIDIA/NemoClaw
fi

echo "=== Step 2: Install OpenShell ==="
cd "$HOME/OpenShell"
sh install.sh
export PATH="$HOME/.local/bin:$PATH"
if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
  # shellcheck disable=SC2016
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
openshell --version

echo "=== Step 3: Pull latest sandbox base image ==="
docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest

echo "=== Step 4: Apply patches ==="
# See UPSTREAM.md for the versions patches were last validated against.
# If patches fail, see BUILD.md "Refreshing Patches" or run: claude /refresh-patches
cd "$HOME/NemoClaw"
git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null || true

apply_patch() {
  local patch="$1"
  local name
  name="$(basename "$patch")"
  if git apply --3way "$patch" 2>/tmp/patch_err_$$; then
    echo "  ✓ $name applied cleanly"
  else
    echo ""
    echo "ERROR: $name failed to apply."
    echo ""
    echo "This usually means upstream NemoClaw changed the files this patch targets."
    echo "The partially-merged files may have conflict markers (<<<<<<)."
    echo ""
    echo "To fix:"
    echo "  1. cd $HOME/NemoClaw"
    echo "  2. Resolve conflicts in the affected file(s)"
    echo "  3. Regenerate the patch:  git diff <file> > ${SCRIPT_DIR}/patches/$name"
    echo "  4. Re-run this script"
    echo ""
    echo "Or use Claude Code:  claude /refresh-patches"
    echo ""
    cat /tmp/patch_err_$$ 2>/dev/null
    rm -f /tmp/patch_err_$$
    exit 1
  fi
  rm -f /tmp/patch_err_$$
}

apply_patch "${SCRIPT_DIR}/patches/Dockerfile.patch"
apply_patch "${SCRIPT_DIR}/patches/policy.patch"
echo "Patches applied."

echo "=== Step 5: Install NemoClaw ==="
cd "$HOME/NemoClaw"
bash install.sh --non-interactive
# shellcheck source=/dev/null
source "$HOME/.bashrc" 2>/dev/null || true

echo "=== Step 6: Add optional integrations ==="
if [ -n "${BRAVE_API_KEY:-}" ]; then
  echo "  Adding Brave Search provider..."
  openshell provider create --name brave-search --type generic --credential BRAVE_API_KEY 2>/dev/null \
    || openshell provider update brave-search --credential BRAVE_API_KEY 2>/dev/null \
    || echo "  Warning: could not configure brave-search provider"
  echo "  ✓ Brave Search provider configured"
fi

echo "=== Step 7: Start services ==="
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || [ -n "${DISCORD_BOT_TOKEN:-}" ] || [ -n "${SLACK_BOT_TOKEN:-}" ]; then
  # Reload env to pick up nvm
  export NVM_DIR="$HOME/.nvm"
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nemoclaw start
else
  echo "No messaging tokens set — skipping services. Set TELEGRAM_BOT_TOKEN, DISCORD_BOT_TOKEN, or SLACK_BOT_TOKEN in ~/.env to enable."
fi

echo ""
echo "=========================================="
echo "  NemoClaw is ready!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Port-forward the Web UI:  brev port-forward <instance> -p 18789:18789"
echo "  2. Get the tokenized URL:    cat ~/openclaw-ui-url.txt"
echo "  3. Authenticate Codex (can be scripted via brev exec):"
echo "     codex login --device-auth"
echo "  4. Authenticate Claude Code + install Codex plugin inside Claude Code (interactive via brev shell):"
echo "     brev shell <instance> → nemoclaw my-assistant connect → claude"
echo ""
echo "See USE.md for day-to-day commands."
