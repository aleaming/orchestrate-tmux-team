# orchestrate-tmux-team

Tooling for orchestrating teams of agents/processes inside tmux. Project skeleton scaffolded 2026-04-29; implementation is still pending.

## Session Memory

At the **start of every session**, read all files in `memory/`:
- `memory/decisions.md` — Architectural and design decisions with rationale
- `memory/people.md` — Team members, roles, and context
- `memory/preferences.md` — How the user prefers to work (code style, communication, workflow)
- `memory/user.md` — Background on the primary user to tailor collaboration

At the **end of every session** (or when significant new context emerges), update the relevant memory file(s):
- New architectural or design decisions → `decisions.md`
- New people or role changes → `people.md`
- New workflow preferences or corrections → `preferences.md`
- New context about the user's goals or background → `user.md`

Keep entries concise. Include dates for decisions. Remove outdated entries rather than letting them accumulate.

## Project Structure

```
orchestrate-tmux-team/
├── src/           # Application source code
├── tests/         # Test suites
├── docs/          # Project documentation
├── .claude/       # Project-scoped Claude Code config (settings.json, etc.)
├── templates/     # Copy-and-use templates (CLAUDE.md, settings.json, .gitignore)
├── hooks/         # Deterministic enforcement scripts (block secrets, dangerous commands)
├── skills/        # Packaged AI expertise (commit-messages, security-audit, ...)
├── agents/        # Custom sub-agents
├── commands/      # Custom slash commands
├── scripts/       # Project automation scripts
├── memory/        # Persistent session memory (read at start, written at end)
└── GUIDE.md       # Long-form educational content
```

## Conventions

- **Secrets:** never commit `.env` or credentials. `.env` must be in `.gitignore`.
- **Hooks > prose:** any rule that MUST hold belongs in `hooks/`, not CLAUDE.md.
- **Skills threshold:** guidance applying to <20% of conversations belongs in a skill, not here.
- **Node.js:** entry points register an `unhandledRejection` handler that logs and exits 1.
- **GitHub:** SSH remotes under the `aleaming` account: `git@github.com:aleaming/<repo>.git`.

## Status

Scaffolding only — `src/`, `tests/`, and `docs/` are empty. Add a "Build" / "Test" / "Run" section here once implementation begins.
