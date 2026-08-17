#!/usr/bin/env bash
# Validate that cookbook fragments can still be applied to upstream NemoClaw.
# Run locally or in CI. Clones upstream into a temp dir — no side effects.
#
# Checks:
#   1. Current upstream clone is reachable
#   2. The post-config Dockerfile anchor still exists
#   3. No-overlay patch application is a no-op
#   4. OpenAI HTTP-only patch application does not add Tavily
#   5. Tavily-only patch application adds the reviewed offline archive and install
#   6. All remaining overlays compose successfully
#   7. Upstream overlap audit flags patches that may now be native
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

echo "Checking Dockerfile post-config anchor..."
if grep -qF "$POST_CONFIG_ANCHOR" Dockerfile; then
  echo "  ✓ Anchor found: '$POST_CONFIG_ANCHOR'"
else
  echo "  ✗ Anchor NOT found: '$POST_CONFIG_ANCHOR'"
  echo "    Update scripts/apply-patches.sh and dockerfile-integrations."
  FAILED=1
fi

reset_upstream_dockerfile() {
  git checkout -- Dockerfile 2>/dev/null
}

echo "Testing no-overlay patch application..."
reset_upstream_dockerfile
if env \
    -u NEMOCLAW_INTEGRATIONS_B64 \
    -u NEMOCLAW_OPENAI_HTTP_ENABLED \
    -u NEMOCLAW_WEB_SEARCH_PROVIDER \
    -u BRAVE_API_KEY \
    -u TAVILY_API_KEY \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$TMPDIR/NemoClaw" 2>&1 \
    && git diff --quiet -- Dockerfile; then
  echo "  ✓ No-overlay path leaves the Dockerfile unchanged"
else
  echo "  ✗ No-overlay path changed the Dockerfile or failed"
  FAILED=1
fi

echo "Testing OpenAI HTTP-only patch application..."
reset_upstream_dockerfile
if env \
    -u NEMOCLAW_INTEGRATIONS_B64 \
    -u NEMOCLAW_WEB_SEARCH_PROVIDER \
    -u BRAVE_API_KEY \
    -u TAVILY_API_KEY \
    NEMOCLAW_OPENAI_HTTP_ENABLED=1 \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$TMPDIR/NemoClaw" 2>&1 \
    && ! git diff -- Dockerfile | grep -qF '@openclaw/tavily-plugin'; then
  echo "  ✓ OpenAI HTTP-only path does not add Tavily"
else
  echo "  ✗ OpenAI HTTP-only path failed or added Tavily"
  FAILED=1
fi

echo "Testing Tavily-only patch application..."
reset_upstream_dockerfile
if env \
    -u NEMOCLAW_INTEGRATIONS_B64 \
    -u NEMOCLAW_OPENAI_HTTP_ENABLED \
    -u BRAVE_API_KEY \
    -u TAVILY_API_KEY \
    NEMOCLAW_WEB_SEARCH_PROVIDER=tavily \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$TMPDIR/NemoClaw" 2>&1 \
    && grep -qF -- '--checksum=sha256:c8d7c2fb40b0c6a3f8ad99e927c1851ef501bef89ce049e88ab79083ff6dcb09' Dockerfile \
    && grep -qF 'archive_name="tavily-plugin-2026.7.1.tgz"' Dockerfile \
    && grep -qF 'install_reviewed_openclaw_plugin "@openclaw/tavily-plugin"' Dockerfile; then
  echo "  ✓ Tavily-only path adds the reviewed offline archive and install"
else
  echo "  ✗ Tavily-only path failed its reviewed archive/install checks"
  FAILED=1
fi

echo "Testing all remaining cookbook overlays together..."
reset_upstream_dockerfile
if env \
    -u NEMOCLAW_INTEGRATIONS_B64 \
    -u BRAVE_API_KEY \
    -u TAVILY_API_KEY \
    NEMOCLAW_OPENAI_HTTP_ENABLED=1 \
    NEMOCLAW_WEB_SEARCH_PROVIDER=tavily \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$TMPDIR/NemoClaw" 2>&1; then
  echo "  ✓ Remaining overlays compose successfully"
else
  echo "  ✗ Combined overlay application failed"
  FAILED=1
fi

echo ""
echo "Upstream overlap audit..."
reset_upstream_dockerfile

OVERLAPS=0

if grep -Rqi "NEMOCLAW_OPENAI_HTTP_ENABLED" scripts src nemoclaw-blueprint docs 2>/dev/null; then
  echo "  ⚠ Upstream now exposes NEMOCLAW_OPENAI_HTTP_ENABLED — review OpenAI HTTP config patch"
  OVERLAPS=1
fi

if grep -Rqi '"chatCompletions".*"enabled"\|"responses".*"enabled"' scripts src docs 2>/dev/null; then
  echo "  ⚠ Upstream appears to configure OpenAI-compatible HTTP endpoints — review OpenAI HTTP config patch"
  OVERLAPS=1
fi

if grep -qF '@openclaw/tavily-plugin' Dockerfile; then
  echo "  ⚠ Upstream now includes the Tavily plugin — review and likely remove the cookbook Tavily install patch"
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
