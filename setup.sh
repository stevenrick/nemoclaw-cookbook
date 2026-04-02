#!/usr/bin/env bash
# NemoClaw automated setup — from clean machine to operational sandbox.
# Usage: ./setup.sh
#
# Prerequisites:
#   - Docker installed and running
#   - ~/.env populated (copy from .env.example)
#   - CHAT_UI_URL env var set if using a remote proxy (e.g. Brev)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HOME}/.env"

# ── Preflight ─────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: ~/.env not found. Copy .env.example and fill in your keys:"
  echo "  cp ${SCRIPT_DIR}/.env.example ~/.env"
  exit 1
fi

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

echo "=== Step 1: Clone repositories ==="
cd "$HOME"
[ -d OpenShell ] || git clone https://github.com/NVIDIA/OpenShell
[ -d NemoClaw ] || git clone https://github.com/NVIDIA/NemoClaw

echo "=== Step 2: Install OpenShell ==="
cd "$HOME/OpenShell"
sh install.sh
export PATH="$HOME/.local/bin:$PATH"
if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
openshell --version

echo "=== Step 3: Pull latest sandbox base image ==="
docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest

echo "=== Step 4: Apply patches ==="
cd "$HOME/NemoClaw"
git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null || true
git apply "${SCRIPT_DIR}/patches/Dockerfile.patch"
git apply "${SCRIPT_DIR}/patches/policy.patch"
echo "Patches applied."

echo "=== Step 5: Install NemoClaw ==="
cd "$HOME/NemoClaw"
bash install.sh --non-interactive
source "$HOME/.bashrc" 2>/dev/null || true

echo "=== Step 6: Start Telegram bridge ==="
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  # Reload env to pick up nvm
  export NVM_DIR="$HOME/.nvm"
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
