---
description: "Watch SDK agent progress with live updates in chat"
argument-hint: "[duration]"
allowed-tools: ["Bash", "Read", "TodoWrite"]
---

# Watch SDK Agent Progress

I'll monitor the SDK agent's progress and provide live updates in the chat.

## Check if Agent is Running

```bash
if [ ! -f ".claude/sdk-bridge.pid" ]; then
  echo "❌ No SDK agent is currently running"
  echo ""
  echo "Start one with: /sdk-bridge:start"
  exit 0
fi

PID=$(cat .claude/sdk-bridge.pid)
if ! ps -p $PID > /dev/null 2>&1; then
  echo "⚠️  SDK agent process has stopped (PID file is stale)"
  echo ""
  echo "Check completion status: /sdk-bridge:resume"
  exit 0
fi

echo "✅ SDK agent is running (PID: $PID)"
echo ""
```

## Initialize Progress Tracker

Parse `feature_list.json` and create initial TodoWrite:

```bash
# Count features
FEATURES_TOTAL=$(jq 'length' feature_list.json 2>/dev/null || echo 0)
FEATURES_PASSING=$(jq '[.[] | select(.passes==true)] | length' feature_list.json 2>/dev/null || echo 0)

echo "Creating live progress tracker for $FEATURES_TOTAL features..."
echo ""
```

Use TodoWrite to create todos for all features:

```json
{
  "todos": [
    // For each feature in feature_list.json:
    // If passes == true: {"content": "Feature N: description", "status": "completed", "activeForm": "Completed feature N"}
    // If passes == false: {"content": "Feature N: description", "status": "pending", "activeForm": "Working on feature N"}
  ]
}
```

## Poll Progress Loop

Monitor for 30 seconds (10 iterations × 3 seconds):

```bash
ITERATIONS=10
POLL_INTERVAL=3

for i in $(seq 1 $ITERATIONS); do
  # Read current state
  FEATURES_PASSING_NOW=$(jq '[.[] | select(.passes==true)] | length' feature_list.json 2>/dev/null || echo 0)
  FEATURES_REMAINING=$((FEATURES_TOTAL - FEATURES_PASSING_NOW))
  COMPLETION_PCT=$((FEATURES_TOTAL > 0 ? FEATURES_PASSING_NOW * 100 / FEATURES_TOTAL : 0))

  # Check if progress changed
  if [ "$FEATURES_PASSING_NOW" -ne "$FEATURES_PASSING" ]; then
    echo "Progress update: $FEATURES_PASSING_NOW / $FEATURES_TOTAL passing (${COMPLETION_PCT}%)"
    FEATURES_PASSING=$FEATURES_PASSING_NOW

    # Update TodoWrite with new status
    # Parse feature_list.json and update todos
  fi

  # Try to determine current feature from log
  if [ -f ".claude/sdk-bridge.log" ]; then
    CURRENT_FEATURE=$(tail -20 .claude/sdk-bridge.log | grep -o "feat-[0-9]*" | tail -1 || echo "")
  fi

  # Wait before next poll
  if [ $i -lt $ITERATIONS ]; then
    sleep $POLL_INTERVAL
  fi
done
```

## Final Status Update

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Current Progress: $FEATURES_PASSING / $FEATURES_TOTAL passing (${COMPLETION_PCT}%)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show progress bar
FILLED=$((COMPLETION_PCT / 5))
EMPTY=$((20 - FILLED))
printf "["
for i in $(seq 1 $FILLED 2>/dev/null); do printf "████"; done
for i in $(seq 1 $EMPTY 2>/dev/null); do printf "░░░░"; done
printf "] ${COMPLETION_PCT}%%\n"
echo ""

# Check if completed
if [ -f ".claude/sdk_complete.json" ]; then
  echo "🎉 Agent completed while watching!"
  echo ""
  echo "Review work: /sdk-bridge:resume"
elif [ "$FEATURES_REMAINING" -gt 0 ]; then
  echo "Still working on $FEATURES_REMAINING features"
  echo ""
  echo "Continue watching: /sdk-bridge:watch"
  echo "Check detailed status: /sdk-bridge:status"
  echo "View live logs: tail -f .claude/sdk-bridge.log"
else
  echo "All features appear complete, waiting for agent to finish..."
  echo ""
  echo "Monitor: /sdk-bridge:watch"
fi

echo ""
```

## Implementation Note

Since we're polling, update TodoWrite every time we detect progress:

```javascript
// Pseudocode for TodoWrite updates in polling loop:

function updateTodoWrite() {
  const features = JSON.parse(fs.readFileSync('feature_list.json'));
  const todos = features.map(f => ({
    content: `${f.id}: ${f.description}`,
    status: f.passes ? 'completed' : 'pending',
    activeForm: f.passes ? `Completed ${f.id}` : `Working on ${f.id}`
  }));

  // Add current working feature as "in_progress" if detected
  if (currentFeature) {
    const idx = todos.findIndex(t => t.content.startsWith(currentFeature));
    if (idx >= 0 && todos[idx].status === 'pending') {
      todos[idx].status = 'in_progress';
    }
  }

  // Call TodoWrite tool with updated todos
}
```

This provides a simulated "live" experience by polling every 3 seconds for 30 seconds.
