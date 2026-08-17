#!/usr/bin/env bash
# Shared, read-only runtime discovery for cookbook scripts.
#
# NemoClaw's registry and status JSON are the source of truth. Callers must not
# infer the active agent from directory names, fixed ports, or human-formatted
# `nemoclaw list` output.
# shellcheck disable=SC2034 # cookbook_load_runtime intentionally publishes globals to callers.

cookbook_last_nonempty_line() {
  awk 'NF { line=$0 } END { if (line) print line }'
}

cookbook_normalize_agent() {
  case "${1:-openclaw}" in
    openclaw) printf '%s\n' openclaw ;;
    hermes|nemohermes) printf '%s\n' hermes ;;
    langchain-deepagents-code|deepagents|dcode|nemo-deepagents)
      printf '%s\n' langchain-deepagents-code
      ;;
    *) return 1 ;;
  esac
}

cookbook_valid_sandbox_name() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

cookbook_discover_sandbox() {
  local requested="${1:-}"
  local list_json sandbox

  if [ -n "$requested" ]; then
    printf '%s\n' "$requested"
    return 0
  fi
  if [ -n "${NEMOCLAW_SANDBOX_NAME:-}" ]; then
    printf '%s\n' "$NEMOCLAW_SANDBOX_NAME"
    return 0
  fi

  list_json="$(nemoclaw list --json 2>/dev/null || true)"
  if [ -n "$list_json" ]; then
    sandbox="$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
name = data.get("defaultSandbox") or data.get("lastOnboardedSandbox")
if not name:
    sandboxes = data.get("sandboxes") or []
    if sandboxes:
        name = sandboxes[0].get("name")
if name:
    print(name)
' <<< "$list_json")"
    if [ -n "$sandbox" ]; then
      printf '%s\n' "$sandbox"
      return 0
    fi
  fi

  # Compatibility fallback for older upstream CLIs without `list --json`.
  nemoclaw list 2>/dev/null | awk '/\*/ { print $1; exit }'
}

cookbook_load_runtime() {
  local sandbox="$1"
  local list_json
  local -a fields

  COOKBOOK_STATUS_JSON="$(nemoclaw "$sandbox" status --json 2>/dev/null)" || return 1
  mapfile -t fields < <(python3 -c '
import json, sys
data = json.load(sys.stdin)
values = (
    data.get("agent"),
    data.get("agentDisplayName"),
    data.get("agentRuntime"),
    data.get("phase"),
    (data.get("inferenceHealth") or {}).get("ok"),
    (data.get("terminalRuntimeHealth") or {}).get("kind"),
)
for value in values:
    if value is True:
        print("true")
    elif value is False:
        print("false")
    elif value is None:
        print("")
    else:
        print(value)
' <<< "$COOKBOOK_STATUS_JSON")
  [ "${#fields[@]}" -eq 6 ] || return 1

  COOKBOOK_SANDBOX="$sandbox"
  COOKBOOK_AGENT="${fields[0]}"
  COOKBOOK_AGENT_DISPLAY="${fields[1]}"
  COOKBOOK_RUNTIME="${fields[2]}"
  COOKBOOK_PHASE="${fields[3]}"
  COOKBOOK_INFERENCE_OK="${fields[4]}"
  COOKBOOK_TERMINAL_HEALTH="${fields[5]}"
  COOKBOOK_DASHBOARD_PORT=""
  COOKBOOK_HERMES_API_PORT=""

  list_json="$(nemoclaw list --json 2>/dev/null || true)"
  if [ -n "$list_json" ]; then
    COOKBOOK_DASHBOARD_PORT="$(SANDBOX_NAME="$sandbox" python3 -c '
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for entry in data.get("sandboxes") or []:
    if entry.get("name") == os.environ["SANDBOX_NAME"]:
        port = entry.get("dashboardPort")
        if isinstance(port, int) and 0 < port < 65536:
            print(port)
        break
' <<< "$list_json")"
  fi

  if [ "$COOKBOOK_AGENT" = "hermes" ]; then
    COOKBOOK_HERMES_API_PORT="$(
      openshell forward list 2>/dev/null \
        | awk -v sandbox="$sandbox" \
          '$1 == sandbox && $3 ~ /^[0-9]+$/ && $3 >= 8642 && $3 <= 8652 { print $3; exit }'
    )"
  fi
}

cookbook_dashboard_url() {
  local sandbox="$1"
  nemoclaw "$sandbox" dashboard-url --quiet 2>/dev/null | cookbook_last_nonempty_line
}

cookbook_agent_command() {
  case "$1" in
    openclaw) printf '%s\n' openclaw ;;
    hermes) printf '%s\n' hermes ;;
    langchain-deepagents-code) printf '%s\n' dcode ;;
    *) return 1 ;;
  esac
}

cookbook_skill_root() {
  case "$1" in
    openclaw) printf '%s\n' /sandbox/.openclaw/skills ;;
    hermes) printf '%s\n' /sandbox/.hermes/skills ;;
    langchain-deepagents-code) printf '%s\n' /sandbox/.deepagents/agent/skills ;;
    *) return 1 ;;
  esac
}
