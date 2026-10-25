#!/usr/bin/env bash
# Apply cookbook customizations to upstream NemoClaw files using modular fragments.
#
# Usage: apply-patches.sh <nemoclaw-dir>
#
# Reads cookbook-only integration flags from the environment. Upstream NemoClaw
# owns core agent tooling, OpenShell installation, agent versioning, and web
# search. The cookbook only patches the OpenClaw-specific gaps listed in
# UPSTREAM.md; Hermes and Deep Agents Code use their upstream images unchanged.
#
# Unlike git patches, this approach:
#   - Only needs one anchor line per file (not 3 lines of context)
#   - Composes fragments independently
#   - Handles upstream YAML restructuring gracefully
set -euo pipefail

NEMOCLAW_DIR="${1:?Usage: apply-patches.sh NEMOCLAW_DIR}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"
FRAGMENTS_DIR="$COOKBOOK_DIR/patches/fragments"
# shellcheck source=scripts/lib/agent-runtime.sh
source "$SCRIPT_DIR/lib/agent-runtime.sh"

# Integration flags
REQUESTED_AGENT="${NEMOCLAW_AGENT:-openclaw}"
if ! ACTIVE_AGENT="$(cookbook_normalize_agent "$REQUESTED_AGENT")"; then
  echo "ERROR: Unsupported NEMOCLAW_AGENT '$REQUESTED_AGENT'." >&2
  echo "Expected openclaw, hermes, or langchain-deepagents-code." >&2
  exit 1
fi
NEMOCLAW_OPENAI_HTTP_ENABLED="${NEMOCLAW_OPENAI_HTTP_ENABLED:-}"

if [ "$ACTIVE_AGENT" != "openclaw" ]; then
  case "$NEMOCLAW_OPENAI_HTTP_ENABLED" in
    1|true|yes)
      echo "ERROR: NEMOCLAW_OPENAI_HTTP_ENABLED is an OpenClaw-only cookbook overlay." >&2
      if [ "$ACTIVE_AGENT" = "hermes" ]; then
        echo "Hermes already exposes its upstream OpenAI-compatible API; leave this flag unset." >&2
      fi
      exit 1
      ;;
  esac
  echo "  No cookbook image patches needed for $ACTIVE_AGENT; using the upstream agent image unchanged."
  exit 0
fi

DOCKERFILE="$NEMOCLAW_DIR/Dockerfile"
REMOVED_TOOL_INSTALLS=0

# ── Dockerfile modifications ────────────────────────────────────────
# Post-config anchor: fragments inserted here run as root, AFTER all upstream
# openclaw.json writes (config generation, plugin installation, token clear,
# managed proxy config) and BEFORE upstream finalizes ownership and permissions.
# Upstream no longer maintains an OpenClaw config hash.
POST_CONFIG_ANCHOR="# Keep the image readable to the root entrypoint. Current bases have a unified .openclaw tree."

# insert_before: insert contents of a fragment file before the anchor line
insert_before() {
  local file="$1" anchor="$2" fragment="$3"
  local name
  name="$(basename "$fragment")"

  if [ ! -f "$fragment" ]; then
    echo "  ERROR: fragment not found: $fragment"
    exit 1
  fi

  # Use python3 for reliable multi-line text insertion
  python3 -c "
import sys
anchor = sys.argv[1]
with open(sys.argv[2]) as f:
    insert = f.read()
with open(sys.argv[3]) as f:
    content = f.read()
if anchor not in content:
    print(f'ERROR: anchor not found in {sys.argv[3]}', file=sys.stderr)
    sys.exit(1)
# Insert before the first occurrence of the anchor
content = content.replace(anchor, insert + anchor, 1)
with open(sys.argv[3], 'w') as f:
    f.write(content)
" "$anchor" "$fragment" "$file"

  echo "    ✓ $name"
}

