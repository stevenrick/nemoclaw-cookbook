# Upstream Compatibility

Last validated end-to-end deployment: **2026-04-09**

| Component | Commit / Tag | Description | Link |
|-----------|-------------|-------------|------|
| NemoClaw | `49b9a1d2` | `docs: update ecosystem doc based on the latest codebase (#1681)` | [commit](https://github.com/NVIDIA/NemoClaw/commit/49b9a1d2) |
| OpenShell | `09581293` | `feat(ci): add release-vm-dev pipeline and install-vm.sh installer (#788)` | [commit](https://github.com/NVIDIA/OpenShell/commit/09581293) |
| sandbox-base | `045a340` | Image tag pulled at deploy time | [package](https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base) |

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
