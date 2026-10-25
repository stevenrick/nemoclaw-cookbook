#!/usr/bin/env bash
# Validate that cookbook fragments can still be applied to upstream NemoClaw.
# Run locally or in CI. Clones upstream into a temp dir — no side effects.
#
# Checks:
#   1. Current upstream clone is reachable
#   2. The post-config Dockerfile anchor still exists
#   3. No-overlay patch application is a no-op
#   4. OpenAI HTTP-only patch application does not add Tavily
#   5. Tavily-only selection uses the upstream plugin without cookbook changes
#   6. Hermes and Deep Agents Code paths leave upstream images unchanged
#   7. OpenClaw-only flags fail closed for non-OpenClaw agents
#   8. The HTTP overlay composes with upstream Tavily selection
#   9. Upstream overlap audit flags patches that may now be native
#
# Usage: ./scripts/validate-patches.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOKBOOK_DIR="$(dirname "$SCRIPT_DIR")"
VALIDATION_DIR="$(mktemp -d)"
trap 'rm -rf "$VALIDATION_DIR"' EXIT

echo "Cloning upstream NemoClaw (shallow)..."
git clone --depth 1 https://github.com/NVIDIA/NemoClaw "$VALIDATION_DIR/NemoClaw" 2>&1 | tail -1

cd "$VALIDATION_DIR/NemoClaw"
echo "Upstream HEAD: $(git log --oneline -1)"
echo ""

FAILED=0

POST_CONFIG_ANCHOR="# Keep the image readable to the root entrypoint. Current bases have a unified .openclaw tree."

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
    NEMOCLAW_AGENT=openclaw \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$VALIDATION_DIR/NemoClaw" 2>&1 \
    && git diff --quiet -- Dockerfile; then
  echo "  ✓ No-overlay path leaves the Dockerfile unchanged"
else
  echo "  ✗ No-overlay path changed the Dockerfile or failed"
  FAILED=1
fi

check_http_overlay() {
  python3 - "$POST_CONFIG_ANCHOR" <<'PYTHON'
import base64
import json
import pathlib
import re
import sys

content = pathlib.Path("Dockerfile").read_text()
args = re.findall(r"^ARG NEMOCLAW_INTEGRATIONS_B64=(.+)$", content, re.MULTILINE)
assert len(args) == 1, "Expected exactly one HTTP overlay"
config = json.loads(base64.b64decode(args[0], validate=True))
assert config == {"gateway": {"http": {"endpoints": {
    "chatCompletions": {"enabled": True}, "responses": {"enabled": True},
}}}}, "HTTP endpoints were not enabled"
position = content.index("# Integration config —")
assert content.rindex("node /scripts/generate-openclaw-config.mts") < position
assert content.rindex("json.dump(cfg, open(path, 'w'), indent=2)") < position
assert position < content.index(sys.argv[1]), "Overlay must precede final permissions"
assert re.findall(r"^USER (.+)$", content[:position], re.MULTILINE)[-1] == "root"
PYTHON
}

echo "Testing OpenAI HTTP-only patch application..."
reset_upstream_dockerfile
if env \
    -u NEMOCLAW_INTEGRATIONS_B64 \
    -u NEMOCLAW_WEB_SEARCH_PROVIDER \
    -u BRAVE_API_KEY \
    -u TAVILY_API_KEY \
    NEMOCLAW_AGENT=openclaw \
    NEMOCLAW_OPENAI_HTTP_ENABLED=1 \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$VALIDATION_DIR/NemoClaw" 2>&1 \
    && check_http_overlay \
    && ! git diff -- Dockerfile | grep -qF '@openclaw/tavily-plugin'; then
  echo "  ✓ HTTP endpoints are enabled after config generation, without adding Tavily"
else
  echo "  ✗ OpenAI HTTP-only payload, placement, or isolation check failed"
  FAILED=1
fi

echo "Testing Tavily-only patch application..."
reset_upstream_dockerfile
if env \
    -u NEMOCLAW_INTEGRATIONS_B64 \
    -u NEMOCLAW_OPENAI_HTTP_ENABLED \
    -u BRAVE_API_KEY \
    -u TAVILY_API_KEY \
    NEMOCLAW_AGENT=openclaw \
    NEMOCLAW_WEB_SEARCH_PROVIDER=tavily \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$VALIDATION_DIR/NemoClaw" 2>&1 \
    && git diff --quiet -- Dockerfile \
    && grep -qE '^ADD .*--checksum=sha256:[0-9a-f]{64} .*@openclaw/tavily-plugin/-/tavily-plugin-' Dockerfile \
    && grep -qF 'install_reviewed_openclaw_plugin "@openclaw/tavily-plugin"' Dockerfile; then
  echo "  ✓ Tavily uses the upstream reviewed archive and install without cookbook changes"
else
  echo "  ✗ Tavily changed the Dockerfile or upstream reviewed archive/install is missing"
  FAILED=1
fi

for agent in hermes langchain-deepagents-code; do
  echo "Testing upstream-only $agent patch path..."
  reset_upstream_dockerfile
  if env \
      -u NEMOCLAW_INTEGRATIONS_B64 \
      -u NEMOCLAW_OPENAI_HTTP_ENABLED \
      -u BRAVE_API_KEY \
      NEMOCLAW_AGENT="$agent" \
      NEMOCLAW_WEB_SEARCH_PROVIDER=tavily \
      TAVILY_API_KEY=test-not-a-secret \
      "$COOKBOOK_DIR/scripts/apply-patches.sh" "$VALIDATION_DIR/NemoClaw" 2>&1 \
      && git diff --quiet -- Dockerfile; then
    echo "  ✓ $agent uses the unchanged upstream image"
  else
    echo "  ✗ $agent patch path changed the OpenClaw Dockerfile or failed"
    FAILED=1
  fi
done

echo "Testing OpenClaw-only overlay rejection for Hermes..."
reset_upstream_dockerfile
if ! env \
    -u NEMOCLAW_INTEGRATIONS_B64 \
    -u NEMOCLAW_WEB_SEARCH_PROVIDER \
    -u BRAVE_API_KEY \
    -u TAVILY_API_KEY \
    NEMOCLAW_AGENT=hermes \
    NEMOCLAW_OPENAI_HTTP_ENABLED=1 \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$VALIDATION_DIR/NemoClaw" >/dev/null 2>&1 \
    && git diff --quiet -- Dockerfile; then
  echo "  ✓ Hermes rejects the OpenClaw-only HTTP overlay without changing upstream"
else
  echo "  ✗ Hermes accepted an OpenClaw-only overlay or changed upstream"
  FAILED=1
fi

echo "Testing the HTTP overlay with upstream Tavily selection..."
reset_upstream_dockerfile
if env \
    -u NEMOCLAW_INTEGRATIONS_B64 \
    -u BRAVE_API_KEY \
    -u TAVILY_API_KEY \
    NEMOCLAW_AGENT=openclaw \
    NEMOCLAW_OPENAI_HTTP_ENABLED=1 \
    NEMOCLAW_WEB_SEARCH_PROVIDER=tavily \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$VALIDATION_DIR/NemoClaw" 2>&1 \
    && check_http_overlay; then
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
