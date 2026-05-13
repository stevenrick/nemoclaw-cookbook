#!/usr/bin/env python3
"""Build the NEMOCLAW_INTEGRATIONS_B64 payload from .env-driven integration flags.

Used by apply-patches.sh to bake cookbook-only config into the upstream Dockerfile's
ARG NEMOCLAW_INTEGRATIONS_B64 default. The dockerfile-integrations fragment then
deep-merges this base64-encoded JSON into /sandbox/.openclaw/openclaw.json at build
time, before the integrity hash is pinned.

Reads (from process environment):
  TAVILY_API_KEY                enables the Tavily web-search plugin
  NEMOCLAW_OPENAI_HTTP_ENABLED  enables /v1/chat/completions, /v1/responses, etc.

Output: base64-encoded JSON dict on stdout (empty dict {} when no flags set).

When upstream NemoClaw exposes native env flags for these integrations, this
helper retires alongside the dockerfile-integrations fragment.
"""
import base64
import json
import os


def build_config() -> dict:
    config: dict = {}

    # Web search (Tavily) — Brave is handled by upstream nemoclaw onboard via
    # NEMOCLAW_WEB_SEARCH_ENABLED. Tavily isn't onboarded upstream, so we bake
    # the minimal config: plugin enabled + provider pointer. The API key is
    # NOT baked here (a placeholder doesn't help on OpenShell <v0.0.39); the
    # plugin falls back to process.env.TAVILY_API_KEY, sourced into the gateway
    # via apply-patches.sh's entrypoint patch.
    if os.environ.get("TAVILY_API_KEY", ""):
        config["plugins"] = {"entries": {"tavily": {"enabled": True}}}
        config["tools"] = {"web": {"search": {
            "enabled": True,
            "provider": "tavily",
        }}}

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
