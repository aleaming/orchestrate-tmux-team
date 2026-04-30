#!/usr/bin/env bash
# PostToolUse hook — runs lightweight formatters after Edit/Write.
#
# Wire-up: "PostToolUse" / matcher "Edit|Write".
#
# Exit code is always 0 (advisory). Failures here should NOT block Claude.

set -u

PAYLOAD="$(cat)"
FILE=""
if command -v jq >/dev/null 2>&1; then
  FILE="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
fi

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  exit 0
fi

case "$FILE" in
  *.py)
    if command -v ruff >/dev/null 2>&1; then ruff format "$FILE" >/dev/null 2>&1 || true; fi
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.md)
    if command -v prettier >/dev/null 2>&1; then prettier --write "$FILE" >/dev/null 2>&1 || true; fi
    ;;
  *.sh|*.bash)
    if command -v shfmt >/dev/null 2>&1; then shfmt -w "$FILE" >/dev/null 2>&1 || true; fi
    ;;
esac

exit 0
