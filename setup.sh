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

# Optional sandbox tools (default: true for backward compatibility)
export INSTALL_CLAUDE_CODE="${INSTALL_CLAUDE_CODE:-true}"
export INSTALL_CODEX="${INSTALL_CODEX:-true}"

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
  git -C NemoClaw checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null || true
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
# Uses modular fragments (not git apply) for resilience to upstream changes.
# If patches fail, see BUILD.md or run: claude /refresh-patches
cd "$HOME/NemoClaw"
git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null || true

"${SCRIPT_DIR}/scripts/apply-patches.sh" "$HOME/NemoClaw"

# If a sandbox already exists, check if it's current. The manifest records the
# NemoClaw commit the image was built from. If upstream moved, force a rebuild
# so the new patches take effect.
if [ -f "$HOME/.nemoclaw/cookbook-deployment.json" ]; then
  CURRENT_NC=$(git -C "$HOME/NemoClaw" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  MANIFEST_NC=$(python3 -c "import json; print(json.load(open('$HOME/.nemoclaw/cookbook-deployment.json')).get('nemoclaw_commit',''))" 2>/dev/null || echo "")
  if [ "$CURRENT_NC" != "$MANIFEST_NC" ] && [ -n "$MANIFEST_NC" ]; then
    echo "  Upstream NemoClaw changed ($MANIFEST_NC → $CURRENT_NC) — forcing sandbox rebuild."
    export NEMOCLAW_RECREATE_SANDBOX=1
  fi
fi

echo "=== Step 5: Install NemoClaw ==="
cd "$HOME/NemoClaw"
bash install.sh --non-interactive
# shellcheck source=/dev/null
source "$HOME/.bashrc" 2>/dev/null || true

echo "=== Step 6: Save tokenized UI URL ==="
# Token is available as soon as the sandbox is running (step 5).
# Extract it now, before any optional steps, so the URL file exists ASAP.
"${SCRIPT_DIR}/scripts/save-ui-url.sh" || echo "  URL extraction failed — retrieve manually (see BUILD.md)."

echo "=== Step 7: Add optional integrations ==="
if [ -n "${BRAVE_API_KEY:-}" ]; then
  echo "  Adding Brave Search provider..."
  openshell provider create --name brave-search --type generic --credential BRAVE_API_KEY 2>/dev/null \
    || openshell provider update brave-search --credential BRAVE_API_KEY 2>/dev/null \
    || echo "  Warning: could not configure brave-search provider"
  echo "  ✓ Brave Search provider configured"
fi

echo "=== Step 8: Start services ==="
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || [ -n "${DISCORD_BOT_TOKEN:-}" ] || [ -n "${SLACK_BOT_TOKEN:-}" ]; then
  # Reload env to pick up nvm
  export NVM_DIR="$HOME/.nvm"
  # shellcheck source=/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nemoclaw start
else
  echo "No messaging tokens set — skipping services. Set TELEGRAM_BOT_TOKEN, DISCORD_BOT_TOKEN, or SLACK_BOT_TOKEN in ~/.env to enable."
fi

echo "=== Step 9: Verify deployment ==="
"${SCRIPT_DIR}/scripts/verify-deployment.sh" || echo "  Some checks failed — review above and fix before proceeding."

echo "=== Step 10: Write deployment manifest ==="
"${SCRIPT_DIR}/scripts/write-manifest.sh"

echo ""
echo "=========================================="
echo "  NemoClaw is ready!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Port-forward the Web UI:  brev port-forward <instance> -p 18789:18789"
echo "  2. Get the tokenized URL:    cat ~/openclaw-ui-url.txt"
if [ "$INSTALL_CODEX" = "true" ]; then
  echo "  3. Authenticate Codex (can be scripted via brev exec):"
  echo "     codex login --device-auth"
fi
if [ "$INSTALL_CLAUDE_CODE" = "true" ]; then
  echo "  4. Authenticate Claude Code (interactive via brev shell):"
  echo "     brev shell <instance> → nemoclaw my-assistant connect → claude"
fi
echo ""
echo "See USE.md for day-to-day commands."
