#!/usr/bin/env bash
# Extract the gateway auth token from the running sandbox and write
# the tokenized Web UI URL to ~/openclaw-ui-url.txt.
#
# Usage: save-ui-url.sh [sandbox-name]
#
# The token lives in /sandbox/.openclaw/openclaw.json inside the sandbox.
# Falls back to parsing sandbox logs if the config download fails.
set -uo pipefail

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"

SANDBOX="${1:-$(nemoclaw list 2>/dev/null | awk '/\*/{print $1}' | head -1)}"
if [ -z "$SANDBOX" ]; then
  echo "  ⚠ No active sandbox found — skipping URL extraction"
  exit 1
fi

TMPDIR_TOKEN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TOKEN"' EXIT

# Primary: download openclaw.json from sandbox and extract the token
if openshell sandbox download "$SANDBOX" /sandbox/.openclaw/openclaw.json "$TMPDIR_TOKEN" 2>/dev/null; then
  GW_TOKEN=$(python3 -c "import json; print(json.load(open('$TMPDIR_TOKEN/openclaw.json')).get('gateway',{}).get('auth',{}).get('token',''))" 2>/dev/null)
  if [ -n "$GW_TOKEN" ]; then
    echo "http://127.0.0.1:18789/#token=${GW_TOKEN}" > "$HOME/openclaw-ui-url.txt"
    echo "  ✓ Tokenized UI URL saved to ~/openclaw-ui-url.txt"
    exit 0
  fi
fi

# Fallback: parse sandbox logs for the gateway startup line
GW_TOKEN=$(nemoclaw "$SANDBOX" logs 2>/dev/null | sed -n 's/.*Local UI: http:\/\/127\.0\.0\.1:18789\/#token=\([a-f0-9]*\).*/\1/p' | tail -1)
if [ -n "$GW_TOKEN" ]; then
  echo "http://127.0.0.1:18789/#token=${GW_TOKEN}" > "$HOME/openclaw-ui-url.txt"
  echo "  ✓ Tokenized UI URL saved to ~/openclaw-ui-url.txt (from logs)"
  exit 0
fi

echo "  ⚠ Could not extract UI URL — retrieve manually: nemoclaw $SANDBOX logs | grep 'Local UI'"
exit 1
