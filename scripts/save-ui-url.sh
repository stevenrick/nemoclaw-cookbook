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

  # OpenAI-compatible HTTP API env file (when integration is enabled).
  # Defaults to http://127.0.0.1/v1 because Brev's cloudflared tunnel sits
  # behind Cloudflare Access — programmatic clients (Python openai SDK,
  # curl) get redirected to an SSO login page unless they have a CF Access
  # service token. Local URL works from the Brev host and from a laptop
  # via SSH port-forward. The tunnel URL is written as a commented
  # alternative for users who configure CF Access service tokens.
  local openai_flag="${NEMOCLAW_OPENAI_HTTP_ENABLED:-}"
  if [ "$openai_flag" = "1" ] || [ "$openai_flag" = "true" ]; then
    {
      echo "# OpenAI-compatible HTTP API on the NemoClaw gateway."
      echo "# Default base URL: works from this Brev host directly, and from a"
      echo "# laptop via 'ssh -L 8080:127.0.0.1:80 <brev-host>' (then use"
      echo "# OPENAI_BASE_URL=http://127.0.0.1:8080/v1)."
      echo "OPENAI_BASE_URL=http://127.0.0.1/v1"
      echo "OPENAI_API_KEY=${token}"
      if [ -n "$TUNNEL_FQDN" ]; then
        echo ""
        echo "# Alternative: tunnel URL. Requires a Cloudflare Access service"
        echo "# token (CF-Access-Client-Id + CF-Access-Client-Secret headers)"
        echo "# OR a /v1/* bypass rule in the Brev/Cloudflare Access dashboard."
        echo "# OPENAI_BASE_URL=https://${TUNNEL_FQDN}/v1"
      fi
    } > "$HOME/openclaw-openai.env"
    chmod 600 "$HOME/openclaw-openai.env"
    echo "  ✓ OpenAI HTTP API env saved to ~/openclaw-openai.env"
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
