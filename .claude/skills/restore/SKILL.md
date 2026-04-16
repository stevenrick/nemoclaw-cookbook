---
name: restore
description: Push a local backup to a remote NemoClaw sandbox — restores workspace files, state, sessions, and skills. Use after deploying a new instance to recover previous state.
allowed-tools: Bash Read Grep Glob AskUserQuestion
---

# Restore — Push Local Backup to NemoClaw Sandbox

Restore a previously saved backup (workspace, sessions, skills) from the local `backups/` directory to a remote NemoClaw sandbox.

## When to use this skill

- After deploying a new NemoClaw instance (to recover previous state)
- After a sandbox rebuild or destroy/recreate cycle
- When migrating to a different Brev instance
- To roll back to a known-good state

## Phase 1 — List available local backups

Find the cookbook directory (this repo's root):

```bash
ls -1t <cookbook-dir>/backups/ 2>/dev/null
```

If no backups exist, abort: "No local backups found in backups/. Run /backup first."

For each backup, check for metadata:

```bash
cat <cookbook-dir>/backups/<timestamp>/backup-meta.json 2>/dev/null
```

Present the available backups to the user with:
- Timestamp
- Original instance and sandbox name (from metadata)
- What's included (workspace, sessions, skills)

If multiple backups exist, ask the user which one to restore. Default to the latest.

## Phase 2 — Discover remote instance and sandbox

Find the Brev instance:

```bash
brev ls
```

If no instances are listed, abort: "No Brev instances found. Create one and run /setup first."

If multiple instances are listed, ask the user which one to restore to.

If exactly one instance is listed, confirm with the user before proceeding.

If the instance is STOPPED, start it. Get the sandbox name:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && nemoclaw list 2>/dev/null"
```

If no sandbox exists, abort: "No sandbox found on the remote. Run /setup first to create one, then /restore."

**Warn the user** that restoring will overwrite the current workspace, sessions, and skills in the sandbox. Ask for confirmation before proceeding.

## Phase 3 — Transfer backup to remote

Create a tarball of the chosen backup:

```bash
cd <cookbook-dir>/backups && COPYFILE_DISABLE=1 tar czf /tmp/nemoclaw-restore-<timestamp>.tar.gz <timestamp>/
```

Copy to remote:

```bash
brev copy /tmp/nemoclaw-restore-<timestamp>.tar.gz <instance>:/tmp/
```

Extract on remote and clean up:

```bash
brev exec <instance> "mkdir -p ~/.nemoclaw/backups && cd ~/.nemoclaw/backups && tar xzf /tmp/nemoclaw-restore-<timestamp>.tar.gz && rm /tmp/nemoclaw-restore-<timestamp>.tar.gz"
```

Clean up local temp:

```bash
rm /tmp/nemoclaw-restore-<timestamp>.tar.gz
```

## Phase 4 — Run restore on remote

Restore happens in two phases. Workspace files and skills can be restored at any time (they're read from disk on each request). Session files must be restored **after** `nemoclaw start` so they overwrite whatever the gateway/channels created on reconnect.

### Phase 4a — Restore workspace + skills

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> <timestamp> workspace"
```

**Important:** Set `timeout: 300000` on the Bash tool call, NOT as a `brev exec` flag.

### Phase 4b — Restore sessions (after nemoclaw start)

If the Cloudflare tunnel (for Telegram webhooks) is not already running, start it. The gateway runs under systemd and should already be active — check with `systemctl status openshell-gateway` if unsure.

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && source ~/.env && export NVIDIA_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_IDS DISCORD_BOT_TOKEN SLACK_BOT_TOKEN 2>/dev/null; nemoclaw start 2>/dev/null || true"
```

Then restore sessions:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> <timestamp> sessions"
```

**Important:** Set `timeout: 300000` on the Bash tool call, NOT as a `brev exec` flag.

This uploads sessions.json and JSONL transcripts, overwriting whatever the gateway created during channel reconnect. The gateway reads sessions.json from disk on each write operation, so the restored sessions take effect on the next message.

## Phase 5 — Verify

Ensure the tokenized UI URL file exists (rebuild changes the token):

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/save-ui-url.sh"
```

Run the comprehensive health check:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/verify-deployment.sh"
```

This checks gateway, sandbox, dashboard reachability, OpenClaw, tools, workspace files (confirms SOUL.md exists after restore), services, and manifest accuracy. If the dashboard port forward died, it auto-restarts it.

## Phase 6 — Report

Summarize:
- What was restored (workspace, N sessions, N skills)
- The remote sandbox name and instance
- If this is a **fresh instance** (not just a rebuild), remind the user about post-restore tasks:
  - Re-authenticate Claude Code: requires `brev shell` (interactive)
  - Re-authenticate Codex: `brev exec <instance> "codex login --device-auth"`
  - Restart bridges (Telegram/Discord) if applicable

## Principles

- **Always warn before overwriting.** Restoring replaces current sandbox state. Confirm with the user first.
- **Use `timeout: 300000`** (5 min) for the restore command.
- **Always tar before `brev copy`** — directory copies are unreliable.
- **Graceful fallback for old backups.** If `backup-meta.json` is missing, still proceed — just restore whatever directories exist (workspace, sessions, skills).
- **If `backup-full.sh` is not found** on the remote, tell the user to run `brev exec <instance> "cd ~/nemoclaw-cookbook && git pull"` to update the cookbook.
- **Never print workspace file contents** — just confirm they exist and list filenames.
