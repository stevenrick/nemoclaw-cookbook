#!/usr/bin/env bash
# Stream a curated progress feed from a setup.sh / upgrade output log.
#
# Designed to be the body of a Claude Code Monitor command:
#
#     Monitor: bash <cookbook>/scripts/watch-setup.sh <task-output-file>
#
# Emits every line we'd want a notification for — phase markers, Dockerfile
# steps, ✓ checkpoints, warnings, errors, and the final "NemoClaw is ready" /
# Web UI line. Liberal on purpose: a noisy stream beats silence for long
# phases (apt+npm in the sandbox image build can sit for minutes between
# upstream-printed lines).
#
# Single source of truth for "what counts as progress" — update the pattern
# here, not in skill files.
#
# Usage:
#   watch-setup.sh <log-file>
#
# Exit:
#   Returns when tail exits (file deleted/rotated/EOF on closed source).
set -uo pipefail

LOG="${1:?Usage: watch-setup.sh <log-file>}"

if [ ! -e "$LOG" ]; then
  # Wait briefly for the file to appear — caller may have just launched the
  # background task. Bail out after 30s so a typo doesn't hang Monitor.
  for _ in $(seq 1 30); do
    [ -e "$LOG" ] && break
    sleep 1
  done
fi

# Line-buffered grep is mandatory — otherwise pipe buffering swallows events
# for minutes during long phases.
exec tail -n +1 -F "$LOG" 2>/dev/null | grep -E --line-buffered "\
^=== Step \
|Step [0-9]+/[0-9]+ \
|✓ \
|✗ \
|\[WARN\]|Warning:|warning:\
|\[ERROR\]|ERROR|Error:|FAILED|fatal|failed to|error:\
|Built image|Uploaded to gateway\
|Image .* is available in the gateway\
|Creating sandbox \
|Still (building|installing|starting)\
|Gateway is healthy\
|Active gateway set to\
|Inference route set:\
|Created provider \
|Applied preset:\
|Sandbox '.*' is Ready\
|Sandbox .env written\
|Sandbox restarted\
|Bouncing sandbox\
|Onboarding complete\
|NemoClaw is (ready|running)\
|Web UI:\
"
