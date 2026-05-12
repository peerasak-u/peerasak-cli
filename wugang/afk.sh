#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <iterations>"
  echo "Example: $0 10"
  exit 1
fi

ITERATIONS="$1"

setup_prereqs
acquire_lock
trap release_lock EXIT

ui_step "🚀" "Starting Wu Gang AFK · $ITERATIONS iterations"
echo ""

for ((i=1; i<=ITERATIONS; i++)); do
  set +e
  run_iteration "$i" "$ITERATIONS"
  code=$?
  set -e
  if [ "$code" -ne 0 ]; then
    if [ "$code" -eq 10 ]; then
      echo ""
      ui_warn "Stopped: no eligible task right now."
      exit 0
    fi
    exit "$code"
  fi
  echo ""
done

ui_success "Completed $ITERATIONS iterations."
append_progress "Wu Gang stopped: $ITERATIONS iterations exhausted"
