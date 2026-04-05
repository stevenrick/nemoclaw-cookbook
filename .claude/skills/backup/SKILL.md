---
name: backup
description: Pull all sandbox assets (workspace, sessions, skills) from remote NemoClaw to local backups/ directory. Use when you want to snapshot the sandbox state to your local machine.
allowed-tools: Bash Read Grep Glob AskUserQuestion
---

# Backup — Snapshot NemoClaw Sandbox to Local

Pull workspace files, chat history, and skills from a remote NemoClaw sandbox to a timestamped local backup directory.

## When to use this skill

- Before destroying or rebuilding a sandbox
- Periodic snapshots of sandbox state
- Before migrating to a new instance
- Anytime you want a local copy of the agent's workspace and memory

## Phase 1 — Discover instance and sandbox

Find the Brev instance:

```bash
brev ls
```

If multiple instances exist, ask the user which one. If the instance is STOPPED, start it with `brev start <instance>`.

Get the sandbox name:

```bash
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$HOME/.nvm/versions/node/v22.22.2/bin:\$PATH\" && nemoclaw list 2>/dev/null"
```

The default sandbox name is `my-assistant`, but the user may have set a custom name via `NEMOCLAW_SANDBOX_NAME`. Always use the name returned by `nemoclaw list`. If no sandbox is found, abort: "No sandbox found. Run /setup first."

## Phase 2 — Run backup on remote

Capture existing backup timestamps (to identify the new one later):

```bash
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$HOME/.nvm/versions/node/v22.22.2/bin:\$PATH\" && ls -1t ~/.nemoclaw/backups/ 2>/dev/null | head -5"
```

Run the backup (use 5-minute timeout — workspace download can be slow):

```bash
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$HOME/.nvm/versions/node/v22.22.2/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/backup-full.sh backup <sandbox>" --timeout 300000
```

Capture the timestamp of the just-created backup:

```bash
brev exec <instance> "ls -1t ~/.nemoclaw/backups/ | head -1"
```

## Phase 3 — Tar and transfer to local

Create a tarball on the remote (avoids unreliable directory transfers):

```bash
brev exec <instance> "cd ~/.nemoclaw/backups && tar czf /tmp/nemoclaw-backup-<timestamp>.tar.gz <timestamp>/"
```

Ensure local backups directory exists:

```bash
mkdir -p <cookbook-dir>/backups
```

Copy the single tarball to local:

```bash
brev copy <instance>:/tmp/nemoclaw-backup-<timestamp>.tar.gz <cookbook-dir>/backups/
```

Extract and clean up the tarball:

```bash
cd <cookbook-dir>/backups && tar xzf nemoclaw-backup-<timestamp>.tar.gz && rm nemoclaw-backup-<timestamp>.tar.gz
```

Clean up remote tarball:

```bash
brev exec <instance> "rm -f /tmp/nemoclaw-backup-<timestamp>.tar.gz"
```

## Phase 4 — Write metadata

Create `<cookbook-dir>/backups/<timestamp>/backup-meta.json` with:

```json
{
  "timestamp": "<timestamp>",
  "created": "<ISO 8601 datetime>",
  "instance": "<brev-instance-name>",
  "sandbox": "<sandbox-name>",
  "includes": ["workspace", "sessions", "skills"]
}
```

Adjust the `includes` array based on what was actually present (check for `sessions/` and `skills/` directories in the backup).

## Phase 5 — Report

Summarize:
- Local path: `backups/<timestamp>/`
- What was backed up: workspace files (list key ones like SOUL.md, USER.md, memory/), session count, skill count
- Backup size: `du -sh <cookbook-dir>/backups/<timestamp>/`
- Note that the remote copy is also kept at `~/.nemoclaw/backups/<timestamp>/`

## Principles

- **Use `timeout: 300000`** (5 min) for the backup and tar commands — large workspaces take time.
- **Never print file contents** of workspace files — they may contain personal info. Just list filenames and counts.
- **Always tar before `brev copy`** — directory copies are unreliable.
- **Capture timestamp from remote**, not local clock — avoids clock skew.
- **If `backup-full.sh` is not found** on the remote, tell the user to run `brev exec <instance> "cd ~/nemoclaw-cookbook && git pull"` to update the cookbook.
