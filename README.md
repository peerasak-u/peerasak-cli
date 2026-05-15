# Tony CLI

Short-hand scripts for working with AI coding agents.

Right now this repo only includes **Wu Gang**, a small automation wrapper for running AI coding agents against GitHub issues in a controlled loop.

## Wu Gang

Wu Gang is an autonomous issue runner. It looks for one active PRD issue and eligible AFK task issues, then launches an agent in a `cmux` pane with the relevant GitHub issue context.

It is designed to keep long-running agent work constrained:

- requires a clean git working tree before running
- uses GitHub labels to choose work:
  - `PRD` — the active product/plan issue
  - `AFK` — tasks safe for autonomous execution
  - `HITL` — tasks blocked on human input
- gives the agent one task issue at a time
- requires the agent to verify, commit, and close the task issue before signaling done
- records runtime progress under `.wugang/` 

## Scripts

```bash
wugang/once.sh
```

Run one Wu Gang iteration.

```bash
wugang/afk.sh <iterations>
```

Run multiple Wu Gang iterations, stopping when there are no eligible tasks or a task needs human input.

## Requirements

Wu Gang expects these tools to be available:

- `git`
- `gh`
- `jq`
- `cmux`
- `pi`
- macOS `caffeinate`

It also expects to run inside a `cmux` session with GitHub CLI already authenticated.

## Notes

This is personal tooling, not a polished framework. Expect scripts to reflect my own workflow and assumptions.
