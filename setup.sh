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
NEMOCLAW_SOURCE_DIR="${NEMOCLAW_SOURCE_DIR:-$HOME/NemoClaw}"
export NEMOCLAW_SOURCE_DIR
# shellcheck source=scripts/lib/agent-runtime.sh
source "$SCRIPT_DIR/scripts/lib/agent-runtime.sh"

normalize_nemoclaw_source_modes() {
  if [ -d "$NEMOCLAW_SOURCE_DIR" ]; then
    find "$NEMOCLAW_SOURCE_DIR" -path "$NEMOCLAW_SOURCE_DIR/.git" -prune -o -perm /022 -exec chmod go-w {} +
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

if [ -z "${NVIDIA_INFERENCE_API_KEY:-}" ] && [ -z "${NVIDIA_API_KEY:-}" ]; then
  echo "ERROR: NVIDIA_INFERENCE_API_KEY (or legacy NVIDIA_API_KEY) not set in ~/.env"
  exit 1
fi

NVIDIA_INFERENCE_API_KEY="${NVIDIA_INFERENCE_API_KEY:-$NVIDIA_API_KEY}"
NVIDIA_API_KEY="${NVIDIA_API_KEY:-$NVIDIA_INFERENCE_API_KEY}"
export NVIDIA_INFERENCE_API_KEY NVIDIA_API_KEY
export NEMOCLAW_NON_INTERACTIVE=1
export NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1

if ! ACTIVE_AGENT="$(cookbook_normalize_agent "${NEMOCLAW_AGENT:-openclaw}")"; then
  echo "ERROR: NEMOCLAW_AGENT must be openclaw, hermes, or langchain-deepagents-code"
  exit 1
fi
export NEMOCLAW_AGENT="$ACTIVE_AGENT"
NEMOCLAW_SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-my-assistant}"
if ! cookbook_valid_sandbox_name "$NEMOCLAW_SANDBOX_NAME"; then
  echo "ERROR: NEMOCLAW_SANDBOX_NAME must start with a letter or digit and contain only letters, digits, dots, underscores, or hyphens"
  exit 1
fi
if [ "$ACTIVE_AGENT" = "hermes" ] && [ "${#NEMOCLAW_SANDBOX_NAME}" -gt 19 ]; then
  echo "ERROR: Hermes sandbox names must be 19 characters or fewer"
  exit 1
fi
export NEMOCLAW_SANDBOX_NAME

if [ "$ACTIVE_AGENT" != "openclaw" ]; then
  case "${NEMOCLAW_OPENAI_HTTP_ENABLED:-}" in
    1|true|yes)
      echo "ERROR: NEMOCLAW_OPENAI_HTTP_ENABLED is a cookbook OpenClaw overlay."
      echo "Leave it unset for $ACTIVE_AGENT; Hermes exposes a native API and Deep Agents Code is terminal-only."
      exit 1
      ;;
  esac
fi

# Inference configuration
[ -n "${NEMOCLAW_MODEL:-}" ] && export NEMOCLAW_MODEL
[ -n "${NEMOCLAW_PROVIDER:-}" ] && export NEMOCLAW_PROVIDER
[ -n "${NEMOCLAW_ENDPOINT_URL:-}" ] && export NEMOCLAW_ENDPOINT_URL
[ -n "${NEMOCLAW_GPU:-}" ] && export NEMOCLAW_GPU
[ -n "${NEMOCLAW_RESOURCE_PROFILE:-}" ] && export NEMOCLAW_RESOURCE_PROFILE
[ -n "${NEMOCLAW_CPU:-}" ] && export NEMOCLAW_CPU
[ -n "${NEMOCLAW_RAM:-}" ] && export NEMOCLAW_RAM
[ -n "${NEMOCLAW_EXPERIMENTAL:-}" ] && export NEMOCLAW_EXPERIMENTAL
[ -n "${NEMOCLAW_DASHBOARD_PORT:-}" ] && export NEMOCLAW_DASHBOARD_PORT
[ -n "${NEMOCLAW_HERMES_API_PORT:-}" ] && export NEMOCLAW_HERMES_API_PORT
[ -n "${NEMOCLAW_HERMES_DASHBOARD_TUI:-}" ] && export NEMOCLAW_HERMES_DASHBOARD_TUI
[ -n "${NEMOCLAW_TOOL_DISCLOSURE:-}" ] && export NEMOCLAW_TOOL_DISCLOSURE
[ -n "${NEMOCLAW_DCODE_AUTO_APPROVAL:-}" ] && export NEMOCLAW_DCODE_AUTO_APPROVAL
[ -n "${NEMOCLAW_REASONING_EFFORT:-}" ] && export NEMOCLAW_REASONING_EFFORT

