@AGENTS.md

## Claude Code

- **To deploy NemoClaw, use `/setup`.** It handles env config, prerequisites, running setup.sh, and post-install auth — interactively, with minimal user burden.
- **To upgrade a running deployment, use `/upgrade`.** It checks versions, validates patches, backs up, and rebuilds only if needed. Also handles adding integrations — just update `.env` and run `/upgrade`.
- Use `/refresh-patches` when fragments fail against upstream NemoClaw.
- Prefer `Edit` over `Write` for fragment files — small targeted changes.
- When modifying fragments, always verify the round-trip: reset, apply, check. Test all three paths (all tools, no tools, partial).
- Use `/backup` before destructive operations (destroy, rebuild). Use `/restore` after deploying a new instance.
