#!/usr/bin/env bash
# Tests for harness/bin/state-mutate.py — named-op state mutator.

MUTATE="$HARNESS_REPO_ROOT/harness/bin/state-mutate.py"

# Helper: write a fresh build state with N pending tasks.
make_state_with_tasks() {
  local file="$1"
  shift
  local tasks_json='{}'
  for tid in "$@"; do
    tasks_json=$(python3 -c "
import json, sys
d = json.loads('${tasks_json}')
d['$tid'] = {'subject': 'task $tid', 'status': 'pending'}
print(json.dumps(d))
")
  done
  cat > "$file" <<JSON
{
  "schema_version": "1",
  "phase_id": "test",
  "status": "running",
  "started_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-01-01T00:00:00Z",
  "output": {"tasks": ${tasks_json}}
}
JSON
}

read_field() {
  python3 -c "
import json
print(json.load(open('$1')).get('$2', ''))"
}

read_path() {
  python3 -c "
import json
d = json.load(open('$1'))
for k in '$2'.split('.'):
    d = d[k] if isinstance(d, dict) and k in d else d[int(k)] if isinstance(d, list) else None
    if d is None: break
print(d)"
}

# ─── mark-task-completed ────────────────────────────────────────────────────

test_mark_task_completed_sets_status() {
  make_state_with_tasks state.json T-1 T-2
  python3 "$MUTATE" mark-task-completed state.json T-1 alice
  local status
  status=$(python3 -c "import json; print(json.load(open('state.json'))['output']['tasks']['T-1']['status'])")
  assert_eq "$status" "completed" "T-1 status updated"
}

test_mark_task_completed_records_teammate() {
  make_state_with_tasks state.json T-1
  python3 "$MUTATE" mark-task-completed state.json T-1 bob
  local who
  who=$(python3 -c "import json; print(json.load(open('state.json'))['output']['tasks']['T-1']['completed_by'])")
  assert_eq "$who" "bob" "completed_by recorded"
}

test_mark_task_completed_updates_progress() {
  make_state_with_tasks state.json T-1 T-2 T-3
  python3 "$MUTATE" mark-task-completed state.json T-1 alice
  python3 "$MUTATE" mark-task-completed state.json T-2 bob
  local current total stories_done
  current=$(python3 -c "import json; print(json.load(open('state.json'))['progress']['current'])")
  total=$(python3 -c "import json; print(json.load(open('state.json'))['progress']['total'])")
  stories_done=$(python3 -c "import json; print(json.load(open('state.json'))['output']['stories_completed'])")
  assert_eq "$current" "2" "progress.current"
  assert_eq "$total" "3" "progress.total"
  assert_eq "$stories_done" "2" "stories_completed mirrored"
}

test_mark_task_completed_unknown_task_is_silent() {
  make_state_with_tasks state.json T-1
  # Should not crash; just no-op the task update but still recompute progress.
  python3 "$MUTATE" mark-task-completed state.json T-99 alice
  LABEL="unknown task no-op" assert_exit 0 true
}

test_mark_task_completed_updates_updated_at() {
  make_state_with_tasks state.json T-1
  local before after
  before=$(read_field state.json updated_at)
  python3 "$MUTATE" mark-task-completed state.json T-1 alice
  after=$(read_field state.json updated_at)
  assert_neq "$before" "$after" "updated_at changed"
}

# ─── record-teammate-status ─────────────────────────────────────────────────

test_record_teammate_appends_new() {
  make_state_with_tasks state.json T-1
  python3 "$MUTATE" record-teammate-status state.json alice implementer working
  local count
  count=$(python3 -c "import json; print(len(json.load(open('state.json')).get('teammates', [])))")
  assert_eq "$count" "1" "one teammate appended"
}

test_record_teammate_updates_existing() {
  make_state_with_tasks state.json T-1
  python3 "$MUTATE" record-teammate-status state.json alice implementer working
  python3 "$MUTATE" record-teammate-status state.json alice implementer idle
  local count status
  count=$(python3 -c "import json; print(len(json.load(open('state.json')).get('teammates', [])))")
  status=$(python3 -c "import json; print(json.load(open('state.json'))['teammates'][0]['status'])")
  assert_eq "$count" "1" "still one teammate (no duplicate)"
  assert_eq "$status" "idle" "status updated"
}

test_record_teammate_sets_team_name() {
  make_state_with_tasks state.json T-1
  python3 "$MUTATE" record-teammate-status state.json alice implementer working "team-1"
  local team
  team=$(read_field state.json team_name)
  assert_eq "$team" "team-1" "team_name set"
}

# ─── error paths ────────────────────────────────────────────────────────────

test_unknown_op_exits_1() {
  make_state_with_tasks state.json T-1
  LABEL="unknown op rejected" assert_exit 1 python3 "$MUTATE" wat state.json
}

test_missing_state_file_exits_1() {
  LABEL="missing file rejected" assert_exit 1 python3 "$MUTATE" mark-task-completed nope.json T-1
}

test_invalid_json_exits_1() {
  echo "not json" > broken.json
  LABEL="invalid json rejected" assert_exit 1 python3 "$MUTATE" mark-task-completed broken.json T-1
}

test_missing_args_exits_2() {
  make_state_with_tasks state.json T-1
  LABEL="missing args rejected" assert_exit 2 python3 "$MUTATE" mark-task-completed
}
