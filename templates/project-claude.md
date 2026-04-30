# [Project Name]

[One-paragraph description of what this project does and who it's for.]

## Session Memory

At the **start of every session**, read all files in `memory/`:
- `memory/decisions.md` — Architectural and design decisions with rationale
- `memory/people.md` — Team members, roles, and context
- `memory/preferences.md` — How the user prefers to work
- `memory/user.md` — Background on the primary user

At the **end of every session**, update the relevant memory file(s) when significant new context emerges.

## Tech stack

- Language: [e.g., TypeScript]
- Runtime: [e.g., Node.js 20]
- Database: [e.g., PostgreSQL]
- Tests: [e.g., Vitest]

## Build / test / run

```bash
# install
[npm install]

# run dev
[npm run dev]

# tests
[npm test]
```

## Conventions

- Secrets in `.env` (never committed).
- Hooks in `hooks/` enforce security deterministically.
- Skills in `skills/<name>/SKILL.md` package reusable expertise.

## Status

[Current state of the project — alpha, beta, production, etc.]
