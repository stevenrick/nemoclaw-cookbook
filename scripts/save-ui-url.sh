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
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"

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

write_private_file() {
  local path="$1"
  local dir base tmp

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  mkdir -p "$dir"
  tmp="$(mktemp "${dir}/.${base}.XXXXXX")"
  cat > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$path"
}

generate_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    python3 -c 'import secrets; print(secrets.token_hex(32))'
  fi
}

ensure_openai_edge_token() {
  local secret_dir="$HOME/.nemoclaw"
  local token_file="$secret_dir/openai-http-edge-token"
  local token=""

  mkdir -p "$secret_dir"
  chmod 700 "$secret_dir"
  if [ -f "$token_file" ]; then
    token="$(sed -n '1p' "$token_file")"
  fi
  case "$token" in
    ""|*[!A-Za-z0-9._~+=/-]*)
      token="$(generate_token)"
      printf '%s\n' "$token" | write_private_file "$token_file"
      ;;
  esac
  printf '%s\n' "$token"
}

refresh_openai_nginx() {
  if [ ! -x "$COOKBOOK_DIR/scripts/install-services.sh" ]; then
    echo "  ⚠ Could not refresh nginx for OpenAI HTTP API; install-services.sh missing"
    return 1
  fi
  if "$COOKBOOK_DIR/scripts/install-services.sh" --nginx-only >/dev/null; then
    echo "  ✓ nginx OpenAI HTTP auth refreshed"
    return 0
  fi
  echo "  ⚠ Could not refresh nginx for OpenAI HTTP API; run scripts/install-services.sh --nginx-only"
  return 1
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

  printf '%s\n' "$local_url" | write_private_file "$HOME/openclaw-ui-url.txt"
  echo "  ✓ Local UI URL saved to ~/openclaw-ui-url.txt"

  if [ -n "$TUNNEL_FQDN" ]; then
    append_token_fragment "https://${TUNNEL_FQDN}/" "$token" | write_private_file "$HOME/openclaw-tunnel-url.txt"
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
    ensure_openai_edge_token >/dev/null
    printf '%s\n' "$token" | write_private_file "$HOME/.nemoclaw/openai-http-gateway-token"
    {
      echo "# OpenAI-compatible HTTP API on the NemoClaw gateway."
      echo "# OPENAI_API_KEY is loaded from the owner-only edge-token file instead"
      echo "# of being stored directly in this client env file. nginx rewrites it"
      echo "# to the private OpenClaw gateway token upstream."
      echo "# Rotate without rebuilding the sandbox: scripts/rotate-openai-http-token.sh"
      echo "# Default base URL: works from this Brev host directly, and from a"
      echo "# laptop via 'ssh -L 8080:127.0.0.1:80 <brev-host>' (then use"
      echo "# OPENAI_BASE_URL=http://127.0.0.1:8080/v1)."
      echo "OPENAI_EDGE_TOKEN_FILE=\"\${OPENAI_EDGE_TOKEN_FILE:-\$HOME/.nemoclaw/openai-http-edge-token}\""
      echo "OPENAI_BASE_URL=\"http://127.0.0.1/v1\""
      echo "OPENAI_API_KEY=\"\$(sed -n '1p' \"\$OPENAI_EDGE_TOKEN_FILE\")\""
      echo "export OPENAI_BASE_URL OPENAI_API_KEY"
      if [ -n "$TUNNEL_FQDN" ]; then
        echo ""
        echo "# Alternative: tunnel URL. Non-loopback /v1/* access requires"
        echo "# NEMOCLAW_OPENAI_HTTP_TUNNEL=1 plus Cloudflare Access service-token"
        echo "# headers configured on nginx and sent by the client."
        echo "# OPENAI_BASE_URL=https://${TUNNEL_FQDN}/v1"
      fi
    } | write_private_file "$HOME/openclaw-openai.env"
    echo "  ✓ OpenAI HTTP API env saved to ~/openclaw-openai.env"
    refresh_openai_nginx
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
  write_urls "$GW_TOKEN" "$LOCAL_URL" || exit 1
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
    write_urls "$GW_TOKEN" "$LOCAL_URL" || exit 1
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
  write_urls "$GW_TOKEN" "$LOCAL_URL" || exit 1
  echo "  (token extracted from logs)"
  exit 0
fi

if [ -n "$UPSTREAM_URL" ]; then
  printf '%s\n' "$UPSTREAM_URL" | write_private_file "$HOME/openclaw-ui-url.txt"
  echo "  ✓ Local UI URL saved to ~/openclaw-ui-url.txt"
  echo "  ⚠ Gateway token was not available; ~/openclaw-openai.env was not written."
  exit 0
fi

echo "  ⚠ Could not extract UI URL — retrieve manually: nemoclaw $SANDBOX dashboard-url --quiet"
exit 1
