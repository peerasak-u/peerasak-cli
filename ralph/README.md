# Freedom Ralph

Autonomous coding agent that works through GitHub issues while you're AFK.

## How it works

```
┌─────────────────────────────────────────┐
│  You run: ./once.sh or ./afk.sh N       │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Ralph (pi agent) wakes up              │
│  • Reads open GitHub issues             │
│  • Filters to AFK-labeled only         │
│  • Skips any HITL-labeled issues        │
│  • Picks ONE issue, highest priority    │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Work cycle (per issue)                 │
│  1. RED: write failing test            │
│  2. GREEN: minimal code to pass        │
│  3. REFACTOR: clean up                 │
│  4. Run tests + typecheck              │
│  5. Commit with clear message         │
│  6. Comment/close issue               │
│  7. Log to progress.txt               │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Ralph finishes all AFK issues         │
│  → outputs <promise>NO MORE TASKS</promise>
└─────────────────────────────────────────┘
```

## Scripts

| Script | Use case |
|--------|----------|
| `once.sh` | Quick single run (one pi invocation) |
| `afk.sh N` | Loop up to N iterations, stops early if done |

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
