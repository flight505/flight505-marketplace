---
description: "Check SDK agent progress"
argument-hint: ""
allowed-tools: ["Bash", "Read"]
---

# Check SDK Agent Status

Let me check the current status of the SDK agent.

## Check Process Status

```bash
PID_FILE=".claude/sdk-bridge.pid"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if ps -p $PID > /dev/null 2>&1; then
    echo "✅ SDK agent is running (PID: $PID)"
    RUNNING=true
  else
    echo "⚠️  SDK agent process not found (PID file is stale)"
    echo "   The process may have crashed or completed."
    RUNNING=false
  fi
else
  echo "❌ No active SDK agent"
  echo ""
  echo "To start an SDK agent, run: /sdk-bridge:handoff"
  RUNNING=false
fi

echo ""
```

## Parse Progress from State Files

```bash
if [ -f ".claude/handoff-context.json" ]; then
  echo "Handoff Context:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Read handoff context
  TIMESTAMP=$(jq -r '.timestamp' .claude/handoff-context.json)
  GIT_COMMIT=$(jq -r '.git_commit' .claude/handoff-context.json)
  MODEL=$(jq -r '.model' .claude/handoff-context.json)
  MAX_SESSIONS=$(jq -r '.max_sessions' .claude/handoff-context.json)

  echo "  Started: $TIMESTAMP"
  echo "  Model: $MODEL"
  echo "  Git commit at handoff: ${GIT_COMMIT:0:8}"
  echo ""
fi

# Parse current feature progress
if [ -f "feature_list.json" ]; then
  FEATURES_TOTAL=$(jq 'length' feature_list.json)
  FEATURES_PASSING=$(jq '[.[] | select(.passes==true)] | length' feature_list.json)
  FEATURES_REMAINING=$((FEATURES_TOTAL - FEATURES_PASSING))
  COMPLETION_PCT=$((FEATURES_PASSING * 100 / FEATURES_TOTAL))

  echo "Feature Progress:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Total features: $FEATURES_TOTAL"
  echo "  ✅ Passing: $FEATURES_PASSING"
  echo "  ❌ Remaining: $FEATURES_REMAINING"
  echo "  📊 Completion: $COMPLETION_PCT%"
  echo ""

  # Show progress bar
  FILLED=$((COMPLETION_PCT / 5))
  EMPTY=$((20 - FILLED))
  printf "  ["
  for i in $(seq 1 $FILLED); do printf "█"; done
  for i in $(seq 1 $EMPTY); do printf "░"; done
  printf "] $COMPLETION_PCT%%\n"
  echo ""
fi

# Estimate session count from log
if [ -f ".claude/sdk-bridge.log" ]; then
  # Count "Iteration" or "Session" mentions in log
  SESSION_COUNT=$(grep -c "Iteration" .claude/sdk-bridge.log 2>/dev/null || echo 0)

  if [ "$SESSION_COUNT" -gt 0 ]; then
    echo "Sessions:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Completed: $SESSION_COUNT"
    if [ -n "$MAX_SESSIONS" ]; then
      echo "  Max allowed: $MAX_SESSIONS"
      SESSIONS_REMAINING=$((MAX_SESSIONS - SESSION_COUNT))
      echo "  Remaining: $SESSIONS_REMAINING"
    fi
    echo ""
  fi
fi
```

## Show Recent Activity

```bash
if [ -f ".claude/sdk-bridge.log" ]; then
  echo "Recent Activity (last 10 lines):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  tail -10 .claude/sdk-bridge.log | sed 's/^/  /'
  echo ""
fi
```

## Check for Completion Signal

```bash
if [ -f ".claude/sdk_complete.json" ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🎉 SDK Agent Completed!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  REASON=$(jq -r '.reason' .claude/sdk_complete.json 2>/dev/null || echo "unknown")
  FINAL_SESSIONS=$(jq -r '.session_count' .claude/sdk_complete.json 2>/dev/null || echo "?")

  echo "Completion reason: $REASON"
  echo "Total sessions: $FINAL_SESSIONS"
  echo ""
  echo "Review the work and continue in CLI:"
  echo "  /sdk-bridge:resume"
  echo ""
fi
```

## Summary

```bash
if [ "$RUNNING" = true ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Next Steps:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  • Check again: /sdk-bridge:status"
  echo "  • View live logs: tail -f .claude/sdk-bridge.log"
  echo "  • Cancel: /sdk-bridge:cancel"
  echo ""
elif [ -f ".claude/sdk_complete.json" ]; then
  echo "The SDK agent has finished. Resume to review its work:"
  echo "  /sdk-bridge:resume"
  echo ""
else
  echo "To start an SDK agent:"
  echo "  /sdk-bridge:handoff"
  echo ""
fi
```
