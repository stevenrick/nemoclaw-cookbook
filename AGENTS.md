# Coding Agent Instructions

This cookbook is a temporary scaffold for features upstream [NemoClaw](https://github.com/NVIDIA/NemoClaw) + [OpenShell](https://github.com/NVIDIA/OpenShell) don't yet handle — it is NOT a fork, and NOT a competitor. When upstream absorbs something we patch, delete our version. When a gap appears, surface it upstream (issue, PR, or a cookbook patch that demonstrates the need) rather than solving it only here. The measure of success is the cookbook shrinking over time, not growing.

## Project structure

```
setup.sh              # Automated setup — clones upstream, applies patches, installs
patches/
  fragments/          # Modular Dockerfile/config fragments
scripts/
  apply-patches.sh    # Applies fragments to upstream (replaces git apply)
  validate-patches.sh # Check fragments still work against upstream
  install-services.sh # Installs nginx, systemd units, terminal server (called by setup.sh)
  save-ui-url.sh      # Uses upstream URL/token commands → UI URL and /v1 env files
  backup-full.sh      # Workspace, chat history, and skills backup/restore
config/
  nginx.conf.template # Reverse proxy template — __COOKBOOK_DIR__ substituted at deploy
  systemd/            # nemoclaw-terminal.service — browser-terminal WebSocket bridge (the gateway is managed by upstream `nemoclaw`, not as a cookbook systemd unit)
terminal-server/      # WebSocket-to-PTY bridge for browser terminal (optional)
BUILD.md              # Step-by-step setup with explanations
USE.md                # Day-to-day commands and features
CONTRIBUTING.md       # Contribution guidelines
```

## Getting started

**If the user wants to deploy NemoClaw**, read BUILD.md and follow it step by step. The key is to create `~/.env` first, check what's configured, and only ask the user for credentials they need to provide.

**To upgrade an existing deployment**, back up first, pull the cookbook and upstream NemoClaw, validate patches, then run `setup.sh` again. It delegates OpenShell installation and sandbox-base resolution to upstream NemoClaw.

## Key docs (read these, don't duplicate them)

- **BUILD.md** — full setup walkthrough, what each fragment does and why, environment variables, troubleshooting
- **USE.md** — sandbox commands, messaging channels, access methods, upgrading
- **CONTRIBUTING.md** — contribution standards

## Rules

- **Keep fragments minimal.** Each fragment should add one logical thing. Defer to upstream when it provides something we previously patched.
- **Don't modify upstream repos directly.** All customizations go through `patches/fragments/` and `scripts/apply-patches.sh`.
- **Preserve fragment intent, not exact lines.** If upstream restructures, adapt anchors but keep the logical additions.
- **Don't add features beyond what's asked.** This is a cookbook — lean and opinionated.
- **Secrets are non-printable runtime values.** `.env`, generated client env files, gateway tokens, and tokenized dashboard URLs must never be committed, printed, logged, pasted into chat, or displayed in shared terminals. Only confirm SET / NOT SET, pass tokenized URLs directly to browsers/clients, and use `sed 's/=.*/=***/'` or equivalent redaction when listing env vars.
- **Test fragments round-trip:** reset target files, apply, verify before committing. Test no overlays and OpenAI HTTP-only when patch logic changes.
- **Never guess external values.** Commit SHAs, version numbers, API signatures, URLs — if you're not certain, look it up (`git ls-remote`, docs, web search). Fabricated-but-plausible values waste more time than admitting you need to check.
- **Check upstream overlap before adding to fragments.** If upstream already provides something, don't duplicate it. Run `scripts/validate-patches.sh` to audit.
- **Only update UPSTREAM.md after deployment verification.** Source review and patch application are useful, but the compatibility table records the last verified end-to-end deployment.
