---
description: "Analyze features and create parallel execution plan with dependency graph"
argument-hint: "[feature-list.json]"
allowed-tools: ["Bash", "Read", "Write", "AskUserQuestion"]
---

# SDK Bridge Plan - Parallel Execution Planning

Analyze features for dependencies and create optimized parallel execution plan with automatic detection of implicit dependencies.

## Step 1: Validate Prerequisites

Check that feature list exists:

```bash
FEATURE_LIST="${1:-feature_list.json}"

if [ ! -f "$FEATURE_LIST" ]; then
  echo "❌ Feature list not found: $FEATURE_LIST"
  echo ""
  echo "Create a feature_list.json file with features to implement."
  echo "Use /project-planner or manually create the file."
  exit 1
fi

echo "✅ Found feature list: $FEATURE_LIST"
echo ""
```

## Step 2: Analyze Dependencies

Use Python to build dependency graph and create execution plan:

```bash
#!/bin/bash
set -euo pipefail

HARNESS_DIR="$HOME/.claude/skills/long-running-agent/harness"
FEATURE_LIST="${1:-feature_list.json}"

python3 -c "
import sys
import json
sys.path.append('$HARNESS_DIR')

from dependency_graph import build_graph_from_feature_list

# Build graph
graph = build_graph_from_feature_list('$FEATURE_LIST')

# Print ASCII visualization
print(graph.visualize_ascii())

# Create execution plan
plan = graph.create_execution_plan(max_parallel_workers=3)

print('\nExecution Plan:')
print('=' * 60)
print(f'Total Features: {plan.total_features}')
print(f'Max Parallel Workers: {plan.max_parallel_workers}')
print(f'Estimated Duration: {plan.estimated_total_minutes} minutes')
print(f'Critical Path: {\" → \".join(plan.critical_path)}')
print()

for level in plan.levels:
    print(f'Level {level.level}: {len(level.features)} feature(s), parallelism={level.max_parallelism}')
    for feat_id in level.features:
        desc = graph.nodes[feat_id].description
        deps = graph.nodes[feat_id].dependencies
        deps_str = f' (depends on: {', '.join(deps)})' if deps else ''
        print(f'  • [{feat_id}] {desc}{deps_str}')
    print()

# Export to feature-graph.json
graph_data = graph.to_json()

import os
os.makedirs('.claude', exist_ok=True)
with open('.claude/feature-graph.json', 'w') as f:
    json.dump(graph_data, f, indent=2)

print('✅ Saved dependency graph to .claude/feature-graph.json')

# Export execution plan
plan_data = {
    'version': '2.0.0',
    'created_at': __import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(),
    'strategy': 'parallel_with_approval',
    'execution_levels': [
        {
            'level': level.level,
            'features': level.features,
            'parallelism': level.max_parallelism,
            'estimated_duration_minutes': level.estimated_duration_minutes
        }
        for level in plan.levels
    ],
    'metadata': {
        'total_features': plan.total_features,
        'max_parallel_workers': plan.max_parallel_workers,
        'estimated_total_minutes': plan.estimated_total_minutes,
        'critical_path': plan.critical_path
    }
}

with open('.claude/execution-plan.json', 'w') as f:
    json.dump(plan_data, f, indent=2)

print('✅ Saved execution plan to .claude/execution-plan.json')
"
```

## Step 3: Display Summary

Show key insights to user:

```bash
# Read execution plan
TOTAL=$(jq '.metadata.total_features' .claude/execution-plan.json)
LEVELS=$(jq '.execution_levels | length' .claude/execution-plan.json)
DURATION=$(jq '.metadata.estimated_total_minutes' .claude/execution-plan.json)
WORKERS=$(jq '.metadata.max_parallel_workers' .claude/execution-plan.json)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   PARALLEL EXECUTION PLAN SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Statistics:"
echo "   Total Features: $TOTAL"
echo "   Execution Levels: $LEVELS"
echo "   Max Workers: $WORKERS"
echo "   Estimated Time: $DURATION minutes"
echo ""

# Calculate speedup vs sequential
SEQUENTIAL_TIME=$((TOTAL * 15))
SPEEDUP=$(echo "scale=1; $SEQUENTIAL_TIME / $DURATION" | bc)

echo "⚡ Performance:"
echo "   Sequential: $SEQUENTIAL_TIME minutes"
echo "   Parallel: $DURATION minutes"
echo "   Speedup: ${SPEEDUP}x faster"
echo ""

# Show critical path
CRITICAL_PATH=$(jq -r '.metadata.critical_path | join(" → ")' .claude/execution-plan.json)
echo "🎯 Critical Path:"
echo "   $CRITICAL_PATH"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if parallel execution should be enabled
if [ "$LEVELS" -gt 1 ] && [ "$TOTAL" -gt 3 ]; then
  echo "💡 Recommendation: Enable parallel execution"
  echo ""
  echo "   Your feature set has $LEVELS independent levels."
  echo "   Parallel execution could save ~$((SEQUENTIAL_TIME - DURATION)) minutes."
  echo ""
  echo "   To enable parallel execution:"
  echo "   1. Edit .claude/sdk-bridge.local.md"
  echo "   2. Set: enable_parallel_execution: true"
  echo "   3. Run: /sdk-bridge:handoff"
else
  echo "💡 Recommendation: Sequential execution is fine"
  echo ""
  echo "   Your features have many dependencies or are few in number."
  echo "   Sequential execution will be simpler and safer."
  echo ""
  echo "   To proceed:"
  echo "   Run: /sdk-bridge:handoff"
fi

echo ""
```

