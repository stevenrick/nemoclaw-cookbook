# Coding Agent Instructions

This is a thin patch overlay on upstream [NemoClaw](https://github.com/NVIDIA/NemoClaw) + [OpenShell](https://github.com/NVIDIA/OpenShell). It is NOT a fork.

## Project structure

```
setup.sh              # Automated setup — clones upstream, applies patches, installs
patches/
  Dockerfile.patch    # Adds Claude Code, Codex CLI, Codex plugin, git HTTPS/SSL config
  policy.patch        # Opens network endpoints for auth (Claude, OpenAI, GitHub, Brave Search)
  onboard.patch       # Creates + attaches integration providers (Brave Search) at sandbox creation
scripts/
  validate-patches.sh # Check patches still apply against upstream
  backup-full.sh      # Workspace + chat history backup/restore
BUILD.md              # Step-by-step setup with explanations
USE.md                # Day-to-day commands and features
CONTRIBUTING.md       # Contribution guidelines
.claude/skills/       # Claude Code skills (e.g. /refresh-patches, /add-integration)
```

## Getting started

**If the user wants to deploy NemoClaw**, don't follow the README manually. Claude Code users should run `/setup` which handles everything interactively. Other agents: read BUILD.md and follow it step by step — the key is to create `~/.env` first, check what's configured, and only ask the user for credentials they need to provide.

## Key docs (read these, don't duplicate them)

- **BUILD.md** — full setup walkthrough, what each patch does and why, environment variables, troubleshooting
- **USE.md** — sandbox commands, authentication flow, Telegram bridge, rebuilding
- **CONTRIBUTING.md** — contribution standards

## Rules

- **Keep patches minimal.** They should apply cleanly on upstream NemoClaw with `git apply --3way`. Fewer context lines = less breakage surface.
- **Don't modify upstream repos directly.** All customizations go through `patches/` and `setup.sh`.
- **Preserve patch intent, not exact lines.** If upstream restructures, adapt placement but keep the logical additions (see BUILD.md § Refreshing Patches).
- **Don't add features beyond what's asked.** This is a cookbook — lean and opinionated.
- **Secrets belong in `~/.env`, never committed.** `.gitignore` covers `.env`.
- **Test patches round-trip:** reset target files, apply, verify — before committing.
- **Never guess external values.** Commit SHAs, version numbers, API signatures, URLs — if you're not certain, look it up (`git ls-remote`, docs, web search). Fabricated-but-plausible values waste more time than admitting you need to check.
