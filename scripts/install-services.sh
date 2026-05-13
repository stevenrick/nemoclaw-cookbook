#!/usr/bin/env bash
# Install the cookbook's host-side services: nginx reverse proxy and the
# optional terminal WebSocket server. Removes any `openshell-gateway.service`
# unit it finds — the cookbook does not manage the OpenShell gateway
# lifecycle (upstream `nemoclaw` does; run `nemoclaw <sandbox> recover` if
# the gateway is down).
#
# Called by setup.sh after NemoClaw is installed. Also called by /upgrade.
#
# Requires: sudo (for nginx and systemd unit installation).
# Idempotent: safe to re-run.
#
# Usage: ./scripts/install-services.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"

# Source .env for optional flags
# shellcheck source=/dev/null
[ -f "$HOME/.env" ] && source "$HOME/.env"

ENABLE_TERMINAL_SERVER="${ENABLE_TERMINAL_SERVER:-true}"

export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"

echo "=== Installing services ==="

# ── 0. Remove openshell-gateway.service if present ──────────────────
# The cookbook does not manage the OpenShell gateway lifecycle — that
# belongs to upstream `nemoclaw`. Any `openshell-gateway.service` unit on
# the host is from a prior cookbook install and is removed so deployments
# converge on a single model.
if [ -f /etc/systemd/system/openshell-gateway.service ]; then
  echo "  Removing openshell-gateway.service (cookbook does not manage the gateway)..."
  sudo systemctl disable openshell-gateway 2>/dev/null || true
  sudo systemctl stop openshell-gateway 2>/dev/null || true
  sudo rm -f /etc/systemd/system/openshell-gateway.service
  sudo systemctl daemon-reload
  echo "  ✓ Unit removed"
fi

# ── 1. Install nginx if not present ──────────────────────────────────
if ! command -v nginx >/dev/null 2>&1; then
  echo "  Installing nginx..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq nginx >/dev/null 2>&1
  echo "  ✓ nginx installed"
else
  echo "  ✓ nginx already installed"
fi

# ── 2. Deploy nginx config (from template) ─────────────────────────
echo "  Deploying nginx config..."
sed "s|__COOKBOOK_DIR__|$COOKBOOK_DIR|g" "$COOKBOOK_DIR/config/nginx.conf.template" \
  | sudo tee /etc/nginx/sites-available/nemoclaw > /dev/null
sudo ln -sf /etc/nginx/sites-available/nemoclaw /etc/nginx/sites-enabled/nemoclaw
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t 2>/dev/null
sudo systemctl restart nginx 2>/dev/null || sudo systemctl start nginx
echo "  ✓ nginx configured"

# ── 3. Terminal WebSocket server (optional) ──────────────────────────
if [ "$ENABLE_TERMINAL_SERVER" = "true" ]; then
  echo "  Installing terminal WebSocket server..."

  # Ensure build tools for node-pty
  if ! dpkg -s build-essential python3 >/dev/null 2>&1; then
    sudo apt-get install -y -qq build-essential python3 >/dev/null 2>&1
  fi

  cd "$COOKBOOK_DIR/terminal-server"
  npm install --quiet 2>/dev/null
  cd "$COOKBOOK_DIR"

  sudo cp "$COOKBOOK_DIR/config/systemd/nemoclaw-terminal.service" /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable nemoclaw-terminal 2>/dev/null
  echo "  ✓ terminal server installed"
else
  echo "  ⊘ terminal server disabled (ENABLE_TERMINAL_SERVER=false)"
  # Disable if previously enabled
  sudo systemctl disable nemoclaw-terminal 2>/dev/null || true
  sudo systemctl stop nemoclaw-terminal 2>/dev/null || true
fi

# ── 4. Configure access method (FQDN or port-forward) ───────────────
# If TUNNEL_FQDN is set in .env, the user has configured Brev Secure Links
# and wants to access the Web UI via that domain. Otherwise, the system uses
# brev port-forward (local access only).
# Strip protocol prefix if user included it (e.g. https://foo.brevlab.com → foo.brevlab.com)
TUNNEL_FQDN="${TUNNEL_FQDN:-}"
TUNNEL_FQDN="${TUNNEL_FQDN#https://}"
TUNNEL_FQDN="${TUNNEL_FQDN#http://}"

if [ -n "$TUNNEL_FQDN" ]; then
  export CHAT_UI_URL="https://$TUNNEL_FQDN"
  echo "  ✓ Access mode: Secure Link (FQDN)"
  echo "  ✓ CHAT_UI_URL=$CHAT_UI_URL"
  # Tokenized tunnel URL is written by save-ui-url.sh (runs later in setup)
else
  echo "  ✓ Access mode: port-forward (local)"
  echo "    To use a Secure Link instead, set TUNNEL_FQDN in ~/.env"
  echo "    and configure it in Brev (Settings → Secure Links)."
fi

# ── 5. Start services ───────────────────────────────────────────────
# Gateway is started by `nemoclaw onboard` upstream; cookbook does not
# manage it (see header note). If the gateway is down after a host
# reboot or crash, run `nemoclaw <sandbox> recover`.
echo "  Starting services..."

sudo systemctl start nginx
echo "  ✓ nginx started"

if [ "$ENABLE_TERMINAL_SERVER" = "true" ]; then
  sudo systemctl start nemoclaw-terminal
  echo "  ✓ terminal server started"
fi

echo "=== Services installed ==="