## Step 4: Offer Configuration Update

Ask user if they want to enable parallel execution:

```bash
# Check current config
if [ -f ".claude/sdk-bridge.local.md" ]; then
  FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' .claude/sdk-bridge.local.md)
  PARALLEL_ENABLED=$(echo "$FRONTMATTER" | grep '^enable_parallel_execution:' | sed 's/enable_parallel_execution: *//' || echo "false")

  if [ "$PARALLEL_ENABLED" = "false" ] && [ "$LEVELS" -gt 1 ]; then
    echo "Would you like to enable parallel execution now?"
    echo ""
    echo "  /sdk-bridge:enable-parallel"
    echo ""
    echo "Or manually edit .claude/sdk-bridge.local.md and set:"
    echo "  enable_parallel_execution: true"
    echo "  max_parallel_workers: 3"
  fi
fi
```

## Output

The plan command creates:

1. **`.claude/feature-graph.json`**: Dependency graph with nodes and edges
2. **`.claude/execution-plan.json`**: Parallel execution schedule with levels

### feature-graph.json Structure

```json
{
  "version": "2.0.0",
  "nodes": [
    {
      "id": "feat-001",
      "description": "Setup Express server",
      "tags": ["backend"],
      "priority": 10,
      "dependencies": []
    }
  ],
  "edges": [
    {"from": "feat-001", "to": "feat-002", "type": "requires"}
  ]
}
```

### execution-plan.json Structure

```json
{
  "version": "2.0.0",
  "execution_levels": [
    {
      "level": 0,
      "features": ["feat-001"],
      "parallelism": 1,
      "estimated_duration_minutes": 15
    },
    {
      "level": 1,
      "features": ["feat-002", "feat-003"],
      "parallelism": 2,
      "estimated_duration_minutes": 15
    }
  ],
  "metadata": {
    "total_features": 3,
    "max_parallel_workers": 3,
    "estimated_total_minutes": 30,
    "critical_path": ["feat-001", "feat-002"]
  }
}
```

## Example Output

```
Dependency Graph:
==================================================

Level 0:
  [feat-001] Set up Express.js server

Level 1:
  [feat-002] Add JWT authentication middleware (depends on: feat-001)
  [feat-004] Add database schema for users (depends on: feat-001)

Level 2:
  [feat-003] Create user registration endpoint (depends on: feat-002, feat-004)
  [feat-005] Implement user profile API (depends on: feat-002)


Execution Plan:
============================================================
Total Features: 5
Max Parallel Workers: 3
Estimated Duration: 45 minutes
Critical Path: feat-001 → feat-002 → feat-003

Level 0: 1 feature(s), parallelism=1
  • [feat-001] Set up Express.js server

Level 1: 2 feature(s), parallelism=2
  • [feat-002] Add JWT authentication middleware (depends on: feat-001)
  • [feat-004] Add database schema for users (depends on: feat-001)

Level 2: 2 feature(s), parallelism=2
  • [feat-003] Create user registration endpoint (depends on: feat-002, feat-004)
  • [feat-005] Implement user profile API (depends on: feat-002)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   PARALLEL EXECUTION PLAN SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Statistics:
   Total Features: 5
   Execution Levels: 3
   Max Workers: 3
   Estimated Time: 45 minutes

⚡ Performance:
   Sequential: 75 minutes
   Parallel: 45 minutes
   Speedup: 1.7x faster

🎯 Critical Path:
   feat-001 → feat-002 → feat-003

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💡 Recommendation: Enable parallel execution

   Your feature set has 3 independent levels.
   Parallel execution could save ~30 minutes.

   To enable parallel execution:
   1. Edit .claude/sdk-bridge.local.md
   2. Set: enable_parallel_execution: true
   3. Run: /sdk-bridge:handoff
```

## Notes

- Automatically detects implicit dependencies (e.g., auth before protected endpoints)
- Calculates critical path to identify bottlenecks
- Estimates time savings from parallelization
- Safe: Falls back to sequential if dependencies are complex
- Compatible with v1.x feature lists (backward compatible)
