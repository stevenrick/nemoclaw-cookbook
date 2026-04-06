---
name: refresh-patches
description: Regenerate cookbook patches when upstream NemoClaw changes break them. Use after setup.sh patch step fails or when deliberately upgrading to a newer upstream.
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob
---

# Refresh Patches

The cookbook maintains two small unified-diff patches applied on top of upstream NemoClaw:

| Patch | Target file | Purpose |
|-------|------------|---------|
| `patches/Dockerfile.patch` | `Dockerfile` | Adds Claude Code, Codex CLI, git HTTPS config |
| `patches/policy.patch` | `nemoclaw-blueprint/policies/openclaw-sandbox.yaml` | Opens network endpoints for Claude auth, OpenAI/Codex, GitHub |

When upstream NemoClaw changes these files, the patches may fail to apply. This skill walks through diagnosing and regenerating them.

## Step 1 — Assess the situation

Run these commands to understand the current state:

```bash
cd ~/NemoClaw && git log --oneline -5
cd ~/NemoClaw && git status
cd ~/NemoClaw && git diff HEAD -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
```

Compare the deployed NemoClaw commit against what's recorded in `UPSTREAM.md`:

```bash
git -C ~/NemoClaw log --oneline -1
cat ~/nemoclaw-cookbook/UPSTREAM.md | head -10
```

If the deployed commit is ahead of what's in `UPSTREAM.md`, upstream has moved since last validation.

## Step 2 — Attempt a clean apply

Reset the target files and try applying with `--3way`:

```bash
cd ~/NemoClaw
git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml
git apply --3way "${COOKBOOK_DIR}/patches/Dockerfile.patch" 2>&1 || true
git apply --3way "${COOKBOOK_DIR}/patches/policy.patch" 2>&1 || true
```

Where `COOKBOOK_DIR` is the path to this cookbook repo (use `!`pwd`` from the project root or find it via the skill directory path).

**If both apply cleanly** — the patches are still compatible. Update `UPSTREAM.md` with the current versions and you're done.

**If conflicts appear** — proceed to Step 3.

## Step 3 — Understand what changed upstream

For each file that failed to patch, compare the upstream change with what our patch expects:

1. Read the current upstream version of the file (`git show HEAD:<file>`)
2. Read the corresponding patch file from `patches/`
3. Identify what upstream changed in the region our patch targets (the context lines that shifted)

Focus on **why** the patch failed — usually one of:
- Lines around our insertion point were added/removed/reworded
- The file was restructured and our target section moved
- Our patched content was partially adopted upstream (great — we can shrink the patch)

## Step 4 — Regenerate the patch

For each broken patch:

1. Start from a clean upstream file: `git checkout -- <file>`
2. Manually apply the **intent** of the patch — add the same logical content, adapted to the new file structure
3. Verify the result makes sense by reading the full file
4. Generate a new patch: `git diff <file> > patches/<name>.patch`
5. Reset the file: `git checkout -- <file>`
6. Verify the new patch applies: `git apply --3way patches/<name>.patch`

### What our patches add (the intent to preserve):

**Dockerfile.patch** adds three `RUN` blocks after the `npm ci --omit=dev` line:
1. Git config: force HTTPS for GitHub URLs, set SSL CA to OpenShell bundle, copy .gitconfig to sandbox user
2. Install Claude Code native binary (with symlink at /sandbox/.local/bin/claude) + Codex CLI via npm

**policy.patch** adds:
1. Claude auth endpoints (platform.claude.com, downloads.claude.ai, raw.githubusercontent.com, storage.googleapis.com) + codex binary to the `claude_code` network policy
2. A new `openai` network policy block (api.openai.com, auth.openai.com, chatgpt.com, ab.chatgpt.com + codex and node binaries)
3. codeload.github.com endpoint + claude/codex/node binaries to the `github` network policy

## Step 5 — Update references

After regenerating patches:

1. Update `UPSTREAM.md` in the cookbook repo with the current NemoClaw commit, OpenShell commit, and sandbox-base image tag. These are the versions the patches are now validated against. Update the "Last validated" date to today.

   To get the values:
   ```bash
   git -C ~/NemoClaw log --oneline -1
   git -C ~/OpenShell log --oneline -1
   # sandbox-base tag: WebFetch https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base
   # (docker images only shows "latest" locally — use the GitHub packages page for the commit SHA tag)
   ```

2. Run `setup.sh` from scratch (or at least the patch step) to verify end-to-end
3. Check that the patched Dockerfile still builds: look for syntax errors, moved anchors, etc.

## Principles

- **Preserve intent, not exact lines.** If upstream reworded a comment or reordered sections, adapt. The goal is the same logical additions.
- **Shrink patches when possible.** If upstream adopted something we were patching in, remove that part of our patch.
- **Minimize context.** Use 3 lines of context (the default) — more context means more breakage surface.
- **Test the round-trip.** After regenerating, reset and re-apply to confirm.
