#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

setup_prereqs
acquire_lock
trap release_lock EXIT

ui_step "🚀" "Starting Wu Gang · single iteration"
echo ""

set +e
run_iteration 1 1
code=$?
set -e

if [ "$code" -ne 0 ]; then
  if [ "$code" -eq 10 ]; then
    ui_warn "Stopped: no eligible task right now."
    exit 0
  fi
  exit "$code"
fi

ui_success "Wu Gang finished single iteration."
