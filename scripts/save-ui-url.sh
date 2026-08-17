#!/usr/bin/env bash
# Save private access files for the selected NemoClaw agent runtime.
#
# Gateway agents get a dashboard URL. Hermes also gets a client env for its
# native OpenAI-compatible API. OpenClaw gets the cookbook API env only when
# NEMOCLAW_OPENAI_HTTP_ENABLED is enabled. Terminal-only agents intentionally
# have no dashboard or API file. Every agent can use the independent browser
# terminal URL when the terminal service is enabled.
set -uo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=scripts/lib/agent-runtime.sh
source "$SCRIPT_DIR/lib/agent-runtime.sh"

export PATH="$HOME/.local/bin:$PATH"
# shellcheck source=/dev/null
[ -f "$HOME/.env" ] && source "$HOME/.env"

TUNNEL_FQDN="${TUNNEL_FQDN:-}"
TUNNEL_FQDN="${TUNNEL_FQDN#https://}"
TUNNEL_FQDN="${TUNNEL_FQDN#http://}"

SANDBOX="$(cookbook_discover_sandbox "${1:-}")"
if [ -z "$SANDBOX" ] || ! cookbook_load_runtime "$SANDBOX"; then
  echo "  ⚠ No healthy registered sandbox found — skipping access-file generation"
  exit 1
fi

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

remove_generated_file() {
  local path="$1"
  if [ -e "$path" ]; then
    rm -f -- "$path"
    echo "  ✓ Removed stale generated file ~/${path#"$HOME"/}"
  fi
}

generate_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    python3 -c 'import secrets; print(secrets.token_hex(32))'
  fi
}

ensure_private_token() {
  local token_file="$1"
  local token=""
  mkdir -p "$(dirname "$token_file")"
  chmod 700 "$(dirname "$token_file")"
  [ -f "$token_file" ] && token="$(sed -n '1p' "$token_file")"
  case "$token" in
    ""|*[!A-Za-z0-9._~+=/-]*)
      token="$(generate_token)"
      printf '%s\n' "$token" | write_private_file "$token_file"
      ;;
  esac
  printf '%s\n' "$token"
}

append_token_fragment() {
  local url="$1"
  local token="$2"
  if [ -z "$token" ] || printf '%s' "$url" | grep -q '[#?&]token='; then
    printf '%s\n' "$url"
  elif printf '%s' "$url" | grep -q '#'; then
    printf '%s&token=%s\n' "$url" "$token"
  else
    printf '%s/#token=%s\n' "${url%/}" "$token"
  fi
}

refresh_openai_nginx() {
  if "$COOKBOOK_DIR/scripts/install-services.sh" --nginx-only --sandbox "$SANDBOX" >/dev/null; then
    echo "  ✓ nginx OpenAI HTTP auth refreshed"
  else
    echo "  ⚠ Could not refresh nginx OpenAI HTTP auth"
    return 1
  fi
}

write_openai_env() {
  local path="$1"
  local base_url="$2"
  local token_file="$3"
  {
    echo "# OpenAI-compatible API for NemoClaw sandbox '$SANDBOX' ($COOKBOOK_AGENT_DISPLAY)."
    echo "# The credential remains in an owner-only token file."
    echo "NEMOCLAW_API_TOKEN_FILE=\"\${NEMOCLAW_API_TOKEN_FILE:-$token_file}\""
    echo "OPENAI_BASE_URL=\"$base_url\""
    echo "OPENAI_API_KEY=\"\$(sed -n '1p' \"\$NEMOCLAW_API_TOKEN_FILE\")\""
    echo "export OPENAI_BASE_URL OPENAI_API_KEY"
  } | write_private_file "$path"
}

# The browser terminal has an independent token so it never reuses an agent's
# dashboard or API credential.
if [ "${ENABLE_TERMINAL_SERVER:-true}" = "true" ]; then
  TERMINAL_TOKEN_FILE="$HOME/.nemoclaw/terminal-access-token"
  TERMINAL_TOKEN="$(ensure_private_token "$TERMINAL_TOKEN_FILE")"
  if [ -n "$TUNNEL_FQDN" ]; then
    TERMINAL_URL="https://${TUNNEL_FQDN}/terminal#token=${TERMINAL_TOKEN}"
  else
    TERMINAL_URL="http://127.0.0.1/terminal#token=${TERMINAL_TOKEN}"
  fi
  printf '%s\n' "$TERMINAL_URL" | write_private_file "$HOME/nemoclaw-terminal-url.txt"
  echo "  ✓ Browser terminal URL saved to ~/nemoclaw-terminal-url.txt"
