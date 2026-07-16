#!/usr/bin/env bash
# Apply cookbook customizations to upstream NemoClaw files using modular fragments.
#
# Usage: apply-patches.sh <nemoclaw-dir>
#
# Reads cookbook-only integration flags from the environment. Upstream NemoClaw
# owns core agent tooling, OpenShell installation, OpenClaw versioning, and web
# search. The cookbook only patches the gaps listed in UPSTREAM.md.
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

# Integration flags
NEMOCLAW_OPENAI_HTTP_ENABLED="${NEMOCLAW_OPENAI_HTTP_ENABLED:-}"

DOCKERFILE="$NEMOCLAW_DIR/Dockerfile"

# ── Dockerfile modifications ────────────────────────────────────────
# Post-config anchor: fragments inserted here run as root, AFTER all upstream
# openclaw.json writes (generate-openclaw-config.py, openclaw doctor, gateway
# token clear, chown to sandbox:sandbox) and BEFORE the integrity hash pin, so
# our changes are covered by the build-time sha256.
POST_CONFIG_ANCHOR="# Pin config hash at build time so the entrypoint can verify integrity."

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
if [ -n "$TOOLS" ]; then
  echo "  Patches applied (${TOOLS# + })."
else
  echo "  No cookbook patches were needed for this environment."
fi
