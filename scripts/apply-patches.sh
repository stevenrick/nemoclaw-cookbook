#!/usr/bin/env bash
# Apply cookbook customizations to upstream NemoClaw files using modular fragments.
#
# Usage: apply-patches.sh <nemoclaw-dir>
#
# Reads cookbook-only integration flags from the environment. Upstream NemoClaw
# owns core agent tooling, OpenShell installation, OpenClaw versioning, and Brave
# Search. The cookbook only patches the gaps listed in UPSTREAM.md.
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
TAVILY_API_KEY="${TAVILY_API_KEY:-}"
NEMOCLAW_OPENAI_HTTP_ENABLED="${NEMOCLAW_OPENAI_HTTP_ENABLED:-}"

DOCKERFILE="$NEMOCLAW_DIR/Dockerfile"
POLICY="$NEMOCLAW_DIR/nemoclaw-blueprint/policies/openclaw-sandbox.yaml"

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
# helper reads TAVILY_API_KEY, NEMOCLAW_OPENAI_HTTP_ENABLED, etc. and emits
# base64 JSON.
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

# Entrypoint: make /sandbox/.env actually take effect for the cookbook-only
# Tavily path. Upstream handles native Brave credentials through OpenShell
# provider placeholders; Tavily still needs process.env until it is upstreamed.
if [ -n "$TAVILY_API_KEY" ]; then
  ENTRYPOINT_SH="$NEMOCLAW_DIR/scripts/nemoclaw-start.sh"
  if [ -f "$ENTRYPOINT_SH" ]; then
    python3 -c "
import sys
path = sys.argv[1]
marker = '# COOKBOOK: source /sandbox/.env'
with open(path) as f: data = f.read()
if marker in data:
    sys.exit(0)
needle = '''if [ -f .env ]; then
  if ! chmod 600 .env 2>/dev/null; then
    echo \"[SECURITY WARNING] Could not restrict .env permissions — file may be world-readable (read-only filesystem)\" >&2
  fi
fi'''
replacement = '''if [ -f .env ]; then
  if ! chmod 600 .env 2>/dev/null; then
    echo \"[SECURITY WARNING] Could not restrict .env permissions — file may be world-readable (read-only filesystem)\" >&2
  fi
  # COOKBOOK: source /sandbox/.env so plugin secrets (TAVILY_API_KEY, etc.)
  # reach the gateway process env. Upstream only chmods; it never loads.
  # shellcheck disable=SC1091
  set -a; . ./.env 2>/dev/null || true; set +a
fi'''
if needle not in data:
    print('WARNING: entrypoint .env block anchor not found — skipping env-loader patch', file=sys.stderr)
    sys.exit(0)
with open(path, 'w') as f: f.write(data.replace(needle, replacement, 1))
print('  ✓ nemoclaw-start.sh patched to source /sandbox/.env')
" "$ENTRYPOINT_SH"
  fi
fi

# ── Policy modifications ────────────────────────────────────────────
# Collect applicable policy fragments
POLICY_FRAGMENTS=()

# Web search policy
if [ -n "$TAVILY_API_KEY" ]; then
  POLICY_FRAGMENTS+=("$FRAGMENTS_DIR/policy-tavily.yaml")
fi

if [ "${#POLICY_FRAGMENTS[@]}" -gt 0 ]; then
  echo "  Applying policy fragments..."

  # Check python3 + PyYAML availability
  if ! python3 -c "import yaml" 2>/dev/null; then
    echo "  Installing PyYAML for policy merging..."
    pip3 install --quiet 'pyyaml>=6,<7' 2>/dev/null || pip install --quiet 'pyyaml>=6,<7'
  fi

  python3 "$SCRIPT_DIR/merge-policy.py" "$POLICY" "${POLICY_FRAGMENTS[@]}"
else
  echo "  No policy fragments needed."
fi

TOOLS=""
[ -n "$TAVILY_API_KEY" ] && TOOLS="$TOOLS + tavily"
case "$NEMOCLAW_OPENAI_HTTP_ENABLED" in
  1|true|yes) TOOLS="$TOOLS + openai-http" ;;
esac
if [ -n "$TOOLS" ]; then
  echo "  Patches applied (${TOOLS# + })."
else
  echo "  No cookbook patches were needed for this environment."
fi
