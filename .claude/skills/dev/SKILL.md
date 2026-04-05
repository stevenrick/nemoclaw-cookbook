---
name: dev
description: Investigate NemoClaw internals, debug issues across the NemoClaw/OpenClaw/OpenShell stack, test upstream branches, and contribute fixes. Use when something isn't working and you need to dig deeper than the user-facing docs cover.
allowed-tools: Bash Read Write Edit Grep Glob AskUserQuestion WebFetch
---

# Dev — Investigation & Upstream Contribution

A workflow for diagnosing issues, testing upstream changes, and contributing fixes to the NemoClaw ecosystem. This skill captures the practices and architecture knowledge needed to work effectively across the NemoClaw → OpenClaw → OpenShell stack.

## When to use this skill

- Something isn't working and the user-facing docs don't explain why
- Testing an upstream PR branch before it merges
- Contributing a fix to NemoClaw
- Understanding why a feature doesn't work inside the sandbox

## Architecture reference

### The three layers

| Layer | What it does | Where it lives |
|-------|-------------|----------------|
| **OpenShell** | Sandbox runtime (K3s, Landlock, seccomp, network policy) | Host: `~/.local/bin/openshell`, Container: `/opt/openshell/` |
| **NemoClaw** | CLI stack that orchestrates OpenShell + OpenClaw | Host: `~/.local/bin/nemoclaw`, Source: `~/NemoClaw/` or `~/.nemoclaw/source/` |
| **OpenClaw** | AI agent gateway + channel integrations | Inside sandbox: `/usr/local/lib/node_modules/openclaw/` |

### Sandbox security model

The sandbox has two partitions with different permissions:

| Path | Access | Purpose |
|------|--------|---------|
| `/sandbox/.openclaw/` | **Read-only** (Landlock enforced at kernel level) | Frozen config, auth tokens, symlinks to writable state |
| `/sandbox/.openclaw-data/` | **Read-write** | Agent sessions, workspace, plugins, writable state |

**Critical: Landlock enforcement means even root cannot write to `/sandbox/.openclaw/`.** File permissions (chmod/chown) are irrelevant — the kernel blocks all writes. Any runtime config changes must go through `/sandbox/.openclaw-data/`.

Additional hardening:
- `chattr +i` on `/sandbox/.openclaw/` and its contents (immutable flag)
- Config integrity verified via SHA-256 hash at startup
- Gateway runs as separate `gateway` user (privilege separation)
- `no-new-privileges` security option prevents privilege escalation

### Key files inside the sandbox

| File | Purpose |
|------|---------|
| `/sandbox/.openclaw/openclaw.json` | Frozen gateway config (read-only, hash-verified) |
| `/sandbox/.openclaw-data/workspace/` | Agent workspace (SOUL.md, USER.md, etc.) |
| `/sandbox/.openclaw-data/agents/main/sessions/` | Chat session history (JSONL) |
| `/usr/local/bin/nemoclaw-start` | Container entrypoint (starts gateway, auto-pair, channel config) |
| `/tmp/gateway.log` | Gateway stdout/stderr |
| `/tmp/openclaw/openclaw-*.log` | OpenClaw runtime log (structured JSON, more detailed) |
| `/tmp/auto-pair.log` | Auto-pair watcher log |

### Gateway device pairing

The OpenClaw gateway requires device pairing for WebSocket connections. The auto-pair watcher in `nemoclaw-start.sh` auto-approves certain client types:

```python
ALLOWED_CLIENTS = {'openclaw-control-ui'}
ALLOWED_MODES = {'webchat', 'cli'}  # 'cli' added by our PR
```

If pairing fails, all `openclaw` CLI commands that need the gateway will error with `"pairing required"`. Check `/tmp/auto-pair.log` and `openclaw devices list --json`.

## Investigating issues

### Step 1 — Check the basics

```bash
# Host-side status
brev exec <instance> "export PATH=\"\$HOME/.local/bin:\$HOME/.nvm/versions/node/v22.22.2/bin:\$PATH\" && nemoclaw list && openshell sandbox list && openshell status"

# Inside sandbox — gateway health
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name my-assistant' sandbox@openshell-my-assistant 'openclaw status 2>&1'"
```

### Step 2 — Read the logs

```bash
# Gateway startup log
brev exec <instance> "ssh ... sandbox@openshell-my-assistant 'cat /tmp/gateway.log | tail -30'"

# OpenClaw runtime log (structured, more detail)
brev exec <instance> "ssh ... sandbox@openshell-my-assistant 'cat /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log | tail -30'"

# Auto-pair watcher log
brev exec <instance> "ssh ... sandbox@openshell-my-assistant 'cat /tmp/auto-pair.log'"

# Filter for errors
brev exec <instance> "ssh ... sandbox@openshell-my-assistant 'grep ERROR /tmp/openclaw/openclaw-*.log | tail -10'"
```

### Step 3 — Check the config

```bash
# Read the frozen config
brev exec <instance> "ssh ... sandbox@openshell-my-assistant 'cat /sandbox/.openclaw/openclaw.json'"

# Check what's writable
brev exec <instance> "ssh ... sandbox@openshell-my-assistant 'ls -la /sandbox/.openclaw/ && echo === && ls -la /sandbox/.openclaw-data/'"

# Check env vars available to the sandbox
brev exec <instance> "ssh ... sandbox@openshell-my-assistant 'env | grep -i -E \"TELEGRAM|DISCORD|SLACK|NVIDIA|OPENCLAW\" | sed \"s/=.*/=***/\"'"
```

### Step 4 — Check the process tree

