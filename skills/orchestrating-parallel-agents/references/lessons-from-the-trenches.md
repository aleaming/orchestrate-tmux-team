# Lessons from the trenches

Eleven defenses, each surfaced by a real failure during production launches, a senior-orchestration review, or the v1.2.1 end-to-end test cycle. The launcher template encodes all of them; this doc is for understanding *why* each line is there so you don't accidentally remove one.

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

## L10 — Empty-array iteration under `set -u` on bash 3.2 (added in v1.2.1)

**Symptom:** on macOS, `bash scripts/launch-team.sh` aborts during `cmd_launch` with `STAGED_FILES[@]: unbound variable`. Both worktrees were created on disk, but neither was rolled back — the operator is left with orphan worktrees + sibling branches and no clear path forward.

**Root cause:** `/usr/bin/env bash` resolves to `/bin/bash` 3.2.57 on macOS. Under `set -u`, `"${empty_array[@]}"` errors with "unbound variable" instead of expanding to nothing. Worse: that error is fatal at the parameter-expansion layer, so it terminates the shell *before* the `ERR` trap can fire — meaning `on_launch_fail` (the rollback handler) is bypassed entirely. The script dies mid-`cmd_launch`, leaving partial state behind.

The bug is doubly hazardous: the rollback handler itself iterates `created_worktrees[@]` and `created_branches[@]`, both of which start empty. So even if the trap *did* fire (e.g. on a different failure type), the rollback would die on the first empty array and abort silently.

**Fix:** all three iteration sites use `${arr[@]+"${arr[@]}"}` — the canonical bash-3.2-compatible "expand only if set" idiom. Empty arrays expand to nothing; non-empty arrays expand normally. Works on bash 3.2 through 5.x.

**Why this matters:** `STAGED_FILES` is empty in the *common* case (no pre-staging requested). So the bug breaks the happy path on every macOS user without a newer bash earlier in `PATH` than `/bin/bash`. The first symptom they see is half-built state with no trail of how to recover. v1.2.1 patches this and the test harness (`run-T4.sh` § T4b) verifies rollback now fires correctly under a synthetic partial-failure injection.

---

## L11 — Stale non-worktree directory at a worker path (added in v1.2.1)

**Symptom:** a previous `bash launch-team.sh` invocation died mid-launch (e.g. crashed before rollback ran, or the user `kill`ed it). The next invocation prints `= worktree exists: …/testfeat-schema` for every worker whose worktree directory survived. tmux comes up with panes pointing at directories that aren't real worktrees. Downstream `git -C "$wt" status` calls fail in unhelpful ways.

**Root cause:** the per-worker setup loop was `if [[ ! -d "$wt" ]]; then git worktree add … ; else echo "= worktree exists" ; fi`. The `else` branch treats *any* directory at that path as if it were a valid worktree. There's no check that the path is actually a git worktree root.

A naive instinct is to use `git -C "$wt" rev-parse --is-inside-work-tree` — but that returns true for *any* path under the parent repo, including a stale dir at `<repo>/.claude/worktrees/foo/`. So that probe defeats the guard rather than implements it.

**Fix:** check `[[ -e "$wt/.git" ]]`. Real worktrees have a `.git` *file* (containing `gitdir: <main-repo>/.git/worktrees/<name>`) at their root. Main repos have a `.git` *directory*. Stale non-worktree dirs have neither. If the path exists but lacks `.git`, abort with an actionable error (`run: bash $0 --cleanup`).

**Why this matters:** silent corruption of orchestrator state is the worst failure mode — every command after the silent reuse runs against the wrong assumptions. Surfacing the conflict early gives the operator a one-line recovery (`bash launch-team.sh --cleanup`) instead of a confusing cascade of downstream errors.

---

## How these compose

L1+L4 pair: rogue panes (L1) reindex the others (L4 trigger). Stability poll covers both.
L2+L5 pair: alias bypass (L2) is needed because L5's split send-keys runs in the pane shell.
L6+L7 pair: bracketed paste (L6) enables auto-launch; per-launch consent (L7) governs whether to use it.
L8+L9 pair: pre-staging (L8) lets parallel workers depend on each other; state machine (L9) lets the coordinator handle the cases where parallelism breaks down.
L10+L11 pair: both protect the launcher's *recovery* posture — L10 makes the rollback path itself executable on bash 3.2, L11 makes the next-launch path detect leftover state from a prior crash that bypassed rollback. Together they close the "partial state without trail" failure class.
