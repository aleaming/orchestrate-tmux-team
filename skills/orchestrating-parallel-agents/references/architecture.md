# Architecture

How the orchestrate-tmux-team plugin's pieces fit together. Read this before modifying the launcher template or the STATUS protocol — most of the design choices here have specific reasons that are easy to miss.

## Branch topology

```
   parent feature branch (e.g. feature/checkout-flow)
   ├── feature/checkout-flow-schema      ← worker 1
   ├── feature/checkout-flow-api         ← worker 2
   └── feature/checkout-flow-ui          ← worker 3
```

Workers operate on **sibling branches** off the parent. Each is created by `git worktree add -b <branch> <worktree-path> HEAD` at launch time, so they all start from the same commit.

After workers complete, the coordinator merges sibling branches back into the parent in dependency order using `git merge --no-ff`. Each merge produces a single commit on the parent, preserving the per-worker history.

## Worktree layout

```
<repo>/.claude/worktrees/
├── checkout-flow-schema/    ← isolated checkout of feature/checkout-flow-schema
├── checkout-flow-api/       ← isolated checkout of feature/checkout-flow-api
└── checkout-flow-ui/        ← isolated checkout of feature/checkout-flow-ui
```

Worktrees give us **filesystem isolation** while sharing the underlying `.git` object database. Each worktree is a fully usable working tree — you can `cd` into it, edit files, run tests, and commit, all without affecting the main repo or other worktrees.

