#!/usr/bin/env bash
# Full backup/restore for NemoClaw sandbox — workspace, chat history, and skills.
# Wraps upstream backup-workspace.sh and adds session data + installed skills.
#
# Usage:
#   ./scripts/backup-full.sh backup  <sandbox-name>
#   ./scripts/backup-full.sh restore <sandbox-name> [timestamp]
#   ./scripts/backup-full.sh list
set -euo pipefail

BACKUP_BASE="${HOME}/.nemoclaw/backups"
SESSIONS_PATH="/sandbox/.openclaw-data/agents/main/sessions"
SKILLS_PATH="/sandbox/.openclaw-data/skills"

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
  $(basename "$0") restore <sandbox-name> [timestamp] [phase]
  $(basename "$0") list

phase (optional): all (default), workspace, sessions
  workspace — workspace files + skills (safe while gateway is running)
  sessions  — sessions.json + JSONL transcripts (run AFTER nemoclaw start)

Backs up workspace files (via upstream script), chat session history, and skills.
EOF
  exit 1
}

find_upstream_script() {
  # Check both locations: cloned repo (setup.sh) and installed source (curl installer)
  local script
  for candidate in "${HOME}/NemoClaw/scripts/backup-workspace.sh" "${HOME}/.nemoclaw/source/scripts/backup-workspace.sh"; do
    if [ -x "$candidate" ]; then
      script="$candidate"
      break
    fi
  done
  [ -n "${script:-}" ] || fail "Upstream backup script not found at ~/NemoClaw or ~/.nemoclaw/source"
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

  # Back up installed skills
  info "Backing up skills..."
  local skills_dir="${dest}/skills"
  mkdir -p "$skills_dir"

  if openshell sandbox download "$sandbox" "${SKILLS_PATH}/" "${skills_dir}/" 2>/dev/null; then
    local skill_count
    skill_count=$(find "$skills_dir" -type f 2>/dev/null | wc -l)
    info "Backed up ${skill_count} skill file(s) to ${skills_dir}/"
  else
    warn "No skills found (sandbox may not have any installed)"
    rmdir "$skills_dir" 2>/dev/null || true
  fi

  info "Full backup saved to ${dest}/"
}

do_restore() {
  local sandbox="$1"
  local ts="${2:-}"
  local phase="${3:-all}"
  local upstream
  upstream="$(find_upstream_script)"

  # Resolve backup timestamp
  if [ -n "$ts" ]; then
    : # use provided timestamp
  else
    ts="$(latest_backup)"
  fi
  [ -n "$ts" ] || fail "No backups found"

  local src="${BACKUP_BASE}/${ts}"
  [ -d "$src" ] || fail "Backup not found: $src"

  # --- Workspace phase: workspace files (safe to restore while gateway is running) ---
  if [ "$phase" = "all" ] || [ "$phase" = "workspace" ]; then
    "$upstream" restore "$sandbox" "$ts"

    if [ -d "${src}/skills" ]; then
      info "Restoring skills..."
      if openshell sandbox upload "$sandbox" "${src}/skills/" "${SKILLS_PATH}/" 2>/dev/null; then
        info "Skills restored."
      else
        warn "Failed to restore skills (sandbox may still be starting)"
      fi
    else
      info "No skills in backup — skipping."
    fi
  fi

  # --- Sessions phase: chat history (restore AFTER nemoclaw start so it overwrites
  #     whatever the gateway/channels created on reconnect). The gateway reads
  #     sessions.json from disk on each write, so uploading the backup version makes
  #     the next gateway operation pick up the restored sessions. ---
  if [ "$phase" = "all" ] || [ "$phase" = "sessions" ]; then
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
  fi

  info "Full restore complete (phase: $phase)."
}

# --- Main ---
[ $# -ge 1 ] || usage

action="$1"
shift

# list doesn't require a sandbox name or openshell
if [ "$action" = "list" ]; then
  ls -1t "$BACKUP_BASE" 2>/dev/null || echo "No backups found."
  exit 0
fi

[ $# -ge 1 ] || usage
command -v openshell >/dev/null 2>&1 || fail "'openshell' is required but not found in PATH."

sandbox="$1"
shift

case "$action" in
  backup)  do_backup "$sandbox" ;;
  restore) do_restore "$sandbox" "$@" ;;
  *)       usage ;;
esac
