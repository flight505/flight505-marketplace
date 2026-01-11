#!/bin/bash
# Monitor SDK agent progress and update tracking files
# Can be called periodically to keep handoff-context.json current

set -euo pipefail

# Check if handoff is active
if [ ! -f ".claude/handoff-context.json" ]; then
  echo "No active handoff found"
  exit 1
fi

# Check if SDK agent is still running
if [ -f ".claude/sdk-bridge.pid" ]; then
  PID=$(cat .claude/sdk-bridge.pid)
  if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "SDK agent process stopped"
  fi
fi

# Count sessions from log (matches "--- Session X/Y ---" pattern)
if [ -f ".claude/sdk-bridge.log" ]; then
  SESSION_COUNT=$(grep -c "Session [0-9]*/[0-9]*" .claude/sdk-bridge.log 2>/dev/null || echo 0)
else
  SESSION_COUNT=0
fi

# Get current feature progress
if [ -f "feature_list.json" ]; then
  FEATURES_TOTAL=$(jq 'length' feature_list.json)
  FEATURES_PASSING=$(jq '[.[] | select(.passes==true)] | length' feature_list.json)
else
  FEATURES_TOTAL=0
  FEATURES_PASSING=0
fi

# Update tracking file
TEMP_FILE=$(mktemp)
jq --arg sessions "$SESSION_COUNT" \
   --arg features_total "$FEATURES_TOTAL" \
   --arg features_passing "$FEATURES_PASSING" \
   '.session_count = ($sessions | tonumber) |
    .features_total = ($features_total | tonumber) |
    .features_passing = ($features_passing | tonumber)' \
  .claude/handoff-context.json > "$TEMP_FILE"

mv "$TEMP_FILE" .claude/handoff-context.json

# Check for completion patterns in log
if [ -f ".claude/sdk-bridge.log" ]; then
  # Check for "all features completed" message (matches autonomous_agent.py output)
  if grep -q "All features completed\|all features passing" .claude/sdk-bridge.log 2>/dev/null; then
    if [ ! -f ".claude/sdk_complete.json" ]; then
      # Create completion signal
      cat > .claude/sdk_complete.json << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "reason": "all_features_passing",
  "session_count": $SESSION_COUNT,
  "exit_code": 0,
  "features_completed": $FEATURES_PASSING,
  "features_remaining": $((FEATURES_TOTAL - FEATURES_PASSING))
}
EOF

      # Remove PID file
      rm -f .claude/sdk-bridge.pid

      echo "✅ SDK agent completed - all features passing"
      exit 0
    fi
  fi

  # Check for max iterations reached (matches autonomous_agent.py output)
  if grep -q "Reached maximum iterations\|max iterations reached" .claude/sdk-bridge.log 2>/dev/null; then
    if [ ! -f ".claude/sdk_complete.json" ]; then
      cat > .claude/sdk_complete.json << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "reason": "max_iterations_reached",
  "session_count": $SESSION_COUNT,
  "exit_code": 1,
  "features_completed": $FEATURES_PASSING,
  "features_remaining": $((FEATURES_TOTAL - FEATURES_PASSING))
}
EOF

      rm -f .claude/sdk-bridge.pid

      echo "⚠️  SDK agent stopped - max sessions reached"
      exit 0
    fi
  fi

  # Check for stall pattern (no progress)
  if grep -q "No progress\|stalled\|stuck" .claude/sdk-bridge.log 2>/dev/null; then
    if [ ! -f ".claude/sdk_complete.json" ]; then
      cat > .claude/sdk_complete.json << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "reason": "progress_stalled",
  "session_count": $SESSION_COUNT,
  "exit_code": 2,
  "features_completed": $FEATURES_PASSING,
  "features_remaining": $((FEATURES_TOTAL - FEATURES_PASSING))
}
EOF

      rm -f .claude/sdk-bridge.pid

      echo "⚠️  SDK agent stopped - progress stalled"
      exit 0
    fi
  fi
fi

# Output current status
echo "Progress updated:"
echo "  Sessions: $SESSION_COUNT"
echo "  Features: $FEATURES_PASSING / $FEATURES_TOTAL passing"

exit 0
