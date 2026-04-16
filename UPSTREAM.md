# Upstream Compatibility

Last validated end-to-end deployment: **2026-04-16**

| Component | Commit / Tag | Description | Link |
|-----------|-------------|-------------|------|
| NemoClaw | `4f30b9dc` | `fix(security): add authenticated reverse proxy for local Ollama (#1922)` | [commit](https://github.com/NVIDIA/NemoClaw/commit/4f30b9dc) |
| OpenShell | `25d2530b` | `fix(inference): allowlist routed request headers (#826)` | [commit](https://github.com/NVIDIA/OpenShell/commit/25d2530b) |
| sandbox-base | `75c08a1a` | `feat(compat): bump openclaw from 2026.3.11 to 2026.4.2 (#1522)` — OpenClaw 2026.4.2 | [package](https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base) |

## What this means

- **Patch fragments in `patches/fragments/` were tested against these versions.** They may apply cleanly to newer upstream commits, or they may need refreshing.
- **This is not a pin.** `setup.sh` always clones latest upstream and pulls `sandbox-base:latest`. These versions record what was running when the cookbook last had a successful end-to-end deployment.
- **sandbox-base tags are NemoClaw commit SHAs.** The image isn't rebuilt on every NemoClaw commit, so the image tag and the NemoClaw repo HEAD can differ.

## Upstream work we're tracking

Open upstream PRs/issues that would let us shrink or delete cookbook patches. When any of these lands, the referenced fragments can be removed (see [CONTRIBUTING.md § Working upstream](CONTRIBUTING.md#working-upstream)).

| Upstream | Would obsolete | Notes |
|----------|----------------|-------|
| [NemoClaw#1497](https://github.com/NVIDIA/NemoClaw/pull/1497) — `feat(onboard): extend web search onboarding to Gemini and Tavily` | `patches/fragments/policy-tavily.yaml`, `patches/fragments/dockerfile-integrations`, setup.sh Tavily plumbing | Adds `tavily` and `gemini` as first-class web-search providers with policy presets. Also makes `/sandbox/.openclaw/openclaw.json` writable via symlink. Open, awaiting maintainer review. Blockers reported in [#1497#issuecomment-4262976883](https://github.com/NVIDIA/NemoClaw/pull/1497#issuecomment-4262976883): Dockerfile Python `SyntaxError` on compound statements after `;`, and web-search API key written in plaintext to `openclaw.json` (regression vs [#1835](https://github.com/NVIDIA/NemoClaw/pull/1835)). |
| NemoClaw `max_openshell_version` lag behind OpenShell releases | Blueprint-derived `OPENSHELL_VERSION` pin in `setup.sh` and `/upgrade` (Phase 7) | OpenShell cut v0.0.27 through v0.0.31 in the four days after NemoClaw set `max_openshell_version: "0.0.26"` in `blueprint.yaml`. Without intervention, `sh install.sh` grabs latest and `nemoclaw onboard` preflight rejects it. Cookbook works around this by deriving the install version from NemoClaw's blueprint. When NemoClaw starts cutting releases that bump `max_openshell_version` to match OpenShell's cadence, the pin becomes a no-op and this scaffold can be removed. |

When contributing a cookbook patch for something that *could* be upstream, open a companion upstream issue/PR and add it to this table so we know to delete the patch when it lands.

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
