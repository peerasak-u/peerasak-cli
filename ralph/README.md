# Freedom Ralph

Autonomous coding agent that works through GitHub issues while you're AFK.

Uses **cmux** to display Ralph's output in a live split pane — no more guessing if it's working.

## How it works

```
┌─────────────────────────────────────────────────────┐
│  You run: ./once.sh or ./afk.sh N                  │
│  (must be inside cmux terminal)                    │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│  Ralph's pane splits to the RIGHT                   │
│  ┌─────────────────┬──────────────────────────┐    │
│  │  Your terminal  │  Ralph's output         │    │
│  │                 │  (live, streaming)        │    │
│  └─────────────────┴──────────────────────────┘    │
└─────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│  Ralph picks ONE AFK issue, works it, signals DONE │
│  → Pane closes automatically                       │
│  → Next iteration spawns fresh Ralph               │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

- **cmux must be running** — `afk.sh` and `once.sh` require cmux socket
- **Ralph must be aliased** — add to your shell:

```bash
alias ralph='cd ~/path/to/peerasak-cli/ralph/freedom-ralph'
alias ralph-once='~/path/to/peerasak-cli/ralph/freedom-ralph/once.sh'
alias ralph-afk='~/path/to/peerasak-cli/ralph/freedom-ralph/afk.sh'
```

## Scripts

| Script | Use case |
|--------|----------|
| `once.sh` | Single Ralph session (one issue) |
| `afk.sh N` | Loop up to N iterations, each spawning fresh Ralph |

## Issue Labels

| Label | What it means |
|-------|----------------|
| `AFK` | Ralph will pick it up |
| `HITL` | Human In The Loop — Ralph skips it |

## Priority Order

1. Critical bugfixes
2. Dev infra (tests, types, scripts)
3. Tracer bullets (small E2E slices)
4. Polish and quick wins
5. Refactors

## Progress

Check `progress.txt` in the project root for a log of what Ralph accomplished.
