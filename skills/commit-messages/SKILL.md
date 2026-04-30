---
name: commit-messages
description: Use when staging or committing changes. Generates a conventional-commit-style message (type(scope): subject) from the current diff, with a body that explains *why* not *what*. Activates on user phrases like "commit", "write a commit message", "git commit".
---

# Commit Messages

Generate clear, conventional commit messages from the staged diff.

## Format

```
<type>(<scope>): <subject>

<body — explain WHY, not WHAT>

<footer — issue refs, breaking-change notes>
```

**Types:** `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `build`, `ci`, `style`.

**Subject rules:**
- Imperative mood ("add", not "added" or "adds").
- Lowercase, no trailing period.
- ≤72 characters.
- Subject answers: "If applied, this commit will _____".

## Process

1. Run `git diff --cached`. If nothing is staged, ask the user before staging.
2. Detect the dominant *type* from the diff:
   - New files implementing capability → `feat`
   - Bug fix referenced in code or test → `fix`
   - No behavior change → `refactor` / `chore` / `style`
   - Tests only → `test`
   - Docs only → `docs`
3. Pick a *scope* from the most-edited directory or module name (e.g. `auth`, `tmux`, `hooks`).
4. Write the subject in imperative mood.
5. Write a 1–3 sentence body explaining motivation, not a restatement of the diff.
6. If a `BREAKING CHANGE:` exists, footer it explicitly.

## Anti-patterns

- "Update files" / "Misc changes" / "WIP" — too vague.
- Restating the diff line by line — the diff already shows that.
- Mentioning the AI tooling that wrote it.
- Skipping the *why* — future readers come here to learn motivation, not mechanics.

## Example

Diff: added `block-dangerous-commands.sh` and wired it into `templates/settings.json`.

```
feat(hooks): block force-push to main and rm -rf in PreToolUse

CLAUDE.md prose can be overridden under context pressure; a hook
returning exit 2 cannot. This closes the loophole that prompted the
March incident where --force pushed to main during a long session.
```
