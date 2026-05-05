#!/usr/bin/env bash
# Launch the harness dashboard in the background
# Usage: launch-dashboard.sh [harness_state_dir]
#
# - Starts Next.js dev server pointed at the state directory
# - Skips if already running (checks port 3000)
# - Opens browser automatically
# - Runs in background, logs to /tmp/harness-dashboard.log

set -euo pipefail

HARNESS_STATE_DIR="${1:-$(pwd)/.harness}"
DASHBOARD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="/tmp/harness-dashboard.log"
PID_FILE="/tmp/harness-dashboard.pid"

# Check if already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[dashboard] Already running (PID $OLD_PID) at http://localhost:3000"
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

# Check if port 3000 is in use
if lsof -i :3000 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[dashboard] Port 3000 already in use — dashboard may be running"
    exit 0
fi

# Check dependencies
if [ ! -d "$DASHBOARD_DIR/node_modules" ]; then
    echo "[dashboard] Installing dependencies..."
    (cd "$DASHBOARD_DIR" && pnpm install --silent 2>&1) || {
        echo "[dashboard] WARNING: Failed to install dependencies. Skipping dashboard." >&2
        exit 0
    }
fi

# Start in background
echo "[dashboard] Starting at http://localhost:3000"
echo "[dashboard] State dir: $HARNESS_STATE_DIR"
echo "[dashboard] Logs: $LOG_FILE"

HARNESS_STATE_DIR="$HARNESS_STATE_DIR" \
    nohup pnpm --dir "$DASHBOARD_DIR" dev > "$LOG_FILE" 2>&1 &

DASH_PID=$!
echo "$DASH_PID" > "$PID_FILE"

# Start heartbeat daemon (updates elapsed_seconds in running state files)
HEARTBEAT_PID_FILE="/tmp/harness-heartbeat.pid"
if [ -f "$HEARTBEAT_PID_FILE" ]; then
    OLD_HB=$(cat "$HEARTBEAT_PID_FILE")
    kill "$OLD_HB" 2>/dev/null || true
    rm -f "$HEARTBEAT_PID_FILE"
fi

nohup node "$DASHBOARD_DIR/scripts/heartbeat.mjs" "$HARNESS_STATE_DIR" > /tmp/harness-heartbeat.log 2>&1 &
HB_PID=$!
echo "$HB_PID" > "$HEARTBEAT_PID_FILE"
echo "[heartbeat] Started (PID $HB_PID)"

# Wait briefly for startup
sleep 3

if kill -0 "$DASH_PID" 2>/dev/null; then
    echo "[dashboard] Running (PID $DASH_PID)"
    # Open browser
    if command -v open >/dev/null 2>&1; then
        open "http://localhost:3000" 2>/dev/null || true
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "http://localhost:3000" 2>/dev/null || true
    fi
else
    echo "[dashboard] WARNING: Failed to start. Check $LOG_FILE" >&2
    rm -f "$PID_FILE"
fi
