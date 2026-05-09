#!/usr/bin/env bash
# TaskCompleted hook for the build subsystem.
#
# Responsibilities:
#   1. Run quality gate commands (typecheck, build, tests) from state config.
#      If any fail, block completion with exit 2 so the teammate fixes and retries.
#   2. Record completion in the active build state file: increment progress,
#      mark the task, update updated_at so the dashboard picks it up.
#
# Fires on every TaskCompleted event. Team hooks cannot be filtered at
# registration time — exits 0 cleanly if no build state is active.
#
# Exit 0: allow task completion
# Exit 2: block completion, stderr sent as feedback
set -euo pipefail

# shellcheck source=_lib.sh
source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib.sh"

STATE_FILE=$(find_active_build_state)
[ -n "$STATE_FILE" ] || exit 0

INPUT=$(cat || echo "")
TASK_SUBJECT=$(printf '%s' "$INPUT" | jq -r '.task_subject // empty' 2>/dev/null || echo "unknown")
TASK_ID=$(printf '%s' "$INPUT" | jq -r '.task_id // empty' 2>/dev/null || echo "")
TEAMMATE=$(printf '%s' "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null || echo "")

# --- Step 1: quality gates ---
TYPECHECK_CMD=$(read_quality_cmd "$STATE_FILE" typecheck)
BUILD_CMD=$(read_quality_cmd "$STATE_FILE" build)
TEST_CMD=$(read_quality_cmd "$STATE_FILE" test)

FAILURES=""

run_gate() {
  local label="$1"
  local cmd="$2"
  [ -n "$cmd" ] || return 0
  # Defense-in-depth: validate the command before executing. workflow.yaml
  # controls these strings, so an unvetted yaml could otherwise run anything.
  if ! is_safe_quality_command "$cmd" 2>/tmp/harness-gate-rejection-$$; then
    local reason
    reason=$(cat /tmp/harness-gate-rejection-$$ 2>/dev/null)
    rm -f /tmp/harness-gate-rejection-$$
    FAILURES+="[${label}] command rejected by allowlist:"$'\n'"  ${reason}"$'\n'"  command: ${cmd}"$'\n\n'
    return 0
  fi
  if ! OUTPUT=$(bash -c -- "$cmd" 2>&1); then
    FAILURES+="[${label}] failed:"$'\n'"${OUTPUT}"$'\n\n'
  fi
}

run_gate "typecheck" "$TYPECHECK_CMD"
run_gate "build" "$BUILD_CMD"
run_gate "tests" "$TEST_CMD"

if [ -n "$FAILURES" ]; then
  # Truncate to keep feedback readable
  printf 'Quality gates failed for %s — fix and retry:\n\n%s\n' \
    "${TASK_SUBJECT}" "${FAILURES}" \
    | head -c 4000 >&2
  exit 2
fi

# --- Step 2: record completion in state file ---
if [ -n "$TASK_ID" ]; then
  mutate_state "$STATE_FILE" "
output = state.setdefault('output', {})
tasks = output.setdefault('tasks', {})
if '${TASK_ID}' in tasks:
    tasks['${TASK_ID}']['status'] = 'completed'
    tasks['${TASK_ID}']['completed_by'] = ${TEAMMATE@Q} or None
completed = sum(1 for t in tasks.values() if t.get('status') == 'completed')
progress = state.setdefault('progress', {'current': 0, 'total': len(tasks), 'unit': 'stories'})
progress['current'] = completed
if progress.get('total', 0) == 0:
    progress['total'] = len(tasks)
output['stories_completed'] = completed
output['stories_total'] = progress['total']
"
fi

exit 0
