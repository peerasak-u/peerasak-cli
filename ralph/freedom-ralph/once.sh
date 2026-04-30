#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RALPH_DIR="$(dirname "$SCRIPT_DIR")"

# Get recent git commits (last 5)
commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits")

# Get open GitHub issues
issues=$(gh issue list --state open --json number,title,body,comments 2>/dev/null || echo "[]")

# Read the prompt
prompt=$(cat "$SCRIPT_DIR/prompt.md")

# Build the context
context="Previous commits:
$commits

Open GitHub issues:
$issues

---

$prompt"

# Run pi with the context
pi -p --no-session "$context"