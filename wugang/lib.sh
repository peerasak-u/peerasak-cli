#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CMUX_TERMINAL_PWD:-$PWD}"
WUGANG_DATA="$PROJECT_DIR/.wugang"
WUGANG_CONTEXT_DIR="$WUGANG_DATA/context"
WUGANG_PROGRESS_FILE="$WUGANG_DATA/progress.txt"
WUGANG_LOCK_DIR="$WUGANG_DATA/run.lock"

WUGANG_TIMEOUT_SECONDS="${WUGANG_TIMEOUT_SECONDS:-1800}"
WUGANG_POLL_INTERVAL_SECONDS="${WUGANG_POLL_INTERVAL_SECONDS:-2}"
WUGANG_STARTUP_SECONDS="${WUGANG_STARTUP_SECONDS:-3}"

REQUIRED_LABELS=("PRD" "AFK" "HITL")

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  WUGANG_BOLD=$'\033[1m'
  WUGANG_DIM=$'\033[2m'
  WUGANG_GREEN=$'\033[32m'
  WUGANG_YELLOW=$'\033[33m'
  WUGANG_RED=$'\033[31m'
  WUGANG_BLUE=$'\033[34m'
  WUGANG_RESET=$'\033[0m'
else
  WUGANG_BOLD=""
  WUGANG_DIM=""
  WUGANG_GREEN=""
  WUGANG_YELLOW=""
  WUGANG_RED=""
  WUGANG_BLUE=""
  WUGANG_RESET=""
fi

log() { printf '%s\n' "$*"; }
ui_info() { printf '%s%s%s %s\n' "$WUGANG_BLUE" "ℹ" "$WUGANG_RESET" "$*"; }
ui_success() { printf '%s%s%s %s\n' "$WUGANG_GREEN" "✓" "$WUGANG_RESET" "$*"; }
ui_warn() { printf '%s%s%s %s\n' "$WUGANG_YELLOW" "⚠" "$WUGANG_RESET" "$*" >&2; }
ui_step() { printf '%s%s%s %s\n' "$WUGANG_BOLD" "$1" "$WUGANG_RESET" "$2"; }
err() { printf '%sError:%s %s\n' "$WUGANG_RED" "$WUGANG_RESET" "$*" >&2; }
die() { err "$*"; exit 1; }

ensure_cmd() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }

ensure_clean_tree() {
  # Wu Gang writes internal artifacts under .wugang/ (progress, contexts, lock).
  # Those files must not make the project look dirty for task execution.
  if [ -n "$(git status --porcelain --untracked-files=all -- . ':(exclude).wugang')" ]; then
    die "Working tree is dirty. Commit/stash/reset changes before running Wu Gang."
  fi
}

append_progress() {
  local message="$1"
  mkdir -p "$WUGANG_DATA"
  touch "$WUGANG_PROGRESS_FILE"
  echo "[$(date)] $message" >> "$WUGANG_PROGRESS_FILE"
}

acquire_lock() {
  mkdir -p "$WUGANG_DATA"
  if ! mkdir "$WUGANG_LOCK_DIR" 2>/dev/null; then
    err "Wu Gang lock already exists: $WUGANG_LOCK_DIR"
    [ -f "$WUGANG_LOCK_DIR/pid" ] && err "PID: $(cat "$WUGANG_LOCK_DIR/pid")"
    [ -f "$WUGANG_LOCK_DIR/started_at" ] && err "Started: $(cat "$WUGANG_LOCK_DIR/started_at")"
    die "Remove lock only if no Wu Gang process is running."
  fi

  echo "$$" > "$WUGANG_LOCK_DIR/pid"
  date > "$WUGANG_LOCK_DIR/started_at"
  gh repo view --json nameWithOwner --jq .nameWithOwner > "$WUGANG_LOCK_DIR/repo" 2>/dev/null || true
}

release_lock() {
  rm -rf "$WUGANG_LOCK_DIR"
}

setup_prereqs() {
  cd "$PROJECT_DIR"
  ensure_cmd cmux
  ensure_cmd gh
  ensure_cmd jq
  ensure_cmd git

  [ -n "${CMUX_SOCKET_PATH:-}" ] || die "Not running inside cmux."
  [ -d .git ] || die "Not a git repository."

  gh auth status >/dev/null 2>&1 || die "gh auth is not ready"
  local repo
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  ui_info "Repo: $repo"

  mkdir -p "$WUGANG_CONTEXT_DIR"
  touch "$WUGANG_PROGRESS_FILE"

  if command -v caffeinate >/dev/null 2>&1; then
    caffeinate -i -w $$ >/dev/null 2>&1 &
  fi

  ensure_clean_tree
  ensure_labels
}

