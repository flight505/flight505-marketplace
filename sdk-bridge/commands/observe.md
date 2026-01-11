---
description: "Real-time dashboard for monitoring parallel execution progress"
argument-hint: ""
allowed-tools: ["Bash", "Read"]
---

# SDK Bridge Real-Time Dashboard

Monitor parallel execution progress in real-time.

## Step 1: Check for Active Workers

```bash
#!/bin/bash
set -euo pipefail

WORKERS_FILE=".claude/worker-sessions.json"

if [ ! -f "$WORKERS_FILE" ]; then
  echo "❌ No active workers found"
  echo ""
  echo "Start parallel execution with:"
  echo "  /sdk-bridge:handoff"
  exit 0
fi

# Count active workers
ACTIVE_COUNT=$(jq '.active_workers | length' "$WORKERS_FILE" 2>/dev/null || echo "0")

if [ "$ACTIVE_COUNT" -eq 0 ]; then
  echo "✅ No active workers (execution complete or not started)"
  exit 0
fi

echo "📊 SDK Bridge Live Dashboard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
```

## Step 2: Display Worker Status

```bash
# Display each active worker
jq -r '
.active_workers | to_entries[] |
"Worker: \(.key)
  Feature: \(.value.feature_id)
  Branch: \(.value.git_branch)
  Model: \(.value.model)
  Status: \(.value.status)
  Session: \(.value.current_session)/\(.value.max_sessions)
  Started: \(.value.started_at)
  Last Update: \(.value.last_heartbeat)
  Message: \(.value.result_message)
  "
' "$WORKERS_FILE"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

## Step 3: Show Overall Progress

```bash
# Check if execution plan exists
if [ -f ".claude/execution-plan.json" ]; then
  TOTAL_FEATURES=$(jq '.metadata.total_features' .claude/execution-plan.json)

  # Count completed from worker sessions
  COMPLETED=$(jq '.completed_workers | length' "$WORKERS_FILE")

  # Calculate progress percentage
  if [ "$TOTAL_FEATURES" -gt 0 ]; then
    PROGRESS=$((COMPLETED * 100 / TOTAL_FEATURES))
    echo ""
    echo "📈 Overall Progress: $COMPLETED/$TOTAL_FEATURES features ($PROGRESS%)"

    # ASCII progress bar
    BAR_LENGTH=40
    FILLED=$((PROGRESS * BAR_LENGTH / 100))
    EMPTY=$((BAR_LENGTH - FILLED))

    printf "["
    for i in $(seq 1 $FILLED); do printf "█"; done
    for i in $(seq 1 $EMPTY); do printf "░"; done
    printf "] $PROGRESS%%\n"

    echo ""
  fi
fi
```

## Step 4: Show Recent Log Activity

```bash
# Show last 10 lines of log
if [ -f ".claude/sdk-bridge.log" ]; then
  echo "📝 Recent Activity:"
  echo ""
  tail -n 10 .claude/sdk-bridge.log | sed 's/^/  /'
  echo ""
fi
```

## Step 5: Continuous Monitoring Mode

Offer option to watch continuously:

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Options:"
echo "  • Refresh: /sdk-bridge:observe"
echo "  • Live logs: tail -f .claude/sdk-bridge.log"
echo "  • Check status: /sdk-bridge:status"
echo "  • Cancel: /sdk-bridge:cancel"
echo ""
```

## Example Output

```
📊 SDK Bridge Live Dashboard
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Worker: worker-1
  Feature: feat-002
  Branch: sdk-bridge/parallel/feat-002
  Model: claude-sonnet-4-5-20250929
  Status: running
  Session: 2/5
  Started: 2026-01-10T19:30:00Z
  Last Update: 2026-01-10T19:32:15Z
  Message: Implementing JWT middleware

Worker: worker-2
  Feature: feat-004
  Branch: sdk-bridge/parallel/feat-004
  Model: claude-sonnet-4-5-20250929
  Status: running
  Session: 1/5
  Started: 2026-01-10T19:30:05Z
  Last Update: 2026-01-10T19:31:45Z
  Message: Creating database schema

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📈 Overall Progress: 3/7 features (42%)
[████████████████░░░░░░░░░░░░░░░░░░░░░░░░] 42%

📝 Recent Activity:
  2026-01-10 19:32:15 - Worker worker-1 executing session 2
  2026-01-10 19:32:10 - Feature feat-002: Added JWT validation
  2026-01-10 19:31:50 - Worker worker-2 executing session 1
  2026-01-10 19:31:45 - Feature feat-004: Created users table
  2026-01-10 19:30:30 - Worker worker-1 completed session 1
  2026-01-10 19:30:00 - Starting parallel execution level 1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💡 Options:
  • Refresh: /sdk-bridge:observe
  • Live logs: tail -f .claude/sdk-bridge.log
  • Check status: /sdk-bridge:status
  • Cancel: /sdk-bridge:cancel
```

## Notes

- Updates show current worker status from worker-sessions.json
- Progress calculated from execution plan
- Shows recent log activity for context
- Use `tail -f .claude/sdk-bridge.log` for continuous monitoring
- Refreshing the command shows updated status
