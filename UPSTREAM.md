# Upstream Compatibility

Last validated end-to-end deployment: **2026-05-27 UTC / 2026-05-26 PDT**

Deployment target: Brev instance `srick-sae-dev-nemoclaw`

Latest published NemoClaw tag checked: **v0.0.52** (`a5768a2`, published 2026-05-27). The verified deployment used upstream `main` at `a784f470b`, which was 6 commits past `latest` / `v0.0.52` at validation time.

| Component | Verified revision | Deployment evidence | Link |
|-----------|-------------------|---------------------|------|
| NemoClaw | `a784f470b282140dd7c342892a7b7145691bf3b1` | `fix(policy): resolve openshell binary path so policy-add works in non-interactive shells (#4224) (#4228)`; `git describe` reported `latest-6-ga784f470b-dirty` after cookbook patches were applied | [commit](https://github.com/NVIDIA/NemoClaw/commit/a784f470b282140dd7c342892a7b7145691bf3b1) |
| NemoClaw latest tag | `v0.0.52` at `a5768a2` | GitHub tags page showed `v0.0.52` / `latest` published on 2026-05-27 | [tag](https://github.com/NVIDIA/NemoClaw/releases/tag/v0.0.52) |
| NemoClaw blueprint | `version: "0.1.0"` | `min_openshell_version: "0.0.44"`, `max_openshell_version: "0.0.44"`, `min_openclaw_version: "2026.3.11"` | [blueprint](https://github.com/NVIDIA/NemoClaw/blob/main/nemoclaw-blueprint/blueprint.yaml) |
| OpenShell | `0.0.44` (`d255cdd`) | Upstream NemoClaw installed and used OpenShell `0.0.44`; gateway preflight passed after the host firewall rule printed by NemoClaw was applied | [tag](https://github.com/NVIDIA/OpenShell/releases/tag/v0.0.44) |
| OpenClaw runtime | `2026.5.22 (a374c3a)` | `scripts/verify-deployment.sh` confirmed OpenClaw inside sandbox; upstream Dockerfile sets `ARG OPENCLAW_VERSION=2026.5.22` | [npm](https://www.npmjs.com/package/openclaw/v/2026.5.22) |
| sandbox base | `sha256:b3d832b596ab6b7184a9dcb4ae93337ca32851a4f93b00765cc12de26baa3a9a` | Deployed from the digest in upstream `nemoclaw-blueprint/blueprint.yaml` | [package](https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base) |

## Deployment Evidence

This file records only validated deployments. Do not update the table from source review, tag review, or patch validation alone.

The 2026-05-27 validation covered:

- `./scripts/validate-patches.sh` against upstream `a784f470b`.
- Full `./setup.sh` on Brev with the revised cookbook patch set.
- OpenShell gateway preflight and sandbox build.
- Upstream policy selection in non-interactive mode. With Telegram configured, upstream applied `npm`, `pypi`, `huggingface`, `brew`, and `telegram`, so the cookbook no longer derives `NEMOCLAW_POLICY_PRESETS`.
- `scripts/verify-deployment.sh my-assistant` passed after a dashboard forward restart.
- Web UI URL/token helper files were written without printing token values.
- Native Telegram channel was installed, configured, and enabled.
- Tavily was selected as the web-search provider in `/sandbox/.openclaw/openclaw.json`.
- OpenAI-compatible HTTP endpoints were enabled: `/v1/models` returned 3 models and `/v1/chat/completions` returned a response.
- Host services were active: nginx proxy, terminal WebSocket service, Secure Link URL file, and deployment manifest.

Deployment note: the first setup attempt failed because UFW blocked sandbox-to-host gateway traffic at `172.18.0.1:8080`. NemoClaw printed the needed UFW rule. After applying that exact rule, setup and verification passed. Keep the docs pointed at NemoClaw's printed rule rather than baking in a broad cookbook rule.

Known non-blocking signal: `nemoclaw status` still reported the in-container Docker health probe as unhealthy, while the host-side verification chain passed. Treat the host-side checks as authoritative until upstream resolves the stale health signal behavior.

## What This Means

- Patch fragments in `patches/fragments/` were tested against the validated upstream revision above.
- This is not a pin. `setup.sh` follows upstream latest and lets upstream NemoClaw resolve OpenShell, OpenClaw, and sandbox-base.
- The cookbook should shrink when upstream closes a gap. When upstream absorbs something, delete the cookbook version and this file's row for it.
- New cookbook patches need a removal condition before they are accepted.

## Remaining Cookbook Surface

Present-state inventory of cookbook-owned behavior, with the condition for removing each item.

| Cookbook component | Upstream gap filled | Remove when |
|--------------------|---------------------|-------------|
| `patches/fragments/dockerfile-integrations`, the Tavily block in `scripts/build-integrations-config.py`, `patches/fragments/policy-tavily.yaml`, and the `nemoclaw-start.sh` `.env` sourcing patch in `scripts/apply-patches.sh` | Upstream web-search onboarding supports Brave. Tavily is not yet a first-class upstream provider, and third-party plugin credentials are not passed through as first-class onboard inputs. | Upstream ships Tavily web search support or a generic provider/plugin credential passthrough. Track [NemoClaw#2105](https://github.com/NVIDIA/NemoClaw/pull/2105), [#2718](https://github.com/NVIDIA/NemoClaw/pull/2718), and [#1720](https://github.com/NVIDIA/NemoClaw/pull/1720). |
| OpenAI HTTP block in `scripts/build-integrations-config.py`, `/v1/` CORS proxying in `config/nginx.conf.template`, `__OPENAI_HTTP_DENY__` in `scripts/install-services.sh`, `~/openclaw-openai.env` in `scripts/save-ui-url.sh`, and `/v1/models` verification in `scripts/verify-deployment.sh` | NemoClaw has no env flag to enable OpenClaw's OpenAI-compatible HTTP endpoints, and OpenClaw does not terminate browser CORS for `/v1/*`. | NemoClaw adds a native `NEMOCLAW_OPENAI_HTTP_ENABLED`-style config path, and OpenClaw handles `Access-Control-Allow-*` plus `OPTIONS` for `/v1/*`. These can retire independently. |
| Post-deploy `/sandbox/.env` injection and driver-aware sandbox bounce in `setup.sh` | Tavily's runtime credential must be provided after onboard because upstream has no generic third-party plugin credential path. | Upstream onboard can pass arbitrary plugin/provider secrets into the sandbox without a post-boot mutation. |
| `setup.sh` failed-onboard recovery via `NEMOCLAW_FRESH=1` when an onboard session marker exists | A failed first run can leave NemoClaw resuming a stale partial onboard session. | Upstream detects failed prior onboard sessions and offers or applies a clean restart. |
| Host-side access and operations helpers: nginx template, terminal WebSocket service, URL/env writers, manifest writer, verifier, backup/restore scripts | The cookbook still provides a deployment recipe around upstream NemoClaw for Brev-style host access, validation, and recovery. | Upstream ships equivalent host-access, validation, and backup workflows, or the cookbook stops covering that deployment shape. |

## Dropped After v0.0.52 Review

These are intentionally gone from the cookbook because upstream either owns the area now or the experiment is no longer needed:

- Claude Code, Codex, and plugin/marketplace sandbox overlays.
- `patches/fragments/dockerfile-core` git HTTPS/CA baseline patch.
- Cookbook `NEMOCLAW_POLICY_PRESETS` derivation. Verified upstream now includes messaging presets when the corresponding token is configured.
- Cookbook OpenShell checkout/version pinning. Upstream blueprint constraints and installer flow own this.
- Cookbook OpenClaw version override. Upstream Dockerfile owns `OPENCLAW_VERSION`.

## What The Cookbook Deliberately Does Not Manage

- OpenShell gateway lifecycle. Gateway start, stop, recover, and preflight are upstream NemoClaw responsibilities.
- OpenShell version selection beyond passing through upstream's blueprint constraints.
- OpenClaw runtime version selection.
- Brave Search onboarding, because upstream already handles it.
- Sandbox-installed coding-agent tools such as Claude Code, Codex, or local plugin scaffolding.
- Upstream policy preset selection, except for cookbook-only policy fragments that support cookbook-only integrations such as Tavily.

## Checking For Drift

Run the validation script before changing fragments:

```bash
./scripts/validate-patches.sh
```

If patches fail, refresh anchors around the upstream design rather than preserving old line positions. If validation warns that upstream now exposes a native equivalent, prefer deleting the cookbook overlay.

## Updating This File

Update this file only after a successful end-to-end deployment and verification run.

On the deployment host:

```bash
git -C ~/NemoClaw rev-parse HEAD
git -C ~/NemoClaw log -1 --pretty=%s
git -C ~/NemoClaw describe --tags --always --dirty
git -C ~/NemoClaw show HEAD:nemoclaw-blueprint/blueprint.yaml | grep -E '^(version:|digest:|min_openshell_version:|max_openshell_version:|min_openclaw_version:)'
scripts/verify-deployment.sh my-assistant
```

Also verify the cookbook-specific surfaces that were enabled in that deployment, such as Tavily search, OpenAI-compatible HTTP, messaging channels, and host access files. Do not print token-bearing URLs or secret values while collecting evidence.
