#!/usr/bin/env bash
# Notification hook — surfaces a desktop notification on macOS.
#
# Wire-up: "Notification" event in settings.json.
# On non-macOS, falls back to a no-op.

set -u

PAYLOAD="$(cat)"

MESSAGE=""
if command -v jq >/dev/null 2>&1; then
  MESSAGE="$(printf '%s' "$PAYLOAD" | jq -r '.message // .notification // empty' 2>/dev/null || true)"
fi
[[ -z "$MESSAGE" ]] && MESSAGE="Claude Code needs attention"

if [[ "$(uname -s)" == "Darwin" ]] && command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"${MESSAGE//\"/\\\"}\" with title \"Claude Code\"" >/dev/null 2>&1 || true
fi

exit 0
