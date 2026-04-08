# Upstream Compatibility

Last validated end-to-end deployment: **2026-04-08**

| Component | Commit / Tag | Description | Link |
|-----------|-------------|-------------|------|
| NemoClaw | `86f94a2` | `fix(inference): increase timeout for local providers to 180s` | [commit](https://github.com/NVIDIA/NemoClaw/commit/86f94a2) |
| OpenShell | `c2e52567` | `ci(gpu): add separate GPU test workflows (#773)` | [commit](https://github.com/NVIDIA/OpenShell/commit/c2e52567) |
| sandbox-base | `latest` | Image tag pulled at deploy time | [package](https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base) |

## What this means

- **Patch fragments in `patches/fragments/` were tested against these versions.** They may apply cleanly to newer upstream commits, or they may need refreshing.
- **This is not a pin.** `setup.sh` always clones latest upstream and pulls `sandbox-base:latest`. These versions record what was running when the cookbook last had a successful end-to-end deployment.
- **sandbox-base tags are NemoClaw commit SHAs.** The image isn't rebuilt on every NemoClaw commit, so the image tag and the NemoClaw repo HEAD can differ.

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
# sandbox-base tag: look up the most recent commit SHA tag at
# https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base
# (docker images only shows "latest" locally)
```

Update the table above with the new values and today's date.
