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
# Writable workspace — NOT /sandbox/.openclaw/ which is immutable build-time config.
WORKSPACE_PATH="/sandbox/.openclaw-data/workspace"

# Additional workspace files not included in upstream backup-workspace.sh.
# We download/upload these ourselves so backups are complete.
EXTRA_FILES=(HEARTBEAT.md TOOLS.md)

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

  # Back up additional workspace files not in upstream backup-workspace.sh
  info "Backing up extra workspace files..."
  for f in "${EXTRA_FILES[@]}"; do
    if openshell sandbox download "$sandbox" "${WORKSPACE_PATH}/${f}" "${dest}/" 2>/dev/null; then
      info "  + ${f}"
    else
      warn "Skipped ${f} (not found in sandbox)"
    fi
  done

  # Back up chat sessions
  info "Backing up chat sessions..."
  local sessions_dir="${dest}/sessions"
  mkdir -p "$sessions_dir"

  if openshell sandbox download "$sandbox" "${SESSIONS_PATH}/" "${sessions_dir}/" 2>/dev/null; then
    # Strip .reset. suffixes — the gateway renames orphaned sessions but
    # the data is still valid. Clean names make restore work without fixup.
    for f in "${sessions_dir}"/*.reset.*; do
      [ -f "$f" ] || continue
      local orig="${f%%.reset.*}"
      mv "$f" "$orig" 2>/dev/null && info "  Recovered: $(basename "$orig")"
    done
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

    # Restore additional workspace files not in upstream backup-workspace.sh
    for f in "${EXTRA_FILES[@]}"; do
      if [ -f "${src}/${f}" ]; then
        if openshell sandbox upload "$sandbox" "${src}/${f}" "${WORKSPACE_PATH}/" 2>/dev/null; then
          info "  + ${f}"
        else
          warn "Failed to restore ${f}"
        fi
      fi
    done

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

        # Point the active session to the most content-rich .jsonl file.
        # After a rebuild the gateway creates a new empty session. The real
        # conversation is in the restored files but sessions.json doesn't
        # reference it. Find the session with the most real user messages
        # (not heartbeat noise) and set it as active.
        openshell sandbox exec --name "$sandbox" -- \
          python3 -c "
import json, os, glob

sessions_dir = '${SESSIONS_PATH}'
best_file = None
best_count = 0

for f in glob.glob(os.path.join(sessions_dir, '*.jsonl')):
    count = 0
    with open(f) as fh:
        for line in fh:
            try:
                entry = json.loads(line)
                if entry.get('type') == 'message':
                    msg = entry.get('message', {})
                    text = msg.get('text', '') or ''
                    if msg.get('role') == 'user' and 'HEARTBEAT' not in text:
                        count += 1
            except:
                pass
    if count > best_count:
        best_count = count
        best_file = f

if best_file and best_count > 0:
    best_id = os.path.splitext(os.path.basename(best_file))[0]
    path = os.path.join(sessions_dir, 'sessions.json')
    try:
        d = json.load(open(path))
    except:
        d = {}
    key = 'agent:main:main'
    if key in d:
        d[key]['sessionId'] = best_id
        d[key]['sessionFile'] = best_file
        d[key]['origin'] = {'label': 'main'}
        d[key]['lastTo'] = 'main'
        d[key]['deliveryContext'] = {}
        json.dump(d, open(path, 'w'), indent=2)
        print(f'  Active session: {best_id} ({best_count} user messages)')
" 2>/dev/null || true
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
