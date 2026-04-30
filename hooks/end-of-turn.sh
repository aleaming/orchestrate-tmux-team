#!/usr/bin/env bash
# Stop hook — runs at the end of each Claude turn.
#
# Wire-up: "Stop" event in settings.json.
#
# Use this for cheap quality gates (typecheck, lint, smoke tests).
# Exit code is always 0 here so Claude can finish the turn cleanly;
# switch to non-zero only if you want failures to block turn completion.

set -u

PROJECT_ROOT="$(pwd)"

# Warn if .env was accidentally tracked.
if command -v git >/dev/null 2>&1 && [[ -d "$PROJECT_ROOT/.git" ]]; then
  if git -C "$PROJECT_ROOT" ls-files --error-unmatch .env >/dev/null 2>&1; then
    echo "WARNING: .env is tracked by git! Run: git rm --cached .env" >&2
  fi
fi

# Add project-specific checks below as the codebase grows, e.g.:
# - npx tsc --noEmit
# - ruff check src
# - shellcheck scripts/*.sh

exit 0
