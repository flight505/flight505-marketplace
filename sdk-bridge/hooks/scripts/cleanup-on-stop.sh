#!/bin/bash
# Cleanup hook when CLI session stops
# SDK agent should keep running, but we update tracking

set -euo pipefail

# Only act if SDK bridge is configured
if [ ! -f ".claude/sdk-bridge.local.md" ]; then
  exit 0
fi

# Check if SDK agent is running
if [ -f ".claude/sdk-bridge.pid" ]; then
  PID=$(cat .claude/sdk-bridge.pid)

  if ps -p "$PID" > /dev/null 2>&1; then
    # SDK agent is still running - this is expected
    # Just log that CLI session is ending but agent continues

    # Optional: Could append to a session log
    if [ -f ".claude/sdk-bridge.log" ]; then
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] CLI session ended, SDK agent continues (PID: $PID)" >> .claude/sdk-bridge.log 2>/dev/null || true
    fi

    # Inform user (this goes to stderr so it appears in CLI output)
    echo "" >&2
    echo "SDK agent continues running in background (PID: $PID)" >&2
    echo "Monitor anytime with: /sdk-bridge:status" >&2
  else
    # Process already stopped - clean up PID file
    rm -f .claude/sdk-bridge.pid
  fi
fi

exit 0
