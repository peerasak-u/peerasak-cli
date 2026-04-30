#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RALPH_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "$CMUX_SOCKET_PATH" ]; then
  echo "Error: Not running inside cmux. Please run from a cmux terminal."
  exit 1
fi

echo "Starting freedom-ralph (single run)..."
echo ""

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
CONTEXT_FILE="/tmp/ralph_ctx_$$.txt"
echo "$context" > "$CONTEXT_FILE"

# Send command to read from temp file and pipe to pi
cmux send --surface "$RALPH_SURFACE" "cat $CONTEXT_FILE | pi -p
"

# Clean up temp file
rm -f "$CONTEXT_FILE"

echo "Ralph is running in the right pane. Waiting for completion..."

# Wait for Ralph to finish (up to 30 minutes)
DONE=false
for ((poll=1; poll<=1800; poll++)); do
  sleep 1
  
  output=$(cmux read-screen --surface "$RALPH_SURFACE" --scrollback --lines 100 2>/dev/null)
  
  if echo "$output" | grep -q "<promise>ISSUE DONE</promise>"; then
    DONE=true
    break
  fi
  
  # Check if Ralph died
  if ! cmux tree --json 2>/dev/null | grep -q "$RALPH_SURFACE"; then
    break
  fi
done

# Close Ralph's pane
cmux close-surface --surface "$RALPH_SURFACE" 2>/dev/null || true

if [ "$DONE" = true ]; then
  echo ""
  echo "✓ Ralph finished the issue."
else
  echo ""
  echo "⚠ Ralph stopped (timed out or crashed)."
fi
