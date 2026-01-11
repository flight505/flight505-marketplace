---
description: "Review completed SDK agent work with detailed analysis"
argument-hint: ""
allowed-tools: ["Bash", "Read"]
---

# Resume and Review SDK Agent Work

I'll provide a comprehensive review of the SDK agent's work with detailed analysis.

## Part 1: Executive Summary

```bash
if [ ! -f ".claude/sdk_complete.json" ]; then
  echo "❌ SDK agent has not completed yet"
  echo ""
  echo "Current options:"
  echo "  • Check progress: /sdk-bridge:watch"
  echo "  • View status: /sdk-bridge:status"
  echo "  • View logs: tail -f .claude/sdk-bridge.log"
  echo ""
  exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 SDK BRIDGE COMPLETION REPORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Parse completion data
REASON=$(jq -r '.reason // "unknown"' .claude/sdk_complete.json)
SESSIONS=$(jq -r '.session_count // 0' .claude/sdk_complete.json)
END_TIME=$(jq -r '.completion_time // ""' .claude/sdk_complete.json)

# Parse handoff context
if [ -f ".claude/handoff-context.json" ]; then
  START_TIME=$(jq -r '.handoff_time // ""' .claude/handoff-context.json)
  MODE=$(jq -r '.mode // "sequential"' .claude/handoff-context.json)
  MODEL=$(jq -r '.model // "unknown"' .claude/handoff-context.json)
  PARALLEL=$(jq -r '.features.parallel_execution // false' .claude/handoff-context.json)
fi

# Calculate duration if times available
if [ -n "$START_TIME" ] && [ -n "$END_TIME" ]; then
  START_TS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$START_TIME" "+%s" 2>/dev/null || echo 0)
  END_TS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$END_TIME" "+%s" 2>/dev/null || echo 0)
  if [ "$START_TS" -gt 0 ] && [ "$END_TS" -gt 0 ]; then
    DURATION_SEC=$((END_TS - START_TS))
    DURATION_MIN=$((DURATION_SEC / 60))
  fi
fi

# Feature progress
FEATURES_TOTAL=$(jq 'length' feature_list.json 2>/dev/null || echo 0)
FEATURES_PASSING=$(jq '[.[] | select(.passes==true)] | length' feature_list.json 2>/dev/null || echo 0)
FEATURES_REMAINING=$((FEATURES_TOTAL - FEATURES_PASSING))
COMPLETION_PCT=$((FEATURES_TOTAL > 0 ? FEATURES_PASSING * 100 / FEATURES_TOTAL : 0))

# Display summary
echo "✅ Status: Completed"
echo "📝 Reason: $REASON"
echo "🔄 Sessions: $SESSIONS"
if [ -n "$DURATION_MIN" ]; then
  echo "⏱️  Duration: $DURATION_MIN minutes"
fi
echo "🤖 Model: ${MODEL##*/}"  # Show just model name, not full path
echo "🚀 Mode: $MODE"
echo ""

# Feature progress bar
echo "Feature Progress: $FEATURES_PASSING / $FEATURES_TOTAL (${COMPLETION_PCT}%)"
FILLED=$((COMPLETION_PCT / 5))
EMPTY=$((20 - FILLED))
printf "["
for i in $(seq 1 $FILLED 2>/dev/null); do printf "████"; done
for i in $(seq 1 $EMPTY 2>/dev/null); do printf "░░░░"; done
printf "] ${COMPLETION_PCT}%%\n"
echo ""

# Speedup estimate for parallel mode
if [ "$MODE" = "parallel" ] && [ -n "$DURATION_MIN" ]; then
  SEQUENTIAL_EST=$((FEATURES_TOTAL * 15))
  if [ "$DURATION_MIN" -lt "$SEQUENTIAL_EST" ]; then
    SPEEDUP=$((SEQUENTIAL_EST / DURATION_MIN))
    SAVED=$((SEQUENTIAL_EST - DURATION_MIN))
    echo "⚡ Parallel Speedup: ~${SPEEDUP}x faster (saved ~$SAVED minutes)"
    echo ""
  fi
fi
```

## Part 2: Feature-by-Feature Breakdown

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 FEATURE BREAKDOWN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

jq -r '.[] | "\(.id)\t\(.passes)\t\(.description // "No description")"' feature_list.json | while IFS=$'\t' read -r ID PASSES DESC; do
  if [ "$PASSES" = "true" ]; then
    echo "✅ Feature $ID (PASSING)"
  else
    echo "❌ Feature $ID (NOT PASSING)"
  fi
  echo "   $DESC"
  echo ""
