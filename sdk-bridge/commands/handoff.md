---
description: "Hand off to SDK Bridge autonomous agent"
argument-hint: "[project-dir]"
allowed-tools: ["Bash", "Read", "Write", "Task", "TodoWrite", "AskUserQuestion"]
---

# Hand Off to SDK Bridge

I'll hand off feature implementation to the SDK Bridge autonomous agent with:
- **Hybrid Loops**: Same-session self-healing + multi-session progression
- **Semantic Memory**: Cross-project learning from past implementations
- **Adaptive Intelligence**: Smart retry strategies and model selection

## Prerequisites Check

Before handoff, run the handoff validator to ensure all prerequisites are met.

Use the Task tool to invoke the `handoff-validator` agent.

The validator will check:
1. ✅ SDK virtual environment exists and claude-agent-sdk is installed
2. ✅ Project has `feature_list.json`
3. ✅ API authentication is configured (CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY)
4. ✅ Git repository is clean or has only intended changes
5. ✅ Configuration file exists (`.claude/sdk-bridge.local.md`)
6. ✅ Harness scripts installed

## Configuration

Ensure `.claude/sdk-bridge.local.md` has proper settings:

```yaml
---
enabled: true
model: claude-sonnet-4-5-20250929
max_sessions: 20
reserve_sessions: 2
progress_stall_threshold: 3
log_level: INFO
webhook_url: https://example.com/webhook  # optional

# Advanced features
enable_v2_features: true
enable_semantic_memory: true
enable_adaptive_models: true
enable_approval_nodes: true
max_inner_loops: 5  # Same-session retries
---
```

If settings are missing, ask the user if they want to enable advanced features.

## Handoff Process

### Step 1: Validate Prerequisites

Use Task tool to invoke the handoff-validator agent:

```bash
# The agent will perform comprehensive validation
```

If validation fails, stop and report errors to user.

### Step 2: Create Handoff Context

Create `.claude/handoff-context.json` with metadata:

```bash
cat > .claude/handoff-context.json << 'EOF'
{
  "version": "2.0.0",
  "handoff_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "mode": "hybrid_loops",
  "features": {
    "semantic_memory": true,
    "adaptive_retry": true,
    "parallel_execution": false
  },
  "session_count": 0,
  "status": "running"
}
EOF
```

### Step 3: Launch Autonomous Agent

Use Bash tool to launch the agent in background:

```bash
#!/bin/bash
set -euo pipefail

PYTHON="$HOME/.claude/skills/long-running-agent/.venv/bin/python"
PROJECT_DIR="${1:-.}"
LOG_FILE=".claude/sdk-bridge.log"
PID_FILE=".claude/sdk-bridge.pid"

# Read configuration
if [ -f ".claude/sdk-bridge.local.md" ]; then
  FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' .claude/sdk-bridge.local.md)
  MODEL=$(echo "$FRONTMATTER" | grep '^model:' | sed 's/model: *//' || echo "claude-sonnet-4-5-20250929")
  MAX_SESSIONS=$(echo "$FRONTMATTER" | grep '^max_sessions:' | sed 's/max_sessions: *//' || echo "20")
  RESERVE_SESSIONS=$(echo "$FRONTMATTER" | grep '^reserve_sessions:' | sed 's/reserve_sessions: *//' || echo "2")
  MAX_INNER=$(echo "$FRONTMATTER" | grep '^max_inner_loops:' | sed 's/max_inner_loops: *//' || echo "5")
  LOG_LEVEL=$(echo "$FRONTMATTER" | grep '^log_level:' | sed 's/log_level: *//' || echo "INFO")
  ENABLE_MEMORY=$(echo "$FRONTMATTER" | grep '^enable_semantic_memory:' | sed 's/enable_semantic_memory: *//' || echo "true")
  ENABLE_PARALLEL=$(echo "$FRONTMATTER" | grep '^enable_parallel_execution:' | sed 's/enable_parallel_execution: *//' || echo "false")
  MAX_WORKERS=$(echo "$FRONTMATTER" | grep '^max_parallel_workers:' | sed 's/max_parallel_workers: *//' || echo "3")
fi

# Calculate max iterations
MAX_ITERATIONS=$((MAX_SESSIONS - RESERVE_SESSIONS))

# Determine execution mode
EXECUTION_MODE="sequential"
HARNESS="$HOME/.claude/skills/long-running-agent/harness/hybrid_loop_agent.py"

if [ "$ENABLE_PARALLEL" = "true" ]; then
  # Check for execution plan
  if [ -f ".claude/execution-plan.json" ]; then
    EXECUTION_MODE="parallel"
    HARNESS="$HOME/.claude/skills/long-running-agent/harness/parallel_coordinator.py"
    echo "🚀 Parallel execution mode enabled"
    echo "   Workers: $MAX_WORKERS"
    echo "   Execution plan: .claude/execution-plan.json"
    echo ""
  else
    echo "⚠️  Warning: enable_parallel_execution is true but no execution plan found"
    echo "   Falling back to sequential execution with hybrid loops"
    echo "   To use parallel execution:"
    echo "   1. Run: /sdk-bridge:plan"
    echo "   2. Run: /sdk-bridge:handoff"
    echo ""
  fi
fi

# Build command based on execution mode
if [ "$EXECUTION_MODE" = "parallel" ]; then
  # Parallel coordinator command
  CMD="$PYTHON $HARNESS \
    --project-dir $PROJECT_DIR \
    --model $MODEL \
    --max-workers $MAX_WORKERS \
    --max-sessions $MAX_SESSIONS \
    --execution-plan .claude/execution-plan.json \
    --log-level $LOG_LEVEL"

  if [ "$ENABLE_MEMORY" = "false" ]; then
    CMD="$CMD --disable-semantic-memory"
  fi
else
  # Sequential hybrid loop command
  CMD="$PYTHON $HARNESS \
    --project-dir $PROJECT_DIR \
    --model $MODEL \
    --max-iterations $MAX_ITERATIONS \
    --max-inner-loops $MAX_INNER \
    --log-level $LOG_LEVEL"

  if [ "$ENABLE_MEMORY" = "false" ]; then
    CMD="$CMD --disable-semantic-memory"
  fi
fi

# Launch in background
nohup $CMD > "$LOG_FILE" 2>&1 &
PID=$!
echo $PID > "$PID_FILE"

# Verify process started
sleep 2
if ps -p $PID > /dev/null 2>&1; then
  echo "✅ SDK Bridge launched (PID: $PID)"
  echo "   Mode: $EXECUTION_MODE"
  if [ "$EXECUTION_MODE" = "parallel" ]; then
    echo "   Workers: $MAX_WORKERS"
  fi
  echo "📝 Logs: $LOG_FILE"
  echo ""
else
  echo "❌ Failed to launch SDK Bridge"
  echo "Check $LOG_FILE for details"
  exit 1
fi
```

