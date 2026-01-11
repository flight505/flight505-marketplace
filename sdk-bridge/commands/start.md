---
description: "Start autonomous development with guided setup"
argument-hint: ""
allowed-tools: ["Bash", "Read", "Write", "AskUserQuestion", "TodoWrite", "Task"]
---

# Start SDK Bridge Autonomous Development

I'll set up and launch SDK Bridge with an interactive guided experience.

## Step 1: Check Prerequisites

Let me verify the environment is ready:

```bash
# Create .claude directory if needed
mkdir -p .claude

# Check harness
if [ ! -f ~/.claude/skills/long-running-agent/harness/hybrid_loop_agent.py ]; then
  echo "❌ ERROR: Harness not installed"
  echo ""
  echo "Install harness first: /sdk-bridge:lra-setup"
  exit 1
fi

# Check venv
VENV_PYTHON="$HOME/.claude/skills/long-running-agent/.venv/bin/python"
if [ ! -f "$VENV_PYTHON" ]; then
  echo "❌ ERROR: SDK virtual environment not found"
  echo "Run /sdk-bridge:lra-setup first"
  exit 1
fi

# Check SDK installed
if ! "$VENV_PYTHON" -c "import claude_agent_sdk" 2>/dev/null; then
  echo "❌ ERROR: claude-agent-sdk not installed"
  echo "Run /sdk-bridge:lra-setup first"
  exit 1
fi

# Check feature list
if [ ! -f "feature_list.json" ]; then
  echo "❌ ERROR: No feature_list.json found"
  echo ""
  echo "Create feature_list.json first with /plan or manually"
  exit 1
fi

# Check git
if ! command -v git &> /dev/null; then
  echo "⚠️  WARNING: git not found (recommended)"
fi

echo "✅ All prerequisites met"
```

## Step 2: Initial Progress Setup

Use TodoWrite to show we're starting:

```
Create initial progress tracker:
- ✅ Prerequisites validated
- ⏳ Configuring setup options
- ⏳ Creating configuration
- ⏳ Validating handoff readiness
- ⏳ Launching autonomous agent
```

## Step 3: Interactive Configuration

Now I'll gather setup preferences using AskUserQuestion.

First, check if execution plan exists to determine if parallel mode is available:

```bash
HAS_PLAN=false
if [ -f ".claude/execution-plan.json" ]; then
  HAS_PLAN=true
fi
```

Use AskUserQuestion to gather preferences:

**Question 1: Model Selection**
```json
{
  "question": "Which Claude model should the agent use?",
  "header": "Model",
  "options": [
    {
      "label": "Sonnet (Recommended)",
      "description": "Fast and capable - handles most development tasks efficiently. Best cost/performance ratio."
    },
    {
      "label": "Opus",
      "description": "Most capable - use for complex refactoring, architecture changes, or when Sonnet struggles."
    }
  ],
  "multiSelect": false
}
```

**Question 2: Parallel Execution** (only if HAS_PLAN=true)
```json
{
  "question": "Enable parallel execution for faster completion?",
  "header": "Execution",
  "options": [
    {
      "label": "Parallel (Recommended)",
      "description": "2-4x faster - launches multiple workers for independent features. Uses git-isolated branches."
    },
    {
      "label": "Sequential",
      "description": "One feature at a time - safer for tightly coupled features or first-time testing."
    }
  ],
  "multiSelect": false
}
```

**Question 3: Advanced Features**
```json
{
  "question": "Which advanced features should be enabled?",
  "header": "Features",
  "options": [
    {
      "label": "Semantic Memory",
      "description": "Cross-project learning - suggests solutions from past successful implementations."
    },
    {
      "label": "Adaptive Models",
      "description": "Smart routing - escalates complex features to Opus automatically."
    },
    {
      "label": "Approval Workflow",
      "description": "Human-in-the-loop - pauses for high-risk operations like DB migrations."
    }
  ],
  "multiSelect": true
}
```