done
```

## Part 3: Deliverable Validation

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 DELIVERABLE FILE VALIDATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Extract all file references from completed features
ALL_FILES=$(jq -r '.[] | select(.passes==true) | .description + " " + (.test // "")' feature_list.json | \
  grep -oE '\b[a-zA-Z0-9_/-]+\.(py|js|ts|jsx|tsx|md|txt|json|yaml|yml|sh|sql|html|css|java|go|rs|cpp|c|h|rb|toml|conf|ini|xml|vue|svelte|php|dart|swift|kt|scala|r|m|mm|cs|fs|ex|exs|erl|hrl|clj|cljs|cljc|edn)\b' 2>/dev/null | \
  sort -u)

if [ -z "$ALL_FILES" ]; then
  echo "ℹ️  No deliverable files detected from feature descriptions"
  echo ""
else
  TOTAL_DELIVERABLES=0
  MISSING_DELIVERABLES=0

  while IFS= read -r file; do
    TOTAL_DELIVERABLES=$((TOTAL_DELIVERABLES + 1))
    if [ -f "$file" ]; then
      echo "  ✅ $file"
    else
      echo "  ❌ $file (MISSING)"
      MISSING_DELIVERABLES=$((MISSING_DELIVERABLES + 1))
    fi
  done <<< "$ALL_FILES"

  echo ""
  if [ "$MISSING_DELIVERABLES" -eq 0 ]; then
    echo "✅ All $TOTAL_DELIVERABLES deliverable files verified"
  else
    echo "⚠️  Warning: $MISSING_DELIVERABLES of $TOTAL_DELIVERABLES deliverable files are missing!"
    echo ""
    echo "Troubleshooting:"
    echo "  • Files may be in different directories than expected"
    echo "  • Check .claude/sdk-bridge.log for file creation details"
    echo "  • Agent may have used different file names"
    echo "  • Some features may not have created files (configuration changes, etc.)"
  fi
  echo ""
fi
```

## Part 4: Git Commits Analysis

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 GIT COMMITS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if ! command -v git &> /dev/null; then
  echo "ℹ️  Git not available"
  echo ""
else
  # Get commit from handoff time
  if [ -f ".claude/handoff-context.json" ]; then
    HANDOFF_COMMIT=$(jq -r '.git_commit // ""' .claude/handoff-context.json 2>/dev/null)
  fi

  if [ -n "$HANDOFF_COMMIT" ]; then
    # Show commits since handoff
    COMMIT_COUNT=$(git log --oneline "$HANDOFF_COMMIT"..HEAD 2>/dev/null | wc -l | tr -d ' ')

    if [ "$COMMIT_COUNT" -gt 0 ]; then
      echo "Commits since handoff ($COMMIT_COUNT total):"
      echo ""
      git log --oneline --decorate "$HANDOFF_COMMIT"..HEAD | while read -r line; do
        HASH=$(echo "$line" | awk '{print $1}')
        MSG=$(echo "$line" | cut -d' ' -f2-)
        FILES=$(git diff-tree --no-commit-id --name-only -r "$HASH" 2>/dev/null | wc -l | tr -d ' ')
        echo "  • $HASH: $MSG ($FILES files)"
      done
      echo ""
    else
      echo "ℹ️  No commits since handoff"
      echo ""
    fi
  else
    # Show recent commits (fallback)
    echo "Recent commits (last 10):"
    echo ""
    git log --oneline --decorate -10 2>/dev/null | while read -r line; do
      HASH=$(echo "$line" | awk '{print $1}')
      MSG=$(echo "$line" | cut -d' ' -f2-)
      FILES=$(git diff-tree --no-commit-id --name-only -r "$HASH" 2>/dev/null | wc -l | tr -d ' ')
      echo "  • $HASH: $MSG ($FILES files)"
    done
    echo ""
  fi
fi
```

## Part 5: Next Steps and Cleanup

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 NEXT STEPS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$FEATURES_REMAINING" -gt 0 ]; then
  echo "⚠️  Not all features are passing ($FEATURES_REMAINING remaining)"
  echo ""
  echo "Recommended actions:"
  echo "  1. Review .claude/sdk-bridge.log for errors"
  echo "  2. Check individual feature test results"
  echo "  3. Fix issues manually or run /sdk-bridge:start again"
  echo ""
else
  echo "✅ All features are passing!"
  echo ""
  echo "Recommended actions:"
  echo "  1. Review deliverable files above"
  echo "  2. Run tests: npm test / pytest / etc."
  echo "  3. Review git commits for changes"
  echo "  4. Commit and push if satisfied"
  echo ""
fi

echo "Cleanup:"
echo "  • Remove completion signal: rm .claude/sdk_complete.json"
echo "  • Archive logs: mv .claude/sdk-bridge.log .claude/sdk-bridge-$(date +%Y%m%d).log"
echo "  • Keep configuration for future runs"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
```

## Summary Note

```bash
echo "📋 Summary saved to: .claude/completion-report.txt"
# Save summary for future reference
{
  echo "SDK Bridge Completion Report"
  echo "Generated: $(date)"
  echo ""
  echo "Status: Completed"
  echo "Reason: $REASON"
  echo "Sessions: $SESSIONS"
  echo "Features: $FEATURES_PASSING / $FEATURES_TOTAL passing"
  echo "Mode: $MODE"
} > .claude/completion-report.txt

echo "Review complete!"
echo ""
```
