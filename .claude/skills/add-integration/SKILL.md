---
name: add-integration
description: Add a new integration to an existing NemoClaw sandbox — creates the provider, updates policy, backs up workspace, recreates sandbox, and restores. Use when adding API keys for new services like Brave Search, or after adding a new key to ~/.env.
allowed-tools: Bash Read Write Edit Grep Glob AskUserQuestion
---

# Add Integration

Safely add a new API integration to a running NemoClaw sandbox. This handles the full lifecycle: detect what's new, back up workspace, create the provider, recreate the sandbox, and restore.

OpenShell does not allow attaching providers to a running sandbox — recreation is required. This skill automates the backup/restore around that constraint.

## Phase 1 — Detect unconfigured integrations

Check what's in `~/.env` versus what's already configured:

```bash
# What keys are available?
grep -E '^\s*[A-Z_]+=' ~/.env | grep -v '^#'

# What providers exist?
openshell provider list 2>/dev/null

# What sandbox is running?
nemoclaw list 2>/dev/null
```

### Known integration mappings

| Env var | Provider name | Provider type | Policy block |
|---------|--------------|---------------|-------------|
| `BRAVE_SEARCH_API_KEY` | `brave-search` | `generic` | `brave_search` in policy.patch (injected as `BRAVE_API_KEY` — the name OpenClaw expects) |

Report what's new and confirm with the user before proceeding.

## Phase 2 — Verify network policy

The policy patch must include endpoints for the integration. Check:

```bash
grep -q 'brave_search' ~/NemoClaw/nemoclaw-blueprint/policies/openclaw-sandbox.yaml \
  && echo "brave_search policy: present" \
  || echo "brave_search policy: MISSING — policy.patch needs updating"
```

If the policy is missing, the `policy.patch` needs to be regenerated first. Guide the user to update it or use `/refresh-patches`.

## Phase 3 — Full backup (workspace + chat history)

Always back up before destructive operations. Use the cookbook's full backup script which includes chat session history:

```bash
COOKBOOK_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." 2>/dev/null && pwd)" # or find it
SANDBOX_NAME=$(nemoclaw list --json 2>/dev/null | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$SANDBOX_NAME" ]; then
  echo "No sandbox found — skipping backup"
else
  ~/nemoclaw-cookbook/scripts/backup-full.sh backup "$SANDBOX_NAME"
fi
```

This backs up workspace files (SOUL.md, USER.md, etc.) AND chat session history (JSONL files from `/sandbox/.openclaw-data/agents/main/sessions/`).

Report the backup location to the user.

## Phase 4 — Create provider

Source credentials and create the OpenShell provider:

```bash
source ~/.env
export BRAVE_SEARCH_API_KEY  # or whichever key

openshell provider create --name brave-search --type generic \
  --credential BRAVE_API_KEY 2>/dev/null \
  || openshell provider update brave-search \
    --credential BRAVE_API_KEY
```

Verify:

```bash
openshell provider list
```

## Phase 5 — Recreate sandbox

The sandbox must be recreated to attach the new provider:

```bash
source ~/.env
export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_RECREATE_SANDBOX=1
[ -n "${CHAT_UI_URL:-}" ] && export CHAT_UI_URL
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && export TELEGRAM_BOT_TOKEN
[ -n "${ALLOWED_CHAT_IDS:-}" ] && export ALLOWED_CHAT_IDS
[ -n "${BRAVE_SEARCH_API_KEY:-}" ] && export BRAVE_SEARCH_API_KEY

cd ~/NemoClaw && nemoclaw onboard
```

This takes a few minutes. Monitor the output for errors.

## Phase 6 — Restore workspace + chat history

Restore the backed-up workspace files and chat sessions:

```bash
~/nemoclaw-cookbook/scripts/backup-full.sh restore "$SANDBOX_NAME"
```

## Phase 7 — Verify

Confirm everything is working:

```bash
# Sandbox is healthy
nemoclaw "$SANDBOX_NAME" status

# Provider is listed
openshell provider list

# Policy includes the new endpoint
grep 'brave_search\|api.search.brave.com' \
  ~/NemoClaw/nemoclaw-blueprint/policies/openclaw-sandbox.yaml
```

Report the results to the user. If the provider shows as created but not attached, the sandbox may need another recreation cycle.

## Adding future integrations

To add a new integration beyond Brave Search:

1. Add the API key to `~/.env`
2. Add the env var to `.env.example` in the cookbook
3. Add network policy entries to `patches/policy.patch` (regenerate via `/refresh-patches`)
4. Add the provider creation to `setup.sh` following the Brave Search pattern
5. Add the mapping to the table in Phase 1 of this skill
6. Run this skill to apply the changes to the running sandbox
