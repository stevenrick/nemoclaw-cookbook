# Upstream Compatibility

Last validated end-to-end deployment: **2026-05-12**

| Component | Commit / Tag | Description | Link |
|-----------|-------------|-------------|------|
| NemoClaw | `c4aaec3bb` (v0.0.38) | `fix(runtime): repair stale inference DNS routes (#3267)` | [commit](https://github.com/NVIDIA/NemoClaw/commit/c4aaec3bb) |
| OpenShell | `4483c860` (v0.0.36) | `feat(server,driver-vm,e2e): gateway-owned readiness + VM compute driver e2e (#901)` | [commit](https://github.com/NVIDIA/OpenShell/commit/4483c860) |
| sandbox-base | `47a54a53` | OpenClaw 2026.4.24 (npm openclaw@2026.4.24) | [package](https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base) |

## What this means

- **Patch fragments in `patches/fragments/` were tested against the validated versions above.** They may apply cleanly to newer upstream commits, or they may need refreshing.
- **This is not a pin.** `setup.sh` always clones latest upstream and pulls `sandbox-base:latest`. These versions record what was running when the cookbook last had a successful end-to-end deployment.
- **sandbox-base tags are NemoClaw commit SHAs.** The image isn't rebuilt on every NemoClaw commit, so the image tag and the NemoClaw repo HEAD can differ.

## What this cookbook adds over upstream

Present-state inventory of cookbook patches and scripts, with the condition for removing each. Search upstream (`gh search issues --repo NVIDIA/NemoClaw …`) when touching any of these to see whether the gap has already been closed.

| Cookbook component | Upstream gap filled | Remove when |
|--------------------|--------------------|-------------|
| `patches/fragments/dockerfile-claude-code`, `patches/fragments/policy-claude-code.yaml` | Claude Code binary + SSO/download network policy not provided by upstream NemoClaw | (out of upstream scope — stays permanently) |
| `patches/fragments/dockerfile-codex`, `patches/fragments/policy-codex.yaml` | Codex CLI binary + OpenAI auth/download network policy not provided by upstream NemoClaw | (out of upstream scope — stays permanently) |
| `patches/fragments/dockerfile-core` | Git HTTPS + CA-bundle configuration inside the sandbox so plugin/marketplace cloning works | Upstream Dockerfile baseline adopts equivalent git HTTPS config |
| `patches/fragments/dockerfile-integrations`, `patches/fragments/policy-tavily.yaml`, `build_integrations_config()` in `setup.sh`, and the `nemoclaw-start.sh` `.env`-sourcing patch in `apply-patches.sh` | Upstream web-search onboarding supports Brave only; Tavily is not a first-class provider, and there is no first-class passthrough for third-party plugin credentials | Any of [NemoClaw#2105](https://github.com/NVIDIA/NemoClaw/pull/2105) (Tavily as web search provider), [#2718](https://github.com/NVIDIA/NemoClaw/pull/2718) (extend web search onboarding to Gemini/Tavily), or [#1720](https://github.com/NVIDIA/NemoClaw/pull/1720) (arbitrary OpenShell providers for non-inference credentials) lands |
| Driver-aware sandbox bounce in `setup.sh` Step 8 (`docker exec … kubectl delete pod` on k3s, `docker restart` on docker-driver) after injecting `/sandbox/.env` | No first-class upstream mechanism to pass third-party plugin credentials at onboard time, so the cookbook injects post-boot and bounces to reload | [NemoClaw#1720](https://github.com/NVIDIA/NemoClaw/pull/1720) lands — bake the credentials into onboard ARGs and remove the post-deploy bounce |
| `setup.sh` auto-deriving `NEMOCLAW_POLICY_PRESETS` from configured messaging tokens | Upstream's tier-based policy selector excludes messaging presets from `balanced` by default, with no token-driven inclusion in non-interactive mode | Upstream restores token-driven preset inclusion (or ships an equivalent tier that covers the common case) |
| `setup.sh` pinning `OPENSHELL_VERSION` to NemoClaw's `max_openshell_version` (plus pinning the OpenShell repo checkout to the same tag) | OpenShell release cadence runs ahead of NemoClaw's `blueprint.yaml` constraint, and HEAD's `install.sh` may expect a newer artifact format than older releases ship | NemoClaw's release cadence keeps `max_openshell_version` current with published OpenShell releases, and OpenShell's installer maintains backward-compatible release artifacts |

When adding a new cookbook patch, add a row here describing the gap and the removal condition. When removing a patch (upstream closed the gap), delete both the patch and the row.

### What the cookbook deliberately does not manage

- **OpenShell gateway lifecycle.** The gateway is started, stopped, and recovered by upstream `nemoclaw` (`nemoclaw <sandbox> recover` brings it back if it's down). `scripts/install-services.sh` removes any `openshell-gateway.service` unit it finds so deployments converge on this model.

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
