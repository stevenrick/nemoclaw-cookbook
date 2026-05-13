#!/usr/bin/env bash
# Apply cookbook customizations to upstream NemoClaw files using modular fragments.
#
# Usage: apply-patches.sh <nemoclaw-dir>
#
# Reads INSTALL_CLAUDE_CODE and INSTALL_CODEX from environment (default: true).
# Modifies <nemoclaw-dir>/Dockerfile and policy YAML in place.
#
# Unlike git patches, this approach:
#   - Only needs one anchor line per file (not 3 lines of context)
#   - Composes fragments independently (add/remove tools without conflicts)
#   - Handles upstream YAML restructuring gracefully
set -euo pipefail

NEMOCLAW_DIR="${1:?Usage: apply-patches.sh <nemoclaw-dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"
FRAGMENTS_DIR="$COOKBOOK_DIR/patches/fragments"

INSTALL_CLAUDE_CODE="${INSTALL_CLAUDE_CODE:-true}"
INSTALL_CODEX="${INSTALL_CODEX:-true}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-}"

# Integration flags
TAVILY_API_KEY="${TAVILY_API_KEY:-}"

DOCKERFILE="$NEMOCLAW_DIR/Dockerfile"
POLICY="$NEMOCLAW_DIR/nemoclaw-blueprint/policies/openclaw-sandbox.yaml"

# ── Dockerfile modifications ────────────────────────────────────────
# Pre-config anchor: fragments inserted here run as root, before openclaw.json exists.
ANCHOR="# Set up blueprint for local resolution"
# Post-config anchor: fragments inserted here run as root, AFTER all upstream
# openclaw.json writes (generate-openclaw-config.py, openclaw doctor, gateway
# token clear, chown to sandbox:sandbox) and BEFORE the integrity hash pin, so
# our changes are covered by the build-time sha256.
POST_CONFIG_ANCHOR="# Pin config hash at build time so the entrypoint can verify integrity."

if ! grep -qF "$ANCHOR" "$DOCKERFILE"; then
  echo "ERROR: Dockerfile anchor not found: '$ANCHOR'"
  echo "Upstream may have changed. Check the Dockerfile and update the anchor in apply-patches.sh."
  exit 1
fi

if ! grep -qF "$POST_CONFIG_ANCHOR" "$DOCKERFILE"; then
  echo "ERROR: Post-config Dockerfile anchor not found: '$POST_CONFIG_ANCHOR'"
  echo "Upstream may have changed. Check the Dockerfile and update the anchor in apply-patches.sh."
  exit 1
fi

echo "  Applying Dockerfile fragments..."

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

# Core: always applied
insert_before "$DOCKERFILE" "$ANCHOR" "$FRAGMENTS_DIR/dockerfile-core"

# Integrations config: must run AFTER openclaw.json creation (post-config anchor).
# The fragment merges search config into the existing openclaw.json.
# No-op when NEMOCLAW_INTEGRATIONS_B64 is empty.
insert_before "$DOCKERFILE" "$POST_CONFIG_ANCHOR" "$FRAGMENTS_DIR/dockerfile-integrations"

# Bake the computed integrations config into the Dockerfile ARG default.
# nemoclaw onboard doesn't pass our custom ARG as --build-arg, so we set the
# default to the actual value. The fragment's no-op guard handles empty/e30=.
if [ -n "${NEMOCLAW_INTEGRATIONS_B64:-}" ] && [ "${NEMOCLAW_INTEGRATIONS_B64:-}" != "e30=" ]; then
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

# Entrypoint: make /sandbox/.env actually take effect.
# Upstream's nemoclaw-start.sh chmods .env to 600 but never sources it, so the
# gateway process never sees secrets the cookbook injects via setup.sh Step 8.
# Plugins that read process.env (Tavily etc.) end up uncredentialed. Patch the
# entrypoint to source .env in the same block where it's chmod'd. Idempotent —
# the marker check prevents double-injection on re-applies.
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

# Claude Code: optional
if [ "$INSTALL_CLAUDE_CODE" = "true" ]; then
  insert_before "$DOCKERFILE" "$ANCHOR" "$FRAGMENTS_DIR/dockerfile-claude-code"
fi

# Codex: optional
if [ "$INSTALL_CODEX" = "true" ]; then
  insert_before "$DOCKERFILE" "$ANCHOR" "$FRAGMENTS_DIR/dockerfile-codex"
fi

# OpenClaw version override (experimental): rebuild sandbox-base locally
# instead of using the GHCR image, with the specified OpenClaw version.
# This rebuilds the ENTIRE base image so everything stays in sync —
# config, UI, plugins, auth model all match the target version.
if [ -n "$OPENCLAW_VERSION" ]; then
  DOCKERFILE_BASE="$NEMOCLAW_DIR/Dockerfile.base"
  if [ ! -f "$DOCKERFILE_BASE" ]; then
    echo "  ERROR: Dockerfile.base not found at $DOCKERFILE_BASE"
    echo "  OPENCLAW_VERSION requires the NemoClaw source checkout."
    exit 1
  fi
  echo "  Building sandbox-base with OpenClaw $OPENCLAW_VERSION (this takes a few minutes)..."
  OPENCLAW_VERSION="$OPENCLAW_VERSION" python3 -c "
import os, re, sys
path = sys.argv[1]
ver = os.environ['OPENCLAW_VERSION']
with open(path) as f: data = f.read()
data = re.sub(r'npm install -g openclaw@[^ ]*', f'npm install -g openclaw@{ver}', data)
with open(path, 'w') as f: f.write(data)
" "$DOCKERFILE_BASE"
  docker build -f "$DOCKERFILE_BASE" -t ghcr.io/nvidia/nemoclaw/sandbox-base:latest "$NEMOCLAW_DIR"
  echo "    ✓ sandbox-base rebuilt with OpenClaw $OPENCLAW_VERSION"
fi

# ── Policy modifications ────────────────────────────────────────────
echo "  Applying policy fragments..."

# Check python3 + PyYAML availability
if ! python3 -c "import yaml" 2>/dev/null; then
  echo "  Installing PyYAML for policy merging..."
  pip3 install --quiet 'pyyaml>=6,<7' 2>/dev/null || pip install --quiet 'pyyaml>=6,<7'
fi

# Collect applicable policy fragments
POLICY_FRAGMENTS=("$FRAGMENTS_DIR/policy-core.yaml")

if [ "$INSTALL_CLAUDE_CODE" = "true" ]; then
  POLICY_FRAGMENTS+=("$FRAGMENTS_DIR/policy-claude-code.yaml")
fi

if [ "$INSTALL_CODEX" = "true" ]; then
  POLICY_FRAGMENTS+=("$FRAGMENTS_DIR/policy-codex.yaml")
fi

# Web search policy
if [ -n "$TAVILY_API_KEY" ]; then
  POLICY_FRAGMENTS+=("$FRAGMENTS_DIR/policy-tavily.yaml")
fi

python3 "$SCRIPT_DIR/merge-policy.py" "$POLICY" "${POLICY_FRAGMENTS[@]}"

TOOLS=""
[ "$INSTALL_CLAUDE_CODE" = "true" ] && TOOLS="$TOOLS + claude-code"
[ "$INSTALL_CODEX" = "true" ] && TOOLS="$TOOLS + codex"
[ -n "$TAVILY_API_KEY" ] && TOOLS="$TOOLS + tavily"
echo "  Patches applied (core${TOOLS})."
