#!/bin/bash
# Check if SDK agent completed while user was away
# This hook runs at SessionStart to notify user of completion

set -euo pipefail

# Only check if in project with SDK bridge configuration
if [ ! -f ".claude/sdk-bridge.local.md" ]; then
  exit 0
fi

# Check for completion signal
if [ -f ".claude/sdk_complete.json" ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🎉 SDK Agent Completed!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "The autonomous SDK agent finished while you were away."
  echo ""

  # Quick summary from completion signal
  if [ -f ".claude/sdk_complete.json" ]; then
    REASON=$(jq -r '.reason // "unknown"' .claude/sdk_complete.json 2>/dev/null || echo "unknown")
    SESSIONS=$(jq -r '.session_count // "?"' .claude/sdk_complete.json 2>/dev/null || echo "?")

    echo "  Reason: $REASON"
    echo "  Sessions: $SESSIONS"
    echo ""
  fi

  # Feature progress summary
  if [ -f "feature_list.json" ]; then
    FEATURES_PASSING=$(jq '[.[] | select(.passes==true)] | length' feature_list.json 2>/dev/null || echo "?")
    FEATURES_TOTAL=$(jq 'length' feature_list.json 2>/dev/null || echo "?")

    echo "  Progress: $FEATURES_PASSING / $FEATURES_TOTAL features passing"
    echo ""
  fi

  echo "Review the work and continue:"
  echo "  /sdk-bridge:resume"
  echo ""
fi

# Check for stale PID (process died unexpectedly)
if [ -f ".claude/sdk-bridge.pid" ]; then
  PID=$(cat .claude/sdk-bridge.pid)

  if ! ps -p "$PID" > /dev/null 2>&1; then
    echo ""
    echo "⚠️  SDK Agent Process Stopped"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "The SDK agent process (PID: $PID) has stopped."
    echo ""

    # Check if it was expected (completion signal exists)
    if [ -f ".claude/sdk_complete.json" ]; then
      echo "This appears to be a normal completion."
    else
      echo "This may indicate a crash or unexpected termination."
      echo ""
      echo "Check logs for details:"
      echo "  tail -50 .claude/sdk-bridge.log"
      echo ""
      echo "Check status or resume:"
      echo "  /sdk-bridge:status"
      echo "  /sdk-bridge:resume"
    fi

    echo ""
    rm -f .claude/sdk-bridge.pid
  fi
fi

exit 0
