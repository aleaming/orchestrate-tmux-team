# Lessons from the trenches

Nine defenses, each surfaced by a real failure during two production launch cycles plus a senior-orchestration review. The launcher template encodes all of them; this doc is for understanding *why* each line is there so you don't accidentally remove one.

Each defense follows the format: **Symptom → Root cause → Fix → Why this matters**.

---

## L1 — Rogue tmux plugin panes

**Symptom:** after `tmux new-session`, `tmux list-panes` shows an extra pane at index 0 with `cwd=~/.config/tmux/plugins/<plugin>/...`. Worker indices shift. Color application lands on wrong panes.

**Root cause:** tmux plugins like `OpenSessions` hook `session-created` and inject a TUI pane *asynchronously* (after `new-session` returns). Static cleanup runs too early and misses it.

**Fix:** two-pass cleanup. After `new-session`: wait for pane count to stabilize (poll until 3 consecutive 100ms checks return the same count) then kill any pane whose `pane_current_path` is outside `$REPO_ROOT`. Repeat after worker splits (catches plugins that hook on later events). Iterate panes in **reverse index order** (`sort -rn`) so kills don't shift remaining indices mid-loop.

**Why this matters:** without it, every other launch on a machine with such a plugin lands colors on the wrong roles, and the operator can't tell which pane is which.

---

## L2 — `cat=bat` shell alias

**Symptom:** `tmux send-keys` with `cat TASK.md` errors out: `zsh: command not found: bat`. Or in bash heredoc command-substitution, `git commit -m "$(cat <<'EOF' ... EOF)"` produces empty commit messages.

**Root cause:** user's interactive zsh has `alias cat=bat`. Even `tmux send-keys "cat ..."` triggers alias expansion when zsh is the pane shell.

**Fix:** in scripts, use `command cat` (POSIX builtin that bypasses aliases). For pane shells, prefix every send-keys command with `unalias cat 2>/dev/null; `. Use `printf` instead of `cat <<EOF` heredocs in command substitution.

