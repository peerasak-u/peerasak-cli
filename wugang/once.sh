#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${CMUX_TERMINAL_PWD:-$PWD}"
WUGANG_DIR="$(dirname "$SCRIPT_DIR")"

# Project-level .wugang/ directory
WUGANG_DATA="$PROJECT_DIR/.wugang"
mkdir -p "$WUGANG_DATA/context"
PROGRESS_FILE="$WUGANG_DATA/progress.txt"

if [ -z "$CMUX_SOCKET_PATH" ]; then
  echo "Error: Not running inside cmux. Please run from a cmux terminal."
  exit 1
fi

# Validate git repo
if [ ! -d ".git" ]; then
  echo "Error: Not a git repository. Wu Gang needs git + GitHub issues."
  exit 1
fi

touch "$PROGRESS_FILE"

echo "Starting Wu Gang (single iteration)..."
echo ""

# Step 1: Create right split pane
SPLIT_OUTPUT=$(cmux new-split right 2>&1)
echo "Created split: $SPLIT_OUTPUT"

# Extract surface ref (format: surface:123)
SURFACE=$(echo "$SPLIT_OUTPUT" | grep -oE 'surface:[0-9]+' | head -1)

if [ -z "$SURFACE" ]; then
  echo "Error: Failed to create Wu Gang's pane"
  exit 1
fi

SURFACE_NUM="${SURFACE#surface:}"
echo "Surface ID: $SURFACE_NUM"

sleep 0.5

# Step 2: Build context (commits + issues + prompt)
commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits")
issues=$(gh issue list --state open --label AFK --json number,title,body,labels,comments 2>/dev/null || echo "[]")
prompt=$(cat "$SCRIPT_DIR/prompt.md")

context="Previous commits:
$commits

Open GitHub issues (AFK only):
$issues

---

$prompt"

# Step 3: Write context to temp file (NOT piping - that breaks TUI)
CONTEXT_FILE="$WUGANG_DATA/context/wugang_ctx_$$_$(date +%s).txt"
echo "$context" > "$CONTEXT_FILE"
echo "Context written to: $CONTEXT_FILE"

# Step 4: Send pi command with @file syntax (not piping)
# The @ syntax tells pi to read context from file while keeping TTY intact
cmux send --surface "$SURFACE" "pi @$CONTEXT_FILE
"

echo "Wu Gang is running in the right pane..."
echo "Waiting for completion signal: <promise>ISSUE DONE</promise>"
echo ""

# Step 5: Poll scrollback for completion sentinel
DONE=false
TIMEOUT=1800  # 30 minutes max
POLL_INTERVAL=2

for ((poll=1; poll<=TIMEOUT; poll++)); do
  sleep $POLL_INTERVAL
  
  # Read scrollback from the pane
  output=$(cmux read-screen --surface "$SURFACE" --scrollback --lines 200 2>/dev/null || echo "")
  
  if echo "$output" | grep -q "<promise>ISSUE DONE</promise>"; then
    DONE=true
    break
  fi
  
  # Check if pane is still alive
  if ! cmux tree 2>/dev/null | grep -q "surface:$SURFACE_NUM"; then
    echo "Pane closed unexpectedly"
    break
  fi
done

# Clean up temp file
rm -f "$CONTEXT_FILE"

# Step 6: Close the pane
cmux close-surface --surface "$SURFACE" 2>/dev/null || true

echo ""
if [ "$DONE" = true ]; then
  echo "✓ Wu Gang finished the issue."
  echo "[$(date)] Done: single iteration" >> "$PROGRESS_FILE"
  exit 0
else
  echo "⚠ Wu Gang stopped (timed out or closed)."
  echo "[$(date)] Warning: single iteration incomplete" >> "$PROGRESS_FILE"
  exit 1
fi
