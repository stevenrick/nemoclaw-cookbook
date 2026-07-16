#!/usr/bin/env python3
"""Build the NEMOCLAW_INTEGRATIONS_B64 payload from cookbook integration flags.

Used by apply-patches.sh to bake cookbook-only config into the upstream Dockerfile's
ARG NEMOCLAW_INTEGRATIONS_B64 default. The dockerfile-integrations fragment then
deep-merges this base64-encoded JSON into /sandbox/.openclaw/openclaw.json at build
time, before the integrity hash is pinned.

Reads (from process environment):
  NEMOCLAW_OPENAI_HTTP_ENABLED  enables /v1/chat/completions, /v1/responses, etc.

Output: base64-encoded JSON dict on stdout (empty dict {} when no flags set).

When upstream NemoClaw exposes a native env flag for OpenAI-compatible HTTP
gateway endpoints, this helper retires alongside the dockerfile-integrations
fragment.
"""
import base64
import json
import os


def build_config() -> dict:
    config: dict = {}

    # OpenAI-compatible HTTP API — flips both chatCompletions.enabled AND
    # responses.enabled because OpenClaw derives openAiCompatEnabled from
    # EITHER, gating /v1/models + /v1/embeddings (server-http.ts ~L498).
    # Enabling both maximizes SDK compatibility.
    if os.environ.get("NEMOCLAW_OPENAI_HTTP_ENABLED", "").lower() in ("1", "true", "yes"):
        gw_http = (
            config.setdefault("gateway", {})
            .setdefault("http", {})
            .setdefault("endpoints", {})
        )
        gw_http["chatCompletions"] = {"enabled": True}
        gw_http["responses"] = {"enabled": True}

    return config


def main() -> None:
    print(base64.b64encode(json.dumps(build_config()).encode()).decode())


if __name__ == "__main__":
    main()
