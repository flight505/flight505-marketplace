#!/bin/bash
# Parse and validate state files
# Useful for debugging or scripting

set -euo pipefail

# Default to handoff-context.json if no argument
STATE_FILE="${1:-.claude/handoff-context.json}"

if [ ! -f "$STATE_FILE" ]; then
  echo "Error: State file not found: $STATE_FILE" >&2
  exit 1
fi

# Validate JSON
if ! jq empty "$STATE_FILE" 2>/dev/null; then
  echo "Error: Invalid JSON in $STATE_FILE" >&2
  exit 1
fi

# Parse based on file type
case "$STATE_FILE" in
  *handoff-context.json)
    echo "Handoff Context"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    jq -r '
      "Started: " + .timestamp,
      "Git commit: " + .git_commit,
      "Features: " + (.features_passing | tostring) + " / " + (.features_total | tostring) + " passing",
      "Sessions: " + (.session_count | tostring) + " / " + (.max_sessions | tostring),
      "Model: " + .model,
      (if .pid then "PID: " + (.pid | tostring) else "PID: not set" end),
      (if .status then "Status: " + .status else "" end)
    ' "$STATE_FILE" | grep -v '^$'
    ;;

  *sdk_complete.json)
    echo "Completion Signal"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    jq -r '
      "Completed: " + .timestamp,
      "Reason: " + .reason,
      "Sessions: " + (.session_count | tostring),
      "Exit code: " + (.exit_code | tostring),
      (if .features_completed then "Features completed: " + (.features_completed | tostring) else "" end),
      (if .features_remaining then "Features remaining: " + (.features_remaining | tostring) else "" end),
      (if .message then "Message: " + .message else "" end),
      (if .final_commit then "Final commit: " + .final_commit else "" end)
    ' "$STATE_FILE" | grep -v '^$'
    ;;

  *feature_list.json)
    echo "Feature List"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    TOTAL=$(jq 'length' "$STATE_FILE")
    PASSING=$(jq '[.[] | select(.passes==true)] | length' "$STATE_FILE")
    REMAINING=$((TOTAL - PASSING))

    # Avoid division by zero
    if [ "$TOTAL" -gt 0 ]; then
      PCT=$((PASSING * 100 / TOTAL))
    else
      PCT=0
    fi

    echo "Total features: $TOTAL"
    echo "Passing: $PASSING ($PCT%)"
    echo "Remaining: $REMAINING"
    echo ""
    echo "Next features to implement:"
    jq -r '.[] | select(.passes==false) | "  • " + .description' "$STATE_FILE" | head -5

    if [ "$REMAINING" -gt 5 ]; then
      echo "  ... and $((REMAINING - 5)) more"
    fi
    ;;

  *)
    # Generic JSON parsing
    echo "State File: $STATE_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    jq '.' "$STATE_FILE"
    ;;
esac

exit 0
