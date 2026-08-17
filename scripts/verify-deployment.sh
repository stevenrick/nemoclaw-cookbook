#!/usr/bin/env bash
# Read-only deployment verification for every upstream NemoClaw agent runtime.
# Usage: verify-deployment.sh [sandbox-name]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/agent-runtime.sh
source "$SCRIPT_DIR/lib/agent-runtime.sh"

export PATH="$HOME/.local/bin:$PATH"
# shellcheck source=/dev/null
[ -f "$HOME/.env" ] && source "$HOME/.env"

SANDBOX="$(cookbook_discover_sandbox "${1:-}")"
if [ -z "$SANDBOX" ] || ! cookbook_load_runtime "$SANDBOX"; then
  echo "  ✗ No readable registered sandbox found"
  exit 1
fi

FAILED=0
WARNINGS=0
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }
warn() { echo "  ⚠ $1"; WARNINGS=$((WARNINGS + 1)); }

echo "Verifying deployment (sandbox: $SANDBOX, agent: $COOKBOOK_AGENT_DISPLAY)..."
echo ""

echo "Control plane:"
if openshell status 2>&1 | grep -q "Connected"; then
  pass "OpenShell gateway connected"
else
  fail "OpenShell gateway not connected"
fi
if [ "$COOKBOOK_PHASE" = "Ready" ]; then
  pass "Sandbox is Ready"
else
  fail "Sandbox phase is ${COOKBOOK_PHASE:-unknown}"
fi
if [ "$COOKBOOK_INFERENCE_OK" = "true" ]; then
  pass "Inference route health passed"
else
  fail "Inference route health did not pass"
fi
if [ "$COOKBOOK_RUNTIME" = "terminal" ]; then
  if [ "$COOKBOOK_TERMINAL_HEALTH" = "ok" ]; then
    pass "Terminal runtime health passed"
  else
    fail "Terminal runtime health is ${COOKBOOK_TERMINAL_HEALTH:-unknown}"
  fi
fi

echo "Agent runtime:"
AGENT_COMMAND="$(cookbook_agent_command "$COOKBOOK_AGENT" || true)"
if [ -n "$AGENT_COMMAND" ] && nemoclaw "$SANDBOX" exec -- "$AGENT_COMMAND" --version >/dev/null 2>&1; then
  pass "$COOKBOOK_AGENT_DISPLAY CLI responds"
else
  fail "$COOKBOOK_AGENT_DISPLAY CLI does not respond"
fi
SKILL_ROOT="$(cookbook_skill_root "$COOKBOOK_AGENT" || true)"
if [ -n "$SKILL_ROOT" ] && nemoclaw "$SANDBOX" exec -- test -d "$SKILL_ROOT" >/dev/null 2>&1; then
  pass "Agent skill root exists ($SKILL_ROOT)"
else
  warn "Agent skill root is not initialized yet"
fi
if nemoclaw "$SANDBOX" snapshot list >/dev/null 2>&1; then
  pass "Agent-aware snapshot interface responds"
else
  fail "Agent-aware snapshot interface failed"
fi

echo "Access surfaces:"
if [ "$COOKBOOK_RUNTIME" = "gateway" ]; then
  DASHBOARD_URL="$(cookbook_dashboard_url "$SANDBOX")"
  if [ -z "$DASHBOARD_URL" ] || [ -z "$COOKBOOK_DASHBOARD_PORT" ]; then
    fail "Gateway runtime did not expose a dashboard URL and port"
  else
    HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
      "http://127.0.0.1:${COOKBOOK_DASHBOARD_PORT}/" 2>/dev/null || printf '000')"
    if [ "$HTTP_CODE" = "200" ]; then
      pass "Dashboard reachable on allocated port $COOKBOOK_DASHBOARD_PORT"
    else
      fail "Dashboard returned HTTP $HTTP_CODE on allocated port $COOKBOOK_DASHBOARD_PORT"
    fi
  fi
else
  pass "Dashboard correctly not applicable to terminal runtime"
fi

if [ "$COOKBOOK_AGENT" = "hermes" ]; then
  HERMES_TOKEN="$(nemoclaw "$SANDBOX" gateway-token --quiet 2>/dev/null | cookbook_last_nonempty_line)"
  if [ -n "$HERMES_TOKEN" ] && [ -n "$COOKBOOK_HERMES_API_PORT" ]; then
    HERMES_API_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
      -H "Authorization: Bearer ${HERMES_TOKEN}" \
      "http://127.0.0.1:${COOKBOOK_HERMES_API_PORT}/v1/models" 2>/dev/null || printf '000')"
    if [ "$HERMES_API_CODE" = "200" ]; then
      pass "Hermes native OpenAI-compatible API reachable"
    else
      fail "Hermes native API returned HTTP $HERMES_API_CODE"
    fi
  else
    fail "Hermes API token or allocated port unavailable"
  fi
fi

