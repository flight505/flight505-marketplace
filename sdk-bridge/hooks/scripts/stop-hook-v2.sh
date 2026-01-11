#!/bin/bash
set -euo pipefail

# Stop Hook v2 - Hybrid Loop Validation
#
# This hook enables Ralph-style same-session self-healing loops.
# When enabled, it intercepts Stop events and checks if the current
# feature implementation should retry in the same session.
#
# Flow:
# 1. Check if v2 features are enabled
# 2. If enabled, validate current feature implementation
# 3. If validation fails and can self-heal, prevent exit and prompt retry
# 4. If validation succeeds or can't self-heal, allow normal exit

CONFIG_FILE=".claude/sdk-bridge.local.md"
CHECKPOINT_FILE=".claude/checkpoint-v2.json"

# Check if v2 features enabled
if [ ! -f "$CONFIG_FILE" ]; then
  # No config - allow normal exit
  exit 0
fi

# Parse YAML frontmatter
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$CONFIG_FILE" 2>/dev/null || echo "")

ENABLE_V2=$(echo "$FRONTMATTER" | grep '^enable_v2_features:' | sed 's/enable_v2_features: *//' | tr -d ' ' || echo "false")

if [ "$ENABLE_V2" != "true" ]; then
  # v2 disabled - allow normal exit
  exit 0
fi

# Check if we're in a hybrid loop session
if [ ! -f "$CHECKPOINT_FILE" ]; then
  # No checkpoint - not in hybrid loop, allow exit
  exit 0
fi

# Read checkpoint to get current attempt count
ATTEMPT=$(jq -r '.attempt // 0' "$CHECKPOINT_FILE" 2>/dev/null || echo "0")
SESSION=$(jq -r '.session_num // 0' "$CHECKPOINT_FILE" 2>/dev/null || echo "0")
MAX_INNER_LOOPS=$(echo "$FRONTMATTER" | grep '^max_inner_loops:' | sed 's/max_inner_loops: *//' || echo "5")

# Check if we've exhausted inner loops
if [ "$ATTEMPT" -ge "$MAX_INNER_LOOPS" ]; then
  # Inner loops exhausted - allow exit to start new session
  echo "ℹ️  Inner loops exhausted ($ATTEMPT/$MAX_INNER_LOOPS), proceeding to next session"
  exit 0
fi

# Check validation status from checkpoint
CAN_SELF_HEAL=$(jq -r '.validation_errors | length > 0' "$CHECKPOINT_FILE" 2>/dev/null || echo "false")

if [ "$CAN_SELF_HEAL" = "true" ]; then
  # Validation failed but can self-heal - this would trigger retry
  # For now, we allow the exit as retry logic is handled by hybrid_loop_agent.py
  echo "ℹ️  Hybrid loop validation: attempt $((ATTEMPT + 1))/$MAX_INNER_LOOPS"
  exit 0
else
  # Validation succeeded or can't self-heal - allow normal exit
  exit 0
fi

# Note: The actual retry logic is handled by hybrid_loop_agent.py
# This hook provides monitoring and configuration support