# Alternative inference provider keys
[ -n "${OPENAI_API_KEY:-}" ] && export OPENAI_API_KEY
[ -n "${ANTHROPIC_API_KEY:-}" ] && export ANTHROPIC_API_KEY

# Messaging integrations
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && export TELEGRAM_BOT_TOKEN
[ -n "${TELEGRAM_ALLOWED_IDS:-}" ] && export TELEGRAM_ALLOWED_IDS
[ -n "${TELEGRAM_REQUIRE_MENTION:-}" ] && export TELEGRAM_REQUIRE_MENTION
[ -n "${TELEGRAM_GROUP_POLICY:-}" ] && export TELEGRAM_GROUP_POLICY
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
if [ -d "$NEMOCLAW_SOURCE_DIR/.git" ]; then
  echo "  NemoClaw exists, pulling latest..."
  git -C "$NEMOCLAW_SOURCE_DIR" checkout -- Dockerfile Dockerfile.base package-lock.json nemoclaw-blueprint/policies/openclaw-sandbox.yaml scripts/nemoclaw-start.sh 2>/dev/null || true
  git -C "$NEMOCLAW_SOURCE_DIR" pull --ff-only || echo "  Warning: pull failed, continuing with existing checkout"
else
  git clone https://github.com/NVIDIA/NemoClaw "$NEMOCLAW_SOURCE_DIR"
fi
normalize_nemoclaw_source_modes

echo "=== Step 2: Install OpenShell via upstream NemoClaw ==="
cd "$NEMOCLAW_SOURCE_DIR"
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
cd "$NEMOCLAW_SOURCE_DIR"
git checkout -- Dockerfile Dockerfile.base package-lock.json nemoclaw-blueprint/policies/openclaw-sandbox.yaml scripts/nemoclaw-start.sh 2>/dev/null || true
normalize_nemoclaw_source_modes

"${SCRIPT_DIR}/scripts/apply-patches.sh" "$NEMOCLAW_SOURCE_DIR"

# If a sandbox already exists, check if it's current. The manifest records the
# NemoClaw commit the image was built from. If upstream moved, force a rebuild
# so the new patches take effect.
if [ -f "$HOME/.nemoclaw/cookbook-deployment.json" ]; then
  CURRENT_NC=$(git -C "$NEMOCLAW_SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
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
cd "$NEMOCLAW_SOURCE_DIR"
bash install.sh --non-interactive
# shellcheck source=/dev/null
source "$HOME/.bashrc" 2>/dev/null || true

# ── Post-deploy ──────────────────────────────────────────────────────
# Core deploy (Steps 1-5) is complete. The remaining steps are individually
# fault-tolerant so critical work (URL extraction, port forward) always
# runs even if an earlier post-deploy step fails.
set +e
POST_FAILURES=0

SANDBOX="$(cookbook_discover_sandbox "$NEMOCLAW_SANDBOX_NAME")"
if ! cookbook_load_runtime "$SANDBOX"; then
  echo "  ERROR: could not read runtime status for '$SANDBOX'."
  exit 1
fi
if [ "$COOKBOOK_AGENT" != "$ACTIVE_AGENT" ]; then
  echo "  ERROR: requested agent '$ACTIVE_AGENT' but '$SANDBOX' runs '$COOKBOOK_AGENT'."
  exit 1
fi

# Upstream recreate currently drops the stored Telegram group policy and the
# rebuilt OpenClaw config falls back to `open`. Reapply only the explicit,
# upstream-supported policy value from ~/.env until NemoClaw preserves it.
if [ "$COOKBOOK_AGENT" = "openclaw" ] && [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_GROUP_POLICY:-}" ]; then
  case "$TELEGRAM_GROUP_POLICY" in
    open|allowlist|disabled)
      if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR -o ConnectTimeout=10 \
          -o "ProxyCommand=${HOME}/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name ${SANDBOX}" \
          "sandbox@openshell-${SANDBOX}" \
          "openclaw config set channels.telegram.groupPolicy ${TELEGRAM_GROUP_POLICY} >/dev/null && openclaw gateway restart >/dev/null 2>&1" \
          2>/dev/null; then
        echo "  Applied upstream OpenClaw Telegram group policy."
      else
        echo "  Warning: failed to apply Telegram group policy after rebuild."
        POST_FAILURES=$((POST_FAILURES + 1))
      fi
      ;;
    *)
      echo "  Warning: TELEGRAM_GROUP_POLICY must be open, allowlist, or disabled."
      POST_FAILURES=$((POST_FAILURES + 1))
      ;;
  esac
