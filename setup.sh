#!/usr/bin/env bash
# NemoClaw automated setup — from clean machine to operational sandbox.
# Usage: ./setup.sh
#
# Prerequisites:
#   - Docker installed and running
#   - ~/.env populated (copy from .env.example)
set -euo pipefail
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HOME}/.env"

normalize_nemoclaw_source_modes() {
  if [ -d "$HOME/NemoClaw" ]; then
    find "$HOME/NemoClaw" -path "$HOME/NemoClaw/.git" -prune -o -perm /022 -exec chmod go-w {} +
  fi
}

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
[ -n "${NEMOCLAW_RESOURCE_PROFILE:-}" ] && export NEMOCLAW_RESOURCE_PROFILE
[ -n "${NEMOCLAW_CPU:-}" ] && export NEMOCLAW_CPU
[ -n "${NEMOCLAW_RAM:-}" ] && export NEMOCLAW_RAM
[ -n "${NEMOCLAW_EXPERIMENTAL:-}" ] && export NEMOCLAW_EXPERIMENTAL

# Alternative inference provider keys
[ -n "${OPENAI_API_KEY:-}" ] && export OPENAI_API_KEY
[ -n "${ANTHROPIC_API_KEY:-}" ] && export ANTHROPIC_API_KEY

# Messaging integrations
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && export TELEGRAM_BOT_TOKEN
[ -n "${TELEGRAM_ALLOWED_IDS:-}" ] && export TELEGRAM_ALLOWED_IDS
[ -n "${TELEGRAM_REQUIRE_MENTION:-}" ] && export TELEGRAM_REQUIRE_MENTION
[ -n "${DISCORD_BOT_TOKEN:-}" ] && export DISCORD_BOT_TOKEN
[ -n "${DISCORD_SERVER_ID:-}" ] && export DISCORD_SERVER_ID
[ -n "${DISCORD_SERVER_IDS:-}" ] && export DISCORD_SERVER_IDS
[ -n "${DISCORD_USER_ID:-}" ] && export DISCORD_USER_ID
[ -n "${DISCORD_ALLOWED_IDS:-}" ] && export DISCORD_ALLOWED_IDS
[ -n "${DISCORD_REQUIRE_MENTION:-}" ] && export DISCORD_REQUIRE_MENTION
[ -n "${SLACK_BOT_TOKEN:-}" ] && export SLACK_BOT_TOKEN
[ -n "${SLACK_APP_TOKEN:-}" ] && export SLACK_APP_TOKEN
[ -n "${SLACK_ALLOWED_USERS:-}" ] && export SLACK_ALLOWED_USERS
[ -n "${SLACK_ALLOWED_CHANNELS:-}" ] && export SLACK_ALLOWED_CHANNELS
[ -n "${WECHAT_ALLOWED_IDS:-}" ] && export WECHAT_ALLOWED_IDS
[ -n "${NEMOCLAW_WECHAT_QUIET:-}" ] && export NEMOCLAW_WECHAT_QUIET

# Tool integrations
[ -n "${BRAVE_API_KEY:-}" ] && export BRAVE_API_KEY
[ -n "${TAVILY_API_KEY:-}" ] && export TAVILY_API_KEY
[ -n "${NEMOCLAW_WEB_SEARCH_PROVIDER:-}" ] && export NEMOCLAW_WEB_SEARCH_PROVIDER
[ -n "${NEMOCLAW_OPENAI_HTTP_ENABLED:-}" ] && export NEMOCLAW_OPENAI_HTTP_ENABLED
[ -n "${NEMOCLAW_OPENAI_HTTP_TUNNEL:-}" ] && export NEMOCLAW_OPENAI_HTTP_TUNNEL
[ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] && export CLOUDFLARE_TUNNEL_TOKEN

# Policy configuration
[ -n "${NEMOCLAW_POLICY_TIER:-}" ] && export NEMOCLAW_POLICY_TIER
[ -n "${NEMOCLAW_POLICY_MODE:-}" ] && export NEMOCLAW_POLICY_MODE
[ -n "${NEMOCLAW_POLICY_PRESETS:-}" ] && export NEMOCLAW_POLICY_PRESETS