```bash
# What's running inside the sandbox
brev exec <instance> "ssh ... sandbox@openshell-my-assistant 'for p in /proc/[0-9]*/; do pid=\$(basename \$p); cmd=\$(cat \$p/cmdline 2>/dev/null | tr \"\\0\" \" \" | head -c 80); [ -n \"\$cmd\" ] && echo \"PID \$pid: \$cmd\"; done'"
```

### Step 5 — Check upstream issues

```bash
# Search NemoClaw issues
gh issue list --repo NVIDIA/NemoClaw --search "<keywords>" --limit 10

# Search open PRs
gh pr list --repo NVIDIA/NemoClaw --search "<keywords>" --state open --limit 10

# Read a specific issue or PR
gh issue view <number> --repo NVIDIA/NemoClaw
gh pr view <number> --repo NVIDIA/NemoClaw --json title,body,state,files
```

## Testing upstream PR branches

To test a NemoClaw PR branch on a Brev instance:

```bash
# 1. Destroy existing sandbox
brev exec <instance> "export PATH=... && nemoclaw my-assistant destroy --yes"

# 2. Switch NemoClaw to the PR branch
brev exec <instance> "cd ~/NemoClaw && git fetch origin <branch-name> && git checkout <branch-name>"

# 3. Reset to clean state and apply cookbook patches
brev exec <instance> "cd ~/NemoClaw && git checkout -- . && git apply --3way ~/nemoclaw-cookbook/patches/Dockerfile.patch && git apply --3way ~/nemoclaw-cookbook/patches/policy.patch"

# 4. Rebuild
brev exec <instance> "export PATH=... && source ~/.env && export NVIDIA_API_KEY NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 && cd ~/NemoClaw && nemoclaw onboard"
```

To test multiple PRs together (may require conflict resolution):

```bash
brev exec <instance> "cd ~/NemoClaw && git fetch origin <branch-1> <branch-2> && git checkout <branch-1> && git merge origin/<branch-2> --no-edit"
```

## Contributing upstream

### Fork and branch

```bash
# Clone your fork
git clone git@github.com:<your-user>/NemoClaw.git /tmp/nemoclaw-pr
cd /tmp/nemoclaw-pr
git checkout -b fix/<descriptive-name>
```

### Make the change and commit

NemoClaw uses Conventional Commits and requires DCO sign-off:

```bash
git commit -m "$(cat <<'EOF'
fix(scripts): short description of the change

Longer explanation if needed.

Related: #<issue-number>

Signed-off-by: Your Name <your-email@example.com>
EOF
)"
```

### Push and open PR

```bash
git push -u origin fix/<descriptive-name>
# Then open PR at https://github.com/<your-user>/NemoClaw/pull/new/fix/<branch>
```

PR template requires: Summary, Related Issue, Changes, Type of Change, Testing, Checklist. See CONTRIBUTING.md in NemoClaw repo.

## Known issues

### Telegram bridge timeout with long-running tasks

The host-side Telegram bridge (`scripts/telegram-bridge.js`) is a synchronous shim: it SSHes into the sandbox, runs `openclaw agent --local -m <message>`, captures stdout, and sends it to Telegram. The SSH process has a 120-second timeout.

Coding agent tasks (Claude Code, Codex) routinely take 5-10+ minutes, causing:
1. Bridge SSH process times out → response never sent to Telegram
2. Agent continues running inside sandbox (visible in Web UI)
3. Follow-up messages create new SSH invocations with same session ID
4. Agent reads prior session history but doesn't know it's on Telegram

The proper fix is the native channel path: `openclaw agent --deliver --channel telegram` through the gateway delivery queue. This is async with no timeout. But it requires the gateway pairing fix + runtime config overrides (PRs #928 + #1081) to land first. The bridge is an interim workaround that will be removed when native channels work.

### `brev copy` unreliable for directories

`brev copy` for directory transfers frequently times out or fails with SCP errors. Use `git clone` on the remote instance instead:

```bash
brev exec <instance> "git clone <repo-url> ~/target-dir"
```

`brev copy` works reliably for single small files (like `.env`).

## Known architecture constraints

These are fundamental to the NemoClaw design and cannot be patched around:

1. **Landlock blocks all writes to `/sandbox/.openclaw/`** — any runtime config changes must go through a writable overlay mechanism (see NemoClaw PR #928)

2. **The auto-pair watcher runs once at startup with a timeout** — if it times out before a client connects, that client stays in "pending" state. Restart the sandbox to trigger a new auto-pair cycle.

3. **The container entrypoint runs as non-root** in OpenShell's security model (`no-new-privileges`). Functions that need root (like modifying root-owned config files) will fail silently or with EPERM.

4. **OpenClaw channel subsystems require config at gateway startup** — adding a new channel config while the gateway is running triggers a "requires restart" message. Hot-reload works for value changes within existing channels, not for adding new channels.

5. **Bot tokens flow through OpenShell providers** — the real token never enters the sandbox. The sandbox sees a placeholder that the L7 proxy rewrites on outbound API calls. This means the token is available as an env var but is a placeholder, not the real value.

## Upstream context

Key open PRs and issues as of 2026-04-05:

| # | Type | Title | Relevance |
|---|------|-------|-----------|
| #1310 | Issue | CLI pairing rejected after onboard | Auto-pair watcher doesn't approve CLI clients |
| #690 | PR | Limit auto-pair to one-shot with 180s timeout | Security tightening of auto-pair |
| #928 | PR | Runtime config overrides via writable overlay | Enables channel config at runtime without modifying frozen config |
| #1081 | PR | Use providers for messaging credential injection | Native Telegram/Discord/Slack channels via OpenShell providers |
| #1496 | PR | Allow CLI clients in auto-pair watcher | Our fix — adds `'cli'` to `ALLOWED_MODES` |

Dependency chain: #1496 (auto-pair fix) → #928 (writable overlay) → #1081 (native channels). All three are needed for native messaging channel support inside the sandbox.
