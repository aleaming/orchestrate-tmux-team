#!/usr/bin/env bash
# PreToolUse hook — blocks dangerous Bash commands.
#
# Wire-up (in .claude/settings.json):
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "bash ./hooks/block-dangerous-commands.sh" }]
#     }]
#
# Exit codes:
#     0  allow
#     1  internal error (fail open)
#     2  block; stderr is fed back to Claude

set -uo pipefail

PAYLOAD="$(cat)"

extract_command() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null
  else
    printf '%s' "$PAYLOAD" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
  fi
}

CMD="$(extract_command || true)"

if [[ -z "$CMD" ]]; then
  exit 0
fi

block() {
  printf 'BLOCKED: %s\nReason: %s\n' "$CMD" "$1" >&2
  exit 2
}

# rm -rf on root, home, or absolute paths / wildcard
if echo "$CMD" | grep -Eq 'rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*[[:space:]]+|-r[fF]?[[:space:]]+|-[fF]r[[:space:]]+)([/]|~|\$HOME|\*)'; then
  block "rm -rf against /, ~, or wildcard is destructive"
fi

# git push --force / -f to main, master, production
if echo "$CMD" | grep -Eq 'git[[:space:]]+push[[:space:]]+.*(--force(-with-lease)?|[[:space:]]-f([[:space:]]|$))'; then
  if echo "$CMD" | grep -Eq '(main|master|production)'; then
    block "force-push to main/master/production requires explicit user approval"
  fi
fi

# git reset --hard
if echo "$CMD" | grep -Eq 'git[[:space:]]+reset[[:space:]]+--hard'; then
  block "git reset --hard discards uncommitted work; confirm with user first"
fi

# git commit --no-verify (forbidden by global CLAUDE.md)
if echo "$CMD" | grep -Eq 'git[[:space:]]+commit[[:space:]]+.*(--no-verify|--no-gpg-sign)'; then
  block "skipping git hooks/signing is forbidden by global CLAUDE.md"
fi

# Fork bomb
if echo "$CMD" | grep -Eq ':\(\)\{[[:space:]]*:\|:&[[:space:]]*\}'; then
  block "fork bomb pattern"
fi

# dd to a real device
if echo "$CMD" | grep -Eq 'dd[[:space:]]+.*of=/dev/(sd|nvme|disk)'; then
  block "dd to a block device will destroy data"
fi

exit 0
