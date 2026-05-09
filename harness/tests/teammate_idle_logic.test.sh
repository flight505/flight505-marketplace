#!/usr/bin/env bash
# Tests for the slack-based idle decision in on-teammate-idle.sh.
# Strategy: stage a build state file, set $TEAMMATE/$TEAM env, pipe a hook
# payload to the script, observe exit code (2 = block idle, 0 = allow idle).

HOOK="$HARNESS_REPO_ROOT/harness/hooks/on-teammate-idle.sh"

# Helper: stage a fresh .harness/build-test.json with given tasks + teammates.
# Args: <tasks-spec> <teammates-spec>
#   tasks-spec:     "T-1:pending,T-2:completed,T-3:pending"
#   teammates-spec: "alice:working,bob:idle"
stage_state() {
  local tasks="$1"
  local teammates="$2"
  python3 - <<PY
import json, datetime, os
state = {
    "schema_version": "1",
    "phase_id": "test",
    "status": "running",
    "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "last_heartbeat": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "config": {"branch": "feat/test", "quality": {}},
    "output": {"tasks": {}},
    "teammates": [],
}
for entry in "${tasks}".split(","):
    if not entry: continue
    tid, status = entry.split(":")
    state["output"]["tasks"][tid] = {"subject": tid, "status": status}
for entry in "${teammates}".split(","):
    if not entry: continue
    name, status = entry.split(":")
    state["teammates"].append({"name": name, "agent_type": "implementer", "status": status, "tasks_completed": 0})
os.makedirs(".harness", exist_ok=True)
with open(".harness/build-test.json", "w") as f:
    json.dump(state, f)
PY
}

invoke_hook() {
  local me="$1"
  local payload="{\"team_name\":\"team-1\",\"teammate_name\":\"${me}\"}"
  echo "$payload" | CLAUDE_PLUGIN_ROOT="$HARNESS_REPO_ROOT/harness" \
    bash "$HOOK" >/tmp/h-stdout-$$ 2>/tmp/h-stderr-$$
  local rc=$?
  rm -f /tmp/h-stdout-$$ /tmp/h-stderr-$$
  return $rc
}

# ─── tests ──────────────────────────────────────────────────────────────────

test_no_state_file_exits_0() {
  # Empty .harness or missing — find_active_build_state returns empty.
  invoke_hook alice
  assert_eq "$?" "0" "no state → exit 0"
}

test_blocks_idle_when_pending_unclaimed() {
  # 2 pending tasks, only 1 other teammate working → slack = 1 → block idle.
  stage_state "T-1:pending,T-2:pending" "bob:working"
  invoke_hook alice
  assert_eq "$?" "2" "pending unclaimed → block (exit 2)"
}

test_allows_idle_when_all_pending_in_flight() {
  # 2 pending tasks, 2 OTHER teammates working → slack = 0 → allow idle.
  stage_state "T-1:pending,T-2:pending" "bob:working,carol:working"
  invoke_hook alice
  assert_eq "$?" "0" "all pending in flight → allow idle"
}

test_allows_idle_when_all_completed() {
  stage_state "T-1:completed,T-2:completed" "bob:idle,carol:idle"
  invoke_hook alice
  assert_eq "$?" "0" "all complete → allow idle"
}

test_blocks_idle_when_more_pending_than_workers() {
  stage_state "T-1:pending,T-2:pending,T-3:pending" "bob:working"
  invoke_hook alice
  assert_eq "$?" "2" "3 pending vs 1 worker → block"
}

# ─── add-task op tests ──────────────────────────────────────────────────────

test_add_task_creates_entry() {
  local MUTATE="$HARNESS_REPO_ROOT/harness/bin/state-mutate.py"
  cat > state.json <<JSON
{"schema_version":"1","phase_id":"t","status":"running","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
JSON
  python3 "$MUTATE" add-task state.json "T-001" "[US-001]: Add status field"
  local subject status total
  subject=$(python3 -c "import json; print(json.load(open('state.json'))['output']['tasks']['T-001']['subject'])")
  status=$(python3 -c "import json; print(json.load(open('state.json'))['output']['tasks']['T-001']['status'])")
  total=$(python3 -c "import json; print(json.load(open('state.json'))['progress']['total'])")
  assert_eq "$subject" "[US-001]: Add status field" "subject preserved"
  assert_eq "$status" "pending" "starts pending"
  assert_eq "$total" "1" "progress.total updated"
}

test_add_task_increments_total_monotonically() {
  local MUTATE="$HARNESS_REPO_ROOT/harness/bin/state-mutate.py"
  cat > state.json <<JSON
{"schema_version":"1","phase_id":"t","status":"running","started_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
JSON
  python3 "$MUTATE" add-task state.json "T-1" "first"
  python3 "$MUTATE" add-task state.json "T-2" "second"
  python3 "$MUTATE" add-task state.json "T-3" "third"
  local total
  total=$(python3 -c "import json; print(json.load(open('state.json'))['progress']['total'])")
  assert_eq "$total" "3" "total tracks task count"
}
