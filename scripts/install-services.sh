#!/usr/bin/env bash
# Install systemd services, nginx reverse proxy, and optional terminal server.
# Called by setup.sh after NemoClaw is installed. Also called by /upgrade for
# migrations from pre-systemd deployments.
#
# Requires: sudo (for nginx, systemd unit installation)
# Idempotent: safe to run multiple times.
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

# ── 1. Install nginx if not present ──────────────────────────────────
if ! command -v nginx >/dev/null 2>&1; then
  echo "  Installing nginx..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq nginx >/dev/null 2>&1
  echo "  ✓ nginx installed"
else
  echo "  ✓ nginx already installed"
fi

# ── 2. Deploy nginx config ──────────────────────────────────────────
echo "  Deploying nginx config..."
sudo cp "$COOKBOOK_DIR/config/nginx.conf" /etc/nginx/sites-available/nemoclaw
sudo ln -sf /etc/nginx/sites-available/nemoclaw /etc/nginx/sites-enabled/nemoclaw
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t 2>/dev/null
sudo systemctl reload nginx 2>/dev/null || sudo systemctl start nginx
echo "  ✓ nginx configured"

# ── 3. Install systemd unit for OpenShell gateway ────────────────────
echo "  Installing OpenShell gateway systemd unit..."
sudo cp "$COOKBOOK_DIR/config/systemd/openshell-gateway.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable openshell-gateway 2>/dev/null
echo "  ✓ openshell-gateway.service installed"

# ── 4. Terminal WebSocket server (optional) ──────────────────────────
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

# ── 5. Configure access method (FQDN or port-forward) ───────────────
# If TUNNEL_FQDN is set in .env, the user has configured Brev Secure Links
# and wants to access the Web UI via that domain. Otherwise, the system uses
# brev port-forward (local access only).
TUNNEL_FQDN="${TUNNEL_FQDN:-}"

if [ -n "$TUNNEL_FQDN" ]; then
  export CHAT_UI_URL="https://$TUNNEL_FQDN"
  echo "  ✓ Access mode: Secure Link (FQDN)"
  echo "  ✓ CHAT_UI_URL=$CHAT_UI_URL"
  echo "https://$TUNNEL_FQDN" > "$HOME/openclaw-tunnel-url.txt"
else
  echo "  ✓ Access mode: port-forward (local)"
  echo "    To use a Secure Link instead, set TUNNEL_FQDN in ~/.env"
  echo "    and configure it in Brev (Settings → Secure Links)."
  rm -f "$HOME/openclaw-tunnel-url.txt"
fi

# ── 6. Start services ───────────────────────────────────────────────
echo "  Starting services..."

# Gateway should already be running from nemoclaw onboard, but ensure systemd tracks it
if systemctl is-active --quiet openshell-gateway 2>/dev/null; then
  echo "  ✓ openshell-gateway already running"
else
  # If gateway container exists (from nemoclaw onboard), adopt it
  if docker ps -q -f "name=openshell-cluster-nemoclaw" 2>/dev/null | grep -q .; then
    echo "  ✓ openshell-gateway container running (adopting into systemd)"
  else
    sudo systemctl start openshell-gateway
    echo "  ✓ openshell-gateway started"
  fi
fi

sudo systemctl start nginx
echo "  ✓ nginx started"

if [ "$ENABLE_TERMINAL_SERVER" = "true" ]; then
  sudo systemctl start nemoclaw-terminal
  echo "  ✓ terminal server started"
fi

echo "=== Services installed ==="
