#!/usr/bin/env bash
# Apply cookbook customizations to upstream NemoClaw files using modular fragments.
#
# Usage: apply-patches.sh <nemoclaw-dir>
#
# Reads cookbook-only integration flags from the environment. Upstream NemoClaw
# owns core agent tooling, OpenShell installation, and web search. The cookbook
# carries a reviewed Hermes release identity so its upstream updater can pin the
# requested Hermes release; other Hermes runtime behavior remains upstream.
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

if [ "$ACTIVE_AGENT" = "hermes" ] && [ "${NEMOCLAW_HERMES_V0215_PREVIEW:-0}" = "1" ]; then
  case "$NEMOCLAW_OPENAI_HTTP_ENABLED" in
    1|true|yes)
      echo "ERROR: NEMOCLAW_OPENAI_HTTP_ENABLED is an OpenClaw-only cookbook overlay." >&2
      echo "Hermes already exposes its upstream OpenAI-compatible API; leave this flag unset." >&2
      exit 1
      ;;
  esac

  DOCKERFILE_BASE="$NEMOCLAW_DIR/agents/hermes/Dockerfile.base"
  DOCKERFILE_HERMES="$NEMOCLAW_DIR/agents/hermes/Dockerfile"
  MANIFEST="$NEMOCLAW_DIR/agents/hermes/manifest.yaml"
  SECURITY_PATCH="$NEMOCLAW_DIR/agents/hermes/security-dependencies.patch"
  WHATSAPP_PATCH="$NEMOCLAW_DIR/agents/hermes/whatsapp-proxy.patch"
  PIN_FRAGMENT="$FRAGMENTS_DIR/hermes-v0.21.5-release-identity.txt"
  SECURITY_PATCH_FRAGMENT="$FRAGMENTS_DIR/hermes-v0.21.5-security-dependencies.patch"
  WHATSAPP_PATCH_FRAGMENT="$FRAGMENTS_DIR/hermes-v0.21.5-whatsapp-proxy.patch"
  DOWNLOAD_PATCH_FRAGMENT="$FRAGMENTS_DIR/hermes-codeload-source-download.patch"
  DOCKERFILE_PATCH_FRAGMENT="$FRAGMENTS_DIR/hermes-v0.21.5-dockerfile-compat.patch"

  if [ ! -f "$DOCKERFILE_BASE" ] || [ ! -f "$DOCKERFILE_HERMES" ] || [ ! -f "$MANIFEST" ] \
    || [ ! -f "$SECURITY_PATCH" ] || [ ! -f "$WHATSAPP_PATCH" ] \
    || [ ! -f "$PIN_FRAGMENT" ] || [ ! -f "$SECURITY_PATCH_FRAGMENT" ] \
    || [ ! -f "$WHATSAPP_PATCH_FRAGMENT" ] || [ ! -f "$DOWNLOAD_PATCH_FRAGMENT" ] \
    || [ ! -f "$DOCKERFILE_PATCH_FRAGMENT" ]; then
    echo "ERROR: Hermes pin target or cookbook identity fragment is missing." >&2
    exit 1
  fi

  if git -C "$NEMOCLAW_DIR" apply --check "$DOCKERFILE_PATCH_FRAGMENT" 2>/dev/null; then
    git -C "$NEMOCLAW_DIR" apply "$DOCKERFILE_PATCH_FRAGMENT"
    echo "  Hermes final Dockerfile now checks the v0.21.5 Hindsight catalog layout."
  elif grep -Fq 'grep -Fqx '\''    "hindsight-client": "hindsight_client",'\'' /opt/hermes/hermes_cli/memory_setup.py' "$DOCKERFILE_HERMES"; then
    : # Already patched.
  else
    echo "ERROR: Hermes final Dockerfile differs from the reviewed v0.21.3 baseline." >&2
    exit 1
  fi

  DOWNLOAD_HELPER="$NEMOCLAW_DIR/scripts/checks/download-hermes-source-archive.sh"
  if [ ! -f "$DOWNLOAD_HELPER" ]; then
    echo "ERROR: Hermes source archive downloader is missing." >&2
    exit 1
  fi
  if git -C "$NEMOCLAW_DIR" apply --check "$DOWNLOAD_PATCH_FRAGMENT" 2>/dev/null; then
    git -C "$NEMOCLAW_DIR" apply "$DOWNLOAD_PATCH_FRAGMENT"
    echo "  Hermes source archive downloader uses the directly hash-verified codeload endpoint."
  elif grep -qF "url=\"https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/tags/\${version}\"" "$DOWNLOAD_HELPER"; then
    : # Already patched.
  else
    echo "ERROR: Hermes source archive downloader differs from the reviewed upstream version." >&2
    exit 1
  fi

  python3 - "$DOCKERFILE_BASE" "$MANIFEST" "$PIN_FRAGMENT" "$SECURITY_PATCH" "$SECURITY_PATCH_FRAGMENT" "$WHATSAPP_PATCH" "$WHATSAPP_PATCH_FRAGMENT" <<'PY'
