#!/usr/bin/env bash
# TaskCreated hook for the build subsystem.
#
# Responsibilities:
#   1. Validate task subject format: [XX-NNN]: Title
#   2. Record the new task in the active build state file
#
# Fires on every TaskCreated event regardless of origin (team hooks do not
# accept matcher or `if` fields — see docs/research/2026-04-primitives.md §2).
# Filters at runtime: exits 0 cleanly if no build state is active.
#
# Exit 0: allow task creation
# Exit 2: block creation, stderr sent as feedback to the creator
set -euo pipefail

# shellcheck source=_lib.sh
source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib.sh"

STATE_FILE=$(find_active_build_state)
[ -n "$STATE_FILE" ] || exit 0  # no active build phase — nothing to do

INPUT=$(cat || echo "")
TASK_SUBJECT=$(printf '%s' "$INPUT" | jq -r '.task_subject // empty' 2>/dev/null || echo "")
TASK_ID=$(printf '%s' "$INPUT" | jq -r '.task_id // empty' 2>/dev/null || echo "")

# Allow tasks without a subject (e.g., tool-created tasks without structured format)
[ -n "$TASK_SUBJECT" ] || exit 0

# Enforce [XX-NNN]: Title naming for team-assigned tasks
if [[ ! "$TASK_SUBJECT" =~ ^\[[A-Z]+-[0-9]+\]:[[:space:]].+ ]]; then
  cat >&2 <<EOF
Task subject must follow format: [XX-NNN]: Title
Example: [US-001]: Add status field
Got: ${TASK_SUBJECT}
EOF
  exit 2
fi

# Record the task in the build state file
if [ -n "$TASK_ID" ]; then
  mutate_state "$STATE_FILE" "
tasks = state.setdefault('output', {}).setdefault('tasks', {})
tasks['${TASK_ID}'] = {
    'subject': ${TASK_SUBJECT@Q},
    'status': 'pending',
}
progress = state.setdefault('progress', {'current': 0, 'total': 0, 'unit': 'stories'})
progress['total'] = max(progress.get('total', 0), len(tasks))
"
fi

exit 0