### Step 4: Confirm Handoff

Display success message to user:

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Handoff to SDK Bridge Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$EXECUTION_MODE" = "parallel" ]; then
  echo "✨ Parallel Execution Mode:"
  echo "  • $MAX_WORKERS workers executing features concurrently"
  echo "  • Git-isolated branches per worker"
  echo "  • Dependency-aware execution levels"
  echo "  • Automatic merge coordination"
  echo ""
  echo "✨ Advanced Features (per worker):"
else
  echo "✨ Active Features:"
fi

echo "  • Hybrid Loops: Same-session self-healing + multi-session progression"
echo "  • Semantic Memory: Learning from past implementations"
echo "  • Adaptive Intelligence: Smart retry strategies"
echo "  • Model Selection: Automatic Sonnet/Opus routing"
echo ""
echo "📊 Configuration:"
echo "  Model: $MODEL"
echo "  Max Sessions: $MAX_SESSIONS"

if [ "$EXECUTION_MODE" = "parallel" ]; then
  echo "  Workers: $MAX_WORKERS"
  echo "  Mode: Parallel execution"
else
  echo "  Inner Loops: $MAX_INNER (per session)"
  echo "  Mode: Sequential execution"
fi

echo "  Semantic Memory: $([ "$ENABLE_MEMORY" = "true" ] && echo "Enabled" || echo "Disabled")"
echo ""
echo "What Happens Now:"

if [ "$EXECUTION_MODE" = "parallel" ]; then
  echo "  • Multiple workers execute independent features simultaneously"
  echo "  • Each worker creates isolated git branch"
  echo "  • Features within same dependency level run in parallel"
  echo "  • Coordinator merges completed branches"
  echo "  • Learns from past implementations via semantic memory"
  echo "  • Requests approval for high-risk changes"
else
  echo "  • Agent works through features in feature_list.json"
  echo "  • Creates git commits after each successful feature"
  echo "  • Learns from past implementations via semantic memory"
  echo "  • Adapts retry strategy based on feature complexity"
  echo "  • Requests approval for high-risk changes"
fi

echo ""
echo "You Can:"
echo "  • Close this terminal - agent continues independently"

if [ "$EXECUTION_MODE" = "parallel" ]; then
  echo "  • Monitor workers: /sdk-bridge:observe"
else
  echo "  • Monitor progress: /sdk-bridge:status"
fi

echo "  • View live logs: tail -f .claude/sdk-bridge.log"
echo "  • Approve requests: /sdk-bridge:approve"
echo "  • Cancel if needed: /sdk-bridge:cancel"
echo "  • Resume when done: /sdk-bridge:resume"
echo ""
echo "The SDK agent is now running autonomously in the background."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
```

## Error Handling

If any step fails:
1. Log error details to `.claude/sdk-bridge.log`
2. Report to user with specific failure reason
3. Suggest remediation steps
4. Do NOT launch the agent if prerequisites fail

**Common Issues**:

- **Harness not found**: Run `/sdk-bridge:lra-setup` to install
- **Configuration missing**: Run `/sdk-bridge:init` to create config
- **feature_list.json missing**: Create feature list first
- **Git not clean**: Commit or stash changes before handoff
- **SDK not installed**: Check `.venv` exists with claude-agent-sdk

## Notes

- All advanced features enabled by default
- Semantic memory learns across projects
- Agent runs until completion or max sessions
- Logs everything for transparency
- User can monitor in real-time

## Implementation

Execute the steps above using appropriate tools:
- **Task**: For invoking handoff-validator agent
- **Bash**: For running scripts and launching agent
- **Read**: For reading configuration files
- **Write**: For creating handoff context
- **AskUserQuestion**: If configuration is incomplete
- **TodoWrite**: For tracking handoff progress
