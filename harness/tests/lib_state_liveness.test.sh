#!/usr/bin/env bash
# Tests for harness/hooks/_lib.sh::find_active_build_state liveness check.
# A state file is live iff its last_heartbeat (or updated_at fallback) is
# within HARNESS_STALE_THRESHOLD_SECONDS of now.

# shellcheck source=lib/assert.sh
LIB_SH="$HARNESS_REPO_ROOT/harness/hooks/_lib.sh"

# Helper: write a build-*.json with a specific last_heartbeat offset (in
# seconds — negative = past, 0 = now). Echoes the file path.
write_state_with_heartbeat() {
  local dir="$1"
  local name="$2"
  local offset_seconds="$3"
  mkdir -p "$dir"
  local ts
  ts=$(python3 -c "
import datetime
o = ${offset_seconds}
t = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=o)
print(t.isoformat().replace('+00:00','Z'))
")
  local path="$dir/build-${name}.json"
  cat > "$path" <<JSON
{
  "schema_version": "1",
  "phase_id": "${name}",
  "status": "running",
  "started_at": "${ts}",
  "updated_at": "${ts}",
  "last_heartbeat": "${ts}"
}
JSON
  echo "$path"
}

# Helper: write a state file with NO last_heartbeat — only updated_at — to
# verify legacy fallback behavior.
write_state_legacy() {
  local dir="$1"
  local name="$2"
  local offset_seconds="$3"
  mkdir -p "$dir"
  local ts
  ts=$(python3 -c "
import datetime
o = ${offset_seconds}
t = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=o)
print(t.isoformat().replace('+00:00','Z'))
")
  local path="$dir/build-${name}.json"
  cat > "$path" <<JSON
{
  "schema_version": "1",
  "phase_id": "${name}",
  "status": "running",
  "started_at": "${ts}",
  "updated_at": "${ts}"
}
JSON
  echo "$path"
}

# ─── tests ──────────────────────────────────────────────────────────────────

test_returns_empty_when_no_state_dir() {
  # PWD is a fresh tmpdir; no .harness exists.
  source "$LIB_SH"
  local out
  out=$(find_active_build_state)
  assert_empty "$out" "no state dir → empty"
}

test_returns_empty_when_state_dir_is_empty() {
  mkdir -p .harness
  source "$LIB_SH"
  local out
  out=$(find_active_build_state)
  assert_empty "$out" "empty state dir → empty"
}

test_returns_path_for_fresh_state() {
  local file
  file=$(write_state_with_heartbeat .harness fresh -2)  # 2 seconds ago
  source "$LIB_SH"
  local out
  out=$(find_active_build_state)
  assert_eq "$out" "$file" "fresh state returned"
}

test_returns_empty_for_stale_state() {
  write_state_with_heartbeat .harness stale -3600 >/dev/null  # 1 hour ago
  source "$LIB_SH"
  local out
  out=$(find_active_build_state)
  assert_empty "$out" "stale state filtered out"
}

test_threshold_env_var_respected() {
  write_state_with_heartbeat .harness mid -120 >/dev/null  # 2 minutes ago
  source "$LIB_SH"
  # Default threshold (600s) → should be live.
  local out
  out=$(find_active_build_state)
  assert_nonempty "$out" "within default threshold"
  # Explicit threshold of 60s → should be stale.
  out=$(HARNESS_STALE_THRESHOLD_SECONDS=60 find_active_build_state)
  assert_empty "$out" "above tightened threshold filtered"
}

test_legacy_state_uses_updated_at_fallback() {
  local file
  file=$(write_state_legacy .harness legacy -5)  # no last_heartbeat, fresh updated_at
  source "$LIB_SH"
  local out
  out=$(find_active_build_state)
  assert_eq "$out" "$file" "legacy fresh state returned via updated_at"
}

test_legacy_stale_filtered() {
  write_state_legacy .harness ancient -7200 >/dev/null  # 2h ago
  source "$LIB_SH"
  local out
  out=$(find_active_build_state)
  assert_empty "$out" "legacy stale state filtered"
}

test_picks_newest_among_multiple_live() {
  write_state_with_heartbeat .harness older -30 >/dev/null
  sleep 0.1
  local newer
  newer=$(write_state_with_heartbeat .harness newer -1)
  source "$LIB_SH"
  local out
  out=$(find_active_build_state)
  assert_eq "$out" "$newer" "newest live state returned"
}
