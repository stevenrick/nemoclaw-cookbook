#!/usr/bin/env bash
# Verify a NemoClaw deployment is fully operational.
# Run on the Brev instance (not locally).
#
# Usage: verify-deployment.sh [sandbox-name]
#
# Checks: sandbox ready, OpenClaw running, dashboard reachable, services running
# (if configured), workspace files present, and cookbook integrations.
#
# Exit code 0 = all checks passed, 1 = failures found.
set -uo pipefail

export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"

# Discover sandbox name
SANDBOX="${1:-$(nemoclaw list 2>/dev/null | awk '/\*/{print $1}' | head -1)}"
if [ -z "$SANDBOX" ]; then
  echo "  ✗ No sandbox found"
  exit 1
fi

FAILED=0
WARNINGS=0

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }
warn() { echo "  ⚠ $1"; WARNINGS=$((WARNINGS + 1)); }

echo "Verifying deployment (sandbox: $SANDBOX)..."
echo ""

# ── 1. Gateway health ────────────────────────────────────────────────
echo "Gateway:"
if openshell status 2>&1 | grep -q "Connected"; then
  pass "OpenShell gateway connected"
else
  fail "OpenShell gateway not connected"
fi

# ── 2. Sandbox status ────────────────────────────────────────────────
echo "Sandbox:"
SANDBOX_PHASE=$(openshell sandbox get "$SANDBOX" 2>/dev/null | grep -i phase | awk '{print $NF}')
if [ "$SANDBOX_PHASE" = "Ready" ]; then
  pass "Sandbox '$SANDBOX' is Ready"
else
  fail "Sandbox '$SANDBOX' phase: ${SANDBOX_PHASE:-unknown}"
fi

# ── 3. Dashboard / Web UI reachable ──────────────────────────────────
echo "Dashboard:"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:18789/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "Web UI reachable on port 18789 (HTTP $HTTP_CODE)"
else
  fail "Web UI NOT reachable on port 18789 (HTTP $HTTP_CODE)"
  # Try to restart the forward
  echo "       Attempting to restart port forward..."
  openshell forward start 18789 "$SANDBOX" --background 2>/dev/null
  sleep 3
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:18789/ 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    pass "Web UI recovered after forward restart (HTTP $HTTP_CODE)"
    FAILED=$((FAILED - 1))
  else
    echo "       Forward restart did not help. May need manual intervention."
  fi
fi

# ── 4. OpenClaw running inside sandbox ───────────────────────────────
echo "OpenClaw:"
sandbox_ssh() {
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -o ConnectTimeout=10 \
    -o "ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name $SANDBOX" \
    "sandbox@openshell-$SANDBOX" "$@"
}

OPENCLAW_VER=$(sandbox_ssh 'openclaw --version 2>/dev/null' 2>/dev/null)
if [ -n "$OPENCLAW_VER" ]; then
  pass "OpenClaw $OPENCLAW_VER"
else
  fail "OpenClaw not responding inside sandbox"
fi

# shellcheck source=/dev/null
[ -f "$HOME/.env" ] && source "$HOME/.env"

# ── 5. Workspace files ──────────────────────────────────────────────
echo "Workspace:"
SOUL_EXISTS=$(sandbox_ssh 'test -f /sandbox/.openclaw/workspace/SOUL.md && echo yes || echo no' 2>/dev/null)
if [ "$SOUL_EXISTS" = "yes" ]; then
  pass "SOUL.md present (workspace populated)"
else
  warn "SOUL.md missing (fresh sandbox — no restore applied, or workspace empty)"
fi

