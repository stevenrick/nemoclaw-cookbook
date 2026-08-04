#!/usr/bin/env bash
# Install the cookbook's host-side services: nginx reverse proxy and the
# optional terminal WebSocket server. Removes any `openshell-gateway.service`
# unit it finds — the cookbook does not manage the OpenShell gateway
# lifecycle (upstream `nemoclaw` does; run `nemoclaw <sandbox> recover` if
# the gateway is down).
#
# Called by setup.sh after NemoClaw is installed. Safe to run manually.
#
# Requires: sudo (for nginx and systemd unit installation).
# Idempotent: safe to re-run.
#
# Usage: ./scripts/install-services.sh [--nginx-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"

NGINX_ONLY=0
if [ "${1:-}" = "--nginx-only" ]; then
  NGINX_ONLY=1
  shift
fi
if [ "$#" -gt 0 ]; then
  echo "Usage: $0 [--nginx-only]" >&2
  exit 1
fi

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

TUNNEL_FQDN="${TUNNEL_FQDN:-}"
TUNNEL_FQDN="${TUNNEL_FQDN#https://}"
TUNNEL_FQDN="${TUNNEL_FQDN#http://}"

OPENAI_HTTP_TUNNEL_ENABLED=0
case "${NEMOCLAW_OPENAI_HTTP_TUNNEL:-}" in
  1|true) OPENAI_HTTP_TUNNEL_ENABLED=1 ;;
esac

# OpenAI HTTP API exposure: loopback-only by default. Tunnel exposure requires
# Cloudflare Access service-token headers in addition to the API bearer.
if [ "$OPENAI_HTTP_TUNNEL_ENABLED" = "1" ]; then
  OPENAI_HTTP_DENY=""
else
  OPENAI_HTTP_DENY="deny all;"
fi
OPENAI_HTTP_EDGE_AUTH=""
OPENAI_HTTP_ACCESS_AUTH=""
OPENAI_HTTP_AUTH_CHECK="return 404;"
OPENAI_HTTP_EXTERNAL_AUTH_CHECK=""
OPENAI_HTTP_UPSTREAM_AUTH=""
case "${NEMOCLAW_OPENAI_HTTP_ENABLED:-}" in
  1|true)
    OPENAI_EDGE_TOKEN_FILE="$HOME/.nemoclaw/openai-http-edge-token"
    OPENAI_GATEWAY_TOKEN_FILE="$HOME/.nemoclaw/openai-http-gateway-token"
    OPENAI_EDGE_TOKEN=""
    OPENAI_GATEWAY_TOKEN=""
    [ -f "$OPENAI_EDGE_TOKEN_FILE" ] && OPENAI_EDGE_TOKEN="$(sed -n '1p' "$OPENAI_EDGE_TOKEN_FILE")"
    [ -f "$OPENAI_GATEWAY_TOKEN_FILE" ] && OPENAI_GATEWAY_TOKEN="$(sed -n '1p' "$OPENAI_GATEWAY_TOKEN_FILE")"
    OPENAI_ACCESS_CLIENT_ID="${NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_ID:-}"
    OPENAI_ACCESS_CLIENT_SECRET="${NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_SECRET:-}"

    case "$OPENAI_EDGE_TOKEN" in
      ""|*[!A-Za-z0-9._~+=/-]*)
        echo "  ⚠ OpenAI HTTP edge token missing or invalid; /v1/* will return 503 until save-ui-url.sh runs"
        OPENAI_HTTP_AUTH_CHECK="return 503;"
        ;;
      *)
        case "$OPENAI_GATEWAY_TOKEN" in
          ""|*[!A-Za-z0-9._~+=/-]*)
            echo "  ⚠ OpenAI HTTP gateway token missing or invalid; /v1/* will return 503 until save-ui-url.sh runs"
            OPENAI_HTTP_AUTH_CHECK="return 503;"
            ;;
          *)
            OPENAI_HTTP_EDGE_AUTH="\"Bearer ${OPENAI_EDGE_TOKEN}\" 1;"
            OPENAI_HTTP_AUTH_CHECK="if (\$openai_edge_authorized = 0) { return 403; }"
            OPENAI_HTTP_UPSTREAM_AUTH="proxy_set_header Authorization \"Bearer ${OPENAI_GATEWAY_TOKEN}\";"
            if [ "$OPENAI_HTTP_TUNNEL_ENABLED" = "1" ]; then
              case "$OPENAI_ACCESS_CLIENT_ID" in
                ""|*[!A-Za-z0-9._~+=/-]*)
                  echo "  ⚠ OpenAI HTTP tunnel exposure requires NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_ID and NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_SECRET; /v1/* will return 503 for non-loopback callers"
                  OPENAI_HTTP_EXTERNAL_AUTH_CHECK="if (\$openai_external_authorized = 0) { return 503; }"
                  ;;
                *)
                  case "$OPENAI_ACCESS_CLIENT_SECRET" in
                    ""|*[!A-Za-z0-9._~+=/-]*)
                      echo "  ⚠ OpenAI HTTP tunnel exposure requires NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_ID and NEMOCLAW_OPENAI_HTTP_ACCESS_CLIENT_SECRET; /v1/* will return 503 for non-loopback callers"
                      OPENAI_HTTP_EXTERNAL_AUTH_CHECK="if (\$openai_external_authorized = 0) { return 503; }"
                      ;;
                    *)
                      OPENAI_HTTP_ACCESS_AUTH="\"${OPENAI_ACCESS_CLIENT_ID}:${OPENAI_ACCESS_CLIENT_SECRET}\" 1;"
                      OPENAI_HTTP_EXTERNAL_AUTH_CHECK="if (\$openai_external_authorized = 0) { return 403; }"
                      ;;
                  esac
                  ;;
              esac
            fi
            ;;
        esac
        ;;
    esac
    ;;
