# Coordinator  🟨

You stay in `{{REPO_ROOT}}` on `{{FEATURE_BRANCH}}`.
The {{N_WORKERS}} workers are operating in parallel git worktrees under `.claude/worktrees/`.

**Workers in this team:**
{{WORKER_LIST_BULLETS}}

{{MATCHED_AGENT_BLOCK}}

## Phase 1 — Watch

Poll for completion. Each worker writes one of these states to `STATUS.md`:

- `PENDING` — not yet started
- `IN_PROGRESS <task>` — working
- `READY <summary>` — done, ready to merge
- `FAILED <reason>` — needs human intervention
- `BLOCKED <reason>` — waiting on something external

Quick poll:

```bash
bash scripts/launch-team.sh --status
```

Continuous poll (refresh every 5s):

```bash
watch -n 5 'bash scripts/launch-team.sh --status'
```

Proceed to Phase 2 only when **all** workers report `READY`. If any worker reports `FAILED` or stays `IN_PROGRESS` beyond expectations, attach to that pane (`tmux attach -t {{SESSION}}` then Ctrl-b o), inspect, and decide whether to nudge, restart, or abort.

## Phase 2a — Pre-merge dry-run

Before the real merge sequence, verify each worker branch applies cleanly:

```bash
for br in {{BRANCH_LIST_SPACE}}; do
  echo "── dry-run: $br ──"
  git merge --no-commit --no-ff "$br" 2>&1 || true
  git merge --abort 2>/dev/null || true
done
```

If any branch produces conflicts, surface them to the affected worker (write `BLOCKED <conflict-with-X>` to their `STATUS.md` or attach to their pane and resolve). Do **not** proceed to Phase 2b until dry-runs are clean.

## Phase 2b — Merge in dependency order

```bash
{{MERGE_ORDER}}
```

The dependency order is what was elicited at `/spawn-team` setup. If a worker's output is a precondition for another's compile-time correctness, merge the producer first.

## Phase 3 — Verification

{{VERIFY_COMMANDS}}

If verification fails, the integration is the suspect — not the workers (their branches dry-ran clean). Inspect the merge commits, fix on the parent branch, and re-run.

## Phase 4 — Push and PR

```bash
git push -u origin {{FEATURE_BRANCH}}
gh pr create \
  --title '{{PR_TITLE}}' \
  --body-file {{PR_BODY_FILE}}
```

If `{{PR_BODY_FILE}}` is unset, draft the body inline summarizing the worker contributions:

```bash
gh pr create --title '{{PR_TITLE}}' --body "$(printf 'Multi-worker feature merge.\n\nWorkers:\n{{WORKER_LIST_BULLETS}}\n\nVerification: passed (see Phase 3 commands).\n')"
```

## Phase 5 — Cleanup (optional)

```bash
bash scripts/launch-team.sh --cleanup
```

Removes the tmux session, all worker worktrees, and all worker branches. Run this after the PR is merged (or earlier if you've abandoned the team).