ensure_labels() {
  ensure_label "PRD" "0E8A16" "Product requirements / long-running plan"
  ensure_label "AFK" "1D76DB" "Safe for Wu Gang autonomous execution"
  ensure_label "HITL" "D93F0B" "Human input required; Wu Gang must skip"
}

ensure_label() {
  local name="$1" color="$2" desc="$3"
  if ! gh label list --limit 1000 --json name --jq ".[] | select(.name==\"$name\") | .name" | grep -q "^$name$"; then
    gh label create "$name" --color "$color" --description "$desc" >/dev/null
  fi
}

active_prd_number() {
  local prds
  prds=$(gh issue list --state open --label PRD --limit 1000 --json number,labels)
  local count
  count=$(echo "$prds" | jq 'length')

  if [ "$count" -eq 0 ]; then
    append_progress "STOP no open PRD issue"
    ui_warn "No open PRD issue."
    return 10
  fi

  if [ "$count" -gt 1 ]; then
    die "Multiple open PRD issues found. Wu Gang requires exactly one open PRD."
  fi

  local num
  num=$(echo "$prds" | jq -r '.[0].number')
  local has_hitl
  has_hitl=$(echo "$prds" | jq -r '.[0].labels[]?.name' | grep -E '^HITL$' || true)
  if [ -n "$has_hitl" ]; then
    append_progress "STOP active PRD #$num has HITL"
    ui_warn "Active PRD #$num has HITL; waiting for human."
    return 10
  fi

  echo "$num"
}

