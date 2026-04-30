#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RALPH_DIR="$(dirname "$SCRIPT_DIR")"
PROGRESS_FILE="$RALPH_DIR/progress.txt"

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  echo "Example: $0 10"
  exit 1
fi

if [ -z "$CMUX_SOCKET_PATH" ]; then
  echo "Error: Not running inside cmux. Please run from a cmux terminal."
  exit 1
fi

ITERATIONS=$1
touch "$PROGRESS_FILE"

echo "Starting freedom-ralph for $ITERATIONS iterations..."
echo ""

for ((i=1; i<=ITERATIONS; i++)); do
  echo "=== Iteration $i/$ITERATIONS ==="

  # Create right split for Ralph
  SPLIT=$(cmux new-split right 2>&1)
  echo "SPLIT: $SPLIT"
  
  # Extract surface ref
  RALPH_SURFACE=$(echo "$SPLIT" | grep -oE 'surface:[0-9]+' || echo "")
  
  if [ -z "$RALPH_SURFACE" ]; then
    echo "Error: Failed to create Ralph's pane"
    exit 1
  fi

  sleep 0.3

  # Build context
  commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits")
  issues=$(gh issue list --state open --json number,title,body,labels,comments 2>/dev/null || echo "[]")
  prompt=$(cat "$SCRIPT_DIR/prompt.md")

  context="Previous commits:
$commits

Open GitHub issues:
$issues

---

$prompt"

  # Write context to temp file
  CONTEXT_FILE="/tmp/ralph_ctx_$$_$i.txt"
  echo "$context" > "$CONTEXT_FILE"

  # Send command to read from temp file and pipe to pi
  cmux send --surface "$RALPH_SURFACE" "cat $CONTEXT_FILE | pi -p --no-session\n"

  # Clean up temp file
  rm -f "$CONTEXT_FILE"
  
  # Wait for Ralph to finish
  DONE=false
  for ((poll=1; poll<=600; poll++)); do
    sleep 1
    
    # Read output from Ralph's pane
    output=$(cmux read-screen --surface "$RALPH_SURFACE" --scrollback --lines 100 2>/dev/null)
    
    if echo "$output" | grep -q "<promise>ISSUE DONE</promise>"; then
      DONE=true
      break
    fi
    
    # Check if Ralph crashed or died
    if ! cmux tree --json 2>/dev/null | grep -q "$RALPH_SURFACE"; then
      break
    fi
  done

  # Log progress
  if [ "$DONE" = true ]; then
    echo "✓ Ralph finished issue"
    echo "[$(date)] Done: iteration $i" >> "$PROGRESS_FILE"
  else
    echo "⚠ Ralph timed out or crashed"
    echo "[$(date)] Warning: iteration $i incomplete" >> "$PROGRESS_FILE"
  fi

  # Close Ralph's pane
  cmux close-surface --surface "$RALPH_SURFACE" 2>/dev/null || true

  # Check if there are more AFK issues
  remaining=$(gh issue list --state open --label AFK --json number 2>/dev/null | grep -c '"number"' || echo "0")
  
  if [ "$remaining" -eq 0 ]; then
    echo ""
    echo "✓ Ralph complete — no more AFK issues."
    echo "[$(date)] Ralph stopped: NO MORE TASKS" >> "$PROGRESS_FILE"
    exit 0
  fi

  echo ""
done

echo ""
echo "Completed $ITERATIONS iterations."
echo "[$(date)] Ralph stopped: $ITERATIONS iterations exhausted" >> "$PROGRESS_FILE"