esac
OPENAI_HTTP_CORS_ORIGIN=""
if [ -n "$TUNNEL_FQDN" ]; then
  case "$TUNNEL_FQDN" in
    *[!A-Za-z0-9._:-]*)
      echo "ERROR: TUNNEL_FQDN contains unsupported characters for nginx CORS config: $TUNNEL_FQDN"
      exit 1
      ;;
  esac
  # shellcheck disable=SC2016
  TUNNEL_FQDN_REGEX="$(printf '%s' "$TUNNEL_FQDN" | sed 's/[.[\*^$()+?{}|\\]/\\&/g')"
  OPENAI_HTTP_CORS_ORIGIN="\"~^https://${TUNNEL_FQDN_REGEX}$\" \$http_origin;"
fi
NGINX_LISTEN_ADDR="${NEMOCLAW_NGINX_LISTEN_ADDR:-127.0.0.1}"
case "$NGINX_LISTEN_ADDR" in
  127.0.0.1|0.0.0.0) ;;
  *)
    echo "ERROR: NEMOCLAW_NGINX_LISTEN_ADDR must be 127.0.0.1 or 0.0.0.0"
    exit 1
    ;;
esac
sed -e "s|__COOKBOOK_DIR__|$COOKBOOK_DIR|g" \
    -e "s|__OPENAI_HTTP_DENY__|$OPENAI_HTTP_DENY|g" \
    -e "s|__OPENAI_HTTP_CORS_ORIGIN__|$OPENAI_HTTP_CORS_ORIGIN|g" \
    -e "s|__OPENAI_HTTP_EDGE_AUTH__|$OPENAI_HTTP_EDGE_AUTH|g" \
    -e "s|__OPENAI_HTTP_ACCESS_AUTH__|$OPENAI_HTTP_ACCESS_AUTH|g" \
    -e "s|__OPENAI_HTTP_AUTH_CHECK__|$OPENAI_HTTP_AUTH_CHECK|g" \
    -e "s|__OPENAI_HTTP_EXTERNAL_AUTH_CHECK__|$OPENAI_HTTP_EXTERNAL_AUTH_CHECK|g" \
    -e "s|__OPENAI_HTTP_UPSTREAM_AUTH__|$OPENAI_HTTP_UPSTREAM_AUTH|g" \
    -e "s|__NGINX_LISTEN_ADDR__|$NGINX_LISTEN_ADDR|g" \
    "$COOKBOOK_DIR/config/nginx.conf.template" \
  | sudo tee /etc/nginx/sites-available/nemoclaw > /dev/null
sudo ln -sf /etc/nginx/sites-available/nemoclaw /etc/nginx/sites-enabled/nemoclaw
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t 2>/dev/null
sudo systemctl restart nginx 2>/dev/null || sudo systemctl start nginx
echo "  ✓ nginx configured"

if [ "$NGINX_ONLY" = "1" ]; then
  echo "=== Services installed ==="
  exit 0
fi

# ── 3. Terminal WebSocket server (optional) ──────────────────────────
if [ "$ENABLE_TERMINAL_SERVER" = "true" ]; then
  echo "  Installing terminal WebSocket server..."

  # Ensure build tools for node-pty
  if ! dpkg -s build-essential python3 >/dev/null 2>&1; then
    sudo apt-get install -y -qq build-essential python3 >/dev/null 2>&1
  fi

  cd "$COOKBOOK_DIR/terminal-server"
  if [ -f package-lock.json ]; then
    npm ci --omit=dev --quiet 2>/dev/null
  else
    npm install --quiet 2>/dev/null
  fi
  cd "$COOKBOOK_DIR"

  sed -e "s|__COOKBOOK_DIR__|$COOKBOOK_DIR|g" \
    "$COOKBOOK_DIR/config/systemd/nemoclaw-terminal.service" \
    | sudo tee /etc/systemd/system/nemoclaw-terminal.service > /dev/null
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
if [ -n "$TUNNEL_FQDN" ]; then
  export CHAT_UI_URL="https://$TUNNEL_FQDN"
  echo "  ✓ Access mode: Secure Link (FQDN)"
  echo "  ✓ nginx listen address: $NGINX_LISTEN_ADDR"
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
