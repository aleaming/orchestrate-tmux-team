---
name: orchestrating-parallel-agents
description: >
  Spawn N parallel Claude Code worker agents in colored tmux panes, each in its
  own git worktree, with a coordinator pane for merge management. Use when a
  task splits cleanly into 2-4 disjoint workers (separate files, parallel-
  friendly scopes) and you want them visible in side-by-side terminal windows.
  Generates the launcher script + prompt templates per project. Triggers on:
  "spawn a team", "/spawn-team", "parallel agents", "tmux orchestration",
  "agent team", "worker team", "orchestrate workers".
version: 1.0.0
---

# Orchestrating parallel agents

You spawn a tmux team of parallel Claude Code workers in isolated git worktrees, generate per-worker task briefs, and walk the operator through launch → monitor → merge → cleanup → PR. The output is two things: a parameterized `scripts/launch-team.sh` and a set of `.claude/team-prompts/*.md` files. Once those exist, the operator runs the script.

## Purpose

This skill exists because some features split cleanly into independent file scopes (e.g. schema, API, UI), and running those workers in parallel is faster and more observable than serializing them. By giving each worker its own git worktree (filesystem isolation), its own sibling branch (history isolation), and its own tmux pane (visual isolation), the operator can watch all three at once and the workers can't trip over each other.

## When to use

- Task has ≥2 disjoint workers operating on different files.
- Each worker's scope can be enumerated in 3 lines.
- No shared mutable state across workers (each owns its own files).
- The task takes ≥30 minutes per worker (orchestration overhead exceeds savings on shorter tasks).

## When NOT to use

- Single-file changes.
- Sequential dependencies that can't be broken (e.g. each step needs the previous step's commit).
- Refactors that touch many files (workers' scopes will overlap).
- Tasks under 30 minutes total (manual sequential is faster).
- 5+ workers (tmux tiled layout breaks down; consider splitting into two passes).

## Architecture (one-paragraph)

Parent feature branch fans out into N sibling branches, each in its own worktree under `.claude/worktrees/`. Each worktree runs a claude session in a colored tmux pane. The coordinator pane (pane 0, in the main repo) watches `STATUS.md` files for `READY` signals, then merges in dependency order. State machine: `PENDING → IN_PROGRESS → READY/FAILED/BLOCKED`. See `references/architecture.md`.

## Activation flow

When invoked via `/spawn-team <feature-name>`:

### Step A — Pre-flight

1. Confirm we're in a git repo: `git rev-parse --show-toplevel`.
2. Confirm we're on a feature branch (not `main`/`master`). If on main, ask the user whether to create a feature branch.
3. Confirm working tree is clean. If dirty, warn (workers start from HEAD; uncommitted work won't propagate).

### Step B — Detect project type

Look for these files in repo root, in order:
- `package.json` → Node → `{{VERIFY_COMMANDS}}` = `npm run lint && npx tsc --noEmit && npm run test:run`
- `pyproject.toml` or `requirements.txt` → Python → `ruff check && pytest`
- `Cargo.toml` → Rust → `cargo check && cargo test`
- `go.mod` → Go → `go vet ./... && go test ./...`
- None → Bare repo → `# No language-specific verify auto-detected; add commands here.`

### Step C — Elicit worker breakdown via AskUserQuestion

Per worker, gather: name (slug), scope files (which paths), task summary (2-3 sentences), hard constraints (numbered list), commit message (the literal `git commit -m "..."`), dependency order (integer; lower merges first).

Optional: pre-staging spec (if any worker imports another's not-yet-committed output). See `references/lessons-from-the-trenches.md` § L8.

### Step D — Render `scripts/launch-team.sh`

Read `templates/launch-team.template.sh` and substitute placeholders:
- `{{SESSION}}` = `<feature-name>-team`
- `{{WORKTREE_PREFIX}}` = `<feature-name>`
- `{{BRANCH_PREFIX}}` = `<parent-branch>-`
- `{{COORD_COLOR}}` = `226`
- `{{WORKERS}}` = newline-joined `"<name>|<branch-suffix>|<color>"` lines
- `{{STAGED_FILES}}` = pre-staging lines or empty

Write to `<repo>/scripts/launch-team.sh`. `chmod +x`.

### Step E — Render coordinator prompt

Read `templates/coordinator.template.md` and substitute. See `workflows/full-orchestration.md` Step 3 for the full placeholder mapping.

Write to `<repo>/.claude/team-prompts/coordinator.md`.

### Step F — Render worker prompts

For each worker, read `templates/worker.template.md` and substitute per-worker fields. The `{{PRE_STAGED_BLOCK}}` is non-empty only if this worker received a pre-staged file.

Write to `<repo>/.claude/team-prompts/<name>.md`.

### Step G — Smoke test

```bash
bash -n scripts/launch-team.sh                                             # syntax check
grep -rE '\{\{[A-Z_]+\}\}' scripts/launch-team.sh .claude/team-prompts/   # must produce no output
```

If anything fails, abort and surface the error. Do NOT hand off artifacts with unsubstituted placeholders.

### Step H — Auto-launch policy (L7)

Ask the user via AskUserQuestion: manual / auto-without-flag / auto-with-`--dangerously-skip-permissions`. Default: manual. If auto-* selected, follow `references/auto-launch-via-tmux-paste.md`.

### Step I — Hand off

Print the four lifecycle commands:

```
▶ Launch:      bash scripts/launch-team.sh
▶ Attach:      tmux attach -t <session>
▶ Poll status: bash scripts/launch-team.sh --status
▶ Tear down:   bash scripts/launch-team.sh --cleanup
```

The skill's job is done at this point. The operator runs the script and watches.

## Lifecycle commands quick-reference

| Command | What it does |
|---|---|
| `bash scripts/launch-team.sh` | Create worktrees, spawn tmux session with N+1 panes, render prompts |
| `tmux attach -t <session>` | Attach to watch the panes |
| `bash scripts/launch-team.sh --status` | Print each worker's STATUS.md state |
| `bash scripts/launch-team.sh --cleanup` | Kill session, remove worktrees + branches (with dirty-worktree confirm) |

## Pre-staging pattern (L8 — quick reference)

When worker B's task imports from worker A's not-yet-committed file, copy A's planned output into B's worktree before launch. A commits the file (per their TASK.md scope); B uses it locally for compilation but does NOT `git add` it. The merge brings it into the parent via A's branch. See `references/architecture.md` for full discussion.

The launcher's `STAGED_FILES` array encodes pre-staging: `"src-abs|workerA,workerB|dest-rel"`. The skill asks at Step C whether pre-staging is needed; default is none.

## References

- `references/lessons-from-the-trenches.md` — the 9 codified defenses (L1–L9) and *why* each line of the launcher exists.
- `references/architecture.md` — branch / worktree / tmux topology, STATUS state machine, failure handling, bare-repo fallback.
- `references/auto-launch-via-tmux-paste.md` — the load-buffer / paste-buffer / bracketed-paste mechanism for autonomous worker injection (L6).
- `workflows/full-orchestration.md` — end-to-end walkthrough including the failure-recovery playbook.