# ── 6. Services ──────────────────────────────────────────────────────
echo "Services:"
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || [ -n "${DISCORD_BOT_TOKEN:-}" ] || [ -n "${SLACK_BOT_TOKEN:-}" ]; then
  # Two separate things must be true for messaging to actually work:
  #   1. Gateway provider exists (created during `nemoclaw onboard` when the token
  #      was in the environment — not just in ~/.env)
  #   2. Channel is configured in /sandbox/.openclaw/openclaw.json (baked at
  #      build time; empty means onboard didn't see the token)
  # "tokens in .env" is NOT sufficient — onboard has to read them at run time.
  SANDBOX_PROVIDERS=$(openshell provider list 2>/dev/null)
  CHANNEL_STATUS=$(sandbox_ssh 'openclaw channels list 2>/dev/null | grep -i "configured\|enabled\|ok"' 2>/dev/null)
  HOST_STATUS=$(nemoclaw status 2>/dev/null)

  expected_providers=""
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && expected_providers="${expected_providers} ${SANDBOX}-telegram-bridge"
  [ -n "${DISCORD_BOT_TOKEN:-}" ] && expected_providers="${expected_providers} ${SANDBOX}-discord-bridge"
  if [ -n "${SLACK_BOT_TOKEN:-}" ]; then
    expected_providers="${expected_providers} ${SANDBOX}-slack-bridge"
    if [ -n "${SLACK_APP_TOKEN:-}" ]; then
      expected_providers="${expected_providers} ${SANDBOX}-slack-app"
    else
      warn "SLACK_BOT_TOKEN set but SLACK_APP_TOKEN missing; upstream Slack Socket Mode requires both"
    fi
  fi
  missing_providers=""
  for p in $expected_providers; do
    echo "$SANDBOX_PROVIDERS" | grep -q "$p" || missing_providers="${missing_providers} ${p}"
  done

  if [ -n "$missing_providers" ]; then
    warn "Messaging tokens in .env but gateway provider(s) missing:${missing_providers}"
    warn "  Sandbox was built without these tokens. Export them and re-onboard (set -a; source ~/.env; set +a)."
  elif [ -n "$CHANNEL_STATUS" ]; then
    pass "Native messaging channels configured"
  elif echo "$HOST_STATUS" | grep -qi "running\|bridge"; then
    pass "Host messaging services running"
  else
    warn "Messaging providers exist but channels are not reporting configured (check 'openclaw channels list')"
  fi
  # Cloudflare tunnel is optional host access, not the messaging channel
  # registry itself. Only require it when the operator supplied a named tunnel.
  if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    if echo "$HOST_STATUS" | grep -qi "cloudflared"; then
      pass "Cloudflare tunnel running"
    else
      warn "CLOUDFLARE_TUNNEL_TOKEN set but cloudflared not detected (run 'nemoclaw tunnel start')"
    fi
  else
    pass "No Cloudflare named tunnel configured"
  fi
else
  pass "No messaging tokens configured (services not needed)"
fi

# ── 7. Infrastructure services ──────────────────────────────────────
echo "Infrastructure:"
# nginx
if systemctl is-active --quiet nginx 2>/dev/null; then
  NGINX_HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:80/ 2>/dev/null || echo "000")
  if [ "$NGINX_HTTP" = "200" ]; then
    pass "nginx proxy active (port 80 → 18789)"
  else
    warn "nginx running but proxy returning HTTP $NGINX_HTTP"
  fi
else
  warn "nginx not running (install with: ~/nemoclaw-cookbook/scripts/install-services.sh)"
fi

# Terminal server
ENABLE_TERMINAL_SERVER="${ENABLE_TERMINAL_SERVER:-true}"
if [ "$ENABLE_TERMINAL_SERVER" = "true" ]; then
  if systemctl is-active --quiet nemoclaw-terminal 2>/dev/null; then
    pass "Terminal WebSocket server running"
  else
    warn "Terminal server enabled but not running (check: systemctl status nemoclaw-terminal)"
  fi
fi

# Tunnel / access mode
TUNNEL_FQDN="${TUNNEL_FQDN:-}"
TUNNEL_FQDN="${TUNNEL_FQDN#https://}"
TUNNEL_FQDN="${TUNNEL_FQDN#http://}"
if [ -n "$TUNNEL_FQDN" ]; then
  if [ -f "$HOME/openclaw-tunnel-url.txt" ]; then
    pass "Secure Link configured ($TUNNEL_FQDN)"
  else
    warn "TUNNEL_FQDN set but tokenized URL not saved (run save-ui-url.sh)"
  fi
