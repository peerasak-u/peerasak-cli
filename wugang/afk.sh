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

echo "Starting Wu Gang for $ITERATIONS iterations..."
echo ""

for ((i=1; i<=ITERATIONS; i++)); do
  if ! run_iteration "$i" "$ITERATIONS"; then
    code=$?
    if [ "$code" -eq 10 ]; then
      echo ""
      echo "Wu Gang stopped: no eligible task right now."
      exit 0
    fi
    exit "$code"
  fi
  echo ""
done

echo "Completed $ITERATIONS iterations."
append_progress "Wu Gang stopped: $ITERATIONS iterations exhausted"
