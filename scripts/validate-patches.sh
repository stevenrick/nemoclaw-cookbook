#!/usr/bin/env bash
# Validate that patches still apply cleanly against upstream NemoClaw.
# Run locally or in CI. Clones upstream into a temp dir — no side effects.
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

FAILED=0
for patch in "$COOKBOOK_DIR"/patches/*.patch; do
  name="$(basename "$patch")"
  if git apply --check --3way "$patch" 2>/dev/null; then
    echo "  ✓ $name"
  else
    echo "  ✗ $name — FAILED to apply"
    FAILED=1
  fi
done

if [ "$FAILED" -eq 1 ]; then
  echo ""
  echo "One or more patches need refreshing."
  echo "Run: claude /refresh-patches"
  exit 1
else
  echo ""
  echo "All patches apply cleanly."
fi
