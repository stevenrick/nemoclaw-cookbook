# Upstream Compatibility

Last validated end-to-end deployment: **2026-03-30**

| Component | Commit / Tag | Description | Link |
|-----------|-------------|-------------|------|
| NemoClaw | `c99e3e8` | `fix(onboard): reject sandbox names starting with a digit and allow retry` | [commit](https://github.com/NVIDIA/NemoClaw/commit/c99e3e8) |
| OpenShell | `491c5d81` | `fix(bootstrap,server): persist sandbox state across gateway stop/start cycles` | [commit](https://github.com/NVIDIA/OpenShell/commit/491c5d81) |
| sandbox-base | `c269f38` | Image tag (NemoClaw commit SHA) pulled at deploy time | [package](https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base) |

## What this means

- **Patches in `patches/` were generated and tested against these versions.** They may apply cleanly to newer upstream commits, or they may need refreshing.
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
docker images ghcr.io/nvidia/nemoclaw/sandbox-base --format '{{.Tag}}'
```

Update the table above with the new values and today's date.
