# Contributing to NemoClaw Cookbook

Thanks for your interest in contributing! This project provides setup automation and patches for running NemoClaw with Claude Code, Codex, and messaging integrations.

## How to Contribute

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Submit a pull request

## What We're Looking For

- Bug fixes in setup scripts or patches
- Support for additional tools or agents
- Documentation improvements
- New integration examples

## Guidelines

- Keep patch fragments minimal and focused — they live in `patches/fragments/` and are applied by `scripts/apply-patches.sh`
- **Always test the round-trip** before committing patch changes: reset target files, apply your patch, verify it works
- If upstream NemoClaw broke existing patches, use `claude /refresh-patches` or see [BUILD.md § Refreshing Patches](BUILD.md#refreshing-patches-after-upstream-updates)
- Test your changes on a clean Ubuntu 22.04 environment when possible
- Use [Conventional Commits](https://www.conventionalcommits.org/) format (e.g., `feat:`, `fix:`, `docs:`)
- Do not commit credentials, API keys, or tokens — use `.env.example` for templates

## Security

Do not report security vulnerabilities through GitHub issues. See [SECURITY.md](SECURITY.md) for instructions.

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
