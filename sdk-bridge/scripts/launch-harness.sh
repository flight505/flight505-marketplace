#!/bin/bash
# Launch autonomous_agent.py in background with proper process management

set -euo pipefail

# Configuration
HARNESS="$HOME/.claude/skills/long-running-agent/harness/autonomous_agent.py"
PYTHON="$HOME/.claude/skills/long-running-agent/.venv/bin/python"
PROJECT_DIR="${1:-.}"
LOG_FILE=".claude/sdk-bridge.log"
PID_FILE=".claude/sdk-bridge.pid"

# Create .claude directory
mkdir -p .claude

# Read configuration from .claude/sdk-bridge.local.md
if [ -f ".claude/sdk-bridge.local.md" ]; then
  FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' .claude/sdk-bridge.local.md)
  MODEL=$(echo "$FRONTMATTER" | grep '^model:' | sed 's/model: *//')
  MAX_SESSIONS=$(echo "$FRONTMATTER" | grep '^max_sessions:' | sed 's/max_sessions: *//')
fi

# Apply defaults if values are empty
MODEL="${MODEL:-claude-sonnet-4-5-20250929}"
MAX_SESSIONS="${MAX_SESSIONS:-20}"

# Calculate max iterations (sessions - reserve)
RESERVE_SESSIONS=2
MAX_ITERATIONS=$((MAX_SESSIONS - RESERVE_SESSIONS))

# Display launch information
echo "Launching SDK agent..."
echo ""
echo "Configuration:"
echo "  • Project: $PROJECT_DIR"
echo "  • Model: $MODEL"
echo "  • Max sessions: $MAX_SESSIONS (reserve: $RESERVE_SESSIONS)"
echo "  • Max iterations: $MAX_ITERATIONS"
echo ""
echo "Logs will be written to: $LOG_FILE"
echo ""

# Launch harness in background
# Use nohup to detach from terminal, redirect output to log file
nohup "$PYTHON" "$HARNESS" \
  --project-dir "$PROJECT_DIR" \
  --model "$MODEL" \
  --max-iterations "$MAX_ITERATIONS" \
  > "$LOG_FILE" 2>&1 &

# Save PID
PID=$!
echo $PID > "$PID_FILE"

# Give it a moment to fail fast if there's an issue
sleep 2

# Check if still running
if ! ps -p $PID > /dev/null 2>&1; then
  echo "❌ Failed to start SDK agent"
  echo ""
  echo "Check logs for details:"
  tail -20 "$LOG_FILE"
  rm -f "$PID_FILE"
  exit 1
fi

echo "✅ SDK agent started successfully"
echo ""
echo "Process ID: $PID"
echo "Status: Running"
echo ""

# Initialize tracking file
cat > .claude/handoff-context.json << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'none')",
  "features_total": $(jq 'length' feature_list.json 2>/dev/null || echo 0),
  "features_passing": $(jq '[.[] | select(.passes==true)] | length' feature_list.json 2>/dev/null || echo 0),
  "session_count": 0,
  "pid": $PID,
  "model": "$MODEL",
  "max_sessions": $MAX_SESSIONS,
  "status": "running"
}
EOF

echo "Tracking file created: .claude/handoff-context.json"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SDK Agent Is Now Running Autonomously"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The SDK agent is working on your features in the background."
echo "You can close this CLI session - the agent will continue running."
echo ""
echo "Monitor progress:"
echo "  /sdk-bridge:status       - Check current state"
echo "  tail -f $LOG_FILE  - Live logs"
echo ""
echo "When complete, resume with:"
echo "  /sdk-bridge:resume"
echo ""
echo "To cancel:"
echo "  /sdk-bridge:cancel"
echo ""

exit 0
