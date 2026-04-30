#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RALPH_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  echo "Example: $0 10"
  exit 1
fi

ITERATIONS=$1
PROGRESS_FILE="$RALPH_DIR/progress.txt"

# Ensure progress file exists
touch "$PROGRESS_FILE"

echo "Starting freedom-ralph for $ITERATIONS iterations..."

for ((i=1; i<=ITERATIONS; i++)); do
  echo ""
  echo "=== Iteration $i/$ITERATIONS ==="

  # Get recent git commits
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

  # Run pi and capture output
  output=$(pi -p --no-session "$context" 2>&1)
  echo "$output"

  # Check if freedom-ralph completed
  if echo "$output" | grep -q "<promise>NO MORE TASKS</promise>"; then
    echo ""
    echo "✓ Ralph complete after $i iterations."
    echo "[$(date)] Ralph stopped: NO MORE TASKS" >> "$PROGRESS_FILE"
    exit 0
  fi
done

echo ""
echo "Completed $ITERATIONS iterations."
echo "[$(date)] Ralph stopped: $ITERATIONS iterations exhausted" >> "$PROGRESS_FILE"