import hashlib
import pathlib
import sys

dockerfile = pathlib.Path(sys.argv[1])
manifest = pathlib.Path(sys.argv[2])
fragment = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").strip()
security_patch = pathlib.Path(sys.argv[4])
security_patch_fragment = pathlib.Path(sys.argv[5]).read_bytes()
whatsapp_patch = pathlib.Path(sys.argv[6])
whatsapp_patch_fragment = pathlib.Path(sys.argv[7]).read_bytes()
content = dockerfile.read_text(encoding="utf-8")
manifest_content = manifest.read_text(encoding="utf-8")
security_patch_bytes = security_patch.read_bytes()
whatsapp_patch_bytes = whatsapp_patch.read_bytes()
old_security_patch_sha = "16233ad16dceb7795a62203541d51f83f8ce3738a160c6e2239dc610b6c6903e"
# Upstream added HTTP/Sharp dependency fixes after the original baseline.
updated_security_patch_sha = "d983166eeb10b3a0ed57cae376f3a80d145dd0b5ce5166f388c5ddb805280e2e"
target_security_patch_sha = "a0625fde027e2c8fe0e2853ac0473b3724265b36b6f6a1ed0d165cbdd3fba0d2"
old_whatsapp_patch_sha = "db4020bf12cfe170388bbae4aa5a20c5fb6e18f41d85716d6efb2e23b05c5f7a"
target_whatsapp_patch_sha = "fe3045c1f2dc3714a90cfbbaa85e704c691ee127dc570effea583993ed1fc545"

security_patch_sha = hashlib.sha256(security_patch_bytes).hexdigest()
if security_patch_sha in {old_security_patch_sha, updated_security_patch_sha}:
    security_patch_needs_update = True
elif security_patch_sha != target_security_patch_sha:
    raise SystemExit("ERROR: Hermes security patch differs from the reviewed v0.21.3 source; refusing to replace it.")
else:
    security_patch_needs_update = False

whatsapp_patch_sha = hashlib.sha256(whatsapp_patch_bytes).hexdigest()
if whatsapp_patch_sha == old_whatsapp_patch_sha:
    whatsapp_patch_needs_update = True
elif whatsapp_patch_sha != target_whatsapp_patch_sha:
    raise SystemExit("ERROR: Hermes WhatsApp patch differs from the reviewed v0.21.3 source; refusing to replace it.")
else:
    whatsapp_patch_needs_update = False

def write_hermes_source_patches():
    if security_patch_needs_update:
        security_patch.write_bytes(security_patch_fragment)
        print("  Hermes source patch adapted for v0.21.5.")
    if whatsapp_patch_needs_update:
        whatsapp_patch.write_bytes(whatsapp_patch_fragment)
        print("  Hermes WhatsApp patch adapted for v0.21.5.")

old = {
    "# Calver tag v2026.9.14 = Hermes Agent v0.21.3.",
    "ARG HERMES_VERSION=v2026.9.14",
    "ARG HERMES_SEMVER=0.21.3",
    "ARG HERMES_TARBALL_SHA256=47df72ebd3f9c96d806a94541163f7fe7d7ce5b84f85c1d3787e6dfeea1d7834",
    "ARG HERMES_NPM_INTEGRITY=sha512-LvPt2/1z6hm4pTRJu34F6uAkBVSlSt94QeZp8fMBLFqASU9/wv7iMODSGMzF1WmrpNENXYGMnWN8s9hi/EUM5Q==",
    "'v2026.9.14|0.21.3|47df72ebd3f9c96d806a94541163f7fe7d7ce5b84f85c1d3787e6dfeea1d7834|sha512-LvPt2/1z6hm4pTRJu34F6uAkBVSlSt94QeZp8fMBLFqASU9/wv7iMODSGMzF1WmrpNENXYGMnWN8s9hi/EUM5Q==') ;; \\",
}
target = {
    "# Calver tag v2026.9.24 = Hermes Agent v0.21.5.",
    "ARG HERMES_VERSION=v2026.9.24",
    "ARG HERMES_SEMVER=0.21.5",
    "ARG HERMES_TARBALL_SHA256=15b15ce4e6ec8ea424a081823709d1e17f0943e7b42b59597d24ebb94cbd1742",
    "ARG HERMES_NPM_INTEGRITY=sha512-cjmXp1bhw7QEZ5Z+eRBNK74R3HRkY944tSFafFhu/SHQ/deRNbRc04gdc2KZ7cUm22/2rnl7jtcFeuhROMrdmQ==",
    "        libssl-dev=3.5.7-1~deb13u3 \\",
}

