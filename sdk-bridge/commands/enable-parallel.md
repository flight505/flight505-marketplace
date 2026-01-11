---
description: "Enable parallel execution for feature implementation"
argument-hint: ""
allowed-tools: ["Bash", "Read", "Write"]
---

# Enable Parallel Execution

I'll enable parallel execution mode for feature implementation.

## Step 1: Validate Prerequisites

Check that execution plan exists:

```bash
#!/bin/bash
set -euo pipefail

CONFIG_FILE=".claude/sdk-bridge.local.md"
PLAN_FILE=".claude/execution-plan.json"

# Check for execution plan
if [ ! -f "$PLAN_FILE" ]; then
  echo "❌ No execution plan found"
  echo ""
  echo "You must run /sdk-bridge:plan first to analyze dependencies"
  echo "and create an execution plan."
  echo ""
  echo "Steps:"
  echo "  1. Run: /sdk-bridge:plan"
  echo "  2. Review the dependency graph and estimated speedup"
  echo "  3. Run: /sdk-bridge:enable-parallel (this command)"
  exit 1
fi

echo "✅ Found execution plan: $PLAN_FILE"
echo ""

# Check for config file
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Configuration file not found: $CONFIG_FILE"
  echo ""
  echo "Run /sdk-bridge:init first to create configuration."
  exit 1
fi

echo "✅ Found configuration: $CONFIG_FILE"
echo ""
```

## Step 2: Display Plan Summary

Show user what they're enabling:

```bash
# Read plan metadata
TOTAL_FEATURES=$(jq '.metadata.total_features' "$PLAN_FILE")
LEVELS=$(jq '.execution_levels | length' "$PLAN_FILE")
WORKERS=$(jq '.metadata.max_parallel_workers' "$PLAN_FILE")
ESTIMATED_TIME=$(jq '.metadata.estimated_total_minutes' "$PLAN_FILE")

# Calculate sequential time
SEQUENTIAL_TIME=$((TOTAL_FEATURES * 15))

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   PARALLEL EXECUTION PLAN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Features: $TOTAL_FEATURES"
echo "📊 Execution Levels: $LEVELS"
echo "👥 Max Workers: $WORKERS"
echo ""
echo "⏱️  Sequential Time: ~$SEQUENTIAL_TIME minutes"
echo "⚡ Parallel Time: ~$ESTIMATED_TIME minutes"
echo "🚀 Speedup: ~$((SEQUENTIAL_TIME / ESTIMATED_TIME))x faster"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
```

## Step 3: Update Configuration

Enable parallel execution in config:

```bash
# Check if already enabled
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$CONFIG_FILE")
CURRENT_VALUE=$(echo "$FRONTMATTER" | grep '^enable_parallel_execution:' | sed 's/enable_parallel_execution: *//' || echo "false")

if [ "$CURRENT_VALUE" = "true" ]; then
  echo "ℹ️  Parallel execution is already enabled"
  echo ""
  echo "Configuration: $CONFIG_FILE"
  echo "  enable_parallel_execution: true"
  echo "  max_parallel_workers: $(echo "$FRONTMATTER" | grep '^max_parallel_workers:' | sed 's/max_parallel_workers: *//' || echo "3")"
  echo ""
  echo "Ready to run: /sdk-bridge:handoff"
  exit 0
fi

# Update the config file
# Read current content
CONTENT=$(cat "$CONFIG_FILE")

# Replace enable_parallel_execution: false with true
UPDATED_CONTENT=$(echo "$CONTENT" | sed 's/^enable_parallel_execution: false/enable_parallel_execution: true/')

# Write back
echo "$UPDATED_CONTENT" > "$CONFIG_FILE"

echo "✅ Enabled parallel execution"
echo ""
echo "Updated configuration:"
echo "  enable_parallel_execution: true"
echo "  max_parallel_workers: $(echo "$FRONTMATTER" | grep '^max_parallel_workers:' | sed 's/max_parallel_workers: *//' || echo "3")"
echo ""
```

## Step 4: Next Steps

Provide guidance:

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   NEXT STEPS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Launch parallel execution:"
echo "   /sdk-bridge:handoff"
echo ""
echo "   This will start $WORKERS workers executing features in parallel."
echo ""
echo "2. Monitor progress:"
echo "   /sdk-bridge:observe"
echo ""
echo "   Real-time dashboard showing all active workers, branches, and progress."
echo ""
echo "3. Check status:"
echo "   /sdk-bridge:status"
echo ""
echo "   Overall progress across all workers."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Tip: Each worker will create a separate git branch"
echo "   (sdk-bridge/parallel/feat-XXX) and work independently."
echo ""
echo "💡 Tip: You can disable parallel execution by editing"
echo "   $CONFIG_FILE and setting:"
echo "   enable_parallel_execution: false"
echo ""
```

## Notes

- Requires execution plan from `/sdk-bridge:plan`
- Updates `.claude/sdk-bridge.local.md` configuration
- Next handoff will use parallel_coordinator.py instead of hybrid_loop_agent.py
- Each worker gets isolated git branch
- Workers execute features from same execution level concurrently
- Automatic merge coordination when levels complete