else
  pass "Access mode: port-forward (no TUNNEL_FQDN set)"
fi

# OpenAI HTTP API (if enabled)
OPENAI_FLAG="${NEMOCLAW_OPENAI_HTTP_ENABLED:-}"
if [ "$OPENAI_FLAG" = "1" ] || [ "$OPENAI_FLAG" = "true" ]; then
  if [ -f "$HOME/openclaw-openai.env" ]; then
    # shellcheck source=/dev/null
    . "$HOME/openclaw-openai.env"
    OPENAI_VERIFY_TMP=$(mktemp)
    HTTP_CODE=$(curl -s -o "$OPENAI_VERIFY_TMP" -w '%{http_code}' --max-time 5 \
      -H "Authorization: Bearer ${OPENAI_API_KEY}" \
      "${OPENAI_BASE_URL}/models" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] && grep -q '"data"' "$OPENAI_VERIFY_TMP" 2>/dev/null; then
      pass "OpenAI HTTP API reachable ($OPENAI_BASE_URL/models → 200)"
    else
      fail "OpenAI HTTP API check failed ($OPENAI_BASE_URL/models → HTTP $HTTP_CODE)"
      echo "       Response: $(head -c 200 "$OPENAI_VERIFY_TMP")"
    fi
    rm -f "$OPENAI_VERIFY_TMP"
  else
    fail "NEMOCLAW_OPENAI_HTTP_ENABLED=1 but ~/openclaw-openai.env missing (save-ui-url.sh skipped?)"
  fi
fi

# ── 8. Deployment manifest ──────────────────────────────────────────
echo "Manifest:"
if [ -f "$HOME/.nemoclaw/cookbook-deployment.json" ]; then
  MANIFEST_NC=$(python3 -c "import json; print(json.load(open('$HOME/.nemoclaw/cookbook-deployment.json')).get('nemoclaw_commit',''))" 2>/dev/null)
  ACTUAL_NC=$(git -C "$HOME/NemoClaw" rev-parse --short HEAD 2>/dev/null)
  if [ "$MANIFEST_NC" = "$ACTUAL_NC" ]; then
    pass "Manifest matches running state ($ACTUAL_NC)"
  else
    warn "Manifest drift: manifest=$MANIFEST_NC actual=$ACTUAL_NC (run write-manifest.sh)"
  fi
else
  warn "No deployment manifest found (run write-manifest.sh)"
fi

# ── 9. Integration checks ───────────────────────────────────────────
# shellcheck source=/dev/null
[ -f "$HOME/.env" ] && source "$HOME/.env"

echo "Integrations:"

# Web search
WEB_SEARCH_PROVIDER="${NEMOCLAW_WEB_SEARCH_PROVIDER:-}"
if [ -z "$WEB_SEARCH_PROVIDER" ]; then
  if [ -n "${BRAVE_API_KEY:-}" ]; then
    WEB_SEARCH_PROVIDER="brave"
  elif [ -n "${TAVILY_API_KEY:-}" ]; then
    WEB_SEARCH_PROVIDER="tavily"
  fi
fi
if [ -n "$WEB_SEARCH_PROVIDER" ] && [ "$WEB_SEARCH_PROVIDER" != "none" ]; then
  pass "Web search configured by upstream NemoClaw ($WEB_SEARCH_PROVIDER)"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
if [ "$FAILED" -eq 0 ]; then
  if [ "$WARNINGS" -gt 0 ]; then
    echo "All checks passed ($WARNINGS warning(s))."
  else
    echo "All checks passed."
  fi
  exit 0
else
  echo "FAILED: $FAILED check(s) failed, $WARNINGS warning(s)."
  exit 1
fi