release_target = {line for line in target if not line.startswith("        libssl-dev=")}
old_libssl = "        libssl-dev=3.5.7-1~deb13u2 " + chr(92)
new_libssl = "        libssl-dev=3.5.7-1~deb13u3 " + chr(92)

if all(line in content for line in release_target) and 'expected_version: "0.21.5"' in manifest_content:
    if old_libssl in content:
        content = content.replace(old_libssl, new_libssl, 1)
    if new_libssl not in content:
        raise SystemExit("ERROR: expected the reviewed Hermes base libssl-dev pin or its v0.21.5 update.")
    dockerfile.write_text(content, encoding="utf-8")
    if any(line.rstrip("\r\n") == "        " + fragment for line in content.splitlines(keepends=True)):
        write_hermes_source_patches()
        print("  Hermes already pins the reviewed v0.21.5 release.")
        raise SystemExit(0)
    lines = content.splitlines(keepends=True)
    matches = [i for i, line in enumerate(lines) if line.strip().startswith("'v2026.9.24|0.21.5|")]
    if len(matches) != 1:
        raise SystemExit("ERROR: expected exactly one v0.21.5 release identity line to repair.")
    index = matches[0]
    newline = "\n" if lines[index].endswith("\n") else ""
    lines[index] = "        " + fragment + newline
    dockerfile.write_text("".join(lines), encoding="utf-8")
    write_hermes_source_patches()
    print("  Repaired Hermes v0.21.5 release identity line.")
    raise SystemExit(0)

if old_libssl not in content and new_libssl not in content:
    raise SystemExit("ERROR: expected the reviewed Hermes base libssl-dev pin or its upstream update.")
if not all(line in content for line in old) or 'expected_version: "0.21.3"' not in manifest_content:
    raise SystemExit("ERROR: Hermes source is not at the reviewed v0.21.3 baseline; refusing to change its pin.")
if fragment in content:
    raise SystemExit("ERROR: the v0.21.5 release identity is already present but the source pins are stale.")
if "        *) echo \"ERROR: unreviewed Hermes release identity tuple\"" not in content:
    raise SystemExit("ERROR: Hermes release identity guard anchor not found.")

replacements = {
    "# Calver tag v2026.9.14 = Hermes Agent v0.21.3.": "# Calver tag v2026.9.24 = Hermes Agent v0.21.5.",
    "ARG HERMES_VERSION=v2026.9.14": "ARG HERMES_VERSION=v2026.9.24",
    "ARG HERMES_SEMVER=0.21.3": "ARG HERMES_SEMVER=0.21.5",
    "ARG HERMES_TARBALL_SHA256=47df72ebd3f9c96d806a94541163f7fe7d7ce5b84f85c1d3787e6dfeea1d7834": "ARG HERMES_TARBALL_SHA256=15b15ce4e6ec8ea424a081823709d1e17f0943e7b42b59597d24ebb94cbd1742",
    "ARG HERMES_NPM_INTEGRITY=sha512-LvPt2/1z6hm4pTRJu34F6uAkBVSlSt94QeZp8fMBLFqASU9/wv7iMODSGMzF1WmrpNENXYGMnWN8s9hi/EUM5Q==": "ARG HERMES_NPM_INTEGRITY=sha512-cjmXp1bhw7QEZ5Z+eRBNK74R3HRkY944tSFafFhu/SHQ/deRNbRc04gdc2KZ7cUm22/2rnl7jtcFeuhROMrdmQ==",
}
content = content.replace(old_libssl, new_libssl, 1)
for before, after in replacements.items():
    if content.count(before) != 1:
        raise SystemExit(f"ERROR: expected exactly one occurrence of Hermes pin line: {before}")
    content = content.replace(before, after, 1)

guard_anchor = '        *) echo "ERROR: unreviewed Hermes release identity tuple"'
content = content.replace(guard_anchor, f"        {fragment}\n{guard_anchor}", 1)
dockerfile.write_text(content, encoding="utf-8")
manifest_content = manifest_content.replace('expected_version: "0.21.3"', 'expected_version: "0.21.5"', 1)
manifest.write_text(manifest_content, encoding="utf-8")
write_hermes_source_patches()
print("  Hermes base image and manifest pin updated to v0.21.5.")
PY
  exit 0
fi

if [ "$ACTIVE_AGENT" != "openclaw" ]; then
  case "$NEMOCLAW_OPENAI_HTTP_ENABLED" in
    1|true|yes)
      echo "ERROR: NEMOCLAW_OPENAI_HTTP_ENABLED is an OpenClaw-only cookbook overlay." >&2
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
