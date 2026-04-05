@AGENTS.md

## Claude Code

- **To deploy NemoClaw, use `/setup`.** It handles env config, prerequisites, running setup.sh, and post-install auth — interactively, with minimal user burden.
- Use `/refresh-patches` when patches fail against upstream NemoClaw.
- Prefer `Edit` over `Write` for patch files — small targeted changes.
- When modifying patches, always verify the round-trip: reset, apply, check.
- Use `/backup` before destructive operations (destroy, rebuild). Use `/restore` after deploying a new instance.
