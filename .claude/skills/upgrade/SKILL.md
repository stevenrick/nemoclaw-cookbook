---
name: upgrade
description: Upgrade a running NemoClaw deployment — checks versions, updates host tooling, and conditionally rebuilds the sandbox. Use when you want to pull latest upstream, add/remove tools, or apply .env changes.
allowed-tools: Bash Read Write Edit Grep Glob AskUserQuestion WebFetch
---

# NemoClaw Upgrade

Upgrade a running NemoClaw deployment to latest upstream, apply .env changes, or add/remove tools. Single entry point for all post-setup changes.

**Important:** The sandbox name is NOT always `my-assistant`. Always look it up via `nemoclaw list` or the deployment manifest. Use the discovered name throughout.

## Phase 1 — Discover current state

Find the Brev instance:

```bash
brev ls
```

If no instances, abort. If multiple, ask the user which one. If exactly one, confirm.

Read the deployment manifest and discover sandbox name:

```bash
brev exec <instance> "cat ~/.nemoclaw/cookbook-deployment.json 2>/dev/null"
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && nemoclaw list 2>/dev/null"
```

Use the sandbox name from `nemoclaw list` (the one marked with `*`). Store it for all subsequent commands.

Check infrastructure state (detects pre-systemd deployments that need migration):

```bash
brev exec <instance> "[ -f /etc/systemd/system/openshell-gateway.service ] && echo SYSTEMD_OK || echo SYSTEMD_MISSING"
brev exec <instance> "command -v nginx >/dev/null 2>&1 && echo NGINX_OK || echo NGINX_MISSING"
```

If either is `MISSING`, the upgrade will include installing infrastructure services (Phase 7b).

If no manifest exists (pre-manifest deployment), bootstrap by inspecting:

```bash
brev exec <instance> "git -C ~/NemoClaw log --oneline -1 2>/dev/null"
brev exec <instance> "git -C ~/OpenShell log --oneline -1 2>/dev/null"
brev exec <instance> "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o 'ProxyCommand=/home/ubuntu/.local/bin/openshell ssh-proxy --gateway-name nemoclaw --name <sandbox>' sandbox@openshell-<sandbox> 'claude --version 2>/dev/null && echo CLAUDE_OK || echo CLAUDE_MISSING; codex --version 2>/dev/null && echo CODEX_OK || echo CODEX_MISSING'"
```

Also read the local `.env` for tool flags:

```bash
source <cookbook-dir>/.env
echo "INSTALL_CLAUDE_CODE: ${INSTALL_CLAUDE_CODE:-true}"
echo "INSTALL_CODEX: ${INSTALL_CODEX:-true}"
```

## Phase 2 — Check available versions

```bash
brev exec <instance> "git -C ~/NemoClaw fetch origin && git -C ~/NemoClaw log --oneline origin/main -1"
brev exec <instance> "git -C ~/OpenShell fetch origin && git -C ~/OpenShell log --oneline origin/main -1"
```

For sandbox-base image tag:

```
WebFetch https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base — get the most recent commit SHA tag
```

Also check if the cookbook on the remote is current:

```bash
brev exec <instance> "git -C ~/nemoclaw-cookbook log --oneline -1 2>/dev/null"
```

Compare local cookbook HEAD vs remote cookbook HEAD. If different, the remote needs `git pull`.

## Phase 3 — Upstream overlap audit

Before applying any changes, check if upstream now provides something we patch. This prevents trampling and duplicate entries.

```bash
brev exec <instance> "cd ~/NemoClaw && git stash 2>/dev/null; git checkout origin/main -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null"
```

Then check the clean upstream files for our additions:

- **Dockerfile**: Does upstream now have `claude.ai/install.sh`, `@openai/codex`, or `insteadOf.*git@github.com`?
- **Policy**: Does upstream now have `platform.claude.com`, `api.openai.com`, `codeload.github.com`?

```bash
brev exec <instance> "cd ~/NemoClaw && grep -c 'claude.ai/install.sh' Dockerfile; grep -c '@openai/codex' Dockerfile; grep -c 'insteadOf' Dockerfile"
brev exec <instance> "cd ~/NemoClaw && grep -c 'platform.claude.com' nemoclaw-blueprint/policies/openclaw-sandbox.yaml; grep -c 'api.openai.com' nemoclaw-blueprint/policies/openclaw-sandbox.yaml; grep -c 'codeload.github.com' nemoclaw-blueprint/policies/openclaw-sandbox.yaml"
```

Restore:

```bash
brev exec <instance> "cd ~/NemoClaw && git checkout -- Dockerfile nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null; git stash pop 2>/dev/null || true"
```

