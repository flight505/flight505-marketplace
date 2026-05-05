#!/usr/bin/env bash
# PreCompact hook for the optimize subsystem.
#
# Fires before context compaction (manual via /compact or auto when context
# fills). Writes a structured preservation summary to stdout so the optimizer's
# critical state (baseline, best so far, last few experiments) survives the
# compaction summary. Tells the post-compaction agent to re-read the full state
# file before proceeding.
#
# Hook payload on stdin:
#   { "hook_event_name": "PreCompact", "trigger": "manual"|"auto", ... }
#
# Decision control: none (PreCompact has no decision control). Output to stdout
# is included in the transcript before compaction; output to stderr is logged.
#
# Exits 0 always — PreCompact failure must not block compaction.
set -euo pipefail

STATE_DIR=".harness"
[ -d "$STATE_DIR" ] || exit 0

# Find the most recent active optimizer state file
LATEST=""
for f in "$STATE_DIR"/optimize-*.json; do
  [ -f "$f" ] || continue
  if [ -z "$LATEST" ] || [ "$f" -nt "$LATEST" ]; then
    LATEST="$f"
  fi
done
[ -n "$LATEST" ] || exit 0

python3 - "$LATEST" <<'PY' || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        state = json.load(f)
except Exception:
    sys.exit(0)

if state.get("status") not in ("running", "pending"):
    sys.exit(0)  # not active, nothing to preserve

metric = state.get("metric", {}) or {}
progress = state.get("progress", {}) or {}
history = metric.get("history", []) or []
config = state.get("config", {}) or {}

direction = metric.get("direction", "lower")
better_word = "lower" if direction == "lower" else "higher"

print("[harness optimize] PreCompact preservation — read this on resume:")
print(f"  state_file: {sys.argv[1]}")
print(f"  run_id:     {state.get('run_id')}")
print(f"  status:     {state.get('status')}")
print(f"  artifact:   {config.get('artifact', '?')}")
print(f"  target:     {config.get('target', 'local')}")
print(f"  metric:     {metric.get('name')} ({better_word} is better)")
print(f"  baseline:   {metric.get('baseline')}")
print(f"  current:    {metric.get('current')}")
print(f"  best:       {metric.get('best')}")
print(f"  progress:   {progress.get('current', 0)}/{progress.get('total', 0)} experiments")

if history:
    print(f"  recent experiments (last 5):")
    for h in history[-5:]:
        desc = (h.get("description") or "")[:60]
        print(f"    #{h.get('experiment')} {h.get('status')}: {h.get('value')} — {desc}")

print("")
print(f"AFTER COMPACTION: re-read {sys.argv[1]} for full history before continuing the loop.")
print(f"Do not re-run kept experiments; pick up from experiment #{progress.get('current', 0) + 1}.")
PY

exit 0
