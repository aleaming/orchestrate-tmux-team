# orchestrate-tmux-team

A Claude Code plugin that spawns parallel `claude` worker agents in colored tmux panes — each in its own git worktree — with a coordinator pane that handles merging, verification, and PR creation.

Adds the `/spawn-team` slash command. Useful for features that split cleanly into 2–4 disjoint workers with independent file scopes.

## Quick start

```bash
# In any project where you want a parallel team:
/spawn-team checkout-flow
```

The skill walks you through:
1. Confirming git state (must be on a feature branch).
2. Eliciting the worker breakdown (names, scopes, dependency order).
3. **Scanning `~/.claude/agents/` and matching each worker to a best-fit specialist agent** (v1.1).
4. Rendering `scripts/launch-team.sh` and `.claude/team-prompts/*.md` (with the matched agent embedded in each worker's `TASK.md`).
5. Optional auto-launch (with explicit per-launch consent for `--dangerously-skip-permissions`).
6. Walking through merge → verification → push → PR.

## Agent matching (v1.1)

When you spawn a team, the skill scans your installed agents at `~/.claude/agents/` and uses an LLM-driven matcher to pick the best-fit specialist for each worker's scope:

- A worker scoped to `src/api/*.py` with FastAPI/Pydantic context → matched to `python-pro`
- A worker scoped to `src/components/*.tsx` → matched to `frontend-developer` or `typescript-pro`
- A worker scoped to `deploy/k8s/*.yaml` → matched to `GENERIC` (no specialist applies)

The matched agent appears:
- In the worker's pane header: `▼ WORKER: api [python-pro]`
- As a recommended specialist block at the top of the worker's `TASK.md`, instructing the worker's claude session to delegate via the `Agent` tool.

Low-confidence matches surface to the operator via a follow-up prompt, listing the top candidates plus `GENERIC`. See `skills/orchestrating-parallel-agents/references/agent-matching.md` for the matching prompt design and defenses (injection guard, hallucination guard, empty-registry handling).

## What you get

```
your-project/
├── scripts/
│   └── launch-team.sh           ← rendered launcher (idempotent, --status, --cleanup)
└── .claude/
    ├── team-prompts/
    │   ├── coordinator.md       ← rendered coordinator brief
    │   └── <worker>.md          ← rendered per-worker brief (one per worker)
    └── worktrees/               ← created at launch time (gitignored)
        ├── <feature>-<worker1>/ ← isolated worktree on a sibling branch
        └── <feature>-<worker2>/
```

Each worker pane runs claude in its own colored tmux pane. The coordinator pane (yellow) sits in the main repo and watches `STATUS.md` files for `READY`.

## Install

### Option 1 — Claude Code marketplace (recommended)

This repo ships its own `marketplace.json`, so it can be added as a marketplace and installed through Claude's plugin UI:

```
/plugin marketplace add aleaming/orchestrate-tmux-team
/plugin install orchestrate-tmux-team
```

Restart Claude Code; `/spawn-team` should appear in the slash-command list.

### Option 2 — Direct clone

```bash
gh repo clone aleaming/orchestrate-tmux-team ~/.claude/plugins/orchestrate-tmux-team
```

### Option 3 — Symlink (for plugin development)

If you've cloned this repo elsewhere and want to develop on it locally:

```bash
ln -s /path/to/orchestrate-tmux-team ~/.claude/plugins/orchestrate-tmux-team
```

## Requirements

- **tmux ≥ 3.0** (for `pane_current_path` queries; older versions may work but are untested)
- **git ≥ 2.30** (for stable worktree behavior)
- **bash or zsh** as the pane shell (alias-bypass for `cat=bat` only works there; fish/csh users must launch panes manually)
- **gh CLI** (optional; only needed if you want the coordinator template's PR step to create the PR for you)

## Lifecycle

After `/spawn-team` generates the artifacts, you have four commands:

| Command | Purpose |
|---|---|
| `bash scripts/launch-team.sh` | Create worktrees, spawn tmux session with `N+1` panes |
| `tmux attach -t <session>` | Attach to watch the panes |
| `bash scripts/launch-team.sh --status` | Print each worker's `STATUS.md` state |
| `bash scripts/launch-team.sh --cleanup` | Tear down session, remove worktrees + branches (with dirty-worktree confirm) |

## STATUS.md state machine

Workers communicate completion via `STATUS.md`, one file per worktree:

| State | Meaning |
|---|---|
| `PENDING` | Seeded by launcher; worker hasn't started |
| `IN_PROGRESS <task>` | Worker is actively working |
| `READY <summary>` | Worker complete; ready to merge |
| `FAILED <reason>` | Worker hit unrecoverable error; needs human |
| `BLOCKED <reason>` | Worker waiting on external input |

The coordinator polls these and merges when all are `READY`. See `skills/orchestrating-parallel-agents/references/architecture.md` for the full state machine.

## Defenses encoded in the launcher (L1–L9)

The launcher script handles nine production-tested gotchas:

| # | Gotcha | Defense |
|---|---|---|
| L1 | Rogue tmux plugin panes | Two-pass cleanup with stability poll |
| L2 | `cat=bat` shell alias | `command cat` + `unalias cat` prefix |
| L3 | zsh `:t` modifier eating session names | Always brace as `${SESSION}:team` |
| L4 | Pane index instability after `kill-pane` | Identify panes by `pane_current_path` |
| L5 | `send-keys` timing race | Split into two send-keys calls |
| L6 | Multi-line task fragmentation on auto-launch | `tmux load-buffer` + `paste-buffer -p` |
| L7 | `--dangerously-skip-permissions` consent | Per-launch user authorization required |
| L8 | Cross-worker compile dependencies | Pre-staging via `STAGED_FILES` array |
| L9 | Single-state `READY` protocol | Five-state STATUS.md vocabulary |

Each is documented in detail in `skills/orchestrating-parallel-agents/references/lessons-from-the-trenches.md`.

## Project type detection

The skill auto-detects project type for the coordinator's verification step:

| Signal | Verify commands rendered |
|---|---|
| `package.json` | `npm run lint && npx tsc --noEmit && npm run test:run` |
| `pyproject.toml` or `requirements.txt` | `ruff check && pytest` |
| `Cargo.toml` | `cargo check && cargo test` |
| `go.mod` | `go vet ./... && go test ./...` |
| (none) | Bare-repo placeholder; user adds their own |

The bare-repo case lets the plugin run on language-agnostic repos including this one.

## When NOT to use

- Single-file changes (orchestration overhead exceeds savings)
- Sequential dependencies that can't be broken
- Refactors touching many overlapping files
- Tasks under ~30 minutes total
- 5+ workers (tmux tiled layout breaks down past 4)

## License

MIT

## Author

Alex Leaming · `aleaming@me.com`
