#!/usr/bin/env bash
# Write the deployment manifest after a successful setup or upgrade.
# Usage: write-manifest.sh
#
# Reads from: ~/.env, NemoClaw source checkout, installed CLI state, nemoclaw list
# Writes to:  ~/.nemoclaw/cookbook-deployment.json
#
# INTEGRATIONS holds a JSON string that we hand to Python via env vars
# (Python reads them with os.environ, no shell expansion), so SC2089/SC2090
# word-splitting warnings don't apply.
# shellcheck disable=SC2089,SC2090
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"

# Source env for tool flags
# shellcheck source=/dev/null
[ -f "$HOME/.env" ] && source "$HOME/.env"

SANDBOX_LIST=$(nemoclaw list 2>/dev/null || true)
SANDBOX_NAME=$(printf '%s\n' "$SANDBOX_LIST" | awk '/\*/{print $1; exit}')
SANDBOX_NAME="${SANDBOX_NAME:-unknown}"
NEMOCLAW_COMMIT=$(git -C "$HOME/NemoClaw" rev-parse --short HEAD 2>/dev/null || echo "unknown")
OPENSHELL_VERSION=$(openshell --version 2>/dev/null | head -1 || echo "unknown")
COOKBOOK_COMMIT=$(git -C "$COOKBOOK_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Build integrations object
INTEGRATIONS="{}"
[ -n "${TAVILY_API_KEY:-}" ] && INTEGRATIONS=$(echo "$INTEGRATIONS" | python3 -c "import sys,json; d=json.load(sys.stdin); d['search']='tavily'; print(json.dumps(d))")
[ -n "${BRAVE_API_KEY:-}" ] && [ -z "${TAVILY_API_KEY:-}" ] && INTEGRATIONS=$(echo "$INTEGRATIONS" | python3 -c "import sys,json; d=json.load(sys.stdin); d['search']='brave'; print(json.dumps(d))")
case "${NEMOCLAW_OPENAI_HTTP_ENABLED:-}" in
  1|true|yes) INTEGRATIONS=$(echo "$INTEGRATIONS" | python3 -c "import sys,json; d=json.load(sys.stdin); d['openai_http']=True; print(json.dumps(d))") ;;
esac

mkdir -p "$HOME/.nemoclaw"
export COOKBOOK_COMMIT NEMOCLAW_COMMIT OPENSHELL_VERSION SANDBOX_NAME INTEGRATIONS
python3 - <<'PY' > "$HOME/.nemoclaw/cookbook-deployment.json"
import json
import os
from datetime import datetime, timezone

manifest = {
    "deployed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "cookbook_commit": os.environ["COOKBOOK_COMMIT"],
    "nemoclaw_commit": os.environ["NEMOCLAW_COMMIT"],
    "openshell_version": os.environ["OPENSHELL_VERSION"],
    "sandbox_name": os.environ["SANDBOX_NAME"],
    "integrations": json.loads(os.environ["INTEGRATIONS"]),
}
print(json.dumps(manifest, indent=2))
PY

echo "  ✓ Deployment manifest written to ~/.nemoclaw/cookbook-deployment.json"