The `.claude/worktrees/` dir is in `.gitignore` (added by the plugin's bootstrap) so it's never accidentally committed.

## Tmux pane layout

```
┌────────────────────────────────────────────────────────┐
│  🎯 COORDINATOR  (pane 0, repo root, yellow)           │
├────────────────────────┬───────────────────────────────┤
│  ▼ WORKER: schema      │  ▼ WORKER: api                │
│  (worktree, orange)    │  (worktree, cyan)             │
├────────────────────────┴───────────────────────────────┤
│  ▼ WORKER: ui                                          │
│  (worktree, magenta)                                   │
└────────────────────────────────────────────────────────┘
```

`tiled` layout. Each pane runs in its respective `cwd` — the launcher uses `pane_current_path` to identify roles (L4), so coloring and status checks are stable even after `kill-pane` reindexes panes.

For N > 4 workers, the layout becomes cramped on typical terminals. Use a separate terminal session or a wider monitor; switching to `tmux new-window` per worker is a v1.1 enhancement.

## STATUS state machine

Workers communicate completion to the coordinator via `STATUS.md`, one file per worktree. The protocol is a five-state machine:

```
   ┌─────────┐
   │ PENDING │  (script seeds this on worktree creation)
   └────┬────┘
        │ worker starts
        ▼
  ┌─────────────┐         ┌─────────┐
  │ IN_PROGRESS │────────►│ BLOCKED │  ← waiting on external input
  └──────┬──────┘         └─────────┘
         │
   success│  failure
         ▼          ▼
     ┌───────┐  ┌────────┐
     │ READY │  │ FAILED │
     └───────┘  └────────┘
```

| State | Worker side | Coordinator response |
|---|---|---|
| `PENDING` | Seeded by launcher; worker hasn't started | Wait |
| `IN_PROGRESS <task>` | First action: `echo "IN_PROGRESS …" > STATUS.md` | Wait |
| `READY <summary>` | Last action after commit | Proceed once all workers are READY |
| `FAILED <reason>` | Worker hit unrecoverable error | Attach pane, decide |
| `BLOCKED <reason>` | Worker waiting on external input | Unblock, then nudge |

Line 1 is the headline; lines 2+ are optional context. `cmd_status` reads line 1 only and shows a count of additional lines (so failed/blocked workers don't lose their narrative).

## Coordinator merge ordering

The skill elicits dependency order at `/spawn-team` setup. Producer-first: if worker A creates a file that worker B imports, A merges first. Most teams have an obvious order (schema → api → ui).

Before each real merge, the coordinator runs a dry-run loop (Phase 2a in the coordinator template):

```bash
git merge --no-commit --no-ff <branch> && git merge --abort
```

This catches conflicts before any merge commit lands. If a branch fails dry-run, surface the conflict to the worker (write `BLOCKED` to their STATUS.md) rather than letting the coordinator paper over it.

## Pre-staging (cross-worker compile dependencies)

When worker B's task imports from worker A's not-yet-committed output, the launcher pre-stages A's planned output into B's worktree before launch. Only A commits it; B uses it locally for compilation.

The launcher's `STAGED_FILES` array encodes this:

```bash
STAGED_FILES=(
  "/abs/path/to/staged-file.tsx|workerA,workerB|src/components/staged-file.tsx"
)
```

After both workers commit, A's branch carries the canonical file; the merge brings it into the parent. B's worktree never `git add`s it, so the merge from B's branch doesn't conflict.

## Failure handling (trap-based rollback)

`cmd_launch` registers `trap on_launch_fail ERR` immediately after preflight. If any subsequent step fails (worktree creation, prompt copy, tmux setup), the trap:

1. Removes every worktree the script created during this launch.
2. Deletes every branch the script created.
3. Kills the (possibly partial) tmux session.
4. Prints a rollback message and exits non-zero.

Worktrees that existed *before* this launch are left untouched. The user is never left with orphaned state from an aborted launch.

`trap - ERR` clears the handler at the end of `cmd_launch`'s success path so subsequent commands don't trigger rollback.

## Self-hosting on bare repos (no `package.json` fallback)

The orchestrate-tmux-team repo itself has no `package.json`. The skill detects project type and resolves `{{VERIFY_COMMANDS}}` accordingly:

| Detection signal | Rendered VERIFY_COMMANDS |
|---|---|
| `package.json` present | `npm run lint && npx tsc --noEmit && npm run test:run` |
| `pyproject.toml` or `requirements.txt` present | `ruff check && pytest` |
| `Cargo.toml` present | `cargo check && cargo test` |
| `go.mod` present | `go vet ./... && go test ./...` |
| Otherwise | A placeholder: `# No language-specific verify auto-detected; add commands here.` |

If the user wants different verify commands than the auto-detect chooses, they can edit `.claude/team-prompts/coordinator.md` after generation. The plugin doesn't hold them to the auto-detected choice.

## Agent matching layer (v1.1)

After worker elicitation but before artifact rendering, the skill scans `~/.claude/agents/` and matches each worker to a best-fit specialist. The flow:

```
elicit workers (Step C) → discover agents → match per worker → escalate low-confidence → render (Step D+)
                          (glob frontmatter)  (1 LLM call/each)  (AskUserQuestion)
```

Each worker carries a `matched_agent` field (specialist name or `GENERIC`) and a `match_confidence` (`high|medium|low`) by the time rendering begins. Two artifacts use these:

- **Worker `TASK.md`** — gets a `## Recommended specialist:` header block (omitted for GENERIC).
- **Pane header** — appends `[<agent>]` to the worker name line (omitted for GENERIC).

The matching layer's full procedure, prompt design (with prompt-injection and hallucination defenses), JSON output schema, and confidence-handling rubric live in `references/agent-matching.md`. It is loaded only when the skill activates; this architecture doc just records that the layer exists between Steps C and D.

## Why these primitives

**Why git worktrees vs branch-switching?** Filesystem isolation. Each worker can run its own dev server, modify the same paths, and never trip over the others. Branch-switching forces sequential operation in the same working tree.

**Why tmux vs background processes?** Visibility. The operator sees what every worker is doing in real time and can intervene. Background processes need a separate UI (logs, dashboards, IPC) to provide the same observability.

**Why STATUS.md vs IPC/sockets?** Crash safety. Files survive worker crashes, tmux server restarts, and `--cleanup` halfway through. They're inspectable post-hoc with `cat`. Sockets and FIFOs disappear when the producer dies.

**Why per-launch consent for `--dangerously-skip-permissions`?** Bounded blast radius doesn't mean zero blast radius. The flag is a real authorization; making it opt-in per launch keeps the user in control.