# Access URL configuration. Upstream NemoClaw now uses CHAT_UI_URL to bake the
# dashboard origin and to disable device auth for non-loopback browser access.
TUNNEL_FQDN="${TUNNEL_FQDN:-}"
TUNNEL_FQDN="${TUNNEL_FQDN#https://}"
TUNNEL_FQDN="${TUNNEL_FQDN#http://}"
if [ -n "$TUNNEL_FQDN" ]; then
  export CHAT_UI_URL="https://$TUNNEL_FQDN"
fi
[ -n "${CHAT_UI_URL:-}" ] && export CHAT_UI_URL
[ -n "${NEMOCLAW_CORS_ORIGIN:-}" ] && export NEMOCLAW_CORS_ORIGIN

# Integration config payload (NEMOCLAW_INTEGRATIONS_B64) is computed by
# apply-patches.sh from cookbook-only .env-driven flags such as
# NEMOCLAW_OPENAI_HTTP_ENABLED via scripts/build-integrations-config.py.

echo "=== Step 1: Clone / update repositories ==="
cd "$HOME"
if [ -d NemoClaw ]; then
  echo "  NemoClaw exists, pulling latest..."
  git -C NemoClaw checkout -- Dockerfile Dockerfile.base package-lock.json nemoclaw-blueprint/policies/openclaw-sandbox.yaml scripts/nemoclaw-start.sh 2>/dev/null || true
  git -C NemoClaw pull --ff-only || echo "  Warning: pull failed, continuing with existing checkout"
else
  git clone https://github.com/NVIDIA/NemoClaw
fi
normalize_nemoclaw_source_modes

echo "=== Step 2: Install OpenShell via upstream NemoClaw ==="
cd "$HOME/NemoClaw"
bash scripts/install-openshell.sh
export PATH="$HOME/.local/bin:$PATH"
if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
  # shellcheck disable=SC2016
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
openshell --version

echo "=== Step 3: Apply patches ==="
# See UPSTREAM.md for the versions patches were last validated against.
# Uses modular fragments (not git apply) for resilience to upstream changes.
cd "$HOME/NemoClaw"
git checkout -- Dockerfile Dockerfile.base package-lock.json nemoclaw-blueprint/policies/openclaw-sandbox.yaml scripts/nemoclaw-start.sh 2>/dev/null || true
normalize_nemoclaw_source_modes

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

echo "=== Step 4: Install NemoClaw ==="
# If a prior run died mid-onboard, install.sh refuses to start a new session.
# Detect a failed-status session and auto-recover by passing NEMOCLAW_FRESH=1.
# Users can still set NEMOCLAW_FRESH=1 explicitly to force a clean start.
ONBOARD_SESSION="$HOME/.nemoclaw/onboard-session.json"
if [ -z "${NEMOCLAW_FRESH:-}" ] && [ -f "$ONBOARD_SESSION" ]; then
  if python3 -c "import json,sys; sys.exit(0 if json.load(open('$ONBOARD_SESSION')).get('status')=='failed' else 1)" 2>/dev/null; then
    echo "  Detected failed prior onboard session — auto-setting NEMOCLAW_FRESH=1."
    export NEMOCLAW_FRESH=1
  fi
fi
cd "$HOME/NemoClaw"
bash install.sh --non-interactive
# shellcheck source=/dev/null
source "$HOME/.bashrc" 2>/dev/null || true

# ── Post-deploy ──────────────────────────────────────────────────────
# Core deploy (Steps 1-5) is complete. The remaining steps are individually
# fault-tolerant so critical work (URL extraction, port forward) always
# runs even if an earlier post-deploy step fails.
set +e
POST_FAILURES=0

SANDBOX=$(nemoclaw list 2>/dev/null | awk '/\*/{print $1}' | head -1)
SANDBOX="${SANDBOX:-my-assistant}"

