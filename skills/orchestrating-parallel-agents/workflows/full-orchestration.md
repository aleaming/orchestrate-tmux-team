# Full orchestration workflow

End-to-end walkthrough of `/spawn-team`, from invocation to merged PR. This is what the skill executes; humans read it to understand what's happening at each step.

## Step 1 — Pre-flight

Before generating anything, confirm:

1. **Inside a git repo.** `git rev-parse --show-toplevel` returns the repo root. If not, error and offer to `git init`.
2. **On a feature branch, not main.** `git rev-parse --abbrev-ref HEAD`. If on `main`/`master`, ask the user to create a feature branch first or offer to create one (e.g. `feature/<feature-name>`).
3. **Working tree is clean.** `git status --porcelain`. If dirty, warn — workers start from HEAD, so uncommitted work won't propagate. Offer: stash, commit, or proceed-anyway.
4. **Project type.** Look for `package.json` / `pyproject.toml` / `requirements.txt` / `Cargo.toml` / `go.mod`. Used to render `{{VERIFY_COMMANDS}}`. Default: bare-repo placeholder.

## Step 2 — Worker elicitation

Ask the user for the worker breakdown via `AskUserQuestion`. Required per worker:

- **Name** (slug; used as branch suffix and pane label). Lowercase, hyphenated.
- **Scope files** (which files this worker may modify). Bullet list.
- **Task summary** (2–3 sentences). What this worker is trying to accomplish.
- **Hard constraints** (3–5 numbered rules: "no new deps," "no test changes," etc.).
- **Commit message** (the literal `git commit -m "..."` command).
- **Dependency order** (integer; lower = merged first).

Optional team-level questions:

- **Pre-staging?** "Does any worker import from another worker's not-yet-committed file?" If yes, ask for source path, target workers, and dest relative path. Default: none.
- **Auto-launch policy?** Three options: manual / auto-without-flag / auto-with-`--dangerously-skip-permissions`. Default: manual. (See L7.)

## Step 3 — Render artifacts

For each rendered file, substitute `{{...}}` placeholders and check that no markers remain.

### `scripts/launch-team.sh`

Render from `templates/launch-team.template.sh`. Substitutions:

| Placeholder | Value source |
|---|---|
| `{{SESSION}}` | `<feature-name>-team` |
| `{{WORKTREE_PREFIX}}` | `<feature-name>` |
| `{{BRANCH_PREFIX}}` | `feature/<feature-name>-` (or whatever the parent branch is + `-`) |
| `{{COORD_COLOR}}` | `226` (yellow) |
| `{{WORKERS}}` | One line per worker: `"<name>\|<branch-suffix>\|<color-256>"` |
| `{{STAGED_FILES}}` | Pre-staging spec lines, or empty |

After rendering: `chmod +x scripts/launch-team.sh && bash -n scripts/launch-team.sh`.

### `.claude/team-prompts/coordinator.md`

Render from `templates/coordinator.template.md`. Substitutions:

| Placeholder | Value source |
|---|---|
| `{{REPO_ROOT}}` | absolute path to repo |
| `{{FEATURE_BRANCH}}` | current branch name |
| `{{N_WORKERS}}` | count |
| `{{WORKER_LIST_BULLETS}}` | bullet list: `- <name>: <task summary>` |
| `{{BRANCH_LIST_SPACE}}` | space-separated worker branches for the dry-run loop |
| `{{MERGE_ORDER}}` | `git merge --no-ff <branch> -m "merge: <name>"` lines, dependency order |
| `{{VERIFY_COMMANDS}}` | per-project-type block (Step 1) |
| `{{PR_TITLE}}` | derived from feature name; user can override |
| `{{PR_BODY_FILE}}` | path to plan file if known, else empty |
| `{{SESSION}}` | as above |

### `.claude/team-prompts/<worker>.md` (one per worker)

Render from `templates/worker.template.md`. Substitutions per worker. The `{{PRE_STAGED_BLOCK}}` is empty unless this worker received a pre-staged file.

## Step 4 — Smoke test

Mechanical checks:

