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
[ -n "${TELEGRAM_ALLOWED_IDS:-}" ] && export TELEGRAM_ALLOWED_IDS
[ -n "${DISCORD_BOT_TOKEN:-}" ] && export DISCORD_BOT_TOKEN
[ -n "${SLACK_BOT_TOKEN:-}" ] && export SLACK_BOT_TOKEN

# Tool integrations
[ -n "${BRAVE_API_KEY:-}" ] && export BRAVE_API_KEY
[ -n "${TAVILY_API_KEY:-}" ] && export TAVILY_API_KEY

# Optional sandbox tools (default: true for backward compatibility)
export INSTALL_CLAUDE_CODE="${INSTALL_CLAUDE_CODE:-true}"
export INSTALL_CODEX="${INSTALL_CODEX:-true}"

# Policy configuration
[ -n "${NEMOCLAW_POLICY_TIER:-}" ] && export NEMOCLAW_POLICY_TIER
[ -n "${NEMOCLAW_POLICY_MODE:-}" ] && export NEMOCLAW_POLICY_MODE
[ -n "${NEMOCLAW_POLICY_PRESETS:-}" ] && export NEMOCLAW_POLICY_PRESETS

# Upstream #1753 replaced credential-based preset auto-detection with a
# tier-based selector. The default `balanced` tier excludes messaging presets,
# so TELEGRAM_BOT_TOKEN et al. no longer wire up policy egress automatically.
# Derive presets from configured tokens unless the user has opted into their
# own tier/mode/presets choice.
if [ -z "${NEMOCLAW_POLICY_TIER:-}" ] \
   && [ -z "${NEMOCLAW_POLICY_MODE:-}" ] \
   && [ -z "${NEMOCLAW_POLICY_PRESETS:-}" ]; then
  PRESETS="npm,pypi,huggingface,brew"
  [ -n "${BRAVE_API_KEY:-}" ] && PRESETS="${PRESETS},brave"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && PRESETS="${PRESETS},telegram"
  [ -n "${DISCORD_BOT_TOKEN:-}" ] && PRESETS="${PRESETS},discord"
  [ -n "${SLACK_BOT_TOKEN:-}" ] && PRESETS="${PRESETS},slack"
  export NEMOCLAW_POLICY_PRESETS="${PRESETS}"
  echo "  Derived policy presets from configured credentials: ${PRESETS}"
fi

# ── Build integration config payload ─────────────────────────────────
build_integrations_config() {
  python3 -c "
import json, base64, os

config = {}

# --- Web search (Tavily) ---
# Brave search is handled by upstream nemoclaw onboard (NEMOCLAW_WEB_SEARCH_ENABLED).
# Tavily is not supported upstream, so we configure it here.
tavily_key = os.environ.get('TAVILY_API_KEY', '')
if tavily_key:
    config['plugins'] = {'entries': {'tavily': {'enabled': True}}}
    config['tools'] = {'web': {'search': {
        'enabled': True,
        'provider': 'tavily',
        'apiKey': 'openshell:resolve:env:TAVILY_API_KEY'
    }}}

print(base64.b64encode(json.dumps(config).encode()).decode())
"
}

NEMOCLAW_INTEGRATIONS_B64="$(build_integrations_config)"
export NEMOCLAW_INTEGRATIONS_B64

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
  git -C NemoClaw checkout -- Dockerfile Dockerfile.base nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null || true
  git -C NemoClaw pull --ff-only || echo "  Warning: pull failed, continuing with existing checkout"
else
  git clone https://github.com/NVIDIA/NemoClaw
fi

echo "=== Step 2: Install OpenShell ==="
# NemoClaw's blueprint declares the supported OpenShell version range.
# `sh install.sh` defaults to the latest release, which may be above NemoClaw's
# validated max and fail the onboard preflight. Derive the install version
# from `max_openshell_version` unless the user overrode it explicitly.
BLUEPRINT_YAML="$HOME/NemoClaw/nemoclaw-blueprint/blueprint.yaml"
if [ -z "${OPENSHELL_VERSION:-}" ] && [ -f "$BLUEPRINT_YAML" ]; then
  BLUEPRINT_MAX=$(awk -F'"' '/^max_openshell_version:/{print $2; exit}' "$BLUEPRINT_YAML")
  if [ -n "$BLUEPRINT_MAX" ]; then
    OPENSHELL_VERSION="v${BLUEPRINT_MAX}"
    export OPENSHELL_VERSION
    echo "  Pinned OpenShell to ${OPENSHELL_VERSION} (from blueprint max_openshell_version)"
  fi
fi
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
git checkout -- Dockerfile Dockerfile.base nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null || true

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

# ── Post-deploy ──────────────────────────────────────────────────────
# Core deploy (Steps 1-5) is complete. The remaining steps are individually
# fault-tolerant so critical work (URL extraction, port forward) always
# runs even if an earlier post-deploy step fails.
set +e
POST_FAILURES=0

SANDBOX=$(nemoclaw list 2>/dev/null | awk '/\*/{print $1}' | head -1)
SANDBOX="${SANDBOX:-my-assistant}"

