#!/usr/bin/env bash
# TeammateIdle hook for the build subsystem.
#
# Responsibilities:
#   1. Prevent teammates from going idle while tasks remain unclaimed or
#      in progress. Returns exit 2 with a nudge so the teammate keeps working.
#   2. Update the teammates[] array in the active build state file with the
#      current teammate's status so the dashboard reflects live team shape.
#
# Fires on every TeammateIdle event. Exits 0 if no build phase active.
#
# Exit 0: allow teammate to go idle (all work done or no active build)
# Exit 2: prevent idle, stderr sent as feedback to the teammate
set -euo pipefail

# shellcheck source=_lib.sh
source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib.sh"

STATE_FILE=$(find_active_build_state)
[ -n "$STATE_FILE" ] || exit 0

INPUT=$(cat || echo "")
TEAMMATE=$(printf '%s' "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null || echo "")
TEAM=$(printf '%s' "$INPUT" | jq -r '.team_name // empty' 2>/dev/null || echo "")

# Compute remaining work from the state file
REMAINING=$(python3 - "$STATE_FILE" <<'PY'
import json, sys
try:
    state = json.loads(open(sys.argv[1]).read())
    tasks = state.get("output", {}).get("tasks", {})
    remaining = sum(1 for t in tasks.values() if t.get("status") != "completed")
    print(remaining)
except Exception:
    print(0)
PY
)

# Record this teammate's status before deciding
if [ -n "$TEAMMATE" ]; then
  STATUS="idle"
  [ "$REMAINING" -gt 0 ] && STATUS="working"
  mutate_state "$STATE_FILE" "
teammates = state.setdefault('teammates', [])
found = False
for m in teammates:
    if m.get('name') == ${TEAMMATE@Q}:
        m['status'] = ${STATUS@Q}
        found = True
        break
if not found:
    teammates.append({
        'name': ${TEAMMATE@Q},
        'agent_type': 'implementer',
        'status': ${STATUS@Q},
        'tasks_completed': 0,
    })
if ${TEAM@Q}:
    state['team_name'] = ${TEAM@Q}
"
fi

# Block idle only if work remains
if [ "$REMAINING" -gt 0 ]; then
  echo "There are still ${REMAINING} incomplete tasks. Run TaskList, claim an unblocked task, and keep working." >&2
  exit 2
fi

exit 0