fi

if [ "$COOKBOOK_RUNTIME" != "gateway" ]; then
  remove_generated_file "$HOME/nemoclaw-ui-url.txt"
  remove_generated_file "$HOME/nemoclaw-tunnel-url.txt"
  remove_generated_file "$HOME/nemoclaw-openai.env"
  echo "  ⊘ $COOKBOOK_AGENT_DISPLAY is terminal-only; no dashboard or HTTP API URL to save"
  exit 0
fi

UPSTREAM_URL="$(cookbook_dashboard_url "$SANDBOX")"
GW_TOKEN="$(nemoclaw "$SANDBOX" gateway-token --quiet 2>/dev/null | cookbook_last_nonempty_line)"
if [ -z "$UPSTREAM_URL" ]; then
  echo "  ⚠ Upstream did not return a dashboard URL for '$SANDBOX'"
  exit 1
fi

LOCAL_URL="$UPSTREAM_URL"
if [ "$COOKBOOK_AGENT" = "openclaw" ]; then
  LOCAL_URL="$(append_token_fragment "$UPSTREAM_URL" "$GW_TOKEN")"
fi
printf '%s\n' "$LOCAL_URL" | write_private_file "$HOME/nemoclaw-ui-url.txt"
echo "  ✓ Dashboard URL saved to ~/nemoclaw-ui-url.txt"

if [ -n "$TUNNEL_FQDN" ]; then
  TUNNEL_URL="https://${TUNNEL_FQDN}/"
  if [ "$COOKBOOK_AGENT" = "openclaw" ]; then
    TUNNEL_URL="$(append_token_fragment "$TUNNEL_URL" "$GW_TOKEN")"
  fi
  printf '%s\n' "$TUNNEL_URL" | write_private_file "$HOME/nemoclaw-tunnel-url.txt"
  echo "  ✓ Secure Link dashboard URL saved to ~/nemoclaw-tunnel-url.txt"
else
  remove_generated_file "$HOME/nemoclaw-tunnel-url.txt"
fi

if [ "$COOKBOOK_AGENT" = "openclaw" ]; then
  # Preserve established filenames for existing OpenClaw deployments.
  printf '%s\n' "$LOCAL_URL" | write_private_file "$HOME/openclaw-ui-url.txt"
  if [ -n "${TUNNEL_URL:-}" ]; then
    printf '%s\n' "$TUNNEL_URL" | write_private_file "$HOME/openclaw-tunnel-url.txt"
  fi

  case "${NEMOCLAW_OPENAI_HTTP_ENABLED:-}" in
    1|true|yes)
      if [ -z "$GW_TOKEN" ]; then
        echo "  ⚠ OpenClaw gateway token unavailable; API client env was not written"
        exit 1
      fi
      EDGE_TOKEN_FILE="$HOME/.nemoclaw/openai-http-edge-token"
      ensure_private_token "$EDGE_TOKEN_FILE" >/dev/null
      printf '%s\n' "$GW_TOKEN" | write_private_file "$HOME/.nemoclaw/openai-http-gateway-token"
      write_openai_env "$HOME/nemoclaw-openai.env" "http://127.0.0.1/v1" "$EDGE_TOKEN_FILE"
      write_openai_env "$HOME/openclaw-openai.env" "http://127.0.0.1/v1" "$EDGE_TOKEN_FILE"
      echo "  ✓ OpenClaw API client env saved to ~/nemoclaw-openai.env"
      refresh_openai_nginx
      ;;
    *)
      remove_generated_file "$HOME/nemoclaw-openai.env"
      remove_generated_file "$HOME/openclaw-openai.env"
      ;;
  esac
elif [ "$COOKBOOK_AGENT" = "hermes" ]; then
  if [ -n "$GW_TOKEN" ] && [ -n "$COOKBOOK_HERMES_API_PORT" ]; then
    HERMES_TOKEN_FILE="$HOME/.nemoclaw/${SANDBOX}-gateway-token"
    printf '%s\n' "$GW_TOKEN" | write_private_file "$HERMES_TOKEN_FILE"
    write_openai_env "$HOME/nemoclaw-openai.env" \
      "http://127.0.0.1:${COOKBOOK_HERMES_API_PORT}/v1" "$HERMES_TOKEN_FILE"
    echo "  ✓ Hermes native API client env saved to ~/nemoclaw-openai.env"
  else
    remove_generated_file "$HOME/nemoclaw-openai.env"
    echo "  ⚠ Hermes API token or forwarded API port unavailable; client env was not written"
  fi
fi
