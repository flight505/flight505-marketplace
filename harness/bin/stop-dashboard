#!/usr/bin/env bash
# Stop the harness dashboard
set -euo pipefail

PID_FILE="/tmp/harness-dashboard.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "[dashboard] Not running (no PID file)"
    exit 0
fi

PID=$(cat "$PID_FILE")
if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    sleep 1
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
    echo "[dashboard] Stopped (PID $PID)"
else
    echo "[dashboard] Process $PID already gone"
fi

rm -f "$PID_FILE"

# Also stop heartbeat
HEARTBEAT_PID_FILE="/tmp/harness-heartbeat.pid"
if [ -f "$HEARTBEAT_PID_FILE" ]; then
    HB_PID=$(cat "$HEARTBEAT_PID_FILE")
    if kill -0 "$HB_PID" 2>/dev/null; then
        kill "$HB_PID" 2>/dev/null
        echo "[heartbeat] Stopped (PID $HB_PID)"
    fi
    rm -f "$HEARTBEAT_PID_FILE"
fi
