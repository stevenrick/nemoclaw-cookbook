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
#   6. Hermes applies the reviewed v0.21.5 pin; Deep Agents Code stays unchanged
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
    && grep -qE '^COPY .*scripts/lib/install-openclaw-optional-plugins\.sh /scripts/lib/' Dockerfile \
    && grep -qE '^RUN .*\. /scripts/lib/install-openclaw-optional-plugins\.sh$' Dockerfile \
    && grep -qF 'install_reviewed_openclaw_plugin "@openclaw/tavily-plugin"' scripts/lib/install-openclaw-optional-plugins.sh; then
  echo "  ✓ Tavily uses the upstream reviewed archive and install without cookbook changes"
else
  echo "  ✗ Tavily changed the Dockerfile or upstream reviewed archive/install is missing"
  FAILED=1
fi

# Each agent scenario starts from a clean OpenClaw Dockerfile.
reset_upstream_dockerfile
echo "Testing reviewed Hermes v0.21.5 base-image pin..."
if git diff --quiet -- agents/hermes/Dockerfile.base agents/hermes/manifest.yaml; then
  if env \
      -u NEMOCLAW_INTEGRATIONS_B64 \
      -u NEMOCLAW_OPENAI_HTTP_ENABLED \
      -u BRAVE_API_KEY \
      -u TAVILY_API_KEY \
      NEMOCLAW_AGENT=hermes \
      NEMOCLAW_HERMES_V0215_PREVIEW=1 \
      "$COOKBOOK_DIR/scripts/apply-patches.sh" "$VALIDATION_DIR/NemoClaw" 2>&1 \
      && grep -q '^ARG HERMES_VERSION=v2026.9.24$' agents/hermes/Dockerfile.base \
      && grep -q '^ARG HERMES_SEMVER=0.21.5$' agents/hermes/Dockerfile.base \
      && grep -qF '        libssl-dev=3.5.7-1~deb13u3 ' agents/hermes/Dockerfile.base \
      && grep -q '^expected_version: "0.21.5"$' agents/hermes/manifest.yaml \
      && grep -Fq 'grep -Fqx '\''    "hindsight-client": "hindsight_client",'\'' /opt/hermes/hermes_cli/memory_setup.py' agents/hermes/Dockerfile \
      && ! grep -Fq '/opt/hermes/plugins/memory/hindsight/plugin.yaml' agents/hermes/Dockerfile \
      && grep -qF "url=\"https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/tags/\${version}\"" scripts/checks/download-hermes-source-archive.sh \
      && grep -q 'pinned Hermes v2026.9.24 source' agents/hermes/security-dependencies.patch \
      && ! grep -q 'plugins/memory/hindsight/plugin.yaml' agents/hermes/security-dependencies.patch \
      && grep -q 'task_id=oneshot_task_id' agents/hermes/security-dependencies.patch \
      && grep -q '^+.*httpx2==2.12.0' agents/hermes/security-dependencies.patch \
      && grep -q 'pinned Hermes v2026.9.24 WhatsApp bridge' agents/hermes/whatsapp-proxy.patch \
      && grep -q 'matchesAllowedSender, matchesAllowedUser, matchesInboundWhatsAppGroup' agents/hermes/whatsapp-proxy.patch \
      && grep -qF "'v2026.9.24|0.21.5|15b15ce4e6ec8ea424a081823709d1e17f0943e7b42b59597d24ebb94cbd1742|sha512-cjmXp1bhw7QEZ5Z+eRBNK74R3HRkY944tSFafFhu/SHQ/deRNbRc04gdc2KZ7cUm22/2rnl7jtcFeuhROMrdmQ==') ;;" agents/hermes/Dockerfile.base \
      && git diff --quiet -- Dockerfile; then
    echo "  ✓ Hermes base pin, manifest, and hash-verified source download advance for v0.21.5"
  else
    echo "  ✗ Hermes pin patch failed or changed the OpenClaw Dockerfile"
    FAILED=1
  fi
else
  echo "  ✗ Upstream Hermes files were already modified before the pin test"
  FAILED=1
fi

echo "Testing Hermes pin patch idempotence..."
git diff --binary > "$VALIDATION_DIR/hermes-first-apply.diff"
if env \
    -u NEMOCLAW_INTEGRATIONS_B64 \
    -u NEMOCLAW_OPENAI_HTTP_ENABLED \
    -u BRAVE_API_KEY \
    -u TAVILY_API_KEY \
    NEMOCLAW_AGENT=hermes \
    NEMOCLAW_HERMES_V0215_PREVIEW=1 \
    "$COOKBOOK_DIR/scripts/apply-patches.sh" "$VALIDATION_DIR/NemoClaw" 2>&1 \
    && grep -q '^ARG HERMES_VERSION=v2026.9.24$' agents/hermes/Dockerfile.base \
    && git diff --binary | cmp -s "$VALIDATION_DIR/hermes-first-apply.diff" -; then
  echo "  ✓ Hermes pin patch can be reapplied without changing the release identity"
else
  echo "  ✗ Hermes pin patch is not idempotent"
  FAILED=1
fi

for agent in hermes langchain-deepagents-code; do
  echo "Testing upstream-only $agent patch path..."
  reset_upstream_dockerfile
  git diff --binary > "$VALIDATION_DIR/before-default-agent.diff"
  if env \
      -u NEMOCLAW_INTEGRATIONS_B64 \
      -u NEMOCLAW_HERMES_V0215_PREVIEW \
      -u NEMOCLAW_OPENAI_HTTP_ENABLED \
      -u BRAVE_API_KEY \
      NEMOCLAW_AGENT="$agent" \
      NEMOCLAW_WEB_SEARCH_PROVIDER=tavily \
      TAVILY_API_KEY=test-not-a-secret \
      "$COOKBOOK_DIR/scripts/apply-patches.sh" "$VALIDATION_DIR/NemoClaw" 2>&1 \
      && git diff --quiet -- Dockerfile \
      && git diff --binary | cmp -s "$VALIDATION_DIR/before-default-agent.diff" -; then
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
