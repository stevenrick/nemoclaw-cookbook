#!/usr/bin/env bash
# Validate that cookbook fragments can still be applied to upstream NemoClaw.
# Run locally or in CI. Clones upstream into a temp dir — no side effects.
#
# Checks:
#   1. Current upstream clone is reachable
#   2. The post-config Dockerfile anchor still exists
#   3. Full apply-patches.sh runs with all cookbook integrations enabled
#   4. Upstream overlap audit flags patches that may now be native
#
# Usage: ./scripts/validate-patches.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Cloning upstream NemoClaw (shallow)..."
git clone --depth 1 https://github.com/NVIDIA/NemoClaw "$TMPDIR/NemoClaw" 2>&1 | tail -1

cd "$TMPDIR/NemoClaw"
echo "Upstream HEAD: $(git log --oneline -1)"
echo ""

FAILED=0

POST_CONFIG_ANCHOR="# Pin config hash at build time so the entrypoint can verify integrity."
POLICY="nemoclaw-blueprint/policies/openclaw-sandbox.yaml"

echo "Checking Dockerfile post-config anchor..."
if grep -qF "$POST_CONFIG_ANCHOR" Dockerfile; then
  echo "  ✓ Anchor found: '$POST_CONFIG_ANCHOR'"
else
  echo "  ✗ Anchor NOT found: '$POST_CONFIG_ANCHOR'"
  echo "    Update scripts/apply-patches.sh and dockerfile-integrations."
  FAILED=1
fi

echo "Checking policy shape..."
if grep -qE "^network_policies:" "$POLICY" 2>/dev/null; then
  echo "  ✓ Policy has network_policies"
else
  echo "  ✗ Policy shape changed: network_policies not found"
  FAILED=1
fi

echo "Running apply-patches.sh with all cookbook integrations enabled..."
pip3 install --quiet 'pyyaml>=6,<7' 2>/dev/null || pip install --quiet 'pyyaml>=6,<7' 2>/dev/null || true

if TAVILY_API_KEY=dummy NEMOCLAW_OPENAI_HTTP_ENABLED=1 "$COOKBOOK_DIR/scripts/apply-patches.sh" "$TMPDIR/NemoClaw" 2>&1; then
  echo "  ✓ Fragments applied successfully"
else
  echo "  ✗ Fragment application failed"
  FAILED=1
fi

echo ""
echo "Upstream overlap audit..."
git checkout -- Dockerfile "$POLICY" scripts/nemoclaw-start.sh 2>/dev/null || true

OVERLAPS=0

if grep -Rqi "TAVILY_API_KEY\|api.tavily.com\|provider.*tavily" scripts src nemoclaw-blueprint docs 2>/dev/null; then
  echo "  ⚠ Upstream now references Tavily — review Tavily Dockerfile/config/policy fragments"
  OVERLAPS=1
fi

if grep -Rqi "NEMOCLAW_OPENAI_HTTP_ENABLED" scripts src nemoclaw-blueprint docs 2>/dev/null; then
  echo "  ⚠ Upstream now exposes NEMOCLAW_OPENAI_HTTP_ENABLED — review OpenAI HTTP config patch"
  OVERLAPS=1
fi

if grep -Rqi '"chatCompletions".*"enabled"\|"responses".*"enabled"' scripts/generate-openclaw-config.py src docs 2>/dev/null; then
  echo "  ⚠ Upstream appears to configure OpenAI-compatible HTTP endpoints — review OpenAI HTTP config patch"
  OVERLAPS=1
fi

if [ "$OVERLAPS" -eq 0 ]; then
  echo "  ✓ No obvious overlaps for remaining cookbook patches"
else
  echo ""
  echo "  Overlaps found. Upstream may now handle things we still patch."
  echo "  Review the flagged fragments and remove any patch that upstream has absorbed."
fi

echo ""
if [ "$FAILED" -eq 1 ]; then
  echo "VALIDATION FAILED — fragments need updating."
  exit 1
else
  echo "All checks passed."
fi