echo "=== Step 5: Install services (nginx, systemd, terminal server) ==="
if "${SCRIPT_DIR}/scripts/install-services.sh"; then
  # CHAT_UI_URL may now be set by install-services.sh (cloudflared FQDN detection)
  [ -n "${CHAT_UI_URL:-}" ] && export CHAT_UI_URL
else
  echo "  Warning: service installation had errors (continuing)"
  POST_FAILURES=$((POST_FAILURES + 1))
fi

echo "=== Step 6: Save tokenized UI URL ==="
# Token is available as soon as the sandbox is running.
# Extract it now, before optional steps, so the URL file exists ASAP.
"${SCRIPT_DIR}/scripts/save-ui-url.sh" || {
  echo "  Warning: URL extraction failed — retrieve manually (see BUILD.md)."
  POST_FAILURES=$((POST_FAILURES + 1))
}

echo "=== Step 7: Start services ==="
# Reload env to pick up nvm
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Refresh the port forward after setup/rebuild. `nemoclaw <name> recover`
# rebuilds the forward in a single step that knows how to wait for the
# gateway — more reliable than raw `forward stop/start`, which races gateway
# readiness.
if [ -n "$SANDBOX" ]; then
  openshell forward stop 18789 "$SANDBOX" 2>/dev/null || true
  if nemoclaw "$SANDBOX" recover 2>/dev/null; then
    # Probe the forward — recover returns before the gateway is fully
    # accepting connections in some races. Up to 20s of polling.
    for _ in $(seq 1 10); do
      curl -sf --max-time 2 -o /dev/null http://127.0.0.1:18789/ 2>/dev/null && break
      sleep 2
    done
  else
    # Fallback to the older path if recover isn't available.
    sleep 1
    openshell forward start 18789 "$SANDBOX" --background 2>/dev/null || true
  fi
fi

# Messaging channels are configured by upstream onboard/rebuild. `nemoclaw
# tunnel start` is only needed for an optional Cloudflare tunnel, not for the
# host-side channel registry itself.
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  nemoclaw tunnel start || {
    echo "  Warning: failed to start Cloudflare tunnel"
    POST_FAILURES=$((POST_FAILURES + 1))
  }
else
  echo "  No CLOUDFLARE_TUNNEL_TOKEN set — skipping optional cloudflared tunnel."
fi

echo "=== Step 8: Write deployment manifest ==="
"${SCRIPT_DIR}/scripts/write-manifest.sh" || {
  echo "  Warning: manifest write failed"
  POST_FAILURES=$((POST_FAILURES + 1))
}

echo "=== Step 9: Verify deployment ==="
"${SCRIPT_DIR}/scripts/verify-deployment.sh" || echo "  Some checks failed — review above."

set -e

echo ""
if [ "$POST_FAILURES" -gt 0 ]; then
  echo "=========================================="
  echo "  NemoClaw is running ($POST_FAILURES post-deploy warning(s))"
  echo "=========================================="
else
  echo "=========================================="
  echo "  NemoClaw is ready!"
  echo "=========================================="
fi
echo ""
if [ -f "$HOME/openclaw-tunnel-url.txt" ]; then
  echo "Web UI: ~/openclaw-tunnel-url.txt"
  echo "  Open the URL from that file — no port forwarding needed."
else
  echo "Web UI: brev port-forward <instance> -p 18789:18789"
  echo "  Then open the URL saved in ~/openclaw-ui-url.txt."
  echo ""
  echo "  To use a Secure Link instead (no port-forward):"
  echo "    1. Create a Brev Secure Link / service endpoint to host port 80"
  echo "    2. Set TUNNEL_FQDN=<your-link> in ~/.env"
  echo "    3. For Brev apps.run endpoints, also set NEMOCLAW_NGINX_LISTEN_ADDR=0.0.0.0"
  echo "    4. Re-run setup.sh"
fi
echo ""
echo "Next steps:"
echo "  Open the Web UI above, or run:"
echo "     nemoclaw ${SANDBOX} connect"
echo ""
echo "See USE.md for day-to-day commands."
