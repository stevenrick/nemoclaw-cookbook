#!/usr/bin/env bash
# Write the deployment manifest after a successful setup or upgrade.
# Usage: write-manifest.sh
#
# Reads from: ~/.env (INSTALL_CLAUDE_CODE, INSTALL_CODEX), git repos, nemoclaw list
# Writes to:  ~/.nemoclaw/cookbook-deployment.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"

# Source env for tool flags
[ -f "$HOME/.env" ] && source "$HOME/.env"

SANDBOX_NAME=$(nemoclaw list 2>/dev/null | grep '\*' | awk '{print $1}' || echo "unknown")
NEMOCLAW_COMMIT=$(git -C "$HOME/NemoClaw" rev-parse --short HEAD 2>/dev/null || echo "unknown")
OPENSHELL_COMMIT=$(git -C "$HOME/OpenShell" rev-parse --short HEAD 2>/dev/null || echo "unknown")
COOKBOOK_COMMIT=$(git -C "$COOKBOOK_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

INSTALL_CLAUDE_CODE="${INSTALL_CLAUDE_CODE:-true}"
INSTALL_CODEX="${INSTALL_CODEX:-true}"

# Build tools array
TOOLS="[]"
if [ "$INSTALL_CLAUDE_CODE" = "true" ]; then
  if [ "$INSTALL_CODEX" = "true" ]; then
    TOOLS='["claude-code", "codex"]'
  else
    TOOLS='["claude-code"]'
  fi
elif [ "$INSTALL_CODEX" = "true" ]; then
  TOOLS='["codex"]'
fi

mkdir -p "$HOME/.nemoclaw"
cat > "$HOME/.nemoclaw/cookbook-deployment.json" <<MANIFEST
{
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cookbook_commit": "$COOKBOOK_COMMIT",
  "nemoclaw_commit": "$NEMOCLAW_COMMIT",
  "openshell_commit": "$OPENSHELL_COMMIT",
  "sandbox_name": "$SANDBOX_NAME",
  "tools": $TOOLS
}
MANIFEST

echo "  ✓ Deployment manifest written to ~/.nemoclaw/cookbook-deployment.json"
