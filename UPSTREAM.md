# Upstream Compatibility

Last validated end-to-end deployment: **2026-07-16 UTC / 2026-07-16 PDT**

Deployment target: Brev instance `srick-saw-dev-nemoclaw`

Latest upstream refs checked: `latest` tag object `eed4385a7` and `v0.0.84`
tag object `e9bcdac99`, both peeling to commit `c1bda8069` at validation time.
The verified deployment used upstream `main` at `d034b7f0e`, which was 17 commits
past `latest` / `v0.0.84`.

| Component | Verified revision | Deployment evidence | Link |
|-----------|-------------------|---------------------|------|
| NemoClaw | `d034b7f0e8e087f4db078ff119bc56173b186953` | `fix(onboard): recover custom endpoint DNS failures (#6865)`; `git describe` reported `latest-17-gd034b7f0e-dirty` after cookbook patches were applied | [commit](https://github.com/NVIDIA/NemoClaw/commit/d034b7f0e8e087f4db078ff119bc56173b186953) |
| NemoClaw latest/version tags | `latest` tag `eed4385a7`; `v0.0.84` tag `e9bcdac99`; peeled commit `c1bda8069` | `git ls-remote --tags` checked both refs on 2026-07-16 | [v0.0.84](https://github.com/NVIDIA/NemoClaw/releases/tag/v0.0.84) |
| NemoClaw blueprint | `version: "0.1.0"` | `min_openshell_version: "0.0.72"`, `max_openshell_version: "0.0.72"`, `min_openclaw_version: "2026.3.11"` | [blueprint](https://github.com/NVIDIA/NemoClaw/blob/main/nemoclaw-blueprint/blueprint.yaml) |
| OpenShell | `0.0.72` (`8cb16de9`) | Upstream NemoClaw installed and used OpenShell `0.0.72`; gateway verification passed | [tag](https://github.com/NVIDIA/OpenShell/releases/tag/v0.0.72) |
| OpenClaw runtime | `2026.6.10 (aa69b12)` | `scripts/verify-deployment.sh` confirmed OpenClaw inside sandbox; upstream Dockerfile sets `ARG OPENCLAW_VERSION=2026.6.10` | [npm](https://www.npmjs.com/package/openclaw/v/2026.6.10) |
| sandbox base | `sha256:b3d832b596ab6b7184a9dcb4ae93337ca32851a4f93b00765cc12de26baa3a9a` | Deployed from the digest in upstream `nemoclaw-blueprint/blueprint.yaml` | [package](https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base) |

## Deployment Evidence

This file records only validated deployments. Do not update the table from source
review, tag review, or patch validation alone.

The 2026-07-16 validation covered:

- `./scripts/validate-patches.sh` against upstream `d034b7f0e`.
- Full `./setup.sh` on Brev instance `srick-saw-dev-nemoclaw` from a staged
  cookbook working tree.
- Local `.env` copied to remote `~/.env`; secret-bearing values were not printed.
- Environment alignment with upstream native web search:
  `NEMOCLAW_WEB_SEARCH_PROVIDER=tavily` and `TAVILY_API_KEY` were set.
- OpenShell gateway preflight, sandbox build, dashboard startup, and sandbox
  readiness.
- Upstream-native Tavily onboarding: provider creation, `tavily` policy preset,
  and OpenShell request-body credential rewrite.
- Live Tavily `/search` probe from inside the sandbox returned HTTP 200 with one
  result using the `openshell:resolve:env:TAVILY_API_KEY` placeholder; no result
  contents or secret values were printed.
- OpenAI-compatible HTTP endpoints were enabled by the remaining cookbook overlay:
  `/v1/models` returned HTTP 200 through the host nginx route.
- Native Telegram channel was configured by upstream NemoClaw.
- Host services were active after fixing relocated-checkout handling for the
  terminal service unit: nginx proxy, terminal WebSocket service, Secure Link URL
  file, and deployment manifest.
- `scripts/verify-deployment.sh` passed with no warnings after the terminal unit
  path fix.

Known non-blocking signal: the initial upstream setup flow printed a Tavily egress
verification warning, but the direct sandbox Tavily `/search` probe succeeded
after setup. Treat the direct HTTP 200 probe as the stronger signal for this
deployment.

## What This Means

- Patch fragments in `patches/fragments/` were tested against the validated
  upstream revision above.
- This is not a pin. `setup.sh` follows upstream latest and lets upstream
  NemoClaw resolve OpenShell, OpenClaw, and sandbox-base.
- The cookbook should shrink when upstream closes a gap. When upstream absorbs
  something, delete the cookbook version and update this inventory after a
  verified deployment.
- New cookbook patches need a removal condition before they are accepted.

## Remaining Cookbook Surface

Present-state inventory of cookbook-owned behavior, with the condition for
removing each item.

| Cookbook component | Upstream gap filled | Remove when |
|--------------------|---------------------|-------------|
| OpenAI HTTP block in `scripts/build-integrations-config.py`, config merge fragment `patches/fragments/dockerfile-integrations`, `/v1/` CORS proxying in `config/nginx.conf.template`, `__OPENAI_HTTP_DENY__` in `scripts/install-services.sh`, `~/openclaw-openai.env` in `scripts/save-ui-url.sh`, and `/v1/models` verification in `scripts/verify-deployment.sh` | NemoClaw has no env flag to enable OpenClaw's OpenAI-compatible HTTP endpoints, and OpenClaw does not terminate browser CORS for `/v1/*`. | NemoClaw adds a native `NEMOCLAW_OPENAI_HTTP_ENABLED`-style config path, and OpenClaw handles `Access-Control-Allow-*` plus `OPTIONS` for `/v1/*`. These can retire independently. |
| `setup.sh` failed-onboard recovery via `NEMOCLAW_FRESH=1` when an onboard session marker exists | A failed first run can leave NemoClaw resuming a stale partial onboard session. | Upstream detects failed prior onboard sessions and offers or applies a clean restart. |
| Host-side access and operations helpers: nginx template, terminal WebSocket service, URL/env writers, manifest writer, verifier, backup/restore scripts | The cookbook still provides a deployment recipe around upstream NemoClaw for Brev-style host access, validation, and recovery. | Upstream ships equivalent host-access, validation, and backup workflows, or the cookbook stops covering that deployment shape. |

## Dropped After v0.0.84 Review

These are intentionally gone from the cookbook because upstream either owns the
area now or the experiment is no longer needed:

- Cookbook Tavily overlay: `patches/fragments/policy-tavily.yaml`,
  `scripts/merge-policy.py`, Tavily config generation in
  `scripts/build-integrations-config.py`, Tavily env-loader patching in
  `scripts/apply-patches.sh`, and post-deploy Tavily provider registration /
  `/sandbox/.env` injection in `setup.sh`.
- Claude Code, Codex, and plugin/marketplace sandbox overlays.
- `patches/fragments/dockerfile-core` git HTTPS/CA baseline patch.
- Cookbook `NEMOCLAW_POLICY_PRESETS` derivation. Verified upstream now includes
  web-search and messaging presets when the corresponding provider/token is
  configured.
- Cookbook OpenShell checkout/version pinning. Upstream blueprint constraints and
  installer flow own this.
- Cookbook OpenClaw version override. Upstream Dockerfile owns
  `OPENCLAW_VERSION`.

## What The Cookbook Deliberately Does Not Manage

- OpenShell gateway lifecycle. Gateway start, stop, recover, and preflight are
  upstream NemoClaw responsibilities.
- OpenShell version selection beyond passing through upstream's blueprint
  constraints.
- OpenClaw runtime version selection.
- Brave or Tavily Search onboarding, because upstream already handles native web
  search provider selection.
- Sandbox-installed coding-agent tools such as Claude Code, Codex, or local
  plugin scaffolding.
- Upstream policy preset selection, except for future cookbook-only policy
  fragments that support cookbook-only integrations.

## Checking For Drift

Run the validation script before changing fragments:

```bash
./scripts/validate-patches.sh
```

If patches fail, refresh anchors around the upstream design rather than
preserving old line positions. If validation warns that upstream now exposes a
native equivalent, prefer deleting the cookbook overlay.

## Updating This File

Update this file only after a successful end-to-end deployment and verification
run.

On the deployment host:

```bash
git -C ~/NemoClaw rev-parse HEAD
git -C ~/NemoClaw log -1 --pretty=%s
git -C ~/NemoClaw describe --tags --always --dirty
git -C ~/NemoClaw show HEAD:nemoclaw-blueprint/blueprint.yaml | grep -E '^(version:|digest:|min_openshell_version:|max_openshell_version:|min_openclaw_version:)'
scripts/verify-deployment.sh
```

Also verify the cookbook-specific surfaces that were enabled in that deployment,
such as OpenAI-compatible HTTP, messaging channels, and host access files. For
upstream-native web search, verify provider/policy configuration and run a
non-printing Tavily or Brave probe if the corresponding key is configured. Do not
print token-bearing URLs or secret values while collecting evidence.
