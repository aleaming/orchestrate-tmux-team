# orchestrate-tmux-team — Guide

> Long-form educational content for the project. Mirrors the structure of the global Claude Code "best practices" guide but focused on tmux-based agent orchestration.
>
> _Stub — fill in once implementation lands._

## Table of contents

1. [Why tmux for agent orchestration?](#why-tmux)
2. [Project layout](#project-layout)
3. [Spinning up a team](#spinning-up-a-team)
4. [Communication patterns between panes](#communication-patterns)
5. [Hooks and deterministic safety](#hooks-and-safety)
6. [Skills you can drop in](#skills)
7. [Troubleshooting](#troubleshooting)

---

## Why tmux for agent orchestration?<a name="why-tmux"></a>

_TODO: write this section once the runtime is implemented. Cover: why tmux beats screen/just-spawning-processes, how panes give per-agent isolation with shared visibility, and why `send-keys` is a robust IPC primitive for shell-native agents._

## Project layout<a name="project-layout"></a>

See [`CLAUDE.md`](./CLAUDE.md) — the canonical map of folders. This guide expands on the *intent* of each folder, not just its name.

## Spinning up a team<a name="spinning-up-a-team"></a>

_TODO: example invocation, e.g._

```bash
./scripts/start-team.sh --count 3 --layout tiled
```

## Communication patterns between panes<a name="communication-patterns"></a>

_TODO: cover broadcasting, point-to-point send-keys, capture-pane → pipe, and a shared work-queue file convention._

## Hooks and deterministic safety<a name="hooks-and-safety"></a>

See `hooks/` for working examples. Hooks return exit code 2 to block; CLAUDE.md prose returns nothing — only hooks can guarantee a rule holds under load.

## Skills<a name="skills"></a>

See `skills/` — `commit-messages/` and `security-audit/` ship with the scaffold.

## Troubleshooting<a name="troubleshooting"></a>

_TODO._
