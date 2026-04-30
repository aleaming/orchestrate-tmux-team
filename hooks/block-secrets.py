#!/usr/bin/env python3
"""
PreToolUse hook — blocks Read/Edit/Write on sensitive files.

Wire-up (in .claude/settings.json):
    "PreToolUse": [{
      "matcher": "Read|Edit|Write",
      "hooks": [{ "type": "command", "command": "python3 ./hooks/block-secrets.py" }]
    }]

Exit codes:
    0  allow operation
    1  internal error (logged, does NOT block — fail open)
    2  block operation; stderr is fed back to Claude
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SECRET_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"(^|/)\.env(\.[a-zA-Z0-9_-]+)?$"),
    re.compile(r"(^|/)credentials\.json$"),
    re.compile(r"(^|/)secrets\.json$"),
    re.compile(r"\.(pem|key|p12|pfx)$"),
    re.compile(r"(^|/)id_rsa(\.pub)?$"),
    re.compile(r"(^|/)id_ed25519(\.pub)?$"),
    re.compile(r"(^|/)\.aws/credentials$"),
    re.compile(r"(^|/)\.ssh/(?!known_hosts$|config$).+"),
]

ALLOW_EXAMPLE_FILES = re.compile(r"\.example$|\.sample$|\.template$")


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path") or tool_input.get("path") or ""

    if not file_path:
        return 0

    if ALLOW_EXAMPLE_FILES.search(file_path):
        return 0

    for pattern in SECRET_PATTERNS:
        if pattern.search(file_path):
            print(
                f"BLOCKED: {Path(file_path).name} is a sensitive file. "
                f"If you genuinely need to inspect it, ask the user to share "
                f"the relevant snippet manually.",
                file=sys.stderr,
            )
            return 2

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"block-secrets hook internal error: {exc}", file=sys.stderr)
        sys.exit(0)