If overlaps found:
- Report them clearly
- Suggest `/refresh-patches` to trim overlapping fragments
- Ask whether to proceed (fragments still work — they just add duplicates)

## Phase 4 — Triage and present changes

Categorize:

**Host-only updates (no rebuild needed):**
- NemoClaw CLI: local commit behind origin/main
- OpenShell CLI: local commit behind origin/main
- Cookbook: remote behind local main

**Sandbox rebuild required:**
- New sandbox-base image tag
- Tool flags changed (added/removed Claude Code or Codex)
- .env changes that affect sandbox creation (new providers, messaging tokens)
- NemoClaw source changes (affects the built image)
- `OPENCLAW_VERSION` changed (rebuilds sandbox-base locally with the specified version)

Present a summary:

> **Upgrade summary for `<instance>` (sandbox: `<sandbox>`):**
>
> Host updates:
> - NemoClaw CLI: `c99e3e8` → `364969d` (fix: clear stale SSH host keys)
> - OpenShell CLI: `491c5d81` → `13262e1c` (feat: sandbox exec subcommand)
> - Cookbook: up to date
>
> Sandbox rebuild: **required** (new sandbox-base image)
> - Tools: claude-code, codex (unchanged)
>
> ⚠ Rebuild will require re-authentication of Claude Code and Codex.
>
> Proceed?

If nothing changed: "Everything is up to date. No changes needed."

## Phase 5 — Backup

Always backup before any changes that touch the sandbox:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/backup-full.sh backup <sandbox>"
```

Use `timeout: 300000`. For host-only updates, skip — no sandbox disruption.

## Phase 6 — Update cookbook on remote

```bash
brev exec <instance> "cd ~/nemoclaw-cookbook && git pull origin main"
brev copy <cookbook-dir>/.env <instance>:~/.env
```

## Phase 7 — Update host tooling

Reset all files that `apply-patches.sh` mutates before pulling — `Dockerfile`, `Dockerfile.base` (touched when `OPENCLAW_VERSION` is set), and the sandbox policy YAML. Pull will otherwise fail with "local changes would be overwritten by merge".

```bash
brev exec <instance> "cd ~/NemoClaw && git checkout -- Dockerfile Dockerfile.base nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null; git pull --ff-only origin main"
brev exec <instance> "cd ~/OpenShell && git pull --ff-only origin main && sh install.sh"
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && docker pull ghcr.io/nvidia/nemoclaw/sandbox-base:latest"
```

Use `timeout: 300000` for docker pull.

## Phase 7b — Install/update infrastructure services

Always run this — it's idempotent. For pre-systemd deployments this installs nginx, systemd units, and the terminal server. For existing deployments it updates configs and restarts services.

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/install-services.sh"
```

## Phase 8 — Apply patches (validate BEFORE destroying)

**Critical ordering.** Patches must apply before we destroy anything. If they fail, abort — the user keeps a working system.

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && set -a && source ~/.env && set +a && cd ~/NemoClaw && git checkout -- Dockerfile Dockerfile.base nemoclaw-blueprint/policies/openclaw-sandbox.yaml 2>/dev/null; ~/nemoclaw-cookbook/scripts/apply-patches.sh ~/NemoClaw"
```

If this fails:
- Do NOT proceed with destroy
- Tell the user: "Patches failed against new upstream. Run `/refresh-patches` then retry `/upgrade`."
- The running sandbox is still intact

## Phase 9 — Rebuild sandbox (if needed)

Skip entirely if only host updates needed.

### Rebuild NemoClaw CLI *first*

After a `git pull`, NemoClaw may have new TypeScript modules. Run `npm ci` **before** `nemoclaw stop` — otherwise `stop` fails with `MODULE_NOT_FOUND` and prints noise.

`npm ci` triggers the prepare hook which builds the CLI and then strips devDeps. Do NOT run `npm run build:cli` separately after — `tsc` will have been removed.

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && cd ~/NemoClaw && npm ci"
```