echo "Host services:"
if systemctl is-active --quiet nginx 2>/dev/null; then
  NGINX_HEADERS="$(mktemp)"
  NGINX_HTTP="$(curl -s -D "$NGINX_HEADERS" -o /dev/null -w '%{http_code}' --max-time 3 \
    http://127.0.0.1:80/ 2>/dev/null || printf '000')"
  if [ "$COOKBOOK_RUNTIME" = "gateway" ] \
      && [ "$NGINX_HTTP" = "200" ] \
      && grep -qF "proxy_pass http://127.0.0.1:${COOKBOOK_DASHBOARD_PORT};" \
        /etc/nginx/sites-enabled/nemoclaw 2>/dev/null; then
    pass "nginx proxies the selected dashboard"
  elif [ "$COOKBOOK_RUNTIME" = "terminal" ] \
      && printf '%s' "$NGINX_HTTP" | grep -Eq '^30[1278]$' \
      && grep -Eqi '^Location: (https?://[^/]+)?/terminal/?' "$NGINX_HEADERS"; then
    pass "nginx redirects terminal runtime to /terminal"
  else
    warn "nginx is active but its root route does not match the selected runtime (HTTP $NGINX_HTTP)"
  fi
  rm -f "$NGINX_HEADERS"
else
  warn "nginx not running"
fi

if [ "${ENABLE_TERMINAL_SERVER:-true}" = "true" ]; then
  if systemctl is-active --quiet nemoclaw-terminal 2>/dev/null; then
    pass "Agent-aware browser terminal service running"
  else
    warn "Browser terminal enabled but service is not running"
  fi
fi
if [ -n "${TUNNEL_FQDN:-}" ]; then
  if [ "$COOKBOOK_RUNTIME" = "gateway" ] && [ -f "$HOME/nemoclaw-tunnel-url.txt" ]; then
    pass "Secure Link dashboard access file present"
  elif [ "$COOKBOOK_RUNTIME" = "terminal" ] && [ -f "$HOME/nemoclaw-terminal-url.txt" ]; then
    pass "Secure Link browser-terminal access file present"
  else
    warn "Secure Link configured but its agent-appropriate access file is missing"
  fi
fi

if [ "$COOKBOOK_RUNTIME" = "terminal" ]; then
  if [ -e "$HOME/nemoclaw-ui-url.txt" ] \
      || [ -e "$HOME/nemoclaw-tunnel-url.txt" ] \
      || [ -e "$HOME/nemoclaw-openai.env" ]; then
    fail "Terminal-only runtime has stale generic dashboard or API access files"
  else
    pass "Terminal-only runtime has no stale dashboard or API access files"
  fi
fi

case "${NEMOCLAW_OPENAI_HTTP_ENABLED:-}" in
  1|true|yes)
    if [ "$COOKBOOK_AGENT" != "openclaw" ]; then
      pass "Ambient OpenClaw HTTP overlay is not applied to $COOKBOOK_AGENT_DISPLAY"
    elif [ -f "$HOME/nemoclaw-openai.env" ]; then
      # shellcheck source=/dev/null
      . "$HOME/nemoclaw-openai.env"
      OPENAI_HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        "${OPENAI_BASE_URL}/models" 2>/dev/null || printf '000')"
      if [ "$OPENAI_HTTP_CODE" = "200" ]; then
        pass "Cookbook OpenClaw HTTP API reachable"
      else
        fail "Cookbook OpenClaw HTTP API returned HTTP $OPENAI_HTTP_CODE"
      fi
    else
      fail "OpenClaw HTTP API enabled but ~/nemoclaw-openai.env is missing"
    fi
    ;;
esac

if [ -n "${TELEGRAM_BOT_TOKEN:-}${DISCORD_BOT_TOKEN:-}${SLACK_BOT_TOKEN:-}" ]; then
  CHANNEL_STATUS_TMP="$(mktemp)"
  if nemoclaw "$SANDBOX" channels status --json >"$CHANNEL_STATUS_TMP" 2>&1; then
    pass "Upstream messaging channel status passed"
  else
    warn "Configured messaging tokens did not produce a healthy upstream channel status"
  fi
  rm -f "$CHANNEL_STATUS_TMP"
else
  pass "No messaging tokens configured"
fi

echo "Manifest:"
if [ -f "$HOME/.nemoclaw/cookbook-deployment.json" ]; then
  MANIFEST_MATCH="$(SANDBOX_NAME="$SANDBOX" AGENT_NAME="$COOKBOOK_AGENT" python3 -c '
import json, os
try:
    data = json.load(open(os.path.expanduser("~/.nemoclaw/cookbook-deployment.json")))
except Exception:
    print("false")
else:
    print(str(data.get("sandbox_name") == os.environ["SANDBOX_NAME"] and data.get("agent") == os.environ["AGENT_NAME"]).lower())
' 2>/dev/null)"
  if [ "$MANIFEST_MATCH" = "true" ]; then
    pass "Manifest identifies the selected sandbox and agent"
  else
    warn "Manifest does not match the selected sandbox and agent"
  fi
else
  warn "No deployment manifest found"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  if [ "$WARNINGS" -gt 0 ]; then
    echo "All required checks passed ($WARNINGS warning(s))."
  else
    echo "All checks passed."
  fi
  exit 0
fi
echo "FAILED: $FAILED check(s) failed, $WARNINGS warning(s)."
exit 1