fi

echo "=== Step 5: Install services (nginx, systemd, terminal server) ==="
if "${SCRIPT_DIR}/scripts/install-services.sh" --sandbox "$SANDBOX"; then
  # CHAT_UI_URL may now be set by install-services.sh (cloudflared FQDN detection)
  [ -n "${CHAT_UI_URL:-}" ] && export CHAT_UI_URL
else
  echo "  Warning: service installation had errors (continuing)"
  POST_FAILURES=$((POST_FAILURES + 1))
fi

echo "=== Step 6: Save tokenized UI URL ==="
# Token is available as soon as the sandbox is running.
# Extract it now, before optional steps, so the URL file exists ASAP.
"${SCRIPT_DIR}/scripts/save-ui-url.sh" "$SANDBOX" || {
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
if [ "$COOKBOOK_RUNTIME" = "gateway" ] && [ -n "$COOKBOOK_DASHBOARD_PORT" ]; then
  if ! curl -sf --max-time 3 -o /dev/null "http://127.0.0.1:${COOKBOOK_DASHBOARD_PORT}/" 2>/dev/null; then
    echo "  Dashboard forward is not healthy; asking upstream NemoClaw to recover it."
    nemoclaw "$SANDBOX" recover 2>/dev/null || true
  fi
else
  echo "  $COOKBOOK_AGENT_DISPLAY is terminal-only — no dashboard forward to refresh."
fi

# Messaging channels are configured by upstream onboard/rebuild. `nemoclaw
# tunnel start` is only needed for an optional Cloudflare tunnel, not for the
# host-side channel registry itself.
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] && [ "$COOKBOOK_RUNTIME" = "gateway" ]; then
  nemoclaw tunnel start || {
    echo "  Warning: failed to start Cloudflare tunnel"
    POST_FAILURES=$((POST_FAILURES + 1))
  }
else
  echo "  No applicable dashboard tunnel requested — skipping optional cloudflared tunnel."
fi

echo "=== Step 8: Write deployment manifest ==="
"${SCRIPT_DIR}/scripts/write-manifest.sh" "$SANDBOX" || {
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
if [ "$COOKBOOK_RUNTIME" = "gateway" ] && [ -f "$HOME/nemoclaw-tunnel-url.txt" ]; then
  echo "Web UI: ~/nemoclaw-tunnel-url.txt"
  echo "  Pass the saved URL directly to a browser — do not print it."
elif [ "$COOKBOOK_RUNTIME" = "gateway" ]; then
  echo "Web UI: forward host port ${COOKBOOK_DASHBOARD_PORT}, then use ~/nemoclaw-ui-url.txt."
else
  echo "Web UI: not applicable ($COOKBOOK_AGENT_DISPLAY is a terminal runtime)."
fi
if [ -f "$HOME/nemoclaw-terminal-url.txt" ]; then
  echo "Browser terminal: ~/nemoclaw-terminal-url.txt"
fi
echo ""
echo "Next steps:"
echo "  Open the Web UI above, or run:"
echo "     nemoclaw ${SANDBOX} connect"
echo ""
echo "See USE.md for day-to-day commands."
