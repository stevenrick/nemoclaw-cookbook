# Upstream Compatibility

Last validated end-to-end deployment: **2026-08-04 UTC / 2026-08-04 PDT**

Deployment target: Brev instance `srick-saw-dev-nemoclaw`

Latest upstream refs checked: `latest` and `v0.0.101` tag object `7000dbad7`,
both peeling to commit `f12ae8d4` at validation time. The verified deployment
used upstream `main` at `dd7db61d`, which was 78 commits past `latest` /
`v0.0.101`.

| Component | Verified revision | Deployment evidence | Link |
|-----------|-------------------|---------------------|------|
| NemoClaw | `dd7db61dd0a25f91f05945d59d6d4303b3c07f38` | `ci(images): add protected buildless qualification batch (#8234)`; `git describe` reported `v0.0.101-78-gdd7db61dd-dirty` after cookbook patches were applied | [commit](https://github.com/NVIDIA/NemoClaw/commit/dd7db61dd0a25f91f05945d59d6d4303b3c07f38) |
| NemoClaw latest/version tags | `latest` and `v0.0.101` tag `7000dbad7`; peeled commit `f12ae8d4` | `git ls-remote --tags` checked both refs on 2026-08-04 | [v0.0.101](https://github.com/NVIDIA/NemoClaw/releases/tag/v0.0.101) |
| NemoClaw blueprint | `version: "0.1.0"` | `min_openshell_version: "0.0.85"`, `max_openshell_version: "0.0.85"`, `min_openclaw_version: "2026.3.11"` | [blueprint](https://github.com/NVIDIA/NemoClaw/blob/main/nemoclaw-blueprint/blueprint.yaml) |
| OpenShell | `0.0.85` (`3dee5570`) | Upstream NemoClaw installed and used OpenShell `0.0.85`; gateway verification passed | [tag](https://github.com/NVIDIA/OpenShell/releases/tag/v0.0.85) |
| OpenClaw runtime | `2026.7.1 (2d2ddc4)` | `scripts/verify-deployment.sh` confirmed OpenClaw inside sandbox; upstream Dockerfile sets `ARG OPENCLAW_VERSION=2026.7.1` | [npm](https://www.npmjs.com/package/openclaw/v/2026.7.1) |
| sandbox base | `sha256:b3d832b596ab6b7184a9dcb4ae93337ca32851a4f93b00765cc12de26baa3a9a` | Deployed from the digest in upstream `nemoclaw-blueprint/blueprint.yaml` | [package](https://github.com/NVIDIA/NemoClaw/pkgs/container/nemoclaw%2Fsandbox-base) |

## Deployment Evidence

This file records only validated deployments. Do not update the table from source
review, tag review, or patch validation alone.

The 2026-08-04 validation covered:

- `./scripts/validate-patches.sh` against upstream `dd7db61d`.
- Full `./setup.sh` on Brev instance `srick-saw-dev-nemoclaw` from a staged
  cookbook working tree.
- Existing deployment backup to `/home/ubuntu/.nemoclaw/backups/20260804-190740/`
  before upgrade, plus NemoClaw's pre-rebuild backup of `my-assistant`.
- Remote `~/.env` was sourced by setup; secret-bearing values were not printed.
- Environment alignment with upstream native web search:
  `NEMOCLAW_WEB_SEARCH_PROVIDER=tavily` and `TAVILY_API_KEY` were set.
- OpenShell gateway preflight, sandbox build, dashboard startup, and sandbox
  readiness.
- Cookbook workaround installed reviewed `@openclaw/tavily-plugin@2026.7.1`
  before the upstream Tavily doctor step, resolving the upstream inspect-only
  build failure.
- Tavily policy preset loaded, and `scripts/verify-deployment.sh` verified
  Tavily egress inside the sandbox.
- OpenAI-compatible HTTP endpoints were enabled by the remaining cookbook overlay:
  `/v1/models` returned HTTP 200 through the host nginx route.
- Native Telegram channel was configured by upstream NemoClaw.
- Host services were active: nginx proxy, terminal WebSocket service, Secure Link
  URL file, OpenAI HTTP env file, and deployment manifest.
- `scripts/verify-deployment.sh` passed. Final manifest commit:
  `dd7db61dd`; deployed at `2026-08-04T20:05:49Z`.

Known non-blocking signal: upstream npm install printed audit summaries
(`8 vulnerabilities` in the main dependency install and `2 vulnerabilities` in
the plugin build), but setup continued through CLI/plugin build, link reported
`found 0 vulnerabilities`, and deployment verification passed. The blocking
failure encountered during this upgrade was the missing Tavily plugin install,
not npm audit.

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
| Disallowed sandbox coding-agent install stripping in `scripts/apply-patches.sh` | Some upstream Dockerfile revisions installed Claude Code or Codex inside the sandbox through unpinned remote install paths. This cookbook does not ship sandbox-installed coding-agent tools. | Upstream no longer installs Claude Code, Codex, or equivalent sandbox coding-agent CLIs, or upstream provides a policy-controlled way to omit them. |
| Reviewed Tavily plugin install in `scripts/apply-patches.sh` | Upstream NemoClaw `dd7db61d` configures Tavily web search but only runs `openclaw plugins inspect tavily`; OpenClaw `2026.7.1` does not include that plugin by default, so the Docker build fails before `openclaw doctor`. | Upstream installs a reviewed Tavily plugin package, bundles Tavily in the OpenClaw runtime, or removes the inspect-only requirement while preserving verified Tavily web search. |
| `setup.sh` failed-onboard recovery via `NEMOCLAW_FRESH=1` when an onboard session marker exists | A failed first run can leave NemoClaw resuming a stale partial onboard session. | Upstream detects failed prior onboard sessions and offers or applies a clean restart. |
| `setup.sh` source-mode normalization and `package-lock.json` reset before upstream pull/patch application | Brev's default umask can leave the upstream checkout group-writable, which trips NemoClaw's build-time payload mode checks; upstream dependency installs can also dirty `package-lock.json` and block `git pull --ff-only`. | Upstream resets all installer-mutated files before pull and makes Docker payload metadata independent of host checkout umask, or upstream setup normalizes source file modes before Docker build. |
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
- Brave or Tavily Search onboarding, except for the temporary reviewed Tavily
  plugin install workaround listed above.
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
