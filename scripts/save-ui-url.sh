#!/usr/bin/env bash
# Extract the gateway auth token from the running sandbox and write
# tokenized Web UI URLs to ~/openclaw-ui-url.txt (local) and
# ~/openclaw-tunnel-url.txt (Secure Link, if TUNNEL_FQDN is set).
#
# Usage: save-ui-url.sh [sandbox-name]
#
# Prefer upstream `dashboard-url` / `gateway-token` commands. Falls back to
# downloading openclaw.json or parsing sandbox logs for older/broken installs.
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

last_nonempty_line() {
  awk 'NF { line=$0 } END { if (line) print line }'
}

append_token_fragment() {
  local url="$1"
  local token="$2"

  if [ -z "$url" ]; then
    return 1
  fi
  if [ -z "$token" ] || printf '%s' "$url" | grep -q '#token='; then
    printf '%s\n' "$url"
    return 0
  fi

  if printf '%s' "$url" | grep -q '#'; then
    printf '%s&token=%s\n' "$url" "$token"
  else
    printf '%s/#token=%s\n' "${url%/}" "$token"
  fi
}

write_urls() {
  local token="$1"
  local local_url="${2:-}"

  if [ -z "$local_url" ]; then
    local_url="http://127.0.0.1:18789/#token=${token}"
  fi

  echo "$local_url" > "$HOME/openclaw-ui-url.txt"
  echo "  ✓ Local UI URL saved to ~/openclaw-ui-url.txt"

  if [ -n "$TUNNEL_FQDN" ]; then
    append_token_fragment "https://${TUNNEL_FQDN}/" "$token" > "$HOME/openclaw-tunnel-url.txt"
    echo "  ✓ Tunnel UI URL saved to ~/openclaw-tunnel-url.txt"
  fi

  # OpenAI-compatible HTTP API env file (when integration is enabled).
  # Defaults to http://127.0.0.1/v1 — works from the Brev host directly and
  # from a laptop via SSH port-forward. The tunnel URL is written as a
  # commented alternative because Brev's Secure Link is gated by Cloudflare
  # Access with SSO by default, so programmatic clients get redirected to a
  # login page until that gate is removed or bypassed. See BUILD.md for the
  # four ways to make the tunnel URL programmatically reachable.
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
        echo "# Alternative: tunnel URL. Brev's Secure Link defaults to"
        echo "# Cloudflare Access SSO — programmatic clients need one of:"
        echo "#   (a) Brev dashboard → Secure Links → this link → Edit Access"
        echo "#       → toggle 'Make Public' on (simplest; exposes the entire"
        echo "#       hostname incl. dashboard, gated only by the gateway token"
        echo "#       below)"
        echo "#   (b) CF Access service token + CF-Access-Client-Id / -Secret"
        echo "#       headers alongside Authorization"
        echo "#   (c) CF Access /v1/* bypass rule (API public, dashboard still"
        echo "#       SSO-gated — narrowest blast radius)"
        echo "# See BUILD.md (\"Exposing the API beyond the host\") for trade-offs."
        echo "# OPENAI_BASE_URL=https://${TUNNEL_FQDN}/v1"
      fi
    } > "$HOME/openclaw-openai.env"
    chmod 600 "$HOME/openclaw-openai.env"
    echo "  ✓ OpenAI HTTP API env saved to ~/openclaw-openai.env"
  fi
}

TMPDIR_TOKEN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TOKEN"' EXIT

# Primary: use upstream commands.
UPSTREAM_URL=$(nemoclaw "$SANDBOX" dashboard-url --quiet 2>/dev/null | last_nonempty_line)
GW_TOKEN=$(nemoclaw "$SANDBOX" gateway-token --quiet 2>/dev/null | last_nonempty_line)

if [ -n "$GW_TOKEN" ]; then
  if [ -n "$UPSTREAM_URL" ]; then
    LOCAL_URL=$(append_token_fragment "$UPSTREAM_URL" "$GW_TOKEN")
  else
    LOCAL_URL=""
  fi
  write_urls "$GW_TOKEN" "$LOCAL_URL"
  exit 0
fi

# Fallback: download openclaw.json from sandbox and extract the token.
if openshell sandbox download "$SANDBOX" /sandbox/.openclaw/openclaw.json "$TMPDIR_TOKEN" 2>/dev/null; then
  GW_TOKEN=$(python3 - "$TMPDIR_TOKEN" <<'PY' 2>/dev/null
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for path in root.rglob("openclaw.json"):
    cfg = json.load(path.open())
    token = cfg.get("gateway", {}).get("auth", {}).get("token", "")
    if token:
        print(token)
        break
PY
)
  if [ -n "$GW_TOKEN" ]; then
    if [ -n "$UPSTREAM_URL" ]; then
      LOCAL_URL=$(append_token_fragment "$UPSTREAM_URL" "$GW_TOKEN")
    else
      LOCAL_URL=""
    fi
    write_urls "$GW_TOKEN" "$LOCAL_URL"
    exit 0
  fi
fi

# Fallback: parse sandbox logs for the gateway startup line
GW_TOKEN=$(nemoclaw "$SANDBOX" logs 2>/dev/null | sed -n 's/.*Local UI: http:\/\/127\.0\.0\.1:18789\/#token=\([^[:space:]]*\).*/\1/p' | tail -1)
if [ -n "$GW_TOKEN" ]; then
  if [ -n "$UPSTREAM_URL" ]; then
    LOCAL_URL=$(append_token_fragment "$UPSTREAM_URL" "$GW_TOKEN")
  else
    LOCAL_URL=""
  fi
  write_urls "$GW_TOKEN" "$LOCAL_URL"
  echo "  (token extracted from logs)"
  exit 0
fi

if [ -n "$UPSTREAM_URL" ]; then
  echo "$UPSTREAM_URL" > "$HOME/openclaw-ui-url.txt"
  echo "  ✓ Local UI URL saved to ~/openclaw-ui-url.txt"
  echo "  ⚠ Gateway token was not available; ~/openclaw-openai.env was not written."
  exit 0
fi

echo "  ⚠ Could not extract UI URL — retrieve manually: nemoclaw $SANDBOX dashboard-url --quiet"
exit 1
