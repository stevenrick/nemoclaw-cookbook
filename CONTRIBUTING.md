# Contributing to NemoClaw Cookbook

Thanks for your interest in contributing! This project helps you deploy and customize NemoClaw in minutes, with scripts that handle setup, upgrades, and operations.

## Working upstream

This cookbook is upstream-first: patches are temporary scaffolds, and contributions *upstream* often accomplish more than additions here. Before opening a cookbook PR for a new integration or fix:

1. **Search upstream first.** `gh search issues --repo NVIDIA/NemoClaw <keywords>` and the same for `NVIDIA/OpenShell`. Check both open PRs and recent closed ones — the work may be in-flight or already landed.
2. **If in-flight work exists**, the highest-leverage contribution is often *validating it*: check out the branch, test against a real deployment with `setup.sh`, and post concrete findings on the PR. Community PRs stalled waiting for maintainer attention frequently move after a third-party validation comment.
3. **If no upstream work exists**, consider opening an upstream issue first to confirm appetite. The cookbook patch can then serve as a reference implementation.
4. **If upstream declines** or the feature is genuinely cookbook-scope (for example host-side Brev conveniences or a temporary provider bridge), write the fragment as minimally as possible so it's easy to remove when upstream direction shifts. Note the rationale in the fragment's comments.

**When upstream ships something we patch**, delete our version — don't keep it around "just in case." The [UPSTREAM.md](UPSTREAM.md) validation date records when we last confirmed end-to-end compatibility, so update it only after a real deployment has been verified.

## How to Contribute

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Submit a pull request

## What We're Looking For

- Bug fixes in setup scripts or patches
- Support for temporary integrations that upstream does not yet handle
- Documentation improvements
- New integration examples

## Guidelines

- Keep patch fragments minimal and focused — they live in `patches/fragments/` and are applied by `scripts/apply-patches.sh`
- **Always test the round-trip** before committing patch changes: reset target files, apply your patch, verify it works
- If upstream NemoClaw broke existing patches, see [BUILD.md § Refreshing Patches](BUILD.md#refreshing-patches-after-upstream-updates)
- Run `shellcheck` on any new or modified shell scripts before committing — CI enforces this
- Use `# shellcheck source=/dev/null` before `source "$HOME/.env"` (shellcheck can't follow dynamic paths)
- When building SSH commands with ProxyCommand, use a shell function, not a string variable — quoting breaks on expansion
- Test your changes on a clean Ubuntu 22.04 environment when possible
- Use [Conventional Commits](https://www.conventionalcommits.org/) format (e.g., `feat:`, `fix:`, `docs:`)
- Do not commit credentials, API keys, tokens, tokenized dashboard URLs, or generated client env files — use `.env.example` for templates
- Do not print secret-bearing values into issues, PRs, shell transcripts, or shared logs. Prefer commands that pipe tokenized URLs directly to a browser/client, and redact with `sed 's/=.*/=***/'` or equivalent when inspection is necessary
- For systemd unit changes: validate syntax with `systemd-analyze verify /path/to/unit`
- For nginx config changes: test with `sudo nginx -t`
- `scripts/install-services.sh` must remain idempotent — safe to run multiple times without side effects

## Adding Integrations

When adding a new integration, check upstream first. NemoClaw onboard already handles some integrations (e.g., Brave Search via `NEMOCLAW_WEB_SEARCH_ENABLED`). Only add cookbook-level support for features upstream doesn't provide.

### Integration architecture

The cookbook extends the sandbox image at build time:

1. **Dockerfile integration fragment** (`patches/fragments/dockerfile-integrations`) — deep-merges config into `openclaw.json` via a base64-encoded JSON payload
2. **Config builder** (`scripts/build-integrations-config.py`) — reads `.env` flags from the environment and emits a base64-encoded JSON payload to stdout. `apply-patches.sh` invokes it automatically when `NEMOCLAW_INTEGRATIONS_B64` is unset, then bakes the result into the Dockerfile ARG default. Every caller gets the right payload by just sourcing `~/.env`.
3. **Upstream provider placeholders** — native upstream integrations should use NemoClaw/OpenShell provider placeholders such as `openshell:resolve:env:` instead of raw API key plumbing.

### Patterns to follow

- **Dockerfile fragments with compound Python** must use `printf '%s\n' 'line1' 'line2' | python3`. The `python3 -c "..."` pattern with `\` continuations collapses to a single line, breaking `def`/`for`/`if`/`else`.
- **The post-config Dockerfile anchor** (`# Pin config hash at build time so the entrypoint can verify integrity.`) is for fragments that read/modify `openclaw.json` — they need to run after all upstream config writes but before the integrity hash is computed. The pre-config anchor (`# Set up blueprint for local resolution`) runs before the config file exists.
- **Avoid raw API key plumbing when upstream has a provider path.** The `openshell:resolve:env:` prefix is preferred for native channels/providers. Do not add cookbook overlays for integrations upstream already supports.
- **Custom build args** are not passed by `nemoclaw onboard`. Bake computed values into Dockerfile ARG defaults via sed in `apply-patches.sh`.

## CI Pipeline

Every PR and push to `main` runs these checks:

| Job | What it validates |
|-----|-------------------|
| **Secret scanning** | No credentials or tokens committed (gitleaks) |
| **Validate patches** | Fragment anchors exist in upstream, `apply-patches.sh` succeeds, overlap audit |
| **Shellcheck** | All `.sh` scripts pass lint |
| **Validate JavaScript** | Terminal server syntax check (`node -c`) |
| **Validate nginx config** | nginx config syntax check (`nginx -t`) |
| **Docker build** | Full sandbox image builds from patched upstream Dockerfile |

A **daily scheduled workflow** (`upstream-drift`) runs `validate-patches.sh` against latest upstream and opens a GitHub issue (labeled `upstream-drift`) if patches no longer apply. It auto-closes when they apply again.

## Security

Do not report security vulnerabilities through GitHub issues. See [SECURITY.md](SECURITY.md) for instructions.

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