## Step 4: Create Configuration

Based on user answers, create `.claude/sdk-bridge.local.md`:

```bash
# Parse answers
MODEL="claude-sonnet-4-5-20250929"
if [[ "$MODEL_ANSWER" == *"Opus"* ]]; then
  MODEL="claude-opus-4-5-20251101"
fi

ENABLE_PARALLEL="false"
if [[ "$EXECUTION_ANSWER" == *"Parallel"* ]]; then
  ENABLE_PARALLEL="true"
fi

ENABLE_MEMORY="true"
ENABLE_ADAPTIVE="true"
ENABLE_APPROVAL="true"

if [[ ! "$FEATURES_ANSWER" == *"Semantic Memory"* ]]; then
  ENABLE_MEMORY="false"
fi
if [[ ! "$FEATURES_ANSWER" == *"Adaptive Models"* ]]; then
  ENABLE_ADAPTIVE="false"
fi
if [[ ! "$FEATURES_ANSWER" == *"Approval Workflow"* ]]; then
  ENABLE_APPROVAL="false"
fi

# Create configuration file
cat > .claude/sdk-bridge.local.md << EOF
---
# SDK Bridge Configuration
enabled: true
model: $MODEL
max_sessions: 20
reserve_sessions: 2
progress_stall_threshold: 3
auto_handoff_after_plan: false
log_level: INFO
webhook_url:

# v2.0 Advanced Features
enable_v2_features: true
enable_semantic_memory: $ENABLE_MEMORY
enable_adaptive_models: $ENABLE_ADAPTIVE
enable_approval_nodes: $ENABLE_APPROVAL
max_inner_loops: 5

# v2.0 Phase 3: Parallel Execution
enable_parallel_execution: $ENABLE_PARALLEL
max_parallel_workers: 3
---

# SDK Bridge Configuration

Created by /sdk-bridge:start on $(date +"%Y-%m-%d %H:%M:%S")

## Settings

- **Model**: $MODEL
- **Parallel Execution**: $ENABLE_PARALLEL
- **Semantic Memory**: $ENABLE_MEMORY
- **Adaptive Models**: $ENABLE_ADAPTIVE
- **Approval Workflow**: $ENABLE_APPROVAL

See CLAUDE.md for detailed configuration documentation.
EOF

echo "✅ Configuration created"
```

Update TodoWrite:
```
- ✅ Prerequisites validated
- ✅ Setup options configured
- ✅ Configuration created
- ⏳ Validating handoff readiness
- ⏳ Launching autonomous agent
```

## Step 5: Validate Handoff Readiness

Use Task tool to invoke the handoff-validator agent:

```bash
echo "Validating handoff prerequisites..."
```

The validator checks:
1. SDK environment setup
2. Feature list exists
3. API authentication
4. Git repository state
5. Configuration file
6. Harness scripts

If validation fails, report errors and stop.

Update TodoWrite:
```
- ✅ Prerequisites validated
- ✅ Setup options configured
- ✅ Configuration created
- ✅ Handoff validation passed
- ⏳ Launching autonomous agent
```

## Step 6: Launch Autonomous Agent

Read configuration and launch:

