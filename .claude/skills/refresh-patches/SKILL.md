---
name: refresh-patches
description: Update cookbook fragments when upstream NemoClaw changes break them or when upstream now provides something we previously patched. Use after apply-patches.sh fails or when upgrading to newer upstream.
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob
---

# Refresh Patches

The cookbook uses modular fragments (not git patches) to customize upstream NemoClaw. Fragments are applied by `scripts/apply-patches.sh` using text insertion (Dockerfile) and YAML merging (policy).

| Fragment | Target | Purpose |
|----------|--------|---------|
| `patches/fragments/dockerfile-core` | `Dockerfile` | Git HTTPS config, NODE_NO_WARNINGS |
| `patches/fragments/dockerfile-claude-code` | `Dockerfile` | Claude Code installation |
| `patches/fragments/dockerfile-codex` | `Dockerfile` | Codex CLI installation |
| `patches/fragments/policy-core.yaml` | `openclaw-sandbox.yaml` | codeload.github.com for HTTPS git |
| `patches/fragments/policy-claude-code.yaml` | `openclaw-sandbox.yaml` | Claude auth endpoints + github binary |
| `patches/fragments/policy-codex.yaml` | `openclaw-sandbox.yaml` | OpenAI section + codex/node binaries |

## Step 1 — Upstream overlap audit (do this FIRST)

Before fixing broken fragments, check if upstream now provides something we add. **Defer to upstream when possible — less is more.**

Clone or use existing upstream checkout:

```bash
cd ~/NemoClaw && git fetch origin && git checkout origin/main -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
```

Check Dockerfile for our additions in upstream:

```bash
grep -c 'claude.ai/install.sh' Dockerfile        # Claude Code install
grep -c '@openai/codex' Dockerfile                 # Codex install
grep -c 'insteadOf.*git@github.com' Dockerfile     # Git HTTPS config
grep -c 'NODE_NO_WARNINGS' Dockerfile              # Node warnings suppression
```

Check policy for our additions in upstream:

```bash
grep -c 'platform.claude.com' nemoclaw-blueprint/policies/openclaw-sandbox.yaml
grep -c 'api.openai.com' nemoclaw-blueprint/policies/openclaw-sandbox.yaml
grep -c 'codeload.github.com' nemoclaw-blueprint/policies/openclaw-sandbox.yaml
```

**If upstream now provides something we patch:**
- Remove that content from our fragment — upstream handles it now
- If the entire fragment is subsumed, delete the fragment file
- Update `apply-patches.sh` if a fragment was removed entirely

**If upstream doesn't provide it yet:** proceed to Step 2.

Restore working state:

```bash
cd ~/NemoClaw && git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
```

## Step 2 — Diagnose the failure

Run the validation script:

```bash
~/nemoclaw-cookbook/scripts/validate-patches.sh
```

This checks:
1. Dockerfile anchor line exists (`# Set up blueprint for local resolution`)
2. Policy section anchors exist (claude_code, nvidia, github)
3. Full apply-patches.sh succeeds
4. Upstream overlap audit

Common failures:
- **Anchor line changed:** upstream reworded the comment. Find the new equivalent and update `scripts/apply-patches.sh`.
- **Policy section renamed/removed:** upstream restructured the YAML. Update the section names in `scripts/merge-policy.py` or the fragment files.
- **YAML merge error:** upstream changed indentation or structure. Check `scripts/merge-policy.py` output.

## Step 3 — Fix the fragments

### Dockerfile anchor moved

If `# Set up blueprint for local resolution` no longer exists:

1. Read the upstream Dockerfile to find the logical equivalent insertion point
2. Update the `ANCHOR` variable in `scripts/apply-patches.sh`
3. Verify: reset, apply, check

### Policy section renamed

If a section like `claude_code` was renamed (e.g., to `anthropic`):

1. Update the section name in the relevant `policy-*.yaml` fragment under `add_endpoints:` or `add_binaries:`
2. Update `scripts/validate-patches.sh` section anchor checks
3. Verify: reset, apply, check

### Fragment content needs adjustment

If the logical content of a fragment needs to change:

1. Edit the fragment file in `patches/fragments/`
2. Reset upstream files and re-run `scripts/apply-patches.sh ~/NemoClaw`
3. Verify the result makes sense by reading the full file

## Step 4 — Verify round-trip

```bash
cd ~/NemoClaw
git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
INSTALL_CLAUDE_CODE=true INSTALL_CODEX=true ~/nemoclaw-cookbook/scripts/apply-patches.sh ~/NemoClaw
```

Also test partial configurations:

```bash
git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
INSTALL_CLAUDE_CODE=false INSTALL_CODEX=false ~/nemoclaw-cookbook/scripts/apply-patches.sh ~/NemoClaw
```

## Step 5 — Update references

1. Update `UPSTREAM.md` with current versions and today's date:

   ```bash
   git -C ~/NemoClaw log --oneline -1
   git -C ~/OpenShell log --oneline -1
   # sandbox-base tag: WebFetch https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base
   ```

2. Run `setup.sh` end-to-end (or at least the patch + build step) to verify
3. Check that the patched Dockerfile builds without errors

## Principles

- **Defer to upstream first.** If upstream now provides something we patched, remove it from our fragment. Less is more.
- **Preserve intent, not exact lines.** If upstream reworded a comment or reordered sections, adapt the anchor or fragment. The goal is the same logical additions.
- **Shrink fragments when possible.** If upstream adopted something we were adding, remove that part.
- **Test the round-trip.** After changes, reset and re-apply to confirm. Test all three paths: all tools, no tools, partial.
- **Fragments are independent.** Changing one fragment should never break another.