If `npm ci` fails to build (e.g., prepare hook doesn't find tsc), install typescript explicitly:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && cd ~/NemoClaw && npm install typescript && npm run build:cli"
```

### Stop services

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && nemoclaw stop 2>/dev/null || true"
```

### Destroy and recreate

**Critical:** use `set -a; source ~/.env; set +a` so every variable in `.env` (messaging tokens, integration keys, policy overrides) gets exported to the `nemoclaw` child process. Only exporting `NVIDIA_API_KEY` means the rebuilt sandbox won't have Telegram/Discord/Slack providers or correct policy presets — onboard then silently re-destroys on the next run to migrate providers, wiping the just-restored workspace. Don't hand-pick variables; export the whole env.

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && set -a && source ~/.env && set +a && export NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 && nemoclaw <sandbox> destroy --yes && nemoclaw onboard"
```

Use `timeout: 600000` (10 min).

After `nemoclaw onboard` returns, confirm the expected messaging providers exist. If a provider is missing, the *next* `nemoclaw onboard` call (anywhere in this flow, or in a future `/upgrade`) will force a full sandbox recreate to migrate providers — destroying workspace files mid-flow.

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && openshell provider list 2>&1"
```

Verify that `<sandbox>-telegram-bridge` / `-discord-bridge` / `-slack-bridge` exist for every token set in `.env`. If any are missing, re-check what was exported to onboard — don't proceed with workspace restore until providers match, or the restore work will be thrown away on the next recreate.

### Restore workspace (phase 1 — before nemoclaw start)

Workspace files (SOUL.md, USER.md, memory/, skills) are read from disk on each request, so restoring them while the gateway is running is safe.

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> '' workspace"
```

### Restart services

Use the same `set -a; source ~/.env; set +a` pattern so messaging tokens reach `nemoclaw start`:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && set -a && source ~/.env && set +a && nemoclaw start 2>/dev/null || true"
```

Make sure the internal OpenShell port forward for 18789 is live (`nemoclaw onboard` typically starts it; this is a belt-and-suspenders step that swallows an "already forwarded" error):

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && SANDBOX=\$(nemoclaw list 2>/dev/null | awk '/\\*/{print \$1}' | head -1) && [ -n \"\$SANDBOX\" ] && (openshell forward start 18789 \"\$SANDBOX\" --background 2>&1 | grep -v 'already forwarded' || true)"
```

### Restore sessions (phase 2 — after nemoclaw start)

Session files (sessions.json + JSONL transcripts) must be restored AFTER `nemoclaw start`. The gateway reads sessions.json from disk on each write, so uploading the backup version makes the next gateway operation pick up the restored sessions. Restoring before start would be overwritten when channels reconnect.

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/backup-full.sh restore <sandbox> '' sessions"
```

## Phase 10 — Save tokenized UI URL and write deployment manifest

**If sandbox was rebuilt**, the gateway token has changed. Regenerate the URL file:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/save-ui-url.sh"
```

Then write the deployment manifest:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/write-manifest.sh"
```

## Phase 11 — Verify and report

Run the comprehensive health check:

```bash
brev exec <instance> ". \$HOME/.nvm/nvm.sh && export PATH=\"\$HOME/.local/bin:\$PATH\" && ~/nemoclaw-cookbook/scripts/verify-deployment.sh"
```

This checks: gateway health, sandbox status, dashboard reachability (auto-restarts the internal forward if dead), OpenClaw running, tools installed, workspace files, services, and manifest accuracy. If any check fails, diagnose before reporting success.

Get the new tokenized URL (changes on rebuild):

```bash
brev exec <instance> "cat ~/openclaw-ui-url.txt 2>/dev/null"
```

Update `UPSTREAM.md` in the local cookbook repo with the new versions and today's date. Use WebFetch to look up the sandbox-base tag from GitHub packages (not `docker images`).

**If sandbox was rebuilt:**

> **Upgrade complete on `<instance>` (sandbox: `<sandbox>`):**
> - NemoClaw: `<commit>`
> - OpenShell: `<commit>`
> - Sandbox: Ready
> - Tools: [list from manifest]
>
> New Web UI URL: `http://127.0.0.1:18789/#token=<hex>`
>
> **Post-upgrade:** Re-authenticate Claude Code and Codex (SSO tokens don't survive rebuild).

**If host-only:**

> **Upgrade complete on `<instance>` (host-only, no rebuild):**
> - NemoClaw CLI: `<old>` → `<new>`
> - OpenShell CLI: `<old>` → `<new>`
> - Sandbox: untouched — no re-auth needed

## Principles

- **Never destroy before validating patches.** If fragments fail, abort. User keeps a working system.
- **Always backup before destroy.** Non-negotiable.
- **Always look up the sandbox name.** Never hardcode `my-assistant`.
- **Host-only updates are zero-disruption.** No downtime, no re-auth, no URL change.
- **Check upstream overlap before applying.** Flag if upstream now handles something we patch.
- **Update cookbook on remote first.** Latest patches and scripts must be in place before rebuild.
- **Export the whole `.env` before onboard.** Use `set -a; source ~/.env; set +a`. Hand-picking variables strands messaging tokens and integration keys, which makes the sandbox rebuild without providers — onboard then silently re-destroys on the next run to migrate, wiping workspace mid-flow.
- **Verify expected providers exist after onboard.** Missing providers = pending silent destroy. Catch this before doing workspace restore work.
- **Surface the new URL.** After rebuild, the tokenized URL changes.
- **Never leak secrets.** Only SET / NOT SET.
