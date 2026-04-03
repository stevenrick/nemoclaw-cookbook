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
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && export TELEGRAM_BOT_TOKEN
[ -n "${ALLOWED_CHAT_IDS:-}" ] && export ALLOWED_CHAT_IDS
[ -n "${CHAT_UI_URL:-}" ] && export CHAT_UI_URL
[ -n "${BRAVE_SEARCH_API_KEY:-}" ] && export BRAVE_SEARCH_API_KEY

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
# Patches last generated against NemoClaw Dockerfile index 2c8e594, policy index 39e93f5
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

echo "=== Step 5b: Integration providers ==="
if [ -n "${BRAVE_SEARCH_API_KEY:-}" ]; then
  echo "  BRAVE_SEARCH_API_KEY detected — creating brave-search provider..."
  openshell provider create --name brave-search --type generic \
    --credential BRAVE_SEARCH_API_KEY 2>/dev/null \
    || openshell provider update brave-search \
      --credential BRAVE_SEARCH_API_KEY 2>/dev/null \
    || echo "  Warning: could not create brave-search provider"
  echo "  Note: If this is a new key on an existing sandbox, run '/add-integration'"
  echo "  in Claude Code to attach the provider (requires sandbox recreation)."
fi

echo "=== Step 6: Start Telegram bridge ==="
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  # Reload env to pick up nvm
  export NVM_DIR="$HOME/.nvm"
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nemoclaw start
else
  echo "TELEGRAM_BOT_TOKEN not set — skipping Telegram bridge."
fi

echo ""
echo "=========================================="
echo "  NemoClaw is ready!"
echo "=========================================="
echo ""
echo "Next steps (inside the sandbox):"
echo "  nemoclaw my-assistant connect"
echo "  claude login"
echo "  codex login --device-auth"
echo "  claude /plugin marketplace add openai/codex-plugin-cc"
echo "  claude /plugin install codex@openai-codex"
echo "  claude /reload-plugins"
echo ""
echo "See USE.md for day-to-day commands."
