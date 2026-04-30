# Auto-launch via tmux paste-buffer

How to launch all workers without manual paste, using `tmux load-buffer` + `paste-buffer -p`. This is opt-in (L7); the skill must ask the user before invoking this path.

## Pre-conditions

Before auto-launch runs, each worker pane must be at a shell prompt with `claude` pre-typed (this is what `cmd_launch` sets up via the L5 split-send-keys pattern). The cursor is on the line `❯ claude`, waiting for the user to hit Enter.

The `TASK.md` file already exists in each worktree (copied by the launcher).

## Authorization (L7)

The auto-launch path comes in two flavors. The skill MUST ask the user which to use:

### Variant A: auto-launch without `--dangerously-skip-permissions`

Workers pause at every tool call for the user to approve. The user attaches and walks the panes accepting/rejecting prompts. Less risky; more babysitting.

### Variant B: auto-launch with `--dangerously-skip-permissions`

Workers run autonomously, executing Bash/Edit/Write without approval prompts. The blast radius is bounded by the worktree (a bad commit lands on a sibling branch, recoverable), but it's still a real authorization. The user grants this **per launch**; the skill never assumes it.

If the user declines both variants, the skill skips auto-launch entirely and just leaves the panes ready for manual launch.

## Steps

### 1. Append the flag (Variant B only) and submit each worker's `claude`

For each worker pane index `i`:

```bash
# Variant A: just submit
tmux send-keys -t "${SESSION}:team.${i}" Enter

# Variant B: append the flag, then submit
tmux send-keys -t "${SESSION}:team.${i}" " --dangerously-skip-permissions" Enter
```

### 2. Wait for the claude TUIs to render

```bash
sleep 10
```

Ten seconds is enough for `claude` to start up across all panes. Skipping this step causes the next paste to land in the shell, not the TUI.

### 3. Inject the task with bracketed paste

For each worker pane index `i`:

```bash
tmux load-buffer -b "worker-${i}" "$WORKTREE_ROOT/${WORKTREE_PREFIX}-${name}/TASK.md"
tmux paste-buffer -t "${SESSION}:team.${i}" -b "worker-${i}" -p
tmux delete-buffer -b "worker-${i}"        # cleanup — buffers leak otherwise (L6)
```

The `-p` flag enables **bracketed paste**. Claude's TUI detects the bracket markers and treats the entire content as one paste, regardless of internal newlines. Without `-p`, every newline triggers premature submission and the task fragments.

### 4. Submit the paste

```bash
sleep 2
tmux send-keys -t "${SESSION}:team.${i}" Enter
```

The 2-second sleep gives the TUI time to finish processing the paste before the Enter is interpreted as "submit message."

### 5. Verify

Capture the last few lines of each pane to confirm claude is running and processing:

```bash
for i in "${!WORKERS[@]}"; do
  echo "── pane $i ──"
  tmux capture-pane -t "${SESSION}:team.${i}" -p | tail -5
done
```

Look for claude's "thinking" or "tool call" indicators. If you see a shell prompt instead, the paste happened before claude was ready — back off the timing or re-run the inject step.

## When auto-launch breaks

| Symptom | Likely cause | Fix |
|---|---|---|
| Task content fragments across multiple submissions | `-p` flag missing | Add `-p` to `paste-buffer` |
| Paste lands in shell, not TUI | claude wasn't ready | Increase initial `sleep 10` |
| Buffers accumulate across runs | `delete-buffer` step skipped | Add the cleanup line |
| Worker says "I see you've sent me TASK.md" but doesn't read it | Worker was already in a conversation | This pattern only works for fresh claude TUIs |

## When NOT to use auto-launch

- The first time you're using the plugin on a project. Launch manually so you can see how the panes are set up.
- After a partial cleanup where some worktrees survived. Manual launch lets you inspect them first.
- If any worker prompt is more than ~50 lines. The bracketed paste works, but if something goes wrong, recovery is painful. Fall back to manual.
