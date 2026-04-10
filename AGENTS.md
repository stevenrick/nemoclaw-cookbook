# Coding Agent Instructions

This is a thin patch overlay on upstream [NemoClaw](https://github.com/NVIDIA/NemoClaw) + [OpenShell](https://github.com/NVIDIA/OpenShell). It is NOT a fork.

## Project structure

```
setup.sh              # Automated setup — clones upstream, applies patches, installs
patches/
  fragments/          # Modular Dockerfile and policy YAML fragments
scripts/
  apply-patches.sh    # Applies fragments to upstream (replaces git apply)
  merge-policy.py     # YAML-aware policy fragment merger
  validate-patches.sh # Check fragments still work against upstream
  install-services.sh # Installs nginx, systemd units, terminal server (called by setup.sh)
  save-ui-url.sh      # Extract gateway token → ~/openclaw-ui-url.txt + tunnel URL
  backup-full.sh      # Workspace, chat history, and skills backup/restore
config/
  nginx.conf.template # Reverse proxy template — __COOKBOOK_DIR__ substituted at deploy
  systemd/            # systemd units for gateway, terminal server
terminal-server/      # WebSocket-to-PTY bridge for browser terminal (optional)
BUILD.md              # Step-by-step setup with explanations
USE.md                # Day-to-day commands and features
CONTRIBUTING.md       # Contribution guidelines
.claude/skills/       # Claude Code skills (e.g. /setup, /upgrade, /backup, /restore, /brev)
```

## Getting started

**If the user wants to deploy NemoClaw**, don't follow the README manually. Claude Code users should run `/setup` which handles everything interactively. Other agents: read BUILD.md and follow it step by step — the key is to create `~/.env` first, check what's configured, and only ask the user for credentials they need to provide.

**To upgrade an existing deployment**, use `/upgrade`. It checks versions, shows what's changed, and handles the full backup → update → rebuild → restore cycle.

## Key docs (read these, don't duplicate them)

- **BUILD.md** — full setup walkthrough, what each fragment does and why, environment variables, troubleshooting
- **USE.md** — sandbox commands, authentication flow, messaging bridges, upgrading
- **CONTRIBUTING.md** — contribution standards

## Rules

- **Keep fragments minimal.** Each fragment should add one logical thing. Defer to upstream when it provides something we previously patched.
- **Don't modify upstream repos directly.** All customizations go through `patches/fragments/` and `scripts/apply-patches.sh`.
- **Preserve fragment intent, not exact lines.** If upstream restructures, adapt anchors but keep the logical additions (see `/refresh-patches`).
- **Don't add features beyond what's asked.** This is a cookbook — lean and opinionated.
- **Secrets belong in `.env`, never committed.** `.gitignore` covers `.env`. **Never print, log, or display actual key/token values.** Only confirm SET / NOT SET. Use `sed 's/=.*/=***/'` when listing env vars.
- **Test fragments round-trip:** reset target files, apply, verify — before committing. Test all three paths (all tools, no tools, partial).
- **Never guess external values.** Commit SHAs, version numbers, API signatures, URLs — if you're not certain, look it up (`git ls-remote`, docs, web search). Fabricated-but-plausible values waste more time than admitting you need to check.
- **Check upstream overlap before adding to fragments.** If upstream already provides something, don't duplicate it. Run `scripts/validate-patches.sh` to audit.
