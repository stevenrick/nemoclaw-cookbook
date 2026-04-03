#!/usr/bin/env bash
# Full backup/restore for NemoClaw sandbox — workspace + chat history.
# Wraps upstream backup-workspace.sh and adds session data.
#
# Usage:
#   ./scripts/backup-full.sh backup  <sandbox-name>
#   ./scripts/backup-full.sh restore <sandbox-name> [timestamp]
set -euo pipefail

BACKUP_BASE="${HOME}/.nemoclaw/backups"
SESSIONS_PATH="/sandbox/.openclaw-data/agents/main/sessions"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[backup-full]${NC} $1"; }
warn() { echo -e "${YELLOW}[backup-full]${NC} $1"; }
fail() { echo -e "${RED}[backup-full]${NC} $1" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  $(basename "$0") backup  <sandbox-name>
  $(basename "$0") restore <sandbox-name> [timestamp]

Backs up workspace files (via upstream script) AND chat session history.
EOF
  exit 1
}

find_upstream_script() {
  local script="${HOME}/NemoClaw/scripts/backup-workspace.sh"
  [ -x "$script" ] || fail "Upstream backup script not found: ${script}"
  echo "$script"
}

latest_backup() {
  find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | sort -r | head -n1
}

do_backup() {
  local sandbox="$1"
  local upstream
  upstream="$(find_upstream_script)"

  # Run upstream workspace backup first
  "$upstream" backup "$sandbox"

  # Find the backup directory that was just created (most recent)
  local ts
  ts="$(latest_backup)"
  [ -n "$ts" ] || fail "Could not find backup directory after upstream backup"
  local dest="${BACKUP_BASE}/${ts}"

  # Back up chat sessions
  info "Backing up chat sessions..."
  local sessions_dir="${dest}/sessions"
  mkdir -p "$sessions_dir"

  if openshell sandbox download "$sandbox" "${SESSIONS_PATH}/" "${sessions_dir}/" 2>/dev/null; then
    local count
    count=$(find "$sessions_dir" -type f 2>/dev/null | wc -l)
    info "Backed up ${count} session file(s) to ${sessions_dir}/"
  else
    warn "No chat sessions found (sandbox may be new)"
    rmdir "$sessions_dir" 2>/dev/null || true
  fi

  info "Full backup saved to ${dest}/"
}

do_restore() {
  local sandbox="$1"
  local ts="${2:-}"
  local upstream
  upstream="$(find_upstream_script)"

  # Run upstream workspace restore
  if [ -n "$ts" ]; then
    "$upstream" restore "$sandbox" "$ts"
  else
    "$upstream" restore "$sandbox"
    ts="$(latest_backup)"
  fi

  local src="${BACKUP_BASE}/${ts}"

  # Restore chat sessions if they exist in the backup
  if [ -d "${src}/sessions" ]; then
    info "Restoring chat sessions..."
    if openshell sandbox upload "$sandbox" "${src}/sessions/" "${SESSIONS_PATH}/" 2>/dev/null; then
      info "Chat sessions restored."
    else
      warn "Failed to restore chat sessions (sandbox may still be starting)"
    fi
  else
    info "No chat sessions in backup — skipping."
  fi

  info "Full restore complete."
}

# --- Main ---
[ $# -ge 2 ] || usage
command -v openshell >/dev/null 2>&1 || fail "'openshell' is required but not found in PATH."

action="$1"
sandbox="$2"
shift 2

case "$action" in
  backup)  do_backup "$sandbox" ;;
  restore) do_restore "$sandbox" "$@" ;;
  *)       usage ;;
esac
