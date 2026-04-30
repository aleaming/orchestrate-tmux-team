---
description: Spawn a parallel tmux team for the current project. Elicits worker breakdown, generates launch script + prompts, walks through launch → monitor → merge → cleanup → PR.
argument-hint: "<feature-name> [N-workers]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "AskUserQuestion", "Skill"]
---

Run the `orchestrating-parallel-agents` skill. Use `$ARGUMENTS` as the feature name (slug-form — becomes the tmux session name + branch prefix). If the user did not provide a feature name, ask via AskUserQuestion. Otherwise immediately invoke the skill, which handles the full workflow:

1. Confirm we're in a git repo on a feature branch (offer to create one if on main).
2. Detect project type (Node / Python / bare) for `{{VERIFY_COMMANDS}}` resolution.
3. Elicit the worker breakdown (names, file scopes, dependency order, optional pre-staging).
4. Generate `scripts/launch-team.sh` + `.claude/team-prompts/{coordinator,<worker>}.md` from skill templates.
5. Smoke-test: `bash -n` on the rendered script; verify no `{{...}}` placeholders left.
6. Provide the four lifecycle commands (launch / attach / status / cleanup) for the user to run.
7. Ask the user about auto-launch consent (manual / auto-without-flag / auto-with-`--dangerously-skip-permissions`).
8. After workers complete (`STATUS.md = READY`), perform the merge + verify + push + PR sequence.
