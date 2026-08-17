#!/usr/bin/env bash
# Agent-aware backup/restore wrapper for NemoClaw sandboxes.
#
# Upstream manifests own the state contract for OpenClaw, Hermes, and
# LangChain Deep Agents Code. This wrapper deliberately does not copy private
# agent directories or guess where sessions and skills live.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/agent-runtime.sh
source "$SCRIPT_DIR/lib/agent-runtime.sh"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") backup  [sandbox-name] [snapshot-name]
  $(basename "$0") restore [sandbox-name] [version|name|timestamp]
  $(basename "$0") list    [sandbox-name]

The sandbox defaults to NEMOCLAW_SANDBOX_NAME, then NemoClaw's registered
default. Backup and restore delegate to the selected agent's upstream snapshot
manifest, which preserves its declared sessions, workspace, and skills while
excluding credential-bearing files.
EOF
}

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

[ "$#" -ge 1 ] || { usage; exit 1; }
case "$1" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac
command -v nemoclaw >/dev/null 2>&1 || fail "'nemoclaw' is required but not found in PATH"

action="$1"
shift
requested_sandbox="${1:-}"
if [ -n "$requested_sandbox" ]; then
  shift
fi
sandbox="$(cookbook_discover_sandbox "$requested_sandbox")"
[ -n "$sandbox" ] || fail "no NemoClaw sandbox found"

case "$action" in
  backup)
    [ "$#" -le 1 ] || { usage; exit 1; }
    snapshot_name="${1:-}"
    if [ -n "$snapshot_name" ]; then
      if ! nemoclaw "$sandbox" snapshot create --name "$snapshot_name"; then
        fail "upstream snapshot creation failed; no cookbook fallback was attempted"
      fi
    elif ! nemoclaw "$sandbox" snapshot create; then
      fail "upstream snapshot creation failed; no cookbook fallback was attempted"
    fi
    ;;
  restore)
    [ "$#" -le 1 ] || { usage; exit 1; }
    selector="${1:-}"
    if [ -n "$selector" ]; then
      nemoclaw "$sandbox" snapshot restore "$selector" --yes
    else
      nemoclaw "$sandbox" snapshot restore --yes
    fi
    ;;
  list)
    [ "$#" -eq 0 ] || { usage; exit 1; }
    nemoclaw "$sandbox" snapshot list
    ;;
  *)
    usage
    exit 1
    ;;
esac
