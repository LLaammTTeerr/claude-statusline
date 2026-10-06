# claude-statusline

A two-line status line for [Claude Code](https://claude.com/claude-code), plus matching rows for each running subagent. The right side of both lines is aligned to the terminal edge, and lines up with the subagent rows.

```
◆ Opus 5.5 [medium] │ ▸ ~/5DChess/…/agent-ae699d5ddecf89420 │ ⎇ feat/guide ⑂ nifty-ferret-420        PR #19 ⊕ merged
▰▰▰▰▱▱▱▱▱▱ 38% 76k/200k                              ⏱ 23m │ vs main +961 −15 │ 5h 41% 7d 18% │ cache ▲warm

● save-load │ sonnet 5.5 [low] │ ▰▱▱▱▱  20% │ ⎇ feat/save-load ⑂ zesty-newt-3fe                   #20 ⊕ │ 1m10s
● Explore   │ haiku 4.5        │ ▱▱▱▱▱   4% │ ⎇ main                            │ ▸ ~/5DChess        — │    9s
```

## What it shows

**Main status line**
- Model and effort level
- Current folder (shortened when the line gets tight)
- Git branch, and the worktree name when you're in one
- PR for the branch, with its state: ○ open, ✓ approved, ± changes requested, ◌ draft, ⊕ merged, ✗ closed
- Context window use as a gauge, coloured green under 50%, amber to 80%, red above
- Session time, lines changed vs the default branch (committed and uncommitted), 5-hour and 7-day usage limits, prompt-cache state

**Subagent rows** (columns aligned across agents)
- Status (● running, ✓ done, ✗ failed), name, model and effort
- Context gauge, branch, worktree, folder, PR, time running
- Subagents without their own effort level show the main session's effort; Haiku shows none
- Agent worktrees (`agent-<hex>`) get a stable funny name such as `zesty-newt-3fe`
- Finished agents are dimmed and their clock stops

## Install

Requires `bash`, `jq` and `git`. `gh` (logged in) is optional and enables the PR column. Linux only for now: terminal width is read via `/proc` and `stty -F`.

```sh
cp statusline-command.sh subagent-statusline.sh statusline-lib.sh ~/.claude/
```

Then merge `settings.example.json` into `~/.claude/settings.json`. `refreshInterval: 1` makes the main line redraw within a second of a window resize, since Claude Code doesn't re-run it on resize by itself.

## Settings

| Variable | Default | Effect |
|---|---|---|
| `SUBAGENT_STATUSLINE_RIGHT_MARGIN` | `2` | Gap between subagent rows and the right edge |
| `STATUSLINE_RIGHT_MARGIN` | subagent margin + 4 | Gap for the main line; the default keeps both right edges aligned |

## Notes

- Nothing waits on the network. PR state comes from `gh pr list --head <branch>`, run in the background and cached for 60 seconds in `~/.cache/claude-statusline/`.
- PRs are looked up by branch name rather than `gh pr view`, which follows the upstream branch and finds the wrong PR for branches created from `origin/main`.
- Claude Code decides when subagent rows appear and disappear (finished agents leave about 30 seconds after their result is collected). The script only controls how each row looks.