extract_section() {
  local heading="$1" body="$2"
  awk -v h="$heading" '
    BEGIN { in_section=0 }
    {
      low=tolower($0)
      if (low ~ "^##[[:space:]]*" tolower(h) "[[:space:]]*$") { in_section=1; next }
      if (in_section && $0 ~ /^#{1,2}[[:space:]]+/) exit
      if (in_section) print
    }
  ' <<< "$body"
}

validate_parent_and_blocked() {
  local issue="$1" active_prd="$2"
  local data body
  data=$(gh issue view "$issue" --json number,title,body,labels,url,state)
  body=$(echo "$data" | jq -r '.body // ""')

  local parent_section parent_refs parent_count parent
  parent_section=$(extract_section "Parent" "$body")
  parent_refs=$(echo "$parent_section" | grep -oE '#[0-9]+' || true)
  parent_count=$(echo "$parent_refs" | sed '/^$/d' | wc -l | tr -d ' ')

  if [ "$parent_count" -ne 1 ]; then
    die "Issue #$issue has invalid Parent section (need exactly one #number)."
  fi

  parent=$(echo "$parent_refs" | head -n1 | tr -d '#')
  if [ "$parent" != "$active_prd" ]; then
    die "Issue #$issue parent #$parent does not match active PRD #$active_prd."
  fi

  local blocked_section
  blocked_section=$(extract_section "Blocked by" "$body")

  if echo "$blocked_section" | grep -qE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|https?://github.com/.+/issues/[0-9]+'; then
    die "Issue #$issue contains cross-repo blockers; only same-repo #123 is supported."
  fi

  local blockers
  blockers=$(echo "$blocked_section" | grep -oE '#[0-9]+' | tr -d '#' || true)

  if [ -z "$blockers" ]; then
    return 0
  fi

  local blocker state
  while read -r blocker; do
    [ -z "$blocker" ] && continue
    state=$(gh issue view "$blocker" --json state --jq .state 2>/dev/null || true)
    [ -n "$state" ] || die "Issue #$issue references blocker #$blocker but it cannot be fetched."
    if [ "$state" = "OPEN" ]; then
      return 20
    fi
  done <<< "$blockers"

  return 0
}

select_afk_issue() {
  local active_prd="$1"
  local issues
  issues=$(gh issue list --state open --label AFK --limit 1000 --json number,labels,title)

  local count
  count=$(echo "$issues" | jq 'length')
  if [ "$count" -eq 0 ]; then
    append_progress "STOP no open AFK issues"
    ui_warn "No open AFK issues."
    return 10
  fi

  local sorted
  sorted=$(echo "$issues" | jq -r 'sort_by(.number)[] | [.number, ([.labels[]?.name] | join(",")), .title] | @tsv')

  local found_any_non_hitl=false
  while IFS=$'\t' read -r num labels title; do
    [ -z "$num" ] && continue
    if echo "$labels" | grep -qE '(^|,)HITL(,|$)'; then
      continue
    fi
    found_any_non_hitl=true

    if validate_parent_and_blocked "$num" "$active_prd"; then
      echo "$num"
      return 0
    else
      local code=$?
      if [ "$code" -eq 20 ]; then
        continue
      fi
      return "$code"
    fi
  done <<< "$sorted"

  if [ "$found_any_non_hitl" = false ]; then
    append_progress "STOP all AFK issues are HITL"
    ui_warn "All AFK issues are HITL; waiting for human."
    return 10
  fi

  append_progress "STOP AFK issues exist but all blocked"
  ui_warn "AFK issues exist but all blocked."
  return 10
}

render_issue_markdown() {
  local issue="$1"
  local data
  data=$(gh issue view "$issue" --json number,title,url,state,labels,body,comments)

  local labels
  labels=$(echo "$data" | jq -r '[.labels[]?.name] | if length==0 then "None" else join(", ") end')

  echo "Issue: #$(echo "$data" | jq -r '.number')"
  echo "Title: $(echo "$data" | jq -r '.title')"
  echo "URL: $(echo "$data" | jq -r '.url')"
  echo "State: $(echo "$data" | jq -r '.state')"
  echo "Labels: $labels"
  echo
  echo "Body:"
  echo "$(echo "$data" | jq -r '.body // ""')"
  echo
  echo "Comments:"

  local ccount
  ccount=$(echo "$data" | jq '.comments | length')
  if [ "$ccount" -eq 0 ]; then
    echo "None."
    return 0
  fi

  echo "$data" | jq -r '.comments | sort_by(.createdAt)[] | "Comment by \(.author.login // \"unknown\") at \(.createdAt):\n\(.body // \"\")\n"'
}

recent_commits_block() {
  git log -n 10 --date=short --pretty=format:'%h %ad%n%s%n---'
}

guard_context_file() {
  local file="$1"
  grep -q '</prd-issue>\|</current-afk-task-issue>\|<prd-issue>\|<current-afk-task-issue>' "$file" && die "Context contains reserved scope tags."
}

guard_no_literal_signals() {
  local file="$1"
  if grep -q '<promise>ISSUE DONE</promise>\|<promise>ISSUE BLOCKED</promise>' "$file"; then
    die "Context contains literal completion signal."
  fi
}

build_context_file() {
  local active_prd="$1" afk_issue="$2" iteration="$3"
  local prompt repo branch head prd_md afk_md commits
  prompt=$(cat "$SCRIPT_DIR/prompt.md")
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  branch=$(git branch --show-current)
  head=$(git rev-parse --short HEAD)
  prd_md=$(render_issue_markdown "$active_prd")
  afk_md=$(render_issue_markdown "$afk_issue")
  commits=$(recent_commits_block)

  local file="$WUGANG_CONTEXT_DIR/wugang_ctx_$$_${iteration}_$(date +%s).txt"
  cat > "$file" <<EOF
wugang context

<repo>
$repo
branch: $branch
head: $head
</repo>

<prd-issue>
$prd_md
</prd-issue>

and this is the task you have to do

<current-afk-task-issue>
$afk_md
</current-afk-task-issue>

<recent-commits>
$commits
</recent-commits>

$prompt
EOF

  guard_no_literal_signals "$file"
  echo "$file"
}

wait_for_signal() {
  local surface="$1" surface_num="$2"
  sleep "$WUGANG_STARTUP_SECONDS"

  local baseline current new_lines output deadline
  baseline=$(cmux read-screen --surface "$surface" --lines 1200 2>/dev/null | wc -l)
  deadline=$((SECONDS + WUGANG_TIMEOUT_SECONDS))

  while [ "$SECONDS" -lt "$deadline" ]; do
    sleep "$WUGANG_POLL_INTERVAL_SECONDS"
    current=$(cmux read-screen --surface "$surface" --lines 1200 2>/dev/null | wc -l)
    new_lines=$((current - baseline))
    if [ "$new_lines" -gt 0 ]; then
      output=$(cmux read-screen --surface "$surface" --lines 1200 2>/dev/null | tail -n "$new_lines")
      local normalized
      normalized=$(echo "$output" | tr '\n' ' ')
      if echo "$normalized" | grep -qE '<promise>[[:space:]]*ISSUE DONE[[:space:]]*</promise>'; then
        echo "DONE"
        return 0
      fi
      if echo "$normalized" | grep -qE '<promise>[[:space:]]*ISSUE BLOCKED[[:space:]]*</promise>'; then
        echo "BLOCKED"
        return 0
      fi
    fi

    if ! cmux tree 2>/dev/null | grep -q "surface:$surface_num"; then
      echo "NO_SIGNAL"
      return 0
    fi
  done

  echo "NO_SIGNAL"
}

verify_done() {
  local issue="$1" start_head="$2"
  local state end_head commit_count msg

  state=$(gh issue view "$issue" --json state --jq .state)
  [ "$state" = "CLOSED" ] || die "Agent signaled DONE but issue #$issue is still open."

  end_head=$(git rev-parse HEAD)
  [ "$end_head" != "$start_head" ] || die "DONE but no new commit was created."

  commit_count=$(git rev-list --count "$start_head"..HEAD)
  [ "$commit_count" -eq 1 ] || die "DONE requires exactly one new commit (got $commit_count)."

  msg=$(git log -1 --pretty=%B)
  echo "$msg" | grep -q "#$issue" || die "Latest commit message must reference #$issue."

  ensure_clean_tree
}

verify_blocked() {
  local issue="$1"
  local state
  state=$(gh issue view "$issue" --json state --jq .state)
  [ "$state" = "OPEN" ] || die "BLOCKED signal invalid: issue #$issue is closed."

  if ! gh issue view "$issue" --json labels --jq '.labels[]?.name' | grep -q '^HITL$'; then
    gh issue edit "$issue" --add-label HITL >/dev/null
  fi

  if [ -n "$(git status --porcelain --untracked-files=all -- . ':(exclude).wugang')" ]; then
    die "Issue blocked but working tree has uncommitted changes."
  fi
}

run_iteration() {
  local iteration="$1" total="$2"
  ui_step "▶" "Iteration $iteration/$total"

  ensure_clean_tree

  local prd
  prd=$(active_prd_number) || return $?

  local issue
  issue=$(select_afk_issue "$prd") || return $?

  local title
  title=$(gh issue view "$issue" --json title --jq .title)

  local context_file
  context_file=$(build_context_file "$prd" "$issue" "$iteration")

  append_progress "START issue #$issue: $title (context: $context_file)"

  log "  PRD:  #$prd"
  log "  Task: #$issue — $title"

  local split_output surface surface_num
  split_output=$(cmux new-split right 2>&1)
  surface=$(echo "$split_output" | grep -oE 'surface:[0-9]+' | head -1)
  [ -n "$surface" ] || die "Failed to create Wu Gang pane"
  surface_num="${surface#surface:}"

  log "  Pane: $surface"

  local start_head
  start_head=$(git rev-parse HEAD)

  cmux send --surface "$surface" "WUGANG_ISSUE=$issue pi @$context_file
" >/dev/null
  ui_info "Waiting for agent signal for #${issue}…"

  local signal
  signal=$(wait_for_signal "$surface" "$surface_num")

  cmux close-surface --surface "$surface" >/dev/null 2>&1 || true

  case "$signal" in
    DONE)
      verify_done "$issue" "$start_head"
      append_progress "DONE issue #$issue: $title"
      rm -f "$context_file"
      ui_success "Done #$issue — $title"
      ;;
    BLOCKED)
      verify_blocked "$issue"
      append_progress "BLOCKED issue #$issue: $title"
      rm -f "$context_file"
      ui_warn "Blocked #$issue — $title"
      ;;
    *)
      append_progress "FAILED issue #$issue: $title (timeout/no signal, context: $context_file)"
      die "Iteration $iteration/$total failed for #$issue — $title (timeout/no signal after ${WUGANG_TIMEOUT_SECONDS}s)"
      ;;
  esac
}
