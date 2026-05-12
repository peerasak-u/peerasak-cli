#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

setup_prereqs
acquire_lock
trap release_lock EXIT

echo "Starting Wu Gang (single iteration)..."
echo ""

if ! run_iteration 1 1; then
  code=$?
  if [ "$code" -eq 10 ]; then
    echo "Wu Gang stopped: no eligible task right now."
    exit 0
  fi
  exit "$code"
fi

echo "✓ Wu Gang finished single iteration."
