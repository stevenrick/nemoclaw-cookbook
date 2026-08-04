#!/usr/bin/env bash
# Rotate the host-side OpenAI-compatible HTTP API edge token.
#
# This does not restart or rebuild the sandbox. nginx accepts the new client
# token and continues to forward the private OpenClaw gateway token upstream.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=/dev/null
[ -f "$HOME/.env" ] && source "$HOME/.env"

case "${NEMOCLAW_OPENAI_HTTP_ENABLED:-}" in
  1|true) ;;
  *)
    echo "ERROR: NEMOCLAW_OPENAI_HTTP_ENABLED=1 is required before rotating the OpenAI HTTP token" >&2
    exit 1
    ;;
esac

SECRET_DIR="$HOME/.nemoclaw"
EDGE_TOKEN_FILE="$SECRET_DIR/openai-http-edge-token"
GATEWAY_TOKEN_FILE="$SECRET_DIR/openai-http-gateway-token"
OPENAI_ENV_FILE="$HOME/openclaw-openai.env"

write_private_file() {
  local path="$1"
  local dir base tmp

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  mkdir -p "$dir"
  if [ "$dir" = "$SECRET_DIR" ]; then
    chmod 700 "$dir"
  fi
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

if [ ! -s "$GATEWAY_TOKEN_FILE" ]; then
  echo "ERROR: $GATEWAY_TOKEN_FILE is missing; run scripts/save-ui-url.sh first" >&2
  exit 1
fi

OPENAI_BASE_URL="http://127.0.0.1/v1"
if [ -f "$OPENAI_ENV_FILE" ]; then
  EXISTING_OPENAI_BASE_URL="$(sed -n 's/^OPENAI_BASE_URL=//p' "$OPENAI_ENV_FILE" | tail -1)"
  OPENAI_BASE_URL="${EXISTING_OPENAI_BASE_URL:-$OPENAI_BASE_URL}"
fi

NEW_TOKEN="$(generate_token)"
printf '%s\n' "$NEW_TOKEN" | write_private_file "$EDGE_TOKEN_FILE"

{
  echo "# OpenAI-compatible HTTP API on the NemoClaw gateway."
  echo "# OPENAI_API_KEY is loaded from the owner-only edge-token file instead"
  echo "# of being stored directly in this client env file. nginx rewrites it"
  echo "# to the private OpenClaw gateway token upstream."
  echo "# Rotate without rebuilding the sandbox: scripts/rotate-openai-http-token.sh"
  echo "OPENAI_EDGE_TOKEN_FILE=\"\${OPENAI_EDGE_TOKEN_FILE:-\$HOME/.nemoclaw/openai-http-edge-token}\""
  echo "OPENAI_BASE_URL=\"${OPENAI_BASE_URL}\""
  echo "OPENAI_API_KEY=\"\$(sed -n '1p' \"\$OPENAI_EDGE_TOKEN_FILE\")\""
  echo "export OPENAI_BASE_URL OPENAI_API_KEY"
} | write_private_file "$OPENAI_ENV_FILE"

"$COOKBOOK_DIR/scripts/install-services.sh" --nginx-only >/dev/null
echo "OpenAI HTTP API token rotated. Reload client settings from ~/openclaw-openai.env."