**Why this matters:** every dev with a fancy shell setup hits this differently. `command cat` is the universal bypass. (We hit this defense in our own implementation — see L2 in this plugin's git history.)

---

## L3 — zsh `:t` modifier eating session names

**Symptom:** `tmux list-panes -t "$SESSION:team"` errors with `can't find window: theme-gen-phase2eam` (note: missing `:t`).

**Root cause:** zsh's parameter modifier `${VAR:t}` returns the path-tail. Even unbraced `$VAR:team` triggers modifier-style parsing in some zsh contexts, eating `:t`.

**Fix:** always brace as `${SESSION}:team`. Universal — bash and zsh both accept braced form.

**Why this matters:** silent failure mode. The script appears to run, but every tmux command targets the wrong window and errors are easy to miss.

---

## L4 — Pane index instability after kill-pane

**Symptom:** color application lands on wrong panes after rogue-pane cleanup runs.

**Root cause:** when `tmux kill-pane` removes a pane, remaining panes renumber to fill the gap. Hardcoded `${SESSION}:team.0` references the wrong role after a kill.

**Fix:** identify panes by their `pane_current_path` (cwd), not by numeric index. Iterate `tmux list-panes -F "#{pane_index}:#{pane_current_path}"` and look up role from cwd → color mapping.

**Why this matters:** bash 3.2 (macOS default) doesn't have associative arrays, so the mapping uses a nested loop over the WORKERS array. Slightly verbose but stable.

---

## L5 — `send-keys` timing race

**Symptom:** `printf 'claude'` output appears in the pane scrollback but doesn't pre-fill the next prompt.

**Root cause:** bundling `clear; ...; printf 'claude'` into a single send-keys with `C-m` runs the whole thing as one shell command. `printf 'claude'` outputs to stdout, then the shell renders a fresh empty prompt.

**Fix:** split into two `tmux send-keys` calls. First call ends with `C-m` (executes the display). Second call sends the literal characters `claude` with **no** `C-m` — they land on the next prompt as input. Tmux serializes pty input, so no sleep needed between the two.

**Why this matters:** the pre-typed command is the UX affordance that lets the user just hit Enter to launch. Without this fix, the user has to type `claude` themselves in every pane.

---

## L6 — `tmux load-buffer` + `paste-buffer -p` for autonomous task injection

**Symptom:** sending multi-line task content via `tmux send-keys "..."` produces fragmented behavior — sometimes claude submits prematurely after the first newline.

**Fix:** write the task to a file (TASK.md), `tmux load-buffer -b worker-N TASK.md`, then `tmux paste-buffer -t pane.N -b worker-N -p`. The `-p` flag enables bracketed paste — claude's TUI detects the bracket markers and treats the entire content as one paste, not a sequence of line submissions.

**Cleanup:** `tmux delete-buffer -b worker-N` after each paste, or buffers leak until the tmux server restarts.

**Why this matters:** without bracketed paste, autonomous launch breaks on any task content with internal newlines (i.e., all of them).

---

## L7 — `--dangerously-skip-permissions` is per-launch consent

**Symptom:** workers running with `--dangerously-skip-permissions` execute Bash and Edit without asking.

**Policy:** the flag is dangerous in users' main repos. In *isolated worktrees* the blast radius is bounded (worst case: a bad commit on a sibling branch, recoverable). But it's still a real authorization the user must give per-launch.

**Fix:** the skill MUST ask before adding the flag. Three paths to offer the user:

1. Manual launch (user attaches and approves each tool call)
2. Auto-launch without flag (workers pause for approvals — user babysits each pane)
3. Auto-launch with flag (workers run autonomously)

The skill never assumes (3).

**Why this matters:** in the original implementation a permission denial caught the assumption-bypass on the first attempt. Same denial would catch any future bypass attempt — which is correct.

---

## L8 — Pre-staging files for cross-worker compile dependencies

**Symptom:** worker B's task imports from worker A's not-yet-existing file. `tsc` fails in B's worktree.

**Fix:** before launching workers, the script copies pre-staged file(s) into both worktrees. Only worker A commits the file (per their TASK.md scope); worker B uses it locally for compilation but doesn't `git add` it. The merge brings the canonical file into the parent branch via worker A's branch.

The launcher's `STAGED_FILES` array encodes this: `"src-abs|workerA,workerB|dest-rel"`. The skill elicits whether pre-staging is needed during `/spawn-team` setup; default is none.

**Why this matters:** without pre-staging, the only options are (a) sequential workers (kills parallelism) or (b) stub the import (worker B leaves broken code that the coordinator fixes). Pre-staging preserves both parallelism and clean per-worker scopes.

---

## L9 — STATUS.md state machine (added in v1)

**Symptom:** original protocol used a single `READY` token. Coordinator couldn't distinguish "still working" from "crashed" or "blocked." If a worker hung, the coordinator polled forever.

**Fix:** extend STATUS.md to a five-state machine:

| State | Meaning | Coordinator response |
|---|---|---|
| `PENDING` | Worktree exists, claude not started | Wait |
| `IN_PROGRESS <task>` | Worker is actively working | Wait |
| `READY <summary>` | Worker complete, branch ready to merge | Proceed once all are READY |
| `FAILED <reason>` | Worker errored unrecoverably | Attach pane, decide: nudge / restart / abort team |
| `BLOCKED <reason>` | Worker waiting on external input | Resolve the dependency, then nudge worker |

Workers MUST emit one of these tokens at line 1 of STATUS.md. Multi-line is allowed (lines 2+ are context for FAILED/BLOCKED).

**Why this matters:** without states, hung workers and crashed workers look identical. The coordinator either merges incomplete work or polls indefinitely. The state machine makes the team observable.

---

## How these compose

L1+L4 pair: rogue panes (L1) reindex the others (L4 trigger). Stability poll covers both.
L2+L5 pair: alias bypass (L2) is needed because L5's split send-keys runs in the pane shell.
L6+L7 pair: bracketed paste (L6) enables auto-launch; per-launch consent (L7) governs whether to use it.
L8+L9 pair: pre-staging (L8) lets parallel workers depend on each other; state machine (L9) lets the coordinator handle the cases where parallelism breaks down.
