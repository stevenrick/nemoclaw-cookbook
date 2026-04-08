#!/usr/bin/env bash
# Validate that cookbook fragments can still be applied to upstream NemoClaw.
# Run locally or in CI. Clones upstream into a temp dir — no side effects.
#
# Checks:
#   1. Dockerfile anchor line exists in upstream
#   2. Policy section anchors exist for all fragment targets
#   3. Full apply-patches.sh runs without errors
#   4. Upstream overlap audit — flags if upstream now provides something we add
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

# ── Check 1: Dockerfile anchor ──────────────────────────────────────
ANCHOR="# Set up blueprint for local resolution"
echo "Checking Dockerfile anchor..."
if grep -qF "$ANCHOR" Dockerfile; then
  echo "  ✓ Anchor found: '$ANCHOR'"
else
  echo "  ✗ Anchor NOT found: '$ANCHOR'"
  echo "    Update the ANCHOR in scripts/apply-patches.sh to match upstream."
  FAILED=1
fi

# ── Check 2: Policy section anchors ─────────────────────────────────
POLICY="nemoclaw-blueprint/policies/openclaw-sandbox.yaml"
echo "Checking policy section anchors..."
for section in claude_code nvidia github; do
  if grep -qE "^  ${section}:" "$POLICY" 2>/dev/null; then
    echo "  ✓ Section: $section"
  else
    echo "  ✗ Section NOT found: $section"
    echo "    Upstream may have renamed or removed this section."
    FAILED=1
  fi
done

# ── Check 3: Full apply test ────────────────────────────────────────
echo "Running full apply-patches.sh (all tools enabled)..."
# Ensure PyYAML is available
pip3 install --quiet 'pyyaml>=6,<7' 2>/dev/null || pip install --quiet 'pyyaml>=6,<7' 2>/dev/null || true

if INSTALL_CLAUDE_CODE=true INSTALL_CODEX=true "$COOKBOOK_DIR/scripts/apply-patches.sh" "$TMPDIR/NemoClaw" 2>&1; then
  echo "  ✓ Fragments applied successfully"
else
  echo "  ✗ Fragment application failed"
  FAILED=1
fi

# ── Check 4: Upstream overlap audit ─────────────────────────────────
# Check if upstream now provides things we previously had to add.
# This doesn't fail the build — it's informational.
echo ""
echo "Upstream overlap audit..."

# Reset to clean upstream for comparison
git checkout -- Dockerfile "$POLICY" 2>/dev/null

OVERLAPS=0

# Check if upstream now installs Claude Code in Dockerfile
if grep -q "claude.ai/install.sh\|/usr/local/bin/claude" Dockerfile; then
  echo "  ⚠ Upstream Dockerfile now references Claude Code — review dockerfile-claude-code fragment"
  OVERLAPS=1
fi

# Check if upstream now installs Codex in Dockerfile
if grep -q "@openai/codex\|/usr/local/bin/codex" Dockerfile; then
  echo "  ⚠ Upstream Dockerfile now references Codex — review dockerfile-codex fragment"
  OVERLAPS=1
fi

# Check if upstream now has git HTTPS config in Dockerfile
if grep -q "insteadOf.*git@github.com" Dockerfile; then
  echo "  ⚠ Upstream Dockerfile now has git HTTPS config — review dockerfile-core fragment"
  OVERLAPS=1
fi

# Check if upstream policy now has our auth endpoints
if grep -q "platform.claude.com" "$POLICY"; then
  echo "  ⚠ Upstream policy now has platform.claude.com — review policy-claude-code.yaml fragment"
  OVERLAPS=1
fi

if grep -q "api.openai.com" "$POLICY"; then
  echo "  ⚠ Upstream policy now has api.openai.com — review policy-codex.yaml fragment"
  OVERLAPS=1
fi

if grep -q "codeload.github.com" "$POLICY"; then
  echo "  ⚠ Upstream policy now has codeload.github.com — review policy-core.yaml fragment"
  OVERLAPS=1
fi

if [ "$OVERLAPS" -eq 0 ]; then
  echo "  ✓ No overlaps — all cookbook additions are still unique"
else
  echo ""
  echo "  Overlaps found. Upstream may now handle things we previously patched."
  echo "  Review the flagged fragments and remove any that upstream now covers."
  echo "  Run: claude /refresh-patches"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
if [ "$FAILED" -eq 1 ]; then
  echo "VALIDATION FAILED — fragments need updating."
  echo "Run: claude /refresh-patches"
  exit 1
else
  echo "All checks passed."
fi
