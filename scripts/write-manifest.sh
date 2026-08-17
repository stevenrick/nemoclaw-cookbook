#!/usr/bin/env bash
# Write the deployment manifest after a successful setup or upgrade.
# Usage: write-manifest.sh [sandbox-name]
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
# shellcheck source=scripts/lib/agent-runtime.sh
source "$SCRIPT_DIR/lib/agent-runtime.sh"

# Source env for tool flags
# shellcheck source=/dev/null
[ -f "$HOME/.env" ] && source "$HOME/.env"

SANDBOX_NAME="$(cookbook_discover_sandbox "${1:-}")"
[ -n "$SANDBOX_NAME" ] || { echo "ERROR: no NemoClaw sandbox found" >&2; exit 1; }
cookbook_load_runtime "$SANDBOX_NAME"
NEMOCLAW_SOURCE_DIR="${NEMOCLAW_SOURCE_DIR:-$HOME/NemoClaw}"
NEMOCLAW_COMMIT=$(git -C "$NEMOCLAW_SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
OPENSHELL_VERSION=$(openshell --version 2>/dev/null | head -1 || echo "unknown")
COOKBOOK_COMMIT=$(git -C "$COOKBOOK_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Build integrations object
INTEGRATIONS="{}"
WEB_SEARCH_PROVIDER="${NEMOCLAW_WEB_SEARCH_PROVIDER:-}"
if [ -z "$WEB_SEARCH_PROVIDER" ]; then
  if [ -n "${BRAVE_API_KEY:-}" ]; then
    WEB_SEARCH_PROVIDER="brave"
  elif [ -n "${TAVILY_API_KEY:-}" ]; then
    WEB_SEARCH_PROVIDER="tavily"
  fi
fi
if [ -n "$WEB_SEARCH_PROVIDER" ] && [ "$WEB_SEARCH_PROVIDER" != "none" ]; then
  INTEGRATIONS=$(WEB_SEARCH_PROVIDER="$WEB_SEARCH_PROVIDER" python3 -c "import os,sys,json; d=json.load(sys.stdin); d['search']=os.environ['WEB_SEARCH_PROVIDER']; print(json.dumps(d))" <<< "$INTEGRATIONS")
fi
case "${NEMOCLAW_OPENAI_HTTP_ENABLED:-}" in
  1|true|yes)
    if [ "$COOKBOOK_AGENT" = "openclaw" ]; then
      INTEGRATIONS=$(printf '%s\n' "$INTEGRATIONS" | python3 -c "import sys,json; d=json.load(sys.stdin); d['openai_http']=True; print(json.dumps(d))")
    fi
    ;;
esac

mkdir -p "$HOME/.nemoclaw"
export COOKBOOK_COMMIT NEMOCLAW_COMMIT OPENSHELL_VERSION SANDBOX_NAME INTEGRATIONS
export COOKBOOK_AGENT COOKBOOK_AGENT_DISPLAY COOKBOOK_RUNTIME
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
    "agent": os.environ["COOKBOOK_AGENT"],
    "agent_display_name": os.environ["COOKBOOK_AGENT_DISPLAY"],
    "agent_runtime": os.environ["COOKBOOK_RUNTIME"],
    "integrations": json.loads(os.environ["INTEGRATIONS"]),
}
print(json.dumps(manifest, indent=2))
PY

echo "  ✓ Deployment manifest written to ~/.nemoclaw/cookbook-deployment.json"
