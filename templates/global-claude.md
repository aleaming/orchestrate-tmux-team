# ~/.claude/CLAUDE.md (global)

> Template for the user's **global** Claude Code instructions. Copy to `~/.claude/CLAUDE.md` and customize.
> Replace placeholders in `[brackets]` with your own values.

## Identity

- **Name:** [Your Name]
- **Email (GitHub):** [you@example.com]
- **GitHub remote convention:** `git@github.com:[YourUsername]/<repo>.git`

## Hard rules (NEVER violate)

- **NEVER** commit secrets, API keys, tokens, `.env`, or credentials.
- **NEVER** use `--no-verify` on git commits.
- **NEVER** run destructive commands (`rm -rf`, `git push --force`, `git reset --hard` against shared branches) without explicit user confirmation.

## New project setup contract

Every new project gets:

- `.env`, `.env.example`, `.gitignore` (with `.env`, `node_modules/`, `dist/`)
- `CLAUDE.md` at project root
- Standard folders: `src/`, `tests/`, `docs/`, `.claude/`, `templates/`, `hooks/`, `skills/`, `agents/`, `commands/`, `scripts/`, `memory/`

## Skills vs CLAUDE.md

If a rule applies to <20% of conversations, package it as a skill (`skills/<name>/SKILL.md`) instead of bloating this file.
