#!/usr/bin/env bash
# Shared helpers for harness build-subsystem hooks.
# Team hooks (TaskCreated, TaskCompleted, TeammateIdle) cannot be filtered by
# matcher or `if` field — they fire on every team event. These helpers let the
# hook scripts decide at runtime whether a build phase is active and
# which state file to touch.
set -euo pipefail

# Echo the path of the newest *live* build state file in .harness/, or empty.
#
# Liveness: a state file is considered live if its `last_heartbeat` field
# (written by harness/bin/heartbeat.mjs) is within HARNESS_STALE_THRESHOLD_SECONDS
# (default 600s = 10 minutes). State files without a `last_heartbeat` field
# are treated as live ONLY if their `updated_at` falls within the same window
# (legacy compatibility).
#
# This prevents stale state files from a crashed/abandoned session from
# hijacking unrelated subsequent sessions: hook scripts that gate on
# `find_active_build_state` will exit cleanly when no state is fresh.
find_active_build_state() {
  local state_dir="${HARNESS_STATE_DIR:-.harness}"
  local threshold="${HARNESS_STALE_THRESHOLD_SECONDS:-600}"
  [ -d "$state_dir" ] || { echo ""; return; }
  # shellcheck disable=SC2012
  local newest
  newest=$(ls -t "$state_dir"/build-*.json 2>/dev/null | head -1)
  [ -n "$newest" ] || { echo ""; return; }

  # Liveness check via Python (jq not always available; python3 is required
  # elsewhere in these hooks anyway).
  local live
  live=$(python3 - "$newest" "$threshold" <<'PY'
import json, sys, datetime
path, threshold = sys.argv[1], int(sys.argv[2])
try:
    state = json.load(open(path))
except Exception:
    print("0"); sys.exit()
def parse_iso(s):
    if not isinstance(s, str): return None
    s = s.replace("Z", "+00:00")
    try: return datetime.datetime.fromisoformat(s)
    except Exception: return None
ts = parse_iso(state.get("last_heartbeat")) or parse_iso(state.get("updated_at"))
if ts is None:
    # No timestamps at all — treat as live (legacy state files).
    print("1"); sys.exit()
now = datetime.datetime.now(datetime.timezone.utc)
if ts.tzinfo is None: ts = ts.replace(tzinfo=datetime.timezone.utc)
age = (now - ts).total_seconds()
print("1" if age <= threshold else "0")
PY
)
  if [ "$live" = "1" ]; then
    echo "$newest"
  else
    echo ""
  fi
}

# Pretty-print the team_name from the hook stdin payload, or empty if not team.
# Team hook payloads include `team_name` per schema (TeammateIdleHookInput /
# TaskCompletedHookInput).
read_team_name() {
  local payload="$1"
  if [ -z "$payload" ]; then
    echo ""
    return
  fi
  printf '%s' "$payload" | jq -r '.team_name // ""' 2>/dev/null || echo ""
}

# Extract a quality command from a build state file's config.
# Usage: read_quality_cmd <state_file> <key>
read_quality_cmd() {
  local state_file="$1"
  local key="$2"
  [ -f "$state_file" ] || { echo ""; return; }
  python3 - "$state_file" "$key" <<'PY'
import json, sys
try:
    state = json.loads(open(sys.argv[1]).read())
    quality = state.get("config", {}).get("quality", {})
    print(quality.get(sys.argv[2], ""))
except Exception:
    print("")
PY
}

# Atomically update a JSON state file with a Python snippet that modifies the
# `state` dict in place. Writes to a .tmp file and renames for atomicity.
# Usage: mutate_state <state_file> <python-snippet>
mutate_state() {
  local state_file="$1"
  local snippet="$2"
  [ -f "$state_file" ] || return 0
  python3 - "$state_file" <<PY
import json, os, sys, datetime
path = sys.argv[1]
with open(path) as f:
    state = json.load(f)
${snippet}
state["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, path)
PY
}
