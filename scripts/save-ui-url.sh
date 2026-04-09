#!/usr/bin/env bash
# Extract the gateway auth token from the running sandbox and write
# tokenized Web UI URLs to ~/openclaw-ui-url.txt (local) and
# ~/openclaw-tunnel-url.txt (Secure Link, if TUNNEL_FQDN is set).
#
# Usage: save-ui-url.sh [sandbox-name]
#
# The token lives in /sandbox/.openclaw/openclaw.json inside the sandbox.
# Falls back to parsing sandbox logs if the config download fails.
set -uo pipefail

export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"

# Source .env for TUNNEL_FQDN
# shellcheck source=/dev/null
[ -f "$HOME/.env" ] && source "$HOME/.env"
TUNNEL_FQDN="${TUNNEL_FQDN:-}"
TUNNEL_FQDN="${TUNNEL_FQDN#https://}"
TUNNEL_FQDN="${TUNNEL_FQDN#http://}"

SANDBOX="${1:-$(nemoclaw list 2>/dev/null | awk '/\*/{print $1}' | head -1)}"
if [ -z "$SANDBOX" ]; then
  echo "  ⚠ No active sandbox found — skipping URL extraction"
  exit 1
fi

write_urls() {
  local token="$1"
  echo "http://127.0.0.1:18789/#token=${token}" > "$HOME/openclaw-ui-url.txt"
  echo "  ✓ Local UI URL saved to ~/openclaw-ui-url.txt"

  if [ -n "$TUNNEL_FQDN" ]; then
    echo "https://${TUNNEL_FQDN}/#token=${token}" > "$HOME/openclaw-tunnel-url.txt"
    echo "  ✓ Tunnel UI URL saved to ~/openclaw-tunnel-url.txt"
  fi
}

TMPDIR_TOKEN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TOKEN"' EXIT

# Primary: download openclaw.json from sandbox and extract the token
if openshell sandbox download "$SANDBOX" /sandbox/.openclaw/openclaw.json "$TMPDIR_TOKEN" 2>/dev/null; then
  GW_TOKEN=$(python3 -c "import json; print(json.load(open('$TMPDIR_TOKEN/openclaw.json')).get('gateway',{}).get('auth',{}).get('token',''))" 2>/dev/null)
  if [ -n "$GW_TOKEN" ]; then
    write_urls "$GW_TOKEN"
    exit 0
  fi
fi

# Fallback: parse sandbox logs for the gateway startup line
GW_TOKEN=$(nemoclaw "$SANDBOX" logs 2>/dev/null | sed -n 's/.*Local UI: http:\/\/127\.0\.0\.1:18789\/#token=\([a-f0-9]*\).*/\1/p' | tail -1)
if [ -n "$GW_TOKEN" ]; then
  write_urls "$GW_TOKEN"
  echo "  (token extracted from logs)"
  exit 0
fi

echo "  ⚠ Could not extract UI URL — retrieve manually: nemoclaw $SANDBOX logs | grep 'Local UI'"
exit 1
