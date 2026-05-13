# Upstream Compatibility

Last validated end-to-end deployment: **2026-05-12**

| Component | Commit / Tag | Description | Link |
|-----------|-------------|-------------|------|
| NemoClaw | `c4aaec3bb` (v0.0.38) | `fix(runtime): repair stale inference DNS routes (#3267)` | [commit](https://github.com/NVIDIA/NemoClaw/commit/c4aaec3bb) |
| OpenShell | `4483c860` (v0.0.36) | `feat(server,driver-vm,e2e): gateway-owned readiness + VM compute driver e2e (#901)` | [commit](https://github.com/NVIDIA/OpenShell/commit/4483c860) |
| sandbox-base | `47a54a53` | OpenClaw 2026.4.24 (npm openclaw@2026.4.24) | [package](https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base) |

## What this means

- **Patch fragments in `patches/fragments/` were tested against these versions.** They may apply cleanly to newer upstream commits, or they may need refreshing.
- **This is not a pin.** `setup.sh` always clones latest upstream and pulls `sandbox-base:latest`. These versions record what was running when the cookbook last had a successful end-to-end deployment.
- **sandbox-base tags are NemoClaw commit SHAs.** The image isn't rebuilt on every NemoClaw commit, so the image tag and the NemoClaw repo HEAD can differ.

## What this cookbook adds over upstream

Present-state inventory of cookbook patches and scripts, with the condition for removing each. Search upstream (`gh search issues --repo NVIDIA/NemoClaw …`) when touching any of these to see whether the gap has already been closed.

| Cookbook component | Upstream gap filled | Remove when |
|--------------------|--------------------|-------------|
| `patches/fragments/dockerfile-claude-code`, `patches/fragments/policy-claude-code.yaml` | Claude Code binary + SSO/download network policy not provided by upstream NemoClaw | (out of upstream scope — stays permanently) |
| `patches/fragments/dockerfile-codex`, `patches/fragments/policy-codex.yaml` | Codex CLI binary + OpenAI auth/download network policy not provided by upstream NemoClaw | (out of upstream scope — stays permanently) |
| `patches/fragments/dockerfile-core` | Git HTTPS + CA-bundle configuration inside the sandbox so plugin/marketplace cloning works | Upstream Dockerfile baseline adopts equivalent git HTTPS config |
| `patches/fragments/dockerfile-integrations`, `patches/fragments/policy-tavily.yaml`, `build_integrations_config()` in `setup.sh` | Upstream web-search onboarding supports Brave only; Tavily is not a first-class provider | Upstream ships Tavily (and other third-party providers) as a first-class web-search option with matching policy preset |
| `setup.sh` auto-deriving `NEMOCLAW_POLICY_PRESETS` from configured messaging tokens | Upstream's tier-based policy selector excludes messaging presets from `balanced` by default, with no token-driven inclusion in non-interactive mode | Upstream restores token-driven preset inclusion (or ships an equivalent tier that covers the common case) |
| `setup.sh` pinning `OPENSHELL_VERSION` to NemoClaw's `max_openshell_version` | OpenShell release cadence runs ahead of NemoClaw's `blueprint.yaml` constraint, so `install.sh` grabs a version NemoClaw's preflight rejects | NemoClaw's release cadence keeps `max_openshell_version` current with published OpenShell releases |

When adding a new cookbook patch, add a row here describing the gap and the removal condition. When removing a patch (upstream closed the gap), delete both the patch and the row.

## Checking for drift

Run the validation script to see if patches still apply against current upstream:

```bash
./scripts/validate-patches.sh
```

If patches fail, see [BUILD.md § Refreshing Patches](BUILD.md#refreshing-patches-after-upstream-updates) or run `claude /refresh-patches`.

## Updating this file

After a successful end-to-end deployment against newer upstream:

```bash
# On the Brev instance:
git -C ~/NemoClaw log --oneline -1
git -C ~/OpenShell log --oneline -1
# sandbox-base commit SHA is embedded as an OCI label on the pulled image:
docker inspect ghcr.io/nvidia/nemoclaw/sandbox-base:latest \
  --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
```

Update the table above with the new values and today's date.