```bash
#!/bin/bash
set -euo pipefail

PYTHON="$HOME/.claude/skills/long-running-agent/.venv/bin/python"
PROJECT_DIR="."
LOG_FILE=".claude/sdk-bridge.log"
PID_FILE=".claude/sdk-bridge.pid"

# Read configuration
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' .claude/sdk-bridge.local.md)
MODEL=$(echo "$FRONTMATTER" | grep '^model:' | sed 's/model: *//')
MAX_SESSIONS=$(echo "$FRONTMATTER" | grep '^max_sessions:' | sed 's/max_sessions: *//' || echo "20")
RESERVE_SESSIONS=$(echo "$FRONTMATTER" | grep '^reserve_sessions:' | sed 's/reserve_sessions: *//' || echo "2")
MAX_INNER=$(echo "$FRONTMATTER" | grep '^max_inner_loops:' | sed 's/max_inner_loops: *//' || echo "5")
LOG_LEVEL=$(echo "$FRONTMATTER" | grep '^log_level:' | sed 's/log_level: *//' || echo "INFO")
ENABLE_MEMORY=$(echo "$FRONTMATTER" | grep '^enable_semantic_memory:' | sed 's/enable_semantic_memory: *//' || echo "true")
ENABLE_PARALLEL=$(echo "$FRONTMATTER" | grep '^enable_parallel_execution:' | sed 's/enable_parallel_execution: *//' || echo "false")
MAX_WORKERS=$(echo "$FRONTMATTER" | grep '^max_parallel_workers:' | sed 's/max_parallel_workers: *//' || echo "3")

MAX_ITERATIONS=$((MAX_SESSIONS - RESERVE_SESSIONS))

# Determine execution mode
EXECUTION_MODE="sequential"
HARNESS="$HOME/.claude/skills/long-running-agent/harness/hybrid_loop_agent.py"

if [ "$ENABLE_PARALLEL" = "true" ] && [ -f ".claude/execution-plan.json" ]; then
  EXECUTION_MODE="parallel"
  HARNESS="$HOME/.claude/skills/long-running-agent/harness/parallel_coordinator.py"
fi

# Create handoff context
cat > .claude/handoff-context.json << EOF
{
  "version": "2.0.0",
  "handoff_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "mode": "$EXECUTION_MODE",
  "model": "$MODEL",
  "max_sessions": $MAX_SESSIONS,
  "features": {
    "semantic_memory": $ENABLE_MEMORY,
    "adaptive_models": $(echo "$FRONTMATTER" | grep '^enable_adaptive_models:' | sed 's/enable_adaptive_models: *//'),
    "parallel_execution": $ENABLE_PARALLEL
  },
  "session_count": 0,
  "status": "running"
}
EOF

# Build command
if [ "$EXECUTION_MODE" = "parallel" ]; then
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
if ! ps -p $PID > /dev/null 2>&1; then
  echo "❌ Failed to launch SDK Bridge"
  echo "Check $LOG_FILE for details"
  exit 1
fi

# Count features
FEATURE_COUNT=$(jq 'length' feature_list.json)

# Estimate time
if [ "$EXECUTION_MODE" = "parallel" ]; then
  ESTIMATED_MIN=$((FEATURE_COUNT * 15 / MAX_WORKERS))
else
  ESTIMATED_MIN=$((FEATURE_COUNT * 15))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 SDK Bridge Launched Successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Configuration:"
echo "  Mode: $EXECUTION_MODE"
if [ "$EXECUTION_MODE" = "parallel" ]; then
  echo "  Workers: $MAX_WORKERS"
  echo "  Speedup: ~${MAX_WORKERS}x faster"
fi
echo "  Model: $MODEL"
echo "  Features: $FEATURE_COUNT"
echo ""
echo "Progress:"
echo "  PID: $PID"
echo "  Log file: $LOG_FILE"
echo "  Estimated time: ~$ESTIMATED_MIN minutes"
echo ""
echo "Next Steps:"
echo "  • Check progress: /sdk-bridge:watch"
echo "  • View logs: tail -f $LOG_FILE"
echo "  • Check status: /sdk-bridge:status"
echo "  • Cancel: /sdk-bridge:cancel"
echo ""
echo "I'll notify you when complete (SessionStart hook)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
```

## Step 7: Final Progress Update

Update TodoWrite to show completion:

```
- ✅ Prerequisites validated
- ✅ Setup options configured
- ✅ Configuration created
- ✅ Handoff validation passed
- ✅ Agent launched (PID: 12345)
```

Show summary with features enabled, execution mode, estimated completion time, and next steps.
