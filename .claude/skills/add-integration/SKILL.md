---
name: add-integration
description: Add a new integration to an existing NemoClaw sandbox — creates the provider, updates policy, backs up workspace, recreates sandbox, and restores. Use when adding API keys for new services like Brave Search, or after adding a new key to .env.
allowed-tools: Bash Read Write Edit Grep Glob AskUserQuestion
---

# Add Integration

Safely add a new API integration to a running NemoClaw sandbox. This handles the full lifecycle: detect what's new, back up workspace, create the provider, recreate the sandbox, and restore.

OpenShell does not allow attaching providers to a running sandbox — recreation is required. This skill automates the backup/restore around that constraint.

## Phase 1 — Detect unconfigured integrations

Check what's in `~/.env` versus what's already configured:

```bash
# What keys are available?
grep -E '^\s*[A-Z_]+=' ~/.env | grep -v '^#' | sed 's/=.*/=***/'

# What providers exist?
openshell provider list 2>/dev/null

# What policy presets are applied?
nemoclaw my-assistant policy-list 2>/dev/null

# What sandbox is running?
nemoclaw list 2>/dev/null
```

### Known integration mappings

| Env var | Provider name | Provider type | Policy |
|---------|--------------|---------------|--------|
| `BRAVE_API_KEY` | `brave-search` | `generic` | `brave` preset (upstream) |
| `DISCORD_BOT_TOKEN` | n/a (env var injection) | n/a | `discord` preset (upstream) |
| `SLACK_BOT_TOKEN` | n/a (env var injection) | n/a | `slack` preset (upstream) |

Report what's new and confirm with the user before proceeding.

## Phase 2 — Verify network policy

Upstream NemoClaw provides policy presets for most integrations. Check if the preset exists and is applied:

```bash
nemoclaw my-assistant policy-list 2>&1
```

If the preset shows as `○` (not applied), it will be applied during sandbox recreation when the token is detected. If no preset exists for the service, the policy patch needs updating.

## Phase 3 — Full backup (workspace + chat history)

Always back up before destructive operations. Use the cookbook's full backup script which includes chat session history:

```bash
COOKBOOK_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." 2>/dev/null && pwd)" # or find it
SANDBOX_NAME=$(nemoclaw list --json 2>/dev/null | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$SANDBOX_NAME" ]; then
  echo "No sandbox found — skipping backup"
else
  "${COOKBOOK_DIR}/scripts/backup-full.sh" backup "$SANDBOX_NAME"
fi
```

This backs up workspace files (SOUL.md, USER.md, etc.) AND chat session history (JSONL files from `/sandbox/.openclaw-data/agents/main/sessions/`).

Report the backup location to the user.

## Phase 4 — Create provider (if needed)

Some integrations need an OpenShell provider (credential bundle). Others (Discord, Slack) are injected as env vars at sandbox creation — no provider needed.

For Brave Search:

```bash
source ~/.env
export BRAVE_API_KEY

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

The sandbox must be recreated to attach new providers or pick up new env vars:

```bash
source ~/.env
export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 NEMOCLAW_RECREATE_SANDBOX=1
[ -n "${NEMOCLAW_MODEL:-}" ] && export NEMOCLAW_MODEL
[ -n "${NEMOCLAW_PROVIDER:-}" ] && export NEMOCLAW_PROVIDER
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] && export TELEGRAM_BOT_TOKEN
[ -n "${ALLOWED_CHAT_IDS:-}" ] && export ALLOWED_CHAT_IDS
[ -n "${DISCORD_BOT_TOKEN:-}" ] && export DISCORD_BOT_TOKEN
[ -n "${SLACK_BOT_TOKEN:-}" ] && export SLACK_BOT_TOKEN
[ -n "${BRAVE_API_KEY:-}" ] && export BRAVE_API_KEY
[ -n "${OPENAI_API_KEY:-}" ] && export OPENAI_API_KEY
[ -n "${ANTHROPIC_API_KEY:-}" ] && export ANTHROPIC_API_KEY

cd ~/NemoClaw && nemoclaw onboard
```

This takes a few minutes. Monitor the output for errors.

## Phase 6 — Restore workspace + chat history

Restore the backed-up workspace files and chat sessions:

```bash
"${COOKBOOK_DIR}/scripts/backup-full.sh" restore "$SANDBOX_NAME"
```

## Phase 7 — Verify

Confirm everything is working:

```bash
# Sandbox is healthy
nemoclaw "$SANDBOX_NAME" status

# Provider is listed (if applicable)
openshell provider list

# Policy presets applied
nemoclaw "$SANDBOX_NAME" policy-list
```

Report the results to the user.

## Adding future integrations

To add a new integration:

1. Add the API key to `.env` in the cookbook repo (and re-copy to instance)
2. Add the env var to `.env.example` in the cookbook
3. Check if an upstream policy preset exists (`nemoclaw my-assistant policy-list`); if not, add entries to `patches/policy.patch`
4. Add the mapping to the table in Phase 1 of this skill
5. Run this skill to apply the changes to the running sandbox