strip_disallowed_tool_installs() {
  local file="$1"
  local removed

  removed="$(python3 - "$file" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    content = f.read()

patterns = [
    re.compile(r"(?m)^RUN\s+.*@openai/codex[^\n]*$"),
    re.compile(r"(?m)^RUN\s+.*@anthropic-ai/claude-code[^\n]*$"),
    re.compile(r"(?m)^RUN\s+.*https://claude\.ai/install\.sh\s*\|\s*(?:sudo\s+)?bash[^\n]*$"),
]

removed = 0
for pattern in patterns:
    content, count = pattern.subn(
        "RUN echo 'NemoClaw cookbook: sandbox coding-agent install removed by policy'",
        content,
    )
    removed += count

remaining = []
for line in content.splitlines():
    stripped = line.lstrip()
    if stripped.startswith("#"):
        continue
    if (
        "@openai/codex" in line
        or "@anthropic-ai/claude-code" in line
        or "https://claude.ai/install.sh" in line
    ):
        remaining.append(line.strip())

if remaining:
    print(
        "ERROR: unhandled disallowed sandbox coding-agent install pattern(s):",
        file=sys.stderr,
    )
    for line in remaining:
        print(f"  {line}", file=sys.stderr)
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print(removed)
PY
)"

  if [ "$removed" -gt 0 ]; then
    echo "  Removed upstream sandbox coding-agent install(s): $removed"
  fi
  REMOVED_TOOL_INSTALLS="$removed"
}

strip_disallowed_tool_installs "$DOCKERFILE"

# Compute the integrations payload from env if not pre-set. This lets every
# caller just `source ~/.env` and let apply-patches.sh handle the payload. The
# helper reads cookbook-owned flags such as NEMOCLAW_OPENAI_HTTP_ENABLED and
# emits base64 JSON.
if [ -z "${NEMOCLAW_INTEGRATIONS_B64:-}" ]; then
  NEMOCLAW_INTEGRATIONS_B64="$(python3 "$SCRIPT_DIR/build-integrations-config.py")"
fi

if [ -n "${NEMOCLAW_INTEGRATIONS_B64:-}" ] && [ "${NEMOCLAW_INTEGRATIONS_B64:-}" != "e30=" ]; then
  if ! grep -qF "$POST_CONFIG_ANCHOR" "$DOCKERFILE"; then
    echo "ERROR: Post-config Dockerfile anchor not found: '$POST_CONFIG_ANCHOR'"
    echo "Upstream may have changed. Check the Dockerfile and update the anchor in apply-patches.sh."
    exit 1
  fi

  echo "  Applying Dockerfile integration fragment..."
  # Integrations config: must run AFTER openclaw.json creation (post-config
  # anchor). The fragment deep-merges cookbook-only config into openclaw.json.
  insert_before "$DOCKERFILE" "$POST_CONFIG_ANCHOR" "$FRAGMENTS_DIR/dockerfile-integrations"

  # Bake the computed integrations config into the Dockerfile ARG default.
  # nemoclaw onboard doesn't pass our custom ARG as --build-arg, so we set the
  # default to the actual value.
  NEMOCLAW_INTEGRATIONS_B64="$NEMOCLAW_INTEGRATIONS_B64" python3 -c "
import os, sys
path = sys.argv[1]
new = os.environ['NEMOCLAW_INTEGRATIONS_B64']
with open(path) as f: data = f.read()
old = 'ARG NEMOCLAW_INTEGRATIONS_B64=e30='
if old not in data:
    print(f'WARNING: ARG default not found in {path} — fragment may not have inserted', file=sys.stderr)
    sys.exit(0)
data = data.replace(old, f'ARG NEMOCLAW_INTEGRATIONS_B64={new}', 1)
with open(path, 'w') as f: f.write(data)
" "$DOCKERFILE"
  echo "    ✓ integrations config baked into Dockerfile"
fi

TOOLS=""
case "$NEMOCLAW_OPENAI_HTTP_ENABLED" in
  1|true|yes) TOOLS="$TOOLS + openai-http" ;;
esac
if [ "$REMOVED_TOOL_INSTALLS" -gt 0 ]; then
  TOOLS="$TOOLS + remove-codex-claude"
fi
if [ -n "$TOOLS" ]; then
  echo "  Patches applied (${TOOLS# + })."
else
  echo "  No cookbook patches were needed for this environment."
fi