echo "=== Step 6: Install services (nginx, systemd, terminal server) ==="
if "${SCRIPT_DIR}/scripts/install-services.sh"; then
  # CHAT_UI_URL may now be set by install-services.sh (cloudflared FQDN detection)
  [ -n "${CHAT_UI_URL:-}" ] && export CHAT_UI_URL
else
  echo "  Warning: service installation had errors (continuing)"
  POST_FAILURES=$((POST_FAILURES + 1))
fi

echo "=== Step 7: Save tokenized UI URL ==="
# Token is available as soon as the sandbox is running (step 5).
# Extract it now, before optional steps, so the URL file exists ASAP.
"${SCRIPT_DIR}/scripts/save-ui-url.sh" || {
  echo "  Warning: URL extraction failed — retrieve manually (see BUILD.md)."
  POST_FAILURES=$((POST_FAILURES + 1))
}

echo "=== Step 8: Register integration providers ==="

register_provider() {
  local name="$1" envkey="$2"
  openshell provider create --name "$name" --type generic --credential "$envkey" 2>/dev/null \
    || openshell provider update "$name" --credential "$envkey" 2>/dev/null \
    || { echo "  Warning: could not configure $name provider"; return 1; }
  echo "    ✓ $name"
}

# Web search providers
if [ -n "${TAVILY_API_KEY:-}" ]; then
  register_provider "${SANDBOX}-tavily" "TAVILY_API_KEY"
elif [ -n "${BRAVE_API_KEY:-}" ]; then
  register_provider "${SANDBOX}-brave-search" "BRAVE_API_KEY"
fi

# Inject integration API keys into the sandbox workspace .env.
# OpenClaw loads /sandbox/.env on startup (via dotenv from process.cwd()).
# This is the only way to get keys to plugins that read process.env (e.g. Tavily).
SANDBOX_ENV_LINES=""
[ -n "${TAVILY_API_KEY:-}" ] && SANDBOX_ENV_LINES="${SANDBOX_ENV_LINES}TAVILY_API_KEY=${TAVILY_API_KEY}\n"
[ -n "${BRAVE_API_KEY:-}" ] && SANDBOX_ENV_LINES="${SANDBOX_ENV_LINES}BRAVE_API_KEY=${BRAVE_API_KEY}\n"
if [ -n "$SANDBOX_ENV_LINES" ]; then
  echo "  Injecting integration keys into sandbox workspace..."
  if printf "%b" "$SANDBOX_ENV_LINES" | openshell sandbox exec --name "$SANDBOX" -- \
    sh -c 'cat > /sandbox/.env' 2>/dev/null; then
    echo "  ✓ Sandbox .env written"
  else
    echo "  Warning: failed to write sandbox .env"
    POST_FAILURES=$((POST_FAILURES + 1))
  fi
fi

echo "=== Step 9: Start services ==="
# Reload env to pick up nvm
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Bounce the port forward — stale forwards from previous sandbox cause 502s.
# Stop first (may fail if none exists), then start fresh.
if [ -n "$SANDBOX" ]; then
  openshell forward stop 18789 "$SANDBOX" 2>/dev/null || true
  sleep 1
  openshell forward start 18789 "$SANDBOX" --background 2>/dev/null || true
fi

# Start messaging bridges if tokens are configured
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || [ -n "${DISCORD_BOT_TOKEN:-}" ] || [ -n "${SLACK_BOT_TOKEN:-}" ]; then
  nemoclaw tunnel start || {
    echo "  Warning: failed to start messaging bridges"
    POST_FAILURES=$((POST_FAILURES + 1))
  }
else
  echo "  No messaging tokens set — skipping bridges."
fi

echo "=== Step 10: Write deployment manifest ==="
"${SCRIPT_DIR}/scripts/write-manifest.sh" || {
  echo "  Warning: manifest write failed"
  POST_FAILURES=$((POST_FAILURES + 1))
}

echo "=== Step 11: Verify deployment ==="
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
  TUNNEL_URL=$(cat "$HOME/openclaw-tunnel-url.txt")
  echo "Web UI: $TUNNEL_URL"
  echo "  Open in your browser — no port forwarding needed."
else
  echo "Web UI: brev port-forward <instance> -p 18789:18789"
  echo "  Then open: cat ~/openclaw-ui-url.txt"
  echo ""
  echo "  To use a Secure Link instead (no port-forward):"
  echo "    1. Go to Brev Settings → Secure Links → add port 80"
  echo "    2. Set TUNNEL_FQDN=<your-link> in ~/.env"
  echo "    3. Re-run setup.sh (or /upgrade)"
fi
echo ""
echo "Next steps:"
if [ "$INSTALL_CODEX" = "true" ]; then
  echo "  1. Authenticate Codex (can be scripted via brev exec):"
  echo "     codex login --device-auth"
fi
if [ "$INSTALL_CLAUDE_CODE" = "true" ]; then
  echo "  2. Authenticate Claude Code (interactive via brev shell):"
  echo "     brev shell <instance> → nemoclaw my-assistant connect → claude"
fi
echo ""
echo "See USE.md for day-to-day commands."
