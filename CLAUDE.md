@AGENTS.md

## Claude Code

- **To deploy NemoClaw, use `/setup`.** It handles env config, prerequisites, running setup.sh, and post-install auth — interactively, with minimal user burden.
- **To upgrade a running deployment, use `/upgrade`.** It checks versions, validates patches, backs up, and rebuilds only if needed. Also handles adding integrations — just update `.env` and run `/upgrade`.
- Use `/refresh-patches` when fragments fail against upstream NemoClaw.
- Prefer `Edit` over `Write` for fragment files — small targeted changes.
- When modifying fragments, always verify the round-trip: reset, apply, check. Test all three paths (all tools, no tools, partial).
- Use `/backup` before destructive operations (destroy, rebuild). Use `/restore` after deploying a new instance.

## Working upstream from the cookbook

When the work you're doing will land in NVIDIA/NemoClaw or NVIDIA/OpenShell (not the cookbook itself), invoke `/contribute-upstream` first. It scans the upstream repo for *current* practice docs, contributor skills, and ratchets — no hardcoded paths — and grounds you in whatever upstream currently expects of contributors. The cookbook is downstream; upstream is the source of truth for upstream practice, and it evolves.

### Design discipline for upstream changes

Six rules. The cookbook has earned each of these through PRs that almost shipped wrong (or did, and got reverted within hours). Walk them before writing code, not after CI flags something.

1. **Root cause first.** Articulate the root cause in one or two sentences. If you can only describe the symptom, keep investigating — the fix you write will only patch what you see.
2. **Mirror reality.** When adding a probe or check that exercises a real system, locate the canonical setup in the codebase and match its configuration exactly (network mode, `--add-host` flags, env, entrypoint). Approximations leak across host/driver configurations.
3. **Diagnostic = proven fact.** Error messages state what your code can prove. Hypotheses about cause (firewall, DNS, routing) go as one of several possible causes, never as the headline of an actionable error. Wrong diagnoses waste user time and erode trust.
4. **Conservative defaults for new diagnostics.** First iteration of a check warns and continues. Fail-hard only when you have proof of a known-bad state, not when you fail to reach a known-good one.
5. **Deployment matrix.** Identify which drivers/hosts/configurations the changed code path supports. Validate against at least two distinct configurations, or scope the PR to one and call that out in the PR body.
6. **Live-reproduce first.** If the bug has a reproduction, run your proposed fix mechanism manually against it before writing code. Code is the last thing you write, not the first.

### Merged ≠ done

An upstream PR isn't done when it merges. It's done when it survives ~48 hours without a revert, supersession, or follow-up issue. Watch the PR's surface area in upstream for that window. If something appears, read it as data — identify which of the six rules above wasn't satisfied — and let the next change of similar shape benefit from the lesson. Don't keep a journal; the lesson lives in the engineer.
