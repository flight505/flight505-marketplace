---
description: "Stop running SDK agent"
argument-hint: ""
allowed-tools: ["Bash", "Read", "Write"]
---

# Cancel Running SDK Agent

I'll help you stop the currently running SDK agent.

## Warning

⚠️  **Warning**: This will interrupt autonomous work in progress. The SDK agent's progress will be saved, but the current feature implementation may be incomplete.

## Check if SDK Agent is Running

```bash
PID_FILE=".claude/sdk-bridge.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "❌ No SDK agent is currently running"
  echo ""
  echo "Status:"
  echo "  • No PID file found at .claude/sdk-bridge.pid"
  echo ""
  echo "To start an SDK agent: /sdk-bridge:handoff"
  exit 0
fi

PID=$(cat "$PID_FILE")

if ! ps -p "$PID" > /dev/null 2>&1; then
  echo "⚠️  SDK agent process not found"
  echo ""
  echo "The PID file exists but process $PID is not running."
  echo "This likely means the agent already stopped."
  echo ""
  echo "Cleaning up stale files..."
  rm -f "$PID_FILE"
  echo ""
  echo "Check status with: /sdk-bridge:status"
  exit 0
fi

echo "Found running SDK agent:"
echo "  PID: $PID"
echo ""

# Show current progress
if [ -f "feature_list.json" ]; then
  FEATURES_TOTAL=$(jq 'length' feature_list.json 2>/dev/null || echo "?")
  FEATURES_PASSING=$(jq '[.[] | select(.passes==true)] | length' feature_list.json 2>/dev/null || echo "?")
  echo "  Progress: $FEATURES_PASSING / $FEATURES_TOTAL features passing"
fi

if [ -f ".claude/handoff-context.json" ]; then
  SESSIONS=$(jq -r '.session_count // 0' .claude/handoff-context.json 2>/dev/null || echo "?")
  MAX_SESSIONS=$(jq -r '.max_sessions // 20' .claude/handoff-context.json 2>/dev/null || echo "20")
  echo "  Sessions: $SESSIONS / $MAX_SESSIONS"
fi

echo ""
```

## Confirmation

Use the AskUserQuestion tool to confirm:

```
Are you sure you want to cancel the running SDK agent?

Options:
- "Yes, cancel it" - Stop the agent immediately
- "No, let it continue" - Keep the agent running
```

If user confirms cancellation, proceed. Otherwise, exit.

## Stop the SDK Agent

```bash
echo "Stopping SDK agent (PID: $PID)..."
echo ""

# Try graceful shutdown first (SIGTERM)
echo "Attempting graceful shutdown..."
kill -TERM "$PID" 2>/dev/null || {
  echo "⚠️  Failed to send TERM signal"
  echo "Process may have already stopped."
}

# Wait up to 10 seconds for graceful shutdown
WAITED=0
while [ $WAITED -lt 10 ]; do
  if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "✅ SDK agent stopped gracefully"
    STOPPED=true
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
  echo "  Waiting... ($WAITED/10)"
done

# Force kill if still running
if [ "${STOPPED:-false}" != "true" ]; then
  if ps -p "$PID" > /dev/null 2>&1; then
    echo ""
    echo "Agent didn't stop gracefully, forcing..."
    kill -KILL "$PID" 2>/dev/null
    sleep 1

    if ! ps -p "$PID" > /dev/null 2>&1; then
      echo "✅ SDK agent force stopped"
    else
      echo "❌ Failed to stop SDK agent"
      echo "   You may need to stop it manually: kill -9 $PID"
      exit 1
    fi
  fi
fi

# Clean up PID file
rm -f "$PID_FILE"
echo ""
```

## Report Current State

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SDK Agent Cancelled"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show what was saved
echo "Progress saved to:"
echo "  • .claude/handoff-context.json - Handoff state"
echo "  • claude-progress.txt - Session logs"
echo "  • feature_list.json - Feature completion status"
echo "  • .claude/sdk-bridge.log - Execution logs"
echo ""

# Show current feature status
if [ -f "feature_list.json" ]; then
  FEATURES_TOTAL=$(jq 'length' feature_list.json)
  FEATURES_PASSING=$(jq '[.[] | select(.passes==true)] | length' feature_list.json)
  FEATURES_REMAINING=$((FEATURES_TOTAL - FEATURES_PASSING))

  echo "Current Progress:"
  echo "  ✅ Completed: $FEATURES_PASSING features"
  echo "  ❌ Remaining: $FEATURES_REMAINING features"
  echo ""
fi

# Check git state
if git diff-index --quiet HEAD -- 2>/dev/null; then
  echo "Git: Working tree is clean"
else
  echo "Git: Uncommitted changes present"
  echo "     The agent may have been mid-implementation"
fi

echo ""
echo "Next Steps:"
echo ""
echo "  Review what was completed:"
echo "    git log --oneline -10"
echo "    cat claude-progress.txt"
echo ""
echo "  Check logs for issues:"
echo "    tail -50 .claude/sdk-bridge.log"
echo ""
echo "  Options:"
echo "    • Review and commit incomplete work"
echo "    • Revert uncommitted changes: git reset --hard"
echo "    • Hand off again: /sdk-bridge:handoff"
echo "    • Continue manually in CLI"
echo ""
```

## Important Notes

- **Progress is preserved**: All completed features are saved in feature_list.json
- **Git commits remain**: Completed feature commits are permanent
- **Current work may be incomplete**: The feature being implemented when cancelled may be partial
- **Can resume later**: You can hand off again with `/sdk-bridge:handoff` after review
- **Logs are kept**: Full execution logs remain in `.claude/sdk-bridge.log` for debugging