```bash
bash -n scripts/launch-team.sh
grep -rE '\{\{[A-Z_]+\}\}' scripts/launch-team.sh .claude/team-prompts/   # should produce no output
```

If anything fails, abort and surface the error to the user. Do NOT push artifacts that have unsubstituted placeholders.

## Step 5 — Hand off

Print the four lifecycle commands and stop:

```
✓ Team artifacts generated:
  scripts/launch-team.sh
  .claude/team-prompts/coordinator.md
  .claude/team-prompts/<worker-1>.md
  ...

  ▶ Launch:        bash scripts/launch-team.sh
  ▶ Attach:        tmux attach -t <session-name>
  ▶ Poll status:   bash scripts/launch-team.sh --status
  ▶ Tear down:     bash scripts/launch-team.sh --cleanup
```

If the user opted into auto-launch (Step 2), invoke the steps in `references/auto-launch-via-tmux-paste.md` instead of just printing.

## Step 6 — Wait for READY signals

Workers run on their own. The skill is done at this point unless the user explicitly asks for help. Common monitoring patterns:

- `bash scripts/launch-team.sh --status` (one-shot)
- `watch -n 5 'bash scripts/launch-team.sh --status'` (continuous)
- `tmux attach -t <session>` then Ctrl-b o to cycle

Workers transition: `PENDING → IN_PROGRESS → READY` (success) or `→ FAILED` / `→ BLOCKED`. The coordinator watches.

## Step 7 — Coordinator merge sequence

When all workers report `READY`:

1. **Pre-merge dry-run** — verify each branch applies cleanly without committing.
2. **Real merge** — `git merge --no-ff <branch>` in dependency order.

Both are detailed in `.claude/team-prompts/coordinator.md` (Phase 2a/2b).

## Step 8 — Verification

Run `{{VERIFY_COMMANDS}}` on the parent branch (now containing all merged worker branches). If verification fails, the integration is the suspect — workers' branches dry-ran clean.

## Step 9 — Push + PR

```bash
git push -u origin <feature-branch>
gh pr create --title '<title>' --body-file <plan-or-body-path>
```

## Step 10 — Cleanup

```bash
bash scripts/launch-team.sh --cleanup
```

Run after the PR is merged. Removes session, worktrees, and worker branches. The parent feature branch (and the merged commits on it) are untouched.

---

## Failure recovery

When something goes wrong mid-flow, here's the playbook:

### Worker writes `FAILED <reason>`

1. Attach: `tmux attach -t <session>`, find the worker's pane.
2. Read its STATUS.md in full (`cat .claude/worktrees/<prefix>-<name>/STATUS.md`) — line 2+ have the error context.
3. Decide:
   - **Nudge** — give claude more context, ask it to retry.
   - **Restart** — kill the pane, re-launch the single worker manually with the same TASK.md.
   - **Abort team** — `bash scripts/launch-team.sh --cleanup` and rethink the breakdown.

### Worker writes `BLOCKED <reason>`

The worker is waiting on external input (e.g., a missing schema file from another worker). Resolve the blocker on the parent branch or another worker's branch, then nudge the blocked worker (`tmux attach`, type "now try again").

### Coordinator dry-run reports a conflict

A worker's branch will conflict at real-merge time. Don't proceed. Either:
- Resolve in that worker's worktree (rebase onto current parent or fix the conflict), or
- Write `BLOCKED conflict-with-<other>` to that worker's STATUS.md and let them deal with it.

### Launcher fails mid-creation

The `trap on_launch_fail ERR` rolls back. You should see the rollback message and find no orphaned worktrees. If something escapes the trap (bug in the script), `bash scripts/launch-team.sh --cleanup` is idempotent — run it.

### Tmux session lost (laptop closed, etc.)

Worktrees survive on disk. Worker progress (commits, STATUS.md) survives in their respective worktrees. Re-launch:

```bash
tmux new-session -d -s <session> -n team -c <repo>
# attach and reconstruct panes manually, or
bash scripts/launch-team.sh --cleanup && bash scripts/launch-team.sh
```

The `--cleanup`-then-relaunch path discards in-flight work (worktrees are removed). Only do that if you're starting over.
